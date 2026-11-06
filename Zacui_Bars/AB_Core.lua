-- AB_Core - ZacUI's own action bars: settings, profiles, geometry and the
-- secure plumbing every bar shares. Replaces Bartender4.
-- Part of ZacUI; load order is set by the TOC.
--
-- WHAT THIS IS. Ten action bars, a pet bar, a stance bar, the bag strip,
-- the micro menu and the XP/rep strip, each on its own secure header,
-- placed, scaled, paged and faded from ZacUI's settings. The buttons are
-- Blizzard's own templates (ActionBarButtonTemplate and friends), so
-- cooldowns, counts, range, usability, drag and drop, tooltips and the
-- secure click all stay the client's - this file only owns WHERE the
-- buttons are and WHICH slot each one shows.
--
-- GEOMETRY IS BARTENDER'S, on purpose. A bar's position is stored as the
-- anchor corner of a 1x1 header (point / x / y in UIParent units, scale
-- separate), button 1 sits (+5,-3) inside that corner and the rest flow
-- from it - the same numbers Bartender4 uses, so an imported profile puts
-- every button on exactly the pixel it was on. AB_Import does that
-- translation once; nothing here reads Bartender4's tables.
--
-- SECURITY. Everything that moves, shows or re-pages a bar is a protected
-- write and runs only out of combat: ApplyAll queues itself for
-- PLAYER_REGEN_ENABLED when a fight is on. Alpha (fading) is not
-- protected and runs any time. Paging is a secure state driver on each
-- header that rewrites the children's "action" attribute, so stance
-- changes in combat are handled by the client, not by us.

local ADDON_NAME = ...
-- Zacui_Bars is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

-- shared state from earlier ZacUI files
local Print = ns.Print
local ZUI = ns.ZUI

local AB = ns.Bars or {}
ns.Bars = AB

AB.NUM_BARS    = 10
AB.PER_BAR     = 12
AB.BUTTON      = 36          -- action button edge, Bartender's stock size
AB.PET_BUTTON  = 30
AB.PLAYER_CLASS = select(2, UnitClass("player"))

-- ============================================================
-- DEFAULTS
-- ============================================================
local function DeepCopy(v, depth)
    if type(v) ~= "table" then return v end
    if (depth or 0) > 12 then return nil end
    local out = {}
    for k, x in pairs(v) do out[k] = DeepCopy(x, (depth or 0) + 1) end
    return out
end
AB.DeepCopy = DeepCopy

-- Fill every key the stored table lacks from the defaults, recursively,
-- without touching anything the player (or an import) already set.
local function Fill(dst, src)
    for k, v in pairs(src) do
        if dst[k] == nil then
            dst[k] = DeepCopy(v)
        elseif type(v) == "table" and type(dst[k]) == "table" then
            Fill(dst[k], v)
        end
    end
    return dst
end
AB.Fill = Fill

-- The three text elements on a button. font nil = the ZacUI font.
local function DefaultFonts()
    return {
        hotkey = { font = nil, size = 13, flags = "OUTLINE", color = { 0.9, 0.9, 0.9 },
                   anchor = "TOPRIGHT", x = -2, y = -4, justify = "RIGHT" },
        count  = { font = nil, size = 16, flags = "OUTLINE", color = { 1, 1, 1 },
                   anchor = "BOTTOMRIGHT", x = -2, y = 4, justify = "RIGHT" },
        macro  = { font = nil, size = 10, flags = "OUTLINE", color = { 1, 1, 1 },
                   anchor = "BOTTOM", x = 0, y = 2, justify = "CENTER" },
    }
end

-- Bar 1 pages with the stance the way Blizzard's main bar does; the
-- class table lists bonusbar index -> page (prowl is a virtual stance).
local DEFAULT_STANCES = {
    WARRIOR = { [1] = 7, [2] = 8, [3] = 9 },
    DRUID   = { [3] = 9, [1] = 7, prowl = 8 },
    ROGUE   = { [1] = 7 },
}

-- THE FADE ANIMATIONS. "none" is the instant snap every bar has always
-- had, so nothing moves for anyone until they pick "Fade". The fade-out
-- waits the bar's fadeDelay first (a key Bartender imports carried long
-- before anything here honoured it) - but only when it is a real fade.
AB.FADE_IN  = { style = "none", duration = 0.2, delay = 0, easing = "easeOutQuad" }
AB.FADE_OUT = { style = "none", duration = 0.4, easing = "easeOutQuad" }

-- THE BUTTON LOOK. Every default is what the buttons drew before these
-- settings existed: a cropped icon, ZacUI's 1px border in the theme's
-- border colour, no backing, white washes for hover and press, the
-- accent for the active state, the client's cooldown sweep and numbers.
-- A nil colour means "the theme's" (border, accent) or "the game's"
-- (cooldown numbers); a nil fonts.cooldown means the game's font.
local function AddLook(t, size, equipped)
    t.buttonSize = size
    t.iconZoom = 8                 -- % cropped off each edge of the icon
    t.borderSize = 1               -- px; 0 = no border
    t.borderColor = nil
    t.backdrop = false
    t.backdropColor = { r = 0, g = 0, b = 0, a = 0.6 }
    t.hoverColor = { r = 1, g = 1, b = 1, a = 0.12 }
    t.pushedColor = { r = 1, g = 1, b = 1, a = 0.18 }
    t.checkedColor = nil
    t.cdSwipe = true
    t.cdText = "game"              -- "game" | "show" | "hide"
    t.cdColor = nil
    if equipped then t.equippedColor = { r = 0.35, g = 0.65, b = 1.0, a = 1 } end
    return t
end
AB.AddLook = AddLook

local function DefaultBar(n)
    return AddLook({
        enabled = n <= 6,
        buttons = 12, rows = 1, padding = 2, offset = 0,
        scale = 1, alpha = 1,
        growH = "RIGHT", growV = "DOWN",
        point = nil, x = nil, y = nil,
        fade = false, fadeAlpha = 0.1, fadeDelay = 0.2,
        fadeIn = DeepCopy(AB.FADE_IN), fadeOut = DeepCopy(AB.FADE_OUT),
        clickthrough = false, showgrid = false,
        hideHotkey = false, hideMacro = false, hideCount = false,
        visibility = { combat = false, nocombat = false, pet = false, nopet = false,
                       mounted = false, always = false, stance = {}, custom = false,
                       customdata = "" },
        paging = {
            enabled = (n == 1), actionbar = false,
            ctrl = 0, alt = 0, shift = 0, default = 0,
            stance = (n == 1) and DeepCopy(DEFAULT_STANCES) or {},
            customEnabled = false, custom = "",
        },
        fonts = DefaultFonts(),
    }, AB.BUTTON, true)
end
AB.DefaultBar = DefaultBar

local function DefaultSmallBar(extra)
    local t = {
        enabled = true, rows = 1, padding = 2, scale = 1, alpha = 1,
        growH = "RIGHT", growV = "DOWN", point = nil, x = nil, y = nil,
        fade = false, fadeAlpha = 0.1, fadeDelay = 0.2,
        fadeIn = DeepCopy(AB.FADE_IN), fadeOut = DeepCopy(AB.FADE_OUT),
        clickthrough = false, hideHotkey = true, showgrid = false,
        visibility = { combat = false, nocombat = false, pet = false, nopet = false,
                       mounted = false, always = false, stance = {} },
    }
    for k, v in pairs(extra or {}) do t[k] = v end
    return t
end

function AB.DefaultProfile()
    local p = { bars = {} }
    for n = 1, AB.NUM_BARS do p.bars[n] = DefaultBar(n) end
    p.pet    = AddLook(DefaultSmallBar({ initial = { "CENTER", 0, 70 },
                                 visibility = { nopet = true } }), AB.PET_BUTTON)
    p.stance = AddLook(DefaultSmallBar({ scale = 1.5, initial = { "CENTER", -55, -10 } }), AB.PET_BUTTON)
    p.bagbar = DefaultSmallBar({ keyring = true, onebag = false, valign = "BOTTOM",
                                 initial = { "CENTER", 142, -18 } })
    p.micro  = DefaultSmallBar({ padding = -3, scale = 0.8, vertical = false,
                                 initial = { "CENTER", -105, 30 } })
    p.status = DefaultSmallBar({ enabled = false, width = 1024,
                                 initial = { "BOTTOM", 0, 0 } })
    p.core = {
        outofrange = "button",      -- "button" | "hotkey" | "none"
        buttonlock = true,          -- drag off a bar needs the pickup modifier
        tooltip = "enabled",        -- "enabled" | "nocombat" | "disabled"
        selfcast = true, focuscast = true, rightclickself = false,
        rangeColor = { 0.8, 0.1, 0.1 }, manaColor = { 0.5, 0.5, 1.0 },
        -- off = the game colours the buttons (as it always has); on =
        -- outofrange and the three colours here decide
        colorButtons = false,
        unusableColor = { r = 0.4, g = 0.4, b = 0.4, a = 1 },
        -- spell alerts on a button: the game's own, ZacUI's glow, or none
        glow = "game",
        glowColor = { r = 1, g = 0.82, b = 0, a = 1 },
        glowSize = 2,
        glowAnim = { style = "pulse", duration = 0.8, delay = 0, easing = "easeOutQuad", loop = true },
    }
    return p
end

-- ============================================================
-- STORE
-- ============================================================
-- Account-wide, like the rest of ZacUIDB: a set of named profiles and a
-- map of which character wears which. The per-character choice is also
-- mirrored in ZacUICharDB so it travels with a profile string.
function AB.DB()
    ZacUIDB.bars = ZacUIDB.bars or {}
    local d = ZacUIDB.bars
    d.profiles = d.profiles or {}
    d.charProfile = d.charProfile or {}
    d.defaultProfile = d.defaultProfile or "Default"
    return d
end

function AB.CharKey()
    local name, realm = UnitName("player"), GetRealmName()
    return (name or "?") .. " - " .. (realm or "?")
end

function AB.ProfileName()
    local d = AB.DB()
    local key = AB.CharKey()
    local name = (ZacUICharDB and ZacUICharDB.barsProfile) or d.charProfile[key]
    if not name or not d.profiles[name] then
        -- A character with no profile of its own wears the one chosen for
        -- new characters (see the Action bars page), else "Default".
        name = d.defaultProfile
        if not d.profiles[name] then name = "Default" end
    end
    return name
end

function AB.Profile()
    local d = AB.DB()
    local name = AB.ProfileName()
    if not d.profiles[name] then d.profiles[name] = AB.DefaultProfile() end
    local p = d.profiles[name]
    Fill(p, AB.DefaultProfile())
    for n = 1, AB.NUM_BARS do
        p.bars[n] = p.bars[n] or DefaultBar(n)
        Fill(p.bars[n], DefaultBar(n))
    end
    d.charProfile[AB.CharKey()] = name
    if ZacUICharDB then ZacUICharDB.barsProfile = name end
    return p, name
end

function AB.ListProfiles()
    local names = {}
    for name in pairs(AB.DB().profiles) do names[#names + 1] = name end
    table.sort(names)
    return names
end

function AB.UseProfile(name)
    local d = AB.DB()
    if not d.profiles[name] then return false, "no profile called '" .. tostring(name) .. "'" end
    d.charProfile[AB.CharKey()] = name
    if ZacUICharDB then ZacUICharDB.barsProfile = name end
    AB._core = nil
    AB.ApplyAll()
    return true
end

function AB.CopyProfile(from, to)
    local d = AB.DB()
    if not d.profiles[from] then return false, "no such profile" end
    if not to or to == "" then return false, "give the profile a name" end
    d.profiles[to] = DeepCopy(d.profiles[from])
    return true
end

function AB.NewProfile(name)
    local d = AB.DB()
    if not name or name == "" then return false, "give the profile a name" end
    if d.profiles[name] then return false, "'" .. name .. "' already exists" end
    d.profiles[name] = AB.DefaultProfile()
    return true
end

function AB.DeleteProfile(name)
    local d = AB.DB()
    if not d.profiles[name] then return false, "no such profile" end
    local inUse = {}
    for key, pn in pairs(d.charProfile) do
        if pn == name then inUse[#inUse + 1] = key end
    end
    d.profiles[name] = nil
    for _, key in ipairs(inUse) do d.charProfile[key] = nil end
    if d.defaultProfile == name then d.defaultProfile = "Default" end
    if ZacUICharDB and ZacUICharDB.barsProfile == name then ZacUICharDB.barsProfile = nil end
    return true
end

function AB.RenameProfile(from, to)
    local d = AB.DB()
    if not d.profiles[from] then return false, "no such profile" end
    if not to or to == "" then return false, "give the profile a name" end
    if d.profiles[to] then return false, "'" .. to .. "' already exists" end
    d.profiles[to], d.profiles[from] = d.profiles[from], nil
    for key, pn in pairs(d.charProfile) do
        if pn == from then d.charProfile[key] = to end
    end
    if d.defaultProfile == from then d.defaultProfile = to end
    if ZacUICharDB and ZacUICharDB.barsProfile == from then ZacUICharDB.barsProfile = to end
    return true
end

-- ============================================================
-- GEOMETRY
-- ============================================================
-- The header is 1x1 and the stored point is its anchor corner, decided
-- by the growth direction: buttons grow right and down from a TOPLEFT
-- corner, left and up from a BOTTOMRIGHT one, and so on.
-- The bar's layout on the standard's shape (cfg.layout, Position tab):
-- grow (RIGHT / LEFT) and wrap (DOWN / UP) stand in for growH / growV,
-- perLine for the rows, spacingX / spacingY for the one padding. Nothing
-- saved = the bar's own keys, exactly as before.
local function LayoutSpec(cfg)
    local l = cfg and cfg.layout
    if type(l) == "table" and next(l) ~= nil then return l end
    return nil
end
AB.LayoutSpec = LayoutSpec

function AB.AnchorOf(cfg)
    local l = LayoutSpec(cfg)
    local gv = (l and l.wrap) or cfg.growV
    local gh = (l and l.grow) or cfg.growH
    local v = (gv == "UP") and "BOTTOM" or "TOP"
    local h = (gh == "LEFT") and "RIGHT" or "LEFT"
    return v .. h, v, h
end

-- buttons per row, rows, gap across, gap down for `count` buttons
function AB.LayoutShape(cfg, count)
    count = math.max(count or 1, 1)
    local pad = cfg.padding or 2
    local l = LayoutSpec(cfg)
    local perRow
    local per = l and tonumber(l.perLine)
    if per and per > 0 then
        perRow = math.min(math.floor(per), count)
    else
        local rows = math.max(1, math.min(cfg.rows or 1, count))
        perRow = math.ceil(count / rows)
    end
    local rows = math.ceil(count / perRow)
    local padX, padY = pad, pad
    if l then padX, padY = tonumber(l.spacingX) or pad, tonumber(l.spacingY) or pad end
    return perRow, rows, padX, padY
end

-- what the Position tab's layout picker shows with nothing saved
function AB.LayoutDefaults(cfg, count)
    local perRow = AB.LayoutShape({ rows = cfg.rows, padding = cfg.padding }, count or cfg.buttons or 12)
    local pad = cfg.padding or 2
    return { grow = cfg.growH or "RIGHT", wrap = cfg.growV or "DOWN", perLine = perRow, spacingX = pad, spacingY = pad }
end

-- The bar's layer on the standard's frame shape (cfg.framePos: strata,
-- level - Position tab). The mover keeps the spot; nothing saved = the
-- header's own layer, untouched. Out of combat only, like every caller.
local NO_LAYER = {}
function AB.ApplyLayer(frame, cfg)
    local fp = cfg and cfg.framePos
    if type(fp) ~= "table" or next(fp) == nil then fp = nil end
    if not (fp or frame._abLayer) then return end
    local def = frame._abLayer
    if not def then
        def = { strata = frame:GetFrameStrata(), level = frame:GetFrameLevel() }
        frame._abLayer = def
    end
    if ns.ApplyFramePosition then ns.ApplyFramePosition(frame, fp or NO_LAYER, def) end
end

-- Puts a header where its config says. x/y are UIParent units; the
-- frame is scaled, so SetPoint takes them divided by the scale.
function AB.Place(frame, cfg, initial)
    local s = cfg.scale or 1
    if s <= 0 then s = 1 end
    frame:SetScale(s)
    frame:ClearAllPoints()
    if cfg.x == nil or cfg.y == nil or not cfg.point then
        local init = initial or cfg.initial or { "CENTER", 0, -250 }
        frame:SetPoint(init[1], UIParent, init[1], init[2] / s, init[3] / s)
        AB.SavePosition(frame, cfg)
        AB.ApplyLayer(frame, cfg)
        return
    end
    frame:SetPoint(cfg.point, UIParent, cfg.point, cfg.x / s, cfg.y / s)
    AB.ApplyLayer(frame, cfg)
end

-- Reads a header's screen position back into its config: the nearest
-- screen anchor (by thirds), and the offset of the matching corner of
-- the frame from it, in UIParent units.
function AB.SavePosition(frame, cfg)
    local s = frame:GetScale() or 1
    local l, r = frame:GetLeft(), frame:GetRight()
    local t, b = frame:GetTop(), frame:GetBottom()
    if not (l and r and t and b) then return end
    l, r, t, b = l * s, r * s, t * s, b * s
    local uw, uh = UIParent:GetWidth(), UIParent:GetHeight()
    local cx, cy = (l + r) / 2, (t + b) / 2
    local h = (cx < uw / 3) and "LEFT" or (cx > uw * 2 / 3) and "RIGHT" or ""
    local v = (cy < uh / 3) and "BOTTOM" or (cy > uh * 2 / 3) and "TOP" or ""
    local x = (h == "LEFT") and l or (h == "RIGHT") and (r - uw) or (cx - uw / 2)
    local y = (v == "BOTTOM") and b or (v == "TOP") and (t - uh) or (cy - uh / 2)
    local point = v .. h
    if point == "" then point = "CENTER" end
    cfg.point, cfg.x, cfg.y = point, x, y
end

-- Lays a header's buttons out in rows from its anchor corner, and sizes
-- the overlay (the mouse-over area used for fading and dragging) around
-- them. Pure anchoring: safe out of combat only, like every caller.
function AB.LayoutButtons(header, buttons, cfg, size, count)
    count = math.min(count or #buttons, #buttons)
    local perRow, rows, padX, padY = AB.LayoutShape(cfg, count)
    local anchor, v, h = AB.AnchorOf(cfg)
    local ox = (h == "LEFT") and 5 or -3
    local oy = (v == "TOP") and -3 or 5
    for i, btn in ipairs(buttons) do
        btn:ClearAllPoints()
        if i == 1 then
            btn:SetPoint(anchor, header, anchor, ox, oy)
        elseif (i - 1) % perRow == 0 then
            local above = buttons[i - perRow]
            if v == "TOP" then
                btn:SetPoint("TOP" .. h, above, "BOTTOM" .. h, 0, -padY)
            else
                btn:SetPoint("BOTTOM" .. h, above, "TOP" .. h, 0, padY)
            end
        else
            local prev = buttons[i - 1]
            if h == "LEFT" then
                btn:SetPoint("LEFT", prev, "RIGHT", padX, 0)
            else
                btn:SetPoint("RIGHT", prev, "LEFT", -padX, 0)
            end
        end
        if i <= count then
            btn:SetSize(size, size)
            btn:Show()
        else
            btn:Hide()
        end
    end
    local ov = header.overlay
    if ov then
        ov:ClearAllPoints()
        ov:SetPoint(anchor, header, anchor, (h == "LEFT") and 1 or -1, (v == "TOP") and 1 or -1)
        ov:SetSize(math.max(1, (size + padX) * perRow - padX + 8),
                   math.max(1, (size + padY) * rows - padY + 8))
    end
end

-- ============================================================
-- DRIVERS - the macro-condition strings the client evaluates
-- ============================================================
function AB.VisibilityDriver(cfg)
    local v = cfg.visibility or {}
    if v.custom and v.customdata and v.customdata ~= "" then return v.customdata end
    if v.always then return "hide" end
    local parts = {}
    if v.combat   then parts[#parts + 1] = "[combat]hide" end
    if v.nocombat then parts[#parts + 1] = "[nocombat]hide" end
    if v.pet      then parts[#parts + 1] = "[pet]hide" end
    if v.nopet    then parts[#parts + 1] = "[nopet]hide" end
    if v.mounted  then parts[#parts + 1] = "[mounted]hide" end
    for id, on in pairs(v.stance or {}) do
        if on and tonumber(id) then parts[#parts + 1] = "[stance:" .. tonumber(id) .. "]hide" end
    end
    -- WHEN IT SHOWS, on ZacUI's visibility standard (cfg.showRule: show =
    -- combat / nocombat / group / raid / target / never; its own key, since
    -- cfg.visibility is this bar's own hide flags). The "Hide when" ticks
    -- above still win; the rule decides the rest. Nothing saved = "show".
    local rule = type(cfg.showRule) == "table" and ns.VisibilityMacro and ns.VisibilityMacro(cfg.showRule) or nil
    parts[#parts + 1] = rule or "show"
    return table.concat(parts, ";")
end

-- The page a bar shows, as a state: 0 = its own slots, N = Blizzard page
-- N (slots (N-1)*12+1 ..). Built left to right in priority order.
function AB.PageDriver(cfg)
    local p = cfg.paging or {}
    if not p.enabled then return "0" end
    if p.customEnabled and p.custom and p.custom ~= "" then return p.custom end
    local parts = {}
    if (p.ctrl or 0) > 0  then parts[#parts + 1] = "[mod:ctrl]" .. p.ctrl end
    if (p.alt or 0) > 0   then parts[#parts + 1] = "[mod:alt]" .. p.alt end
    if (p.shift or 0) > 0 then parts[#parts + 1] = "[mod:shift]" .. p.shift end
    if p.actionbar then
        parts[#parts + 1] = "[bar:2]2;[bar:3]3;[bar:4]4;[bar:5]5;[bar:6]6"
    end
    local st = p.stance and p.stance[AB.PLAYER_CLASS]
    if st then
        -- prowl before cat: both are bonusbar 1, stealth tells them apart
        if (st.prowl or 0) > 0 then parts[#parts + 1] = "[bonusbar:1,stealth:1]" .. st.prowl end
        for _, idx in ipairs({ 1, 2, 3, 4 }) do
            local page = st[idx] or st[tostring(idx)]
            if (page or 0) > 0 then parts[#parts + 1] = "[bonusbar:" .. idx .. "]" .. page end
        end
    end
    parts[#parts + 1] = tostring(p.default or 0)
    return table.concat(parts, ";")
end

-- ============================================================
-- COMBAT QUEUE
-- ============================================================
-- One queue for the whole bar system: anything protected that is asked
-- for in combat runs once, after the fight.
local queued, regenWatch = {}, nil
function AB.AfterCombat(key, fn)
    if not (InCombatLockdown and InCombatLockdown()) then fn() return true end
    queued[key] = fn
    if not regenWatch then
        regenWatch = CreateFrame("Frame")
        regenWatch:RegisterEvent("PLAYER_REGEN_ENABLED")
        regenWatch:SetScript("OnEvent", function()
            local run = queued
            queued = {}
            for _, f in pairs(run) do pcall(f) end
        end)
    end
    return false
end

-- ============================================================
-- HIDING BLIZZARD'S BARS
-- ============================================================
-- Reparented to a hidden frame rather than only hidden, so the client's
-- own layout passes cannot bring them back. Buttons are also detached
-- from their events and marked statehidden so paging code leaves them
-- alone. Login-time, out of combat, once.
local hider
function AB.HideBlizzard()
    if AB._blizzHidden then return end
    AB._blizzHidden = true
    hider = hider or CreateFrame("Frame", "ZacUIBarsHider", UIParent)
    hider:Hide()
    local function Frame(f, clearEvents)
        if not f then return end
        if clearEvents and f.UnregisterAllEvents then f:UnregisterAllEvents() end
        if f.HideBase then f:HideBase() elseif f.Hide then f:Hide() end
        if f.SetParent then f:SetParent(hider) end
    end
    local function Button(b)
        if not b then return end
        if b.Hide then b:Hide() end
        if b.UnregisterAllEvents then b:UnregisterAllEvents() end
        if b.SetAttribute then b:SetAttribute("statehidden", true) end
    end
    -- the main bar keeps its events (the client expects it to), bar
    -- paging events it does not need are dropped
    if MainMenuBar then
        if MainMenuBar.UnregisterEvent then
            pcall(MainMenuBar.UnregisterEvent, MainMenuBar, "PLAYER_REGEN_ENABLED")
            pcall(MainMenuBar.UnregisterEvent, MainMenuBar, "PLAYER_REGEN_DISABLED")
            pcall(MainMenuBar.UnregisterEvent, MainMenuBar, "ACTIONBAR_SHOWGRID")
            pcall(MainMenuBar.UnregisterEvent, MainMenuBar, "ACTIONBAR_HIDEGRID")
        end
        Frame(MainMenuBar, false)
    end
    Frame(_G.MainActionBar, false)
    for _, name in ipairs({ "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarLeft",
                            "MultiBarRight", "MultiBar5", "MultiBar6", "MultiBar7" }) do
        Frame(_G[name], true)
    end
    for _, prefix in ipairs({ "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton",
                              "MultiBarRightButton", "MultiBarLeftButton",
                              "MultiBar5Button", "MultiBar6Button", "MultiBar7Button" }) do
        for i = 1, 12 do Button(_G[prefix .. i]) end
    end
    Frame(_G.MicroButtonAndBagsBar, false)
    Frame(_G.StanceBar, true)
    Frame(_G.StanceBarFrame, true)
    Frame(_G.PossessActionBar, true)
    Frame(_G.PossessBarFrame, true)
    Frame(_G.MultiCastActionBarFrame, true)
    Frame(_G.PetActionBar, true)
    Frame(_G.PetActionBarFrame, true)
    Frame(_G.StatusTrackingBarManager, false)
    Frame(_G.BagsBar, true)
    Frame(_G.MicroMenu, true)
    if _G.MainMenuBarVehicleLeaveButton then Frame(_G.MainMenuBarVehicleLeaveButton, true) end
end
function AB.Hider() return hider end

-- ============================================================
-- FADING
-- ============================================================
-- Bars that fade poll the mouse on a shared ticker (alpha is not a
-- protected write, so this runs in combat too). While ZacUI's Edit Mode
-- is open every bar is forced visible so it can be dragged.
--
-- THE TRANSITION. The poll only decides which way a bar should be (in:
-- pointed at, out: not); the move itself is AB.FadeTo, an alpha tween
-- on the motion layer's ticker (ns.Animate) that honours the global
-- Motion switch and speed. Not ns.Motion.Play: a bar is a secure header,
-- which Motion rightly leaves alone in combat, and its show/hide is the
-- state driver's - only alpha is ours, and alpha may be written any time.

-- An animation spec's fade, from wherever the frame's alpha is now to
-- `target`. spec nil / "none" / Motion off = the instant snap. `delay`
-- (seconds) overrides the spec's own. Returns true if it animates.
-- The tween itself is ns.Motion.FadeTo (it started here and moved into
-- the motion layer for every part to use); these two names stay for the
-- bar code and the preview.
function AB.FadeTo(frame, target, spec, delay)
    if not frame then return false end
    local M = ns.Motion
    if M and M.FadeTo then return M.FadeTo(frame, target, spec, delay) end
    frame:SetAlpha(target)
    return false
end

-- waiting out a delay, or mid-tween: the poll leaves the alpha alone
function AB.FadeBusy(frame)
    local M = ns.Motion
    if M and M.FadeBusy then return M.FadeBusy(frame) end
    return false
end

-- A bar's two fade animations, and the wait before the fade-out (only
-- for a real fade - "none" stays the instant snap it always was).
function AB.FadeSpecs(cfg)
    local inS = type(cfg.fadeIn) == "table" and cfg.fadeIn or AB.FADE_IN
    local outS = type(cfg.fadeOut) == "table" and cfg.fadeOut or AB.FADE_OUT
    local wait = 0
    if outS.style and outS.style ~= "none" then wait = math.max(0, tonumber(cfg.fadeDelay) or 0) end
    return inS, outS, wait
end

local fadeBars, fadeTicker = {}, nil
function AB.RegisterFade(header, cfg)
    if cfg.fade then fadeBars[header] = cfg else fadeBars[header] = nil end
    local any = next(fadeBars) ~= nil
    if any and not fadeTicker then
        fadeTicker = C_Timer.NewTicker(0.15, function() AB.PollFade() end)
        if ns.Profiler and ns.Profiler.TrackTicker then ns.Profiler.TrackTicker(fadeTicker, "bars.fade") end
    elseif not any and fadeTicker then
        fadeTicker:Cancel()
        fadeTicker = nil
    end
    -- Every (re)apply writes the bar's full alpha first, so the poll's
    -- memory of which way the bar was is stale from here: forget it (and
    -- any fade in flight), and the first poll puts the bar straight where
    -- it belongs - a re-apply never plays a fade.
    header._zFadeState = nil
    header._zFadeSerial = (header._zFadeSerial or 0) + 1
    header._zFadeWait = nil
    if ns.StopAnim then ns.StopAnim(header) end
    if not cfg.fade then header:SetAlpha(cfg.alpha or 1) else AB.PollFade() end
end

local function Hovered(header)
    local ov = header.overlay or header
    if MouseIsOver(ov) then return true end
    -- a flyout open from one of the bar's buttons counts as hovering it
    local fly = _G.SpellFlyout
    if fly and fly:IsShown() then
        local p = fly:GetParent()
        while p do
            if p == header then return true end
            p = p:GetParent()
        end
    end
    return false
end

function AB.PollFade()
    local edit = ns.IsEditMode and ns.IsEditMode()
    for header, cfg in pairs(fadeBars) do
        local want = (edit or Hovered(header)) and "in" or "out"
        local target = (want == "in") and (cfg.alpha or 1) or (cfg.fadeAlpha or 0.1)
        if header._zFadeState ~= want then
            local first = header._zFadeState == nil
            header._zFadeState = want
            local inS, outS, wait = AB.FadeSpecs(cfg)
            if first then
                AB.FadeTo(header, target, nil)
            elseif want == "in" then
                AB.FadeTo(header, target, inS)
            else
                AB.FadeTo(header, target, outS, wait)
            end
        elseif not AB.FadeBusy(header) and header:GetAlpha() ~= target then
            -- compared against the live alpha too: anything else that
            -- writes the bar's alpha (a re-apply, a skin pass, an opacity
            -- change) is corrected next tick
            header._zFadeTo = target
            header:SetAlpha(target)
        end
    end
end

-- ============================================================
-- HEADERS
-- ============================================================
-- Every bar is a 1x1 secure state header with an overlay child for the
-- mouse, and the registry of all of them for the apply pass.
AB.headers = {}
function AB.NewHeader(key, name, label)
    local h = CreateFrame("Frame", name, UIParent, "SecureHandlerStateTemplate")
    h:SetSize(1, 1)
    h:SetFrameStrata("MEDIUM")
    h.key, h.label = key, label
    local ov = CreateFrame("Frame", nil, h)
    ov:SetFrameLevel(h:GetFrameLevel())
    ov:EnableMouse(false)
    h.overlay = ov
    AB.headers[key] = h
    return h
end

-- A template's named region: the parentKey field when the template set
-- one (modern buttons), else the "<ButtonName>Suffix" global (classic).
function AB.Region(btn, key, suffix)
    local r = rawget(btn, key)
    if type(r) == "table" then return r end
    local name = btn.GetName and btn:GetName()
    return name and _G[name .. suffix] or nil
end

-- ============================================================
-- KEY TEXT
-- ============================================================
-- Short form for the hotkey corner: capital modifier letters, one
-- hyphen, then a short key name. SHIFT-MOUSEWHEELUP -> S-WU,
-- CTRL-NUMPAD7 -> C-N7, ALT-BUTTON4 -> A-M4, CTRL-SHIFT-F -> CS-F.
local KEY_SHORT = {
    { "MOUSEWHEELUP", "WU" }, { "MOUSEWHEELDOWN", "WD" }, { "BUTTON", "M" },
    { "NUMPADDIVIDE", "N/" }, { "NUMPADMULTIPLY", "N*" }, { "NUMPADMINUS", "N-" },
    { "NUMPADPLUS", "N+" }, { "NUMPADDECIMAL", "N." }, { "NUMPADEQUALS", "N=" },
    { "NUMPAD", "N" }, { "NUMLOCK", "NL" }, { "PAGEUP", "PU" }, { "PAGEDOWN", "PD" },
    { "SPACE", "Sp" }, { "INSERT", "Ins" }, { "DELETE", "Del" }, { "HOME", "Hm" },
    { "END", "En" }, { "BACKSPACE", "BS" }, { "CAPSLOCK", "Cp" }, { "ESCAPE", "Esc" },
    { "ENTER", "Ent" }, { "TAB", "Tb" }, { "SCROLLLOCK", "SL" }, { "PRINTSCREEN", "PS" },
    { "DOWN", "Dn" }, { "LEFT", "Lf" }, { "RIGHT", "Rt" }, { "UP", "Up" },
}
-- ShortKey runs per button on every hotkey refresh, so the answer for a
-- binding string is remembered; the ~30 gsubs happen once per distinct key
local MODS = { { "CTRL%-", "C" }, { "SHIFT%-", "S" }, { "ALT%-", "A" }, { "META%-", "M" } }
local shortKeys = {}
function AB.ShortKey(key)
    if not key or key == "" then return "" end
    local hit = shortKeys[key]
    if hit then return hit end
    local raw = key
    key = key:upper():gsub(" ", "")
    local mods = ""
    local changed = true
    while changed do
        changed = false
        for _, m in ipairs(MODS) do
            if key:find("^" .. m[1]) then
                mods = mods .. m[2]
                key = key:gsub("^" .. m[1], "")
                changed = true
            end
        end
    end
    for _, pair in ipairs(KEY_SHORT) do key = key:gsub(pair[1], pair[2]) end
    local out = (mods ~= "") and (mods .. "-" .. key) or key
    shortKeys[raw] = out
    return out
end

-- ============================================================
-- BUTTON LOOK - the one styling path for live buttons and the samples
-- ============================================================
-- Everything here is region work (textures, font strings, the cooldown
-- child): safe on a secure button, in combat too. The live buttons
-- (AB_ActionBars, AB_Extras) and the preview's look-alikes (AB_Preview)
-- both go through these functions, so the dock shows exactly what the
-- bars draw.

-- The profile's core settings without re-filling the whole profile on
-- every call (range and usability updates ask per button). ApplyAll
-- refreshes it.
function AB.CoreCfg()
    if not (AB.active and AB._core) then
        local ok, p = pcall(AB.Profile)
        AB._core = ok and p and p.core or {}
    end
    return AB._core
end

local WHITE = { 1, 1, 1, 1 }

-- A text element ({ font, size, flags, color, anchor, x, y, justify,
-- shadow, shadowX, shadowY }) as the standard font spec, and back. The
-- saved keys stay what they always were; only the pickers see specs.
function AB.FontSpecOf(el)
    el = el or {}
    return { face = el.font, size = el.size, outline = el.flags,
             shadow = el.shadow, shadowX = el.shadowX, shadowY = el.shadowY }
end
function AB.PutFontSpec(el, spec)
    spec = spec or {}
    el.font = spec.face
    el.size = spec.size
    el.flags = ns.FontOutlineFlags and ns.FontOutlineFlags(spec.outline) or "OUTLINE"
    el.shadow, el.shadowX, el.shadowY = spec.shadow, spec.shadowX, spec.shadowY
end

-- A font string's shadow before ZacUI ever touched it: a text element
-- with no shadow setting keeps the template's own.
local function StockShadow(fs)
    if not fs.zStockShadow then
        local x, y = 0, 0
        if fs.GetShadowOffset then x, y = fs:GetShadowOffset() end
        fs.zStockShadow = { x or 0, y or 0 }
    end
    return fs.zStockShadow
end

-- WHERE THE TEXTS SIT. Each text's corner and offsets (el.anchor / x / y
-- / justify, the bar's own keys) are its built-in spot; the bar's saved
-- anchor (cfg.anchors.<hotkey|count|macro|cooldown>, ZacUI's anchor
-- shape) goes on top, and can hang it off any other piece of the button.
-- Nothing saved = the old SetPoint exactly.
AB.ANCHOR_TEXTS = { "hotkey", "count", "macro", "cooldown" }
AB.ANCHOR_LABELS = { button = "The button", icon = "The icon", hotkey = "Key text", count = "Count",
    macro = "Macro name", cooldown = "Cooldown numbers" }
AB.ANCHOR_TARGETS = { "button", "icon", "hotkey", "count", "macro" }
function AB.ElementTarget(btn, key)
    if key == "button" then return btn
    elseif key == "icon" then return AB.Region(btn, "icon", "Icon")
    elseif key == "hotkey" then return btn.zHotkey
    elseif key == "count" then return btn.zCount
    elseif key == "macro" then return btn.zName end
    return nil
end
local function Resolver(btn)
    if not btn.zAnchorTo then btn.zAnchorTo = function(k) return AB.ElementTarget(btn, k) end end
    return btn.zAnchorTo
end
-- a text's built-in spot from its element settings (for the page too)
function AB.TextAnchorDefaults(el, into)
    local t = into or {}
    local a = (el and el.anchor) or "CENTER"
    t.point, t.relPoint, t.x, t.y = a, a, (el and el.x) or 0, (el and el.y) or 0
    t.justify = (el and el.justify) or "CENTER"
    return t
end
local function AnchorSpec(cfg, key)
    local a = key and cfg and cfg.anchors
    return type(a) == "table" and a[key] or nil
end

-- key / cfg: which text it is and the bar it is on (its saved anchor);
-- left out, the old corner alone.
function AB.ApplyText(btn, fs, el, hidden, key, cfg)
    if not (fs and el) then return end
    local sh = StockShadow(fs)
    local has = (sh[1] ~= 0 or sh[2] ~= 0)
    if ns.ApplyFontSpec then
        ns.ApplyFontSpec(fs, AB.FontSpecOf(el), { size = 12, outline = "outline", shadow = has,
            shadowX = has and sh[1] or 1, shadowY = has and sh[2] or -1 })
    else
        local path = (el.font and ns.ResolveFontPath and ns.ResolveFontPath(el.font)) or STANDARD_TEXT_FONT
        local ok, set = pcall(fs.SetFont, fs, path, el.size or 12, el.flags or "OUTLINE")
        if not (ok and set) then pcall(fs.SetFont, fs, STANDARD_TEXT_FONT, el.size or 12, el.flags or "OUTLINE") end
    end
    local r, g, b, a = 1, 1, 1, 1
    if ns.ColorOf then r, g, b, a = ns.ColorOf(el.color, WHITE) end
    fs:SetTextColor(r, g, b, a)
    local def = AB.TextAnchorDefaults(el, fs.zAnchorDef)
    def.to = btn
    fs.zAnchorDef = def
    ns.ApplyAnchor(fs, AnchorSpec(cfg, key), def, Resolver(btn))
    fs:SetAlpha(hidden and 0 or 1)
end

-- The template gives the corner texts fixed boxes (32x10, 36x10) that a
-- 13px font cannot fit three letters into; each gets the whole button
-- width and sizes its own height, never an ellipsis.
function AB.FitText(btn, width)
    for _, fs in ipairs({ btn.zHotkey, btn.zCount, btn.zName }) do
        if fs then
            fs:SetWidth(width or AB.BUTTON)
            fs:SetHeight(0)
            if fs.SetWordWrap then fs:SetWordWrap(false) end
            if fs.SetMaxLines then fs:SetMaxLines(1) end
        end
    end
end

-- The 1px border every skinned button carries (ns.AddPixelBorder), in
-- the bar's colour - or the equipped-item colour while the slot holds
-- something you are wearing.
function AB.TintButtonBorder(btn, equipped)
    if not (btn and btn._zui_borderTex) then return end
    local cfg = btn.zLook or btn.zCfg or {}
    if equipped == nil then equipped = btn.zEquipped end
    btn.zEquipped = equipped and true or nil
    local ch = cfg.chrome
    local c = (equipped and cfg.equippedColor) or (type(ch) == "table" and ch.borderColor) or cfg.borderColor
    if c and ns.ColorOf and ns.TintBorder then
        ns.TintBorder(btn, ns.ColorOf(c))
    elseif ns.TintBorder then
        ns.TintBorder(btn)
    end
end

local function Wash(tex, c, fallback, add)
    if not tex then return end
    local r, g, b, a = ns.ColorOf(c, fallback)
    tex:SetColorTexture(r, g, b, a)
    if add and tex.SetBlendMode then tex:SetBlendMode("ADD") end
end

local function AccentWash()
    local a = ns.Col and ns.Col("accent") or { r = 1, g = 0.82, b = 0 }
    return { r = a.r, g = a.g, b = a.b, a = 0.35 }
end

-- The countdown numbers on a cooldown: shown, hidden or the game's
-- option, in the bar's font and colour (nil = the client's own, put back
-- exactly as it was found).
function AB.StyleCooldown(btn, cfg)
    local cd = AB.Region(btn, "cooldown", "Cooldown")
    if not cd then return end
    if cd.SetDrawSwipe and (cfg.cdSwipe == false or btn.zNoSwipe) then
        cd:SetDrawSwipe(cfg.cdSwipe ~= false)
        btn.zNoSwipe = (cfg.cdSwipe == false) or nil
    end
    local mode = cfg.cdText or "game"
    local prev = btn.zCdMode
    btn.zCdMode = mode
    if cd.SetHideCountdownNumbers then
        if mode == "show" then
            cd:SetHideCountdownNumbers(false)
        elseif mode == "hide" then
            cd:SetHideCountdownNumbers(true)
        elseif btn.zSample or (prev and prev ~= "game") then
            -- back to the game's option (Interface > Action Bars > show
            -- cooldown numbers); a button that was never told otherwise
            -- is left exactly as the client has it
            if btn.zBar and ActionButton_UpdateCooldownNumberHidden then
                ActionButton_UpdateCooldownNumberHidden(btn)
            else
                local on = false
                if GetCVarBool then
                    local ok, v = pcall(GetCVarBool, "countdownForCooldowns")
                    on = ok and v and true or false
                end
                cd:SetHideCountdownNumbers(not on)
            end
        end
    end
    local fs = cd.GetCountdownFontString and cd:GetCountdownFontString()
    if not fs then return end
    if not fs.zStock then
        local path, size, flags = fs:GetFont()
        local r, g, b, a = 1, 1, 1, 1
        if fs.GetTextColor then r, g, b, a = fs:GetTextColor() end
        fs.zStock = { path = path, size = size, flags = flags, r = r or 1, g = g or 1, b = b or 1, a = a or 1 }
    end
    local st = fs.zStock
    local spec = cfg.fonts and cfg.fonts.cooldown
    if type(spec) == "table" and ns.ApplyFontSpec then
        ns.ApplyFontSpec(fs, spec, { size = 16, outline = "outline", shadow = false })
    elseif st.path then
        pcall(fs.SetFont, fs, st.path, st.size or 16, st.flags or "")
    end
    if cfg.cdColor then
        fs:SetTextColor(ns.ColorOf(cfg.cdColor))
    else
        fs:SetTextColor(st.r, st.g, st.b, st.a)
    end
    -- its spot: the client's own until the bar saves an anchor for it;
    -- the client's points are kept and put back when that goes again
    local spec = AnchorSpec(cfg, "cooldown")
    if spec then
        if not fs.zStockPoints then
            local pts = {}
            for i = 1, (fs.GetNumPoints and fs:GetNumPoints() or 0) do pts[i] = { fs:GetPoint(i) } end
            fs.zStockPoints = pts
            fs.zStockJustify = fs.GetJustifyH and fs:GetJustifyH() or nil
        end
        local def = fs.zAnchorDef or {}
        def.point, def.relPoint, def.x, def.y, def.to, def.justify = "CENTER", "CENTER", 0, 0, cd, nil
        fs.zAnchorDef = def
        ns.ApplyAnchor(fs, spec, def, Resolver(btn))
    elseif fs.zStockPoints then
        fs:ClearAllPoints()
        for _, pt in ipairs(fs.zStockPoints) do fs:SetPoint(unpack(pt)) end
        if fs.zStockJustify and fs.SetJustifyH then fs:SetJustifyH(fs.zStockJustify) end
        fs.zStockPoints, fs.zStockJustify = nil, nil
    end
end

-- One bar's look onto one button: icon crop, border, backing, the three
-- washes and the cooldown. Expects the button already skinned once
-- (ns.SkinSecureIcon gives it the border strips this resizes).
function AB.StyleButton(btn, cfg)
    if not btn then return end
    cfg = cfg or {}
    btn.zLook = cfg
    local icon = AB.Region(btn, "icon", "Icon")
    local z = math.max(0, math.min(30, tonumber(cfg.iconZoom) or 8)) / 100
    if icon and icon.SetTexCoord then icon:SetTexCoord(z, 1 - z, z, 1 - z) end

    -- the button's edge on the standard's chrome shape (cfg.chrome, Look
    -- tab): its border size / colour and backing colour stand in for the
    -- bar's own keys, plus a shadow and a glow; nothing saved = as before
    local ch = cfg.chrome
    if type(ch) ~= "table" or next(ch) == nil then ch = nil end
    local size = math.max(0, math.floor(tonumber(ch and ch.borderSize) or tonumber(cfg.borderSize) or 1))
    for i, t in ipairs(btn._zui_borderTex or {}) do
        local side = (i - 1) % 4          -- AddPixelBorder: top, bottom, left, right
        if side < 2 then t:SetHeight(math.max(1, size)) else t:SetWidth(math.max(1, size)) end
        if size > 0 then t:Show() else t:Hide() end
    end
    AB.TintButtonBorder(btn)

    if cfg.backdrop or (ch and ch.bgColor) then
        local bg = btn.zBackdrop
        if not bg then
            bg = btn:CreateTexture(nil, "BACKGROUND", nil, -8)
            bg._zui_own = true
            bg:SetTexture(ns.FLAT or "Interface\\Buttons\\WHITE8X8")
            bg:SetAllPoints(btn)
            btn.zBackdrop = bg
        end
        bg:SetVertexColor(ns.ColorOf((ch and ch.bgColor) or cfg.backdropColor, { 0, 0, 0, 0.6 }))
        bg:Show()
    elseif btn.zBackdrop then
        btn.zBackdrop:Hide()
    end
    if (ch or btn._abChrome) and ns.ApplyChrome then
        btn._abChrome = ch and true or nil
        local sg = btn._abSG or {}
        btn._abSG = sg
        sg.shadowSize, sg.shadowColor = ch and ch.shadowSize, ch and ch.shadowColor
        sg.glowSize, sg.glowColor = ch and ch.glowSize, ch and ch.glowColor
        ns.ApplyChrome(btn, sg, nil)
    end

    Wash(btn.GetHighlightTexture and btn:GetHighlightTexture(), cfg.hoverColor, { 1, 1, 1, 0.12 }, true)
    Wash(btn.GetPushedTexture and btn:GetPushedTexture(), cfg.pushedColor, { 1, 1, 1, 0.18 }, true)
    Wash(btn.GetCheckedTexture and btn:GetCheckedTexture(), cfg.checkedColor, AccentWash(), false)

    AB.StyleCooldown(btn, cfg)
    if btn.zGlow and btn.zGlow:IsShown() then AB.SetGlow(btn, true, true) end
end

-- ------------------------------------------------------------
-- RANGE AND USABILITY
-- ------------------------------------------------------------
-- The icon and key-text colours for a button's state. stock = the
-- colours the game itself uses (what the bars show while "colour by
-- range and usability" is off); otherwise the profile's. The key text
-- colour is nil when it should be the text element's own.
local GAME_UNUSABLE, GAME_NOMANA, GAME_RANGE = { 0.4, 0.4, 0.4 }, { 0.5, 0.5, 1.0 }, { 1, 0.13, 0.13 }
-- PER-STATE LOOKS on the standard (core.states.<outofrange|nomana|
-- unusable>: icon colour, key text colour - Look tab). They paint over
-- whichever colours are in use (the game's or the profile's); nothing
-- saved = the same colours as ever.
AB.STATE_LIST = {
    { id = "outofrange", label = "Out of range" },
    { id = "nomana", label = "Not enough mana, rage or energy" },
    { id = "unusable", label = "Cannot be used now" },
}
local function StatesOf(core)
    local st = core and core.states
    if type(st) == "table" and next(st) ~= nil then return st end
    return nil
end
AB.StatesOf = StatesOf
local function StateOver(st, oor, usable, noMana, ir, ig, ib, hr, hg, hb)
    local s = (oor and st.outofrange) or (noMana and st.nomana) or ((usable == false) and st.unusable) or nil
    if type(s) ~= "table" then return ir, ig, ib, hr, hg, hb end
    if s.color then ir, ig, ib = ns.ColorOf(s.color) end
    if s.textColor then hr, hg, hb = ns.ColorOf(s.textColor) end
    return ir, ig, ib, hr, hg, hb
end
-- what the state editor shows with nothing saved
function AB.StateDefaults(core)
    core = core or {}
    local on = core.colorButtons
    local function C(t, fb) local r, g, b = ns.ColorOf(t, fb) return { r = r, g = g, b = b, a = 1 } end
    local range = on and C(core.rangeColor, { 0.8, 0.1, 0.1 }) or C(GAME_RANGE)
    local iconRange = (on and (core.outofrange or "button") == "button")
    return {
        outofrange = { color = iconRange and range or nil, textColor = (not iconRange) and range or nil },
        nomana = { color = on and C(core.manaColor, GAME_NOMANA) or C(GAME_NOMANA) },
        unusable = { color = on and C(core.unusableColor, GAME_UNUSABLE) or C(GAME_UNUSABLE) },
    }
end
function AB.ButtonTint(core, oor, usable, noMana)
    core = core or {}
    local st = StatesOf(core)
    if st then
        return StateOver(st, oor, usable, noMana, AB.BaseTint(core, oor, usable, noMana))
    end
    return AB.BaseTint(core, oor, usable, noMana)
end
function AB.BaseTint(core, oor, usable, noMana)
    local ir, ig, ib, hr, hg, hb = 1, 1, 1, nil, nil, nil
    if not core.colorButtons then
        if noMana then ir, ig, ib = unpack(GAME_NOMANA)
        elseif usable == false then ir, ig, ib = unpack(GAME_UNUSABLE) end
        if oor then hr, hg, hb = unpack(GAME_RANGE) end
        return ir, ig, ib, hr, hg, hb
    end
    local mode = core.outofrange or "button"
    if oor and mode == "button" then
        ir, ig, ib = ns.ColorOf(core.rangeColor, { 0.8, 0.1, 0.1 })
    elseif noMana then
        ir, ig, ib = ns.ColorOf(core.manaColor, { 0.5, 0.5, 1.0 })
    elseif usable == false then
        ir, ig, ib = ns.ColorOf(core.unusableColor, GAME_UNUSABLE)
    end
    if oor and mode == "hotkey" then hr, hg, hb = ns.ColorOf(core.rangeColor, { 0.8, 0.1, 0.1 }) end
    return ir, ig, ib, hr, hg, hb
end

-- Live: after the game has coloured the button (its usability and range
-- updates), ZacUI's colours go over the top - only while they are on.
function AB.ColorButton(btn, usable, noMana)
    local core = AB.CoreCfg()
    if not btn then return end
    -- the state looks need this pass too (over the game's colours); once
    -- they go, one more pass puts the game's colours back
    local st = StatesOf(core)
    if not (core.colorButtons or st or btn._abSt) then return end
    btn._abSt = st and true or nil
    local action = btn.action
    if usable == nil and action and IsUsableAction then usable, noMana = IsUsableAction(action) end
    if usable == nil then usable = true end
    local ir, ig, ib, hr, hg, hb = AB.ButtonTint(core, btn.zOutOfRange, usable and true or false, noMana)
    local icon = AB.Region(btn, "icon", "Icon")
    if icon then icon:SetVertexColor(ir, ig, ib) end
    local fs = btn.zHotkey
    if fs then
        if hr then fs:SetVertexColor(hr, hg, hb)
        else
            local el = btn.zCfg and btn.zCfg.fonts and btn.zCfg.fonts.hotkey
            local r, g, b = ns.ColorOf(el and el.color, WHITE)
            fs:SetVertexColor(r, g, b)
        end
    end
end

-- The icon colour for a pet or stance button that cannot be used now.
function AB.UnusableTint()
    local core = AB.CoreCfg()
    if core.colorButtons then return ns.ColorOf(core.unusableColor, GAME_UNUSABLE) end
    return GAME_UNUSABLE[1], GAME_UNUSABLE[2], GAME_UNUSABLE[3]
end

-- ------------------------------------------------------------
-- SPELL ALERT GLOW
-- ------------------------------------------------------------
-- ZacUI's own glow: a coloured frame round the button on an insecure
-- child (never the button itself), shown while the spell's alert is up
-- and moved by ns.Motion as a repeating highlight. Hung from one point
-- so a pulse grows from the middle.
function AB.EnsureGlow(btn)
    local g = btn.zGlow
    if g then return g end
    g = CreateFrame("Frame", nil, btn)
    g:SetFrameLevel((btn:GetFrameLevel() or 1) + 6)
    if g.EnableMouse then g:EnableMouse(false) end
    g.strips = {}
    for i = 1, 4 do
        local t = g:CreateTexture(nil, "OVERLAY", nil, 7)
        t._zui_own = true
        t:SetTexture(ns.FLAT or "Interface\\Buttons\\WHITE8X8")
        g.strips[i] = t
    end
    g:Hide()
    btn.zGlow = g
    return g
end

function AB.StyleGlow(btn)
    local g = AB.EnsureGlow(btn)
    local core = AB.CoreCfg()
    local t = math.max(1, math.floor(tonumber(core.glowSize) or 2))
    local w, h = btn:GetWidth() or AB.BUTTON, btn:GetHeight() or AB.BUTTON
    g:ClearAllPoints()
    g:SetPoint("CENTER", btn, "CENTER", 0, 0)
    g:SetSize(w + 2 * t, h + 2 * t)
    local s = g.strips
    s[1]:ClearAllPoints() s[1]:SetPoint("TOPLEFT") s[1]:SetPoint("TOPRIGHT") s[1]:SetHeight(t)
    s[2]:ClearAllPoints() s[2]:SetPoint("BOTTOMLEFT") s[2]:SetPoint("BOTTOMRIGHT") s[2]:SetHeight(t)
    s[3]:ClearAllPoints() s[3]:SetPoint("TOPLEFT", 0, -t) s[3]:SetPoint("BOTTOMLEFT", 0, t) s[3]:SetWidth(t)
    s[4]:ClearAllPoints() s[4]:SetPoint("TOPRIGHT", 0, -t) s[4]:SetPoint("BOTTOMRIGHT", 0, t) s[4]:SetWidth(t)
    local r, gg, b, a = ns.ColorOf(core.glowColor, { 1, 0.82, 0, 1 })
    for _, tex in ipairs(s) do tex:SetVertexColor(r, gg, b, a) end
end

-- on/off; restyle = put it back up with the current settings
function AB.SetGlow(btn, on, restyle)
    if not btn then return end
    local g = btn.zGlow
    if not on then
        if g then
            if ns.Motion then ns.Motion.Stop(g) end
            g:Hide()
        end
        return
    end
    g = AB.EnsureGlow(btn)
    if g:IsShown() and not restyle then return end
    if ns.Motion then ns.Motion.Stop(g) end
    AB.StyleGlow(btn)
    g:Show()
    if ns.Motion then ns.Motion.Play(g, AB.CoreCfg().glowAnim, "update") end
end

-- The game's own alert frame on a button (whichever this client makes).
function AB.HideStockAlert(btn)
    local a = rawget(btn, "SpellActivationAlert") or rawget(btn, "overlay")
    if type(a) == "table" and a.Hide and a.IsShown and a:IsShown() then a:Hide() end
end

-- ============================================================
-- LOCK / UNLOCK (drag overlays)
-- ============================================================
-- A mover is a sibling frame laid over the bar's overlay. Dragging it
-- drags a copy; on release the header is re-anchored to where the copy
-- ended (out of combat only) and the position saved.
local movers = {}
function AB.MoverFor(header, cfg, onMoved)
    local m = movers[header]
    if m then m.cfg, m.onMoved = cfg, onMoved return m end
    m = CreateFrame("Frame", nil, UIParent)
    m.header, m.cfg, m.onMoved = header, cfg, onMoved
    local function Drop(self)
        if InCombatLockdown() then AB.FitMover(self) return end
        -- where the header's anchor corner now is: the mover's matching
        -- corner plus the overlay inset
        local hdr, cfg = self.header, self.cfg
        local anchor, v, h = AB.AnchorOf(cfg)
        local s = hdr:GetScale() or 1
        local mx = (h == "LEFT") and self:GetLeft() or self:GetRight()
        local my = (v == "TOP") and self:GetTop() or self:GetBottom()
        if not (mx and my) then AB.FitMover(self) return end
        mx = mx - ((h == "LEFT") and 1 or -1) * s
        my = my - ((v == "TOP") and 1 or -1) * s
        hdr:ClearAllPoints()
        hdr:SetPoint(anchor, UIParent, "BOTTOMLEFT", mx / s, my / s)
        AB.SavePosition(hdr, cfg)
        AB.Place(hdr, cfg)
        AB.FitMover(self)
        if self.onMoved then self.onMoved() end
    end
    -- ZacUI's handle kit: the bar's name, its spot in the Action bars
    -- page's numbers (the nearest screen corner or edge by thirds, in UI
    -- units) on hover / while dragging, nudge, right-click reset, and a
    -- red "locked" box in combat (the bars are secure)
    ns.MoverKit.Dress(m, {
        label = function(self) return self.header.label or self.header.key end,
        secure = true,
        coords = function(self)
            local cfg = self.cfg
            if rawget(self, "_zDragging") or not (cfg and cfg.point) then
                local probe = { }
                local l, r, t, b = self:GetLeft(), self:GetRight(), self:GetTop(), self:GetBottom()
                if not l then return nil end
                -- the same thirds rule as AB.SavePosition, on the box
                local uw, uh = UIParent:GetWidth(), UIParent:GetHeight()
                local cx, cy = (l + r) / 2, (t + b) / 2
                local h = (cx < uw / 3) and "LEFT" or (cx > uw * 2 / 3) and "RIGHT" or ""
                local v = (cy < uh / 3) and "BOTTOM" or (cy > uh * 2 / 3) and "TOP" or ""
                probe.x = (h == "LEFT") and l or (h == "RIGHT") and (r - uw) or (cx - uw / 2)
                probe.y = (v == "BOTTOM") and b or (v == "TOP") and (t - uh) or (cy - uh / 2)
                local point = v .. h
                return ns.MoverKit.Format(point ~= "" and point or "CENTER", probe.x, probe.y)
            end
            return ns.MoverKit.Format(cfg.point, cfg.x, cfg.y)
        end,
        dragStop = Drop,
        nudge = function(dx, dy, self)
            local hdr, cfg = self.header, self.cfg
            if not cfg.point then AB.SavePosition(hdr, cfg) end
            if not cfg.point then return end
            cfg.x, cfg.y = (cfg.x or 0) + dx, (cfg.y or 0) + dy
            AB.Place(hdr, cfg)
            AB.FitMover(self)
            if self.onMoved then self.onMoved() end
        end,
        reset = function(self)
            AB.ResetBarPosition(self.header)
            AB.FitMover(self)
        end,
        hint = "Settings: /zui bars",
    })
    m.text = m._zLabel
    m:Hide()
    movers[header] = m
    return m
end

function AB.FitMover(m)
    local ov = m.header.overlay or m.header
    m:ClearAllPoints()
    m:SetPoint("TOPLEFT", ov, "TOPLEFT", 0, 0)
    m:SetPoint("BOTTOMRIGHT", ov, "BOTTOMRIGHT", 0, 0)
    if ns.MoverKit and rawget(m, "_zMover") then ns.MoverKit.Refresh(m) end
end

function AB.ShowBarMover(header)
    local m = movers[header]
    if m and header:IsShown() then AB.FitMover(m) m:Show() end
end
function AB.HideBarMover(header)
    local m = movers[header]
    if m then m:Hide() end
end
function AB.ResetBarPosition(header)
    local cfg = header.cfg
    if not cfg then return end
    cfg.point, cfg.x, cfg.y = nil, nil, nil
    AB.ApplyAll()
    Print((header.label or header.key) .. " put back at its starting position.")
end

-- ZacUI's Edit Mode lists every bar alongside the other movables, so
-- each can be parked, reset and dragged from the one control box.
function AB.EditModeMovables()
    local list = {}
    for _, header in pairs(AB.headers) do
        if header.cfg and header.cfg.enabled ~= false and header:IsShown() then
            list[#list + 1] = {
                key = "zbar_" .. header.key, label = header.label or header.key,
                show = function() AB.ShowBarMover(header) end,
                hide = function() AB.HideBarMover(header) end,
                reset = function() AB.ResetBarPosition(header) end,
                -- the box Edit Mode outlines and lines its guides up on
                frames = function() local m = movers[header] return m and { m } or nil end,
                -- the bar itself, faded while it is hidden in Edit Mode
                content = function() return { header } end,
            }
        end
    end
    table.sort(list, function(a, b) return a.label < b.label end)
    return list
end
ns.EditModeProviders = ns.EditModeProviders or {}
ns.EditModeProviders[#ns.EditModeProviders + 1] = AB.EditModeMovables

AB.unlocked = false
function AB.SetUnlocked(on)
    AB.unlocked = on and true or false
    for header, m in pairs(movers) do
        if on and header:IsShown() and m.cfg and m.cfg.enabled ~= false then
            AB.FitMover(m)
            m:Show()
        else
            m:Hide()
        end
    end
    AB.PollFade()
    if AB.RefreshAllEmpty then AB.RefreshAllEmpty() end
    if on then Print("Bars unlocked - drag the gold boxes. /zui bars lock (or close Edit Mode) when done.") end
end

-- ============================================================
-- APPLY PASS
-- ============================================================
-- Each bar family registers its builder here; ApplyAll runs them all
-- against the current profile. Builders must be idempotent - they are
-- called after every settings change.
AB.appliers = {}
function AB.RegisterApplier(fn) AB.appliers[#AB.appliers + 1] = fn end

function AB.ApplyAll()
    if not AB.active then return end
    AB.AfterCombat("applyall", function()
        local p = AB.Profile()
        AB._core = p.core
        for _, fn in ipairs(AB.appliers) do
            local ok, err = pcall(fn, p)
            if not ok then Print("Action bars: " .. tostring(err)) end
        end
        if AB.unlocked then AB.SetUnlocked(true) end
    end)
end

-- The global font (Fonts & Textures): bar text already follows it when
-- a bar has no font of its own, so the push clears the per-bar overrides
-- and re-applies. The texture does not apply to buttons.
if ns.Media and ns.Media.RegisterTarget then
    ns.Media.RegisterTarget("bars", {
        label = "Action bar text",
        desc = "Key, count and macro text on every bar - clears any per-bar font override so they follow the global font.",
        order = 30,
        apply = function(font)
            if not font then return end
            local p = AB.Profile()
            for _, cfg in pairs(p.bars or {}) do
                if type(cfg) == "table" and type(cfg.fonts) == "table" then
                    for _, el in pairs(cfg.fonts) do
                        if type(el) == "table" then el.font = nil end
                    end
                end
            end
            AB.ApplyAll()
        end,
    })
end


-- Is Bartender4 running? Then this system stands down entirely and only
-- its import offer runs (AB_Import).
function AB.BartenderLoaded()
    local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    if not isLoaded then return false end
    local ok, res = pcall(isLoaded, "Bartender4")
    return ok and res and true or false
end
