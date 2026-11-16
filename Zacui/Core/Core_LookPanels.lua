-- Core_LookPanels - the game's own panels in the worn look, and ZacUI's own
-- dialogs dressed by one shared helper.
-- Part of ZacUI; load order is set by the TOC (right after Core_Look).
--
-- ZAC'S RULE (2026-11-08): "if i have 2004 mode enabled everything should
-- be 2004 style if i have forever it should all be forever or live client
-- or my style if that selected".
--
-- WHAT EACH LOOK DOES TO A BLIZZARD PANEL
--   ZacUI           the Blz_* skins (Modules/Blizzard) - not this file
--   WoW Forever /   the client's panels as drawn: the skins stand down
--   Blizzard style  (Core_Look's Look.STOCK) and this file does nothing
--   Classic WoW UI  Era / TBC: the client already draws the 2004 panels,
--                   so nothing is done. Forever / Retail: the modern
--                   chrome (NineSlice rim, portrait, title band, rock
--                   fill, tabs, red X, red buttons) steps back (alpha 0)
--                   and the 2004 chrome goes on, through ONE dresser
--                   (Look.dressers.blizzardPanel) every panel passes:
--                   the dialog border and background, the gold title in
--                   GameFontNormal centred at the top, the round close,
--                   the character-sheet tabs and the panel buttons.
--
-- SAFETY (taint). Chrome only: textures, our own frames and fonts, alpha.
-- No secure frame is moved, reparented, shown or hidden. A protected
-- panel gets its chrome out of combat only (a pass in combat waits for
-- the fight to end), and its close button keeps its place and size; a
-- forbidden frame is never touched. The dresser runs when a panel is
-- shown (HookScript OnShow, and ShowUIPanel's post-hook for a panel the
-- first hook missed) and, for a load-on-demand panel, after its addon
-- loads; every pass is idempotent. All of it is latched with the look:
-- it is set up once at login, never undone live.
--
-- (2026-11-08, Zac's Classic-look screenshots) Past the panels, the same
-- latch dresses the game's own pieces the skins leave stock: the minimap
-- (the round mask on every client - a square one set by ZacUI's look in
-- an earlier session stays on the client's map otherwise - and on
-- Forever / Retail the 2004 ring, zone banner and zoom buttons), the
-- character sheet's inner parts and the spellbook's pages (below), and
-- the chat's button column put back on Blizzard's own anchors.

local ADDON_NAME, ns = ...

local Look = ns.Look
if not Look then return end

local DIALOG_BG     = "Interface\\DialogFrame\\UI-DialogBox-Background"
local DIALOG_BORDER = "Interface\\DialogFrame\\UI-DialogBox-Border"
local TIP_BG        = "Interface\\Tooltips\\UI-Tooltip-Background"
local TIP_BORDER    = "Interface\\Tooltips\\UI-Tooltip-Border"
local CLOSE_UP      = "Interface\\Buttons\\UI-Panel-MinimizeButton-Up"
local CLOSE_DOWN    = "Interface\\Buttons\\UI-Panel-MinimizeButton-Down"
local CLOSE_HI      = "Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight"
local TAB_ACTIVE    = "Interface\\PaperDollInfoFrame\\UI-Character-ActiveTab"
local TAB_INACTIVE  = "Interface\\PaperDollInfoFrame\\UI-Character-InActiveTab"
local TAB_HI        = "Interface\\PaperDollInfoFrame\\UI-Character-Tab-Highlight"
local BTN_UP        = "Interface\\Buttons\\UI-Panel-Button-Up"
local BTN_DOWN      = "Interface\\Buttons\\UI-Panel-Button-Down"
local BTN_OFF       = "Interface\\Buttons\\UI-Panel-Button-Disabled"
local BTN_HI        = "Interface\\Buttons\\UI-Panel-Button-Highlight"
local GOLD          = { 1, 0.82, 0 }

-- The sheets' cuts (the classic templates' own texcoords): the tab sheet
-- is a 20 | 88 | 20 strip; the panel button a 12-px cap, the stretched
-- middle and the other cap, its art the top 0.6875 of the sheet.
local TAB_TC = { 0, 0.15625, 0.84375, 1 }
local TAB_CAP = 20
local BTN_TC = { 0, 0.09375, 0.53125, 0.625, 0.6875 }

local P = {}
Look.Panels = P
P.dressed = {}          -- frame -> true once the panel's chrome is on
P.hooked = {}           -- frame -> true once its OnShow is hooked

local function RealFlavor()
    if ns.RealFlavor then return ns.RealFlavor() end
    if ns.DetectFlavor then return ns.DetectFlavor() end
    return "era"
end

-- the client draws modern panels (Forever and Retail): Era and TBC draw
-- the 2004 ones themselves
function P.Modern()
    local fl = RealFlavor()
    return fl == "forever" or fl == "retail"
end

-- this panel (by its look part) wears Classic WoW UI on a modern client
function P.Wanted(part)
    if not P.Modern() then return false end
    local l = Look.For(part or "blizzard")
    return l ~= nil and l.id == "classic"
end

local function Forbidden(f)
    if not f then return true end
    return f.IsForbidden and f:IsForbidden() and true or false
end

local function Protected(f)
    if not f then return true end
    if Forbidden(f) then return true end
    return f.IsProtected and f:IsProtected() and true or false
end

local function InCombat() return InCombatLockdown and InCombatLockdown() and true or false end

local function Quiet(x)
    if x and x.SetAlpha then x:SetAlpha(0) end
end

-- a piece of ZacUI's own steps back and STAYS back, whatever colours its
-- paints give it after (Core_Look's Look.Back: the client keeps one alpha
-- per region). A piece of the game's is hidden with Quiet() and never hooked.
local Back = Look.Back

-- a texture's own colours to grey (a modern bronze piece with no 2004
-- file to stand in for it); marked for the tests
local function Grey(t)
    if type(t) ~= "table" or not t.SetDesaturated or rawget(t, "_zui_own") then return end
    t:SetDesaturated(true)
    rawset(t, "_zLookGrey", true)
end
P.Grey = Grey

-- a file the client ships, asked once (GetFileIDFromPath answers on the
-- Classic and the modern clients alike; a client without it is taken at
-- its word). A 2004 file the client lacks is never set: the piece goes
-- grey instead (Grey above).
local fileOK = {}
local function FileOK(path)
    if type(path) ~= "string" then return false end
    local v = fileOK[path]
    if v == nil then
        local get = _G.GetFileIDFromPath
        if type(get) == "function" then
            local ok, id = pcall(get, path)
            v = ok and id ~= nil
        else
            v = true
        end
        fileOK[path] = v
    end
    return v
end
P.FileOK = FileOK

local function IsTex(x) return type(x) == "table" and x.IsObjectType and x:IsObjectType("Texture") and true or false end

-- every texture region of a frame that is not ours
local function EachTex(f, fn)
    if type(f) ~= "table" or not f.GetRegions then return end
    for _, r in ipairs({ f:GetRegions() }) do
        if IsTex(r) and not rawget(r, "_zui_own") then fn(r) end
    end
end

-- ============================================================
-- THE MODERN CHROME, BY THE TEMPLATE KEYS THE CLIENT USES
-- (SharedUIPanelTemplates: PortraitFrameTemplate / ButtonFrameTemplate,
-- DialogBorderTemplate, InsetFrameTemplate, TooltipBackdropTemplate)
-- ============================================================
local CHROME_KEYS = { "NineSlice", "PortraitContainer", "PortraitFrame", "Portrait", "portrait",
    "TitleContainer", "TitleBg", "Bg", "TopTileStreaks", "BtnCornerLeft", "BtnCornerRight",
    "ButtonBottomBorder", "Border", "Header", "TopBorder", "BottomBorder", "LeftBorder", "RightBorder" }
local INSET_KEYS = { "Inset", "InsetRight", "LeftInset", "RightInset" }

local function HideChrome(host)
    for _, k in ipairs(CHROME_KEYS) do
        local x = rawget(host, k)
        -- a region or a frame of the template (never a function, never ours)
        if type(x) == "table" and x.SetAlpha and not rawget(x, "_zui_own") then Quiet(x) end
    end
    for _, k in ipairs(INSET_KEYS) do
        local inset = rawget(host, k)
        if type(inset) == "table" then
            Quiet(rawget(inset, "NineSlice"))
            Quiet(rawget(inset, "Bg"))
        end
    end
end

-- the panel's title text, wherever its template keeps it
local function TitleOf(host)
    local tc = rawget(host, "TitleContainer")
    if type(tc) == "table" and rawget(tc, "TitleText") then return rawget(tc, "TitleText") end
    if rawget(host, "TitleText") then return rawget(host, "TitleText") end
    local hd = rawget(host, "Header")
    if type(hd) == "table" and rawget(hd, "Text") then return rawget(hd, "Text") end
    local n = host.GetName and host:GetName()
    if n and _G[n .. "TitleText"] then return _G[n .. "TitleText"] end
    return nil
end

local function CloseOf(host)
    local b = rawget(host, "CloseButton") or rawget(host, "ClosePanelButton")
    if not b then
        local n = host.GetName and host:GetName()
        b = n and _G[n .. "CloseButton"]
    end
    return b
end

local function TabsOf(f, host)
    local out, seen = {}, {}
    local function add(t)
        if type(t) == "table" and t.GetObjectType and not seen[t] then
            seen[t] = true
            out[#out + 1] = t
        end
    end
    local n = f.GetName and f:GetName()
    if n then for i = 1, 10 do add(_G[n .. "Tab" .. i]) end end
    for _, owner in ipairs({ f, host }) do
        local list = rawget(owner, "Tabs")
        if type(list) == "table" then for _, t in ipairs(list) do add(t) end end
        local sys = rawget(owner, "TabSystem")
        if type(sys) == "table" then
            local tl = rawget(sys, "tabs") or rawget(sys, "Tabs")
            if type(tl) == "table" then for _, t in ipairs(tl) do add(t) end end
        end
    end
    return out, seen
end

-- ============================================================
-- THE 2004 PIECES
-- ============================================================
local function OwnTex(host, layer, sub)
    local t = host:CreateTexture(nil, layer, nil, sub)
    t._zui_own = true
    return t
end

local function FileArt(t, file, l, r, top, b)
    t:SetTexture(file)
    if t.SetTexCoord then t:SetTexCoord(l or 0, r or 1, top or 0, b or 1) end
end

-- the dialog box behind and around the panel: the background on a frame
-- a level under the panel (its own content draws over it), the border on
-- one at the modern rim's level (over the content's edges, as the 2004
-- panels' painted border was). kind: "panel" / "popup" the dialog box,
-- "tooltip" the tooltip box, "border" the rim alone (no fill)
local function Chrome(host, kind)
    local c = rawget(host, "_zLookChrome")
    if c then return c end
    local tip = kind == "tooltip"
    local edgeFile, bgFile = tip and TIP_BORDER or DIALOG_BORDER, tip and TIP_BG or DIALOG_BG
    local edgeSize, inset = tip and 16 or 32, tip and 5 or 11
    local lvl = host.GetFrameLevel and host:GetFrameLevel() or 1
    -- a frame-only host (the world map's border frame sits OVER the map):
    -- the rim alone, no fill
    local bg = kind ~= "border" and CreateFrame("Frame", nil, host, "BackdropTemplate") or nil
    if bg then
    bg:SetAllPoints(host)
    bg:SetFrameLevel(math.max(0, lvl - 1))
    bg:EnableMouse(false)
    end
    if bg and bg.SetBackdrop then
        bg:SetBackdrop({ bgFile = bgFile, tile = true, tileSize = tip and 16 or 32,
            insets = { left = inset, right = inset, top = inset, bottom = inset } })
    end
    if not bg then
        -- (no fill)
    elseif tip then
        local cr = TOOLTIP_DEFAULT_BACKGROUND_COLOR
        if bg.SetBackdropColor then
            bg:SetBackdropColor(cr and cr.r or 0.09, cr and cr.g or 0.09, cr and cr.b or 0.19, 1)
        end
    elseif bg.SetBackdropColor then
        bg:SetBackdropColor(1, 1, 1, 1)
    end
    local rim = CreateFrame("Frame", nil, host, "BackdropTemplate")
    rim:SetAllPoints(host)
    local nine = rawget(host, "NineSlice")
    local rl = (type(nine) == "table" and nine.GetFrameLevel and nine:GetFrameLevel()) or (lvl + 10)
    rim:SetFrameLevel(math.max(lvl + 1, rl))
    rim:EnableMouse(false)
    if rim.SetBackdrop then
        rim:SetBackdrop({ edgeFile = edgeFile, edgeSize = edgeSize,
            insets = { left = inset, right = inset, top = inset, bottom = inset } })
    end
    if rim.SetBackdropBorderColor then rim:SetBackdropBorderColor(1, 1, 1, 1) end
    -- ours: the sweeps that strip a panel's chrome (Zacui_Maps' among
    -- them) pass them by
    if bg then bg._zui_own = true end
    rim._zui_own = true
    c = { bg = bg, rim = rim, edgeFile = edgeFile, bgFile = bgFile, kind = kind }
    -- what the tests read (the stub's SetBackdrop draws nothing)
    if bg then rawset(bg, "_zBgFile", bgFile) end
    rawset(rim, "_zEdgeFile", edgeFile)
    rawset(host, "_zLookChrome", c)
    return c
end

-- the gold title in GameFontNormal, centred inside the border's top edge;
-- it follows the panel's own title (which steps back)
local function Title(host, c)
    if c.title then return c.title end
    local src = TitleOf(host)
    if not src then return nil end
    local fs = c.rim:CreateFontString(nil, "OVERLAY")
    fs._zui_own = true
    if GameFontNormal and fs.SetFontObject then fs:SetFontObject(GameFontNormal) end
    if fs.GetFont and not fs:GetFont() then
        pcall(fs.SetFont, fs, STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 12, "")
    end
    fs:SetPoint("TOP", host, "TOP", 0, -16)
    fs:SetTextColor(GOLD[1], GOLD[2], GOLD[3], 1)
    fs:SetText(src.GetText and src:GetText() or "")
    Quiet(src)
    if hooksecurefunc and src.SetText then
        hooksecurefunc(src, "SetText", function(_, t) fs:SetText(t) end)
    end
    if hooksecurefunc and src.SetFormattedText then
        hooksecurefunc(src, "SetFormattedText", function(self) fs:SetText(self:GetText()) end)
    end
    c.title, c.titleSrc = fs, src
    return fs
end

-- the round 2004 close button: the template's own art steps back, ours
-- goes on (normal / pushed / highlight), in the border's top-right corner
local function Close(host, c, fixed)
    local b = CloseOf(host)
    if not b or c.close or Protected(b) then return end
    for _, g in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
        if b[g] then Quiet(b[g](b)) end
    end
    for _, r in ipairs({ b:GetRegions() }) do
        if r.IsObjectType and r:IsObjectType("Texture") and not rawget(r, "_zui_own") then Quiet(r) end
    end
    -- (2026-11-08) a text "Close" button (the game options' ClosePanelButton)
    -- wearing the round X: its word goes, or it read as a second button
    local fs = b.GetFontString and b:GetFontString()
    if fs and fs.SetAlpha then fs:SetAlpha(0) end
    local n, p, h = OwnTex(b, "ARTWORK"), OwnTex(b, "ARTWORK", 1), OwnTex(b, "HIGHLIGHT")
    if fixed then
        -- a protected panel: the button keeps its place and size, the
        -- round art is drawn on it at the 2004 size
        for _, t in ipairs({ n, p, h }) do t:SetSize(32, 32) t:SetPoint("CENTER", b, "CENTER", 0, 0) end
    else
        b:SetSize(32, 32)
        b:ClearAllPoints()
        b:SetPoint("TOPRIGHT", host, "TOPRIGHT", -5, -5)
        for _, t in ipairs({ n, p, h }) do t:SetAllPoints(b) end
    end
    FileArt(n, CLOSE_UP) FileArt(p, CLOSE_DOWN) FileArt(h, CLOSE_HI)
    if h.SetBlendMode then h:SetBlendMode("ADD") end
    p:Hide()
    b:HookScript("OnMouseDown", function() n:Hide() p:Show() end)
    b:HookScript("OnMouseUp", function() p:Hide() n:Show() end)
    b:HookScript("OnLeave", function() p:Hide() n:Show() end)
    c.close = { button = b, normal = n, pushed = p, highlight = h, fixed = fixed and true or nil }
end

-- the modern red maximize / minimize pair (MaximizeMinimizeButtonFrame-
-- Template) as the 2004 bigger / smaller buttons where the client has
-- those files, grey otherwise
local MINMAX = {
    MaximizeButton = { "Interface\\Buttons\\UI-Panel-BiggerButton-Up", "Interface\\Buttons\\UI-Panel-BiggerButton-Down" },
    MinimizeButton = { "Interface\\Buttons\\UI-Panel-SmallerButton-Up", "Interface\\Buttons\\UI-Panel-SmallerButton-Down" },
}
local MINMAX_HI = "Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight"
local function MinMax(host)
    local mm = rawget(host, "MaximizeMinimizeButton") or rawget(host, "MaximizeMinimizeFrame")
    if type(mm) ~= "table" or rawget(mm, "_zLookMinMax") or Protected(mm) then return end
    rawset(mm, "_zLookMinMax", true)
    for key, files in pairs(MINMAX) do
        local b = rawget(mm, key)
        if type(b) == "table" and not Protected(b) then
            local n = b.GetNormalTexture and b:GetNormalTexture()
            local p = b.GetPushedTexture and b:GetPushedTexture()
            local h = b.GetHighlightTexture and b:GetHighlightTexture()
            if FileOK(files[1]) and FileOK(files[2]) then
                if n then FileArt(n, files[1]) end
                if p then FileArt(p, files[2]) end
                if h then FileArt(h, MINMAX_HI) if h.SetBlendMode then h:SetBlendMode("ADD") end end
                rawset(b, "_zLook2004", true)
            else
                Grey(n) Grey(p) Grey(h)
            end
        end
    end
end

-- one three-slice of a tab sheet onto the template's left / middle / right,
-- at the 2004 tab's own measure (Classic's CharacterFrameTabButtonTemplate:
-- 20 x 32 caps flush with the button's top corners, the selected set 4 px
-- higher). The modern pieces are the atlas's size and place - 36 px tall
-- unselected, 42 selected, hung 1 to 8 px off the corners - and the 2004
-- sheets drawn on those were stretched, the selected tab a third taller
-- than its art with its text left near the top (2026-11-15, Zac: "clicked
-- merchant button has some weird text alignment"). raise: the selected set.
local TAB_H = 32
local function TabSlice(tab, l, m, r, file, raise)
    local y = raise and 4 or 0
    if l then
        FileArt(l, file, TAB_TC[1], TAB_TC[2], 0, 1)
        if tab and l.SetSize then l:SetSize(TAB_CAP, TAB_H) elseif l.SetWidth then l:SetWidth(TAB_CAP) end
        if tab and l.ClearAllPoints then l:ClearAllPoints() l:SetPoint("TOPLEFT", tab, "TOPLEFT", 0, y) end
    end
    if r then
        FileArt(r, file, TAB_TC[3], TAB_TC[4], 0, 1)
        if tab and r.SetSize then r:SetSize(TAB_CAP, TAB_H) elseif r.SetWidth then r:SetWidth(TAB_CAP) end
        if tab and r.ClearAllPoints then r:ClearAllPoints() r:SetPoint("TOPRIGHT", tab, "TOPRIGHT", 0, y) end
    end
    if m then
        FileArt(m, file, TAB_TC[2], TAB_TC[3], 0, 1)
        -- (the modern middle is a tiled strip: the sheet's middle is stretched)
        if tab and l and r and m.ClearAllPoints then
            if m.SetHorizTile then m:SetHorizTile(false) end
            if m.SetHeight then m:SetHeight(TAB_H) end
            m:ClearAllPoints()
            m:SetPoint("TOPLEFT", l, "TOPRIGHT", 0, 0)
            m:SetPoint("TOPRIGHT", r, "TOPLEFT", 0, 0)
        end
    end
end

-- a modern tab as the character sheet's 2004 tab: the inactive sheet on
-- its plain pieces, the active sheet on its selected pieces (the client
-- shows one set or the other as it selects), the 2004 highlight
local function Tab(t)
    if rawget(t, "_zLookTab") or Protected(t) then return end
    rawset(t, "_zLookTab", true)
    local any = false
    local L, M, R = rawget(t, "Left"), rawget(t, "Middle"), rawget(t, "Right")
    -- the 2004 measure for a panel's bottom tabs only: a tab on top of its
    -- window, or one of a tab system (its pieces are turned to suit), keeps
    -- the template's own places
    local own = (not rawget(t, "isTopTab") and not rawget(t, "isTabOnTop")
        and rawget(t, "RotatedTextures") == nil) and t or nil
    if L or M or R then TabSlice(own, L, M, R, TAB_INACTIVE) any = true end
    local LA, MA, RA = rawget(t, "LeftActive"), rawget(t, "MiddleActive"), rawget(t, "RightActive")
    if LA or MA or RA then TabSlice(own, LA, MA, RA, TAB_ACTIVE, true) any = true end
    local LD, MD, RD = rawget(t, "LeftDisabled"), rawget(t, "MiddleDisabled"), rawget(t, "RightDisabled")
    if LD or MD or RD then TabSlice(own, LD, MD, RD, TAB_ACTIVE, true) any = true end
    for _, k in ipairs({ "LeftHighlight", "MiddleHighlight", "RightHighlight" }) do Quiet(rawget(t, k)) end
    if not any then
        -- a tab drawn some other way (a TabSystem button with its own art):
        -- its own art steps back, a 2004 tab is laid under its text
        for _, r in ipairs({ t:GetRegions() }) do
            if r.IsObjectType and r:IsObjectType("Texture") and not rawget(r, "_zui_own") then Quiet(r) end
        end
        local l, m, r = OwnTex(t, "BACKGROUND"), OwnTex(t, "BACKGROUND"), OwnTex(t, "BACKGROUND")
        l:SetPoint("TOPLEFT", t, "TOPLEFT", 0, 0) l:SetPoint("BOTTOMLEFT", t, "BOTTOMLEFT", 0, 0)
        r:SetPoint("TOPRIGHT", t, "TOPRIGHT", 0, 0) r:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", 0, 0)
        m:SetPoint("TOPLEFT", l, "TOPRIGHT", 0, 0) m:SetPoint("BOTTOMRIGHT", r, "BOTTOMLEFT", 0, 0)
        TabSlice(nil, l, m, r, TAB_INACTIVE)
        rawset(t, "_zLookTabArt", { l, m, r })
    end
    local hi = OwnTex(t, "HIGHLIGHT")
    hi:SetPoint("TOPLEFT", t, "TOPLEFT", 3, 5)
    hi:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", -3, 0)
    FileArt(hi, TAB_HI)
    if hi.SetBlendMode then hi:SetBlendMode("ADD") end
end

-- a modern red panel button (UIPanelButtonTemplate: Left / Middle / Right)
-- as the 2004 one; the client re-sets its art on press, enable and disable,
-- so each of those puts ours back
local function ButtonArt(b)
    local file = BTN_UP
    if b.IsEnabled and not b:IsEnabled() then file = BTN_OFF
    elseif rawget(b, "_zLookDown") then file = BTN_DOWN end
    local L, M, R = rawget(b, "Left"), rawget(b, "Middle"), rawget(b, "Right")
    if L then FileArt(L, file, BTN_TC[1], BTN_TC[2], 0, BTN_TC[5]) end
    if M then FileArt(M, file, BTN_TC[2], BTN_TC[3], 0, BTN_TC[5]) end
    if R then FileArt(R, file, BTN_TC[3], BTN_TC[4], 0, BTN_TC[5]) end
end
local function PanelButton(b)
    if rawget(b, "_zLookBtn") or Protected(b) then return end
    rawset(b, "_zLookBtn", true)
    ButtonArt(b)
    local hi = b.GetHighlightTexture and b:GetHighlightTexture()
    if hi then
        FileArt(hi, BTN_HI, 0, BTN_TC[4], 0, BTN_TC[5])
        if hi.SetBlendMode then hi:SetBlendMode("ADD") end
    end
    b:HookScript("OnMouseDown", function(self) if self:IsEnabled() then rawset(self, "_zLookDown", true) end ButtonArt(self) end)
    b:HookScript("OnMouseUp", function(self) rawset(self, "_zLookDown", nil) ButtonArt(self) end)
    b:HookScript("OnShow", ButtonArt)
    b:HookScript("OnEnable", ButtonArt)
    b:HookScript("OnDisable", ButtonArt)
end

local function IsTexture(x) return type(x) == "table" and x.IsObjectType and x:IsObjectType("Texture") end

-- the panel's red buttons, a few levels down (never a tab, never protected)
local function Buttons(root, tabs, depth)
    -- (the panel itself may be protected: its red buttons need not be)
    if depth > 5 or Forbidden(root) or (depth > 1 and Protected(root)) then return end
    for _, k in ipairs({ root:GetChildren() }) do
        if not rawget(k, "_zui_own") and not tabs[k] and not Protected(k) then
            if k.GetObjectType and k:GetObjectType() == "Button"
                and IsTexture(rawget(k, "Left")) and IsTexture(rawget(k, "Middle")) and IsTexture(rawget(k, "Right")) then
                PanelButton(k)
            end
            Buttons(k, tabs, depth + 1)
        end
    end
end

-- ============================================================
-- THE ONE DRESSER: a Blizzard panel in the Classic look
--   frame  the panel; look the worn look; part its look part
--   kind   "panel" (default) | "popup" | "tooltip"
--   host   the frame that carries the chrome (WorldMapFrame.BorderFrame)
-- ============================================================
-- a protected panel shown in a fight is dressed once the fight ends
P.waiting = {}
local regen
local function AfterCombat(fn)
    P.waiting[#P.waiting + 1] = fn
    if regen then return end
    regen = CreateFrame("Frame")
    regen:RegisterEvent("PLAYER_REGEN_ENABLED")
    regen:SetScript("OnEvent", function()
        local list = P.waiting
        P.waiting = {}
        for _, f in ipairs(list) do pcall(f) end
    end)
end

local function DressPanel(frame, look, part, kind, host)
    if not (frame and look and look.id == "classic") then return end
    if not P.Modern() then return end
    host = host or frame
    if Forbidden(host) then return end
    local prot = Protected(host)
    if prot and InCombat() then
        AfterCombat(function() DressPanel(frame, look, part, kind, host) end)
        return
    end
    HideChrome(host)
    local c = Chrome(host, kind)
    if kind ~= "tooltip" then
        Title(host, c)
        Close(host, c, prot)
        MinMax(host)
        local tabs, set = TabsOf(frame, host)
        for _, t in ipairs(tabs) do Tab(t) end
        Buttons(frame, set, 1)
    end
    P.dressed[frame] = true
    return c
end
Look.dressers.blizzardPanel = DressPanel
P.Tab = Tab

-- ============================================================
-- THE CHARACTER SHEET'S INSIDE (Forever's Camelot CharacterFrame:
-- Blizzard_UIPanels_Game/Camelot/CharacterFrame.xml, PaperDollFrame.xml,
-- branch "forever"). The window is the paperdoll pane (LeftPaneHost, 398
-- wide, 20 under the window's top) and the stats pane beside it; the
-- 2004 sheet's name sat centred over the SHEET, 24 under its top, the
-- level line under it in white. So: the title over LeftPaneHost (not the
-- whole, wider window), the pane fills and the rock strip step back for
-- the dialog background, each slot wears the 2004 ring (UI-Quickslot2,
-- 64 on a 37 slot, one down) in place of the bronze gear-slot frame, and
-- the bronze side tabs, sidebar tabs and stat headers go grey (no 2004
-- file draws them), the headers' words gold as the 2004 sheet's labels.
-- ============================================================
local SLOT_NAMES = { "Head", "Neck", "Shoulder", "Back", "Chest", "Shirt", "Tabard", "Wrist", "Hands", "Waist",
    "Legs", "Feet", "Finger0", "Finger1", "Trinket0", "Trinket1", "MainHand", "SecondaryHand", "Ranged", "Ammo" }
local QUICKSLOT = "Interface\\Buttons\\UI-Quickslot2"
P.SLOT_NAMES = SLOT_NAMES

local function SlotRing(b)
    if type(b) ~= "table" or Protected(b) then return end
    local bf = rawget(b, "BorderFrame")
    if type(bf) == "table" then Quiet(bf) end
    local nt = rawget(b, "NormalTexture")
    if not IsTex(nt) then nt = b.GetNormalTexture and b:GetNormalTexture() end
    if not IsTex(nt) then return end
    local w = b.GetWidth and b:GetWidth() or 37
    local h = b.GetHeight and b:GetHeight() or 37
    if type(w) ~= "number" or w <= 0 then w = 37 end
    if type(h) ~= "number" or h <= 0 then h = w end
    FileArt(nt, QUICKSLOT)
    if nt.SetVertexColor then nt:SetVertexColor(1, 1, 1, 1) end
    if nt.SetDesaturated then nt:SetDesaturated(false) end
    nt:SetAlpha(1)
    if nt.Show then nt:Show() end
    nt:ClearAllPoints()
    nt:SetSize(w * 64 / 37, h * 64 / 37)
    nt:SetPoint("CENTER", b, "CENTER", 0, -h / 37)
    rawset(b, "_zLookSlot", nt)
end
P.SlotRing = SlotRing

local GOLD_FS = function(fs) if type(fs) == "table" and fs.SetTextColor then fs:SetTextColor(GOLD[1], GOLD[2], GOLD[3], 1) end end

-- one stats row or header (the pane's own headers, or a ScrollBox row)
local function StatRow(row)
    if type(row) ~= "table" then return end
    Grey(rawget(row, "Background"))
    local t = rawget(row, "Title")
    if t then GOLD_FS(t) end
end

local function CharacterInside(f, c)
    local lp = rawget(f, "LeftPaneHost")
    -- the title over the sheet: centred on the paperdoll pane, its top 18
    -- under the window's (the pane starts 20 down)
    if c and c.title and type(lp) == "table" then
        c.title:ClearAllPoints()
        c.title:SetPoint("TOP", lp, "TOP", 0, 2)
        c.titleHost = lp
    end
    local rp = rawget(f, "RightPaneHost")
    EachTex(lp, Quiet)
    EachTex(rp, Quiet)
    if type(rp) == "table" and rp.GetChildren then
        -- the frame divider (rebuilt by the client on a page switch)
        for _, k in ipairs({ rp:GetChildren() }) do
            if not rawget(k, "_zui_own") and not Protected(k) then Quiet(k) end
        end
    end
    local pd = _G.PaperDollFrame
    local strip = type(pd) == "table" and rawget(pd, "TopBackgroundStripHost")
    if type(strip) == "table" then EachTex(strip, Quiet) end
    -- the level line: white, as the 2004 sheet's (the font stays the
    -- client's outlined one)
    local lvl = _G.CharacterLevelText
    if type(lvl) == "table" and lvl.SetTextColor then lvl:SetTextColor(1, 1, 1, 1) rawset(lvl, "_zLookWhite", true) end
    -- the slots
    for _, n in ipairs(SLOT_NAMES) do SlotRing(_G["Character" .. n .. "Slot"]) end
    -- the stats pane: its class picture steps back, the headers go grey
    -- with gold words, every row the list hands out after this too
    for _, n in ipairs({ "CharacterStatsPane", "CharacterStatsPaneScrollBox", "CharacterStatsPanePetScrollBox" }) do
        local pane = _G[n]
        if type(pane) == "table" then
            Quiet(rawget(pane, "ClassBackground"))
            for _, k in ipairs({ "ItemLevelCategory", "AttributesCategory", "EnhancementsCategory" }) do StatRow(rawget(pane, k)) end
            local box = rawget(pane, "ScrollBox")
            if type(box) == "table" and not rawget(box, "_zLookRows") and ScrollUtil and ScrollUtil.AddInitializedFrameCallback then
                rawset(box, "_zLookRows", true)
                pcall(ScrollUtil.AddInitializedFrameCallback, box, function(a, b) StatRow(a == P and b or a) end, P, true)
            end
        end
    end
    -- the side tabs (the window's mode tabs, the paperdoll's sidebar tabs):
    -- their bronze to grey, the icon in its own colours
    local tabs = {}
    for i = 1, 8 do
        tabs[#tabs + 1] = _G["CharacterFrameModeTab" .. i]
        tabs[#tabs + 1] = _G["PaperDollSidebarTab" .. i]
    end
    for _, t in ipairs(tabs) do
        if type(t) == "table" and not rawget(t, "_zLookSideTab") then
            rawset(t, "_zLookSideTab", true)
            local icon = rawget(t, "Icon")
            EachTex(t, function(r) if r ~= icon then Grey(r) end end)
            for _, g in ipairs({ "GetCheckedTexture", "GetHighlightTexture", "GetNormalTexture", "GetPushedTexture" }) do
                local r = t[g] and t[g](t)
                if IsTex(r) and r ~= icon then Grey(r) end
            end
        end
    end
    -- the client rebuilds the divider and re-titles on each page switch
    if f.ShowSubFrame and hooksecurefunc and not rawget(f, "_zLookSubHook") then
        rawset(f, "_zLookSubHook", true)
        hooksecurefunc(f, "ShowSubFrame", function(self) CharacterInside(self, rawget(self, "_zLookChrome")) end)
    end
end
P.CharacterInside = CharacterInside

-- ============================================================
-- THE SPELLBOOK (Forever's PlayerSpellsFrame: Blizzard_PlayerSpells,
-- branch "forever"). Past the window's chrome: the parchment pages
-- (BookBGLeft / Right / Halved, the top bar, the corner and the bookmark)
-- step back for the dialog's dark background, the category tabs take the
-- 2004 tab, and each spell's words take the 2004 book's colours - the
-- name gold, the rank / subtext white, the level line grey - where the
-- client wrote them in its dark parchment ink (SPELLBOOK_FONT_COLOR in
-- the item template; nothing in the client's code colours them again).
-- The parchment card behind each spell goes grey.
-- ============================================================
local PAGE_ART = { "BookBGLeft", "BookBGRight", "BookBGHalved", "TopBar", "BookCornerFlipbook", "Bookmark" }
local function SpellItemText(item)
    if type(item) ~= "table" then return end
    local tc = rawget(item, "TextContainer")
    local function fs(k) return rawget(item, k) or (type(tc) == "table" and rawget(tc, k)) end
    GOLD_FS(fs("Name"))
    local sub = fs("SubName")
    if type(sub) == "table" and sub.SetTextColor then sub:SetTextColor(1, 1, 1, 1) end
    local req = fs("RequiredLevel")
    if type(req) == "table" and req.SetTextColor then req:SetTextColor(0.8, 0.8, 0.8, 1) end
    Grey(rawget(item, "Backplate"))
    rawset(item, "_zLookInk", true)
end
P.SpellItemText = SpellItemText

-- the client's spell item template: every item it makes from now on
-- takes the colours on each visual pass (set once, when the book's addon
-- loads - before its first page is drawn)
local function HookSpellItems()
    if P.spellItemsHooked then return end
    local mx = _G.SpellBookItemMixin
    if type(mx) ~= "table" or type(mx.UpdateVisuals) ~= "function" or not hooksecurefunc then return end
    P.spellItemsHooked = true
    hooksecurefunc(mx, "UpdateVisuals", SpellItemText)
end

local function SpellItemsUnder(root, depth)
    if depth > 7 or type(root) ~= "table" or not root.GetChildren then return end
    for _, k in ipairs({ root:GetChildren() }) do
        if not rawget(k, "_zui_own") then
            if type(rawget(k, "TextContainer")) == "table" then SpellItemText(k) end
            SpellItemsUnder(k, depth + 1)
        end
    end
end

local function SpellsInside(f, c)
    HookSpellItems()
    local page = rawget(f, "SpellBookFrame")
    if type(page) ~= "table" then return end
    for _, k in ipairs(PAGE_ART) do Quiet(rawget(page, k)) end
    local sys = rawget(page, "CategoryTabSystem")
    if type(sys) == "table" then
        local list = rawget(sys, "tabs") or rawget(sys, "Tabs")
        if type(list) == "table" then for _, t in ipairs(list) do Tab(t) end end
    end
    -- the items already drawn (a book opened before the look's pass)
    SpellItemsUnder(page, 1)
end
P.SpellsInside = SpellsInside

-- ============================================================
-- THE PANELS (by global name; lod = the load-on-demand addon that makes
-- it; host = the child that carries the chrome; part = its look part)
-- ============================================================
P.LIST = {
    { "CharacterFrame", inside = CharacterInside }, { "PaperDollFrame", sub = true }, { "SpellBookFrame" },
    { "PlayerSpellsFrame", lod = "Blizzard_PlayerSpells", inside = SpellsInside, onHook = HookSpellItems },
    { "PlayerTalentFrame", lod = "Blizzard_TalentUI" }, { "TalentFrame", lod = "Blizzard_TalentUI" },
    { "ClassTalentFrame", lod = "Blizzard_ClassTalentUI" },
    { "QuestLogFrame" }, { "WorldMapFrame", part = "maps", host = "BorderFrame", kind = "border",
        -- Zacui_Maps' map rebuild restyles the map frame itself (its header,
        -- its buttons) under every look: two dressers on one frame would
        -- fight over the close button, so the map is left to it while it runs
        -- (asked by the switch, not by "has run": the map may be up before
        -- the login's module pass reaches the rebuild)
        -- (2026-11-14: under a game look that rebuild stands down -
        -- Maps.WindowOn - and the map is dressed here like any other panel)
        skip = function()
            local m = type(ZacUIDB) == "table" and type(ZacUIDB.modules) == "table" and ZacUIDB.modules.maps
            if not (m and ns.Modules and ns.Modules.maps) then return false end
            if ns.Maps and ns.Maps.WindowOn and not ns.Maps.WindowOn() then return false end
            return true
        end },
    { "MerchantFrame" }, { "GossipFrame" }, { "QuestFrame" },
    { "ClassTrainerFrame", lod = "Blizzard_TrainerUI" },
    { "MailFrame" }, { "OpenMailFrame" }, { "BankFrame", part = "bags" },
    { "FriendsFrame" }, { "SocialUIFrame" },
    { "GuildFrame", lod = "Blizzard_GuildUI" }, { "CommunitiesFrame", lod = "Blizzard_Communities" },
    { "LFGParentFrame" }, { "PVEFrame" }, { "PVPUIFrame", lod = "Blizzard_PVPUI" },
    { "SettingsPanel" }, { "GameMenuFrame" }, { "TradeFrame" }, { "LootFrame" },
    { "AuctionHouseFrame", lod = "Blizzard_AuctionHouseUI" },
    { "InspectFrame", lod = "Blizzard_InspectUI" }, { "MacroFrame", lod = "Blizzard_MacroUI" },
    { "ProfessionsFrame", lod = "Blizzard_Professions" }, { "TradeSkillFrame", lod = "Blizzard_TradeSkillUI" },
    { "AddonList" }, { "TaxiFrame" }, { "ItemTextFrame" }, { "TabardFrame" }, { "DressUpFrame" },
    { "PetStableFrame" }, { "LegacySystemFrame" }, { "HelpFrame" },
    { "StaticPopup1", kind = "popup" }, { "StaticPopup2", kind = "popup" },
    { "StaticPopup3", kind = "popup" }, { "StaticPopup4", kind = "popup" },
    { "GroupLootFrame1", kind = "popup" }, { "GroupLootFrame2", kind = "popup" },
    { "GroupLootFrame3", kind = "popup" }, { "GroupLootFrame4", kind = "popup" },
    { "GameTooltip", part = "tooltip", kind = "tooltip" }, { "ItemRefTooltip", part = "tooltip", kind = "tooltip" },
    { "ShoppingTooltip1", part = "tooltip", kind = "tooltip" }, { "ShoppingTooltip2", part = "tooltip", kind = "tooltip" },
    { "EmbeddedItemTooltip", part = "tooltip", kind = "tooltip" },
}

P.BYNAME = {}
for _, e in ipairs(P.LIST) do P.BYNAME[e[1]] = e end

local function DressEntry(e, f)
    if e.skip and e.skip() then return end
    local host = e.host and rawget(f, e.host) or nil
    if e.host and not host then return end
    local c = DressPanel(f, Look.For(e.part or "blizzard"), e.part or "blizzard", e.kind, host)
    if c and e.inside and not (Protected(f) and InCombat()) then pcall(e.inside, f, c) end
end

-- hook one panel: dressed now if it is up, and on every show (idempotent)
local function Hook(e)
    if e.sub then return end
    local f = _G[e[1]]
    if type(f) ~= "table" or not f.HookScript or P.hooked[f] then return end
    if not P.Wanted(e.part) then return end
    if Forbidden(f) then return end
    P.hooked[f] = true
    if e.onHook then pcall(e.onHook, f) end
    f:HookScript("OnShow", function(self) DressEntry(e, self) end)
    if f.IsShown and f:IsShown() then DressEntry(e, f) end
end

function P.Scan()
    for _, e in ipairs(P.LIST) do Hook(e) end
end

-- a panel shown through the UI panel system: hooked (and dressed) here
-- too, should the scans have missed it (a panel made by an addon that
-- loaded in a way the load hook did not hear)
local function OnShowUIPanel(f)
    if type(f) ~= "table" or not f.GetName then return end
    local e = P.BYNAME[f:GetName() or ""]
    if not e or e.sub then return end
    if not P.hooked[f] then Hook(e) end
end

local started = false
-- once, when the look is final (PLAYER_LOGIN's re-read): nothing at all
-- unless some part wears Classic WoW UI on a modern client
function P.Start()
    if started then return end
    if not P.Modern() then return end
    local any = false
    for _, part in ipairs({ "blizzard", "maps", "bags", "tooltip" }) do
        if P.Wanted(part) then any = true end
    end
    if not any then return end
    started = true
    P.Scan()
    if hooksecurefunc and type(_G.ShowUIPanel) == "function" then
        hooksecurefunc("ShowUIPanel", OnShowUIPanel)
    end
    -- a load-on-demand panel is made when its addon loads: the main event
    -- frame (Boot_Events, already listening for ADDON_LOADED) is heard,
    -- so no frame of ours is made and the shared LoD registry (one skin
    -- per addon) is left to the skins
    local zui = ns.ZUI
    if zui and zui.HookScript then
        zui:HookScript("OnEvent", function(_, event, name)
            -- (any addon: a client may make a panel from an addon not named
            -- Blizzard_*; the scan is a table walk of names, cheap)
            if event == "ADDON_LOADED" and type(name) == "string" then P.Scan() end
        end)
    end
end

-- ============================================================
-- THE MINIMAP UNDER A GAME LOOK (Blz_Minimap, ZacUI's square map, stands
-- down; Core_Look's Look.STOCK)
-- ============================================================
-- Every client: the round mask (Look.MinimapSpec). The client's map keeps
-- the mask it was last given across a reload, so the square one ZacUI's
-- look set in an earlier session stayed on Era's stock map, its corners
-- past the round ring (Zac 2026-11-08: "on 2004 style does the map
-- normally go outside the circle i doubt that"). Era and TBC draw the
-- 2004 ring, banner and zoom buttons themselves; that is all they need.
-- Forever / Retail under Classic WoW UI (Blizzard_Minimap Mainline
-- Minimap.xml + Camelot Minimap.lua, branch "forever": a 198 map, the
-- bronze MinimapCompassTexture over it, the zone button's and tracking /
-- calendar buttons' own bronze art): the bronze steps back and the 2004
-- pieces go on, from the vanilla files every client ships, scaled from
-- the vanilla 140 map to this one -
--   the ring     UI-Minimap-Border's 192 x 192 region (texcoords 0.25-1,
--                0.125-0.875), centred 8 left and 24 below the map's
--                centre (the art's circle on the map, the rest its lower-
--                left bulge)
--   the banner   the same sheet's top strip (rows 0-28): a 36-column
--                rounded left end, a 16-column right end, the middle
--                stretched, 28 tall, under the zone name (centred)
--   zoom + / -   UI-Minimap-ZoomIn/OutButton-Up / -Down / -Disabled and
--                the shared highlight, 32 a side at the vanilla map's
--                scale, where the client puts them
--   tracking     the vanilla ring (MiniMap-TrackingBorder, 52 on a 32
--                button, from its top-left) round the client's button,
--                which goes grey with the calendar's
-- Region calls and textures of ours only; nothing is moved but the zone
-- name inside its own button. The client re-sets its mask and compass on
-- a rotate-minimap change: both are put back after it.
local MM_BORDER = "Interface\\Minimap\\UI-Minimap-Border"
local MM_TRACK = "Interface\\Minimap\\MiniMap-TrackingBorder"
local MM_ZOOM = {
    ZoomIn = "Interface\\Minimap\\UI-Minimap-ZoomInButton-",
    ZoomOut = "Interface\\Minimap\\UI-Minimap-ZoomOutButton-",
}
local MM_ZOOM_HI = "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight"
P.MM_BORDER = MM_BORDER

local function MapScale(map)
    local w = map.GetWidth and map:GetWidth() or 140
    if type(w) ~= "number" or w <= 0 then w = 140 end
    return w / 140
end

local function MinimapRing(map, s)
    local host = _G.MinimapBackdrop
    if type(host) ~= "table" or not host.CreateTexture then host = map end
    local ring = rawget(map, "_zLookRing")
    if not ring then
        ring = OwnTex(host, "OVERLAY", 3)
        FileArt(ring, MM_BORDER, 0.25, 1, 0.125, 0.875)
        rawset(map, "_zLookRing", ring)
    end
    ring:ClearAllPoints()
    ring:SetSize(192 * s, 192 * s)
    ring:SetPoint("CENTER", map, "CENTER", -8 * s, -24 * s)
    return ring
end

local function ZoneBanner(zb)
    if type(zb) ~= "table" or not zb.CreateTexture then return nil end
    Quiet(rawget(zb, "StateTexture"))
    Quiet(rawget(zb, "AddTexture"))
    local b = rawget(zb, "_zLookBanner")
    if not b then
        local l, m, r = OwnTex(zb, "BACKGROUND", 1), OwnTex(zb, "BACKGROUND", 1), OwnTex(zb, "BACKGROUND", 1)
        FileArt(l, MM_BORDER, 0.3125, 0.453125, 0, 0.109375)
        FileArt(m, MM_BORDER, 0.453125, 0.9375, 0, 0.109375)
        FileArt(r, MM_BORDER, 0.9375, 1, 0, 0.109375)
        b = { left = l, mid = m, right = r }
        rawset(zb, "_zLookBanner", b)
    end
    local w = zb.GetWidth and zb:GetWidth() or 152
    if type(w) ~= "number" or w <= 0 then w = 152 end
    -- the banner reaches past the button by a buttons' width a side (the
    -- client's tracking and calendar buttons sit on its ends)
    local span = w + 46
    b.left:ClearAllPoints() b.left:SetSize(36, 28)
    b.left:SetPoint("LEFT", zb, "CENTER", -span / 2, 0)
    b.right:ClearAllPoints() b.right:SetSize(16, 28)
    b.right:SetPoint("RIGHT", zb, "CENTER", span / 2, 0)
    b.mid:ClearAllPoints()
    b.mid:SetPoint("TOPLEFT", b.left, "TOPRIGHT", 0, 0)
    b.mid:SetPoint("BOTTOMRIGHT", b.right, "BOTTOMLEFT", 0, 0)
    -- the zone name centred on the banner, as the 2004 one
    local zt = _G.MinimapZoneText
    if type(zt) == "table" and zt.SetPoint then
        if zt.SetJustifyH then zt:SetJustifyH("CENTER") end
        zt:ClearAllPoints()
        zt:SetPoint("CENTER", zb, "CENTER", 0, 1)
    end
    return b
end

local function ZoomButton(b, base, s)
    if type(b) ~= "table" or Protected(b) then return end
    local up, down, off = base .. "Up", base .. "Down", base .. "Disabled"
    if not (FileOK(up) and FileOK(down)) then
        for _, g in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture", "GetHighlightTexture" }) do
            Grey(b[g] and b[g](b))
        end
        return
    end
    local function Set(get, file, add)
        local t = b[get] and b[get](b)
        if not IsTex(t) or not file then return end
        FileArt(t, file)
        if t.SetDesaturated then t:SetDesaturated(false) end
        if add and t.SetBlendMode then t:SetBlendMode("ADD") end
        if t.SetAllPoints then t:ClearAllPoints() t:SetAllPoints(b) end
    end
    Set("GetNormalTexture", up)
    Set("GetPushedTexture", down)
    Set("GetDisabledTexture", FileOK(off) and off or up)
    Set("GetHighlightTexture", MM_ZOOM_HI, true)
    b:SetSize(32 * s, 32 * s)
    rawset(b, "_zLook2004", true)
end

local function TrackingRing(btn)
    if type(btn) ~= "table" or not btn.CreateTexture then return end
    Grey(rawget(btn, "StateTexture"))
    Grey(rawget(btn, "AddTexture"))
    local ring = rawget(btn, "_zLookRing")
    if not ring then
        ring = OwnTex(btn, "OVERLAY", 2)
        FileArt(ring, MM_TRACK)
        rawset(btn, "_zLookRing", ring)
    end
    local w = btn.GetWidth and btn:GetWidth() or 32
    if type(w) ~= "number" or w <= 0 then w = 32 end
    ring:ClearAllPoints()
    ring:SetSize(w * 52 / 32, w * 52 / 32)
    ring:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
end

local function DressMinimap()
    local map = _G.Minimap
    local spec = P.mm and P.mm.spec
    if type(map) ~= "table" or not spec then return end
    if map.SetMaskTexture then map:SetMaskTexture(spec.mask) end
    if not P.mm.dress then return end
    local s = MapScale(map)
    Quiet(_G.MinimapCompassTexture)
    Quiet(_G.MinimapCompassTextureUnderlay)
    P.mm.ring = MinimapRing(map, s)
    local cl = _G.MinimapCluster
    P.mm.banner = ZoneBanner(type(cl) == "table" and rawget(cl, "ZoneTextButton") or nil)
    for key, base in pairs(MM_ZOOM) do
        ZoomButton(rawget(map, key) or _G["Minimap" .. key], base, s)
    end
    local tr = type(cl) == "table" and rawget(cl, "Tracking") or nil
    if type(tr) == "table" then
        Quiet(rawget(tr, "Background"))
        TrackingRing(rawget(tr, "Button"))
    end
    local gt = _G.GameTimeFrame
    if type(gt) == "table" then
        Grey(rawget(gt, "StateTexture"))
        Grey(rawget(gt, "AddTexture"))
    end
end
P.DressMinimap = DressMinimap

-- once, at the login's look latch
function P.Minimap()
    if P.mm then return end
    local map = _G.Minimap
    if type(map) ~= "table" or not map.SetMaskTexture then return end
    local look = Look.For("minimap")
    if not look or look.id == "zacui" then return end
    -- ZacUI's minimap switched off: another minimap addon may own the map
    local mods = type(ZacUIDB) == "table" and ZacUIDB.modules or nil
    if type(mods) == "table" and mods.minimap == false then return end
    -- a modern client under its own modern look sets its own round mask
    -- at load (MinimapClusterMixin:UpdateMinimapConfig): left to it
    if P.Modern() and look.id ~= "classic" then return end
    local spec = Look.MinimapSpec and Look.MinimapSpec("minimap")
    if type(spec) ~= "table" or spec.shape ~= "ROUND" then return end
    P.mm = { spec = spec, dress = P.Modern() and look.id == "classic" }
    DressMinimap()
    local cl = _G.MinimapCluster
    if P.mm.dress and type(cl) == "table" and type(cl.UpdateMinimapConfig) == "function" and hooksecurefunc then
        hooksecurefunc(cl, "UpdateMinimapConfig", DressMinimap)
    end
end

-- ============================================================
-- THE CHAT'S BUTTON COLUMN UNDER A GAME LOOK (Blz_Chat stands down)
-- ============================================================
-- The client hangs ChatFrame1's button column (ChatFrame1ButtonFrame,
-- the chat menu, channel and voice buttons) beside the chat's background
-- (FCF_SetButtonSide: TOPRIGHT / BOTTOMRIGHT of the column on the
-- background's left, 3 out, 3 down / 6 up) and the alert stack holding
-- the friends (QuickJoinToastButton) button 27 over the column's top
-- (ChatAlertFrameMixin:OnLoad) - Blizzard_ChatFrameBase, branch "forever".
-- Under a game look ZacUI's chat skin never runs and nothing of ZacUI's
-- places them; still, Zac saw the column float far over the chat on
-- Forever. So the client's own anchors are put back on the client's own
-- terms: once the world has settled after the login, and after each time
-- the chat window is saved (moved or sized), out of combat, through the
-- client's FCF_SetButtonSide and the alert stack's own anchor.
function P.ChatSeat()
    if InCombat() then return false end
    local cf = _G.ChatFrame1
    local bf = type(cf) == "table" and rawget(cf, "buttonFrame") or nil
    if type(bf) ~= "table" then return false end
    local side = cf.buttonSide
    if type(_G.FCF_GetButtonSide) == "function" then
        local ok, s = pcall(_G.FCF_GetButtonSide, cf)
        if ok and (s == "left" or s == "right") then side = s end
    end
    if side ~= "left" and side ~= "right" then side = "left" end
    if type(_G.FCF_SetButtonSide) == "function" then pcall(_G.FCF_SetButtonSide, cf, side, true) end
    local alert = _G.ChatAlertFrame
    if type(alert) == "table" and alert.SetPoint and not Protected(alert) then
        alert:ClearAllPoints()
        -- (Zac's /fstack, 2026-11-08: the friends button floated 27 over
        -- the column as the client hangs it) on the column's top, level
        -- with the chat's tabs, so the column reads as one stack
        alert:SetPoint("BOTTOMLEFT", bf, "TOPLEFT", 0, 2)
    end
    local menu = _G.ChatFrameMenuButton
    if type(menu) == "table" and menu.GetParent and menu:GetParent() == bf and not Protected(menu) then
        menu:ClearAllPoints()
        menu:SetPoint("BOTTOM", bf, "BOTTOM", 0, 0)
    end
    P.chatSeated = (P.chatSeated or 0) + 1
    return true
end

function P.ChatStart()
    if P.chatStarted or not P.Modern() then return end
    if not (Look.StandsDown and Look.StandsDown("chat")) then return end
    P.chatStarted = true
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:SetScript("OnEvent", function()
        C_Timer.After(2, P.ChatSeat)
    end)
    if hooksecurefunc and type(_G.FCF_SavePositionAndDimensions) == "function" then
        hooksecurefunc("FCF_SavePositionAndDimensions", function(f)
            if f == _G.ChatFrame1 then C_Timer.After(0, P.ChatSeat) end
        end)
    end
end

local origRelatch = Look.Relatch
function Look.Relatch(...)
    if origRelatch then origRelatch(...) end
    P.Start()
    pcall(P.Minimap)
    pcall(P.ChatStart)
end

-- ============================================================
-- ZACUI'S OWN DIALOGS UNDER A GAME LOOK (one helper for every window)
-- ============================================================
-- The bag window's rules (Zacui_Bags DressViewKit), shared: the look's
-- window (Look.dressers.window: the dialog border and background, or the
-- client's rim on the rock), the title in the game's font and gold -
-- Classic: centred just inside the border's top edge (TOP 0,-16); the
-- modern looks: in the rim's title band (TOP 0,-5) - and the look's close:
-- Classic's round button in the border's corner (TOPRIGHT -5,-5), the
-- modern red X on the rim (TOPRIGHT 1,1; Classic's where the client lacks
-- the atlas). Under ZacUI's look Look.Dress returns before reaching this.
--   Look.Dress(frame, "dialog", part) with frame._zDialogParts =
--   { title = fontstring, close = button }
local CLOSE_MODERN = { "RedButton-Exit", "RedButton-exit-pressed", "RedButton-Highlight" }

local function DialogTitle(f, look, src)
    local fs = rawget(f, "_zLookTitle")
    if not fs then
        fs = f:CreateFontString(nil, "OVERLAY")
        fs._zui_own = true
        local face = ns.GAME_FONT or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
        -- the game's face, outlined (Zac keeps the black edge on text)
        local ok, set = pcall(fs.SetFont, fs, face, 12, "OUTLINE")
        if not (ok and set) then pcall(fs.SetFont, fs, "Fonts\\FRIZQT__.TTF", 12, "OUTLINE") end
        if fs.SetShadowOffset then fs:SetShadowOffset(0, 0) end
        if fs.SetJustifyH then fs:SetJustifyH("CENTER") end
        fs:SetText(src.GetText and src:GetText() or "")
        if hooksecurefunc and src.SetText then
            hooksecurefunc(src, "SetText", function(_, t) fs:SetText(t) end)
        end
        rawset(f, "_zLookTitle", fs)
    end
    Back(src)
    fs:ClearAllPoints()
    fs:SetPoint("TOP", f, "TOP", 0, look.id == "classic" and -16 or -5)
    fs:SetTextColor(GOLD[1], GOLD[2], GOLD[3], 1)
    return fs
end

local function DialogClose(f, look, b)
    local modern = look.id ~= "classic" and Look.AtlasOK and Look.AtlasOK(CLOSE_MODERN[1])
    local art = rawget(b, "_zLookClose")
    if not art then
        Back(rawget(b, "_zA"))
        Back(rawget(b, "_zFill"))
        for _, t in ipairs(rawget(b, "_zBorder") or {}) do Back(t) end
        local n, p, h = OwnTex(b, "ARTWORK"), OwnTex(b, "ARTWORK", 1), OwnTex(b, "HIGHLIGHT")
        for _, t in ipairs({ n, p, h }) do t:SetAllPoints(b) end
        if modern then
            n:SetAtlas(CLOSE_MODERN[1]) p:SetAtlas(CLOSE_MODERN[2]) h:SetAtlas(CLOSE_MODERN[3])
        else
            FileArt(n, CLOSE_UP) FileArt(p, CLOSE_DOWN) FileArt(h, CLOSE_HI)
        end
        if h.SetBlendMode then h:SetBlendMode("ADD") end
        p:Hide()
        b:HookScript("OnMouseDown", function() n:Hide() p:Show() end)
        b:HookScript("OnMouseUp", function() p:Hide() n:Show() end)
        b:HookScript("OnLeave", function() p:Hide() n:Show() end)
        art = { normal = n, pushed = p, highlight = h, modern = modern }
        rawset(b, "_zLookClose", art)
    end
    local size = modern and 24 or 32
    b:SetSize(size, size)
    b:ClearAllPoints()
    if modern then b:SetPoint("TOPRIGHT", f, "TOPRIGHT", 1, 1)
    else b:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -5) end
end

-- ============================================================
-- THE KIT FOR ZACUI'S OWN POPUPS (2026-11-14)
-- ============================================================
-- Zac, on the first ZacUI popup he met under the WoW Forever look (the map
-- style question): "why does this popup not have the same background as the
-- bags? and it needs to be behind the text and why did you include my zui
-- icon thats not forever style" / "and like my popup menus that ask to
-- reload and stuff" / "if i pick a style everything needs to be styled like
-- that ... fucking everything ... not just some of it".
-- What was wrong, all of it in the framework and so in every popup:
--   * only a popup that named a look part was dressed at all; the reload
--     question and the rest stayed ZacUI's flat style under a game look
--   * the dress was a rim with the rock file inside it - not the window the
--     bags wear, which is the client's own panel
--   * the popup's "raise my children above my fill" pass (UIF_Dialogs
--     Relevel) lifted the look's background OVER the popup's own text and
--     title
--   * ZacUI's mark, title icon and header hairline stayed on
--   * its buttons and texts stayed ZacUI's
-- Now UI.Popup dresses EVERY popup (part "windows" unless it names one),
-- and under the modern looks the dress is the bag window's (Zacui_Bags
-- KitChrome, the one he has looked at on Forever): the client's own
-- PortraitFrameFlatTemplate without its portrait - its rim, its title band
-- with the title in the game's font and gold, its red X, its panel
-- background at the bag's 0.72 - with that background a level UNDER the
-- popup, behind everything the popup draws. Classic WoW UI, and a client
-- without the template, keep the dialog box (below), now also held under
-- the text. Buttons are the stock panel button and texts the game's font
-- (Kit.Button / Kit.Font, the bag kit's rules and numbers).
--
-- NOT CALLED SINCE 2026-11-15. Zac, after seeing it: "even in a different
-- styling keep the zui popus main menu etc the same" / "go back to how it
-- was before I told you to style zui like the style picked ingame".
-- ZacUI's own interface is ZacUI's style under every look: Look.Dress
-- returns for the "dialog" and "box" roles and nothing in the framework
-- asks for them, so no popup, window or small panel is ever a host and
-- none of the blocks below dresses anything. The kit stays here, whole,
-- for the day a game-facing window needs it; it is not to be pointed at
-- ZacUI's own interface again without his word.
local Kit = {}
Look.Kit = Kit
Kit.BG_ALPHA = 0.72
Kit.TEMPLATE = "PortraitFrameFlatTemplate"
Kit.BORDER = "ButtonFrameTemplateNoPortrait"

-- a text in the look's font: the game's face, outlined (Zac keeps the black
-- edge on text), at `size`
function Kit.Font(fs, size)
    if not (fs and fs.SetFont) then return end
    local face = ns.GAME_FONT or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    local ok, set = pcall(fs.SetFont, fs, face, size, "OUTLINE")
    if not (ok and set) then pcall(fs.SetFont, fs, "Fonts\\FRIZQT__.TTF", size, "OUTLINE") end
    if fs.SetShadowOffset then fs:SetShadowOffset(0, 0) end
    rawset(fs, "_zKitFont", size)
end

-- ZacUI's flat fill and pixel edge on a widget step back
function Kit.HideFlat(f)
    if not f then return end
    Back(rawget(f, "_zFill"))
    for _, t in ipairs(rawget(f, "_zBorder") or {}) do Back(t) end
end

-- a label of the kit's own over a ZacUI one (which steps back): the game's
-- font, never re-dressed by ZacUI's font passes; follows the ZacUI label
function Kit.Label(host, src, size, justify)
    local fs = host:CreateFontString(nil, "OVERLAY")
    fs._zui_own = true
    Kit.Font(fs, size)
    if justify and fs.SetJustifyH then fs:SetJustifyH(justify) end
    if src then
        fs:SetText(src.GetText and src:GetText() or "")
        -- (held back: ZacUI's paints colour the label again and again)
        Back(src)
        if hooksecurefunc and src.SetText then
            hooksecurefunc(src, "SetText", function(_, t) fs:SetText(t) end)
        end
    end
    return fs
end

-- a ZacUI button as the stock panel button: the three-slice up / down art,
-- the highlight sheet (ADD), the label gold, white under the mouse, grey
-- while disabled
local function PanelSlices(b)
    local p = { OwnTex(b, "BACKGROUND", 1), OwnTex(b, "BACKGROUND", 1), OwnTex(b, "BACKGROUND", 1) }
    return p
end
local function PanelPlace(b, p, cap)
    p[1]:ClearAllPoints() p[2]:ClearAllPoints() p[3]:ClearAllPoints()
    p[1]:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    p[1]:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
    p[1]:SetWidth(cap)
    p[3]:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, 0)
    p[3]:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
    p[3]:SetWidth(cap)
    p[2]:SetPoint("TOPLEFT", p[1], "TOPRIGHT", 0, 0)
    p[2]:SetPoint("BOTTOMRIGHT", p[3], "BOTTOMLEFT", 0, 0)
end
local function PanelFile(p, file)
    FileArt(p[1], file, BTN_TC[1], BTN_TC[2], 0, BTN_TC[5])
    FileArt(p[2], file, BTN_TC[2], BTN_TC[3], 0, BTN_TC[5])
    FileArt(p[3], file, BTN_TC[3], BTN_TC[4], 0, BTN_TC[5])
end
function Kit.Button(b)
    if not b or rawget(b, "_zKitBtn") then return b end
    rawset(b, "_zKitBtn", true)
    Kit.HideFlat(b)
    -- ZacUI's own hover wash and pushed shade step back
    for _, r in ipairs({ b:GetRegions() }) do
        if r ~= rawget(b, "_zFill") and r.IsObjectType and r:IsObjectType("Texture") and rawget(r, "_zui_own") then Back(r) end
    end
    local h = b:GetHeight()
    if type(h) ~= "number" or h <= 0 then h = 22 end
    local up = PanelSlices(b)
    PanelPlace(b, up, math.floor(12 * h / 22 + 0.5))
    PanelFile(up, BTN_UP)
    local hi = OwnTex(b, "HIGHLIGHT")
    hi:SetAllPoints(b)
    FileArt(hi, BTN_HI, 0, BTN_TC[4], 0, BTN_TC[5])
    if hi.SetBlendMode then hi:SetBlendMode("ADD") end
    local label = Kit.Label(b, rawget(b, "_zText"), h >= 20 and 12 or 10, "CENTER")
    label:SetPoint("CENTER", b, "CENTER", 0, 0)
    rawset(b, "_zKitLabel", label)
    -- (a button that is a switch and is on - UI.Button's SetActive, the
    -- Edit Mode bar's Grid and Snap - is lit and white, as a picked stock
    -- button is: the highlight held on it)
    local function Tint(self, hot)
        local on = rawget(self, "_zActive") and true or false
        if rawget(self, "_zDisabled") or (self.IsEnabled and not self:IsEnabled()) then label:SetTextColor(0.5, 0.5, 0.5, 1)
        elseif hot or on then label:SetTextColor(1, 1, 1, 1)
        else label:SetTextColor(GOLD[1], GOLD[2], GOLD[3], 1) end
        if on then
            if self.LockHighlight then self:LockHighlight() end
        elseif self.UnlockHighlight then
            self:UnlockHighlight()
        end
    end
    -- (under the mouse: remembered, so a paint that lands while the mouse
    -- is on it - ZacUI's hover fade paints every frame - leaves it white)
    b:HookScript("OnEnter", function(self) rawset(self, "_zKitHot", true) Tint(self, true) end)
    b:HookScript("OnLeave", function(self) rawset(self, "_zKitHot", nil) Tint(self, false) PanelFile(up, BTN_UP) end)
    b:HookScript("OnHide", function(self) rawset(self, "_zKitHot", nil) end)
    b:HookScript("OnMouseDown", function(self) if not self.IsEnabled or self:IsEnabled() then PanelFile(up, BTN_DOWN) end end)
    b:HookScript("OnMouseUp", function() PanelFile(up, BTN_UP) end)
    -- ZacUI's own paint (the accent / destructive kinds, the theme) runs
    -- first and is then put back under the kit. A caller that gives the
    -- button a paint of its own AFTER it was made (a popup's button does:
    -- UIF_Dialogs' PopupButton) wraps it with b._zKitWrap, so the kit's
    -- label still follows the button's state.
    local function After(self)
        Kit.HideFlat(self)
        Tint(self, rawget(self, "_zKitHot") and true or false)
    end
    local function Wrap(paint)
        return function(self, ...)
            if paint then paint(self, ...) end
            After(self)
        end
    end
    rawset(b, "_zKitWrap", Wrap)
    b._zPaint = Wrap(rawget(b, "_zPaint"))
    -- (and its state setters, whatever paint they end in: lit while it is
    -- the picked one, grey while it is disabled)
    if hooksecurefunc then
        for _, m in ipairs({ "SetActive", "SetDisabled", "Enable", "Disable", "SetEnabled" }) do
            if type(b[m]) == "function" then pcall(hooksecurefunc, b, m, After) end
        end
    end
    Tint(b, false)
    return b
end

-- an atlas the client knows, asked once per name (the bag kit's rule: an
-- atlas is used only when the client has it, the file cut otherwise)
local atlasOK = {}
local function AtlasOK(name)
    local v = atlasOK[name]
    if v == nil then
        v = false
        local get = C_Texture and C_Texture.GetAtlasInfo
        if get and type(name) == "string" then
            local ok, info = pcall(get, name)
            v = (ok and type(info) == "table") and true or false
        end
        atlasOK[name] = v
    end
    return v
end
local function AtlasArt(t, name)
    if not (AtlasOK(name) and t.SetAtlas) then return false end
    if t.SetTexCoord then t:SetTexCoord(0, 1, 0, 1) end
    t:SetAtlas(name)
    return true
end

-- A ZACUI CHECKBOX AS THE STOCK ONE (2026-11-14): the box, its pushed
-- state, the highlight (ADD), the gold tick, grey while disabled; the
-- label in the game's font. Blizzard's own names (every client's
-- UICheckButtonTemplate): Interface\Buttons\UI-CheckBox-Up / -Down /
-- -Highlight / -Check / -Check-Disabled, 32 px sheets whose box is 22
-- across in the middle - drawn so that box lands on ZacUI's box, whatever
-- its size (14 in a window, 18 in a popup).
local CHK_UP   = "Interface\\Buttons\\UI-CheckBox-Up"
local CHK_DOWN = "Interface\\Buttons\\UI-CheckBox-Down"
local CHK_HI   = "Interface\\Buttons\\UI-CheckBox-Highlight"
local CHK_TICK = "Interface\\Buttons\\UI-CheckBox-Check"
local CHK_TICK_OFF = "Interface\\Buttons\\UI-CheckBox-Check-Disabled"
function Kit.Check(h)
    if not h or rawget(h, "_zKitChk") then return h end
    local tick = rawget(h, "_zCheck")
    local box = tick and tick.GetParent and tick:GetParent()
    if not box then return h end
    rawset(h, "_zKitChk", true)
    Kit.HideFlat(h)
    local ck = box:GetHeight()
    if type(ck) ~= "number" or ck <= 0 then ck = 14 end
    local sz = math.floor(ck * 32 / 22 + 0.5)
    local up = OwnTex(box, "BACKGROUND", 1)
    up:SetSize(sz, sz)
    up:SetPoint("CENTER", box, "CENTER", 0, 0)
    FileArt(up, CHK_UP)
    local hi = OwnTex(h, "HIGHLIGHT")
    hi:SetSize(sz, sz)
    hi:SetPoint("CENTER", box, "CENTER", 0, 0)
    FileArt(hi, CHK_HI)
    if hi.SetBlendMode then hi:SetBlendMode("ADD") end
    tick:ClearAllPoints()
    tick:SetPoint("CENTER", box, "CENTER", 0, 0)
    tick:SetSize(sz, sz)
    local label = rawget(h, "_zText")
    if label then
        Kit.Font(label, ck >= 18 and 12 or 11)
        -- (the label is another face now: the row is as wide as it reads)
        if h._zUnfit then pcall(h._zUnfit, h) end
        if h._zPoolRefit then pcall(h._zPoolRefit, h) end
    end
    local function Off(self) return rawget(self, "_zOff") or rawget(self, "_zDisabled") end
    local function Tint(self)
        Kit.HideFlat(self)
        FileArt(tick, Off(self) and CHK_TICK_OFF or CHK_TICK)
        tick:SetVertexColor(1, 1, 1, 1)
        if label then
            if Off(self) then label:SetTextColor(0.5, 0.5, 0.5, 1) else label:SetTextColor(1, 1, 1, 1) end
        end
    end
    h:HookScript("OnMouseDown", function(self) if not Off(self) then FileArt(up, CHK_DOWN) end end)
    h:HookScript("OnMouseUp", function() FileArt(up, CHK_UP) end)
    h:HookScript("OnLeave", function() FileArt(up, CHK_UP) end)
    local own = rawget(h, "_zPaint")
    h._zPaint = function(self)
        if own then own(self) end
        Tint(self)
    end
    Tint(h)
    return h
end

-- A ZACUI EDIT BOX AS THE STOCK ONE (2026-11-14): the bag kit's search box
-- (Zacui_Bags KitSearch, the one Zac has looked at on Forever), shared -
-- the InputBox / SearchBox border cut (common-search-border-left / -middle
-- / -right, 8 | middle | 8 on 20; without the atlases the old
-- Interface\Common\Common-Input-Border cut), the text white in the
-- game's font, the hint grey. A box with a hint is a filter: it gets the
-- magnifying glass and the small clear cross, as the game's search boxes.
local FIELD_ATLAS = { "common-search-border-left", "common-search-border-middle", "common-search-border-right" }
local FIELD_FILE = "Interface\\Common\\Common-Input-Border"
local FIELD_TC = { 0, 0.0625, 0.9375, 1, 0.625 }
local FIELD_GLASS = "common-search-magnifyingglass"
local FIELD_CLEAR = "common-search-clearbutton"
function Kit.Field(host)
    if not host or rawget(host, "_zKitBtn") then return host end
    rawset(host, "_zKitBtn", true)
    Kit.HideFlat(host)
    local h = host:GetHeight()
    if type(h) ~= "number" or h <= 0 then h = 20 end
    local p = PanelSlices(host)
    PanelPlace(host, p, math.floor(8 * h / 20 + 0.5))
    if not (AtlasArt(p[1], FIELD_ATLAS[1]) and AtlasArt(p[2], FIELD_ATLAS[2]) and AtlasArt(p[3], FIELD_ATLAS[3])) then
        FileArt(p[1], FIELD_FILE, FIELD_TC[1], FIELD_TC[2], 0, FIELD_TC[5])
        FileArt(p[2], FIELD_FILE, FIELD_TC[2], FIELD_TC[3], 0, FIELD_TC[5])
        FileArt(p[3], FIELD_FILE, FIELD_TC[3], FIELD_TC[4], 0, FIELD_TC[5])
    end
    local eb = rawget(host, "editBox") or host.editBox
    local x = rawget(host, "clearButton") or host.clearButton
    local inset
    if x then
        local glass = OwnTex(host, "OVERLAY")
        if AtlasArt(glass, FIELD_GLASS) then
            glass:SetSize(10, 10)
            glass:SetPoint("LEFT", host, "LEFT", 6, -1)
            glass:SetVertexColor(0.6, 0.6, 0.6, 1)
            inset = 19
        else
            glass:Hide()
        end
        if AtlasOK(FIELD_CLEAR) then
            if rawget(x, "_zA") then x._zA:SetAlpha(0) end
            local t = OwnTex(x, "ARTWORK")
            t:SetSize(10, 10)
            t:SetPoint("CENTER", x, "CENTER", 0, 0)
            AtlasArt(t, FIELD_CLEAR)
            t:SetAlpha(0.5)
            x:HookScript("OnEnter", function() t:SetAlpha(1) end)
            x:HookScript("OnLeave", function() t:SetAlpha(0.5) end)
        end
    end
    if eb then
        if inset then eb:SetPoint("TOPLEFT", host, "TOPLEFT", inset, -2) end
        Kit.Font(eb, h >= 26 and 12 or 10)
        eb:SetTextColor(1, 1, 1, 1)
    end
    -- the hint follows the text's start
    for _, r in ipairs({ host:GetRegions() }) do
        if r.IsObjectType and r:IsObjectType("FontString") then
            if inset then r:SetPoint("LEFT", host, "LEFT", inset + 1, 0) end
            Kit.Font(r, h >= 26 and 12 or 10)
            r:SetTextColor(0.5, 0.5, 0.5, 1)
            r._zPaint = function(self) self:SetTextColor(0.5, 0.5, 0.5, 1) end
        end
    end
    -- ZacUI's own paint (the focus edge) runs first and is put back under
    -- the kit
    local own = rawget(host, "_zPaint")
    host._zPaint = function(self)
        if own then own(self) end
        Kit.HideFlat(self)
        if eb then eb:SetTextColor(1, 1, 1, 1) end
    end
    return host
end

-- A ZACUI CARD (UI.Card, a titled group in a window) AS THE LOOK'S SMALL
-- BOX (2026-11-14): the bag kit's small box (Zacui_Bags KitBox) - the
-- tooltip edge and fill of Classic, the client's tooltip slice on the
-- modern looks (Core_Look's own primitive) - under the card's content;
-- ZacUI's fill, pixel edge and accent stripe step back, the title is gold.
function Kit.Card(card, part)
    if not card or rawget(card, "_zKitBtn") then return card end
    local lk = Look.For(part or "windows")
    if not (lk and lk.id ~= "zacui" and Look.AddFill and lk.border) then return card end
    rawset(card, "_zKitBtn", true)
    local function Settle(self)
        Kit.HideFlat(self)
        Back(rawget(self, "_zAccent"))
        local t = rawget(self, "_zTitle")
        if t and t.SetTextColor then t:SetTextColor(GOLD[1], GOLD[2], GOLD[3], 1) end
    end
    local ok, edge = pcall(Look.AddFill, card, lk.border, lk.bgSmall or lk.bgTexture, 1)
    if ok and type(edge) == "table" and edge.SetFrameLevel and card.GetFrameLevel then
        edge:SetFrameLevel(math.max(0, (card:GetFrameLevel() or 1) - 1))
    end
    local own = rawget(card, "_zPaint")
    card._zPaint = function(self)
        if own then own(self) end
        Settle(self)
    end
    Settle(card)
    return card
end

-- A ZACUI SCROLL BAR AS THE STOCK ONE (2026-11-15): the game's scroll knob
-- (the look's scrollThumb; Interface\\Buttons\\UI-ScrollBar-Knob, the
-- 18 x 24 cut every UIPanelScrollBar uses), one size whatever the list's
-- length, no flat rail and no accent under the mouse. UI.ScrollArea reads
-- bar._zKitKnob and leaves the knob's size and colour alone.
local KNOB = "Interface\\Buttons\\UI-ScrollBar-Knob"
local KNOB_TC = { 0.20, 0.80, 0.125, 0.875 }
function Kit.Scroll(bar, part)
    if not bar or rawget(bar, "_zKitKnob") then return bar end
    local thumb, track = rawget(bar, "_zThumb"), rawget(bar, "_zTrack")
    if not thumb then return bar end
    rawset(bar, "_zKitKnob", true)
    if track then
        Kit.HideFlat(track)
        local own = rawget(track, "_zPaint")
        track._zPaint = function(self)
            if own then own(self) end
            Kit.HideFlat(self)
        end
    end
    local lk = Look.For(part or "windows")
    local file = (lk and type(lk.scrollThumb) == "string" and lk.scrollThumb ~= "") and lk.scrollThumb or KNOB
    FileArt(thumb, file, KNOB_TC[1], KNOB_TC[2], KNOB_TC[3], KNOB_TC[4])
    thumb:SetSize(18, 24)
    thumb:SetVertexColor(1, 1, 1, 1)
    return bar
end

-- A ZACUI SLIDER AS THE STOCK ONE (2026-11-15): the game's slider groove
-- (every client's OptionsSliderTemplate: Interface\\Buttons\\
-- UI-SliderBar-Background tiled 8 in an 8 px UI-SliderBar-Border edge,
-- insets 3 / 3 / 6 / 6, 17 high) and its thumb (UI-SliderBar-Button-
-- Horizontal, 32 x 32); ZacUI's pill track, its accent fill and its disc
-- step back; the value box of the settings-size slider is the stock input
-- box. UI.Slider hands its parts over as host._zSl.
local SL_BG = "Interface\\Buttons\\UI-SliderBar-Background"
local SL_EDGE = "Interface\\Buttons\\UI-SliderBar-Border"
local SL_THUMB = "Interface\\Buttons\\UI-SliderBar-Button-Horizontal"
function Kit.Slider(host)
    if not host or rawget(host, "_zKitBtn") then return host end
    local p = rawget(host, "_zSl")
    if type(p) ~= "table" or not (p.thumb and p.track) then return host end
    rawset(host, "_zKitBtn", true)
    local function Settle()
        if p.trackPill then p.trackPill:Show(false) end
        if p.fillPill then p.fillPill:Show(false) end
        if p.block then p.block:Hide() end
        Kit.HideFlat(p.track)
        if p.ring then Kit.HideFlat(p.ring) end
        p.thumb:SetVertexColor(1, 1, 1, 1)
    end
    -- the groove: a frame of its own under the slider, 17 high on the track
    local okG, groove = pcall(CreateFrame, "Frame", nil, p.track, BackdropTemplateMixin and "BackdropTemplate" or nil)
    if okG and groove and groove.SetBackdrop then
        groove._zui_own = true
        groove:SetPoint("LEFT", p.track, "LEFT", -2, 0)
        groove:SetPoint("RIGHT", p.track, "RIGHT", 2, 0)
        groove:SetHeight(17)
        groove:SetFrameLevel(math.max(0, (p.track:GetFrameLevel() or 1)))
        pcall(groove.SetBackdrop, groove, { bgFile = SL_BG, edgeFile = SL_EDGE, tile = true, tileSize = 8, edgeSize = 8,
            insets = { left = 3, right = 3, top = 6, bottom = 6 } })
        rawset(host, "_zKitGroove", groove)
    end
    FileArt(p.thumb, SL_THUMB)
    p.thumb:SetSize(32, 32)
    if p.box and p.value then
        p.box.editBox = p.value
        Kit.Field(p.box)
    end
    local own = rawget(host, "_zPaint")
    host._zPaint = function(self)
        if own then own(self) end
        Settle()
        if p.box then Kit.HideFlat(p.box) end
    end
    Settle()
    return host
end

-- A ZACUI RESIZE GRIP AS THE STOCK ONE (2026-11-15): the chat window's size
-- grabber (Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up / -Highlight /
-- -Down, every client's), in place of ZacUI's three-line grip.
local GRIP_UP = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up"
local GRIP_HI = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight"
local GRIP_DOWN = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down"
function Kit.Grip(grip)
    if not grip or rawget(grip, "_zKitBtn") then return grip end
    rawset(grip, "_zKitBtn", true)
    -- ZacUI's three-line art is put away (its lit / held animation finds
    -- no art and does nothing); kept on the grip for a return to ZacUI's
    -- look at the next reload
    local art = grip.art
    if art then
        if art.Hide then art:Hide() end
        Back(art)
        rawset(grip, "_zArtKept", art)
        grip.art = nil
    end
    local up = OwnTex(grip, "ARTWORK")
    up:SetAllPoints(grip)
    FileArt(up, GRIP_UP)
    local hi = OwnTex(grip, "HIGHLIGHT")
    hi:SetAllPoints(grip)
    FileArt(hi, GRIP_HI)
    if hi.SetBlendMode then hi:SetBlendMode("ADD") end
    grip:HookScript("OnMouseDown", function() FileArt(up, GRIP_DOWN) end)
    grip:HookScript("OnMouseUp", function() FileArt(up, GRIP_UP) end)
    grip:HookScript("OnHide", function() FileArt(up, GRIP_UP) end)
    return grip
end

-- EVERYTHING ALREADY BUILT INSIDE A FRAME THAT HAS JUST BEEN DRESSED
-- (2026-11-15). Each ZacUI building block says what it is (rawget "_zIs":
-- button, check, field, card, slider, scroll, grip, text): a window that
-- was put together by hand, or filled before its dress ran, is walked
-- once and every block in it gets the same kit a block made afterwards
-- asks for itself (Kit.Host). So dressing a window is one call wherever
-- it was built.
-- (a multi-line text box: the look's small box round it, the game's font
-- in it - the input border art is one line high and does not stretch)
function Kit.TextBox(host, part)
    if not host or rawget(host, "_zKitBtn") then return host end
    Kit.Card(host, part)
    local eb = rawget(host, "editBox") or host.editBox
    if eb and not rawget(eb, "_zKitFont") and eb.GetFont then
        local _, at = eb:GetFont()
        Kit.Font(eb, type(at) == "number" and at > 0 and at or 12)
    end
    return host
end
local ADOPT = {
    textbox = function(o, part) Kit.TextBox(o, part) end,
    button = function(o) Kit.Button(o) end,
    check = function(o) Kit.Check(o) end,
    field = function(o) Kit.Field(o) end,
    card = function(o, part) Kit.Card(o, part) end,
    slider = function(o) Kit.Slider(o) end,
    scroll = function(o, part) Kit.Scroll(o, part) end,
    grip = function(o) Kit.Grip(o) end,
}
function Kit.Adopt(root, part)
    if not root then return end
    local function Walk(f, d)
        if d > 14 or rawget(f, "_zLookOver") then return end
        local fn = ADOPT[rawget(f, "_zIs") or false]
        if fn and rawget(f, "_zNoLook") ~= true then pcall(fn, f, part) end
        if f.GetRegions then
            for _, r in ipairs({ f:GetRegions() }) do
                if rawget(r, "_zIs") == "text" and not rawget(r, "_zKitFont") and rawget(r, "_zNoLook") ~= true and r.GetFont then
                    local _, at = r:GetFont()
                    Kit.Font(r, type(at) == "number" and at > 0 and at or 12)
                end
            end
        end
        if f.GetChildren then
            for _, c in ipairs({ f:GetChildren() }) do Walk(c, d + 1) end
        end
    end
    Walk(root, 0)
end

-- the window or popup a frame sits in when that one wears a game look
-- through this kit (nil otherwise): what a building block asks at creation
function Kit.Host(frame)
    if not Kit.live then return nil end
    local n = 0
    while frame and n < 16 do
        if rawget(frame, "_zLookAuto") then return frame end
        frame = frame.GetParent and frame:GetParent() or nil
        n = n + 1
    end
    return nil
end

-- the client's own panel on a ZacUI popup (the modern looks). nil when the
-- client cannot build it whole: the caller keeps the dialog box.
local tplOK
local function TemplateOK()
    if tplOK == nil then
        tplOK = false
        local X = C_XMLUtil
        if X and X.GetTemplateInfo then
            local ok, info = pcall(X.GetTemplateInfo, Kit.TEMPLATE)
            tplOK = (ok and info ~= nil) and true or false
        end
    end
    return tplOK
end
Kit.TemplateOK = TemplateOK

function Kit.Chrome(f, parts)
    local c = rawget(f, "_zKitChrome")
    if c then return c end
    if c == false or not TemplateOK() then return nil end
    local ok, made = pcall(CreateFrame, "Frame", nil, f, Kit.TEMPLATE)
    c = ok and made or nil
    local tc = c and c.TitleContainer
    if not (c and c.NineSlice and tc and tc.TitleText and c.CloseButton) then
        if c and c.Hide then c:Hide() end
        rawset(f, "_zKitChrome", false)
        return nil
    end
    rawset(f, "_zKitChrome", c)
    rawset(c, "_zLookOver", true)           -- (the popup's relevel pass leaves it where this puts it)
    c:SetAllPoints(f)
    c:EnableMouse(false)
    -- no portrait: the rim without its ring, the title across the band
    if c.SetBorder then pcall(c.SetBorder, c, Kit.BORDER) end
    if c.SetPortraitShown then pcall(c.SetPortraitShown, c, false) end
    local pc = rawget(c, "PortraitContainer") or c.PortraitContainer
    if pc and pc.Hide then pc:Hide() end
    if c.SetTitleOffsets then pcall(c.SetTitleOffsets, c, 24, -24) end
    local title = tc.TitleText
    Kit.Font(title, 12)
    title:SetTextColor(GOLD[1], GOLD[2], GOLD[3], 1)
    local src = parts and parts.title
    if src then
        title:SetText(src.GetText and src:GetText() or "")
        if hooksecurefunc and src.SetText then
            hooksecurefunc(src, "SetText", function(_, t) title:SetText(t) end)
        end
        Back(src)
    end
    c.CloseButton:SetScript("OnClick", function()
        if ns.UI and ns.UI.CloseWindow then ns.UI.CloseWindow(f) else f:Hide() end
    end)
    c.CloseButton:Show()
    local zclose = parts and parts.close
    if zclose then
        -- (a popup made without a close keeps none)
        if zclose.IsShown and not zclose:IsShown() then c.CloseButton:Hide() end
        Back(zclose)
        if zclose.EnableMouse then zclose:EnableMouse(false) end
    end
    -- ZacUI's own window steps back: the fill, the edge, the title band
    -- (still the drag handle, drawn by nothing)
    Kit.HideFlat(f)
    local bar = rawget(f, "titleBar")
    if bar then
        Back(rawget(bar, "_zFill"))
        Back(rawget(bar, "_zArt"))
        Back(rawget(bar, "_zFlatRule"))
    end
    -- THE BACKGROUND, ON THE POPUP'S OWN BACKGROUND LAYER (2026-11-15).
    -- The template brings its background as a frame of its own (Bg:
    -- FlatPanelBackgroundTemplate - two corner pieces, a bottom edge and
    -- the top section, in the panel's colour). Until today that frame was
    -- put a frame level UNDER the popup so the popup's text drew over it;
    -- on WoW Forever it then drew nowhere (Zac: "no background" - the
    -- world showed through the popup). A frame's own layers are the one
    -- order the client always keeps: the pieces move onto the popup
    -- itself, at the very bottom of its BACKGROUND layer, where ZacUI's
    -- own fill is drawn under ZacUI's look - behind every text and every
    -- child of the popup, whatever level any frame is at. Each keeps the
    -- anchors the template gave it (said again by name, so they hold
    -- after the move) and is the bag window's 0.72 of what it was.
    local function Ground()
        if rawget(f, "_zKitGround") ~= nil then return rawget(f, "_zKitGround") end
        local bg = rawget(c, "Bg") or c.Bg
        if not (type(bg) == "table" and bg.GetRegions) then rawset(f, "_zKitGround", false) return false end
        local moved = {}
        for _, r in ipairs({ bg:GetRegions() }) do
            if r.SetParent and r.SetDrawLayer and r.GetNumPoints then
                local pts = {}
                for i = 1, r:GetNumPoints() do
                    local point, rel, relPoint, x, y = r:GetPoint(i)
                    pts[#pts + 1] = { point, rel or bg, relPoint or point, x or 0, y or 0 }
                end
                r:SetParent(f)
                if #pts > 0 then
                    r:ClearAllPoints()
                    for _, q in ipairs(pts) do r:SetPoint(q[1], q[2], q[3], q[4], q[5]) end
                end
                r:SetDrawLayer("BACKGROUND", -8)
                local a = r.GetAlpha and r:GetAlpha()
                r:SetAlpha((type(a) == "number" and a or 1) * Kit.BG_ALPHA)
                moved[#moved + 1] = r
            end
        end
        if #moved == 0 then moved = false end
        rawset(f, "_zKitGround", moved)
        return moved
    end
    local okG, ground = pcall(Ground)
    if not okG then ground = false rawset(f, "_zKitGround", false) end
    -- THE LEVELS: the rim, the title and the X over the popup (they sit on
    -- its edges and take the click), where the template itself keeps them
    -- from a base level: the rim at +500, the title and the X at +510.
    -- (Until today the X was put at +40: UNDER the rim, whose corner then
    -- covered it - the popup had no X.) The base stays low enough for the
    -- template's own sum (it refuses a level of 10000 or more).
    local function Levels()
        local lv = f:GetFrameLevel() or 1
        local base = math.min(lv + 1, 9400)
        pcall(function()
            if c.SetFrameLevelsFromBaseLevel then c:SetFrameLevelsFromBaseLevel(base) end
            c:SetFrameLevel(base)
        end)
        -- (the background's frame is empty now; where its pieces could not
        -- be moved it sits at the popup's own level, as the bag's does)
        pcall(function()
            local bg = rawget(c, "Bg") or c.Bg
            if not bg then return end
            if bg.SetFixedFrameLevel then bg:SetFixedFrameLevel(false) end
            bg:SetFrameLevel(lv)
            if not ground then bg:SetAlpha(Kit.BG_ALPHA) end
        end)
    end
    rawset(f, "_zLookLevels", Levels)
    Levels()
    c:HookScript("OnShow", Levels)
    return c
end

Look.dressers.dialog = function(f, look, part)
    local parts = rawget(f, "_zDialogParts")
    if type(parts) ~= "table" then parts = {} end
    -- ZacUI's own marks are not the look's: the title mark (hidden as
    -- well as cleared: it is an animated one) and the header hairline. A
    -- popup's own picture (its subject) stays.
    if parts.mark then
        if parts.mark.Hide then parts.mark:Hide() end
        Back(parts.mark)
    end
    Back(parts.rule)
    -- the building blocks made inside it from now on ask the look
    -- themselves (UI.Button: Kit.Host)
    rawset(f, "_zLookAuto", true)
    rawset(f, "_zLookPart", part or "windows")
    Kit.live = true
    local chrome = (look.id ~= "classic") and Kit.Chrome(f, parts) or nil
    if not chrome then
        local window = Look.dressers.window
        if window then window(f, look, part) end
        -- (the dialog box sits under the popup's own text: the popup's
        -- relevel pass must not lift it)
        local edge = rawget(f, "_zui_edge") or rawget(f, "_zLookEdge")
        if edge then rawset(edge, "_zLookUnder", true) end
        if parts.title then DialogTitle(f, look, parts.title) end
        if parts.close then DialogClose(f, look, parts.close) end
    end
    for _, b in ipairs(rawget(f, "buttons") or {}) do Kit.Button(b) end
    for _, fs in ipairs(rawget(f, "_zKitTexts") or {}) do Kit.Font(fs, rawget(fs, "_zKitSize") or 12) end
    -- whatever was built inside it before this ran
    Kit.Adopt(f, part or "windows")
end

-- A SMALL ZACUI PANEL THAT IS NOT A WINDOW (2026-11-15): a callout, a
-- strip along the screen's edge, a tool bar - the look's small box (the
-- tooltip edge and fill of Classic, the client's tooltip slice on the
-- modern looks: the box round the bag's gold list), under the panel's own
-- content; ZacUI's fill, pixel edge and accent marks step back, its close
-- is the look's, an arrow or pointer it carries turns the look's gold,
-- and everything in it - made before or after - is the look's.
--   frame._zDialogParts = { close = button, marks = { textures to hide },
--                           pointers = { textures to turn gold } }
--   Look.Dress(frame, "box", part)
Look.dressers.box = function(f, look, part)
    local parts = rawget(f, "_zDialogParts")
    if type(parts) ~= "table" then parts = {} end
    local function Settle(self)
        Kit.HideFlat(self)
        for _, t in ipairs(rawget(self, "_zEdges") or {}) do Back(t) end
        -- (a panel made with the older backdrop helper, ns.SkinBackdrop)
        local cbg = rawget(self, "_zui_cbg")
        if cbg and cbg ~= rawget(self, "_zui_edge") then Back(cbg) end
        local strips = rawget(self, "_zui_borderTex")
        if strips and not strips._zEdge then for _, t in ipairs(strips) do Back(t) end end
        for _, t in ipairs(parts.marks or {}) do Back(t) end
        for _, t in ipairs(parts.texts or {}) do
            if not rawget(t, "_zKitFont") and t.GetFont then
                local _, at = t:GetFont()
                Kit.Font(t, type(at) == "number" and at > 0 and at or 12)
            end
        end
        for _, t in ipairs(parts.pointers or {}) do
            if t.SetVertexColor then t:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1) end
        end
    end
    if Look.AddFill and look.border then
        local ok, edge = pcall(Look.AddFill, f, look.border, look.bgSmall or look.bgTexture, 1)
        if ok and type(edge) == "table" and edge.SetFrameLevel and f.GetFrameLevel then
            edge:SetFrameLevel(math.max(0, (f:GetFrameLevel() or 1) - 1))
            rawset(edge, "_zLookUnder", true)
        end
    end
    if parts.close then DialogClose(f, look, parts.close) end
    local own = rawget(f, "_zPaint")
    f._zPaint = function(self, ...)
        if own then own(self, ...) end
        Settle(self)
    end
    Settle(f)
    rawset(f, "_zLookAuto", true)
    rawset(f, "_zLookPart", part or "windows")
    Kit.live = true
    Kit.Adopt(f, part or "windows")
end
