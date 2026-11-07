-- Config_PagesStyle - the Font and Colours pages.
-- Part of ZacUI; load order is set by the TOC.

local ADDON_NAME, ns = ...

-- shared state from earlier ZacUI files
local ApplyFonts = ns.ApplyFonts
local GetColor = ns.GetColor
local PALETTE_KEYS = ns.PALETTE_KEYS
local PALETTE_ORDER = ns.PALETTE_ORDER
local Print = ns.Print
local RefreshConfig = ns.RefreshConfig
local RegisterPage = ns.RegisterPage
local ResetAllColors = ns.ResetAllColors
local ResetColor = ns.ResetColor
local UI = ns.UI
local ColorLabel = ns.ColorLabel
local Media = ns.Media
local ResolveFontPath = ns.ResolveFontPath

local M, F = UI.M, UI.F

local BLIZZARD_FONT = "Fonts\\FRIZQT__.TTF"

local function LSM()
    return LibStub and LibStub("LibSharedMedia-3.0", true)
end

-- ============================================================
-- FONT PREVIEW
-- ============================================================
-- Text in the three roles ZacUI's own windows use, and a bar in the
-- chosen texture: exactly what UI.Font and the skinned bars draw, from
-- the same three settings (face, size adjustment, outline).
local SAMPLES = {
    { text = "The quick brown fox jumps over the lazy dog  0123456789", size = F.LABEL },
    { text = "Card heading", size = F.CARD, cat = "text", key = "gold" },
    { text = "Muted description text", size = F.DESC, cat = "text", key = "gray" },
}

-- Wide and short for the preview strip: the long line across the top,
-- then the heading, the description and the bar side by side.
local FONT_PV_W, FONT_PV_H = 500, 58
local FONT_PV_SPOTS = { { 10, -9, 480 }, { 10, -34, 120 }, { 138, -35, 170 } }

local function BuildFontPreview(canvas, P)
    local st = P.store
    st.lines = {}
    for i, s in ipairs(SAMPLES) do
        local spot = FONT_PV_SPOTS[i]
        local fs = UI.Font(canvas, s.size, { text = s.text, cat = s.cat, key = s.key,
            width = spot[3], wrap = false })
        fs:SetPoint("TOPLEFT", canvas, "TOPLEFT", spot[1], spot[2])
        st.lines[i] = fs
    end
    local bar = CreateFrame("StatusBar", nil, canvas)
    bar:SetSize(172, 16)
    bar:SetPoint("TOPLEFT", canvas, "TOPLEFT", 318, -33)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0.72)
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg._zui_own = true
    bar.bg:SetAllPoints()
    UI.Border(bar, "ui", "border")
    st.bar = bar
end

local function UpdateFontPreview(canvas, P)
    local st = P.store
    local cfg = ZacUIDB.font or {}
    local path = ResolveFontPath(cfg.name)
        or (GameFontNormal and GameFontNormal.GetFont and GameFontNormal:GetFont())
        or BLIZZARD_FONT
    local flags = (cfg.outline == "NONE") and "" or "OUTLINE"
    for i, s in ipairs(SAMPLES) do
        local fs = st.lines[i]
        local ok, set = pcall(fs.SetFont, fs, path, s.size + (cfg.delta or 0), flags)
        if not (ok and set) then
            pcall(fs.SetFont, fs, BLIZZARD_FONT, s.size + (cfg.delta or 0), flags)
        end
        fs:_zPaint()
    end
    local tex = Media and Media.BarPath() or ns.TEX_NORM
    local a = GetColor("ui", "accent")
    st.bar:SetStatusBarTexture(tex)
    st.bar:SetStatusBarColor(a.r, a.g, a.b, 1)
    -- a darker stretch, so a gradient's two ends can be told apart
    st.bar.bg:SetTexture(tex)
    st.bar.bg:SetVertexColor(a.r * 0.25, a.g * 0.25, a.b * 0.25, 1)
    UI.PaintBox(st.bar)
end

-- ============================================================
-- FONT
-- ============================================================
RegisterPage("Font", function(L)
    L:Header("Fonts & Textures",
        "One font and one bar texture for the whole UI. The font is every "
        .. "text's, everywhere; 'Where it goes' picks which parts take the texture.")

    L:Preview({
        key = "appearance.font",
        title = "Font and bar texture",
        width = FONT_PV_W, height = FONT_PV_H,
        build = BuildFontPreview,
        update = UpdateFontPreview,
    })

    local function Tab_font()
        L:Card("Typeface")
        local media = LSM()
        -- each font in the list is drawn in itself; only SharedMedia's
        -- names are offered, the ones the global font can resolve
        local dd = UI.FontFaceDropdown(L.current, {
            width = 240,
            defaultLabel = "Blizzard default",
            defaultPath = function() return BLIZZARD_FONT end,
            list = function() local m = LSM() return m and m:List("font") or {} end,
            get = function()
                local n = ZacUIDB.font.name
                return (n and n ~= "") and n or nil
            end,
            set = function(value)
                if Media then Media.SetFont(value) else
                    ZacUIDB.font.name = value
                    ApplyFonts()
                end
                RefreshConfig()
            end,
        })
        L:Row(dd, M.DROPDOWN_H + 6)
        if not media then
            L:Desc("LibSharedMedia is not installed, so only the Blizzard default "
                .. "is listed. You can still point ZacUI at any font file with "
                .. "/zacui font <path>.")
        end
        L:EndCard()

        L:Card("Size and weight")
        -- A DELTA, not an absolute size. Blizzard's font objects range from 9pt
        -- to 32pt; forcing them all to one number flattens the type hierarchy
        -- and makes zone names the same size as tooltip body text.
        local slider = UI.Slider(L.current, {
            width = 220, min = -3, max = 6, step = 1,
            value = ZacUIDB.font.delta or 0,
            label = "Size adjustment",
            format = function(v) return (v > 0 and "+" or "") .. v end,
            onChange = function(v)
                ZacUIDB.font.delta = v
                ApplyFonts()
            end,
        })
        L:Row(slider, 40)
        L:Desc("Shifts every font object relative to its stock size, so the "
            .. "difference between a header and body text is preserved.")
        L:Gap(4)

        -- nil means "not chosen yet", and every text path in ZacUI treats that
        -- as outlined. Testing == "OUTLINE" made a fresh install show an
        -- unticked box over visibly outlined text.
        local outline = UI.Checkbox(L.current, "Outlined text",
            ZacUIDB.font.outline ~= "NONE",
            function(checked)
                ZacUIDB.font.outline = checked and "OUTLINE" or "NONE"
                ApplyFonts()
                RefreshConfig()
            end)
        L:Row(outline, 17)
        L:Desc("Outlines keep text legible over the world and over bright bar "
            .. "textures. Turn it off for a softer look on dark panels only.")
        L:EndCard()
    end

    local function Tab_texture()
        -- ------------------------------------------------------------
        -- BAR TEXTURE
        -- ------------------------------------------------------------
        if Media then
            L:Card("Status bar texture")
            -- every texture in the list shows a stretch of itself; the
            -- full-size sample is in the preview
            local barDD = UI.TexturePicker(L.current, {
                width = 240,
                defaultLabel = "ZacUI default (gradient)",
                defaultPath = function() return ns.TEX_NORM end,
                list = function() return Media.ListBars() end,
                get = function() return Media.BarName() end,
                set = function(value)
                    Media.SetBar(value)
                    RefreshConfig()
                end,
            })
            L:Row(barDD, M.DROPDOWN_H + 6)
            L:Desc("The fill of every HEALTH, POWER, CAST and METER bar: unit frames, "
                .. "nameplates, the meter, the HUD, loot rolls, the tooltip health bar "
                .. "and the Blizzard frames ZacUI skins. Not the action bars - how "
                .. "buttons look lives under Action bars. Bars already on screen "
                .. "change at once; a bar skinned at login that is not up right now "
                .. "takes it when it next appears.")
            L:EndCard()
        end
    end

    local function Tab_where()
        -- ------------------------------------------------------------
        -- WHERE IT GOES
        -- ------------------------------------------------------------
        if Media then
            L:Card("Where it goes")
            L:Desc("Every text ZacUI draws - every part, every aura, every skinned "
                .. "Blizzard frame - and Readycheck's too, is in the font above, always. "
                .. "These keep a bar texture of their own and are handed the one above "
                .. "whenever you change it, while ticked. Un-tick one to set its texture "
                .. "by hand on its own page.")
            L:Gap(2)
            local manual = {}
            for _, t in ipairs(Media.Targets()) do
                if t.manual then
                    manual[#manual + 1] = t
                else
                    local here = (not t.available) or t.available()
                    local label = t.label .. (here and "" or "  (not loaded)")
                    local cb = UI.Checkbox(L.current, label, Media.TargetOn(t.key), function(on)
                        Media.SetTargetOn(t.key, on)
                        if on then Media.Apply(t.key) end
                    end)
                    if not here and cb.SetAlpha then cb:SetAlpha(0.5) end
                    L:Row(cb, 17)
                    if t.desc then L:Desc(t.desc) end
                end
            end
            L:Gap(4)
            local applyBtn = UI.Button(L.current, "Apply to ticked now", {
                width = 170,
                tooltip = "Pushes the current font and texture into every ticked target again.",
                onClick = function()
                    local n = Media.Apply()
                    Print(("media: pushed to %d target%s."):format(n, n == 1 and "" or "s"))
                end,
            })
            L:Row(applyBtn, M.BUTTON_H + 6)
            for _, t in ipairs(manual) do
                local here = (not t.available) or t.available()
                local btn = UI.Button(L.current, "Texture into auras...", {
                    width = 170,
                    tooltip = t.desc,
                    onClick = function()
                        UI.Confirm({
                            title = "Texture into auras",
                            text = "Set the texture of every bar in ALL your auras to the choice "
                                .. "above? Each aura's saved data is edited; there is no undo short "
                                .. "of re-importing. (Their texts already use ZacUI's font.)",
                            acceptText = "Push",
                            onAccept = function()
                                local ok, err = Media.PushAuras(function(c, n)
                                    Print(("auras: %d of %d updated."):format(c, n))
                                end)
                                if not ok then Print("auras: " .. tostring(err)) end
                            end,
                        })
                    end,
                })
                if not here then btn:SetDisabled(true) end
                L:Row(btn, M.BUTTON_H + 6)
                L:Desc(t.desc .. (here and "" or "  Not loaded right now."))
            end
            L:EndCard()
        end
    end

    L:Tabs({
        { id = "font", label = "Font", build = Tab_font },
        { id = "texture", label = "Bar texture", build = Tab_texture },
        { id = "where", label = "Where it goes", build = Tab_where },
    })
end)

-- ============================================================
-- COLOURS
-- ============================================================
RegisterPage("Colors", function(L)
    L:Header("Colours",
        "Every colour ZacUI paints, grouped by what it paints. Click a "
        .. "swatch to change it.")

    L:Card("What updates immediately")
    L:Desc("ZacUI's own windows - this one included - repaint as you pick. "
        .. "Skinned Blizzard frames do not: skinning strips their artwork, "
        .. "and there is no way to un-strip it. Those pick up new colours on "
        .. "the next reload.")
    local row = UI.Holder(L.current)
    row:SetSize(340, M.BUTTON_H)
    local reload = UI.Button(row, "Reload UI", { width = 100, onClick = function()
        if type(ReloadUI) == "function" then ReloadUI()
        elseif C_UI and C_UI.Reload then C_UI.Reload() end
    end })
    reload:SetPoint("LEFT")
    local resetAll = UI.Button(row, "Reset all colours", { width = 140,
        onClick = function()
            UI.Confirm({
                title = "Reset colours",
                text = "Every colour goes back to the shipped palette. "
                    .. "Other settings are untouched.",
                acceptText = "Reset colours",
                destructive = true,
                onAccept = function()
                    ResetAllColors()
                    RefreshConfig()
                    Print("Colours reset - reload to repaint skinned frames.")
                end,
            })
        end })
    resetAll:SetPoint("LEFT", reload, "RIGHT", 8, 0)
    L:Row(row, M.BUTTON_H + 4)
    L:EndCard()

    for _, cat in ipairs(PALETTE_ORDER) do
        L:Card(cat.label)
        -- the Reset buttons and hex values in one column, right of the
        -- longest name in the card (never at a fixed x a bigger font runs into)
        local rows = {}
        local nameW = 0
        for _, key in ipairs(PALETTE_KEYS[cat.key] or {}) do
            local line = UI.Holder(L.current)

            -- LIGHT repaint, not RefreshConfig. The colour picker calls
            -- this on every change while it is open, and a full page
            -- rebuild per tick orphans thousands of frames - and unparents
            -- the very swatch whose closure is driving the drag.
            local sw = UI.Swatch(line, cat.key, key, function()
                local win = _G.ZacUIConfigFrame
                if win then UI.Repaint(win) end
            end)
            sw:SetPoint("LEFT")

            local label = UI.Font(line, F.LABEL, { text = ColorLabel(key) })
            label:SetPoint("LEFT", sw, "RIGHT", 10, 0)
            nameW = math.max(nameW, math.ceil(label:GetStringWidth() or 0))
            rows[#rows + 1] = { line = line, sw = sw, key = key }
        end
        for _, r in ipairs(rows) do
            local line, key = r.line, r.key
            local x = (r.sw:GetWidth() or 16) + 10 + nameW + 14
            -- Per-swatch reset. Resetting one colour without losing the
            -- other twenty is the whole reason this is here.
            local rst = UI.Button(line, "Reset", { width = 56, height = 16,
                size = F.SMALL,
                onClick = function()
                    ResetColor(cat.key, key)
                    RefreshConfig()   -- one-shot, so the hex readout updates
                end })
            rst:SetPoint("LEFT", x, 0)

            local hexed = GetColor(cat.key, key)
            local hex = UI.Font(line, F.SMALL, {
                text = string.format("%02X%02X%02X",
                    (hexed.r or 0) * 255, (hexed.g or 0) * 255, (hexed.b or 0) * 255),
                cat = "text", key = "gray" })
            hex:SetPoint("LEFT", rst, "RIGHT", 14, 0)
            local hexW = math.ceil(hex:GetStringWidth() or 40)
            local w = x + 56 + 14 + hexW
            -- a narrow window with big text: the hex value moves into the
            -- Reset button's tooltip rather than past the card
            if w > L:Room() + 0.5 then
                hex:Hide()
                w = x + 56
                UI.Tooltip(rst, "Reset", "Back to the shipped colour. Now #" .. (hex:GetText() or "") .. ".")
            end
            line:SetSize(w, math.max(16, math.ceil(r.sw:GetHeight() or 16)))

            L:Row(line, 20)
        end
        L:EndCard()
    end
end)
