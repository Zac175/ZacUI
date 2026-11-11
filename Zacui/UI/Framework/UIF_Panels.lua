-- UIF_Panels - the panel entry point, its inset/line calibration, and
-- the dark-text lifting machinery that keeps parchment pages readable.
-- Part of ZacUI; load order is set by the TOC.

local ADDON_NAME, ns = ...

-- shared state from earlier ZacUI files
local AccentTitle = ns.AccentTitle
local Col = ns.Col
local ColSafe = ns.ColSafe
local FLAT = ns.FLAT
local SkinBackdrop = ns.SkinBackdrop
local SkinBottomTabs = ns.SkinBottomTabs
local SkinButton = ns.SkinButton
local SkinCloseButton = ns.SkinCloseButton
local StripFrameChrome = ns.StripFrameChrome
local StripTextures = ns.StripTextures
local ZUI = ns.ZUI

-- ============================================================
-- PANEL INSETS + HEADER LINE DEPTH (with live calibration)
-- ============================================================
local CLASSIC_INSET = { l = 11, r = 32, t = 12, b = 74 }
local PANEL_INSETS = {
    QuestLogFrame   = CLASSIC_INSET,
    CharacterFrame  = CLASSIC_INSET,
    SpellBookFrame  = CLASSIC_INSET,
    FriendsFrame    = CLASSIC_INSET,
    TradeFrame      = CLASSIC_INSET,
    -- Quest/Gossip: Blizzard anchors the Accept/Decline/Complete row to
    -- the FRAME bottom; the generic b=74 stopped the dark panel above
    -- them ("buttons outside the UI"). Live-calibrate: /zacui inset.
    -- b=74 cut the buttons off; b=12 ran way past the content. The true
    -- art bottom varies by build - dial it live in seconds with
    -- /zacui inset QuestFrame 11 32 12 <b> (it saves).
    GossipFrame     = { l = 11, r = 32, t = 12, b = 42 },
    QuestFrame      = { l = 11, r = 32, t = 12, b = 42 },
    TalentFrame     = CLASSIC_INSET,
    TradeSkillFrame = CLASSIC_INSET,
    CraftFrame      = CLASSIC_INSET,
    LootFrame       = { l = 10, r = 10, t = 12, b = 10 },
    AuctionFrame    = { l = 11, r = 32, t = 12, b = 74 },
    PlayerTalentFrame = { l = 11, r = 32, t = 12, b = 74 },
    -- Classic 384x512 art shells with no NineSlice: without a preset they
    -- fell to a zero inset and the panel filled the transparent margin
    -- (Blizzard's own hit-rect insets: bank r30/b70, trainer r34/b75).
    BankFrame         = { l = 11, r = 32, t = 12, b = 70 },
    ClassTrainerFrame = CLASSIC_INSET,
    InspectFrame      = CLASSIC_INSET,
}
local PANEL_LINES = {
    CharacterFrame = -46,
    InspectFrame   = -46,   -- same shell and name plate as CharacterFrame
}

-- Resolution order: user override > modern-template auto-detect (zero) >
-- classic preset > zero. Modern ButtonFrameTemplate windows (detected by
-- their NineSlice) align at the FULL rect - applying a classic inset to
-- one (FriendsFrame was filed that way) shoves the panel 11px right and
-- 74px short: the "misaligned background". Classic-art frames have no
-- NineSlice, so their presets still apply. /zacui inset overrides all.
local function GetPanelInset(name, frame)
    local o = ZacUIDB and ZacUIDB.insets and name and ZacUIDB.insets[name]
    if o then return o end
    if frame and frame.NineSlice then
        return { l = 0, r = 0, t = 0, b = 0 }
    end
    return (name and PANEL_INSETS[name]) or { l = 0, r = 0, t = 0, b = 0 }
end

local function GetPanelLineY(name, fallback)
    local o = ZacUIDB and ZacUIDB.lines and name and ZacUIDB.lines[name]
    if o then return o end
    return (name and PANEL_LINES[name]) or fallback or -24
end

local function AnchorPanel(panel, frame, ins)
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT",     frame, "TOPLEFT",     ins.l or 0, -(ins.t or 0))
    panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -(ins.r or 0), ins.b or 0)
end

-- PARCHMENT FONT RECOLOR (quest/book/letter fonts are dark-on-parchment)
local parchmentRecolored = false
-- FONT-OBJECT PINS - the level the fight was actually at. Blizzard's
-- quest MATERIAL system re-blackens the parchment FONT OBJECTS on every
-- quest page open; a one-time recolor loses every subsequent open, while
-- per-string pins only protected the strings they were on - grey islands
-- in re-blackened text. Pin the objects: whatever writes dark to them,
-- by any caller, flips to palette in the same call.
local function PinFontObject(obj, key, fr, fg, fb)
    if not obj or obj._zui_fontPinned or not obj.SetTextColor then return end
    obj._zui_fontPinned = true
    local c = ColSafe(key, fr, fg, fb)
    obj:SetTextColor(c.r, c.g, c.b, 1)
    hooksecurefunc(obj, "SetTextColor", function(self, nr, ng, nb)
        if self._zui_repin then return end
        if nr and ng and nb and nr < 0.35 and ng < 0.35 and nb < 0.35 then
            self._zui_repin = true
            local cc = ColSafe(key, fr, fg, fb)
            self:SetTextColor(cc.r, cc.g, cc.b, 1)
            self._zui_repin = nil
        end
    end)
end

local function RecolorParchmentFonts()
    if parchmentRecolored then return end
    parchmentRecolored = true
    -- Explicit appends, not a table literal (hole-in-ipairs law): any of
    -- these font objects going nil on a build would silently un-pin every
    -- entry after the hole.
    local objs = {}
    local function AddObj(o) if o then objs[#objs + 1] = o end end
    AddObj(QuestFont)
    AddObj(QuestFontNormalSmall)
    AddObj(ItemTextFontNormal)
    AddObj(QuestFontHighlight)
    AddObj(QuestFontNormalHuge)
    AddObj(QuestFontLeft)
    for _, obj in ipairs(objs) do
        PinFontObject(obj, "text", 0.92, 0.92, 0.92)
    end
    PinFontObject(QuestTitleFont, "accent", 1, 0.82, 0)
    PinFontObject(QuestTitleFontBlackShadow, "accent", 1, 0.82, 0)
end

-- GENERIC DARK-TEXT LIFTER: Blizzard sets per-string black in updaters
-- faster than names can be enumerated. Walk a panel's FontStrings and
-- lift anything genuinely dark (r,g,b all < 0.35) to palette text -
-- named or not, present or future.
-- METHOD-LEVEL TEXT PIN: five rounds of lift sweeps lost the timing war
-- against Blizzard's per-string color writes. The pin ends it - a
-- SetTextColor post-hook on the string itself: whatever writes a dark
-- color, by any name, at any moment, flips to palette in the same call.
-- Reentry-guarded; one hook per string, ever.
local function PinTextLight(fs)
    if not fs or fs._zui_textPinned or not fs.SetTextColor then return end
    fs._zui_textPinned = true
    local tc = ColSafe("text", 0.92, 0.92, 0.92)
    local r, g, b = fs:GetTextColor()
    if r and r < 0.35 and g < 0.35 and b < 0.35 then
        fs:SetTextColor(tc.r, tc.g, tc.b)
    end
    hooksecurefunc(fs, "SetTextColor", function(self, nr, ng, nb)
        if self._zui_repin then return end
        if nr and ng and nb and nr < 0.35 and ng < 0.35 and nb < 0.35 then
            self._zui_repin = true
            local c = ColSafe("text", 0.92, 0.92, 0.92)
            self:SetTextColor(c.r, c.g, c.b)
            self._zui_repin = nil
        end
    end)
    -- INLINE ESCAPE CLEANER: the ground-truth case - GetTextColor says
    -- 0.9 grey, screen says pitch black - means the blackness rides
    -- INSIDE the text as |cffRRGGBB escapes, which no SetTextColor can
    -- override. Rewrite near-black escapes to palette on every SetText.
    local function CleanEscapes(self, txt)
            if self._zui_retext or type(txt) ~= "string" then return end
            if not txt:find("|c", 1, true) then return end
            local c = ColSafe("text", 0.92, 0.92, 0.92)
            local hex = string.format("%02x%02x%02x",
                c.r * 255, c.g * 255, c.b * 255)
            local fixed = txt:gsub("|c[fF][fF](%x%x)(%x%x)(%x%x)",
                function(r2, g2, b2)
                    if tonumber(r2, 16) < 48 and tonumber(g2, 16) < 48
                        and tonumber(b2, 16) < 48 then
                        return "|cff" .. hex
                    end
                    return "|cff" .. r2 .. g2 .. b2
                end)
            if fixed ~= txt then
                self._zui_retext = true
                self:SetText(fixed)
                self._zui_retext = nil
            end
    end
    if fs.SetText then
        hooksecurefunc(fs, "SetText", CleanEscapes)
    end
    if fs.SetFormattedText then
        hooksecurefunc(fs, "SetFormattedText", function(self)
            if self._zui_retext then return end
            CleanEscapes(self, self.GetText and self:GetText())
        end)
    end
end

-- NORMALIZE: render-vs-report cases (string says 0.9, screen says black)
-- leave three physical channels - the alpha chain, a shadow-only render,
-- and escapes inside the text. Close all three on every visible string;
-- force color only when dark so reward-quality colors survive.
local function NormalizeText(fs, forceColor)
    if not fs then return end
    PinTextLight(fs)
    if fs.SetAlpha then fs:SetAlpha(1) end
    if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, 0.9) end
    if forceColor then
        local c = ColSafe("text", 0.92, 0.92, 0.92)
        fs:SetTextColor(c.r, c.g, c.b)
    end
    local txt = fs.GetText and fs:GetText()
    if txt and txt:find("|c", 1, true) and not fs._zui_retext then
        -- NO reentry flag around this SetText: setting _zui_retext here
        -- made the pinned escape cleaner early-return - the re-route this
        -- call exists for never ran, and only the 000000 fallback below
        -- ever fired. The cleaner sets its own guard when it rewrites, so
        -- this bare SetText is recursion-safe by construction.
        fs:SetText(txt)  -- routes through the pinned escape cleaner
        local t2 = fs:GetText()
        if t2 == txt and txt:find("|c[fF][fF]0000") then
            fs:SetText(txt:gsub("|c[fF][fF]000000", "|r"))
        end
    end
end

local function LiftDarkText(root, depth)
    if not root or (depth or 0) > 6 then return end
    local tc = ColSafe("text", 0.92, 0.92, 0.92)
    -- SimpleHTML: some quest/book text renders through an HTML widget
    -- with PER-TAG colors - it ignores everything FontString-related and
    -- defaults black. The renderer no FontString pass could ever touch.
    if root.IsObjectType and root:IsObjectType("SimpleHTML") then
        for _, tag in ipairs({ "p", "h1", "h2", "h3" }) do
            pcall(root.SetTextColor, root, tag, tc.r, tc.g, tc.b)
        end
    end
    if root.GetRegions then
        for _, region in ipairs({ root:GetRegions() }) do
            if region.IsObjectType and region:IsObjectType("FontString") then
                local r, g, b = region:GetTextColor()
                NormalizeText(region, r and r < 0.35 and g < 0.35 and b < 0.35)
            end
        end
    end
    if root.GetChildren then
        for _, child in ipairs({ root:GetChildren() }) do
            LiftDarkText(child, (depth or 0) + 1)
        end
    end
end

-- QUEST STRING RECOLOR (Blizzard sets per-string black in its updaters)
local function RecolorObjectiveString(fs)
    if not fs or not fs.GetTextColor then return end
    local tc = Col("text")
    local r, g, b = fs:GetTextColor()
    if r < 0.3 and g < 0.3 and b < 0.3 then
        fs:SetTextColor(tc.r, tc.g, tc.b)
    elseif r < 0.7 and g < 0.7 and b < 0.7 then
        fs:SetTextColor(tc.r * 0.55, tc.g * 0.55, tc.b * 0.55)
    end
end

local function RecolorQuestLogStrings()
    for i = 1, 30 do
        RecolorObjectiveString(_G["QuestLogObjective" .. i])
    end
    local tc = Col("text")
    for _, n in ipairs({ "QuestLogQuestDescription", "QuestLogObjectivesText",
                         "QuestLogItemChooseText", "QuestLogItemReceiveText",
                         "QuestLogSpellLearnText", "QuestLogQuestTitle" }) do
        local fs = _G[n]
        if fs and fs.SetTextColor then fs:SetTextColor(tc.r, tc.g, tc.b) end
    end
end

local function RecolorQuestInfoStrings()
    for i = 1, 20 do
        RecolorObjectiveString(_G["QuestInfoObjective" .. i])
    end
    local tc = ColSafe("text", 0.92, 0.92, 0.92)
    local a = ColSafe("accent", 1, 0.82, 0)
    for _, n in ipairs({ "QuestInfoDescriptionText", "QuestInfoObjectivesText",
                         "QuestInfoRewardText", "QuestInfoGroupSize",
                         "QuestInfoDescriptionHeader", "QuestInfoObjectivesHeader" }) do
        local fs = _G[n]
        if fs and fs.SetTextColor then fs:SetTextColor(tc.r, tc.g, tc.b) end
    end
    if QuestInfoTitleHeader and QuestInfoTitleHeader.SetTextColor then
        QuestInfoTitleHeader:SetTextColor(a.r, a.g, a.b)
    end
end

-- ============================================================
-- HEADER CHROME - the band, the gold hairline and the X, placed as ONE
-- unit because all three are measured off the same header depth. Called
-- at skin time and again by /zacui line, so a live calibration moves the
-- whole header instead of sliding the rule out from under the X.
--
-- THE RULE RUNS EDGE TO EDGE. It used to stop 34px short of the right so
-- it would not pass under the close button, which left every window in
-- the game wearing a gold line that visibly gave up before the corner.
-- It does not need the gap: the X is a child FRAME, and a child frame
-- draws above its parent's OVERLAY layer whatever the sublevel, so the
-- rule simply passes beneath it - exactly what ZacUI's own windows do.
--
-- THE X SITS IN THE BAND, NOT ON THE CORNER. Blizzard's close buttons
-- are 32px squares whose art deliberately overhangs the frame edge (the
-- overhang is baked into the texture, which is why it looks right on a
-- Blizzard frame and wrong on a flat one). Re-anchored to a flat panel
-- corner that overhang reads as an X sliced by the border, and a 32px
-- button in a 23px band hangs out of the band as well. So the rect is
-- refitted to the band and centred in it, 6px clear of the edge, while
-- the drawn X keeps the same 11px arms as every other X in the addon.
-- ============================================================
local X_ARM = 11   -- matches UI.CloseX's bars on ZacUI's own windows

local function FitPanelChrome(frame, lineY)
    if not frame then return end
    local target = frame._zui_artbg or frame._zui_panel
    if not target then return end
    lineY = lineY or GetPanelLineY(frame.GetName and frame:GetName(), nil)
    local bandH = math.max(8, -lineY - 1)

    if frame._zui_band then
        frame._zui_band:ClearAllPoints()
        frame._zui_band:SetPoint("TOPLEFT",  target, "TOPLEFT",  1, -1)
        frame._zui_band:SetPoint("TOPRIGHT", target, "TOPRIGHT", -1, -1)
        frame._zui_band:SetHeight(bandH)
    end

    if frame._zui_line then
        frame._zui_line:ClearAllPoints()
        frame._zui_line:SetPoint("TOPLEFT",  target, "TOPLEFT",  1, lineY)
        frame._zui_line:SetPoint("TOPRIGHT", target, "TOPRIGHT",
            -(frame._zui_lineRight or 1), lineY)
    end

    -- THE TITLE (2026-11-11, the last of "every menu popup etc needs to
    -- match"): at the left of the header in ZacUI's title font, where
    -- ZacUI's own windows have theirs - it was the game's centred title in
    -- the game's font. Not on a window wearing Blizzard's art (the Classic
    -- look keeps its own header).
    if not frame._zui_artbg and frame._zui_line then
        local name = frame.GetName and frame:GetName()
        local title = frame.TitleText
            or (frame.TitleContainer and frame.TitleContainer.TitleText)
            or (name and _G[name .. "TitleText"])
        if title and title.SetPoint and title.SetJustifyH then
            local U = ns.UI
            if U and U._zFontDress and U.F and not rawget(title, "_zTitleFont") then
                rawset(title, "_zTitleFont", true)
                pcall(U._zFontDress, title, U.F.TITLE)
            end
            title:ClearAllPoints()
            title:SetPoint("LEFT", target, "TOPLEFT", 12, lineY / 2)
            title:SetPoint("RIGHT", target, "TOPRIGHT", -34, lineY / 2)
            title:SetJustifyH("LEFT")
            if title.SetWordWrap then title:SetWordWrap(false) end
        end
    end

    local close = frame._zui_close
    if close and close.SetPoint then
        local fit = math.max(14, math.min(bandH - 4, 22))
        close:SetSize(fit, fit)
        if close._zui_x1 then close._zui_x1:SetSize(X_ARM, 2) end
        if close._zui_x2 then close._zui_x2:SetSize(X_ARM, 2) end
        -- (the close icon: as wide as the X_ARM bars, its glyph 12/32 of it)
        if close._zui_xIcon then close._zui_xIcon:SetSize(21, 21) end
        close:ClearAllPoints()
        -- RIGHT edge 6px inside, centre of the button on the centre of
        -- the band (the band spans 0 .. lineY, so its middle is lineY/2)
        close:SetPoint("RIGHT", target, "TOPRIGHT", -6, lineY / 2)
        -- above the band and the rule, whatever level the template gave
        -- it - a close button drawn under its own header is unclickable
        -- art, and this costs nothing on an insecure frame
        if close.SetFrameLevel and frame.GetFrameLevel then
            close:SetFrameLevel(frame:GetFrameLevel() + 5)
        end
    end
end

-- ============================================================
-- WINDOW DRAGGING
-- ============================================================
-- Blizzard's panels (character, inspect, spellbook, friends...) are not
-- draggable in Classic: the panel manager puts them in fixed left /
-- centre / right slots. ZacUI lets you drag any of them by its title bar
-- (a ZacUI window's bar, or the header band of a skinned Blizzard one)
-- and keeps it there: the position is saved per window, and re-applied
-- every time the panel manager lays the panels out (it moves every open
-- panel back to its slot whenever one opens or closes).
--
-- Shift + right-click the title bar to forget a window's position; it
-- goes back to Blizzard's slot the next time it opens.
--
-- Protected panels (the character sheet and the others with ZacUI's
-- secure buttons) cannot be moved in combat; a drag started in combat is
-- ignored, and a saved position is re-applied when combat ends.
local dragHosts = {}
local dragHooked = false

-- The panel that actually moves: a cover can be parented to a sub-page
-- (InboxFrame, PaperDollFrame), and it is the page's window that moves.
local function TopPanel(f)
    local top = f
    while top and top.GetParent and top:GetParent() and top:GetParent() ~= UIParent do
        top = top:GetParent()
    end
    return top
end

local function DragBlocked(host)
    return InCombatLockdown() and host.IsProtected and host:IsProtected()
end

local function SavedPos(host)
    local name = host.GetName and host:GetName()
    return name and ZacUIDB and ZacUIDB.windowPos and ZacUIDB.windowPos[name]
end

local function ApplySavedPos(host)
    local p = SavedPos(host)
    if not p or host._zDragging or not host:IsShown() or DragBlocked(host) then return end
    local k = UIParent:GetEffectiveScale() / host:GetEffectiveScale()
    host:ClearAllPoints()
    host:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p.x * k, p.y * k)
end

local function ApplyAllSaved()
    for host in pairs(dragHosts) do ApplySavedPos(host) end
end

local function RegisterDragHost(host)
    if dragHosts[host] then return end
    dragHosts[host] = true
    host:HookScript("OnShow", function(self)
        C_Timer.After(0, function() ApplySavedPos(self) end)
    end)
    if dragHooked then return end
    dragHooked = true
    -- hooksecurefunc keeps the panel manager's own run secure; this only
    -- runs after it, and puts moved windows back where they were left.
    if FramePositionDelegate and type(FramePositionDelegate.UpdateUIPanelPositions) == "function" then
        hooksecurefunc(FramePositionDelegate, "UpdateUIPanelPositions", ApplyAllSaved)
    end
    if type(UpdateUIPanelPositions) == "function" then
        hooksecurefunc("UpdateUIPanelPositions", ApplyAllSaved)
    end
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    ev:SetScript("OnEvent", ApplyAllSaved)
end

local function StartWindowDrag(host)
    if not host or DragBlocked(host) then return end
    host._zDragging = true
    host:SetMovable(true)
    host:SetClampedToScreen(true)
    host:StartMoving()
end

local function StopWindowDrag(host)
    if not host or not host._zDragging then return end
    host._zDragging = nil
    host:StopMovingOrSizing()
    -- StartMoving marks the frame user-placed, which puts it in the
    -- client's layout cache; the saved position here is the one that
    -- counts, so keep the cache out of it.
    if host.SetUserPlaced and not DragBlocked(host) then host:SetUserPlaced(false) end
    local name = host.GetName and host:GetName()
    local l, t = host:GetLeft(), host:GetTop()
    if name and l and t then
        ZacUIDB.windowPos = ZacUIDB.windowPos or {}
        local k = host:GetEffectiveScale() / UIParent:GetEffectiveScale()
        ZacUIDB.windowPos[name] = { x = l * k, y = t * k }
    end
    ApplySavedPos(host)
end

local function ResetWindowPos(host)
    local name = host and host.GetName and host:GetName()
    if name and ZacUIDB and ZacUIDB.windowPos then ZacUIDB.windowPos[name] = nil end
end

-- A ZacUI title bar (or any handle) that drags the window it sits on.
local function AttachWindowDrag(handle, host)
    host = TopPanel(host)
    if not handle or not host or handle._zDragHost or not (host.GetName and host:GetName()) then return end
    handle._zDragHost = host
    RegisterDragHost(host)
    handle:EnableMouse(true)
    handle:RegisterForDrag("LeftButton")
    handle:HookScript("OnDragStart", function() StartWindowDrag(host) end)
    handle:HookScript("OnDragStop", function() StopWindowDrag(host) end)
    handle:HookScript("OnMouseUp", function(_, button)
        if button == "RightButton" and IsShiftKeyDown() then ResetWindowPos(host) end
    end)
end

-- A skinned Blizzard window: drags that start in its header band move
-- it. Frames that already drag themselves keep their own behaviour.
local function AttachBandDrag(frame)
    if not frame or frame._zBandDrag or not (frame.GetName and frame:GetName()) then return end
    if not frame.RegisterForDrag or frame:GetScript("OnDragStart") then return end
    if frame.IsMouseEnabled and not frame:IsMouseEnabled() then return end
    frame._zBandDrag = true
    RegisterDragHost(frame)
    frame:RegisterForDrag("LeftButton")
    local function InBand()
        local top = (frame._zui_artbg or frame._zui_panel or frame):GetTop()
        if not top then return false end
        local depth = -(GetPanelLineY(frame:GetName(), nil) or -24)
        local _, cy = GetCursorPosition()
        cy = cy / frame:GetEffectiveScale()
        return cy <= top and cy >= top - depth - 2
    end
    frame:HookScript("OnDragStart", function(self)
        if InBand() then StartWindowDrag(self) end
    end)
    frame:HookScript("OnDragStop", function(self) StopWindowDrag(self) end)
    frame:HookScript("OnMouseUp", function(self, button)
        if button == "RightButton" and IsShiftKeyDown() and InBand() then ResetWindowPos(self) end
    end)
end

-- GENERIC PANEL - the ONE entry point. Every frame is a one-line
-- classification into one of FOUR MODES, not a new invention:
--   1. STANDARD FITTED  - SkinPanel(f)                classic art shell
--   2. MODERN AUTO      - SkinPanel(f)                NineSlice detected,
--                                                     zero inset automatic
--   3. CONTENT-ART      - SkinPanel(f,{keepArt=...,noPanel=true})
--                         listed art regions survive (optionally zoomed),
--                         dark bg goes ON THE FRAME at sublevel -8, which
--                         renders UNDER regions - art on dark, always.
--   4. HANDS-OFF        - don't call SkinPanel (SettingsPanel doctrine)
local function SkinPanel(frame, opts)
    if not frame or ZUI.skinned[frame] then return end
    ZUI.skinned[frame] = true
    opts = opts or {}
    -- Classic: the Blizzard window keeps its own art. Only the panel
    -- register is kept, so /zacui inset and the covers' GetPanelInset
    -- still know the frame.
    if ns.Look.Pick(opts.look).windowChrome == "stock" then
        local nm = frame.GetName and frame:GetName()
        if nm then ZUI.panels[nm] = frame end
        return
    end

    StripFrameChrome(frame)
    if opts.keepArt then
        local keep = {}
        for _, piece in ipairs(opts.keepArt) do
            keep[piece] = true
            piece._zui_own = true
            if opts.artZoom and piece.SetTexCoord then
                piece:SetTexCoord(opts.artZoom[1], opts.artZoom[2],
                    opts.artZoom[1], opts.artZoom[2])
            end
        end
        for _, region in ipairs({ frame:GetRegions() }) do
            if region.IsObjectType and region:IsObjectType("Texture")
                and not keep[region] then
                region:SetTexture(nil)
                region:Hide()
            end
        end
    elseif not opts.keepRegions then
        StripTextures(frame)
    end

    local name = frame.GetName and frame:GetName()
    local panel
    if opts.noPanel then
        -- Mode 3: background under kept art, anchored to the INSET - the
        -- frame rect on classic windows is mostly transparent margin, and
        -- filling it made the dark area huge next to the actual content.
        local ins = opts.inset or GetPanelInset(name, frame)
        if not frame._zui_artbg then
            local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
            bg._zui_own = true
            bg:SetTexture(FLAT)
            frame._zui_artbg = bg
        end
        frame._zui_artbg:ClearAllPoints()
        frame._zui_artbg:SetPoint("TOPLEFT", frame, "TOPLEFT", ins.l or 0, -(ins.t or 0))
        frame._zui_artbg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -(ins.r or 0), ins.b or 0)
        local w = Col("windowBg")
        frame._zui_artbg:SetVertexColor(w.r, w.g, w.b, 0.95)
        panel = frame
    else
        panel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        AnchorPanel(panel, frame, opts.inset or GetPanelInset(name, frame))
        -- One level BELOW the window: at an equal level the panel could
        -- draw over the window's own regions (titles, and the labels on
        -- useParentLevel sub-pages like ReputationFrame).
        panel:SetFrameLevel(math.max(0, frame:GetFrameLevel() - 1))
        SkinBackdrop(panel, "windowBg", 0.97)
    end
    frame._zui_panel = panel
    if name then ZUI.panels[name] = frame end

    -- Close lookup: keyed, then global-name, then a bounded child scan -
    -- template generations name their close buttons differently, and a
    -- missed lookup here is exactly "the menu has no X".
    -- Mode 3 chrome target: the inset-fitted art background, NOT the
    -- frame rect (classic frames are mostly transparent margin - pinning
    -- chrome to the rect put the hairline through the title text and the
    -- X off the visible page). Anchoring to the art-bg means /zacui inset
    -- moves background, hairline and X together.
    local chromeTarget = frame._zui_artbg or panel

    local close = frame.CloseButton or (name and _G[name .. "CloseButton"])
    if not close then
        local function FindClose(root, depth)
            if not root or depth > 2 or not root.GetChildren then return nil end
            for _, child in ipairs({ root:GetChildren() }) do
                if child.IsObjectType and child:IsObjectType("Button") then
                    local cn = child.GetName and child:GetName()
                    if cn and cn:find("Close") then return child end
                end
                local found = FindClose(child, depth + 1)
                if found then return found end
            end
            return nil
        end
        close = FindClose(frame, 0)
    end
    local lineY = GetPanelLineY(name, opts.lineY)
    if close then
        -- Sized BEFORE skinning: SkinCloseButton reads the button width
        -- to work out its arms, so a resize afterwards would leave the
        -- X drawn for the old rect. FitPanelChrome below does the
        -- placing; the nominal 22 is only the arm length.
        SkinCloseButton(close, 22)
        frame._zui_close = close
    end

    -- The rule spans the full width now; the field stays because
    -- /zacui line reads it (and an override can still notch it).
    frame._zui_lineRight = 1

    -- THE HEADER BAND - the Esc-menu treatment, for every window: a flat
    -- strip in the palette's header color filling everything above the
    -- gold hairline, so the title visibly sits IN a header rather than
    -- floating over the body. One palette key (headerBg) drives this,
    -- ZacUI's own windows and the game menu alike. BORDER layer: the
    -- backdrop fills draw at BACKGROUND and would cover it.
    do
        local hb = Col("headerBg")
        local band = (frame._zui_artbg and frame or panel)
            :CreateTexture(nil, "BORDER")
        band._zui_own = true
        band:SetTexture(FLAT)
        -- (2026-11-10, Zac: "literally every menu popup etc needs to
        -- match") the header is the window itself, as on ZacUI's own
        -- windows: the band stays (things anchor to it) and is not drawn
        band:SetVertexColor(hb.r, hb.g, hb.b, 0)
        frame._zui_band = band
    end

    if frame._zui_artbg then
        local line = frame:CreateTexture(nil, "OVERLAY", nil, 6)
        line._zui_own = true
        line:SetColorTexture(1, 1, 1, 0.08)
        if ns.Pixel then ns.Pixel.Edge(line, "TOP", frame) else line:SetHeight(1) end
        frame._zui_line = line
    else
        -- AccentTitle also golds the title text; its placement is
        -- replaced a line later by FitPanelChrome.
        frame._zui_line = AccentTitle(panel, lineY, frame._zui_lineRight, frame)
    end

    -- band, rule and X placed together, off the one header depth
    FitPanelChrome(frame, lineY)

    if opts.tabs then SkinBottomTabs(opts.tabs, opts.tabCount or 5) end
    if opts.buttons then
        for _, bname in ipairs(opts.buttons) do
            local b = _G[bname]
            if b then SkinButton(b) end
        end
    end
    if opts.subStrip then
        for _, fname in ipairs(opts.subStrip) do
            local f = _G[fname]
            if f then StripTextures(f) end
        end
    end
    if not opts.noDrag and frame:GetParent() == UIParent then AttachBandDrag(frame) end
end


-- shared with later ZacUI files
ns.AnchorPanel = AnchorPanel
ns.AttachWindowDrag = AttachWindowDrag
ns.AttachBandDrag = AttachBandDrag
ns.FitPanelChrome = FitPanelChrome
ns.GetPanelInset = GetPanelInset
ns.GetPanelLineY = GetPanelLineY
ns.LiftDarkText = LiftDarkText
ns.PinFontObject = PinFontObject
ns.PinTextLight = PinTextLight
ns.RecolorParchmentFonts = RecolorParchmentFonts
ns.RecolorQuestInfoStrings = RecolorQuestInfoStrings
ns.RecolorQuestLogStrings = RecolorQuestLogStrings
ns.SkinPanel = SkinPanel
