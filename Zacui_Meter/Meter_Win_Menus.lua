-- Meter_Win_Menus - the meter windows' menus: the house popup list
-- (one level of submenus, a tooltip per entry, the current pick marked),
-- and the three menus a window's header opens with it - the mode menu
-- (Damage / Healing / Actions / Threat), the segment menu (the fight in
-- progress, the overall, then each kept fight by name with its length)
-- and the window's own settings menu.
-- Part of ZacUI; load order is set by the TOC (after Meter_Windows).
--
-- Meter v2 (2026-11-07, Zac: "his damage meters and stuff are so much
-- better than mine"). No Blizzard dropdown: the list is ZacUI's own
-- frames, so nothing here can taint, and it is the same list on every
-- game version. Everything a menu writes is a saved setting the Meter
-- page also shows.

local ADDON_NAME = ...
-- Zacui_Meter is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

local Meter = ns.Meter
if not Meter then return end
local Print = ns.Print

local format, floor = string.format, math.floor

local Menu = {}
Meter.Menu = Menu

local ROW_H = 18
local PAD = 4
local MIN_W = 150
local HOLD = 0.35          -- seconds the list stays after the mouse leaves it

-- ============================================================
-- THE LIST - one main list and one submenu, rows pooled
-- ============================================================
local main, sub

local function MeterFont(fs, size)
    fs:SetFont(Meter.FontPath(), size)
    if ns.TrackHouseFont then
        ns.TrackHouseFont(fs, function(s) pcall(s.SetFont, s, Meter.FontPath(), size) end)
    end
end

local function Build(name, level)
    local m = CreateFrame("Frame", name, UIParent)
    m:SetFrameStrata("FULLSCREEN_DIALOG")
    m:SetFrameLevel(level)
    m:SetClampedToScreen(true)
    -- (2026-11-08) the settings window's menu colours (UI.S: the dropdown
    -- list's fill at 0.98, a white 0.20 edge), as every ZacUI popup
    local S = ns.UI and ns.UI.S
    local bg = m:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    if S then
        bg:SetColorTexture(S.DD_BG.r, S.DD_BG.g, S.DD_BG.b, S.DD_BG_HA)
    else
        bg:SetColorTexture(0.05, 0.05, 0.06, 0.97)
    end
    if S and ns.Pixel and ns.Pixel.Border then ns.Pixel.Border(m, 1, 1, 1, S.DD_BRD_A, "BORDER")
    elseif ns.AddPixelBorder then ns.AddPixelBorder(m) end
    m._zPopup = true
    m.buttons = {}
    m:Hide()
    return m
end

local function Over()
    if main and main:IsShown() and main:IsMouseOver() then return true end
    if sub and sub:IsShown() and sub:IsMouseOver() then return true end
    if main and main.anchor and main.anchor.IsMouseOver and main.anchor:IsMouseOver() then return true end
    return false
end

function Menu.Hide()
    if sub then sub:Hide() end
    if main then main:Hide() main.anchor = nil end
    GameTooltip:Hide()
end

-- a leave from any row or either list: gone a moment later unless the
-- mouse is still on one of them
local leaving
local function Leave()
    if leaving then return end
    leaving = true
    C_Timer.After(HOLD, function()
        leaving = nil
        if main and main:IsShown() and not Over() then Menu.Hide() end
    end)
end

local Lay   -- forward (a row's hover opens its submenu through it)

local function Row(m, i)
    local b = m.buttons[i]
    if b then return b end
    b = CreateFrame("Button", nil, m)
    b:SetHeight(ROW_H)
    b:SetPoint("TOPLEFT", m, "TOPLEFT", PAD, -((i - 1) * ROW_H) - PAD)
    b:SetPoint("RIGHT", m, "RIGHT", -PAD, 0)
    b:RegisterForClicks("LeftButtonUp")
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)
    b.text = b:CreateFontString(nil, "OVERLAY")
    MeterFont(b.text, 11)
    b.text:SetPoint("LEFT", 4, 0)
    b.text:SetShadowColor(0, 0, 0, 1)
    b.text:SetShadowOffset(1, -1)
    b.text:SetJustifyH("LEFT")
    b.text:SetWordWrap(false)
    -- a second text at the right: a fight's length, a submenu's arrow
    b.right = b:CreateFontString(nil, "OVERLAY")
    MeterFont(b.right, 11)
    b.right:SetPoint("RIGHT", -4, 0)
    b.right:SetJustifyH("RIGHT")
    b.right:SetShadowColor(0, 0, 0, 1)
    b.right:SetShadowOffset(1, -1)
    b.text:SetPoint("RIGHT", b.right, "LEFT", -4, 0)
    -- a separator: a hairline across the row
    b.sep = b:CreateTexture(nil, "ARTWORK")
    b.sep:SetHeight(1)
    b.sep:SetPoint("LEFT", 6, 0)
    b.sep:SetPoint("RIGHT", -6, 0)
    b.sep:SetColorTexture(1, 1, 1, 0.12)
    b.sep:Hide()
    m.buttons[i] = b
    return b
end

-- the item under the mouse: its tooltip (the mode's meaning, the window
-- option's explanation) and its submenu
local function Enter(b)
    local item = b.item
    if not item then return end
    if item.tip then
        GameTooltip:SetOwner(b, "ANCHOR_LEFT")
        local t, c = ns.GetColor("tooltip", "title"), ns.GetColor("tooltip", "body")
        GameTooltip:AddLine(item.text, t.r, t.g, t.b)
        GameTooltip:AddLine(item.tip, c.r, c.g, c.b, true)
        GameTooltip:Show()
    end
    if b.menu == main then
        if item.children and not item.disabled then
            sub = sub or Build("ZacUIMeterMenuSub", 220)
            Lay(sub, item.children)
            sub:ClearAllPoints()
            local right, w = main:GetRight(), sub:GetWidth() or 0
            local screen = UIParent:GetRight()
            if right and screen and right + w > screen then
                sub:SetPoint("TOPRIGHT", b, "TOPLEFT", -PAD, PAD)
            else
                sub:SetPoint("TOPLEFT", b, "TOPRIGHT", PAD, PAD)
            end
            sub:Show()
        elseif sub then
            sub:Hide()
        end
    end
end

local measure
Lay = function(m, items)
    if not measure then
        measure = UIParent:CreateFontString(nil, "OVERLAY")
        MeterFont(measure, 11)
        measure:Hide()
    end
    local width = MIN_W
    local n = 0
    for _, item in ipairs(items) do
        n = n + 1
        local b = Row(m, n)
        b.menu = m
        b.item = item
        local active = ns.GetColor("ui", "accent")
        if item == "---" or item.sep then
            b.item = nil
            b.text:SetText("")
            b.right:SetText("")
            b.sep:Show()
            b:EnableMouse(false)
            b:SetScript("OnClick", nil)
        else
            b.sep:Hide()
            b:EnableMouse(true)
            b.text:SetText(item.text or "")
            if item.disabled then
                b.text:SetTextColor(0.5, 0.5, 0.5, 1)
            elseif item.active then
                b.text:SetTextColor(active.r, active.g, active.b, 1)
            else
                b.text:SetTextColor(1, 1, 1, 1)
            end
            local r = item.right or (item.children and ">" or "")
            b.right:SetText(r)
            if item.rightColor then
                local c = ns.GetColor(item.rightColor[1], item.rightColor[2])
                b.right:SetTextColor(c.r, c.g, c.b, 1)
            else
                b.right:SetTextColor(0.7, 0.7, 0.7, 1)
            end
            measure:SetText((item.text or "") .. "    " .. r)
            local sw = (measure:GetStringWidth() or 0) + 24
            if sw > width then width = sw end
            b:SetScript("OnClick", function()
                if item.disabled or item.children then return end
                Menu.Hide()
                if item.func then item.func() end
            end)
        end
        b:SetScript("OnEnter", function(self) Enter(self) end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() Leave() end)
        b:Show()
    end
    for i = n + 1, #m.buttons do m.buttons[i]:Hide() m.buttons[i].item = nil end
    m:SetSize(floor(width + 0.5), n * ROW_H + PAD * 2)
end

-- items: { text, tip, func, active, right, rightColor, children, disabled }
-- or "---". opts.point / relPoint / x / y place it against the anchor
-- (below its right edge unless told otherwise).
function Menu.Show(anchor, items, opts)
    main = main or Build("ZacUIMeterMenu", 210)
    if not main.scripted then
        main.scripted = true
        main:SetScript("OnLeave", Leave)
        main:SetScript("OnHide", function(self)
            if sub then sub:Hide() end
            if self.UnregisterEvent then pcall(self.UnregisterEvent, self, "GLOBAL_MOUSE_DOWN") end
        end)
        -- Escape closes it (the game hides UISpecialFrames on Escape)
        if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "ZacUIMeterMenu") end
        -- a click anywhere else closes it (registered only while it is
        -- open: one event per mouse press, nothing at rest)
        main:SetScript("OnEvent", function(self, event)
            if event == "GLOBAL_MOUSE_DOWN" and self:IsShown() and not Over() then
                C_Timer.After(0, function() if not Over() then Menu.Hide() end end)
            end
        end)
    end
    if sub then sub:Hide() end
    opts = opts or {}
    Lay(main, items)
    main.anchor = anchor
    main:ClearAllPoints()
    main:SetPoint(opts.point or "TOPRIGHT", anchor, opts.relPoint or "BOTTOMRIGHT", opts.x or 0, opts.y or -2)
    main:Show()
    if main.RegisterEvent then pcall(main.RegisterEvent, main, "GLOBAL_MOUSE_DOWN") end
    return main
end

function Menu.IsShown() return main ~= nil and main:IsShown() end
function Menu.Frame() return main end
function Menu.SubFrame() return sub end

-- ============================================================
-- THE MODE MENU - the groups, each statistic with its meaning on hover
-- ============================================================
local function Entry(win, key, disp)
    return { text = disp.label, tip = disp.desc, active = win.settings.display == key,
        func = function() win:SetDisplay(key) end }
end

function Menu.ModeItems(win)
    local D = Meter.DISPLAYS
    local items = {}
    local cur = win.settings.display
    for _, g in ipairs(Meter.GROUPS or {}) do
        local children = {}
        local active = false
        for _, key in ipairs(g.keys) do
            local disp = D[key]
            if disp then
                children[#children + 1] = Entry(win, key, disp)
                if key == cur then active = true end
            end
        end
        if #children > 0 then
            items[#items + 1] = { text = g.label, tip = g.desc, active = active, children = children }
        end
    end
    if Meter.Threat then
        items[#items + 1] = "---"
        items[#items + 1] = { text = "Threat", tip = Meter.THREAT_DESC, active = cur == "threat",
            children = {
                { text = "Threat (TinyThreat)", tip = Meter.THREAT_DESC, active = cur == "threat",
                  func = function() win:SetDisplay("threat") end },
                { text = "Back to the group meter",
                  tip = "Damage, healing, deaths and the rest - whichever this window showed last.",
                  active = cur ~= "threat",
                  func = function() win:SetDisplay(win.settings.lastMeterDisplay or "damage_done") end },
            } }
    end
    return items
end

function Menu.Mode(win, anchor)
    return Menu.Show(anchor or win.frame, Menu.ModeItems(win))
end

-- ============================================================
-- THE SEGMENT MENU
-- ============================================================
local SEG_MAX = 20

local function MyDeaths(combat)
    local n = 0
    local me = Meter.playerName
    if not (me and Meter.DeathsFor) then return 0 end
    for _, dt in ipairs(Meter.DeathsFor(combat)) do
        if dt.name == me then n = n + 1 end
    end
    return n
end

function Menu.SegmentItems(win)
    local items = {}
    local seg = win.settings.segment or 0
    local function Pick(s) return function() win:SetSegment(s) end end
    local live = Meter.inCombat
    local cur = Meter.current
    items[1] = { text = "Current fight",
        tip = "The fight in progress, or the last one when nobody is fighting.",
        active = seg == 0, func = Pick(0),
        right = (live and cur) and Meter.Clock(cur:GetCombatTime()) or nil }
    local ov = Meter.overall
    local n = ov and ov.segmentsAdded or 0
    items[2] = { text = live and "Overall (live)" or "Overall",
        tip = "Every fight of the night added up" .. (live and ", the one in progress included." or "."),
        active = seg == -1, func = Pick(-1),
        right = n > 0 and (n .. (n == 1 and " fight" or " fights")) or nil }
    local segs = Meter.segments or {}
    if #segs > 0 then items[#items + 1] = "---" end
    for i = 1, math.min(#segs, SEG_MAX) do
        local c = segs[i]
        local name = c:Name()
        local deaths = MyDeaths(c)
        local rc
        if c.isBoss then rc = c.isBoss.killed and { "text", "green" } or { "text", "red" } end
        items[#items + 1] = { text = "#" .. i .. "  " .. name,
            right = Meter.Clock(c:GetCombatTime()), rightColor = rc,
            tip = (c.isBoss and (c.isBoss.killed and "Boss killed" or "Wipe") or "Trash")
                .. (deaths > 0 and format(", you died %d time%s", deaths, deaths == 1 and "" or "s") or "")
                .. ".",
            active = seg == i, func = Pick(i) }
    end
    if #segs > SEG_MAX then
        items[#items + 1] = { text = "... and " .. (#segs - SEG_MAX) .. " more", disabled = true }
    end
    return items
end

function Menu.Segment(win, anchor)
    return Menu.Show(anchor or win.frame, Menu.SegmentItems(win))
end

-- ============================================================
-- THE WINDOW'S SETTINGS MENU
-- ============================================================
local SCALES = { 80, 90, 100, 110, 125 }

function Menu.SettingsItems(win)
    local s = win.settings
    local d = Meter.Look()
    local items = {}
    local function Toggle(key, text, tip, dflt, after)
        local on = s[key]
        if on == nil then on = dflt end
        items[#items + 1] = { text = text, tip = tip, active = on and true or false,
            func = function()
                s[key] = not on
                if after then after(not on) end
                if ns.SettingsChanged then ns.SettingsChanged("meter.menu") end
            end }
    end
    Toggle("locked", "Lock position and size", "Locked, the window will not drag or resize. The menus still work.", false,
        function() if win.UpdateLock then win:UpdateLock() end end)
    Toggle("clickthrough", "Click-through in combat", "The mouse goes straight through the window while fighting.", false,
        function() win:ApplyClickthrough() end)
    if s.display ~= "threat" then
        Toggle("hideClock", "Hide the fight clock", "The title shows the mode alone.", false,
            function() Meter.UpdateTitle(win) end)
        Toggle("syncSegments", "Sync segments with other windows",
            "Picking a fight here switches every window that has this on.", false)
        Toggle("autoCurrent", "Back to the current fight on a new pull",
            "A window looking at a past fight goes back to the fight in progress when one starts.", true)
    end
    Toggle("snap", "Snap to other windows", "Dragging or resizing lines up with the nearest meter window.", true)
    local scale = {}
    local cur = tonumber(s.scale) or 1
    for _, pct in ipairs(SCALES) do
        scale[#scale + 1] = { text = pct .. "%", active = math.abs(cur * 100 - pct) < 0.5,
            func = function()
                s.scale = pct / 100
                if Meter.RestyleAll then Meter.RestyleAll() end
                if ns.SettingsChanged then ns.SettingsChanged("meter.menu") end
            end }
    end
    items[#items + 1] = { text = "Scale", tip = "This window's size on screen, rows and text together.", children = scale }
    -- (2026-11-08) what the header had no room for at this width
    local W = Meter.Win
    if W and W.Dropped and not win.preview then
        if W.Dropped(win, "segment") and s.display ~= "threat" then
            items[#items + 1] = { text = "Fight", tip = "The fight in progress, the whole night, or any past fight by name.",
                children = Menu.SegmentItems(win) }
        end
        if W.Dropped(win, "report") then
            items[#items + 1] = { text = "Report to chat...", tip = "Pastes the rows to a chat channel.",
                func = function() win:ToolbarClick("report", "LeftButton") end }
        end
        if W.Dropped(win, "winaction") and win.id == 1 then
            items[#items + 1] = { text = "New window", tip = "Opens another meter window next to this one (five at most).",
                func = function() if W.Add then W.Add(win) end end }
        end
    end
    items[#items + 1] = "---"
    local mode = d.headerMode or "bar"
    local header = {}
    for _, m in ipairs({ { "bar", "Header bar", "A bar on top with the mode, the fight clock and the icons." },
        { "hover", "Hover toolbar", "No bar: the icons float above the window while the mouse is on it (the old look)." },
        { "none", "Nothing", "No bar and no icons; right-click the window for the menus." } }) do
        header[#header + 1] = { text = m[2], tip = m[3], active = mode == m[1],
            func = function()
                d.headerMode = m[1]
                if Meter.RestyleAll then Meter.RestyleAll() end
                if ns.SettingsChanged then ns.SettingsChanged("meter.menu") end
            end }
    end
    items[#items + 1] = { text = "Header", tip = "Every meter window's header.", children = header }
    if win.id ~= 1 and not win.preview then
        items[#items + 1] = { text = "Close this window", tip = "Window 1 keeps the + to open it again.",
            disabled = s.locked and true or false,
            func = function() if win.Close then win:Close() end end }
    end
    -- the reset (its icon left the header bar in the 2026-11-07 polish)
    items[#items + 1] = { text = "Reset data...", tip = "Wipes every fight and the overall (asks first when Ask before reset is on).",
        func = function() if Meter.Win and Meter.Win.Reset then Meter.Win.Reset() end end }
    items[#items + 1] = { text = "Meter settings...", tip = "Every option, with a live preview.",
        func = function() if ns.OpenConfig then ns.OpenConfig("meter") end end }
    return items
end

function Menu.Settings(win, anchor)
    return Menu.Show(anchor or win.frame, Menu.SettingsItems(win))
end

-- ============================================================
-- THE MODE TILES (match pass, 2026-11-07). Zac: make the meter's mode
-- picker look and work like the reference meter's. A click on the
-- header's mode icon or on the title swaps the window's rows for a grid
-- of tiles, two to a row: each mode with its icon, its name and a ">",
-- the one on show marked by an accent bar down its left edge. A click on
-- a tile switches to it and brings the rows back; right-click, Escape on
-- the menu key, or the mode icon again goes back without a change.
--   * the QUICK tiles first: the modes used most, look.quickModes (a list
--     of display keys; nil = QUICK_DEFAULT). Middle-click a quick tile to
--     take it off the list.
--   * "More modes": every mode, by group (Damage / Healing / Actions /
--     Threat). A click there picks it; middle-click pins it to the quick
--     tiles. "Back" returns to the quick tiles.
--   * "+ NEW WINDOW" across the foot: another meter window next to this one
--     (Win.Add), dimmed when five are open.
-- The sizes, gaps, colours and alphas are the reference's numbers
-- (zui_tests/MATCH_SPEC_1107.md, with their source lines); the code, the
-- words and the icons (Zacui/Media/Icons, drawn by zui_tests/icons/
-- make_icons.py) are ZacUI's own. Nothing here runs unless the tiles are
-- open; nothing is saved but the quick list.
-- ============================================================
local Tiles = {}
Meter.Tiles = Tiles

local TILE_H, TILE_GAP, COL_GAP, PAD_X, PAD_TOP = 26, 4, 4, 8, 6
local TILE_BG = { 0.12, 0.12, 0.12, 0.8 }
local TILE_HOVER_LIFT, TILE_HOVER_A = 0.06, 0.18     -- colour +0.06, alpha +0.18
local FOOT_BG_A, FOOT_HOVER_LIFT, FOOT_HOVER_A = 0.5, 0.04, 0.7   -- x the tile alpha
local PAGE_BG = { 0.03, 0.03, 0.03, 0.95 }
local BAR_W = 2                    -- the accent bar, in screen pixels
local ICON_INSET, ICON_GAP_R = 6, 5
-- the icon's box is the reference's (the tile less 2); ZacUI's glyphs fill
-- more of their square than the reference art does, so they are drawn at
-- 18 centred in it: the same size on screen
local ICON_BOX, ICON_SZ = TILE_H - 2, 18
local MORE_ICON = 11               -- More's glyph: the size of the foot row's "+"
local LABEL_R = 30                 -- the label stops this far from the right edge
local CHEV, CHEV_R, CHEV_A = 18, 4, 0.35
-- (x FONT_FIT: the reference's sizes are for a wider face; ZacUI's HD font
-- is stepped up so its lines are as wide, the same factor as the look
-- popup's, MATCH_SPEC_1107.md)
local FONT_FIT = 1.15
local LABEL_PT, PLUS_PT, HINT_PT, HEAD_PT = 11 * FONT_FIT, 13 * FONT_FIT, 9 * FONT_FIT, 9 * FONT_FIT
local ICON_ON_A, ICON_OFF_A, LABEL_OFF_A = 1, 0.6, 0.8
local FOOT_TEXT_A, FOOT_TEXT_HOVER_A = 0.3, 0.5
local HEAD_H = 16                  -- a group's heading on the More page
local WHEEL = 30
-- (2026-11-08, Zac's Era screenshot: the labels read "." and the foot rows'
-- words ran off the window) the tiles go one to a row when two would cut
-- a mode's name; More and New window share a row when both fit half of it;
-- the hints that ran off ("(every mode, by group)", "(middle click a tile
-- to remove it)") live in the tooltips now; every label is held inside its
-- tile and ends in "..." rather than running past it
local FOOT_PAD = 6                 -- a foot label's room from the tile's edges

Tiles.QUICK_DEFAULT = { "damage_done", "heal_done", "interrupts", "deaths" }

-- one glyph per mode (ZacUI's own icons)
Tiles.GLYPH = {
    damage_done = "sword", dps = "sword", damage_taken = "shield", friendly_fire = "target",
    enemy_taken = "target", heal_done = "heart", hps = "heart", overheal = "drop", absorbs = "shield",
    heal_taken = "cross", deaths = "skull", interrupts = "fist", dispels = "star", cc_breaks = "chain",
    ress = "ankh", threat = "eye",
}
local function IconPath(name) return (Meter.ICONS or "Interface\\AddOns\\ZacUI\\Media\\Icons\\") .. name end
function Tiles.Glyph(key) return IconPath(Tiles.GLYPH[key] or "mode") end

local function Label(key)
    if key == "threat" then return "Threat" end
    local d = Meter.DISPLAYS[key]
    return d and d.label or key
end
local function Offered(key) return key == "threat" and Meter.Threat ~= nil or Meter.DISPLAYS[key] ~= nil end

-- the quick list: the saved one (keys this client draws), else the default
function Tiles.Quick()
    local d = Meter.Look()
    local list = type(d.quickModes) == "table" and d.quickModes or Tiles.QUICK_DEFAULT
    local out = {}
    for _, k in ipairs(list) do if Offered(k) then out[#out + 1] = k end end
    return out
end

local function SaveQuick(list)
    local d = Meter.Look()
    d.quickModes = list
    if ns.SettingsChanged then ns.SettingsChanged("meter.tiles") end
end

-- middle-click on a quick tile: off the list (nil becomes the default
-- without it)
function Tiles.Unpin(key)
    local src = type(Meter.Look().quickModes) == "table" and Meter.Look().quickModes or Tiles.QUICK_DEFAULT
    local list = {}
    for _, k in ipairs(src) do if k ~= key then list[#list + 1] = k end end
    SaveQuick(list)
end

-- middle-click on a More tile: onto the end of the list
function Tiles.Pin(key)
    local src = type(Meter.Look().quickModes) == "table" and Meter.Look().quickModes or Tiles.QUICK_DEFAULT
    local list = {}
    for _, k in ipairs(src) do
        if k == key then return end
        list[#list + 1] = k
    end
    list[#list + 1] = key
    SaveQuick(list)
end

local function Font(fs, size)
    MeterFont(fs, size)
    fs:SetShadowColor(0, 0, 0, 1)
    fs:SetShadowOffset(1, -1)
end

local function Accent() return ns.GetColor("ui", "accent") end

-- a tile: the plate, the accent bar, the icon, the name, the chevron
local function NewTile(page)
    local t = CreateFrame("Button", nil, page.content)
    t:SetHeight(TILE_H)
    t:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
    t.bg = t:CreateTexture(nil, "BACKGROUND")
    t.bg:SetAllPoints()
    t.bar = t:CreateTexture(nil, "ARTWORK")
    t.bar:SetPoint("TOPLEFT", t, "TOPLEFT", 0, 0)
    t.bar:SetPoint("BOTTOMLEFT", t, "BOTTOMLEFT", 0, 0)
    if ns.Pixel and ns.Pixel.Edge then ns.Pixel.Edge(t.bar, "LEFT", t, BAR_W) else t.bar:SetWidth(BAR_W) end
    t.bar:Hide()
    t.icon = t:CreateTexture(nil, "OVERLAY")
    t.icon:SetSize(ICON_SZ, ICON_SZ)
    t.icon:SetPoint("CENTER", t, "LEFT", ICON_INSET + ICON_BOX / 2, 0)
    t.text = t:CreateFontString(nil, "OVERLAY")
    Font(t.text, LABEL_PT)
    t.text:SetPoint("LEFT", t, "LEFT", ICON_INSET + ICON_BOX + ICON_GAP_R, 0)
    t.text:SetPoint("RIGHT", t, "RIGHT", -LABEL_R, 0)
    t.text:SetJustifyH("LEFT")
    t.text:SetWordWrap(false)
    t.chev = t:CreateTexture(nil, "ARTWORK")
    t.chev:SetTexture(IconPath("chevron"))
    t.chev:SetSize(CHEV, CHEV)
    t.chev:SetPoint("RIGHT", t, "RIGHT", -CHEV_R, 0)
    t.chev:SetVertexColor(1, 1, 1, CHEV_A)
    -- the foot tile's words: "+", the label, the hint, centred as a group
    t.plus = t:CreateFontString(nil, "OVERLAY")
    Font(t.plus, PLUS_PT)
    t.hint = t:CreateFontString(nil, "OVERLAY")
    Font(t.hint, HINT_PT)
    t.plus:SetPoint("RIGHT", t.text, "LEFT", -4, 0)
    t.hint:SetPoint("LEFT", t.text, "RIGHT", 6, 0)
    t:SetScript("OnEnter", function(self) self.hover = true Tiles.PaintTile(self) Tiles.Tip(self) end)
    t:SetScript("OnLeave", function(self) self.hover = nil Tiles.PaintTile(self) GameTooltip:Hide() end)
    t:SetScript("OnClick", function(self, button) Tiles.Click(page.win, self, button) end)
    t:EnableMouseWheel(true)
    t:SetScript("OnMouseWheel", function(_, delta) Tiles.Wheel(page.win, delta) end)
    return t
end

function Tiles.Tip(t)
    if not t.tip then return end
    GameTooltip:SetOwner(t, "ANCHOR_RIGHT")
    local tc, bc = ns.GetColor("tooltip", "title"), ns.GetColor("tooltip", "body")
    GameTooltip:AddLine(t.tip[1], tc.r, tc.g, tc.b)
    if t.tip[2] then GameTooltip:AddLine(t.tip[2], bc.r, bc.g, bc.b, true) end
    -- the how-to line, dimmer (what the old in-row hints said)
    if t.tip[3] then
        local g = ns.GetColor("text", "gray")
        GameTooltip:AddLine(t.tip[3], g.r, g.g, g.b, true)
    end
    GameTooltip:Show()
end

-- the plate and words in their state: selected, hovered, a foot tile, off
function Tiles.PaintTile(t)
    local a = Accent()
    local foot, hov, on = t.dim, t.hover and not t.off, t.selected
    local r, g, b, al = TILE_BG[1], TILE_BG[2], TILE_BG[3], TILE_BG[4]
    if foot then
        if hov then r, g, b, al = r + FOOT_HOVER_LIFT, g + FOOT_HOVER_LIFT, b + FOOT_HOVER_LIFT, al * FOOT_HOVER_A
        else al = al * FOOT_BG_A end
        local ta = hov and FOOT_TEXT_HOVER_A or FOOT_TEXT_A
        if t.off then ta = FOOT_TEXT_A * 0.6 end
        t.text:SetTextColor(1, 1, 1, ta)
        t.plus:SetTextColor(1, 1, 1, ta)
        t.hint:SetTextColor(1, 1, 1, FOOT_TEXT_A)
        t.icon:SetVertexColor(1, 1, 1, ta)
    else
        if hov then r, g, b, al = r + TILE_HOVER_LIFT, g + TILE_HOVER_LIFT, b + TILE_HOVER_LIFT, al + TILE_HOVER_A end
        t.text:SetTextColor(1, 1, 1, (on or hov) and 1 or LABEL_OFF_A)
        t.icon:SetVertexColor(a.r, a.g, a.b, on and ICON_ON_A or ICON_OFF_A)
    end
    t.bg:SetColorTexture(r, g, b, al)
    t.bar:SetColorTexture(a.r, a.g, a.b, 1)
    t.bar:SetShown(on and not foot and true or false)
end

-- the page over the window's body: built once per window
local function EnsurePage(win)
    if win.tilePage then return win.tilePage end
    local f = win.frame
    local page = CreateFrame("Frame", nil, f)
    page.win = win
    page:SetFrameLevel((f:GetFrameLevel() or 1) + 25)
    page:EnableMouse(true)
    page.bg = page:CreateTexture(nil, "BACKGROUND")
    page.bg:SetAllPoints()
    page.bg:SetColorTexture(PAGE_BG[1], PAGE_BG[2], PAGE_BG[3], PAGE_BG[4])
    -- measures labels for the column choice (never shown)
    page.measure = page:CreateFontString(nil, "OVERLAY")
    Font(page.measure, LABEL_PT)
    page.measure:Hide()
    if page.SetClipsChildren then pcall(page.SetClipsChildren, page, true) end
    page.content = CreateFrame("Frame", nil, page)
    page.content:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
    page.content:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, 0)
    page.content:SetHeight(1)
    page.tiles, page.heads = {}, {}
    page:SetScript("OnMouseUp", function(_, button) if button == "RightButton" then Tiles.Hide(win) end end)
    page:EnableMouseWheel(true)
    page:SetScript("OnMouseWheel", function(_, delta) Tiles.Wheel(win, delta) end)
    page:SetScript("OnSizeChanged", function() if page:IsShown() then Tiles.Layout(win) end end)
    page:Hide()
    win.tilePage = page
    return page
end

local function Head(page, i)
    local h = page.heads[i]
    if h then return h end
    h = page.content:CreateFontString(nil, "OVERLAY")
    Font(h, HEAD_PT)
    h:SetJustifyH("LEFT")
    page.heads[i] = h
    return h
end

-- what the page lists now: { kind = "mode"|"more"|"back"|"foot"|"head", key, full }
local function Entries(win)
    local out = {}
    local page = win.tilePage
    if page.view == "more" then
        out[#out + 1] = { kind = "back", full = true }
        for _, g in ipairs(Meter.GROUPS or {}) do
            out[#out + 1] = { kind = "head", text = g.label }
            for _, k in ipairs(g.keys) do if Offered(k) then out[#out + 1] = { kind = "mode", key = k } end end
        end
        if Meter.Threat then
            out[#out + 1] = { kind = "head", text = "Threat" }
            out[#out + 1] = { kind = "mode", key = "threat" }
        end
    else
        for _, k in ipairs(Tiles.Quick()) do out[#out + 1] = { kind = "mode", key = k } end
        out[#out + 1] = { kind = "more", full = true, pair = true }
        out[#out + 1] = { kind = "foot", full = true, pair = true }
    end
    return out
end

local function TextW(page, text, size)
    local m = page.measure
    if size then Font(m, size) end
    m:SetText(text or "")
    local ok, w = pcall(m.GetStringWidth, m)
    if size then Font(m, LABEL_PT) end
    return (ok and type(w) == "number") and w or 0
end
-- a foot label's lead: the "+" or More's small icon, and its gap
local function FootLead(page, kind)
    if kind == "foot" then return TextW(page, "+", PLUS_PT) + 4 end
    if kind == "more" then return MORE_ICON + 4 end
    return 0
end
local FOOT_TEXT = { more = "MORE MODES", foot = "NEW WINDOW", back = "BACK" }

-- how many tiles to a row: two when every mode's name fits half the
-- width, else one (Zac's Era windows are 160-225 wide: one)
function Tiles.Columns(win, entries)
    local page = win.tilePage
    local w = page:GetWidth() or 0
    local colW = (w - PAD_X * 2 - COL_GAP) / 2
    local most = 0
    for _, e in ipairs(entries) do
        if e.kind == "mode" then
            local lw = TextW(page, Label(e.key))
            if lw > most then most = lw end
        end
    end
    if ICON_INSET + ICON_BOX + ICON_GAP_R + most + LABEL_R <= colW then return 2, colW end
    return 1, w - PAD_X * 2
end

-- More and New window side by side when both labels fit half the row
local function PairFits(page, w)
    local half = (w - PAD_X * 2 - COL_GAP) / 2
    for _, kind in ipairs({ "more", "foot" }) do
        if TextW(page, FOOT_TEXT[kind]) + FootLead(page, kind) + FOOT_PAD * 2 > half then return false end
    end
    return true
end

-- lay the tiles out from the page's width: two columns, the full-width
-- rows (More, Back, the foot) on lines of their own
function Tiles.Layout(win)
    local page = win.tilePage
    if not (page and page:IsShown()) then return end
    local w = page:GetWidth() or 0
    if w < 1 then return end
    local entries = Entries(win)
    local cols, colW = Tiles.Columns(win, entries)
    page.cols = cols
    local pair = PairFits(page, w)
    local halfW = (w - PAD_X * 2 - COL_GAP) / 2
    local cur = win.settings.display
    local y, col = -PAD_TOP, 0
    local nt, nh = 0, 0
    local function NewLine()
        if col > 0 then y = y - TILE_H - TILE_GAP col = 0 end
    end
    local pairCol = 0
    for _, e in ipairs(entries) do
        if e.kind == "head" then
            NewLine()
            nh = nh + 1
            local h = Head(page, nh)
            local a = Accent()
            h:SetTextColor(a.r, a.g, a.b, 0.9)
            h:SetText(e.text:upper())
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", page.content, "TOPLEFT", PAD_X + 2, y - 3)
            h:Show()
            y = y - HEAD_H
        else
            nt = nt + 1
            local t = page.tiles[nt] or NewTile(page)
            page.tiles[nt] = t
            t.kind, t.key, t.off, t.tip, t.dim = e.kind, e.key, nil, nil, nil
            t:ClearAllPoints()
            local tileW
            if e.full and e.pair and pair then
                -- More and New window share the row, half each
                if pairCol == 0 then NewLine() end
                t:SetPoint("TOPLEFT", page.content, "TOPLEFT", PAD_X + pairCol * (halfW + COL_GAP), y)
                t:SetWidth(halfW)
                tileW = halfW
                pairCol = pairCol + 1
                if pairCol >= 2 then pairCol = 0 y = y - TILE_H - TILE_GAP end
            elseif e.full then
                NewLine()
                t:SetPoint("TOPLEFT", page.content, "TOPLEFT", PAD_X, y)
                t:SetPoint("TOPRIGHT", page.content, "TOPRIGHT", -PAD_X, y)
                tileW = w - PAD_X * 2
                y = y - TILE_H - TILE_GAP
            else
                t:SetPoint("TOPLEFT", page.content, "TOPLEFT", PAD_X + col * (colW + COL_GAP), y)
                t:SetWidth(colW)
                tileW = colW
                col = col + 1
                if col >= cols then col = 0 y = y - TILE_H - TILE_GAP end
            end
            -- the full-width rows (More, Back, New window) are dim and
            -- centred, the weight of the reference's foot row, so the
            -- grid of modes stays what the eye goes to
            local foot = e.kind == "foot" or e.kind == "back" or e.kind == "more"
            t.dim = foot or nil
            t.plus:SetShown(e.kind == "foot")
            t.hint:SetShown(false)
            t.icon:SetShown(e.kind == "mode" or e.kind == "more")
            t.chev:SetShown(not foot)
            t.text:ClearAllPoints()
            t.icon:ClearAllPoints()
            t.selected = (e.kind == "mode" and e.key == cur) or nil
            if foot then
                t.hint:SetText("")
                t.text:SetText(FOOT_TEXT[e.kind])
                if e.kind == "more" then
                    t.plus:SetText("")
                    t.icon:SetTexture(IconPath("more"))
                    t.icon:SetSize(MORE_ICON, MORE_ICON)
                    t.action = "more"
                    t.tip = { "More modes", "Every mode the meter has, by group.",
                        "Middle-click a mode there to pin it to this page." }
                elseif e.kind == "foot" then
                    t.plus:SetText("+")
                    local full = #(Meter.windowFrames or {}) >= (Meter.MAX_WINDOWS or 5)
                    t.off = full or win.preview or nil
                    t.action = "add"
                    t.tip = full and { "New window", "Five meter windows are open: the most there can be." }
                        or { "New window", "Opens another meter window next to this one, showing this mode.",
                            "Middle-click a mode tile to take it off this page." }
                else
                    t.plus:SetText("")
                    t.action = "back"
                    t.tip = { "Back", "The quick tiles again.", "Middle-click a mode to pin it to the quick tiles." }
                end
                -- the label centred with its lead ("+" or More's small
                -- icon) and held inside the tile: cut with "..." when the
                -- window is too narrow for it
                local pw = FootLead(page, e.kind)
                local lw = TextW(page, t.text:GetText())
                local most = math.max(10, tileW - FOOT_PAD * 2 - pw)
                if lw > most then lw = most end
                t.text:SetWidth(lw + 1)
                t.text:SetPoint("CENTER", t, "CENTER", pw / 2, 0)
                if e.kind == "more" then t.icon:SetPoint("RIGHT", t.text, "LEFT", -4, 0) end
            else
                t.action = nil
                t.text:SetWidth(0)
                t.icon:SetSize(ICON_SZ, ICON_SZ)
                t.icon:SetPoint("CENTER", t, "LEFT", ICON_INSET + ICON_BOX / 2, 0)
                t.text:SetPoint("LEFT", t, "LEFT", ICON_INSET + ICON_BOX + ICON_GAP_R, 0)
                t.text:SetPoint("RIGHT", t, "RIGHT", -LABEL_R, 0)
                t.icon:SetTexture(Tiles.Glyph(e.key))
                t.text:SetText(Label(e.key))
                local disp = Meter.DISPLAYS[e.key]
                t.tip = { Label(e.key), e.key == "threat" and Meter.THREAT_DESC or (disp and disp.desc),
                    page.view == "more" and "Middle-click to pin it to the quick tiles."
                        or "Middle-click to take it off this page." }
            end
            Tiles.PaintTile(t)
            t:Show()
        end
    end
    NewLine()
    if pairCol > 0 then y = y - TILE_H - TILE_GAP end
    for i = nt + 1, #page.tiles do page.tiles[i]:Hide() end
    for i = nh + 1, #page.heads do page.heads[i]:Hide() end
    local contentH = -y + 5
    page.content:SetHeight(math.max(10, contentH))
    page.scrollMax = math.max(0, contentH - (page:GetHeight() or 0))
    page.scroll = math.min(page.scroll or 0, page.scrollMax)
    page.content:ClearAllPoints()
    page.content:SetPoint("TOPLEFT", page, "TOPLEFT", 0, page.scroll)
    page.content:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, page.scroll)
end

function Tiles.Wheel(win, delta)
    local page = win.tilePage
    if not page then return end
    local s = math.max(0, math.min(page.scrollMax or 0, (page.scroll or 0) - delta * WHEEL))
    if s == page.scroll then return end
    page.scroll = s
    Tiles.Layout(win)
end

function Tiles.Click(win, t, button)
    if win.preview then return end
    if button == "RightButton" then Tiles.Hide(win) return end
    local page = win.tilePage
    if t.action == "add" then
        if t.off or button ~= "LeftButton" then return end
        Tiles.Hide(win)
        if Meter.Win and Meter.Win.Add then Meter.Win.Add(win) end
    elseif t.action == "back" then
        page.view, page.scroll = nil, 0
        Tiles.Layout(win)
    elseif t.action == "more" then
        if button ~= "LeftButton" then return end
        page.view, page.scroll = "more", 0
        Tiles.Layout(win)
    elseif t.key then
        if button == "MiddleButton" then
            if page.view == "more" then Tiles.Pin(t.key) else Tiles.Unpin(t.key) end
            GameTooltip:Hide()
            Tiles.Layout(win)
            return
        end
        Tiles.Hide(win)
        win:SetDisplay(t.key)
    end
end

function Tiles.IsShown(win) return win.tilePage ~= nil and win.tilePage:IsShown() end

-- the rows out, the tiles in (the quick page; the breakdown closes first)
function Tiles.Show(win)
    if win.preview then return end
    Menu.Hide()
    local BD = Meter.Breakdown
    if BD and BD.IsOpen and BD.IsOpen(win) and BD.Close then BD.Close(win) end
    local page = EnsurePage(win)
    page:ClearAllPoints()
    page:SetPoint("TOPLEFT", win.rowframe, "TOPLEFT", 0, 0)
    page:SetPoint("BOTTOMRIGHT", win.rowframe, "BOTTOMRIGHT", 0, 0)
    page.view, page.scroll = nil, 0
    -- (Classic look) the window's own tile shows through; ZacUI's look: the
    -- reference's near-black page
    if Meter.IsClassicLook and Meter.IsClassicLook() then page.bg:SetColorTexture(0, 0, 0, 0)
    else page.bg:SetColorTexture(PAGE_BG[1], PAGE_BG[2], PAGE_BG[3], PAGE_BG[4]) end
    win.rowframe:Hide()
    page:Show()
    Tiles.Layout(win)
end

function Tiles.Hide(win)
    local page = win.tilePage
    if not (page and page:IsShown()) then return end
    page:Hide()
    GameTooltip:Hide()
    if not (Meter.Breakdown and Meter.Breakdown.IsOpen and Meter.Breakdown.IsOpen(win)) then
        win.rowframe:Show()
        Meter.RefreshWindow(win, true)
    end
end

function Tiles.Toggle(win)
    if Tiles.IsShown(win) then Tiles.Hide(win) else Tiles.Show(win) end
end
