-- Blz_GameMenu - the Esc menu, its buttons and the interface option shells.
-- Part of ZacUI; load order is set by the TOC.

local ADDON_NAME, ns = ...

-- shared state from earlier ZacUI files
local AddPixelBorder = ns.AddPixelBorder
local Col = ns.Col
local FLAT = ns.FLAT
local Modules = ns.Modules
local Print = ns.Print
local SkinButton = ns.SkinButton
local StripDeep = ns.StripDeep
local StripFrameChrome = ns.StripFrameChrome
local StripTextures = ns.StripTextures
local ZUI = ns.ZUI

Modules.gamemenu = function()
    if not GameMenuFrame then return end
    if GameMenuFrame.Border then GameMenuFrame.Border:SetAlpha(0) end
    StripFrameChrome(GameMenuFrame)

    -- The surviving "Blizzard default texture": Header/Border art lives
    -- partly on CHILD frames a single-level strip never reached. Deep-
    -- strip every non-Button child BEFORE creating any of our layers.
    -- 11509 exemptions: the "New!" feature chips and the Edit Mode
    -- notification are INFORMATION, not chrome - stripping them left
    -- invisible-but-clickable ghosts on the modern menu.
    local keepKids = {}
    keepKids[GameMenuFrame.EditModeNotification or false] = true
    keepKids[GameMenuFrame.NewOptionsFrame or false] = true
    keepKids[GameMenuFrame.NewExternalEventFrame or false] = true
    for _, child in ipairs({ GameMenuFrame:GetChildren() }) do
        if not keepKids[child]
            and not (child.IsObjectType and child:IsObjectType("Button")) then
            StripDeep(child, 0)
        end
    end
    StripTextures(GameMenuFrame)

    -- Background as an EXPLICIT texture, not SetBackdrop: this template's
    -- backdrop rendering has been unreliable all along, and the deep
    -- strips exposed it fully (the background vanished entirely). A
    -- texture created AFTER all strips cannot be touched by them.
    if not GameMenuFrame._zui_bg then
        local bg = GameMenuFrame:CreateTexture(nil, "BACKGROUND", nil, -8)
        bg:SetAllPoints()
        bg:SetTexture(FLAT)
        local w = Col("windowBg")
        bg:SetVertexColor(w.r, w.g, w.b, 0.97)
        GameMenuFrame._zui_bg = bg
        AddPixelBorder(GameMenuFrame)
    end

    -- HEADER BAR - one aligned unit, not three floating pieces. The
    -- v1.5.0 look (title adrift in dead space, hairline at a magic
    -- offset, band invisible behind it) read as arbitrary. Now: a 30px
    -- solid bar at the top, the title centered IN it, and the gold
    -- hairline sitting exactly on its bottom edge - everything anchored
    -- to the band, so no offset can ever drift.
    if not GameMenuFrame._zui_band then
        -- BORDER layer: BackdropTemplate draws its center fill in the
        -- BACKGROUND layer, which rendered OVER the first version of this
        -- band - it existed but was invisible. BORDER always sits above.
        local band = GameMenuFrame:CreateTexture(nil, "BORDER")
        band:SetPoint("TOPLEFT", GameMenuFrame, "TOPLEFT", 1, -1)
        band:SetPoint("TOPRIGHT", GameMenuFrame, "TOPRIGHT", -1, -1)
        band:SetHeight(30)
        -- THE house header color - the same palette key ZacUI's own
        -- window title bars wear, so the Esc menu and the AH/bag/config
        -- windows read as one family. (It used to be a bespoke darker
        -- mix, which is exactly the inconsistency that got reported.)
        band:SetTexture(FLAT)
        -- (2026-11-10, Zac: "literally every menu popup etc needs to
        -- match") the header ZacUI's own windows wear now: the window
        -- itself (the band is kept for the anchors, not drawn), the title
        -- in the light text, a white 8% rule
        local h = Col("headerBg")
        band:SetVertexColor(h.r, h.g, h.b, 0)
        GameMenuFrame._zui_band = band

        local line = GameMenuFrame:CreateTexture(nil, "OVERLAY", nil, 6)
        line._zui_own = true
        line:SetColorTexture(1, 1, 1, 0.08)
        line:SetPoint("TOPLEFT",  band, "BOTTOMLEFT",  0, 0)
        line:SetPoint("TOPRIGHT", band, "BOTTOMRIGHT", 0, 0)
        line:SetHeight(1)
    end

    local a = Col("text")
    if GameMenuFrame.Header then
        StripTextures(GameMenuFrame.Header)
        local htext = GameMenuFrame.Header.Text
        if not htext then
            for _, region in ipairs({ GameMenuFrame.Header:GetRegions() }) do
                if region.IsObjectType and region:IsObjectType("FontString") then
                    htext = region
                    break
                end
            end
        end
        if htext then
            htext:ClearAllPoints()
            htext:SetPoint("CENTER", GameMenuFrame._zui_band, "CENTER", 0, 0)
            htext:SetTextColor(a.r, a.g, a.b, 1)
        end
    end
    for _, region in ipairs({ GameMenuFrame:GetRegions() }) do
        if region.IsObjectType and region:IsObjectType("FontString") then
            region:SetTextColor(a.r, a.g, a.b, 1)
        end
    end

    -- ============================================================
    -- THE BUTTONS
    -- ============================================================
    -- The menu is a VerticalLayoutFrame over a button pool: Blizzard
    -- releases and re-acquires every button on each open (InitButtons),
    -- so everything below runs as an InitButtons post-hook, every time,
    -- and every per-button look is re-decided rather than remembered.
    --   * ZacUI's font and colours, a faint rule in each section gap
    --   * Return to Game is the primary button (green), Log Out and Exit
    --     Game warn red under the mouse, disabled buttons look disabled
    --   * ZacUI's and Readycheck's settings sit in a strip under the menu
    --
    -- LOOK ONLY, NEVER LAYOUT. Escape opens the menu through Blizzard's
    -- secure panel code, and that code reads the menu's own tables on the
    -- way: the button pool, each button's layout fields, the frame's
    -- spacing and paddings. This file used to write to all of them -
    -- AddButton for its two entries, new spacing, paddings and section
    -- gaps - and a value an addon writes is tainted: the next open read
    -- it and ran tainted from there on. That is the likely reason the
    -- menu would not open in combat, where a tainted open is refused,
    -- and it is certainly why "Log Out" came out tainted (BugSack had
    -- 'Zacui' blocked calling CancelLogout from the logout countdown).
    -- So nothing here writes a field Blizzard reads, or calls a method
    -- that does: textures, fonts and colours only, which live in the
    -- client, not in Lua tables. Our two entries are our own buttons on
    -- our own strip.
    local BTN_H, GAP = 26, 4
    local GetColor = ns.GetColor
    local TintBorder = ns.TintBorder
    local dividers = {}

    local function FontFor(fs)
        ns.HouseFont(fs, 12)
    end

    local function RoleOf(text)
        if text == RETURN_TO_GAME then return "primary" end
        if text == LOG_OUT or text == LOGOUT or text == EXIT_GAME then return "danger" end
        return nil
    end

    local function Paint(b)
        local fs = b._zui_fs or (b.GetFontString and b:GetFontString())
        local enabled = b:IsEnabled()
        -- (2026-11-10) the one button look (UIF_Base SkinButton's plate):
        -- the main button keeps the accent, a switched-off one is dim
        if b._zui_plate and b._zPaint then
            b._zActive = (b._zRole == "primary" and enabled) or nil
            b._zDisabled = (not enabled) or nil
            b._zHot, b._zP = nil, 0
            b:_zPaint()
            return
        end
        local bgKey = (b._zRole == "primary") and "activeBg" or "buttonBg"
        b._zui_bgKey = bgKey
        local c = Col(enabled and bgKey or "buttonBg")
        if b._zui_bg then b._zui_bg:SetVertexColor(c.r, c.g, c.b, enabled and 1 or 0.5) end
        if TintBorder then
            if b._zRole == "primary" and enabled then
                local g = Col("borderSelected")
                TintBorder(b, g.r, g.g, g.b, 1)
            else
                TintBorder(b)
            end
        end
        if fs then
            local t
            if not enabled then t = GetColor("text", "disabled")
            elseif b._zRole == "primary" then t = Col("textGreen")
            else t = Col("text") end
            fs:SetTextColor(t.r, t.g, t.b, 1)
        end
    end

    -- Hover, re-attached on every open: Blizzard's AddButton does
    -- SetScript("OnEnter"/"OnLeave", nil) on each button it acquires,
    -- which throws away any hook - this is why the old skin's hover
    -- stopped working after the first time the menu was opened.
    local function OnEnter(self)
        if not self:IsEnabled() then return end
        if self._zui_plate and self._zPaint then
            -- (Blizzard clears the scripts on every open, the plate's hover
            -- fade with them: lit at once here)
            self._zHot, self._zP = true, 1
            self:_zPaint()
            if self._zRole == "danger" and self._zui_fs then
                local t = GetColor("text", "red")
                self._zui_fs:SetTextColor(t.r, t.g, t.b, 1)
            end
            return
        end
        local h = Col("hoverBg")
        if self._zui_bg then self._zui_bg:SetVertexColor(h.r, h.g, h.b, 1) end
        local fs = self._zui_fs
        if fs then
            local t = (self._zRole == "danger") and GetColor("text", "red") or Col("accent")
            fs:SetTextColor(t.r, t.g, t.b, 1)
        end
    end

    local function StyleButton(b)
        if not ZUI.skinned[b] then
            SkinButton(b, "buttonBg", "hoverBg")
        end
        if not b._zMenuHooked then
            -- OnEnable / OnDisable are never reset by Blizzard: once.
            b._zMenuHooked = true
            b:HookScript("OnEnable", Paint)
            b:HookScript("OnDisable", Paint)
        end
        b:HookScript("OnEnter", OnEnter)
        b:HookScript("OnLeave", Paint)
        local fs = b._zui_fs or (b.GetFontString and b:GetFontString())
        b._zui_fs = fs
        if fs then FontFor(fs) end
        b._zRole = RoleOf(b:GetText())
        Paint(b)
    end

    -- A faint rule in each section gap, drawn from a small pool.
    local function Divider(i)
        local d = dividers[i]
        if not d then
            d = GameMenuFrame:CreateTexture(nil, "ARTWORK")
            d._zui_own = true
            d:SetTexture(FLAT)
            d:SetHeight(1)
            dividers[i] = d
        end
        local c = Col("border")
        d:SetVertexColor(c.r, c.g, c.b, 1)
        return d
    end

    -- ZacUI's and Readycheck's settings: two buttons of ours on a strip
    -- of ours, hanging under the menu. Parented to the menu, so they come
    -- and go with it, and nothing of Blizzard's is touched to place them.
    local strip
    local function OurStrip(frame)
        if strip then return end
        local entries = {}
        if ns.OpenConfig then
            entries[#entries + 1] = { "ZacUI", function() ns.OpenConfig() end }
        end
        entries[#entries + 1] = { "Readycheck", function()
            local rc = SlashCmdList and SlashCmdList["WARRIORREMINDER"]
            if rc then rc("") end
        end, needs = function() return SlashCmdList and SlashCmdList["WARRIORREMINDER"] end }
        strip = CreateFrame("Frame", nil, frame)
        strip:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -GAP)
        strip:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 0, -GAP)
        strip:SetHeight(BTN_H + 12)
        local bg = strip:CreateTexture(nil, "BACKGROUND", nil, -8)
        bg:SetAllPoints()
        bg:SetTexture(FLAT)
        local w = Col("windowBg")
        bg:SetVertexColor(w.r, w.g, w.b, 0.97)
        AddPixelBorder(strip)
        strip.buttons = {}
        for i, e in ipairs(entries) do
            local b = CreateFrame("Button", nil, strip)
            b:SetNormalFontObject("GameFontHighlight")
            b:SetText(e[1])
            b:SetHeight(BTN_H)
            SkinButton(b, "buttonBg", "hoverBg")
            local fs = b:GetFontString()
            if fs then FontFor(fs) end
            b:SetScript("OnClick", function()
                PlaySound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION or 852)
                -- Out of combat the menu closes as it always has. In
                -- combat an addon may not drive the panel manager, so the
                -- menu stays and the window opens over it.
                if not InCombatLockdown() and HideUIPanel then HideUIPanel(frame) end
                e[2]()
            end)
            b.needs = e.needs
            strip.buttons[i] = b
        end
        local function Place()
            local shown = {}
            for _, b in ipairs(strip.buttons) do
                local on = not b.needs or b.needs()
                b:SetShown(on and true or false)
                if on then shown[#shown + 1] = b end
            end
            local n = #shown
            local inner = (strip:GetWidth() or 0) - 12 - (n - 1) * GAP
            for i, b in ipairs(shown) do
                b:ClearAllPoints()
                b:SetWidth(math.max(40, math.floor(inner / math.max(1, n))))
                if i == 1 then
                    b:SetPoint("LEFT", strip, "LEFT", 6, 0)
                else
                    b:SetPoint("LEFT", shown[i - 1], "RIGHT", GAP, 0)
                end
            end
            -- only on a change: Place also runs from the strip's OnShow
            if (strip:IsShown() and true or false) ~= (n > 0) then strip:SetShown(n > 0) end
        end
        strip.Place = Place
        strip:SetScript("OnSizeChanged", Place)
        strip:SetScript("OnShow", Place)
    end

    -- The header band sits in the room above the first button, however
    -- much room Blizzard's layout left there. Measured once the menu is
    -- laid out, which is after InitButtons returns.
    local function FitBand(frame)
        local band = frame._zui_band
        if not (band and frame.buttonPool and frame:IsShown()) then return end
        local top, first = frame:GetTop(), nil
        for b in frame.buttonPool:EnumerateActive() do
            local t = b:IsShown() and b:GetTop()
            if t and (not first or t > first) then first = t end
        end
        if top and first then
            band:SetHeight(math.max(16, math.min(30, math.floor(top - first) - 6)))
        end
    end

    local function StyleMenu(frame)
        if not frame.buttonPool then return end
        -- Blizzard's own section gaps (read, never written) get a rule.
        local used = 0
        for b in frame.buttonPool:EnumerateActive() do
            local gap = b.topPadding
            if type(gap) == "number" and gap > 0 then
                used = used + 1
                local d = Divider(used)
                local mid = math.floor(gap / 2)
                d:ClearAllPoints()
                d:SetPoint("BOTTOMLEFT", b, "TOPLEFT", 6, mid)
                d:SetPoint("BOTTOMRIGHT", b, "TOPRIGHT", -6, mid)
                d:Show()
            end
            StyleButton(b)
        end
        for i = used + 1, #dividers do dividers[i]:Hide() end
        OurStrip(frame)
        if strip and strip.Place then strip.Place() end
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function() FitBand(frame) end)
        end
    end

    -- The header text in the house font, size and colour.
    if GameMenuFrame.Header then
        local htext = GameMenuFrame.Header.Text
        if htext and htext.GetFont then
            ns.HouseFont(htext, 14)
        end
    end

    if type(GameMenuFrame.InitButtons) == "function" then
        -- Post-hook the rebuild itself: catches OnShow AND the event-
        -- driven re-inits (store / trial status) that never fire OnShow.
        hooksecurefunc(GameMenuFrame, "InitButtons", function(frame)
            StyleMenu(frame)
        end)
    end
    if GameMenuFrame:IsShown() then StyleMenu(GameMenuFrame) end
end

-- MAILBOX
