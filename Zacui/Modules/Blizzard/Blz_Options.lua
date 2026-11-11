-- Blz_Options - the Settings window (Esc > Options), dressed as ZacUI.
-- Part of ZacUI; load order is set by the TOC.

local ADDON_NAME, ns = ...

-- shared state from earlier ZacUI files
local Modules = ns.Modules
local SkinAllScrollBarsUnder = ns.SkinAllScrollBarsUnder
local SkinBackdrop = ns.SkinBackdrop
local SkinCloseButton = ns.SkinCloseButton
local SkinEditBox = ns.SkinEditBox
local SkinPanel = ns.SkinPanel
local ZUI = ns.ZUI

-- OPTIONS
-- THE SETTINGS WINDOW (Esc > Options: Graphics, Keybindings, Interface...).
--
-- This used to be a "light touch" - a dark fill under Blizzard's art and
-- nothing else - on the grounds that the panel was already dark. It is
-- dark, but it is Blizzard's art: gold-edged tabs, a carved inner frame,
-- ornate category headers, silver keybind buttons, gold slider bars. So it
-- is now dressed like every other ZacUI window, with one rule kept from
-- the old caution: NOTHING STRUCTURAL CHANGES. No frame is re-parented,
-- moved or resized, no Blizzard field is written, no script is replaced.
-- Art regions are faded (alpha), ZacUI surfaces are added beside them, and
-- the per-row restyle is a post-hook on the lists' own Update, so it runs
-- after Blizzard has built a row and never in place of it.
--
-- Rows are POOLED: the list keeps a handful of frames and re-points them
-- at whatever is scrolled into view, so each frame is dressed once (the
-- skinned table) and the per-state paints hook that frame's own methods.

local FLAT = ns.FLAT
local Col = ns.Col
local GetColor = ns.GetColor
local SkinButton = ns.SkinButton
local PaintSelected = ns.PaintSelected
local AddPixelBorder = ns.AddPixelBorder

local function Fade(region)
    if type(region) == "table" and region.SetAlpha then region:SetAlpha(0) end
end

local function AtlasOf(region)
    local ok, a = pcall(function() return region.GetAtlas and region:GetAtlas() end)
    return ok and a or nil
end

-- Blizzard's options art is all "Options_*" atlases: the carved inner
-- frame, the list backgrounds. Faded wherever it is a plain region.
local function FadeOptionsArt(frame)
    if not (frame and frame.GetRegions) then return end
    for _, r in ipairs({ frame:GetRegions() }) do
        if r.IsObjectType and r:IsObjectType("Texture") and not r._zui_own then
            local a = AtlasOf(r)
            if a and (a:find("^Options_") or a:find("^_Options_")) then
                if a == "Options_HorizontalDivider" then
                    local c = GetColor("ui", "border")
                    r:SetTexture(FLAT)
                    r:SetVertexColor(c.r, c.g, c.b, 1)
                    r:SetHeight(1)
                else
                    Fade(r)
                end
            end
        end
    end
end

local UI = ns.UI
local M, F = UI.M, UI.F

-- ZacUI's font at one of ZacUI's sizes, the way UI.Font sets it, for a
-- string Blizzard owns. Re-applied after any SetFontObject of Blizzard's.
local function ZFont(fs, size)
    ns.HouseFont(fs, size)
end

local function PaintText(fs, cat, key)
    if type(fs) ~= "table" or not fs.SetTextColor then return end
    local c = GetColor(cat, key)
    fs._zRemapping = true
    fs:SetTextColor(c.r, c.g, c.b, 1)
    fs._zRemapping = nil
end

local function Tex(frame, layer, sub)
    local t = frame:CreateTexture(nil, layer, nil, sub)
    t._zui_own = true
    t:SetTexture(FLAT)
    return t
end

-- One 1px box edge as four strips around an anchor region.
local function EdgeAround(frame, region, layer, sub)
    local strips = {}
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local t = Tex(frame, layer, sub)
        if side == "TOP" or side == "BOTTOM" then
            t:SetPoint(side .. "LEFT", region, side .. "LEFT")
            t:SetPoint(side .. "RIGHT", region, side .. "RIGHT")
            t:SetHeight(1)
        else
            t:SetPoint("TOP" .. side, region, "TOP" .. side)
            t:SetPoint("BOTTOM" .. side, region, "BOTTOM" .. side)
            t:SetWidth(1)
        end
        strips[#strips + 1] = t
    end
    return strips
end

local WHITE = { r = 1, g = 1, b = 1, a = 1 }
local function TintAll(strips, c, a)
    for _, t in ipairs(strips) do t:SetVertexColor(c.r, c.g, c.b, a or c.a or 1) end
end

-- A UI.Card header strip: card fill, soft border, the 3 px gold bar down
-- the left. Drawn as textures ON the row, not as a child frame: the row's
-- label is one of the row's own regions, and any child frame would cover
-- it.
local function CardStrip(frame, left, top, right, bottom)
    local fill = Tex(frame, "BACKGROUND", -7)
    fill:SetPoint("TOPLEFT", left, top)
    fill:SetPoint("BOTTOMRIGHT", right or 0, bottom)
    -- (2026-11-10, Zac: "options still on the really old styling") the
    -- settings window's card: a faint dark wash, a white 5% edge, no gold
    -- bar down the left
    fill:SetVertexColor(0, 0, 0, UI.S.ROW_ODD)
    TintAll(EdgeAround(frame, fill, "BORDER", 1), WHITE, UI.S.BORDER_A)
    return fill
end

-- TEXT IN THE HOUSE COLOURS. Blizzard paints this window's labels gold
-- (NORMAL_FONT_COLOR) and repaints them on every enable / disable and
-- font change, so a one-time recolour is undone at once. Each string gets
-- a post-hook instead: whatever Blizzard writes, gold becomes ZacUI's
-- text colour and Blizzard's grey becomes ZacUI's grey. White, green and
-- red - real meaning - pass through untouched.
local function IsGold(r, g, b)
    return r and r > 0.85 and g > 0.6 and g < 0.92 and b < 0.3
end
local function IsGrey(r, g, b)
    return r and math.abs(r - g) < 0.06 and math.abs(g - b) < 0.06 and r < 0.7 and r > 0.2
end
local function Remap(fs)
    if fs._zRemapping then return end
    local r, g, b = fs:GetTextColor()
    local c
    if IsGold(r, g, b) then
        c = GetColor("text", "normal")
    elseif IsGrey(r, g, b) then
        c = GetColor("text", r < 0.55 and "disabled" or "gray")
    end
    if c then
        fs._zRemapping = true
        fs:SetTextColor(c.r, c.g, c.b, 1)
        fs._zRemapping = nil
    end
end
local function PinText(fs)
    if type(fs) ~= "table" or not fs.SetTextColor or fs._zPinned then return end
    fs._zPinned = true
    hooksecurefunc(fs, "SetTextColor", Remap)
    hooksecurefunc(fs, "SetFontObject", Remap)
    Remap(fs)
end
local function PinTextsOf(frame)
    if not (frame and frame.GetRegions) then return end
    for _, r in ipairs({ frame:GetRegions() }) do
        if r.IsObjectType and r:IsObjectType("FontString") then PinText(r) end
    end
end

-- Tabs, like Kit.Tabs: a flat 26 px button, label centred, the selected
-- one green. Blizzard re-anchors the label to the bottom edge on every
-- selection, so it is put back in the middle after each one.
local function SkinTab(tab)
    if not tab or ZUI.skinned[tab] then return end
    SkinButton(tab)
    for _, k in ipairs({ "Left", "Middle", "Right" }) do Fade(tab[k]) end
    tab:SetHeight(26)
    local function Paint(self)
        local sel = self.IsSelected and self:IsSelected()
        PaintSelected(self, sel)
        local t = self.Text
        if t then
            t:ClearAllPoints()
            t:SetPoint("CENTER", 0, 0)
            ZFont(t, F.CARD)
            PaintText(t, sel and "ui" or "text", sel and "accent" or "normal")
        end
    end
    PinText(tab.Text)
    if tab.Text then
        ZFont(tab.Text, F.CARD)
        tab:SetWidth(math.max(72, math.ceil(tab.Text:GetStringWidth() or 0) + 28))
    end
    -- OnSelected runs on every selection change, whoever makes it.
    if type(tab.OnSelected) == "function" then
        hooksecurefunc(tab, "OnSelected", Paint)
    end
    tab:HookScript("OnLeave", Paint)
    Paint(tab)
end

-- The < > steppers beside dropdowns and sliders: Blizzard's gold icon
-- buttons become ZacUI's plain arrows (grey, gold under the mouse, faded
-- when there is nowhere further to go).
local function SkinStepper(b, dir)
    if not b or ZUI.skinned[b] or not b.GetRegions then return end
    for _, r in ipairs({ b:GetRegions() }) do
        if r.IsObjectType and r:IsObjectType("Texture") then r:SetAlpha(0) end
    end
    ns.SkinArrowButton(b, dir)
    if b.IsEnabled and not b:IsEnabled() and b._zui_arrow then b._zui_arrow:SetAlpha(0.35) end
end

-- Checkboxes, like UI.Checkbox: a flat box with a black edge, ZacUI's
-- green checkmark, a gold edge under the mouse.
local function SkinCheck(cb)
    if not cb or ZUI.skinned[cb] then return end
    ZUI.skinned[cb] = true
    for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture" }) do
        local t = cb[get] and cb[get](cb)
        if t then t:SetAlpha(0) end
    end
    if cb.HoverBackground then cb.HoverBackground:SetAlpha(0) end
    local box = CreateFrame("Frame", nil, cb)
    box:SetSize(14, 14)
    box:SetPoint("CENTER")
    box:SetFrameLevel(math.max(0, cb:GetFrameLevel() - 1))
    local fill = box:CreateTexture(nil, "BACKGROUND")
    fill._zui_own = true
    fill:SetAllPoints()
    fill:SetTexture(FLAT)
    AddPixelBorder(box)
    -- (2026-11-10) the settings window's checkbox: its box colour, a
    -- white 5% edge (the accent at 15% while ticked), the tick an accent
    -- square
    local S = UI.S
    local function Paint(hot)
        local on = cb.GetChecked and cb:GetChecked() and true or false
        local k = (on or hot) and 1 or S.CB_REST
        local c = S.CB_BOX
        fill:SetVertexColor(c.r, c.g, c.b, k)
        if on then
            local a = GetColor("ui", "accent")
            ns.TintBorder(box, a.r, a.g, a.b, S.CB_ACT_BRD_A)
        else
            ns.TintBorder(box, 1, 1, 1, S.CB_BRD_A * k)
        end
    end
    Paint(false)
    cb:HookScript("OnEnter", function() Paint(true) end)
    cb:HookScript("OnLeave", function() Paint(false) end)
    cb:HookScript("OnClick", function(self) Paint(self.IsMouseOver and self:IsMouseOver()) end)
    if type(cb.SetChecked) == "function" then hooksecurefunc(cb, "SetChecked", function() Paint(false) end) end
    for _, get in ipairs({ "GetCheckedTexture", "GetDisabledCheckedTexture" }) do
        local t = cb[get] and cb[get](cb)
        if t then
            t:SetTexture(FLAT)
            t:ClearAllPoints()
            t:SetSize(10, 10)
            t:SetPoint("CENTER")
            local c = (get == "GetCheckedTexture") and GetColor("ui", "accent") or GetColor("text", "disabled")
            t:SetVertexColor(c.r, c.g, c.b, 1)
        end
    end
end

-- Sliders, like UI.Slider: a 6 px bordered track and a narrow pale grab
-- with its own outline, riding above the track.
local function SkinSlider(sl)
    if not sl or ZUI.skinned[sl] then return end
    ZUI.skinned[sl] = true
    for _, k in ipairs({ "Left", "Middle", "Right" }) do Fade(sl[k]) end
    -- (2026-11-10) the settings window's slider: a 4 px pill, a round
    -- accent grip with a black edge
    local S = UI.S
    local track = CreateFrame("Frame", nil, sl)
    track:SetHeight(S.TRACK_H)
    track:SetPoint("LEFT", 0, 0)
    track:SetPoint("RIGHT", 0, 0)
    track:SetFrameLevel(math.max(0, sl:GetFrameLevel() - 1))
    if UI.Pill then
        UI.Pill(track, "BACKGROUND", 1, S.TRACK_H):Color(1, 1, 1, S.SL_TRACK_A)
    else
        local tf = track:CreateTexture(nil, "BACKGROUND")
        tf._zui_own = true
        tf:SetAllPoints()
        tf:SetTexture(FLAT)
        tf:SetVertexColor(1, 1, 1, S.SL_TRACK_A)
    end
    local thumb = sl.GetThumbTexture and sl:GetThumbTexture()
    if thumb then
        local a = GetColor("ui", "accent")
        thumb:SetSize(12, 12)
        if UI.DiscArt then UI.DiscArt(thumb, 12) else thumb:SetTexture(FLAT) end
        thumb:SetVertexColor(a.r, a.g, a.b, 1)
        if UI.DiscArt and sl.CreateTexture then
            local block = sl:CreateTexture(nil, "ARTWORK", nil, 6)
            block._zui_own = true
            UI.DiscArt(block, 14)
            block:SetSize(14, 14)
            block:SetPoint("CENTER", thumb, "CENTER", 0, 0)
            block:SetVertexColor(0, 0, 0, 1)
            if thumb.SetDrawLayer then thumb:SetDrawLayer("OVERLAY", 2) end
        end
    end
    local holder = sl:GetParent()
    if holder then
        SkinStepper(holder.Back, "left")
        SkinStepper(holder.Forward, "right")
        for _, k in ipairs({ "LeftText", "RightText", "TopText", "MinText", "MaxText" }) do PinText(holder[k]) end
    end
end

-- Dropdowns, like ZacUI's: the dropdown palette's box and arrow, the
-- value in the text colour.
local function SkinMenuButton(dd)
    if not dd or ZUI.skinned[dd] then return end
    ZUI.skinned[dd] = true
    for _, k in ipairs({ "Background", "Left", "Middle", "Right" }) do Fade(dd[k]) end
    local bg = dd:CreateTexture(nil, "BACKGROUND", nil, -7)
    bg._zui_own = true
    bg:SetAllPoints()
    bg:SetTexture(FLAT)
    -- (2026-11-10) the settings window's dropdown: its fill, a white edge
    local S = UI.S
    AddPixelBorder(dd)
    local function Paint(hot)
        local c = S.DD_BG
        bg:SetVertexColor(c.r, c.g, c.b, hot and S.DD_BG_HA or S.DD_BG_A)
        ns.TintBorder(dd, 1, 1, 1, hot and S.DD_BRD_HA or S.DD_BRD_A)
    end
    Paint(false)
    PinText(dd.Text)
    if dd.Arrow then
        local c = GetColor("dropdown", "arrow")
        dd.Arrow:SetDesaturated(true)
        dd.Arrow:SetVertexColor(c.r, c.g, c.b, 1)
    end
    dd:HookScript("OnEnter", function() Paint(true) end)
    dd:HookScript("OnLeave", function() Paint(false) end)
end

-- Keybind buttons: the silver stretch art out (its textures are swapped
-- on press, so they are faded rather than cleared), our button look in,
-- and the "press a key now" highlight kept - recoloured, not removed,
-- because it is the only sign the button is listening.
local STRETCH = { "TopLeft", "TopRight", "BottomLeft", "BottomRight", "TopMiddle",
    "MiddleLeft", "MiddleRight", "BottomMiddle", "MiddleMiddle" }
local function SkinKeyButton(b)
    if not b or ZUI.skinned[b] then return end
    ZUI.skinned[b] = true
    for _, k in ipairs(STRETCH) do Fade(b[k]) end
    local hl = b.GetHighlightTexture and b:GetHighlightTexture()
    if hl then hl:SetAlpha(0) end
    local bg = b:CreateTexture(nil, "BACKGROUND", nil, -7)
    bg._zui_own = true
    bg:SetAllPoints()
    bg:SetTexture(FLAT)
    local n = Col("buttonBg")
    bg:SetVertexColor(n.r, n.g, n.b, 1)
    AddPixelBorder(b)
    -- (2026-11-10) the one button look: the raised plate
    local plated = UI.PlateLook and true or false
    if plated then
        bg:SetVertexColor(0, 0, 0, 0)
        ns.TintBorder(b, 0, 0, 0, 0)
        UI.PlateLook(b, b.Text or (b.GetFontString and b:GetFontString()))
    end
    if b.SelectedHighlight then
        local a = Col("accent")
        b.SelectedHighlight:SetTexture(FLAT)
        b.SelectedHighlight:SetAllPoints()
        b.SelectedHighlight:SetBlendMode("BLEND")
        b.SelectedHighlight:SetVertexColor(a.r, a.g, a.b, 0.35)
    end
    b:HookScript("OnEnter", function()
        if plated then return end
        local h = Col("hoverBg")
        bg:SetVertexColor(h.r, h.g, h.b, 1)
    end)
    b:HookScript("OnLeave", function()
        if plated then return end
        local c = Col("buttonBg")
        bg:SetVertexColor(c.r, c.g, c.b, 1)
    end)
end

local SkinRow
local rowInitDone = setmetatable({}, { __mode = "k" })

-- Collapsible sections (the keybinding groups, Graphics' advanced): ONE
-- frame holds the bar and, when open, every row under it, so the whole
-- frame is one UI.Card - card fill, gold bar down the left, the gold
-- title - and it grows and shrinks with the section. A +/- of ours
-- replaces the arrow baked into Blizzard's bar art.
local function SkinSectionBar(section)
    local bar = section and section.Button
    if not bar or ZUI.skinned[bar] then return end
    ZUI.skinned[bar] = true
    for _, r in ipairs({ bar:GetRegions() }) do
        if r.IsObjectType and r:IsObjectType("Texture") then Fade(r) end
    end
    CardStrip(section, -3, -2, -4, -4)
    local label = bar.Text
    if label then
        -- Pinned BEFORE the row pass reaches it: the remap turns gold
        -- into plain text, and this one is meant to be gold.
        label._zPinned = true
        ZFont(label, F.CARD)
        PaintText(label, "text", "gold")
        label:ClearAllPoints()
        label:SetPoint("LEFT", bar, "LEFT", 12, 1)
    end
    local sign = UI.Font(bar, F.CARD, { cat = "text", key = "gray" })
    sign:SetPoint("RIGHT", bar, "RIGHT", -10, 1)
    local function Paint()
        local data = section.GetElementData and section:GetElementData()
        local open = data and data.data and data.data.expanded
        sign:SetText(open and "-" or "+")
        for _, r in ipairs({ bar:GetRegions() }) do
            if r.IsObjectType and r:IsObjectType("Texture") and not r._zui_own then r:SetAlpha(0) end
        end
    end
    if type(section.OnExpandedChanged) == "function" then
        hooksecurefunc(section, "OnExpandedChanged", Paint)
    end
    if type(section.Init) == "function" then
        hooksecurefunc(section, "Init", Paint)
        -- A pooled section re-pointed at a bigger group builds more rows
        -- from its own pool; those are dressed here (each control once).
        hooksecurefunc(section, "Init", function(self) SkinRow(self, 0) end)
    end
    bar:HookScript("OnClick", Paint)
    bar:HookScript("OnEnter", function() PaintText(sign, "ui", "accent") end)
    bar:HookScript("OnLeave", function() PaintText(sign, "text", "gray") end)
    Paint()
end

-- Section titles inside a page ("Controls", "Camera" ...) become the
-- title of a card; the card itself is drawn by PaintCards below.
local function SkinSectionHeader(f)
    if ZUI.skinned[f] then return end
    ZUI.skinned[f] = true
    local t = f.Title
    t._zPinned = true
    ZFont(t, F.CARD)
    PaintText(t, "text", "gold")
    t:ClearAllPoints()
    t:SetPoint("LEFT", f, "TOPLEFT", 12, -23)
end

-- Labels start where a ZacUI card's controls do (14 px in from the card
-- edge) instead of Blizzard's 37, in ZacUI's font. Blizzard re-anchors
-- and re-fonts the label in every Init, so this runs after each one; it
-- only ever moves Blizzard's own 37-based offset, so running twice is
-- harmless.
local LABEL_SHIFT = 26
local function ShiftLabel(fs, size)
    if type(fs) ~= "table" or not fs.GetNumPoints then return end
    for i = 1, fs:GetNumPoints() do
        local p, rel, rp, x, y = fs:GetPoint(i)
        if p == "LEFT" and type(x) == "number" and x >= 37 then
            fs:SetPoint("LEFT", rel, rp, x - LABEL_SHIFT, y or 0)
            break
        end
    end
    if size then ZFont(fs, size) end
end

local function RowInit(f)
    local t = f.Text
    if not t then return end
    local small = t.GetFontObject and t:GetFontObject() == _G.GameFontNormalSmall
    ShiftLabel(t, small and F.LABEL or F.CARD)
end

local function BindingInit(f)
    ShiftLabel(f.Label, F.CARD)
end

-- Everything inside one settings row, found by what it IS rather than by
-- template name (the same control appears under a dozen templates).
SkinRow = function(frame, depth)
    if not frame or depth > 3 then return end
    if frame.IsForbidden and frame:IsForbidden() then return end
    if depth == 0 and frame.Title and frame.NewFeature and not frame.Text and not frame.Button then
        SkinSectionHeader(frame)
    end
    if frame.Button and frame.Button.Text and frame.Button.GetRegions
            and (frame.OnExpandedChanged or frame.CalculateHeight) then
        SkinSectionBar(frame)
    end
    PinTextsOf(frame)
    -- A keybinding row (inside a section): label in, ZacUI's font.
    if frame.Label and frame.Buttons and type(frame.Init) == "function" and not rowInitDone[frame] then
        rowInitDone[frame] = true
        hooksecurefunc(frame, "Init", BindingInit)
        BindingInit(frame)
    end
    if frame.IncrementButton then SkinStepper(frame.IncrementButton, "right") end
    if frame.DecrementButton then SkinStepper(frame.DecrementButton, "left") end
    for _, child in ipairs({ frame:GetChildren() }) do
        if child.IsObjectType then
            if child:IsObjectType("CheckButton") then
                SkinCheck(child)
            elseif child:IsObjectType("Slider") then
                SkinSlider(child)
            elseif child:IsObjectType("DropdownButton") or (child.Arrow and child.Text and child.Background) then
                SkinMenuButton(child)
            elseif child:IsObjectType("Button") then
                if child.SelectedHighlight or child.TopLeft then
                    SkinKeyButton(child)
                elseif child.Left and child.Middle and child.Right and child.OnSelected and child.IsSelected then
                    SkinTab(child)
                elseif (child.Left and child.Right) or (child.GetName and child:GetName()
                        and _G[child:GetName() .. "Left"]) then
                    SkinButton(child)
                end
            end
            if not child:IsObjectType("Slider") then SkinRow(child, depth + 1) end
        end
    end
    if frame.NineSlice and frame ~= SettingsPanel then frame.NineSlice:SetAlpha(0) end
end

-- THE CATEGORY LIST, as ZacUI's config sidebar. Each category is a nav
-- row - a bordered box on the row colour, the gold bar down the left and
-- green text when selected, the hover colour under the mouse - and a
-- category with children carries the config's chevron on the right
-- instead of Blizzard's +/- on the left. Headers become small gold
-- section labels over a gold rule.
local function PaintNav(self, selected)
    local nav = self._zNav
    if not nav then return end
    if selected == nil then selected = nav.sel else nav.sel = selected end
    if self.Texture then self.Texture:SetAlpha(0) end
    -- (2026-11-10, Zac: "options still on the really old styling") the
    -- settings window's page rows: a faint plate with a soft edge; the
    -- edge goes to the accent under the mouse and on the open page, which
    -- also carries the accent bar; the name white at 0.60 / 0.86 / 1.0
    local S, a = UI.S, GetColor("ui", "accent")
    if selected then
        nav.fill:SetVertexColor(a.r, a.g, a.b, 0.08)
        TintAll(nav.edge, a, 0.70)
    elseif self.over then
        nav.fill:SetVertexColor(1, 1, 1, 0.07)
        TintAll(nav.edge, a, 0.50)
    else
        nav.fill:SetVertexColor(1, 1, 1, 0.035)
        TintAll(nav.edge, WHITE, 0.085)
    end
    nav.ind:SetVertexColor(a.r, a.g, a.b, selected and 1 or 0)
    -- Blizzard swaps the label's font object on every state change, so
    -- the font and colour go back on after each one.
    ZFont(self.Label, F.NAV)
    if self.Label and self.Label.SetTextColor then
        self.Label._zPinned = true
        self.Label:SetTextColor(1, 1, 1, selected and 1 or (self.over and S.NAV_HOVER or S.NAV_EN))
    end

    local tg, chev = self.Toggle, nav.chev
    if tg and chev then
        for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture" }) do
            local t = tg[get] and tg[get](tg)
            if t then t:SetAlpha(0) end
        end
        local data = self.GetElementData and self:GetElementData()
        local cat = data and data.data and data.data.category
        local open = cat and cat.IsExpanded and cat:IsExpanded()
        -- Down when open, right when closed: the shipped left arrow
        -- mirrored, exactly as the config sidebar does it.
        if open then
            chev:SetTexture(ns.TEX_ARROW)
            chev:SetTexCoord(0, 1, 0, 1)
        else
            chev:SetTexture(ns.TEX_ARROWL)
            chev:SetTexCoord(1, 0, 0, 1)
        end
        local a = GetColor("ui", "accent")
        chev:SetVertexColor(a.r, a.g, a.b, self.over and 1 or 0.65)
    end
end

local function SkinCategory(btn)
    if not btn or ZUI.skinned[btn] then return end
    ZUI.skinned[btn] = true
    if btn.Background and btn.Label and not btn.Texture then
        Fade(btn.Background)
        local label = btn.Label
        label:ClearAllPoints()
        label:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 2, 8)
        local function Head(self)
            Fade(self.Background)
            ZFont(self.Label, F.CARD)
            PaintText(self.Label, "text", "gold")
        end
        local rule = Tex(btn, "ARTWORK")
        rule:SetHeight(1)
        rule:SetPoint("BOTTOMLEFT", 0, 4)
        rule:SetPoint("BOTTOMRIGHT", 0, 4)
        local a = GetColor("ui", "accent")
        rule:SetVertexColor(a.r, a.g, a.b, 0.6)
        if type(btn.Init) == "function" then hooksecurefunc(btn, "Init", Head) end
        Head(btn)
        return
    end
    if not (btn.Texture and btn.Label) then return end

    local nav = { sel = false }
    nav.fill = Tex(btn, "BACKGROUND", -7)
    nav.fill:SetAllPoints()
    nav.edge = EdgeAround(btn, nav.fill, "BORDER", 1)
    nav.ind = Tex(btn, "BORDER", 2)
    nav.ind:SetWidth(3)
    nav.ind:SetPoint("TOPLEFT", 1, -1)
    nav.ind:SetPoint("BOTTOMLEFT", 1, 1)
    btn._zNav = nav

    btn.Label:ClearAllPoints()
    btn.Label:SetPoint("LEFT", btn, "LEFT", 10, 0)
    btn.Label:SetPoint("RIGHT", btn, "RIGHT", -22, 0)
    btn.Label:SetWordWrap(false)

    local tg = btn.Toggle
    if tg then
        tg:ClearAllPoints()
        tg:SetSize(18, 18)
        tg:SetPoint("RIGHT", btn, "RIGHT", -2, 0)
        nav.chev = tg:CreateTexture(nil, "ARTWORK")
        nav.chev._zui_own = true
        nav.chev:SetSize(8, 8)
        nav.chev:SetPoint("CENTER")
        if type(btn.SetExpanded) == "function" then
            hooksecurefunc(btn, "SetExpanded", function(self) PaintNav(self) end)
        end
        tg:HookScript("OnEnter", function() PaintNav(btn) end)
        tg:HookScript("OnLeave", function() PaintNav(btn) end)
    end
    if type(btn.UpdateStateInternal) == "function" then
        hooksecurefunc(btn, "UpdateStateInternal", PaintNav)
    end
    PaintNav(btn)
end

-- A pooled row's controls are built once, with the row, so one pass per
-- row frame is enough however often the list scrolls.
local rowDone = setmetatable({}, { __mode = "k" })
local function SkinRowOnce(f)
    if rowDone[f] then return end
    rowDone[f] = true
    SkinRow(f, 0)
    if f.Text and type(f.Init) == "function" and not rowInitDone[f] then
        rowInitDone[f] = true
        hooksecurefunc(f, "Init", RowInit)
        RowInit(f)
    end
    -- Blizzard's hover glow only lit the label half of a row; ZacUI's
    -- hover is the buttons' faint white lift, across the whole row.
    local hb = f.Tooltip and f.Tooltip.HoverBackground
    if hb and hb.SetColorTexture then
        hb:SetColorTexture(1, 1, 1, 0.05)
        hb:SetBlendMode("ADD")
        hb:ClearAllPoints()
        hb:SetPoint("TOPLEFT", f, "TOPLEFT", -2, 0)
        hb:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -5, 0)
    end
end

-- CARDS. Each page is a run of separate list rows - a section title, then
-- its settings, then the next title - so a card cannot be one frame. Each
-- row draws its own slice of one instead: the title row the top, every
-- setting under it the sides (reaching half-way into the gap to the next
-- row, so the slices meet), the last one the bottom edge. Rows are pooled
-- and re-pointed as the list scrolls, so which slice a row draws is
-- worked out again on every update, from its neighbours in the data.
local function KindOf(ed)
    if type(ed) ~= "table" then return nil end
    local ok, t = pcall(ed.GetTemplate, ed)
    t = ok and t or nil
    if t == "SettingsListSectionHeaderTemplate" then return "head" end
    -- Sections are their own cards; search hits and spacers sit outside.
    if type(t) ~= "string" or t:find("Section") or t:find("SearchCategory") or t:find("Spacer") then
        return "break"
    end
    return "body"
end

local function Segment(f)
    local s = f._zSeg
    if s then return s end
    s = {}
    s.fill = Tex(f, "BACKGROUND", -7)
    s.fill:SetVertexColor(0, 0, 0, UI.S.ROW_ODD)
    s.l, s.r, s.t, s.b = Tex(f, "BORDER", 1), Tex(f, "BORDER", 1), Tex(f, "BORDER", 1), Tex(f, "BORDER", 1)
    s.l:SetWidth(1)
    s.l:SetPoint("TOPLEFT", s.fill, "TOPLEFT")
    s.l:SetPoint("BOTTOMLEFT", s.fill, "BOTTOMLEFT")
    s.r:SetWidth(1)
    s.r:SetPoint("TOPRIGHT", s.fill, "TOPRIGHT")
    s.r:SetPoint("BOTTOMRIGHT", s.fill, "BOTTOMRIGHT")
    s.t:SetHeight(1)
    s.t:SetPoint("TOPLEFT", s.fill, "TOPLEFT")
    s.t:SetPoint("TOPRIGHT", s.fill, "TOPRIGHT")
    s.b:SetHeight(1)
    s.b:SetPoint("BOTTOMLEFT", s.fill, "BOTTOMLEFT")
    s.b:SetPoint("BOTTOMRIGHT", s.fill, "BOTTOMRIGHT")
    TintAll({ s.l, s.r, s.t, s.b }, WHITE, UI.S.BORDER_A)
    s.all = { s.fill, s.l, s.r, s.t, s.b }
    f._zSeg = s
    return s
end

local function SetSegment(f, kind, top, bottom)
    local s = Segment(f)
    -- Spacing between rows is 9 px: a slice reaches 5 up and 5 down so
    -- neighbours overlap by one pixel rather than leave a seam. A title
    -- starts 8 px into its own row, which is the gap between two cards.
    local y1 = (kind == "head") and -8 or (top and 4 or 5)
    local y2 = bottom and -4 or -5
    s.fill:ClearAllPoints()
    s.fill:SetPoint("TOPLEFT", f, "TOPLEFT", -3, y1)
    s.fill:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, y2)
    for _, t in ipairs(s.all) do t:Show() end
    s.t:SetShown(kind == "head" or top)
    s.b:SetShown(bottom)
end

local function HideSegment(f)
    local s = f._zSeg
    if s then for _, t in ipairs(s.all) do t:Hide() end end
end

local function PaintCards(box)
    local dp = box.GetDataProvider and box:GetDataProvider()
    if not dp or type(dp.Find) ~= "function" then return end
    box:ForEachFrame(function(f)
        pcall(function()
            local i = f.GetElementDataIndex and f:GetElementDataIndex()
            local kind = KindOf(f.GetElementData and f:GetElementData())
            if not i or kind == nil or kind == "break" then
                HideSegment(f)
                return
            end
            local prev = (i > 1) and KindOf(dp:Find(i - 1)) or nil
            local nxt = KindOf(dp:Find(i + 1))
            local top = kind == "body" and (prev == nil or prev == "break")
            SetSegment(f, kind, top, nxt ~= "body")
        end)
    end)
end

local function EachFrame(box, fn)
    if box and type(box.ForEachFrame) == "function" then
        box:ForEachFrame(function(f) pcall(fn, f) end)
    end
end

local function HookList(box, fn, after)
    if not box or box._zOptHooked or type(box.Update) ~= "function" then return end
    box._zOptHooked = true
    hooksecurefunc(box, "Update", function(self)
        EachFrame(self, fn)
        if after then pcall(after, self) end
    end)
    EachFrame(box, fn)
    if after then pcall(after, box) end
end

local FOOT_H = 36

local function Place(frame, ...)
    if not frame then return end
    frame:ClearAllPoints()
    frame:SetPoint(...)
end

-- THE WINDOW CHROME, built like UI.Window and Kit.Cover: a flat header
-- bar with the ZacUI icon, the gold title, the gold hairline and the X;
-- the config's sidebar column behind the category list; Kit's footer
-- strip under Close / Apply. Blizzard's own title lives on the NineSlice
-- (faded with it), so ours copies whatever Blizzard writes there.
local function BuildChrome(sp)
    local bar = CreateFrame("Frame", nil, sp)
    bar:SetHeight(M.TITLEBAR)
    bar:SetPoint("TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", -1, -1)
    UI.Fill(bar, "ui", "headerBg")
    -- (2026-11-10, Zac: "options still on the really old styling") the
    -- flat header every ZacUI window wears now: the window itself, the
    -- title in the light text, a white 6% rule under it (it was the gold
    -- header art)
    bar._zFill:SetVertexColor(0, 0, 0, 0)
    bar._zPaint = function(self) self._zFill:SetVertexColor(0, 0, 0, 0) end
    do
        local rule = Tex(bar, "ARTWORK", 1)
        rule:SetHeight(1)
        rule:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
        rule:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
        rule:SetVertexColor(1, 1, 1, UI.S.HEAD_DIV_A)
    end

    local icon = bar:CreateTexture(nil, "ARTWORK", nil, 3)
    icon._zui_own = true
    icon:SetSize(18, 18)
    icon:SetPoint("LEFT", 9, 2)
    icon:SetTexture(ns.TEX_ICON)
    if ns.SharpenIcon then ns.SharpenIcon(icon) end
    if UI.AnimateMark then UI.AnimateMark(icon, bar, { idle = false }) end

    local src = sp.NineSlice and sp.NineSlice.Text
    local title = UI.Font(bar, F.TITLE, {
        text = (src and src:GetText()) or _G.SETTINGS_TITLE or "Options",
        cat = "text", key = "normal" })
    title:SetPoint("LEFT", icon, "RIGHT", 8, 2)
    if src then
        hooksecurefunc(src, "SetText", function(_, t) title:SetText(t or "") end)
    end

    -- Drag by the bar, like every ZacUI window.
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function()
        if sp:IsMovable() then sp:StartMoving() end
    end)
    bar:SetScript("OnDragStop", function() sp:StopMovingOrSizing() end)

    local close = sp.ClosePanelButton
    if close then
        SkinCloseButton(close, 22)
        Place(close, "RIGHT", bar, "RIGHT", -5, 0)
        close:SetSize(22, 22)
        close:SetFrameLevel(bar:GetFrameLevel() + 2)
    end

    -- Sidebar column, from under the title bar down to the footer, as
    -- wide as the category list - with the config's 1 px rule on its
    -- right. Textures on the window itself, so they sit under every one
    -- of Blizzard's frames.
    local cat = sp.CategoryList
    if cat then
        local side = Tex(sp, "BACKGROUND", -6)
        side:SetPoint("TOPLEFT", sp, "TOPLEFT", 1, -(M.TITLEBAR + 1))
        side:SetPoint("BOTTOMLEFT", sp, "BOTTOMLEFT", 1, FOOT_H + 1)
        side:SetPoint("RIGHT", cat, "RIGHT", 4, 0)
        -- (the settings window's sidebar: the window, a fifth darker)
        side:SetVertexColor(0, 0, 0, UI.S.SIDEBAR_A)
        local edge = Tex(sp, "BACKGROUND", -5)
        edge:SetWidth(1)
        edge:SetPoint("TOPLEFT", side, "TOPRIGHT")
        edge:SetPoint("BOTTOMLEFT", side, "BOTTOMRIGHT")
        edge:SetVertexColor(1, 1, 1, UI.S.HEAD_DIV_A)
    end

    -- Footer strip (Kit.Footer's colours) for Close / Apply and the
    -- "press a key" prompt the keybinding page writes.
    local foot = Tex(sp, "BACKGROUND", -6)
    foot:SetPoint("BOTTOMLEFT", 1, 1)
    foot:SetPoint("BOTTOMRIGHT", -1, 1)
    foot:SetHeight(FOOT_H)
    foot:SetVertexColor(0, 0, 0, UI.S.HEAD_BAND_A)
    local frule = Tex(sp, "BACKGROUND", -5)
    frule:SetHeight(1)
    frule:SetPoint("BOTTOMLEFT", foot, "TOPLEFT")
    frule:SetPoint("BOTTOMRIGHT", foot, "TOPRIGHT")
    frule:SetVertexColor(1, 1, 1, UI.S.HEAD_DIV_A)
    Place(sp.CloseButton, "BOTTOMRIGHT", sp, "BOTTOMRIGHT", -8, 8)
    Place(sp.OutputText, "LEFT", sp, "BOTTOMLEFT", 12, 19)
    PinText(sp.OutputText)

    -- Tabs on the sidebar under the title bar; the search box level with
    -- them over the settings side.
    Place(sp.GameTab, "TOPLEFT", sp, "TOPLEFT", 18, -(M.TITLEBAR + 8))
    if sp.SearchBox and sp.Container then
        Place(sp.SearchBox, "BOTTOMRIGHT", sp.Container, "TOPRIGHT", 0, 14)
        sp.SearchBox:SetHeight(22)
    end
end

-- The search box as UI.EditBox: a flat box, a gold edge while typing, the
-- hint in grey, ZacUI's X to clear. No magnifier - ZacUI's boxes have
-- none, and Blizzard's atlas icon read as a dark square on this skin.
local function SkinSearch(search)
    if not search then return end
    SkinEditBox(search)
    local icon = search.searchIcon or search.SearchIcon
    if icon then icon:SetAlpha(0) end
    search:SetTextInsets(6, 20, 0, 0)
    if search.Instructions then
        Place(search.Instructions, "TOPLEFT", search, "TOPLEFT", 6, 0)
        search.Instructions:SetPoint("BOTTOMRIGHT", search, "BOTTOMRIGHT", -20, 0)
        PinText(search.Instructions)
    end
    if search.clearButton then
        Fade(search.clearButton.Icon)
        SkinCloseButton(search.clearButton, 14)
    end
    search:HookScript("OnEditFocusGained", function(self)
        local a = Col("accent")
        ns.TintBorder(self, a.r, a.g, a.b, 1)
    end)
    search:HookScript("OnEditFocusLost", function(self) ns.TintBorder(self) end)
end

-- The page title over the settings list, as UI.PageHeader: gold, ZacUI's
-- header size, a gold rule under it in place of Blizzard's carved one.
local function SkinPageHeader(hd)
    if not hd then return end
    for _, r in ipairs({ hd:GetRegions() }) do
        if r.IsObjectType and r:IsObjectType("Texture") and AtlasOf(r) == "Options_HorizontalDivider" then
            r._zui_own = true
            r:SetTexture(FLAT)
            r:ClearAllPoints()
            r:SetHeight(1)
            r:SetPoint("BOTTOMLEFT", hd, "BOTTOMLEFT", 7, 6)
            r:SetPoint("BOTTOMRIGHT", hd, "BOTTOMRIGHT", -8, 6)
            r:SetVertexColor(1, 1, 1, UI.S.HEAD_DIV_A)
        end
    end
    FadeOptionsArt(hd)
    if hd.Title then
        ZFont(hd.Title, F.HEADER)
        PaintText(hd.Title, "text", "normal")
        Place(hd.Title, "TOPLEFT", hd, "TOPLEFT", 7, -20)
    end
    if hd.DefaultsButton then SkinButton(hd.DefaultsButton) end
end

local function SkinSettingsPanel(sp)
    if sp.NineSlice then sp.NineSlice:SetAlpha(0) end
    if sp.Bg then sp.Bg:SetAlpha(0) end
    SkinBackdrop(sp, "windowBg", 0.97)
    FadeOptionsArt(sp)
    BuildChrome(sp)
    SkinSearch(sp.SearchBox)
    SkinTab(sp.GameTab)
    SkinTab(sp.AddOnsTab)
    if sp.CloseButton then SkinButton(sp.CloseButton) end
    if sp.ApplyButton then SkinButton(sp.ApplyButton) end

    local cat = sp.CategoryList
    if cat then
        FadeOptionsArt(cat)
        HookList(cat.ScrollBox, SkinCategory)
    end
    -- The settings side sits straight on the window, as the config's
    -- content pane does; its sections carry the cards.
    local list = sp.Container and sp.Container.SettingsList
    if list then
        FadeOptionsArt(list)
        SkinPageHeader(list.Header)
        HookList(list.ScrollBox, SkinRowOnce, PaintCards)
    end
    -- Canvas pages are left alone: they are other addons' own option
    -- panels, built however each addon likes, and restyling a stranger's
    -- buttons is how a skin breaks someone else's UI.
end

Modules.options = function()
    if SettingsPanel and not ZUI.skinned[SettingsPanel] then
        ZUI.skinned[SettingsPanel] = true
        SkinSettingsPanel(SettingsPanel)
        -- Content builds lazily (each category page materializes on first
        -- visit), so the scrollbar sweep re-runs (idempotent) on every
        -- show, and so does the row pass for anything built off-screen.
        SettingsPanel:HookScript("OnShow", function(f)
            C_Timer.After(0, function()
                SkinAllScrollBarsUnder(f, 0)
                local l = f.Container and f.Container.SettingsList
                if l and l.ScrollBox then
                    EachFrame(l.ScrollBox, SkinRowOnce)
                    pcall(PaintCards, l.ScrollBox)
                end
                if f.CategoryList then EachFrame(f.CategoryList.ScrollBox, SkinCategory) end
            end)
        end)
        SkinAllScrollBarsUnder(SettingsPanel, 0)
    end
    -- Legacy pre-SettingsPanel windows (gone on 11509, present on older
    -- lineages). Explicit appends (hole-in-ipairs law): any one of them
    -- being nil mid-literal would skip the rest.
    local legacy = {}
    local function AddLegacy(f) if f then legacy[#legacy + 1] = f end end
    AddLegacy(VideoOptionsFrame)
    AddLegacy(InterfaceOptionsFrame)
    AddLegacy(AudioOptionsFrame)
    for _, f in ipairs(legacy) do
        SkinPanel(f)
    end
end

-- LoD PANELS
