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

-- the ZacUI look on the bars (the match pass's numbers; see THE MATCH
-- PASS by the text helpers)
local function HDOn()
    local L = ns.Look
    return (L and L.Is and L.Is("bars", "zacui")) and true or false
end
AB.HDOn = HDOn

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
    -- (WoW Forever, no realms: name + ruleset, the old key moved over -
    -- Core_Names; everywhere else the same string as always)
    if ns.CharKey then
        local d = ZacUIDB.bars
        return ns.CharKey(" - ", name or "?", realm or "?", type(d) == "table" and d.charProfile or nil)
    end
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
            -- a game look's kit follows the button's size (the kits below;
            -- before them the Classic ring alone, Core_Look's FitClassicRing)
            if AB.KitOf and AB.KitOf(btn) then AB.PaintKit(btn, size, size) end
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

-- VEHICLES, OVERRIDE AND POSSESS BARS (2026-11-07). Bar 1's keys are
-- taken onto ZacUI's buttons, so in a vehicle they fired the normal page
-- while Blizzard's vehicle bar held the abilities. On a client that has
-- these bars (the modern client: Retail, Forever - each index asked of the
-- client, never assumed) bar 1 pages to them first, in Blizzard's own
-- order, and to the skyriding page after the stances. Classic Era and TBC
-- have none: nothing is added there.
local function BarIndex(name)
    local f = _G[name] or (C_ActionBar and C_ActionBar[name])
    if type(f) ~= "function" then return nil end
    local ok, v = pcall(f)
    if ok and type(v) == "number" and v > 0 then return v end
    return nil
end
function AB.VehicleStates()
    if not (ns.ModernClient and ns.ModernClient()) then return nil, nil end
    local o, v, t = BarIndex("GetOverrideBarIndex"), BarIndex("GetVehicleBarIndex"), BarIndex("GetTempShapeshiftBarIndex")
    local first = {}
    if o then first[#first + 1] = "[overridebar]" .. o end
    if v then first[#first + 1] = "[vehicleui][possessbar]" .. v end
    if t then first[#first + 1] = "[shapeshift]" .. t end
    if #first == 0 then return nil, nil end
    return table.concat(first, ";"), "[bonusbar:5]11"
end

-- The page a bar shows, as a state: 0 = its own slots, N = Blizzard page
-- N (slots (N-1)*12+1 ..). Built left to right in priority order.
-- n: the bar's number (bar 1 takes the vehicle pages); left out, none.
function AB.PageDriver(cfg, n)
    local p = cfg.paging or {}
    if not p.enabled then return "0" end
    if p.customEnabled and p.custom and p.custom ~= "" then return p.custom end
    local parts = {}
    local vFirst, vLast
    if n == 1 then vFirst, vLast = AB.VehicleStates() end
    if vFirst then parts[#parts + 1] = vFirst end
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
    if vLast then parts[#parts + 1] = vLast end
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
    -- a fresh install starts each bar where Blizzard's is (ZacUI's
    -- Core_FreshLayout; nothing on an existing install), read before they go
    -- (a fresh install under a game look first takes that look's stock bar
    -- settings, so the spots below are worked out for them)
    if AB.KitFreshDefaults then pcall(AB.KitFreshDefaults) end
    -- ...and under ZacUI's own look, ZacUI's tidy layout (below); it places
    -- its bars first, so the read of Blizzard's spots leaves them alone
    if AB.ZacuiFreshLayout then pcall(AB.ZacuiFreshLayout) end
    if ns.FreshLayout and ns.FreshLayout.Bars then pcall(ns.FreshLayout.Bars, AB) end
    -- ...and where the client's bag buttons and micro menu sit (AB_Extras;
    -- read only, used only by a bar that was never placed)
    if AB.CaptureStockSpots then pcall(AB.CaptureStockSpots) end
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
    -- the vehicle / taxi leave button: on the modern client (vehicles,
    -- Retail's flight paths) it stays the client's, lifted off the hidden
    -- main bar so it can still show; elsewhere put away as before
    local leave = _G.MainMenuBarVehicleLeaveButton
    if leave and ns.ModernClient and ns.ModernClient() then
        if leave.SetParent then leave:SetParent(UIParent) end
    elseif leave then
        Frame(leave, true)
    end
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
-- Under the ZacUI look the shipped pair ("none", 0.2 s / 0.4 s, a 0.2 s
-- wait) is the reference's mouseover fade: 0.15 s each way, no wait
-- (match pass); anything picked on the Animation tab is the player's.
AB.HD_FADE = { style = "fade", duration = 0.15, delay = 0, easing = "easeOutQuad" }
local function ShippedFade(s, dur)
    return type(s) == "table" and s.style == "none" and s.duration == dur and (s.delay or 0) == 0
end
function AB.FadeSpecs(cfg)
    local inS = type(cfg.fadeIn) == "table" and cfg.fadeIn or AB.FADE_IN
    local outS = type(cfg.fadeOut) == "table" and cfg.fadeOut or AB.FADE_OUT
    local delay = tonumber(cfg.fadeDelay) or 0
    if HDOn() then
        local shippedIn, shippedOut = ShippedFade(inS, AB.FADE_IN.duration), ShippedFade(outS, AB.FADE_OUT.duration)
        if shippedIn then inS = AB.HD_FADE end
        if shippedOut then
            outS = AB.HD_FADE
            if cfg.fadeDelay == nil or cfg.fadeDelay == 0.2 then delay = 0 end
        end
    end
    local wait = 0
    if outS.style and outS.style ~= "none" then wait = math.max(0, delay) end
    return inS, outS, wait
end

-- SHOW ON MOUSEOVER (2026-11-07): "On mouseover" picked under When it
-- shows (cfg.showRule.show) is a fade to nothing until the mouse is over
-- the bar - the same poll, at 0 unless the bar's own fade is on (then its
-- fade opacity). Secure show / hide cannot see the mouse; alpha can.
function AB.HoverOnly(cfg)
    local r = cfg and cfg.showRule
    return type(r) == "table" and r.show == "mouseover" or false
end
local function FadeOn(cfg) return cfg.fade or AB.HoverOnly(cfg) end
local function OutAlpha(cfg)
    if cfg.fade then return cfg.fadeAlpha or 0.1 end
    return 0
end
AB.FadeOutAlpha = OutAlpha

local fadeBars, fadeTicker = {}, nil
function AB.RegisterFade(header, cfg)
    if FadeOn(cfg) then fadeBars[header] = cfg else fadeBars[header] = nil end
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
    if not FadeOn(cfg) then header:SetAlpha(cfg.alpha or 1) else AB.PollFade() end
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
    -- ZacUI's keybind mode shows every bar too, so each button can be bound
    local edit = (ns.IsEditMode and ns.IsEditMode()) or AB.keyMode
    for header, cfg in pairs(fadeBars) do
        local want = (edit or Hovered(header)) and "in" or "out"
        local target = (want == "in") and (cfg.alpha or 1) or OutAlpha(cfg)
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
    -- (BACKSPACE before SPACE: the other way round it came out "BACKSp")
    { "BACKSPACE", "BS" }, { "SPACE", "Sp" }, { "INSERT", "Ins" }, { "DELETE", "Del" }, { "HOME", "Hm" },
    { "END", "En" }, { "CAPSLOCK", "Cp" }, { "ESCAPE", "Esc" },
    { "ENTER", "Ent" }, { "TAB", "Tb" }, { "SCROLLLOCK", "SL" }, { "PRINTSCREEN", "PS" },
    { "DOWN", "Dn" }, { "LEFT", "Lf" }, { "RIGHT", "Rt" }, { "UP", "Up" },
}
-- ShortKey runs per button on every hotkey refresh, so the answer for a
-- binding string is remembered; the ~30 gsubs happen once per distinct key
local MODS = { { "CTRL%-", "C" }, { "SHIFT%-", "S" }, { "ALT%-", "A" }, { "META%-", "M" } }
-- THE KEY TEXT STYLE (core.keyStyle, Advanced > Keys; nothing saved =
-- "short", what the corner has always said): short S-1 / C-N7 / A-M4,
-- compact the same without the hyphen (S1, CN7, AM4), full the game's own
-- name for the key (Shift-1). Remembered per style.
AB.KEY_STYLES = {
    { id = "short", label = "Short (S-1, C-N7, A-M4)" },
    { id = "compact", label = "Compact (S1, CN7, AM4)" },
    { id = "full", label = "The game's name (Shift-1)" },
}
local shortKeys = { short = {}, compact = {}, full = {} }
function AB.ShortKey(key, style)
    if not key or key == "" then return "" end
    if not style then
        local c = AB._core or (AB.active and AB.CoreCfg()) or nil
        style = c and c.keyStyle
    end
    if not shortKeys[style or ""] then style = "short" end
    local cache = shortKeys[style]
    local hit = cache[key]
    if hit then return hit end
    local raw = key
    if style == "full" then
        local ok, t = false, nil
        if GetBindingText then ok, t = pcall(GetBindingText, key) end
        local out = (ok and type(t) == "string" and t ~= "") and t or key
        cache[raw] = out
        return out
    end
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
    local sep = (style == "compact") and "" or "-"
    local out = (mods ~= "") and (mods .. sep .. key) or key
    cache[raw] = out
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

-- ------------------------------------------------------------
-- THE MATCH PASS (2026-11-07, zui_tests/MATCH_BARS_1107.md; ZacUI look
-- only). The bar settings are SAVED as they are read (Fill), so a profile
-- holds the numbers ZacUI shipped as values. Under the ZacUI look a value
-- still at the shipped number draws the reference UI's number instead
-- (key text 12 white at -1,-3; count 12 at -1,4; macro 12 at 0,4; the
-- countdown in ZacUI's font at 12; a warm edge glow for hover / press, a
-- white one while active; the equipped ring in the item's quality colour;
-- a 0.15 grey backing in an empty slot; a 0.15 s fade). Nothing is
-- written: the Classic, Blizzard and Forever looks draw exactly what they
-- drew, and anything set by hand is the player's. A font picked on the
-- Text tab is marked (el.own) and never mapped again, so the old number
-- can be picked back.
-- ------------------------------------------------------------
-- key -> the shipped size / spot, and what they draw under the ZacUI look
AB.HD_TEXT = {
    hotkey = { size = 13, to = 12, anchor = "TOPRIGHT", x = -2, y = -4, tx = -1, ty = -3 },
    count  = { size = 16, to = 12, anchor = "BOTTOMRIGHT", x = -2, y = 4, tx = -1, ty = 4 },
    macro  = { size = 10, to = 12, anchor = "BOTTOM", x = 0, y = 2, tx = 0, ty = 4 },
}
local function HDText(el, key)
    local m = key and AB.HD_TEXT[key]
    if not (m and el and HDOn()) then return nil end
    return m
end
-- the size a text draws at
function AB.TextSize(el, key)
    local s = el and el.size
    local m = HDText(el, key)
    if m and not el.own and s == m.size then return m.to end
    return s
end
-- the spot (built-in corner offsets) a text draws at
function AB.TextSpot(el, key)
    local x, y = (el and el.x) or 0, (el and el.y) or 0
    local m = HDText(el, key)
    if m and (el.anchor or "CENTER") == m.anchor and x == m.x and y == m.y then return m.tx, m.ty end
    return x, y
end
-- the colour a text draws in: the key text's shipped grey (0.9) is white
local function ShippedGrey(c)
    if type(c) ~= "table" then return false end
    local r, g, b = c[1] or c.r, c[2] or c.g, c[3] or c.b
    local a = c[4] or c.a or 1
    return r == 0.9 and g == 0.9 and b == 0.9 and a == 1
end
function AB.TextColour(el, key)
    local c = el and el.color
    if key == "hotkey" and ShippedGrey(c) and HDText(el, key) then return 1, 1, 1, 1 end
    return ns.ColorOf(c, WHITE)
end
-- the same for a picker: the colour table that draws
function AB.TextColourShown(el, key)
    local c = el and el.color
    if key == "hotkey" and ShippedGrey(c) and HDText(el, key) then return { 1, 1, 1, 1 } end
    return c
end

-- A text element ({ font, size, flags, color, anchor, x, y, justify,
-- shadow, shadowX, shadowY }) as the standard font spec, and back. The
-- saved keys stay what they always were; only the pickers see specs.
-- key: which text it is (hotkey / count / macro), for the ZacUI look's
-- numbers (left out: the saved size as it is).
function AB.FontSpecOf(el, key)
    el = el or {}
    return { face = el.font, size = AB.TextSize(el, key), outline = el.flags,
             shadow = el.shadow, shadowX = el.shadowX, shadowY = el.shadowY }
end
function AB.PutFontSpec(el, spec)
    spec = spec or {}
    -- picked by hand: the player's from here (never mapped by the look)
    el.own = true
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
function AB.TextAnchorDefaults(el, into, key)
    local t = into or {}
    local a = (el and el.anchor) or "CENTER"
    t.point, t.relPoint = a, a
    t.x, t.y = AB.TextSpot(el, key)
    t.justify = (el and el.justify) or "CENTER"
    return t
end
local function AnchorSpec(cfg, key)
    local a = key and cfg and cfg.anchors
    return type(a) == "table" and a[key] or nil
end

-- THE HD RULE for icon text (HD_POLISH_STANDARD_1107, ZacUI look only):
-- key, count and macro text is a crisp outline with no drop shadow under
-- it - outline plus the template's shadow drew a soft double edge. Only
-- the default: a shadow picked on the Text tab stays. The Classic,
-- Blizzard and Forever looks keep the template's shadow as before.
function AB.TextShadowDefault(sh)
    local has = sh and (sh[1] ~= 0 or sh[2] ~= 0) or false
    if has and ns.Look and ns.Look.Is and ns.Look.Is("bars", "zacui") then has = false end
    return has
end

-- key / cfg: which text it is and the bar it is on (its saved anchor);
-- left out, the old corner alone.
-- A GAME LOOK'S TEXT (2026-11-08, Zac: under a game look everything is
-- that look's own by default): a text still exactly as ZacUI shipped it
-- (size, outline, colour, spot, no font picked, no anchor saved) is left
-- as the client's template draws it - the stock key, count and macro
-- fonts, colours and spots (all three outlined). Anything set by hand is
-- the player's and draws as set.
local SHIPPED_TEXT = DefaultFonts()
function AB.TextIsShipped(el, key, cfg)
    local d = key and SHIPPED_TEXT[key]
    if not (d and type(el) == "table") or el.own then return false end
    if el.font ~= nil or el.shadow ~= nil or el.shadowX ~= nil or el.shadowY ~= nil then return false end
    if el.size ~= d.size or (el.flags or "OUTLINE") ~= d.flags then return false end
    if (el.anchor or d.anchor) ~= d.anchor or (el.x or d.x) ~= d.x or (el.y or d.y) ~= d.y then return false end
    if (el.justify or d.justify) ~= d.justify then return false end
    local c, dc = el.color, d.color
    if type(c) == "table" then
        if (c[1] or c.r) ~= dc[1] or (c[2] or c.g) ~= dc[2] or (c[3] or c.b) ~= dc[3] or (c[4] or c.a or 1) ~= 1 then return false end
    end
    if AnchorSpec(cfg, key) ~= nil then return false end
    return true
end

function AB.ApplyText(btn, fs, el, hidden, key, cfg)
    if not (fs and el) then return end
    if AB.KitOf and AB.KitOf(btn) and AB.TextIsShipped(el, key, cfg) then
        -- the game look's own text: the template's, untouched
        fs:SetAlpha(hidden and 0 or 1)
        return
    end
    local sh = StockShadow(fs)
    local has = AB.TextShadowDefault(sh)
    if ns.ApplyFontSpec then
        ns.ApplyFontSpec(fs, AB.FontSpecOf(el, key), { size = 12, outline = "outline", shadow = has,
            shadowX = has and sh[1] or 1, shadowY = has and sh[2] or -1 })
    else
        local path = (el.font and ns.ResolveFontPath and ns.ResolveFontPath(el.font)) or STANDARD_TEXT_FONT
        local size = AB.TextSize(el, key) or 12
        local ok, set = pcall(fs.SetFont, fs, path, size, el.flags or "OUTLINE")
        if not (ok and set) then pcall(fs.SetFont, fs, STANDARD_TEXT_FONT, size, el.flags or "OUTLINE") end
    end
    local r, g, b, a = 1, 1, 1, 1
    if ns.ColorOf then r, g, b, a = AB.TextColour(el, key) end
    fs:SetTextColor(r, g, b, a)
    local def = AB.TextAnchorDefaults(el, fs.zAnchorDef, key)
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
    local c = (equipped and AB.EquippedColour(btn, cfg)) or (type(ch) == "table" and ch.borderColor) or cfg.borderColor
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

-- THE ZacUI LOOK'S HIGHLIGHTS (match pass): ZacUI's own edge glow
-- (Zacui/Media/Textures/btnglow, drawn by zui_tests/hd/match/
-- make_btn_glow.py), tinted, added over the icon: warm (0.973, 0.839,
-- 0.604) for hover and press, white while active. A shipped wash colour
-- (white 12 % / 18 %, no active colour) means these; a colour picked by
-- hand tints the glow instead.
AB.GLOW_TEX = "Interface\\AddOns\\Zacui\\Media\\Textures\\btnglow"
AB.HD_WARM = { r = 0.973, g = 0.839, b = 0.604, a = 1 }
AB.HD_ACTIVE = { r = 1, g = 1, b = 1, a = 1 }
local SHIPPED_WASH = { hoverColor = 0.12, pushedColor = 0.18 }
local function ShippedWash(key, c)
    local a = SHIPPED_WASH[key]
    if not a then return c == nil end
    if type(c) ~= "table" then return c == nil end
    local r, g, b = c.r or c[1], c.g or c[2], c.b or c[3]
    local ca = c.a or c[4] or 1
    return r == 1 and g == 1 and b == 1 and math.abs(ca - a) < 0.001
end
-- the colour a highlight draws in (also what the Look tab's swatch shows)
function AB.HighlightColour(cfg, key)
    local c = cfg and cfg[key]
    if HDOn() and ShippedWash(key, c) then
        return (key == "checkedColor") and AB.HD_ACTIVE or AB.HD_WARM
    end
    return c
end
local function Glow(tex, c)
    if not tex then return end
    local r, g, b, a = ns.ColorOf(c, AB.HD_WARM)
    tex:SetTexture(AB.GLOW_TEX)
    if tex.SetTexCoord then tex:SetTexCoord(0, 1, 0, 1) end
    tex:SetVertexColor(r, g, b, a)
    if tex.SetBlendMode then tex:SetBlendMode("ADD") end
end

-- The equipped-item ring: the shipped colour under the ZacUI look is the
-- item's quality colour (btn.zEquipQ, read when the slot changes), a
-- colour picked by hand is the player's.
local SHIPPED_EQUIP = { 0.35, 0.65, 1.0, 1 }
function AB.EquippedColour(btn, cfg)
    local c = cfg and cfg.equippedColor
    if not c then return nil end
    if HDOn() and btn and btn.zEquipQ and type(c) == "table" then
        local r, g, b, a = c.r or c[1], c.g or c[2], c.b or c[3], c.a or c[4] or 1
        if r == SHIPPED_EQUIP[1] and g == SHIPPED_EQUIP[2] and b == SHIPPED_EQUIP[3] and a == 1 then
            return btn.zEquipQ
        end
    end
    return c
end
-- the quality colour of the item an action slot holds (nil when unknown)
local qualityCols = {}
function AB.ItemQualityColour(action)
    if not (action and GetActionInfo) then return nil end
    local ok, kind, id = pcall(GetActionInfo, action)
    if not ok or kind ~= "item" or type(id) ~= "number" then return nil end
    local q
    if C_Item and C_Item.GetItemQualityByID then
        local ok2, v = pcall(C_Item.GetItemQualityByID, id)
        if ok2 and type(v) == "number" then q = v end
    end
    if not q and GetItemInfo then
        local ok3, _, _, v = pcall(GetItemInfo, id)
        if ok3 and type(v) == "number" then q = v end
    end
    if not q then return nil end
    local t = qualityCols[q]
    if t then return t end
    local r, g, b
    if C_Item and C_Item.GetItemQualityColor then
        local ok4, rr, gg, bb = pcall(C_Item.GetItemQualityColor, q)
        if ok4 and type(rr) == "number" then r, g, b = rr, gg, bb end
    end
    if not r and GetItemQualityColor then
        local ok5, rr, gg, bb = pcall(GetItemQualityColor, q)
        if ok5 and type(rr) == "number" then r, g, b = rr, gg, bb end
    end
    if not r then return nil end
    t = { r = r, g = g, b = b, a = 1 }
    qualityCols[q] = t
    return t
end

-- what an unset countdown font means: under the ZacUI look ZacUI's font
-- at 12 with a crisp outline (the reference's numbers), else 16 (the
-- picker's old default; with nothing picked the client's own font draws)
function AB.CooldownFontDefaults()
    return { size = HDOn() and 12 or 16, outline = "outline", shadow = false }
end

-- The countdown numbers on a cooldown: shown, hidden or the game's
-- option, in the bar's font and colour (nil = the client's own, put back
-- exactly as it was found; the ZacUI look's own numbers - match pass).
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
    local hd = HDOn() and not (btn._zLook == "classic")
    if type(spec) == "table" and ns.ApplyFontSpec then
        ns.ApplyFontSpec(fs, spec, AB.CooldownFontDefaults())
    elseif hd and ns.ApplyFontSpec then
        -- the ZacUI look's countdown: ZacUI's font, 12, a crisp outline
        ns.ApplyFontSpec(fs, nil, AB.CooldownFontDefaults())
    elseif st.path then
        -- the client's own face and size; under a game look's kit always
        -- with an outline (the numbers stay legible on the game's art)
        local fl = st.flags or ""
        if AB.KitOf and AB.KitOf(btn) and not tostring(fl):upper():find("OUTLINE") then fl = "OUTLINE" end
        pcall(fs.SetFont, fs, st.path, st.size or 16, fl)
    end
    if cfg.cdColor then
        fs:SetTextColor(ns.ColorOf(cfg.cdColor))
    elseif hd then
        fs:SetTextColor(1, 1, 1, 1)
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
    -- THE CLASSIC LOOK (Core_Look; SkinSecureIcon marked the button): the
    -- shipped zoom (8) means the look's crop (none), a zoom set by hand is
    -- the player's; the ring follows the button's size; the washes stay
    -- Blizzard's own unless a colour was picked for one. No strips exist,
    -- so the border walk below finds nothing.
    -- (the shipped zoom, 8, follows the look's icon crop through the one
    -- helper: ZacUI's cuts the bevel off, Classic's keeps it, the General
    -- page's Icon zoom tunes it)
    local classic = btn._zLook == "classic"
    -- a game look's kit (THE GAME LOOKS' KITS, below): the button wears the
    -- game's own art; the ZacUI look's border, glow and washes stand back
    -- unless a colour was picked by hand
    local kit = AB.KitOf and AB.KitOf(btn)
    local zoom = tonumber(cfg.iconZoom) or 8
    if icon and icon.SetTexCoord then
        if zoom == 8 and ns.Look and ns.Look.CropIcon then
            ns.Look.CropIcon(icon, nil, nil, { part = "bars", border = false })
        else
            if ns.Look and ns.Look.ForgetIcon then ns.Look.ForgetIcon(icon) end
            local z = math.max(0, math.min(30, zoom)) / 100
            icon:SetTexCoord(z, 1 - z, z, 1 - z)
        end
    end
    if kit then
        AB.PaintKit(btn)
    elseif classic and ns.FitClassicRing then
        ns.FitClassicRing(btn)
    end

    -- the button's edge on the standard's chrome shape (cfg.chrome, Look
    -- tab): its border size / colour and backing colour stand in for the
    -- bar's own keys, plus a shadow and a glow; nothing saved = as before
    local ch = cfg.chrome
    if type(ch) ~= "table" or next(ch) == nil then ch = nil end
    local size = math.max(0, math.floor(tonumber(ch and ch.borderSize) or tonumber(cfg.borderSize) or 1))
    for i, t in ipairs(btn._zui_borderTex or {}) do
        local side = (i - 1) % 4          -- AddPixelBorder: top, bottom, left, right
        -- through the pixel helper: N PHYSICAL pixels under the ZacUI look
        -- (SetHeight / SetWidth in UI units undid ns.Pixel.Edge and gave
        -- 1 px / 2 px edges); exactly the old SetHeight / SetWidth elsewhere
        local px = math.max(1, size)
        if not (ns.Pixel and ns.Pixel.SetEdgeSize and ns.Pixel.SetEdgeSize(t, px)) then
            if side < 2 then t:SetHeight(px) else t:SetWidth(px) end
        end
        if size > 0 and not kit then t:Show() else t:Hide() end
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

    if kit then
        -- the kit's own hover / press / active art; a colour picked by hand
        -- (not the shipped wash) is the player's and washes over it
        if not ShippedWash("hoverColor", cfg.hoverColor) then
            Wash(btn.GetHighlightTexture and btn:GetHighlightTexture(), cfg.hoverColor, { 1, 1, 1, 0.12 }, true)
        end
        if not ShippedWash("pushedColor", cfg.pushedColor) then
            Wash(btn.GetPushedTexture and btn:GetPushedTexture(), cfg.pushedColor, { 1, 1, 1, 0.18 }, true)
        end
        if cfg.checkedColor then
            Wash(btn.GetCheckedTexture and btn:GetCheckedTexture(), cfg.checkedColor, AccentWash(), false)
        end
    elseif not classic and HDOn() then
        -- the ZacUI look: the edge glow (see THE ZacUI LOOK'S HIGHLIGHTS)
        Glow(btn.GetHighlightTexture and btn:GetHighlightTexture(), AB.HighlightColour(cfg, "hoverColor"))
        Glow(btn.GetPushedTexture and btn:GetPushedTexture(), AB.HighlightColour(cfg, "pushedColor"))
        Glow(btn.GetCheckedTexture and btn:GetCheckedTexture(), AB.HighlightColour(cfg, "checkedColor"))
    else
        if not classic or cfg.hoverColor then
            Wash(btn.GetHighlightTexture and btn:GetHighlightTexture(), cfg.hoverColor, { 1, 1, 1, 0.12 }, true)
        end
        if not classic or cfg.pushedColor then
            Wash(btn.GetPushedTexture and btn:GetPushedTexture(), cfg.pushedColor, { 1, 1, 1, 0.18 }, true)
        end
        if not classic or cfg.checkedColor then
            Wash(btn.GetCheckedTexture and btn:GetCheckedTexture(), cfg.checkedColor, AccentWash(), false)
        end
    end

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

-- The key text's own colour (the bar's Text tab), put back over the
-- game's: the client's range update repaints every hotkey light grey (red
-- out of range) on each check, which buried the colour picked for it.
-- Out of range the game's red stays - that is its range cue.
local function KeyColour(btn)
    local fs = btn.zHotkey
    if not fs or btn.zOutOfRange then return end
    local el = btn.zCfg and btn.zCfg.fonts and btn.zCfg.fonts.hotkey
    if not el then return end
    local r, g, b = AB.TextColour(el, "hotkey")
    fs:SetVertexColor(r, g, b)
end
AB.KeyColour = KeyColour

-- Live: after the game has coloured the button (its usability and range
-- updates), ZacUI's colours go over the top - only while they are on.
function AB.ColorButton(btn, usable, noMana)
    local core = AB.CoreCfg()
    if not btn then return end
    -- the state looks need this pass too (over the game's colours); once
    -- they go, one more pass puts the game's colours back
    local st = StatesOf(core)
    if not (core.colorButtons or st or btn._abSt) then KeyColour(btn) return end
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
            local r, g, b = AB.TextColour(el, "hotkey")
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
    -- whole physical pixels under the ZacUI look (1 UI unit elsewhere)
    if ns.Pixel and ns.Pixel.On and ns.Pixel.On() then t = t * ns.Pixel.One(btn) end
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
                -- its spot of record, for Edit Mode's undo and Cancel
                snapshot = function()
                    local cfg = header.cfg
                    return { point = cfg.point, x = cfg.x, y = cfg.y }
                end,
                restore = function(v)
                    local cfg = header.cfg
                    if type(v) ~= "table" or not cfg or InCombatLockdown() then return end
                    cfg.point, cfg.x, cfg.y = v.point, v.x, v.y
                    AB.Place(header, cfg)
                    if movers[header] and movers[header]:IsShown() then AB.FitMover(movers[header]) end
                end,
                page = "bars",
            }
        elseif header.cfg and header.key then
            -- switched off (or hidden by its own show rules): listed
            -- greyed, with the way to bring it up
            local off = header.cfg.enabled == false
            list[#list + 1] = {
                key = "zbar_" .. header.key, label = header.label or header.key,
                show = function() end, hide = function() end,
                page = "bars",
                state = function()
                    if off then
                        return "off", "This bar is switched off. Turn it on on the Action bars page, then it can be placed here."
                    end
                    return "hidden now", "This bar is not on screen right now (its show rules on the Action bars page decide when it is)."
                end,
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

-- ============================================================
-- THE GAME LOOKS' KITS (2026-11-08, zui_tests/AB_KITS_STUDY_1108.md)
-- ============================================================
-- Under a game look (Core_Look, part "bars") the buttons wear the game's
-- own art, the way the reference UI's style kits do - its numbers, never
-- its code:
--   classic   the vanilla button: the Quickslot ring (66 on 36, one down;
--             the empty-slot ring on an empty slot), the depress, the
--             square hilight and checked art (added), the equipped ring
--             (62 on 36, one up). On Era and TBC that IS the client's own
--             template; on Forever and Retail it is painted over the
--             modern one (its mask and slot art put away).
--   blizzard  the modern template's own frame art, kept and fitted to the
--             button (WoW Forever's client draws the retail sheet for it).
--   forever   the same pieces from Forever's own atlases.
-- ZacUI's buttons keep their size (the reference scales a 45 px button
-- instead; that would shrink the key text and move saved bars): every
-- template layer is placed at the template's proportions of the button's
-- own size. Region calls only (safe on a secure button, in combat too);
-- the one frame write (the modern cooldown's anchor) waits for no combat.
-- Under ZacUI's look none of this runs.
AB.KIT_CLASSIC = {
    slot     = "Interface\\Buttons\\UI-Quickslot2",
    empty    = "Interface\\Buttons\\UI-Quickslot",
    pushed   = "Interface\\Buttons\\UI-Quickslot-Depress",
    hilight  = "Interface\\Buttons\\ButtonHilight-Square",
    checked  = "Interface\\Buttons\\CheckButtonHilight",
    equipped = "Interface\\Buttons\\UI-ActionButton-Border",
    ring = 66, border = 62, unit = 36,
}
-- the modern template's art (the Mainline ActionButtonTemplate's atlases)
AB.KIT_MODERN = {
    normal   = "UI-HUD-ActionBar-IconFrame",
    pushed   = "UI-HUD-ActionBar-IconFrame-Down",
    hover    = "UI-HUD-ActionBar-IconFrame-Mouseover",
    -- the layers the template hangs from the top-left at 46 x 45 on a 45
    -- button; a measured template size wins (AB.KitCapture)
    topLeft = { "Normal", "Highlight", "Checked", "Border", "Flash", "NewActionTexture", "SpellHighlightTexture" },
    -- every layer WoW Forever's kit lays out as the template does
    geo = { "icon", "IconMask", "SlotBackground", "SlotArt", "Normal", "Pushed", "Highlight", "Checked", "Border",
            "Flash", "NewActionTexture", "SpellHighlightTexture" },
    unitW = 46, unitH = 45, unit = 45,
}
local KIT_IDS = { classic = true, blizzard = true, forever = true }

-- the kit the bars wear this session ("zacui" when none)
function AB.Kit()
    local L = ns.Look
    local lk = L and L.For and L.For("bars")
    local id = lk and lk.id
    return KIT_IDS[id] and id or "zacui"
end
-- the kit one button was skinned in (SkinSecureIcon marks it)
-- (only the action, pet and stance buttons and their samples: AB.KitCapture
-- marks them when they are made - a bag slot's art is its icon)
function AB.KitOf(btn)
    if not (btn and rawget(btn, "_zKitNative")) then return nil end
    local id = rawget(btn, "_zLook")
    return KIT_IDS[id] and id or nil
end

-- Atlas presence, asked once per name (a piece the client lacks is
-- skipped and the template's art stays).
local atlasOK = {}
function AB.AtlasOK(name)
    if type(name) ~= "string" then return false end
    local v = atlasOK[name]
    if v == nil then
        v = false
        local get = C_Texture and C_Texture.GetAtlasInfo
        if get then
            local ok, info = pcall(get, name)
            v = (ok and type(info) == "table") and true or false
        end
        atlasOK[name] = v
    end
    return v
end

-- BLIZZARD STYLE ON THE FOREVER CLIENT: that client draws its own bronze
-- art under the retail names, so Blizzard style takes the retail sheets
-- the client still ships - by file and box (pixels: the reference UI's
-- measured records, EllesmereUI_RetailAtlas.lua:549-577). Only when the
-- file is there (its id asked of the client) and the client's atlas is not
-- already that sheet; the 2x sheet when the client draws its own pressed
-- frame from it. Anywhere else the atlas.
local SHEET1 = { 4613342, "Interface\\HUD\\UIActionBar", 256, 1024 }
local SHEET2 = { 4615764, "Interface\\HUD\\UIActionBar2x", 512, 2048 }
AB.KIT_RETAIL_ROWS = {
    ["ui-hud-actionbar-iconframe"]      = { 181, 227, 254, 299, 359, 451, 649, 739 },
    ["ui-hud-actionbar-iconframe-down"] = { 181, 227, 521, 566, 359, 451, 881, 971 },
    ["ui-hud-actionbar-gryphon-left"]   = { 1, 179, 136, 303, 1, 357, 209, 543 },
    ["ui-hud-actionbar-gryphon-right"]  = { 1, 179, 305, 472, 1, 357, 545, 879 },
    ["ui-hud-actionbar-wyvern-left"]    = { 1, 179, 474, 641, 1, 357, 881, 1215 },
    ["ui-hud-actionbar-wyvern-right"]   = { 1, 179, 643, 810, 1, 357, 1217, 1551 },
}
local sheetHas = {}
local function SheetPresent(s)
    local v = sheetHas[s]
    if v == nil then
        v = false
        if GetFileIDFromPath then
            local ok, id = pcall(GetFileIDFromPath, s[2])
            v = (ok and id == s[1]) and true or false
        end
        sheetHas[s] = v
    end
    return v
end
local function RetailBox(name)
    if not _G.ZACUI_IS_FOREVER then return nil end
    local row = AB.KIT_RETAIL_ROWS[string.lower(name)]
    if not row then return nil end
    local get = C_Texture and C_Texture.GetAtlasInfo
    local ok, native = false, nil
    if get then ok, native = pcall(get, name) end
    local nf = ok and type(native) == "table" and native.file or nil
    if nf == SHEET1[1] or nf == SHEET2[1] then return nil end      -- already the retail art
    local hi = false
    if get then
        local ok2, d = pcall(get, "UI-HUD-ActionBar-IconFrame-Down")
        hi = ok2 and type(d) == "table" and d.file == SHEET2[1] or false
    end
    local s, l, r, t, b = SHEET1, row[1], row[2], row[3], row[4]
    if (hi or not SheetPresent(SHEET1)) and SheetPresent(SHEET2) then
        s, l, r, t, b = SHEET2, row[5], row[6], row[7], row[8]
    elseif not SheetPresent(SHEET1) then
        return nil
    end
    return s[1], l / s[3], r / s[3], t / s[4], b / s[4]
end

-- One piece of modern art onto a texture: the retail sheet (Blizzard style
-- on Forever), else the atlas when the client has it. False: left as it was.
function AB.KitArt(tex, name, stock)
    if not (tex and name) then return false end
    if stock then
        local file, l, r, t, b = RetailBox(name)
        if file then
            tex:SetTexture(file)
            tex:SetTexCoord(l, r, t, b)
            return true
        end
    end
    if not (AB.AtlasOK(name) and tex.SetAtlas) then return false end
    if tex.SetTexCoord then tex:SetTexCoord(0, 1, 0, 1) end
    tex:SetAtlas(name)
    return true
end

local function StateTex(btn, kind)
    local get = btn["Get" .. kind .. "Texture"]
    return get and get(btn) or nil
end
local function LayerOf(btn, key)
    if key == "Normal" or key == "Highlight" or key == "Checked" or key == "Pushed" then return StateTex(btn, key) end
    if key == "Border" then return AB.Region(btn, "Border", "Border") end
    if key == "Flash" then return AB.Region(btn, "Flash", "Flash") end
    return rawget(btn, key)
end

-- THE TEMPLATE'S OWN SIZES, read once when a button is made (before the
-- bars resize it): the button's native edge and each top-left layer's size
-- as a share of it. What the kit fits the layers to; a client that could
-- not answer gets the template's numbers (46 x 45 on 45).
function AB.KitCapture(btn)
    if not btn or rawget(btn, "_zKitNative") then return end
    local nw = btn.GetWidth and btn:GetWidth() or 0
    local nh = btn.GetHeight and btn:GetHeight() or 0
    local nat = { w = (type(nw) == "number" and nw > 0) and nw or nil, h = (type(nh) == "number" and nh > 0) and nh or nil, layers = {} }
    if nat.w and nat.h and rawget(btn, "SlotArt") ~= nil then
        for _, key in ipairs(AB.KIT_MODERN.topLeft) do
            local t = LayerOf(btn, key)
            if t and t.GetSize then
                local lw, lh = t:GetSize()
                if type(lw) == "number" and type(lh) == "number" and lw > 0 and lh > 0 then
                    nat.layers[key] = { lw / nat.w, lh / nat.h }
                end
            end
        end
        -- WoW Forever draws the template exactly as the client lays it out:
        -- every layer's own anchors (to the button or the icon), offsets and
        -- size, and its atlas, kept to be scaled to ZacUI's button size
        -- (2026-11-08, Zac: Forever's icons did not fill the frame's window)
        local icon = AB.Region(btn, "icon", "Icon")
        nat.geo = {}
        for _, key in ipairs(AB.KIT_MODERN.geo) do
            local t = (key == "icon") and icon or LayerOf(btn, key)
            if t and t.GetNumPoints then
                local g = { pts = {} }
                local okAll = true
                for i = 1, t:GetNumPoints() do
                    local p, rel, rp, x, y = t:GetPoint(i)
                    local kind = (rel == nil or rel == btn) and "btn" or (rel == icon and key ~= "icon") and "icon" or nil
                    if not kind then okAll = false break end
                    g.pts[i] = { p, kind, rp or p, x or 0, y or 0 }
                end
                if okAll then
                    if t.GetSize then
                        local lw, lh = t:GetSize()
                        if type(lw) == "number" and type(lh) == "number" and lw > 0 and lh > 0 then g.w, g.h = lw, lh end
                    end
                    if t.GetAtlas then
                        local ok, a = pcall(t.GetAtlas, t)
                        if ok and type(a) == "string" and a ~= "" then g.atlas = a end
                    end
                    nat.geo[key] = g
                end
            end
        end
    end
    rawset(btn, "_zKitNative", nat)
end

-- is the slot filled (the ring's art follows it)
local function SlotFilled(btn)
    -- (an action bar's button; a pet or stance button's slot is not an
    -- action slot, and Blizzard shows those only while they hold something)
    if not rawget(btn, "zBar") then return true end
    local a = btn.action or (btn.GetAttribute and btn:GetAttribute("action"))
    if not a then return true end
    if C_ActionBar and C_ActionBar.HasAction then
        local ok, v = pcall(C_ActionBar.HasAction, a)
        if ok then return v and true or false end
    end
    if HasAction then
        local ok, v = pcall(HasAction, a)
        if ok then return v and true or false end
    end
    return true
end

local function PinAll(btn, tex)
    if tex and tex.ClearAllPoints then
        tex:ClearAllPoints()
        tex:SetAllPoints(btn)
    end
end

-- the modern template's extras, fitted (both kits)
local function ModernExtras(btn)
    if btn.NewActionTexture then btn.NewActionTexture:SetAlpha(0) end
    PinAll(btn, rawget(btn, "QuickKeybindHighlightTexture"))
    if not (InCombatLockdown and InCombatLockdown()) then
        local cd = AB.Region(btn, "cooldown", "Cooldown")
        if cd and cd.ClearAllPoints then
            cd:ClearAllPoints()
            cd:SetAllPoints(btn)
        end
        local ac = rawget(btn, "AutoCastOverlay")
        if ac and ac.ClearAllPoints then
            ac:ClearAllPoints()
            ac:SetAllPoints(btn)
        end
    end
end

-- Classic WoW UI on one button (study section 2)
local function PaintClassic(btn, w, h, modern)
    local art = AB.KIT_CLASSIC
    local sw, sh = w / art.unit, h / art.unit
    local icon = AB.Region(btn, "icon", "Icon")
    local mask = rawget(btn, "IconMask")
    if icon and mask then
        if icon.RemoveMaskTexture then pcall(icon.RemoveMaskTexture, icon, mask) end
        if mask.Hide then mask:Hide() end
    end
    if btn.SlotBackground then btn.SlotBackground:SetAlpha(0) end
    if btn.SlotArt then btn.SlotArt:SetAlpha(0) end
    local filled = rawget(btn, "_zKitFilled")
    if filled == nil then
        filled = SlotFilled(btn)
        rawset(btn, "_zKitFilled", filled)
    end
    local nt = StateTex(btn, "Normal")
    if nt then
        nt:SetTexture(filled and art.slot or art.empty)
        if nt.SetTexCoord then nt:SetTexCoord(0, 1, 0, 1) end
        nt:SetVertexColor(1, 1, 1, 1)
        nt:SetAlpha(1)
        nt:ClearAllPoints()
        nt:SetPoint("CENTER", btn, "CENTER", 0, -sh)
        nt:SetSize(art.ring * sw, art.ring * sh)
    end
    local pt = StateTex(btn, "Pushed")
    if pt then
        pt:SetTexture(art.pushed)
        if pt.SetTexCoord then pt:SetTexCoord(0, 1, 0, 1) end
        if modern and pt.SetDrawLayer then pt:SetDrawLayer("OVERLAY", 7) end
        if pt.SetBlendMode then pt:SetBlendMode("BLEND") end
        PinAll(btn, pt)
        pt:SetVertexColor(1, 1, 1, 1)
        pt:SetAlpha(1)
    end
    for _, s in ipairs({ { "Highlight", art.hilight }, { "Checked", art.checked } }) do
        local t = StateTex(btn, s[1])
        if t then
            t:SetTexture(s[2])
            if t.SetTexCoord then t:SetTexCoord(0, 1, 0, 1) end
            if t.SetBlendMode then t:SetBlendMode("ADD") end
            t:SetVertexColor(1, 1, 1, 1)
            t:SetAlpha(1)
            PinAll(btn, t)
        end
    end
    local bd = AB.Region(btn, "Border", "Border")
    if bd then
        bd:SetTexture(art.equipped)
        if bd.SetTexCoord then bd:SetTexCoord(0, 1, 0, 1) end
        if bd.SetBlendMode then bd:SetBlendMode("ADD") end
        bd:ClearAllPoints()
        bd:SetPoint("CENTER", btn, "CENTER", 0, sh)
        bd:SetSize(art.border * sw, art.border * sh)
    end
    if modern then
        PinAll(btn, AB.Region(btn, "Flash", "Flash"))
        PinAll(btn, rawget(btn, "SpellHighlightTexture"))
        ModernExtras(btn)
    end
end

-- Blizzard style / WoW Forever on a modern button (study sections 3, 4)
-- WoW Forever on a modern button: the client's own template, every layer
-- where and as big as the client lays it out, scaled to the button (the
-- art's real proportions, never stretched); the slot art behind the icon
-- on a bar wearing Forever's frame (the stock main bar's empty slot), the
-- dark slot background elsewhere. False when nothing was measured.
local function PaintForeverGeo(btn, w, h)
    local nat = rawget(btn, "_zKitNative")
    local geo = nat and nat.geo
    if not (geo and nat.w and nat.h and next(geo)) then return false end
    local kx, ky = w / nat.w, h / nat.h
    local icon = AB.Region(btn, "icon", "Icon")
    for key, g in pairs(geo) do
        local t = (key == "icon") and icon or LayerOf(btn, key)
        if t and t.ClearAllPoints and #g.pts > 0 then
            if g.atlas and key ~= "icon" and key ~= "IconMask" and t.SetAtlas then
                local cur
                if t.GetAtlas then local ok, a = pcall(t.GetAtlas, t) cur = ok and a or nil end
                if cur ~= g.atlas then
                    if t.SetTexCoord then t:SetTexCoord(0, 1, 0, 1) end
                    t:SetAtlas(g.atlas)
                end
            end
            t:ClearAllPoints()
            for _, p in ipairs(g.pts) do
                t:SetPoint(p[1], (p[2] == "icon") and icon or btn, p[3], p[4] * kx, p[5] * ky)
            end
            if #g.pts == 1 and g.w and t.SetSize then t:SetSize(g.w * kx, g.h * ky) end
        end
    end
    local mask = rawget(btn, "IconMask")
    if mask and mask.Show then mask:Show() end
    local cfg, n = rawget(btn, "zCfg"), rawget(btn, "zBar")
    local framed = n ~= nil and cfg ~= nil and AB.KitFrameOn(cfg, n)
    if btn.SlotArt then
        if framed then btn.SlotArt:SetAlpha(1) btn.SlotArt:Show() else btn.SlotArt:SetAlpha(0) btn.SlotArt:Hide() end
    end
    if btn.SlotBackground then btn.SlotBackground:SetAlpha(framed and 0 or 1) end
    for _, key in ipairs({ "Normal", "Pushed", "Highlight", "Checked" }) do
        local t = StateTex(btn, key)
        if t then t:SetVertexColor(1, 1, 1, 1) t:SetAlpha(1) end
    end
    ModernExtras(btn)
    return true
end

local function PaintModern(btn, w, h, kit)
    if kit == "forever" and PaintForeverGeo(btn, w, h) then return end
    local M = AB.KIT_MODERN
    local stock = kit == "blizzard"
    local nat = rawget(btn, "_zKitNative") or {}
    local layers = nat.layers or {}
    local nw = nat.w or M.unit
    local nh = nat.h or M.unit
    if btn.SlotArt then btn.SlotArt:Hide() btn.SlotArt:SetAlpha(0) end
    AB.KitArt(StateTex(btn, "Normal"), M.normal, stock)
    -- (Blizzard style draws the retail art: the retail template's own
    -- numbers, 46 x 45 on a 45 button - never the sizes measured from the
    -- client's atlases, which on the Forever client are its bigger bronze
    -- frame; 2026-11-08, Zac: "icons dont fully fill the space")
    for _, key in ipairs(M.topLeft) do
        local t = LayerOf(btn, key)
        if t and t.SetSize then
            local share = (not stock) and layers[key] or nil
            local fw = share and share[1] or (M.unitW / M.unit)
            local fh = share and share[2] or (M.unitH / M.unit)
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
            t:SetSize(w * fw, h * fh)
        end
    end
    local nt = StateTex(btn, "Normal")
    if nt then nt:SetAlpha(1) nt:SetVertexColor(1, 1, 1, 1) end
    -- hover and active: the template's own art (a hand-picked wash that
    -- covered it is gone again once the colour is back to the shipped one)
    for _, key in ipairs({ "Highlight", "Checked" }) do
        local t = StateTex(btn, key)
        if t and AB.KitArt(t, M.hover, false) then
            t:SetVertexColor(1, 1, 1, 1)
            t:SetAlpha(1)
        end
    end
    local pt = StateTex(btn, "Pushed")
    if pt then
        AB.KitArt(pt, M.pushed, stock)
        if pt.SetDrawLayer then pt:SetDrawLayer("OVERLAY", 7) end
        if pt.SetBlendMode then pt:SetBlendMode("BLEND") end
        PinAll(btn, pt)
        pt:SetVertexColor(1, 1, 1, 1)
        pt:SetAlpha(1)
    end
    -- Blizzard style: the icon fills the button (the frame's inner window)
    -- under the rounded mask laid on the icon itself, and an empty slot
    -- shows the slot's own dark background inside the frame, as the stock
    -- button does
    local icon = AB.Region(btn, "icon", "Icon")
    local mask = rawget(btn, "IconMask")
    if stock then
        if icon and icon.ClearAllPoints then
            icon:ClearAllPoints()
            icon:SetAllPoints(btn)
        end
        -- (2026-11-09, Zac on Forever: "how are my action bar icons fucked
        -- again") the Forever client's IconFrame-Mask is ITS art - a smaller
        -- window for its bronze frame - so laid on the icon it cut every
        -- icon down inside the retail frame. There the icon goes unmasked,
        -- trimmed of its own edge, and the frame's window frames it.
        local rf = ns.RealFlavor and ns.RealFlavor() or (ns.DetectFlavor and ns.DetectFlavor())
        if rf == "forever" then
            if mask and icon and icon.RemoveMaskTexture then pcall(icon.RemoveMaskTexture, icon, mask) end
            if mask and mask.Hide then mask:Hide() end
            rawset(btn, "_zKitUnmasked", true)
            if icon and icon.SetTexCoord then icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
        elseif mask and mask.ClearAllPoints and icon then
            if rawget(btn, "_zKitUnmasked") and icon.AddMaskTexture then
                pcall(icon.AddMaskTexture, icon, mask)
                rawset(btn, "_zKitUnmasked", nil)
            end
            mask:ClearAllPoints()
            mask:SetAllPoints(icon)
            if mask.Show then mask:Show() end
        end
        local bg = rawget(btn, "SlotBackground")
        if bg and bg.SetAlpha then
            PinAll(btn, bg)
            bg:SetAlpha(1)
            if bg.Show then bg:Show() end
        end
    -- the rounded mask at the template's size for this button
    elseif mask and mask.SetSize and mask.Show then
        local get = C_Texture and C_Texture.GetAtlasInfo
        local ok, info = false, nil
        if get then ok, info = pcall(get, "UI-HUD-ActionBar-IconFrame-Mask") end
        if ok and type(info) == "table" and type(info.width) == "number" and info.width > 0 then
            mask:SetSize(info.width * w / nw, (info.height or info.width) * h / nh)
        end
    end
    ModernExtras(btn)
end

-- A button's kit, painted for a w x h button (its own size when left out).
-- True when a kit was painted. Idempotent: the apply pass and every resize
-- run it again.
function AB.PaintKit(btn, w, h)
    local kit = AB.KitOf(btn)
    if not kit then return false end
    if not w then w = btn.GetWidth and btn:GetWidth() or 0 end
    if not h then h = btn.GetHeight and btn:GetHeight() or 0 end
    if type(w) ~= "number" or w <= 0 then w = AB.BUTTON end
    if type(h) ~= "number" or h <= 0 then h = w end
    local modern = rawget(btn, "SlotArt") ~= nil
    if kit == "classic" or not modern then
        PaintClassic(btn, w, h, modern)
    else
        PaintModern(btn, w, h, kit)
    end
    rawset(btn, "_zKitW", w)
    rawset(btn, "_zKitH", h)
    -- Blizzard re-runs its art pass on a modern button (Edit Mode, bar art
    -- on / off): the kit goes back on after it (a post-hook: nothing of
    -- Blizzard's is written)
    if btn.UpdateButtonArt and not rawget(btn, "_zKitArtHook") then
        rawset(btn, "_zKitArtHook", true)
        hooksecurefunc(btn, "UpdateButtonArt", function(self)
            if AB.KitOf(self) then AB.PaintKit(self, rawget(self, "_zKitW"), rawget(self, "_zKitH")) end
        end)
    end
    return true
end

-- The Classic ring follows the slot: the empty-slot art on an empty slot.
-- One comparison when nothing changed (the content edges call it).
function AB.KitSlot(btn, filled)
    if AB.KitOf(btn) ~= "classic" then return end
    filled = filled and true or false
    if rawget(btn, "_zKitFilled") == filled then return end
    rawset(btn, "_zKitFilled", filled)
    local nt = StateTex(btn, "Normal")
    if nt then nt:SetTexture(filled and AB.KIT_CLASSIC.slot or AB.KIT_CLASSIC.empty) end
end

-- ------------------------------------------------------------
-- THE BAR'S CHROME (study section 5): end caps under every game look,
-- WoW Forever's frame and dividers under that look. Per bar, a frame of
-- ours on the header (never anchored to a button), placed on the button
-- grid from the same numbers LayoutButtons uses; built the first time a
-- piece shows, hidden when none does. Apply pass only (out of combat).
-- ------------------------------------------------------------
-- unit: the button size the art is drawn for (only ever scaled down);
-- near / far: { left point, grid point, x, y, right point, grid point, x, y }
-- for one row / several; lvl: frame levels over the bar.
AB.KIT_CAPS = {
    classic = {
        unit = 36, w = 128, h = 128, lvl = 17, file = true,
        any = { "Interface\\MainMenuBar\\UI-MainMenuBar-EndCap-Dwarf",
                "Interface\\MainMenuBar\\UI-MainMenuBar-EndCap-Dwarf" },
        near = { "BOTTOMRIGHT", "BOTTOMLEFT", 28, -3, "BOTTOMLEFT", "BOTTOMRIGHT", -29, -3 },
        far  = { "BOTTOMRIGHT", "BOTTOMLEFT", 0, -3, "BOTTOMLEFT", "BOTTOMRIGHT", -1, -3 },
    },
    blizzard = {
        unit = 45, w = 104.5, h = 98, lvl = 17, stock = true,
        near = { "BOTTOMRIGHT", "BOTTOMLEFT", 9, -22, "BOTTOMLEFT", "BOTTOMRIGHT", -8, -22 },
    },
    forever = {
        unit = 45, w = 154, h = 95, lvl = 4,
        near = { "RIGHT", "LEFT", 30, 5, "LEFT", "RIGHT", -30, 5 },
    },
}
AB.KIT_CAPS.forever.art = {
    Alliance = { "ui-hud-actionbar-gryphon-left", "ui-hud-actionbar-gryphon-right" },
    Horde    = { "ui-hud-actionbar-wyvern-left",  "ui-hud-actionbar-wyvern-right" },
}
AB.KIT_CAPS.blizzard.art = AB.KIT_CAPS.forever.art
-- every look's caps sit this much higher than the art's own spot
AB.KIT_CAP_LIFT = 5
AB.KIT_FRAME = {
    frame = "UI-HUD-ActionBar-Frame",
    -- around the grid, in 45 px button units
    l = -6, t = 6, r = 4, b = -5,
    -- dividers: { start edge, end edge, middle, start depth, end depth }
    divH = { "ui-hud-actionbar-frame-divider-ThreeSlice-EdgeTop",
             "ui-hud-actionbar-frame-divider-ThreeSlice-EdgeBottom",
             "!ui-hud-actionbar-frame-divider-ThreeSlice-Center", 14, 15 },
    divV = { "ui-hud-actionbar-frame-divider-ThreeSlice-EdgeLeft",
             "ui-hud-actionbar-frame-divider-ThreeSlice-EdgeRight",
             "_ui-hud-actionbar-frame-divider-ThreeSlice-Center", 12, 12 },
    -- a divider is 12 across at its own size, starting 7 before the next button
    across = 12, before = 7,
}

-- which ends show caps / whether the frame shows, by the bar's settings:
-- nil = the bar's default (bar 1 on), a saved true / false wins
function AB.KitCapsOn(cfg, n)
    local v = cfg and cfg.endCaps
    if v == nil then return n == 1 end
    return v and true or false
end
-- a bar wearing the look's chrome shows its empty slots, as the game's own
-- main bar does (the slot art inside the frame); cfg.kitGrid = false: not
function AB.KitShowsGrid(cfg, n)
    if not cfg or cfg.kitGrid == false or AB.Kit() == "zacui" then return false end
    if AB.KitCapsOn(cfg, n) then return true end
    return AB.Kit() == "forever" and AB.KitFrameOn(cfg, n)
end
-- where a bar's chrome frame is (bar 1's: the XP bar seats on it), or nil
function AB.KitGridFrame(header)
    local st = header and rawget(header, "_zChrome")
    if not st then return nil end
    if st.under and st.under:IsShown() then return st.under, true end
    if st.host and st.host:IsShown() then return st.host, false end
    return nil
end
function AB.KitFrameOn(cfg, n)
    local v = cfg and cfg.kitFrame
    if v == nil then return n == 1 end
    return v and true or false
end

-- the art of one cap side for the player's faction (nil while neutral)
local function CapArt(c)
    if c.any then return c.any end
    local fac = UnitFactionGroup and UnitFactionGroup("player")
    return fac and c.art and c.art[fac] or nil
end
local function SetCap(tex, c, name, right)
    if c.file then
        tex:SetTexture(name)
        if right then tex:SetTexCoord(1, 0, 0, 1) else tex:SetTexCoord(0, 1, 0, 1) end
        return true
    end
    if AB.KitArt(tex, name, c.stock) then
        -- (a right cap drawn from the sheet keeps the sheet's own box)
        return true
    end
    return false
end

-- a neutral character picks a side, or the faction was not known yet:
-- the caps are painted again (registered only while waiting)
local capWait
local function WaitFaction(on)
    if not on then return end
    if not capWait then
        capWait = CreateFrame("Frame")
        capWait:SetScript("OnEvent", function(self)
            self:UnregisterAllEvents()
            if AB.ApplyAll then AB.ApplyAll() end
        end)
    end
    capWait:RegisterEvent("NEUTRAL_FACTION_SELECT_RESULT")
    capWait:RegisterEvent("PLAYER_ENTERING_WORLD")
end

local function HideChrome(st)
    if not st then return end
    if st.host then st.host:Hide() end
    if st.under then st.under:Hide() end
    if st.stone then st.stone:Hide() end
end

-- Paints bar n's chrome round its button grid (count buttons of `size`,
-- laid out by cfg as LayoutButtons lays them). The pieces live on
-- header._zChrome; the caps are also header._zGryphons (left, right).
function AB.KitChrome(header, cfg, size, count, n)
    if not header then return end
    cfg = cfg or {}
    local st = rawget(header, "_zChrome")
    local kit = AB.Kit()
    if kit == "zacui" or not cfg or cfg.enabled == false then return HideChrome(st) end
    count = math.max(1, math.min(count or cfg.buttons or 12, AB.PER_BAR))
    size = size or cfg.buttonSize or AB.BUTTON
    local perRow, rows, padX, padY = AB.LayoutShape(cfg, count)
    local vertical = perRow == 1 and count > 1
    local c = AB.KIT_CAPS[kit]
    local set = c and CapArt(c)
    local capsOn = c ~= nil and not vertical and AB.KitCapsOn(cfg, n)
    local frameOn = kit == "forever" and AB.KitFrameOn(cfg, n) and AB.AtlasOK(AB.KIT_FRAME.frame)
    -- Classic WoW UI: the original main bar's stone behind a one-row bar
    -- (Zac 2026-11-08: "even in elesmere he had the vanilla art correct")
    local stoneOn = kit == "classic" and not vertical and rows == 1 and AB.KitFrameOn(cfg, n)
    WaitFaction(capsOn and set == nil and c.art ~= nil)
    if not capsOn and not frameOn and not stoneOn then return HideChrome(st) end
    if not st then st = {} rawset(header, "_zChrome", st) end

    local anchor, v, hz = AB.AnchorOf(cfg)
    local ox = (hz == "LEFT") and 5 or -3
    local oy = (v == "TOP") and -3 or 5
    local gw = size * perRow + padX * (perRow - 1)
    local gh = size * rows + padY * (rows - 1)
    local lvl = header.GetFrameLevel and header:GetFrameLevel() or 0

    -- the caps, over the buttons (made once the bar asks for them; a side
    -- whose art the client lacks, or a neutral character's, stays hidden)
    local host = st.host
    if capsOn then
        if not host then
            host = CreateFrame("Frame", nil, header)
            host._zui_own = true
            host:EnableMouse(false)
            st.host = host
            st.capL = host:CreateTexture(nil, "OVERLAY", nil, 5)
            st.capR = host:CreateTexture(nil, "OVERLAY", nil, 5)
            st.capL._zui_own, st.capR._zui_own = true, true
        end
        host:SetFrameLevel(lvl + c.lvl)
        host:ClearAllPoints()
        host:SetPoint(anchor, header, anchor, ox, oy)
        host:SetSize(gw, gh)
        local kc = math.min(size / c.unit, 1)
        local g = (rows > 1 and c.far) or c.near
        local okL, okR = false, false
        if set then
            if st.capSet == set and st.capLook == kit then
                okL, okR = true, true
            else
                okL = SetCap(st.capL, c, set[1], false)
                okR = SetCap(st.capR, c, set[2], true)
            end
        end
        st.capSet = (okL and okR) and set or nil
        st.capLook = kit
        for side = 1, 2 do
            local t = side == 1 and st.capL or st.capR
            local i = (side == 1) and 1 or 5
            t:SetSize(c.w * kc, c.h * kc)
            t:ClearAllPoints()
            t:SetPoint(g[i], host, g[i + 1], g[i + 2] * kc, g[i + 3] * kc + AB.KIT_CAP_LIFT)
            if (side == 1 and okL) or (side == 2 and okR) then t:Show() else t:Hide() end
        end
        rawset(header, "_zGryphons", { st.capL, st.capR })
        host:Show()
    elseif host then
        host:Hide()
    end

    -- WoW Forever's frame and dividers, under the buttons
    local under = st.under
    if frameOn then
        local F = AB.KIT_FRAME
        local k = size / 45
        if not under then
            under = CreateFrame("Frame", nil, header)
            under._zui_own = true
            under:EnableMouse(false)
            st.under = under
            st.divs = {}
            local fr = under:CreateTexture(nil, "BACKGROUND", nil, -3)
            fr._zui_own = true
            fr:SetAtlas(F.frame)
            st.frame = fr
        end
        under:SetFrameLevel(lvl)
        under:ClearAllPoints()
        under:SetPoint(anchor, header, anchor, ox, oy)
        under:SetSize(gw, gh)
        st.frame:ClearAllPoints()
        st.frame:SetPoint("TOPLEFT", under, "TOPLEFT", F.l * k, F.t * k)
        st.frame:SetPoint("BOTTOMRIGHT", under, "BOTTOMRIGHT", F.r * k, F.b * k)
        -- dividers on a one-line bar at the game's spacing (2 or less)
        local line = (vertical and rows or perRow)
        local lineOnly = (vertical and perRow == 1 or rows == 1) and (vertical and padY or padX) <= 2
        local ds = vertical and F.divV or F.divH
        local nDiv = lineOnly and (line - 1) or 0
        if nDiv > 0 and not (AB.AtlasOK(ds[1]) and AB.AtlasOK(ds[2]) and AB.AtlasOK(ds[3])) then nDiv = 0 end
        local step = size + (vertical and padY or padX)
        for i = 1, nDiv do
            local d = st.divs[i]
            if not d then
                d = { under:CreateTexture(nil, "BACKGROUND", nil, -2), under:CreateTexture(nil, "BACKGROUND", nil, -2),
                      under:CreateTexture(nil, "BACKGROUND", nil, -2) }
                st.divs[i] = d
            end
            local a, b, m = d[1], d[2], d[3]
            if d.set ~= ds then
                a:SetAtlas(ds[1]) b:SetAtlas(ds[2]) m:SetAtlas(ds[3])
                d.set = ds
            end
            local at = i * step
            a:ClearAllPoints() b:ClearAllPoints() m:ClearAllPoints()
            if vertical then
                a:SetSize(ds[4], F.across) b:SetSize(ds[5], F.across)
                a:SetPoint("TOPLEFT", under, "TOPLEFT", 0, F.before - at)
                b:SetPoint("TOPRIGHT", under, "TOPRIGHT", 0, F.before - at)
                m:SetPoint("TOPLEFT", a, "TOPRIGHT")
                m:SetPoint("BOTTOMRIGHT", b, "BOTTOMLEFT")
            else
                a:SetSize(F.across, ds[4]) b:SetSize(F.across, ds[5])
                a:SetPoint("TOPLEFT", under, "TOPLEFT", at - F.before, 0)
                b:SetPoint("BOTTOMLEFT", under, "BOTTOMLEFT", at - F.before, 0)
                m:SetPoint("TOPLEFT", a, "BOTTOMLEFT")
                m:SetPoint("BOTTOMRIGHT", b, "TOPRIGHT")
            end
            a:Show() b:Show() m:Show()
        end
        for i = nDiv + 1, #st.divs do
            local d = st.divs[i]
            d[1]:Hide() d[2]:Hide() d[3]:Hide()
        end
        under:Show()
    elseif under then
        under:Hide()
    end

    -- Classic WoW UI's stone: the stock main bar art (MainMenuBarTexture0
    -- and 1 of FrameXML: UI-MainMenuBar-Dwarf, two 256 x 43 strips) laid
    -- under the buttons as the stock bar lays it under its twelve 36 px
    -- buttons - 8 px of stone left of the first, 6 right of the last, 4
    -- below and 3 above - stretched to this bar's own row
    local stone = st.stone
    if stoneOn then
        local k = size / 36
        if not stone then
            stone = CreateFrame("Frame", nil, header)
            stone._zui_own = true
            stone:EnableMouse(false)
            st.stone = stone
            st.stoneL = stone:CreateTexture(nil, "BACKGROUND", nil, -4)
            st.stoneR = stone:CreateTexture(nil, "BACKGROUND", nil, -4)
            for i, t in ipairs({ st.stoneL, st.stoneR }) do
                t._zui_own = true
                t:SetTexture("Interface\\MainMenuBar\\UI-MainMenuBar-Dwarf")
            end
            st.stoneL:SetTexCoord(0, 1, 0.83203125, 1.0)
            st.stoneR:SetTexCoord(0, 1, 0.58203125, 0.75)
        end
        stone:SetFrameLevel(math.max(0, lvl - 1))
        stone:ClearAllPoints()
        stone:SetPoint(anchor, header, anchor, ox, oy)
        stone:SetSize(gw, gh)
        -- across, the stock bar's 42 px step (36 + 6) scaled to this bar's
        -- step, so the art's button bays sit under the buttons
        local kx = (count == 12) and ((size + padX) / 42) or k
        local l, b, t = -8 * kx, -4 * k, 3 * k
        local r = (count == 12) and (l + 512 * kx - gw) or 6 * kx
        st.stoneL:ClearAllPoints()
        st.stoneL:SetPoint("TOPLEFT", stone, "TOPLEFT", l, t)
        st.stoneL:SetPoint("BOTTOMRIGHT", stone, "BOTTOM", (l + r) / 2, b)
        st.stoneR:ClearAllPoints()
        st.stoneR:SetPoint("TOPLEFT", stone, "TOP", (l + r) / 2, t)
        st.stoneR:SetPoint("BOTTOMRIGHT", stone, "BOTTOMRIGHT", r, b)
        stone:Show()
    elseif stone then
        stone:Hide()
    end
end

-- ------------------------------------------------------------
-- DEFAULT SPOTS FOR THE BAG BAR AND THE MICRO MENU (2026-11-08, Zac: "good
-- defaults for positions"). A bar that was never placed (a fresh install:
-- AB.Place saves the spot the first time, so an existing save always has
-- one and never moves) is centred on where the client's own buttons sit
-- right now, before ZacUI takes them - the stock UI's spot, on every client
-- and under every look. A client that cannot say (the buttons are already
-- hidden) gets the stock modern corner: the micro menu in the bottom-right
-- corner and the bag bar right above it, 4 px in.
-- ------------------------------------------------------------
local function StockRect(list)
    local L, B, Rr, T
    local us = UIParent:GetEffectiveScale() or 1
    for _, f in ipairs(list or {}) do
        if f and f.GetRect and (not f.IsVisible or f:IsVisible()) then
            local ok, l, b, w, h = pcall(f.GetRect, f)
            if ok and type(l) == "number" and type(b) == "number" and type(w) == "number" and type(h) == "number"
                and w > 0 and h > 0 then
                local k = (f.GetEffectiveScale and f:GetEffectiveScale() or us) / ((us > 0) and us or 1)
                l, b, w, h = l * k, b * k, w * k, h * k
                L = (L and math.min(L, l)) or l
                B = (B and math.min(B, b)) or b
                Rr = (Rr and math.max(Rr, l + w)) or (l + w)
                T = (T and math.max(T, b + h)) or (b + h)
            end
        end
    end
    return L, B, Rr, T
end
-- the header spot (AB's convention) that centres a bar of `count` buttons
-- (size wide, hgt tall) on cx, cy
function AB.SpotFor(cfg, cx, cy, count, size, hgt)
    local sc = cfg.scale or 1
    if sc <= 0 then sc = 1 end
    local perRow, rows, padX, padY = AB.LayoutShape(cfg, count)
    local w = (perRow * size + (perRow - 1) * padX) * sc
    local h = (rows * (hgt or size) + (rows - 1) * padY) * sc
    local _, v, hz = AB.AnchorOf(cfg)
    local ox = (hz == "LEFT") and 5 or -3
    local oy = (v == "TOP") and -3 or 5
    local px = ((hz == "LEFT") and (cx - w / 2) or (cx + w / 2)) - ox * sc
    local py = ((v == "TOP") and (cy + h / 2) or (cy - h / 2)) - oy * sc
    local uw, uh = UIParent:GetWidth(), UIParent:GetHeight()
    local H = (px < uw / 3) and "LEFT" or (px > uw * 2 / 3) and "RIGHT" or ""
    local V = (py < uh / 3) and "BOTTOM" or (py > uh * 2 / 3) and "TOP" or ""
    local x = (H == "LEFT") and px or (H == "RIGHT") and (px - uw) or (px - uw / 2)
    local y = (V == "BOTTOM") and py or (V == "TOP") and (py - uh) or (py - uh / 2)
    local point = V .. H
    if point == "" then point = "CENTER" end
    return point, math.floor(x + 0.5), math.floor(y + 0.5), w, h
end
AB.STOCK_CORNER = { margin = 4, microH = 40, gap = 4 }
function AB.StockRect(list) return StockRect(list) end
function AB.SeatFromStock(cfg, list, size, kind, hgt)
    if type(cfg) ~= "table" or cfg.point ~= nil then return false end
    local count = math.max(1, #(list or {}))
    local seen = AB._stock and AB._stock[kind]
    local l, b, r, t
    if seen then l, b, r, t = seen[1], seen[2], seen[3], seen[4] else l, b, r, t = StockRect(list) end
    -- (only a spot fully on the screen: never a bar seated off it)
    if l and not (l >= 0 and b >= 0 and r <= UIParent:GetWidth() + 0.5 and t <= UIParent:GetHeight() + 0.5) then
        l, b, r, t = nil, nil, nil, nil
    end
    -- (and a real row: buttons not yet laid out all sit on one spot)
    if l and count > 1 and (r - l) < size * 1.5 and (t - b) < size * 1.5 then
        l, b, r, t = nil, nil, nil, nil
    end
    -- (ZacUI's own fresh layout: the corner, not the client's spot)
    if AB._cornerFresh then l, b, r, t = nil, nil, nil, nil end
    local cx, cy
    if l then
        cx, cy = (l + r) / 2, (b + t) / 2
    else
        local C = AB.STOCK_CORNER
        local _, _, _, w, h = AB.SpotFor(cfg, 0, 0, count, size, hgt)
        local uw = UIParent:GetWidth()
        cx = uw - C.margin - w / 2
        if kind == "micro" then
            cy = C.margin + h / 2
        else
            local mc = (AB.Profile and AB.Profile().micro) or {}
            local ms = (mc.scale or 1)
            cy = C.margin + C.microH * ms + C.gap + h / 2
        end
    end
    -- the whole bar on the screen
    local _, _, _, bw, bh = AB.SpotFor(cfg, 0, 0, count, size, hgt)
    local uw, uh = UIParent:GetWidth(), UIParent:GetHeight()
    cx = math.max(bw / 2, math.min(uw - bw / 2, cx))
    cy = math.max(bh / 2, math.min(uh - bh / 2, cy))
    cfg.point, cfg.x, cfg.y = AB.SpotFor(cfg, cx, cy, count, size, hgt)
    return true
end

-- ------------------------------------------------------------
-- A FRESH INSTALL UNDER A GAME LOOK (2026-11-08, Zac: "make sure its
-- actually default to what it suppose to look like"): the bars start as
-- that look's stock bars - only the bars the game itself shows (its main
-- bar, and each extra bar the player had switched on in the game), the
-- game's button size and spacing, the pet and stance bars and the micro
-- menu at the game's own scale. Once, on the first login of a fresh
-- install (or after Reset ZacUI), and only over values still at ZacUI's
-- shipped default; everything stays the player's to change afterwards. An
-- existing save is never touched. (Fades, glows, empty-slot backings and
-- number formats already default to the game's own under a game look.)
-- ------------------------------------------------------------
--   look -> { button size, spacing }: Era / TBC's main bar spaces its 36 px
--   buttons 6 apart; the modern client's Edit Mode default is 45 px, 2 apart
AB.KIT_STOCK = {
    classic  = { size = 36, pad = 6 },
    blizzard = { size = 45, pad = 2 },
    forever  = { size = 45, pad = 2 },
}
-- ZacUI bar -> the game's bar it stands in for (Core_FreshLayout's pairs)
AB.KIT_STOCK_BARS = { [3] = "MultiBarRight", [4] = "MultiBarLeft", [5] = "MultiBarBottomRight", [6] = "MultiBarBottomLeft" }
function AB.KitFreshDefaults()
    if not (ns.freshInstall == true or ns.openSetupAfterReset == true) then return false end
    local kit = AB.Kit()
    local st = AB.KIT_STOCK[kit]
    if not st then return false end
    local ok, p = pcall(AB.Profile)
    if not (ok and type(p) == "table" and type(p.bars) == "table") then return false end
    if p.kitFresh then return false end
    p.kitFresh = kit
    -- (the modern client's main bar is shown at the 45 px of its own art;
    -- the Classic client's 36 is ZacUI's default already)
    local modernClient = ns.ModernClient and ns.ModernClient()
    for n = 1, AB.NUM_BARS do
        local c = p.bars[n]
        if type(c) == "table" then
            if n ~= 1 and c.enabled == (n <= 6) then
                local f = AB.KIT_STOCK_BARS[n] and _G[AB.KIT_STOCK_BARS[n]]
                c.enabled = (f and f.IsShown and f:IsShown()) and true or false
            end
            if c.padding == 2 then c.padding = st.pad end
            if c.buttonSize == AB.BUTTON and (kit == "classic" or modernClient) then
                c.buttonSize = (kit == "classic") and AB.BUTTON or st.size
            end
        end
    end
    if type(p.stance) == "table" and p.stance.scale == 1.5 then p.stance.scale = 1 end
    if type(p.micro) == "table" and p.micro.scale == 0.8 then p.micro.scale = 1 end
    return true
end

-- ------------------------------------------------------------
-- A FRESH INSTALL UNDER ZacUI'S OWN LOOK (2026-11-08, Zac's Forever fresh
-- install: bar 1 in two clumps, a lone stance button floating above, the bag
-- slots off at the far right). Copying the client's spots works for a game
-- look, whose bars ARE the client's; under ZacUI's look the client's spots
-- (Forever's stance bar over its hidden bars 2 and 3, a warrior's single
-- stance button) scatter ZacUI's bars. So a fresh install under ZacUI's look
-- gets ZacUI's own layout instead, bottom up, in UIParent units:
--   bar 1          centred at the bottom, one row, its empty slots shown
--                  (a new character's three spells and its 0 - = keys
--                  read as one bar, not two clumps)
--   stance, pet    the row right above it, flush with bar 1's left end
--                  (a class has one or the other; the pet bar hides with
--                  no pet out)
--   bars 6, 5, 2   stacked above that row at bar 1's width and centre (the
--                  game's Action Bar 2 and 3 pages, then ZacUI's page 2);
--                  empty until a spell is dragged on, as before
--   micro menu     in the bottom-right corner, the bag bar right above it
--                  (AB.SeatFromStock's corner, not the client's own spot)
-- Bars 3 and 4 keep Core_FreshLayout's spot (the client's right-hand bars).
-- Once, on a fresh install (or after Reset ZacUI), only for a bar still on
-- its shipped defaults (no spot saved): an existing save never moves.
-- ------------------------------------------------------------
AB.ZACUI_FRESH = { margin = 8, gap = 4 }
function AB.ZacuiFreshLayout()
    if not (ns.freshInstall == true or ns.openSetupAfterReset == true) then return false end
    if AB.Kit() ~= "zacui" then return false end
    local ok, p = pcall(AB.Profile)
    if not (ok and type(p) == "table" and type(p.bars) == "table") then return false end
    if p.zacuiFresh then return false end
    p.zacuiFresh = true
    AB._cornerFresh = true
    local Z = AB.ZACUI_FRESH
    local uw = UIParent:GetWidth()
    local cx = uw / 2
    local function Size(cfg, small) return cfg.buttonSize or (small and AB.PET_BUTTON or AB.BUTTON) end
    local function Count(cfg) return cfg.buttons or 12 end
    -- bar 1
    local c1 = p.bars[1]
    if type(c1) ~= "table" or c1.point ~= nil then return false end
    local _, _, _, w1, h1 = AB.SpotFor(c1, 0, 0, Count(c1), Size(c1))
    c1.point, c1.x, c1.y = AB.SpotFor(c1, cx, Z.margin + h1 / 2, Count(c1), Size(c1))
    if c1.showgrid == false then c1.showgrid = true end
    local left = cx - w1 / 2
    local top = Z.margin + h1
    -- stance and pet: one row above bar 1, from its left end
    local rowH = 0
    for _, key in ipairs({ "stance", "pet" }) do
        local c = p[key]
        if type(c) == "table" and c.point == nil then
            local n = 10
            local sz = Size(c, true)
            local _, _, _, w, h = AB.SpotFor(c, 0, 0, n, sz)
            c.point, c.x, c.y = AB.SpotFor(c, left + w / 2, top + Z.gap + h / 2, n, sz)
            rowH = math.max(rowH, h)
        end
    end
    if rowH > 0 then top = top + Z.gap + rowH end
    -- the next bars, stacked above at bar 1's centre
    for _, n in ipairs({ 6, 5, 2 }) do
        local c = p.bars[n]
        if type(c) == "table" and c.point == nil and c.enabled then
            local _, _, _, _, h = AB.SpotFor(c, 0, 0, Count(c), Size(c))
            c.point, c.x, c.y = AB.SpotFor(c, cx, top + Z.gap + h / 2, Count(c), Size(c))
            top = top + Z.gap + h
        end
    end
    return true
end

-- (kept for callers from before the kits: bar 1's caps on a header)
function AB.Gryphons(header, size)
    if not header then return end
    local cfg = rawget(header, "cfg") or { enabled = true, buttons = 12, rows = 1, padding = 2 }
    return AB.KitChrome(header, cfg, size, cfg.buttons or 12, rawget(header, "n") or 1)
end

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

-- The global font (Fonts & Textures): bar text follows it whenever a bar
-- has no font of its own (and is re-dressed when it changes); a font
-- picked for one bar's text stays. The push re-applies the bars. The
-- texture does not apply to buttons.
if ns.Media and ns.Media.RegisterTarget then
    ns.Media.RegisterTarget("bars", {
        label = "Action bar text",
        desc = "Key, count and macro text on every bar that has no font of its own.",
        order = 30,
        apply = function(font)
            if not font then return end
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
