-- UIF_Base - the skinning primitives. THE one background implementation
-- and the widget skinners every module builds on.
-- Part of ZacUI; load order is set by the TOC.

local ADDON_NAME, ns = ...

-- shared state from earlier ZacUI files
local Col = ns.Col
local FLAT = ns.FLAT
local Modules = ns.Modules
local SharpenIcon = ns.SharpenIcon
local TEX_ARROW = ns.TEX_ARROW
local TEX_ARROWL = ns.TEX_ARROWL
local TEX_NORM = ns.TEX_NORM
local ZUI = ns.ZUI
-- THE LOOK (Core_Look): which art a primitive draws. Every skinner below
-- keeps today's code as its ZacUI branch, byte for byte, and adds the
-- Classic branch beside it; `look` is the optional last argument (a part
-- key, a look table or the explicit "pixel" / "edge"), nil = the
-- Blizzard windows' look.
local Look = ns.Look
local function LookOf(x, part) return Look.Pick(x, part) end

-- ============================================================
-- PRIMITIVES
-- ============================================================
local function KillTexture(tex)
    if tex and tex.SetTexture then
        tex:SetTexture(nil)
        tex:SetAlpha(0)
    end
end

local function HideNamed(base, suffixes)
    for _, sfx in ipairs(suffixes) do
        local t = _G[base .. sfx]
        if t then
            if t.SetAlpha then t:SetAlpha(0) end
            if t.Hide then t:Hide() end
        end
    end
end

local function ClearButtonArt(btn)
    if not btn then return end
    KillTexture(btn.GetNormalTexture    and btn:GetNormalTexture())
    KillTexture(btn.GetPushedTexture    and btn:GetPushedTexture())
    KillTexture(btn.GetDisabledTexture  and btn:GetDisabledTexture())
    KillTexture(btn.GetHighlightTexture and btn:GetHighlightTexture())
    for _, key in ipairs({ "Left", "Middle", "Right",
                           "LeftDisabled", "MiddleDisabled", "RightDisabled" }) do
        local t = btn[key]
        if t and t.SetAlpha then t:SetAlpha(0) end
    end
    local name = btn.GetName and btn:GetName()
    if name then
        HideNamed(name, { "Left", "Middle", "Mid", "Right",
                          "LeftDisabled", "MiddleDisabled", "RightDisabled",
                          "NormalTexture", "PushedTexture", "HighlightTexture" })
    end
end

-- THE one background implementation. SetBackdrop proved unreliable on
-- this client (invisible fills, vanished menus); the explicit texture +
-- pixel border always renders. Same signature as before, so every call
-- site in the addon gains the reliable path at once. Re-calling retints.
-- HANDLES ARE KEPT (frame._zui_borderTex). The border is not only
-- decoration: on item slots it is the only surface left that can carry
-- quality colour once Blizzard's ring is gone, so something has to be
-- able to find these again and retint them.
local function AddPixelBorder(frame, colorKey, alpha, look)
    -- Classic: a Blizzard edge instead of the strips; the four handles are
    -- proxies onto it (Core_Look.AddEdge), so every retint below still
    -- lands. Untinted (white) unless a colour was asked for: the gold is
    -- the art's own.
    local lk = LookOf(look)
    if lk.border.style == "edge" then
        if colorKey then
            local bd = Col(colorKey)
            Look.AddEdge(frame, lk.border, bd.r, bd.g, bd.b, alpha or bd.a or 1)
        else
            Look.AddEdge(frame, lk.border, 1, 1, 1, alpha or 1)
        end
        return
    end
    local bd = Col(colorKey or "border")
    local ba = alpha or bd.a or 1
    local strips = frame._zui_borderTex or {}
    frame._zui_borderTex = strips
    -- a frame outside UIParent (a nameplate's bar, scaled by the camera):
    -- the strips go on a holder that ignores that scale (Core_Pixel), so
    -- they stay one physical pixel as the plate grows and shrinks
    local host = frame
    if ns.Pixel and ns.Pixel.On() and not ns.Pixel.UnderUIParent(frame) then
        host = ns.Pixel.Holder(frame) or frame
    end
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local t = host:CreateTexture(nil, "OVERLAY", nil, 7)
        t._zui_own = true
        strips[#strips + 1] = t
        t:SetColorTexture(bd.r, bd.g, bd.b, ba)
        if side == "TOP" or side == "BOTTOM" then
            t:SetPoint(side .. "LEFT")
            t:SetPoint(side .. "RIGHT")
        else
            t:SetPoint("TOP" .. side)
            t:SetPoint("BOTTOM" .. side)
        end
        -- one PHYSICAL pixel under the ZacUI look (Core_Pixel); exactly
        -- SetHeight(1) / SetWidth(1) everywhere else
        if ns.Pixel then
            ns.Pixel.Edge(t, side, host)
        elseif side == "TOP" or side == "BOTTOM" then
            t:SetHeight(1)
        else
            t:SetWidth(1)
        end
    end
end

-- Retint an existing pixel border. No arguments means "back to palette".
local function TintBorder(frame, r, g, b, a)
    local strips = frame and frame._zui_borderTex
    if not strips then return end
    if not r and frame._zui_rest then
        -- (a field's own resting edge: the white 10% one, not the palette's)
        r, g, b, a = frame._zui_rest[1], frame._zui_rest[2], frame._zui_rest[3], frame._zui_rest[4]
    end
    if not r then
        -- a Classic edge's "palette" is the art's own colour
        if strips._zEdge then
            r, g, b, a = 1, 1, 1, 1
        else
        local bd = Col("border")
        r, g, b, a = bd.r, bd.g, bd.b, bd.a or 1
        end
    end
    for _, t in ipairs(strips) do
        t:SetColorTexture(r, g, b, a or 1)
    end
end

local function SkinBackdrop(frame, bgKey, alpha, look)
    if not frame then return end
    -- Classic: Blizzard's own backdrop - the dialog background and border
    -- on a window (bgKey "windowBg"), the tooltip ones on anything smaller
    -- - drawn by Core_Look.AddFill, untinted. A pre-existing SetBackdrop is
    -- still cleared first, as below.
    local lk = LookOf(look)
    if lk.border.style == "edge" then
        if not frame._zui_cbg then
            if frame.GetBackdrop and frame.SetBackdrop then
                local ok, bd = pcall(frame.GetBackdrop, frame)
                if ok and type(bd) == "table" then
                    pcall(frame.SetBackdrop, frame, nil)
                end
            end
            local window = (bgKey or "windowBg") == "windowBg"
            frame._zui_cbg = Look.AddFill(frame, window and lk.borderWindow or lk.border,
                window and lk.bgTexture or lk.bgSmall, lk.bgAlpha or alpha or 1)
            frame._zui_cbg._zui_own = true
        end
        return
    end
    local bg = Col(bgKey or "windowBg")
    if not frame._zui_cbg then
        -- Neutralize any EXISTING Blizzard backdrop first: modern dialogs
        -- (StaticPopups included - the logout and summon borders) carry
        -- their own SetBackdrop, and adding our fill without clearing it
        -- left Blizzard's ornate edge rendering around ours. The black-
        -- lines classifier rule couldn't save these because _zui_cbg
        -- fences them from it - so the clear belongs HERE, at the root.
        if frame.GetBackdrop and frame.SetBackdrop then
            local ok, bd = pcall(frame.GetBackdrop, frame)
            if ok and type(bd) == "table" then
                pcall(frame.SetBackdrop, frame, nil)
            end
        end
        frame._zui_cbg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
        frame._zui_cbg._zui_own = true
        frame._zui_cbg:SetAllPoints()
        frame._zui_cbg:SetTexture(FLAT)
        AddPixelBorder(frame)
    end
    frame._zui_cbg:SetVertexColor(bg.r, bg.g, bg.b, alpha or bg.a or 1)
end

local function StripTextures(frame)
    if not frame or not frame.GetRegions then return end
    for _, region in ipairs({ frame:GetRegions() }) do
        if region.IsObjectType and region:IsObjectType("Texture") then
            region:SetTexture(nil)
            region:Hide()
        end
    end
end

-- (2026-11-10, Zac on Retail: "random gold line through the center" of
-- the character pane - /fstack named CharacterFrame.NineSlice.TopEdge)
-- The rim's own alpha was set to nothing once; Retail puts it back when a
-- panel changes size or tab. So each piece is emptied too, and the rim is
-- emptied again whenever the game shows it or gives it an alpha.
local function QuietNineSlice(nine)
    if type(nine) ~= "table" or not nine.SetAlpha then return end
    local function Zero(self)
        if rawget(self, "_zQuieting") then return end
        rawset(self, "_zQuieting", true)
        if (self:GetAlpha() or 0) > 0 then self:SetAlpha(0) end
        if self.GetRegions then
            for _, r in ipairs({ self:GetRegions() }) do
                if r.SetAlpha and (r:GetAlpha() or 0) > 0 then r:SetAlpha(0) end
            end
        end
        rawset(self, "_zQuieting", nil)
    end
    Zero(nine)
    if not rawget(nine, "_zQuietHook") then
        rawset(nine, "_zQuietHook", true)
        hooksecurefunc(nine, "SetAlpha", Zero)
        if nine.Show then hooksecurefunc(nine, "Show", Zero) end
        if nine.HookScript then pcall(nine.HookScript, nine, "OnShow", Zero) end
    end
end

local function StripFrameChrome(frame)
    if not frame then return end
    if frame.NineSlice then QuietNineSlice(frame.NineSlice) end
    if frame.Bg then frame.Bg:Hide() end
    if frame.TitleBg then frame.TitleBg:Hide() end
    if frame.Inset then
        if frame.Inset.NineSlice then frame.Inset.NineSlice:SetAlpha(0) end
        if frame.Inset.Bg then frame.Inset.Bg:Hide() end
    end
    local portrait = frame.portrait or frame.PortraitContainer
        or (frame.GetName and frame:GetName() and _G[frame:GetName() .. "Portrait"])
    if portrait then
        if portrait.SetAlpha then portrait:SetAlpha(0) end
        if portrait.Hide then portrait:Hide() end
    end
end


-- titleFrame: where the title lives when it differs from where the line
-- goes. SkinPanel draws on an unnamed child panel, so a lookup through
-- the panel never found <Name>TitleText and no window title went gold.
local function AccentTitle(frame, lineY, rightInset, titleFrame)
    if not frame then return end
    local tf = titleFrame or frame
    local name = tf.GetName and tf:GetName()
    local title = tf.TitleText
        or (tf.TitleContainer and tf.TitleContainer.TitleText)
        or (name and _G[name .. "TitleText"])
    -- (2026-11-10, Zac: "same thing with the mail window. like literally
    -- every menu popup etc needs to match") ONE HEADER: a game window
    -- ZacUI has skinned wears the header ZacUI's own windows wear - the
    -- title in the light text, the rule under it white at 8% - where it
    -- was the gold title over a gold rule.
    local tc = Col("text")
    if title and title.SetTextColor then
        title:SetTextColor(tc.r, tc.g, tc.b, 1)
    end
    local line = frame:CreateTexture(nil, "OVERLAY", nil, 6)
    line._zui_own = true
    line:SetColorTexture(1, 1, 1, 0.08)
    line:SetPoint("TOPLEFT",  frame, "TOPLEFT",  1, lineY or -24)
    line:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -(rightInset or 1), lineY or -24)
    if ns.Pixel then ns.Pixel.Edge(line, "TOP", frame) else line:SetHeight(1) end
    return line
end

-- TEXT buttons: flat fill, 1px border, hover fill + GOLD hover text.
-- (normTex is a bright gradient - reserved for status bars only.)
-- Sweeps unnamed regions too: modern buttons carry unnamed atlas art.
local function SkinButton(btn, bgKey, hoverKey, borderKey, borderAlpha, look)
    if not btn or ZUI.skinned[btn] then return end
    ZUI.skinned[btn] = true
    -- Classic: the button keeps its stock art (UI-Panel-Button)
    if LookOf(look).button == "stock" then return end
    ClearButtonArt(btn)
    for _, region in ipairs({ btn:GetRegions() }) do
        if region.IsObjectType and region:IsObjectType("Texture") then
            region:SetTexture(nil)
            region:SetAlpha(0)
        end
    end

    btn._zui_bgKey = bgKey or "buttonBg"
    btn._zui_hoverKey = hoverKey or "hoverBg"
    btn._zui_bg = btn:CreateTexture(nil, "BACKGROUND")
    btn._zui_bg._zui_own = true
    btn._zui_bg:SetAllPoints()
    btn._zui_bg:SetTexture(FLAT)
    local n = Col(btn._zui_bgKey)
    btn._zui_bg:SetVertexColor(n.r, n.g, n.b, 1)
    AddPixelBorder(btn, borderKey, borderAlpha)

    local fs = btn.GetFontString and btn:GetFontString()
    if fs then
        local tc = Col("text")
        fs:SetTextColor(tc.r, tc.g, tc.b, 1)
        btn._zui_fs = fs
    end

    btn:HookScript("OnEnter", function(self)
        if self._zui_plate then return end
        local h = Col(self._zui_hoverKey or "hoverBg")
        if self._zui_bg then self._zui_bg:SetVertexColor(h.r, h.g, h.b, 1) end
        if self._zui_fs then
            local ac = Col("accent")
            self._zui_fs:SetTextColor(ac.r, ac.g, ac.b, 1)
        end
    end)
    btn:HookScript("OnLeave", function(self)
        if self._zui_plate then return end
        local nn = Col(self._zui_selected and "activeBg" or self._zui_bgKey or "buttonBg")
        if self._zui_bg then self._zui_bg:SetVertexColor(nn.r, nn.g, nn.b, 1) end
        if self._zui_fs then
            local tc = Col(self._zui_selected and "textGreen" or "text")
            self._zui_fs:SetTextColor(tc.r, tc.g, tc.b, 1)
        end
    end)

    -- (2026-11-10, Zac: "so many buttons ... not updated to match the new
    -- buttons") ONE BUTTON LOOK: a game button ZacUI has skinned wears the
    -- same raised plate as ZacUI's own (UIF_Controls: UI.PlateLook) - the
    -- flat fill and the strips step back under it. The framework is up by
    -- the time anything is skinned; without it the flat look above stays.
    local UI = ns.UI
    if UI and UI.PlateLook and btn.HookScript and not btn._zui_borderTex._zEdge then
        btn._zui_plate = true
        btn._zui_bg:SetVertexColor(0, 0, 0, 0)
        TintBorder(btn, 0, 0, 0, 0)
        btn._zDisabled = (btn.IsEnabled and not btn:IsEnabled()) or nil
        UI.PlateLook(btn, fs)
        btn:HookScript("OnDisable", function(self) self._zDisabled = true self:_zPaint() end)
        btn:HookScript("OnEnable", function(self) self._zDisabled = nil self:_zPaint() end)
    end
end

-- SELECTED STATE for a skinned Blizzard tab: the same green fill + green
-- ring ZacUI's own tabs use. Hover still lifts it (gold text) and OnLeave
-- above puts the selected look back.
local function PaintSelected(btn, on)
    if not btn or not btn._zui_bg then return end
    btn._zui_selected = on and true or nil
    if btn._zui_plate then
        -- the plate's picked look: the accent on its edge and label
        btn._zActive = on and true or nil
        if btn._zPaint then btn:_zPaint() end
        return
    end
    local c = Col(on and "activeBg" or btn._zui_bgKey or "buttonBg")
    btn._zui_bg:SetVertexColor(c.r, c.g, c.b, 1)
    if btn._zui_fs then
        local tc = Col(on and "textGreen" or "text")
        btn._zui_fs:SetTextColor(tc.r, tc.g, tc.b, 1)
    end
    if on then
        local r = Col("borderSelected")
        TintBorder(btn, r.r, r.g, r.b, r.a or 1)
    else
        TintBorder(btn)
    end
end

-- ICON/SLOT buttons: nuke every texture region EXCEPT the icon (and the
-- normal texture when the icon IS the normal texture - attachments,
-- repair buttons), crop, border, additive hover.
local function SkinIconButton(btn, keepNormal, look)
    if not btn or ZUI.skinned[btn] then return end
    -- Callers pass GLOBALS whose widget type varies by client build, and
    -- a Texture has no GetRegions. Bail instead of erroring: these run
    -- inside a module's skin function, so one raise here takes down every
    -- widget after it in that function, not just this button.
    if not btn.GetRegions then return end
    ZUI.skinned[btn] = true
    -- Classic: Blizzard's ring, quality ring and overlays stay as drawn;
    -- the icon is only sharpened, never cropped or bordered
    if LookOf(look).iconButton == "stock" then
        local nm = btn.GetName and btn:GetName()
        local ic = btn.icon or btn.Icon
            or (nm and (_G[nm .. "IconTexture"] or _G[nm .. "Icon"] or _G[nm:gsub("Button$", "") .. "Icon"]))
        SharpenIcon(ic)
        return
    end

    local name = btn.GetName and btn:GetName()
    -- Icon lookup, three name spellings: <Name>IconTexture, <Name>Icon,
    -- and 11509's <NameMinusButton>Icon (MerchantRepairAllButton's icon
    -- is the global "MerchantRepairAllIcon" - the old lookup missed it,
    -- the sweep killed it: the "hidden repair icon" bug).
    local icon = btn.icon or btn.Icon
        or (name and (_G[name .. "IconTexture"] or _G[name .. "Icon"]
            or _G[name:gsub("Button$", "") .. "Icon"]))
    local normal = btn.GetNormalTexture and btn:GetNormalTexture()
    -- Bag-search grey-out is a per-button overlay texture (Baganator and
    -- Blizzard both use it: shown = item does NOT match the search).
    -- The strip loop was wiping it, so searches lit every item full
    -- bright. Resolve it like icon/normal, BEFORE the loop, keep it.
    local search = btn.searchOverlay or btn.SearchOverlay
        or (name and _G[name .. "SearchOverlay"])
    -- Quality ring and quest-item overlay are INFORMATION: the ring's
    -- colour moves onto our border below, the quest "!" stays as drawn.
    -- Wiping them here was why no item slot anywhere showed its quality.
    local quality = btn.IconBorder or (name and _G[name .. "IconBorder"])
    local quest = btn.IconQuestTexture or (name and _G[name .. "IconQuestTexture"])

    -- THE ICON IS SOMETIMES THE NORMAL TEXTURE, and that is what left
    -- buttons looking like empty black squares.
    --
    -- Classic draws several icons straight through the button's normal
    -- texture instead of a separate region: TradeSkillSkillIcon, CraftIcon,
    -- ClassTrainerSkillIcon, the macro buttons, the spellbook profession
    -- tabs. When such a button was skinned without keepNormal, the sweep
    -- below plus KillTexture(normal) nulled the icon AND set its alpha to
    -- 0 - and the alpha is the part that never comes back. Blizzard later
    -- calls SetNormalTexture() when you pick a recipe or a skill, which
    -- restores the texture on a region that is still alpha 0, so the slot
    -- stays blank forever. CropIconsUnder already learned this the hard
    -- way on the macro page ("crop, NEVER kill"); the rule belongs here,
    -- where every caller gets it.
    --
    -- So: no separate icon region found means the normal texture is the
    -- best - and often the only - candidate for the icon. Adopt it rather
    -- than destroy it. Worst case a grey ring survives, which is a far
    -- cheaper mistake than deleting the art.
    if not icon and normal then
        icon = normal
        keepNormal = true
    end

    for _, region in ipairs({ btn:GetRegions() }) do
        if region.IsObjectType and region:IsObjectType("Texture") then
            local keep = (region == icon) or (region == search)
                or (keepNormal and region == normal)
                or (region == quality) or (region == quest)
            if not keep then
                region:SetTexture(nil)
                region:SetAlpha(0)
            end
        end
    end
    -- `normal ~= icon` is not redundant with the adoption above. That
    -- block only fires when NO icon was resolved. A template is free to
    -- name its <NormalTexture> "$parentIconTexture" or "$parentIcon", in
    -- which case the lookup resolves icon = normal on its own, the sweep
    -- correctly keeps it - and this line would then null the very region
    -- it just protected. Same permanent-blank-slot ending, reached by a
    -- different road.
    if not keepNormal and normal ~= icon then KillTexture(normal) end

    -- _zui_noCrop: sheet-textured icons (the repair anvils live on a
    -- shared UI-Merchant-RepairIcons sheet with their OWN texcoords)
    -- must never be re-cropped - 0.08-0.92 would slide the sheet and
    -- show the wrong icon. Callers set the flag; everything else keeps
    -- the standard zoom.
    if icon and icon.SetTexCoord and not btn._zui_noCrop then
        ns.Look.CropIcon(icon, nil, nil, { border = false })
    end
    if keepNormal and normal and normal.SetTexCoord and not btn._zui_noCrop then
        ns.Look.CropIcon(normal, nil, nil, { border = false })
    end
    -- Sharpen whether or not it was cropped: _zui_noCrop is about sheet
    -- texcoords, and a sheet icon blurs from grid snapping just the same.
    SharpenIcon(icon)
    if keepNormal then SharpenIcon(normal) end

    AddPixelBorder(btn)
    -- Looked up at call time: AdoptQualityBorder lives in UIF_Bars, which
    -- loads after this file. It blanks the ring and tints our border.
    if quality and quality.SetTexture and ns.AdoptQualityBorder then
        ns.AdoptQualityBorder(btn, quality)
        -- Blizzard re-sets the ring's art on some updates; keep it blank
        -- so only the tinted border carries the colour.
        if not quality._zui_blankHooked then
            quality._zui_blankHooked = true
            hooksecurefunc(quality, "SetTexture", function(t, tex)
                if tex and not t._zui_reblank then
                    t._zui_reblank = true
                    t:SetTexture(nil)
                    t._zui_reblank = nil
                end
            end)
            if quality.SetAtlas then
                hooksecurefunc(quality, "SetAtlas", function(t)
                    if not t._zui_reblank then
                        t._zui_reblank = true
                        t:SetTexture(nil)
                        t._zui_reblank = nil
                    end
                end)
            end
        end
    end

    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl._zui_own = true
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.15)
    hl:SetBlendMode("ADD")
end

-- ARROW buttons: the real media arrows (mirrored for right/up).
local function SkinArrowButton(btn, direction)
    if not btn or ZUI.skinned[btn] then return end
    ZUI.skinned[btn] = true
    ClearButtonArt(btn)

    local ar = btn:CreateTexture(nil, "ARTWORK")
    ar._zui_own = true
    ar:SetSize(12, 12)
    ar:SetPoint("CENTER")
    if direction == "left" then
        ar:SetTexture(TEX_ARROWL)
    elseif direction == "right" then
        ar:SetTexture(TEX_ARROWL)
        ar:SetTexCoord(1, 0, 0, 1)
    elseif direction == "up" then
        ar:SetTexture(TEX_ARROW)
        ar:SetTexCoord(0, 1, 1, 0)
    else
        ar:SetTexture(TEX_ARROW)
    end
    local nc = Col("xNormal")
    ar:SetVertexColor(nc.r, nc.g, nc.b, 1)
    btn._zui_arrow = ar

    -- These fire from Blizzard's own Enable()/Disable() on the action-bar
    -- paging buttons, i.e. from inside a secure call stack. A nil arrow
    -- must not raise there, so every handler checks first.
    btn:HookScript("OnEnter", function(self)
        if not self._zui_arrow then return end
        local a = Col("accent")
        self._zui_arrow:SetVertexColor(a.r, a.g, a.b, 1)
    end)
    btn:HookScript("OnLeave", function(self)
        if not self._zui_arrow then return end
        local nn = Col("xNormal")
        self._zui_arrow:SetVertexColor(nn.r, nn.g, nn.b, 1)
    end)
    btn:HookScript("OnDisable", function(self)
        if self._zui_arrow then self._zui_arrow:SetAlpha(0.35) end
    end)
    btn:HookScript("OnEnable", function(self)
        if self._zui_arrow then self._zui_arrow:SetAlpha(1) end
    end)
end

-- X close: chromeless two rotated lines (Readycheck CreateXCloseButton port).
local function SkinCloseButton(btn, size, look)
    if not btn or ZUI.skinned[btn] then return end
    ZUI.skinned[btn] = true
    -- Classic: the stock round X stays
    if LookOf(look).closeX == "stock" then return end
    ClearButtonArt(btn)

    local w = (btn.GetWidth and btn:GetWidth()) or 0
    local s = size or (w > 0 and math.min(w, 24)) or 24
    local nc = Col("xNormal")

    -- ZacUI's own close icon (2026-11-07; it replaced two rotated lines),
    -- as wide as the lines were (its glyph spans 12/32 of the icon)
    local t = btn:CreateTexture(nil, "ARTWORK")
    t._zui_own = true
    local is = math.floor(s * 0.95 + 0.5)
    t:SetSize(is, is)
    t:SetPoint("CENTER")
    t:SetTexture((ns.MEDIA or "Interface\\AddOns\\ZacUI\\Media\\") .. "Icons\\close128", "CLAMP", "CLAMP", "TRILINEAR")
    t:SetVertexColor(nc.r, nc.g, nc.b, 1)
    btn._zui_xIcon = t

    btn:HookScript("OnEnter", function(self)
        local h = Col("xHover")
        self._zui_xIcon:SetVertexColor(h.r, h.g, h.b, 1)
    end)
    btn:HookScript("OnLeave", function(self)
        local nn = Col("xNormal")
        self._zui_xIcon:SetVertexColor(nn.r, nn.g, nn.b, 1)
    end)
end

local function SkinEditBox(eb, height, look)
    if not eb or ZUI.skinned[eb] then return end
    ZUI.skinned[eb] = true
    -- Classic: the stock input art stays
    if LookOf(look).widgets == "stock" then return end
    local name = eb.GetName and eb:GetName()
    if name then
        HideNamed(name, { "Left", "Mid", "Middle", "Right",
                          "FocusLeft", "FocusMid", "FocusRight" })
    end
    if eb.Left then eb.Left:SetAlpha(0) end
    if eb.Middle then eb.Middle:SetAlpha(0) end
    if eb.Right then eb.Right:SetAlpha(0) end
    -- 11509: popup edit boxes ride TooltipBackdropTemplate - a NineSlice
    -- border SkinBackdrop's backdrop-clear never touches. Hide it like
    -- every other NineSlice.
    if eb.NineSlice then eb.NineSlice:SetAlpha(0) end
    SkinBackdrop(eb, "elementBg", 0.9)
    -- (2026-11-10, Zac: "literally every menu popup etc needs to match")
    -- ONE FIELD LOOK on a game edit box ZacUI has skinned (mail's To and
    -- Subject, every search box): the settings window's field - the input
    -- colour at 0.35 with a white 10% edge. _zui_rest is what TintBorder
    -- goes back to when a caller clears its own tint (focus lost).
    if eb._zui_cbg and eb._zui_borderTex and not eb._zui_borderTex._zEdge then
        local S = ns.UI and ns.UI.S
        local c = S and S.INPUT or { r = 0.024, g = 0.024, b = 0.024 }
        eb._zui_cbg:SetVertexColor(c.r, c.g, c.b, S and S.INPUT_A or 0.35)
        eb._zui_rest = { 1, 1, 1, S and S.INPUT_BRD_A or 0.10 }
        for _, t in ipairs(eb._zui_borderTex) do t:SetColorTexture(1, 1, 1, eb._zui_rest[4]) end
    end
    if height then eb:SetHeight(height) end
end

-- DROPDOWNS (Blizzard UIDropDownMenuTemplate -> the Readycheck look):
-- classic art hidden, fitted dark box, media arrow, palette text. The
-- OPEN lists (DropDownList1/2) are dark-skinned once globally, so every
-- dropdown MENU in the game matches too.
local function SkinDropdown(dd, look)
    if not dd or ZUI.skinned[dd] then return end
    ZUI.skinned[dd] = true
    -- Classic: the stock dropdown art stays
    if LookOf(look).widgets == "stock" then return end
    local name = dd.GetName and dd:GetName()
    if name then
        HideNamed(name, { "Left", "Middle", "Right" })
    end

    local box = CreateFrame("Frame", nil, dd, "BackdropTemplate")
    box:SetPoint("TOPLEFT", dd, "TOPLEFT", 16, -6)
    box:SetPoint("BOTTOMRIGHT", dd, "BOTTOMRIGHT", -14, 6)
    -- One level BELOW the dropdown: at an equal level the box's fill could
    -- draw over the dropdown's own Text region (the selected value).
    box:SetFrameLevel(math.max(0, dd:GetFrameLevel() - 1))
    SkinBackdrop(box, "elementBg", 0.9)

    local text = name and _G[name .. "Text"]
    if text then
        local tc = Col("text")
        text:SetTextColor(tc.r, tc.g, tc.b, 1)
    end

    local btn = name and _G[name .. "Button"]
    if btn then
        ClearButtonArt(btn)
        local ar = btn:CreateTexture(nil, "ARTWORK")
        ar._zui_own = true
        ar:SetSize(10, 10)
        ar:SetPoint("CENTER", 0, 0)
        ar:SetTexture(TEX_ARROW)
        local nc = Col("xNormal")
        ar:SetVertexColor(nc.r, nc.g, nc.b, 1)
        btn._zui_arrow = ar
        btn:HookScript("OnEnter", function(self)
            local a = Col("accent")
            self._zui_arrow:SetVertexColor(a.r, a.g, a.b, 1)
        end)
        btn:HookScript("OnLeave", function(self)
            local nn = Col("xNormal")
            self._zui_arrow:SetVertexColor(nn.r, nn.g, nn.b, 1)
        end)
    end
end

local dropListsSkinned = false
local function SkinDropDownLists()
    if dropListsSkinned then return end
    dropListsSkinned = true
    -- Classic: the game's menus keep their own art
    if LookOf(nil).widgets == "stock" then return end
    for i = 1, (UIDROPDOWNMENU_MAXLEVELS or 2) do
        local list = _G["DropDownList" .. i]
        if list then
            list:HookScript("OnShow", function(self)
                if not self._zui_bg then
                    StripTextures(self)
                    local bd = _G[self:GetName() .. "Backdrop"]
                    if bd then StripTextures(bd) end
                    local mb = _G[self:GetName() .. "MenuBackdrop"]
                    if mb then StripTextures(mb) end
                    SkinBackdrop(self, "windowBg", 0.97)
                    self._zui_bg = true
                end
            end)
        end
    end
end

-- STACK SPLIT (shift-click split popup). Defined HERE, in the primitives
-- section, because Modules.dialogs references it: Lua locals are only
-- visible AFTER their declaration point, and the first placement (below
-- the dialogs module) compiled the reference as a nil GLOBAL - the
-- "attempt to call global SkinStackSplit" error, which also killed the
-- dropdown-list styling running right after it. Second time this project
-- has hit this class; luac cannot catch it.
local function SkinStackSplit()
    if not StackSplitFrame or ZUI.skinned[StackSplitFrame] then return end
    ZUI.skinned[StackSplitFrame] = true
    StripTextures(StackSplitFrame)
    StripFrameChrome(StackSplitFrame)
    SkinBackdrop(StackSplitFrame, "windowBg", 0.97)
    if StackSplitOkayButton then SkinButton(StackSplitOkayButton) end
    if StackSplitCancelButton then SkinButton(StackSplitCancelButton) end
    if StackSplitLeftButton then SkinArrowButton(StackSplitLeftButton, "left") end
    if StackSplitRightButton then SkinArrowButton(StackSplitRightButton, "right") end
end


-- Art signature: lowercase identity string for a button's normal art,
-- from the texture PATH or - critically - the ATLAS name. Atlas-based
-- widgets return a numeric fileID from GetTexture(), which made every
-- string signature check silently skip them: the reason modern Xs and
-- buttons kept surviving the sweeps.
local function GetArtSignature(btn)
    if not btn or not btn.GetNormalTexture then return nil end
    local nt = btn:GetNormalTexture()
    if not nt then return nil end
    local tex = nt.GetTexture and nt:GetTexture()
    if type(tex) == "string" then return tex:lower() end
    local atlas = nt.GetAtlas and nt:GetAtlas()
    if type(atlas) == "string" then return atlas:lower() end
    return nil
end

-- Blizzard CheckButtons (UICheckButtonTemplate family): dark box + border,
-- Blizzard's own check glyph kept on top.
local function SkinBlizzCheck(cb, look)
    if not cb or ZUI.skinned[cb] then return end
    ZUI.skinned[cb] = true
    -- Classic: the stock check box stays
    if LookOf(look).widgets == "stock" then return end
    KillTexture(cb.GetNormalTexture and cb:GetNormalTexture())
    KillTexture(cb.GetPushedTexture and cb:GetPushedTexture())
    KillTexture(cb.GetHighlightTexture and cb:GetHighlightTexture())
    local bg = cb:CreateTexture(nil, "BACKGROUND")
    bg._zui_own = true
    bg:SetPoint("TOPLEFT", 3, -3)
    bg:SetPoint("BOTTOMRIGHT", -3, 3)
    bg:SetTexture(TEX_NORM)
    local e = Col("elementBg")
    bg:SetVertexColor(e.r, e.g, e.b, 1)
end


-- shared with later ZacUI files
ns.AccentTitle = AccentTitle
ns.AddPixelBorder = AddPixelBorder
ns.TintBorder = TintBorder
ns.ClearButtonArt = ClearButtonArt
ns.GetArtSignature = GetArtSignature
ns.HideNamed = HideNamed
ns.KillTexture = KillTexture
ns.PaintSelected = PaintSelected
ns.SkinArrowButton = SkinArrowButton
ns.SkinBackdrop = SkinBackdrop
ns.SkinBlizzCheck = SkinBlizzCheck
ns.SkinButton = SkinButton
ns.SkinCloseButton = SkinCloseButton
ns.SkinDropDownLists = SkinDropDownLists
ns.SkinDropdown = SkinDropdown
ns.SkinEditBox = SkinEditBox
ns.SkinIconButton = SkinIconButton
ns.SkinStackSplit = SkinStackSplit
ns.StripFrameChrome = StripFrameChrome
ns.StripTextures = StripTextures
