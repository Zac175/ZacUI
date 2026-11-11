-- HUD_Shared - the framework the class HUDs and the Drink Ticker stand
-- on: their settings store (ZacUIDB.hud), the one-time migration from
-- Readycheck, API compat shims, a cached item-cooldown lookup, fonts and
-- colours read from ZacUI's own systems, anchors wired into ZacUI's
-- mover registry, and the config-page helpers built on UI.* + Layout.
-- Part of ZacUI; load order is set by the TOC. Must load before every
-- HUD file - they bind locals from ns.HUD at file load.

local ADDON_NAME = ...
-- Zacui_HUD is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end
-- Not on every game version (Core_Flavor's feature table): where the
-- whole part is off it stands down here, before it publishes ns.HUD.
-- Every later file of the part needs ns.HUD and returns at once without
-- it, so no frame, event, ticker or menu row is ever made there.
if ns.PartOff and ns.PartOff("Zacui_HUD") then return end

-- shared state from earlier ZacUI files
local GetColor = ns.GetColor
local Print = ns.Print
local RegisterMover = ns.RegisterMover
local RegisterPage = ns.RegisterPage
local ResolveFontPath = ns.ResolveFontPath
local UI = ns.UI

local HUD = {}
ns.HUD = HUD
-- Retail (Mainline 12.x, 2026-11-09): the part loads for HUD_Retail.lua's
-- class HUD only. The Classic HUDs (Warrior, Priest, the seven class
-- definitions, Drink Ticker, Hesitation) each return on this flag, so
-- nothing of theirs is made there. False on every other game version.
HUD.RETAIL = (ns.Flavor ~= nil and ns.Flavor() == "retail") or false

-- API compat (Interface 11509 / 20506) --------------------------------
HUD.GetSpellInfo = GetSpellInfo or (C_Spell and function(spell)
    local info = C_Spell.GetSpellInfo(spell)
    if not info then return nil end
    return info.name, nil, info.iconID, info.castTime, info.minRange, info.maxRange, info.spellID
end)

HUD.UnitAura = UnitAura or (C_UnitAuras and function(unit, index, filter)
    local a = C_UnitAuras.GetAuraDataByIndex(unit, index, filter)
    if not a or (ns.AuraHidden and ns.AuraHidden(a)) then return nil end   -- (Forever, hidden in combat)
    return a.name, a.icon, a.applications, a.dispelName, a.duration, a.expirationTime,
        a.sourceUnit, a.isStealable, a.nameplateShowPersonal, a.spellId
end)

local GetContainerNumSlots_C = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
local GetContainerItemID_C   = (C_Container and C_Container.GetContainerItemID) or GetContainerItemID
local GetContainerItemCooldown_C = (C_Container and C_Container.GetContainerItemCooldown) or GetContainerItemCooldown
HUD.GetContainerNumSlots     = GetContainerNumSlots_C
HUD.GetContainerItemID       = GetContainerItemID_C
HUD.GetContainerItemCooldown = GetContainerItemCooldown_C

HUD.GetSpellCooldown = GetSpellCooldown or (C_Spell and function(spell)
    local c = C_Spell.GetSpellCooldown(spell)
    if not c then return 0, 0, 0 end
    local en = c.isEnabled
    if ns.IsSecret(en) then en = true end
    return c.startTime, c.duration, en and 1 or 0
end)

-- WoW Forever (2026-11-07): spell and item cooldowns can come back as
-- secret values (no maths or comparing). Every HUD reads them through
-- these, so there a hidden reading keeps the last plain one while it
-- runs, else reads as ready (0, 0) - nothing does maths on a hidden one.
-- Where nothing is ever secret (Classic Era, TBC) the plain calls stay.
-- HUD.PlainCD(start, duration) does the same for a read made elsewhere.
function HUD.PlainCD(start, duration)
    if ns.Hidden(start, duration) then return 0, 0 end
    return start, duration
end
if issecretvalue ~= nil then
    local function Keep(raw)
        if not raw then return raw end
        local last = {}
        return function(a, b)
            local s, d, e, m = raw(a, b)
            local k = b ~= nil and (tostring(a) .. ":" .. tostring(b)) or a
            if ns.Hidden(s, d) then
                local l = k ~= nil and last[k]
                if l and l[1] + l[2] > GetTime() then return l[1], l[2], 1, 1 end
                return 0, 0, 1, 1
            end
            if k ~= nil and type(s) == "number" and type(d) == "number" then
                local l = last[k] or {}
                last[k] = l
                l[1], l[2] = s, d
            end
            return s, d, e, m
        end
    end
    HUD.GetSpellCooldown = Keep(HUD.GetSpellCooldown)
    -- (2026-11-07) A spell cooldown the game hides reads as ready above, but
    -- its swipe can still be drawn: the 5th value is then the game's
    -- duration object for it (C_Spell.GetSpellCooldownDuration, Forever's
    -- API docs), for IconProto:SetSwipe's third argument.
    local CSp = C_Spell
    if CSp and CSp.GetSpellCooldown and CSp.GetSpellCooldownDuration then
        local plain = HUD.GetSpellCooldown
        HUD.GetSpellCooldown = function(spell, b)
            local s, d, e, m = plain(spell, b)
            if b == nil and spell ~= nil and s == 0 then
                local ok, c = pcall(CSp.GetSpellCooldown, spell)
                if ok and type(c) == "table" and ns.IsSecret(c.startTime) then
                    local okd, obj = pcall(CSp.GetSpellCooldownDuration, spell)
                    if okd and obj then return s, d, e, m, obj end
                end
            end
            return s, d, e, m
        end
    end
    GetContainerItemCooldown_C = Keep(GetContainerItemCooldown_C)
    HUD.GetContainerItemCooldown = GetContainerItemCooldown_C
end

HUD.IsUsableSpell = IsUsableSpell or (C_Spell and C_Spell.IsSpellUsable)
HUD.IsSpellInRange = IsSpellInRange or (C_Spell and function(spell, unit)
    local r = C_Spell.IsSpellInRange(spell, unit)
    if r == nil then return nil end
    return r and 1 or 0
end)
HUD.GetSpellTexture = GetSpellTexture or (C_Spell and C_Spell.GetSpellTexture)
HUD.IsCurrentSpell  = IsCurrentSpell or (C_Spell and C_Spell.IsCurrentSpell)
HUD.GetItemCount    = GetItemCount or (C_Item and C_Item.GetItemCount)
HUD.GetItemIcon     = GetItemIcon or (C_Item and C_Item.GetItemIconByID)
HUD.GetItemInfo     = GetItemInfo or (C_Item and C_Item.GetItemInfo)

-- Shared game reads ---------------------------------------------------
-- WoW Forever: your debuffs on the target, read from the game's aura
-- tables (ns.ReadAura) instead of the old UnitAura stand-in, which drops
-- every aura with a hidden detail and stops the walk at the first. An
-- aura the game refuses is walked past. fn(name, aura) for each of yours
-- (the never-hidden "from you" flag when the caster is hidden); name is
-- nil when the game hides it as well, and the aura's own fields may be
-- hidden - show them through Core_Flavor's display helpers, never maths.
-- HUD.HIDDEN_AURAS is false on every other client: the HUDs keep their
-- own UnitAura walk there, exactly as before.
HUD.HIDDEN_AURAS = _G.ZACUI_MODERN and true or false
function HUD.EachMyTargetDebuff(fn)
    for i = 1, 40 do
        local a = ns.ReadAura("target", i, "HARMFUL")
        if a == nil then break end
        if a and ns.AuraIsMine(a) then
            local name = a.name
            if ns.IsSecret(name) then name = nil end
            fn(name, a)
        end
    end
end

-- An ability's rage cost as the client reports it (talents included), or
-- nil when it does not say. One copy for the Warrior HUD and Hesitation.
function HUD.RageCost(id)
    if id and GetSpellPowerCost then
        local ok, t = pcall(GetSpellPowerCost, id)
        if ok and type(t) == "table" then
            for _, c in ipairs(t) do
                if c.type == 1 or c.name == "RAGE" then return tonumber(c.cost) end
            end
        end
    end
    return nil
end

-- WoW Forever (2026-11-07): a swing whose time the game hides runs on the
-- game's own clock - the bar gets the swing's duration object (ns.Swings'
-- 4th value; StatusBar:SetTimerDuration, draining like the plain bars)
-- and its spark rides the fill's right edge, so nothing reads the hidden
-- value. HUD.TimedSwing(barF, durObj) answers true while it does that;
-- HUD.UntimedSwing(barF) hands the bar back to the plain fraction.
function HUD.TimedSwing(barF, durObj)
    local bar = barF and barF.bar
    if not (durObj and bar and bar.SetTimerDuration) then return false end
    if barF._zTimed ~= durObj then
        local E = Enum
        local interp = E and E.StatusBarInterpolation and E.StatusBarInterpolation.Immediate or 0
        local dirs = E and E.StatusBarTimerDirection
        local dir = dirs and dirs.RemainingTime or 1
        if not pcall(bar.SetTimerDuration, bar, durObj, interp, dir) then return false end
        barF._zTimed = durObj
        local sp = barF.spark
        local fill = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
        if sp then
            sp:ClearAllPoints()
            if fill then sp:SetPoint("CENTER", fill, "RIGHT", 0, 0) sp:Show() else sp:Hide() end
        end
    end
    return true
end
function HUD.UntimedSwing(barF)
    if barF and barF._zTimed then
        barF._zTimed = nil
        barF.bar:SetMinMaxValues(0, 1)
    end
end

-- A living enemy target the player can attack.
function HUD.TargetAttackable()
    return (UnitExists("target") and UnitCanAttack("player", "target")
        and not UnitIsDeadOrGhost("target")) and true or false
end

-- The target's health as a fraction (1 when there is no reading).
function HUD.TargetHealthFrac()
    local hpMax, hp = UnitHealthMax("target"), UnitHealth("target")
    -- (WoW Forever hides an enemy's health in combat: no reading)
    if ns.IsSecret and (ns.IsSecret(hpMax) or ns.IsSecret(hp)) then return 1 end
    if not hpMax or hpMax <= 0 then return 1 end
    return (hp or 0) / hpMax
end

-- WoW Forever, the target's health hidden: the game itself answers
-- "at or under `below` (0-1, default 20%)?" through a curve, as 1 or 0
-- for an icon's alpha (ns.HealthAlpha) - nothing here compares it. nil
-- while the health reads (the fraction above answers then) or when the
-- client has no such curve.
function HUD.TargetExecuteAlpha(below)
    if not (ns.HealthHidden and ns.HealthHidden("target")) then return nil end
    return ns.HealthAlpha("target", below or 0.2)
end

-- Settings storage ----------------------------------------------------
-- Recursive defaults merge: fills missing keys only, user values stand.
function HUD.CopyDefaults(src, dst)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            HUD.CopyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

local function Root()
    if type(ZacUIDB) ~= "table" then return nil end
    ZacUIDB.hud = ZacUIDB.hud or {}
    return ZacUIDB.hud
end

-- One store per HUD under ZacUIDB.hud, defaults merged on first read so a
-- key added later arrives without a migration step. Store() is read from
-- the HUD tickers twenty to fifty times a second, so the merge is done
-- once per stored table: it runs again only when the table object under
-- the name changes (a profile switch, import or reset puts a new one
-- there) or a different defaults table is passed for the name.
local merged = {}   -- name -> { tbl = the merged store, defaults = the defaults it got }
function HUD.Store(name, defaults)
    local root = Root()
    if not root then return nil end
    local tbl = root[name]
    if type(tbl) ~= "table" then
        tbl = {}
        root[name] = tbl
    end
    if defaults then
        local m = merged[name]
        if not (m and m.tbl == tbl and m.defaults == defaults) then
            HUD.CopyDefaults(defaults, tbl)
            if m then
                m.tbl, m.defaults = tbl, defaults
            else
                merged[name] = { tbl = tbl, defaults = defaults }
            end
        end
    end
    return tbl
end

-- Migration from Readycheck ------------------------------------------
-- The HUDs used to live in Readycheck_Testing and kept their settings
-- at the root of ReadycheckDB. Copied once into ZacUIDB.hud (never over
-- settings already here), then removed from ReadycheckDB so nothing is
-- left behind in an addon that no longer reads them.
local MIGRATE = {
    { from = "warriorHud", to = "warrior" },
    { from = "paladinHud", to = "paladin" },
    { from = "priestHud",  to = "priest" },
    { from = "drinkTicker", to = "drinkTicker" },
}

local function DeepCopy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = DeepCopy(x) end
    return out
end

function HUD.Migrate()
    local src = _G.ReadycheckDB
    if type(src) ~= "table" then return end
    local root = Root()
    if not root then return end
    local moved = {}
    for _, m in ipairs(MIGRATE) do
        local old = src[m.from]
        if type(old) == "table" then
            if type(root[m.to]) ~= "table" then
                root[m.to] = DeepCopy(old)
                moved[#moved + 1] = m.to
            end
            src[m.from] = nil
        end
    end
    if #moved > 0 then
        Print("HUD settings moved from Readycheck: " .. table.concat(moved, ", ") .. ".")
    end
end

-- ZacUIDB is a SavedVariable of this addon, so it is only guaranteed to
-- exist from our own ADDON_LOADED. ReadycheckDB loaded earlier (it is an
-- optional dependency, so Readycheck comes first when present).
local migrator = CreateFrame("Frame")
migrator:RegisterEvent("ADDON_LOADED")
migrator:SetScript("OnEvent", function(self, _, name)
    if name ~= ADDON_NAME then return end
    self:UnregisterEvent("ADDON_LOADED")
    ZacUIDB = ZacUIDB or {}
    HUD.Migrate()
end)

-- Cached item cooldowns -----------------------------------------------
-- GetItemCooldown is retail-only; Classic Era reads item cooldowns per
-- bag/slot. Scanning all bags per icon per tick is wasteful, so each
-- consumer creates its own tracker: slots are found once and cached
-- until the consumer calls MarkDirty() on BAG_UPDATE_DELAYED.
local MISSING = {}    -- sentinel: item known absent until the bags change
function HUD.NewItemCDTracker()
    local slots = {}          -- itemId -> { bag = b, slot = s } | MISSING
    local tracker = {}
    function tracker.MarkDirty()
        wipe(slots)
    end
    -- Returns start, duration (0, 0 when absent or API unavailable).
    function tracker.Get(itemId)
        if not (GetContainerNumSlots_C and GetContainerItemID_C
                and GetContainerItemCooldown_C) then
            return 0, 0
        end
        local e = slots[itemId]
        if e == MISSING then return 0, 0 end
        -- Bags can shift before the dirty event lands; re-verify the slot.
        if e and GetContainerItemID_C(e.bag, e.slot) ~= itemId then
            e = nil
        end
        if not e then
            for bag = 0, 4 do
                local n = GetContainerNumSlots_C(bag) or 0
                for slot = 1, n do
                    if GetContainerItemID_C(bag, slot) == itemId then
                        e = { bag = bag, slot = slot }
                        break
                    end
                end
                if e then break end
            end
            slots[itemId] = e or MISSING
            if not e then return 0, 0 end
        end
        local start, duration = GetContainerItemCooldown_C(e.bag, e.slot)
        return start or 0, duration or 0
    end
    return tracker
end

-- Shared look and motion ----------------------------------------------
-- What every HUD draws with (the icon and bar widgets, their text, the
-- motion), one setting each, shared by every class HUD, the Drink Ticker
-- and Hesitation's icons: ZacUIDB.hud.look and ZacUIDB.hud.motion. The
-- defaults are exactly what the widgets drew before these settings
-- existed, so nothing changes until someone changes it. Missing keys are
-- filled when read (HUD.Store), never replaced.
HUD.LOOK_DEFAULTS = {
    -- barTexture: a SharedMedia statusbar name; absent = ZacUI's texture
    barBg         = { r = 0, g = 0, b = 0, a = 0.6 },
    barBorder     = { r = 0, g = 0, b = 0, a = 1 },
    barBorderSize = 1,
    iconBg        = { r = 0, g = 0, b = 0, a = 0.5 },
    iconBorder    = { r = 0, g = 0, b = 0, a = 1 },
    iconBorderSize = 1,       -- the Warrior HUD keeps its own (its Look tab)
    swipe         = { r = 0, g = 0, b = 0, a = 0.75 },
    zoom          = 0.12,     -- how much of a spell icon's edge is cropped
    iconSheen     = 0.14,     -- the light sheen over an icon's top half
    barSheen      = 0.22,     -- ...and over a bar's fill
    barEdge       = 0.7,      -- the glowing leading edge of a bar
    desatDim      = 0.28,     -- a greyed-out icon this much darker
    flash         = { r = 1, g = 1, b = 1, a = 0.55 },   -- the "ready" flash
    font          = {},       -- HUD text: face / outline / shadow, size = a 14 px timer
    alertFont     = {},       -- big alert and reminder texts: face / outline / shadow
}
HUD.MOTION_DEFAULTS = {
    appear    = { style = "fade",  duration = 0.18, delay = 0, easing = "easeOutQuad" },
    disappear = { style = "none",  duration = 0.15, delay = 0, easing = "easeOutQuad" },
    glide     = { style = "slide", duration = 0.3,  delay = 0, easing = "easeOutCubic" },
    ready     = { style = "fade",  duration = 0.4,  delay = 0, easing = "easeOutQuad" },
}

-- THE GAME LOOKS' STOCK STYLE (2026-11-08, Core_Look's FollowDefaults):
-- under Classic WoW UI, Blizzard style and WoW Forever the HUDs keep every
-- feature but none of ZacUI's own polish the stock UI has no part of - the
-- light sheen over icons and bars and the glowing leading edge of a bar.
-- A value set by hand stays; ZacUI's look is untouched.
HUD.LOOK_STOCK = {
    { "iconSheen", 0 },
    { "barSheen", 0 },
    { "barEdge", 0 },
}
local lookFollowed
function HUD.Look()
    local t = HUD.Store("look", HUD.LOOK_DEFAULTS)
    if t and not lookFollowed then
        local L = ns.Look
        if L and L.Settled and L.Settled() and L.FollowDefaults then
            lookFollowed = true
            L.FollowDefaults(t, HUD.LOOK_DEFAULTS, HUD.LOOK_STOCK, "hud")
        end
    end
    return t or HUD.LOOK_DEFAULTS
end

function HUD.Motion()
    return HUD.Store("motion", HUD.MOTION_DEFAULTS) or HUD.MOTION_DEFAULTS
end

-- The one switch for the HUDs' motion and polish (ZacUIDB.hud.smooth).
function HUD.Smooth()
    local r = ZacUIDB and ZacUIDB.hud
    return not (r and r.smooth == false)
end

-- Fonts and colours ---------------------------------------------------
-- HUD text uses the face ZacUI is set to at the size the HUD asks for
-- (no UI size delta: these are on-screen elements, not window text).
-- Roles: "text" (timers, counts, bar values - the HUD text font, whose
-- size scales every one of them against a 14 px timer), "alert" (the big
-- reminder / alert texts, sized by their own HUD's setting) and "plain"
-- (the default: ZacUI's font at the size asked, nothing else - what other
-- parts of ZacUI get when they borrow HUD.Text). Every HUD font string is
-- remembered, so a change restyles them all.
local fonts = setmetatable({}, { __mode = "k" })
local TEXT_REF = 14

function HUD.ApplyFont(fs, size, flags, role)
    if not fs then return end
    role = role or fs._hudRole or "plain"
    fs._hudSize, fs._hudFlags, fs._hudRole = size or 11, flags or "OUTLINE", role
    fonts[fs] = true
    -- the shadow the HUD drew it with, put back when the setting is cleared
    if fs._hudSX == nil and fs.GetShadowOffset then
        fs._hudSX, fs._hudSY = fs:GetShadowOffset()
        fs._hudSX, fs._hudSY = fs._hudSX or 0, fs._hudSY or 0
    end
    local look = HUD.Look()
    local spec = (role == "alert" and look.alertFont) or (role == "text" and look.font) or nil
    if type(spec) ~= "table" then spec = {} end
    -- one font: ZacUI's (a face saved in the HUD's text font specs is
    -- kept there, and ignored)
    local cfg = ZacUIDB and ZacUIDB.font or {}
    local path = ResolveFontPath(cfg.name)
    local sz = fs._hudSize
    if role ~= "alert" and tonumber(spec.size) then
        sz = math.max(4, math.floor(sz * tonumber(spec.size) / TEXT_REF + 0.5))
    end
    local fl = fs._hudFlags
    if spec.outline ~= nil and ns.FontOutlineFlags then fl = ns.FontOutlineFlags(spec.outline) end
    -- the face the string was made with: what "Blizzard default" puts back
    local cur = ns.HouseOrig and ns.HouseOrig(fs) or select(1, fs:GetFont())
    -- A registered font whose file is missing still throws; fall back so
    -- one bad font cannot stop the HUD from building.
    -- SetFont can also fail quietly (returns false), leaving no font at all
    local ok, set = pcall(fs.SetFont, fs, path or cur or "Fonts\\FRIZQT__.TTF", sz, fl)
    if not (ok and set) then
        pcall(fs.SetFont, fs, "Fonts\\FRIZQT__.TTF", sz, fl)
    end
    -- a text in ZacUI's font is dressed again when that font changes
    if ns.TrackHouseFont then
        ns.TrackHouseFont(fs, function(s)
            HUD.ApplyFont(s, s._hudSize, s._hudFlags, s._hudRole)
        end)
    end
    if fs.SetShadowOffset then
        if spec.shadow == true then
            if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, 0.9) end
            fs:SetShadowOffset(tonumber(spec.shadowX) or 1, tonumber(spec.shadowY) or -1)
        elseif spec.shadow == false then
            fs:SetShadowOffset(0, 0)
        else
            fs:SetShadowOffset(fs._hudSX, fs._hudSY)
        end
    end
end

-- Every HUD font string again, after a font setting changed.
function HUD.RestyleFonts()
    for fs in pairs(fonts) do
        HUD.ApplyFont(fs, fs._hudSize, fs._hudFlags, fs._hudRole)
    end
end

-- WHERE AN ICON'S TEXTS SIT. Every HUD icon's texts (the class HUDs, the
-- Drink Ticker, Hesitation's icons) are made by IconProto:AddText at
-- their built-in spot. One shared saved spot per kind of text
-- (ZacUIDB.hud.look.anchors.<kind>, ZacUI's anchor shape) moves that kind
-- on every icon: any corner of the icon, or hung off another of its
-- texts. Nothing saved = the text never moves from where it was made.
HUD.ICON_TEXTS = { "p", "s", "count", "label", "mobs", "short", "plates", "nx", "key" }
HUD.ICON_TEXT_LABELS = { p = "Main timer", s = "Corner timer", count = "Stack count", label = "Label under the icon",
    mobs = "Mob count", short = "Rage short", plates = "Plate count", nx = "Press next", key = "Keybind" }
HUD.ICON_TEXT_TIPS = {
    p = "The big number on or under an icon: its cooldown or time left.",
    s = "The small second timer in an icon's top right corner.",
    count = "Charges and stacks, in an icon's bottom right corner.",
    label = "A word under an icon (an alert's name).",
    mobs = "How many mobs Whirlwind reaches, on its icon.",
    short = "How much rage an ability is short (\"-6\").",
    plates = "How many plates a sapper would hit, on its icon.",
    nx = "Hesitation's \"NEXT\" over the button to press first.",
    key = "The key that casts it, in an icon's top left corner (the class HUDs' keybind text).",
}
-- where most icons put each kind (what the page's picker shows as the
-- default; each icon's own spot is the real one)
HUD.ICON_TEXT_DEFAULTS = {
    p = { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 },
    s = { point = "TOPRIGHT", relPoint = "TOPRIGHT", x = 0, y = 0 },
    count = { point = "BOTTOMRIGHT", relPoint = "BOTTOMRIGHT", x = 0, y = 0 },
    label = { point = "CENTER", relPoint = "BOTTOM", x = 0, y = 0 },
    mobs = { point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT", x = 1, y = 1 },
    short = { point = "TOPRIGHT", relPoint = "TOPRIGHT", x = -1, y = -1 },
    plates = { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 },
    nx = { point = "CENTER", relPoint = "TOP", x = 0, y = 7 },
    key = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 1, y = -1 },
}
-- Hesitation's icons name the same texts their own way
local KIND_OF = { t = "p", n = "mobs", r = "short" }
function HUD.IconTextKind(key) return KIND_OF[key] or key end
local iconTexts = setmetatable({}, { __mode = "k" })
local function IconTextTo(fs)
    if not fs._hudTo then
        fs._hudTo = function(k)
            local icon = fs._hudIcon
            if not icon then return nil end
            if k == "icon" then return icon end
            for key, t in pairs(icon.texts or {}) do
                if HUD.IconTextKind(key) == k then return t end
            end
            return nil
        end
    end
    return fs._hudTo
end
function HUD.IconTextSpec(kind)
    local a = HUD.Look().anchors
    return type(a) == "table" and a[kind] or nil
end
-- ONE ICON'S OWN SPOT: an icon that names itself (icon._hudSpot, the
-- Warrior HUD's grid and buff-row icons: their def key) can keep its own
-- spot per kind of text (ZacUIDB.hud.look.iconAnchors.<icon>.<kind>,
-- ZacUI's anchor shape), over the shared one. Nothing saved = the shared
-- spot, which with nothing saved is the icon's own built-in point.
function HUD.IconKey(icon) return icon and icon._hudSpot or nil end
function HUD.IconSpotSpec(iconKey, kind)
    if not iconKey then return nil end
    local a = HUD.Look().iconAnchors
    local t = type(a) == "table" and a[iconKey]
    return type(t) == "table" and t[kind] or nil
end
-- get / set for one icon's spot of one kind; an emptied spec takes its
-- icon's table and then the whole iconAnchors table with it
function HUD.IconSpotAccess(iconKey, kind, after)
    local function get() return HUD.IconSpotSpec(iconKey, kind) end
    local function set(spec)
        local l = HUD.Look()
        if l == HUD.LOOK_DEFAULTS then return end
        if type(spec) == "table" then
            for k, v in pairs(spec) do if v == "" then spec[k] = nil end end
            if next(spec) == nil then spec = nil end
        else
            spec = nil
        end
        if spec then
            l.iconAnchors = type(l.iconAnchors) == "table" and l.iconAnchors or {}
            l.iconAnchors[iconKey] = type(l.iconAnchors[iconKey]) == "table" and l.iconAnchors[iconKey] or {}
            l.iconAnchors[iconKey][kind] = spec
        elseif type(l.iconAnchors) == "table" and type(l.iconAnchors[iconKey]) == "table" then
            l.iconAnchors[iconKey][kind] = nil
            if next(l.iconAnchors[iconKey]) == nil then l.iconAnchors[iconKey] = nil end
            if next(l.iconAnchors) == nil then l.iconAnchors = nil end
        end
        if after then after() end
    end
    return get, set
end
function HUD.PlaceIconText(fs)
    if not (fs and fs._hudDef) then return end
    iconTexts[fs] = true
    -- the pick hook: a click on a preview's icon text opens its kind
    if ns.TagElement and not fs._zElement then ns.TagElement(fs, "hud." .. HUD.IconTextKind(fs._hudKey)) end
    local kind = HUD.IconTextKind(fs._hudKey)
    local spec = HUD.IconSpotSpec(HUD.IconKey(fs._hudIcon), kind) or HUD.IconTextSpec(kind)
    if spec or fs._hudMoved then
        ns.ApplyAnchor(fs, spec, fs._hudDef, IconTextTo(fs))
        fs._hudMoved = spec ~= nil or nil
    end
end
function HUD.PlaceIconTexts()
    for fs in pairs(iconTexts) do HUD.PlaceIconText(fs) end
    if HUD.PlaceBarTexts then HUD.PlaceBarTexts() end
end

-- THE NUMBERS ON THE BARS (rage, mana, energy; the Drink Ticker's label):
-- the spot each bar's creator gave its text is its default (read once,
-- from a frame of the HUD's own - never a nameplate), and the shared
-- look's anchors.barText (ZacUI's anchor shape) goes on top for every
-- HUD at once. Nothing saved = never touched.
local barTexts = setmetatable({}, { __mode = "k" })
function HUD.BarTextSpec()
    local a = HUD.Look().anchors
    return type(a) == "table" and a.barText or nil
end
function HUD.PlaceBarText(fs)
    if not (fs and fs._hudBarDef and ns.ApplyAnchor) then return end
    local spec = HUD.BarTextSpec()
    if spec or fs._hudBarMoved then
        ns.ApplyAnchor(fs, spec, fs._hudBarDef, fs._hudBarTo)
        fs._hudBarMoved = spec ~= nil or nil
    end
end
function HUD.PlaceBarTexts()
    for fs in pairs(barTexts) do HUD.PlaceBarText(fs) end
end
function HUD.BarText(fs, bar)
    if not fs then return fs end
    local p, rel, rp, x, y = fs:GetPoint(1)
    fs._hudBarDef = { point = p or "CENTER", to = rel or bar, relPoint = rp or p or "CENTER", x = x or 0, y = y or 0,
        justify = fs.GetJustifyH and fs:GetJustifyH() or nil }
    fs._hudBarTo = function(k) if k == "bar" then return bar end end
    barTexts[fs] = true
    if ns.TagElement then ns.TagElement(fs, "hud.barText") end
    HUD.PlaceBarText(fs)
    return fs
end
HUD.BAR_TEXT_DEFAULTS = { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 }

-- A plain FontString carrying the HUD font; the caller owns its colour.
function HUD.Text(parent, size, flags, layer, role)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY", "GameFontNormal")
    HUD.ApplyFont(fs, size, flags, role)
    return fs
end

-- A colour setting ({ r, g, b, a }) or its default, as r, g, b, a.
function HUD.Col(c, d)
    if ns.ColorOf then return ns.ColorOf(c, d) end
    c = type(c) == "table" and c or d or {}
    return c.r or c[1] or 1, c.g or c[2] or 1, c.b or c[3] or 1, c.a or c[4] or 1
end

-- { r, g, b, a } from the old array colours ({ 1, 0.5, 0 [, a] }).
function HUD.RGBA(t)
    return { r = t[1], g = t[2], b = t[3], a = t[4] or 1 }
end

-- Palette read at call time (never cached - live recolour depends on it).
function HUD.Color(key)
    return GetColor("text", key or "normal")
end

-- Shared HUD layouts --------------------------------------------------
-- The Paladin, Priest and data-driven class HUDs lay their rows out with
-- these. A row is laid out again only when the shown icons or the sizes
-- changed since last time (the 0.2s refresh used to re-size and re-place
-- every icon on every tick); `memo` is the caller's own table for that.
local function PlaceIcon(icon, anchor, x, y)
    local Wd = ns.WarriorHUD and ns.WarriorHUD.Widgets
    if Wd and Wd.Place then return Wd.Place(icon, anchor, x, y) end
    icon:ClearAllPoints()
    icon:SetPoint("CENTER", anchor, "CENTER", x, y)
end

-- true when list/params match what memo saw last; remembers them otherwise
local function Same(memo, list, a, b, c)
    local n = #list
    local same = memo.n == n and memo.a == a and memo.b == b and memo.c == c
    if same then
        for i = 1, n do if memo[i] ~= list[i] then same = false break end end
    end
    if not same then
        for i = 1, n do memo[i] = list[i] end
        for i = n + 1, (memo.n or 0) do memo[i] = nil end
        memo.n, memo.a, memo.b, memo.c = n, a, b, c
    end
    return same
end

-- rows: array of { limit, w, h }; overflow repeats the last row.
function HUD.LayoutGrid(memo, list, anchor, rowsCfg, space)
    -- the row sizes are edited in place by the settings page, so they
    -- are compared value by value
    local rs = memo.rows
    if not rs then rs = {} memo.rows = rs end
    local nr, rowsSame = #rowsCfg, rs.n == #rowsCfg
    for i = 1, nr do
        local r, j = rowsCfg[i], (i - 1) * 3
        local l, w, h = r.limit or 0, r.w or 25, r.h or 25
        if rs[j + 1] ~= l or rs[j + 2] ~= w or rs[j + 3] ~= h then
            rowsSame = false
            rs[j + 1], rs[j + 2], rs[j + 3] = l, w, h
        end
    end
    rs.n = nr
    if Same(memo, list, anchor, 0, space) and rowsSame then return end
    local n = #list
    if n == 0 then return end
    local idx, yTop = 1, 0
    local function placeRow(rowCfg)
        local count = math.min(rowCfg.limit, n - idx + 1)
        local w, h = rowCfg.w or 25, rowCfg.h or 25
        local rowW = count * w + (count - 1) * space
        for col = 0, count - 1 do
            local icon = list[idx]
            icon:SetSize(w, h)
            PlaceIcon(icon, anchor, -rowW / 2 + w / 2 + col * (w + space), yTop - h / 2)
            idx = idx + 1
        end
        yTop = yTop - h - space
    end
    for _, rowCfg in ipairs(rowsCfg) do
        if idx > n then break end
        placeRow(rowCfg)
    end
    local last = rowsCfg[#rowsCfg] or { limit = 8, w = 25, h = 25 }
    while idx <= n do placeRow(last) end
end

-- one centred row
function HUD.LayoutRow(memo, list, anchor, w, h, space)
    if Same(memo, list, anchor, w * 10000 + h, space) then return end
    local n = #list
    if n == 0 then return end
    local rowW = n * w + (n - 1) * space
    for i, icon in ipairs(list) do
        icon:SetSize(w, h)
        PlaceIcon(icon, anchor, -rowW / 2 + w / 2 + (i - 1) * (w + space), 0)
    end
end

-- Forget a memo so the next call lays out again (anchor/size changes).
function HUD.ForgetLayout(memo)
    if memo then memo.n = nil end
end

-- The mana bar's OnUpdate (Paladin, Priest, class HUDs): eases toward the
-- current mana and writes the raw number; settled and unchanged frames
-- return after one read.
-- A preview sample hands its own numbers in through self.readMana.
function HUD.ManaBarOnUpdate(self, elapsed)
    local mana, manaMax
    if self.readMana then
        mana, manaMax = self.readMana()
    else
        mana = UnitPower("player", 0) or 0
        manaMax = UnitPowerMax("player", 0) or 1
    end
    -- a hidden value (WoW Forever): the bar and the number take it as it
    -- is, with no maths or smoothing, until it reads again
    if ns.IsSecret and (ns.IsSecret(mana) or ns.IsSecret(manaMax)) then
        if not self._secretPow then
            self._secretPow = true
            self.displayValue, self.lastMana, self.settled = nil, nil, false
        end
        self.bar:SetMinMaxValues(0, ns.IsSecret(manaMax) and (self._plainMax or 1) or manaMax)
        self.bar:SetValue(mana)
        self.text:SetText(mana)
        return
    elseif self._secretPow then
        self._secretPow = nil
        self.bar:SetMinMaxValues(0, 1)
        self.displayValue, self.lastMana, self.settled = nil, nil, false
    end
    self._plainMax = manaMax
    if self.settled and mana == self.lastMana and manaMax == self.lastMax then return end
    self.lastMax = manaMax
    local target = manaMax > 0 and (mana / manaMax) or 0
    local cur = self.displayValue or target
    local diff = target - cur
    if math.abs(diff) < 0.002 then
        cur = target
        self.settled = true
    else
        cur = cur + diff * math.min(1, elapsed * 12)
        self.settled = false
    end
    self.displayValue = cur
    self.bar:SetValue(cur)
    -- the raw mana value on the bar, not a percent
    if mana ~= self.lastMana then
        self.lastMana = mana
        self.text:SetText(tostring(mana))
    end
end

-- Tickers and diagnostics ---------------------------------------------
function HUD.Ticker(interval, fn, name)
    local t = C_Timer.NewTicker(interval, fn)
    if ns.Profiler and ns.Profiler.TrackTicker then ns.Profiler.TrackTicker(t, name or "hud") end
    return t
end

function HUD.Debug(msg)
    local root = Root()
    if root and root.debug then Print("[hud] " .. tostring(msg)) end
end

-- Anchors and movers --------------------------------------------------
-- Every HUD element hangs off an anchor. The anchor a HUD parents its
-- widgets to may be scaled by a setting, so the frame ZacUI's mover
-- registry positions is an UNSCALED holder (the anchor sits at its
-- centre): mover offsets are then plain UIParent units, which is what a
-- dropped proxy reports. Position of record is ZacUIDB.movers[key] (the
-- Movers page, Edit Mode and Reset all work unchanged); the HUD store's
-- migrated { x, y } is the default when nothing has been dragged yet.
local groups = {}   -- key -> { handle, members = { { key, holder } } }

function HUD.MoverPos(key)
    local pos = ZacUIDB and ZacUIDB.movers and ZacUIDB.movers[key]
    if type(pos) == "table" then return pos end
    return nil
end

function HUD.PlaceAnchor(key, holder, store)
    holder:ClearAllPoints()
    local pos = HUD.MoverPos(key)
    if pos then
        holder:SetPoint(pos.point or "CENTER", UIParent, pos.point or "CENTER", pos.x or 0, pos.y or 0)
    else
        holder:SetPoint("CENTER", UIParent, "CENTER", (store and store.x) or 0, (store and store.y) or 0)
    end
end

-- opts: passed on to the registry (reset = the piece's own default spot
-- when it is not simply the store's x / y, secure, ...)
function HUD.RegisterMover(key, label, holder, store, opts)
    if not (RegisterMover and holder) then return end
    -- (2026-11-10) a HUD piece is drawn while Edit Mode is open (the
    -- preview below), so its box is see-through over the real icons
    opts = opts or {}
    if opts.clear == nil then opts.clear = true end
    RegisterMover(key, label, function() return holder end,
        "CENTER", (store and store.x) or 0, (store and store.y) or 0, nil, opts)
end

-- EDIT MODE SHOWS THE REAL HUD (2026-11-10, Zac: "needs to reflect the
-- actual thing"): a HUD says how to switch its "show every element" test
-- on and off, and Edit Mode switches it on for the pass and puts it back.
--   on()      -> true when this HUD is enabled for this character
--   get()     -> its test state now;  set(v)  switch it
local editPreviews = {}
function HUD.EditPreview(on, get, set)
    editPreviews[#editPreviews + 1] = { on = on, get = get, set = set }
end
if ns.WatchEditMode then
    ns.WatchEditMode(function(open)
        for _, p in ipairs(editPreviews) do
            local ok, want = pcall(p.on)
            if open then
                if ok and want then
                    p.was = p.get() and true or false
                    pcall(p.set, true)
                    p.held = true
                end
            elseif p.held then
                p.held = nil
                pcall(p.set, p.was and true or false)
            end
        end
    end)
end

-- CENTER offsets of a holder in UIParent units (holders are unscaled).
local function CenterOffsets(f)
    local cx, cy = f:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if not (cx and ux) then return nil end
    return cx - ux, cy - uy
end

-- A "move all" handle: dragging its proxy shifts every member by the same
-- delta. ZacUI only positions the handle itself, so a 0.3s watch (live
-- only while that proxy is shown) carries the delta to the members.
function HUD.RegisterGroup(key, label, handle, store, members)
    -- (2026-11-10, Zac: "moving the entire warrior hud around even when
    -- my mouse is not moving") the watch below carries any move of this
    -- handle's box to every member, so the box must only move when it is
    -- dragged: it is fitted to the handle itself (exact), never to what is
    -- drawn round it, which changes as the HUD's pieces show and hide
    HUD.RegisterMover(key, label, handle, store, { exact = true, clear = false })
    groups[key] = { handle = handle, members = members }
end

local function ShiftMember(m, dx, dy)
    ZacUIDB.movers = ZacUIDB.movers or {}
    local pos = ZacUIDB.movers[m.key]
    if type(pos) ~= "table" or (pos.point and pos.point ~= "CENTER") then
        local x, y = CenterOffsets(m.holder)
        pos = { point = "CENTER", x = x or 0, y = y or 0 }
        ZacUIDB.movers[m.key] = pos
    end
    pos.x, pos.y = (pos.x or 0) + dx, (pos.y or 0) + dy
    HUD.PlaceAnchor(m.key, m.holder, nil)
end

-- Runs for the life of the session, so it builds nothing: the proxy
-- frame is looked up once per group and remembered, and a group with no
-- proxy yet costs one table read per tick.
local function WatchGroups()
    for key, g in pairs(groups) do
        local proxy = g.proxy
        if not proxy then
            proxy = _G["ZacUIMover_" .. key]
            g.proxy = proxy
        end
        if proxy and proxy:IsShown() then
            local cx, cy = proxy:GetCenter()
            if cx and g.lastX and (cx ~= g.lastX or cy ~= g.lastY) then
                local dx, dy = cx - g.lastX, cy - g.lastY
                for _, m in ipairs(g.members) do ShiftMember(m, dx, dy) end
            end
            g.lastX, g.lastY = cx, cy
        else
            g.lastX, g.lastY = nil, nil
        end
    end
end
do
    local t = C_Timer.NewTicker(0.3, WatchGroups)
    if ns.Profiler and ns.Profiler.TrackTicker then ns.Profiler.TrackTicker(t, "hud.movers") end
end

-- Edit Mode put spots back (undo, Cancel): each group's watch takes the
-- handle's box where it is now, so the pieces it already put back are
-- not carried a second time
function HUD.SyncGroups()
    for key, g in pairs(groups) do
        local proxy = g.proxy or _G["ZacUIMover_" .. key]
        if proxy and proxy:IsShown() then
            g.lastX, g.lastY = proxy:GetCenter()
        else
            g.lastX, g.lastY = nil, nil
        end
    end
end

-- Shows or hides the drag proxies of every registered anchor whose key
-- starts with `prefix` (one HUD's set), so a page button can unlock a
-- whole HUD at once. Toggling again locks them.
function HUD.ToggleMovers(prefix)
    if not (ns.ToggleMover and ns.MOVERS) then return end
    for _, m in ipairs(ns.MOVERS) do
        if string.sub(m.key, 1, #prefix) == prefix then
            ns.ToggleMover(m.key)
        end
    end
end

-- Config pages --------------------------------------------------------
-- Pages live in ZacUI's config window under a "Class HUDs" entry. Each
-- HUD registers its page once, gated to the classes it serves, so a
-- warrior never sees the Priest HUD in the nav.
local GROUP_ID = "classhuds"

local function HudGroup()
    local menu = ns.ConfigMenu
    if not menu then return nil end
    for _, item in ipairs(menu) do
        if item.id == GROUP_ID then return item end
    end
    -- addon: the sidebar's power button turns the whole part off (finish pass)
    local group = { id = GROUP_ID, label = "Class HUDs", children = {}, addon = "Zacui_HUD" }
    -- Right after Combat, with the other things that draw in a fight
    -- (before Quality of life when there is no Combat group).
    local at = #menu + 1
    for i, item in ipairs(menu) do
        if item.id == "combat" then at = i + 1 break end
    end
    if at == #menu + 1 then
        for i, item in ipairs(menu) do
            if item.id == "qol" then at = i break end
        end
    end
    table.insert(menu, at, group)
    return group
end

-- Pages that are not a class's HUD sit with the other combat pages
-- (2026-10-28 settings tidy: Hesitation Alerts is fight feedback for
-- every class, not part of one class's HUD).
local IN_COMBAT_GROUP = { hesitation = true }
local function CombatGroup()
    for _, item in ipairs(ns.ConfigMenu or {}) do
        if item.id == "combat" and item.children then return item end
    end
end

-- classes: nil for every class, or a set { WARRIOR = true, ... }.
function HUD.RegisterPage(id, label, keywords, classes, build)
    if classes then
        local _, cls = UnitClass("player")
        if not classes[cls] then return end
    end
    local group = (IN_COMBAT_GROUP[id] and CombatGroup()) or HudGroup()
    if not group then return end
    for _, child in ipairs(group.children) do
        if child.id == id then return end
    end
    local pageName = "HUD_" .. id
    group.children[#group.children + 1] = {
        id = id, label = label, page = pageName, keywords = keywords or "",
    }
    if RegisterPage then RegisterPage(pageName, build) end
end

-- Layout helpers: one row each, the Readycheck-era AddCheck/AddSlider
-- shape rebuilt on UI.* so every HUD page reads the same.
-- A SPELL NOT LEARNED YET, SHOWN ANYWAY (2026-11-09, Zac: "the option to
-- show all buttons even if not learned yet from either the talent tree or
-- being the correct level"): cfg.showUnlearned on a HUD's store. The icon
-- is drawn grey and dim with no cooldown, so it reads as "not yours yet";
-- off by default, so nothing changes unless it is ticked.
function HUD.Ghost(icon, sp)
    icon:SetIconTexture((sp and sp.icon) or 134400)
    if icon.ClearSwipe then icon:ClearSwipe() end
    if icon.SetDesat then icon:SetDesat(true) end
    if icon.SetIconColor then icon:SetIconColor(1, 1, 1, 0.45) end
    return true
end
HUD.UNLEARNED_LABEL = "Show spells you haven't learned yet"
HUD.UNLEARNED_DESC = "Ticked: an icon that is on for your spec shows even before you have the spell (a talent "
    .. "you haven't taken, or a level you haven't reached), grey and dim until you learn it."

function HUD.Check(L, label, checked, onSet, desc)
    local w = UI.Checkbox(L.current, label, checked and true or false, function(v)
        onSet(v and true or false)
    end)
    L:Row(w, UI.M.ROW)
    if desc then L:Desc(desc) end
    return w
end

function HUD.Slider(L, label, minV, maxV, cur, onChange, opts)
    opts = opts or {}
    local w = UI.Slider(L.current, {
        width = opts.width or 200, min = minV, max = maxV, step = opts.step or 1,
        value = cur, label = label, format = opts.format,
        onChange = function(v)
            if (opts.step or 1) == 1 then v = math.floor(v + 0.5) end
            onChange(v)
        end,
    })
    L:Row(w, UI.M.BLOCK)
    if opts.desc then L:Desc(opts.desc) end
    return w
end

-- items: { { text=, value= }, ... }; selected(): the display text.
function HUD.Dropdown(L, width, items, selected, onSelect, desc)
    local w = UI.Dropdown(L.current, {
        width = width or 200,
        items = function() return items end,
        selected = selected,
        onSelect = onSelect,
    })
    L:Row(w, UI.M.DROPDOWN_H + 8)
    if desc then L:Desc(desc) end
    return w
end

function HUD.Button(L, text, width, onClick, desc)
    local b = UI.Button(L.current, text, { width = width or UI.M.BUTTON_W, onClick = onClick })
    L:Row(b, UI.M.BUTTON_H + 8)
    if desc then L:Desc(desc) end
    return b
end

function HUD.Label(L, text, colorKey)
    local fs = UI.Font(L.current, UI.F.LABEL, { text = text, cat = "text", key = colorKey or "normal" })
    L:Row(fs, 18)
    return fs
end

-- The one switch for the HUDs' motion and polish (sliding rows, fade-in,
-- the ready flash, sheen and bar edges). Shared by every HUD page.
function HUD.MotionCheck(L)
    local root = Root()
    if not root then return end
    return HUD.Check(L, "Smooth motion and polish", root.smooth ~= false, function(v)
        root.smooth = v and true or false
        HUD.ApplyLookAll()
        HUD.RefreshPage()
    end, "Icons slide into place and fade in, a flash when a cooldown is back, "
        .. "a light sheen on icons and bars. Every class HUD and the Drink Ticker. "
        .. "Off is the plain look with no animation.")
end

-- Rebuilds the open config page so a control that changes what the
-- page shows (a tab, an add/remove) re-renders in place.
function HUD.RefreshPage()
    if ns.RefreshConfig then ns.RefreshConfig() end
end

-- Settings follow-through -----------------------------------------------
-- After any ZacUI setting changes (once per frame, however many landed):
-- HUD.serial moves on, so every HUD re-reads its own colours on its next
-- refresh, and when the shared look itself changed, every icon, bar and
-- text the widgets ever made is restyled in place. The comparison is a
-- short string of the shared settings, so a change on another module's
-- page costs one string build and nothing else.
HUD.serial = 0
local lookSig

local function Ser(v, out, depth)
    local t = type(v)
    if t ~= "table" then
        out[#out + 1] = tostring(v)
        return
    end
    if depth > 4 then return end
    out[#out + 1] = "{"
    for k, x in pairs(v) do
        out[#out + 1] = tostring(k)
        out[#out + 1] = "="
        Ser(x, out, depth + 1)
        out[#out + 1] = ","
    end
    out[#out + 1] = "}"
end

local function LookSig()
    local out = {}
    -- (reading the look to compare it must not be what first saves it)
    local root = Root()
    local saved = root and type(root.look) == "table"
    Ser(saved and HUD.Look() or HUD.LOOK_DEFAULTS, out, 0)
    out[#out + 1] = HUD.Smooth() and "s1" or "s0"
    out[#out + 1] = tostring(ZacUIDB and ZacUIDB.font and ZacUIDB.font.name)
    out[#out + 1] = tostring(ns.Media and ns.Media.BarName and ns.Media.BarName())
    return table.concat(out)
end

function HUD.ApplyLookAll()
    lookSig = LookSig()
    local W = ns.WarriorHUD and ns.WarriorHUD.Widgets
    if W and W.ApplyLookAll then W.ApplyLookAll() end
    HUD.RestyleFonts()
    HUD.PlaceIconTexts()
end

-- Restyle now if the shared look moved since the last restyle (a preview's
-- update calls this so its sample is right in the same frame).
function HUD.CheckLook()
    if LookSig() ~= lookSig then HUD.ApplyLookAll() end
end

-- The serial moves at once (a preview updating later in this frame then
-- reads fresh colours); the restyle waits for the next frame, once.
local CheckLookSoon = ns.Coalesce and ns.Coalesce(function() HUD.CheckLook() end)
if ns.OnSettingsChanged and CheckLookSoon then
    ns.OnSettingsChanged(function()
        HUD.serial = HUD.serial + 1
        CheckLookSoon()
    end)
end

-- Shared page sections ------------------------------------------------
-- Every HUD page carries the same Look / Text / Animation cards for the
-- shared look, so whichever HUD page a player opens, everything that
-- shapes their HUD is on it.
local function SetLook(key, v)
    local look = HUD.Look()
    look[key] = v
end

local function AddColor(L, label, key, alpha, desc)
    local d = HUD.LOOK_DEFAULTS[key]
    local w = UI.ColorPicker(L.current, {
        label = label, alpha = alpha,
        get = function() return HUD.Col(HUD.Look()[key], d) end,
        set = function(r, g, b, a)
            SetLook(key, { r = r, g = g, b = b, a = a or (d and d.a) or 1 })
            HUD.ApplyLookAll()
        end,
    })
    L:Add(w, 4)
    if desc then L:Desc(desc) end
    return w
end

local function Pct(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end

local function LookSlider(L, label, key, minV, maxV, step, fmt, desc)
    local look = HUD.Look()
    local w = UI.Slider(L.current, {
        width = 240, min = minV, max = maxV, step = step,
        value = tonumber(look[key]) or HUD.LOOK_DEFAULTS[key], label = label,
        format = fmt,
        onChange = function(v)
            if step >= 1 then v = math.floor(v + 0.5) else v = math.floor(v / step + 0.5) * step end
            SetLook(key, v)
            HUD.ApplyLookAll()
        end,
    })
    L:Row(w, UI.M.BLOCK)
    if desc then L:Desc(desc) end
    return w
end

-- opts.ownBorder: this HUD keeps its own icon border thickness (the
-- Warrior HUD), so the shared one is not offered here
function HUD.SharedLookCards(L, opts)
    opts = opts or {}
    L:Card("Every HUD: bars")
    L:Desc("Shared by every class HUD, the Drink Ticker and Hesitation's nameplate row.")
    local tex = UI.TexturePicker(L.current, {
        label = "Bar texture", width = 240,
        get = function() return HUD.Look().barTexture end,
        set = function(name) SetLook("barTexture", name) HUD.ApplyLookAll() end,
        color = function() return 0, 0.44, 0.87 end,
    })
    L:Add(tex, 6)
    AddColor(L, "Bar background", "barBg", true)
    AddColor(L, "Bar border", "barBorder", true)
    LookSlider(L, "Bar border thickness", "barBorderSize", 0, 4, 1, function(v) return v .. " px" end)
    L:EndCard()

    L:Card("Every HUD: icons")
    AddColor(L, "Icon background", "iconBg", true)
    AddColor(L, "Icon border", "iconBorder", true)
    if not opts.ownBorder then
        LookSlider(L, "Icon border thickness", "iconBorderSize", 0, 4, 1, function(v) return v .. " px" end)
    end
    AddColor(L, "Cooldown swipe", "swipe", true, "The dark sweep over an icon while it is on cooldown.")
    LookSlider(L, "Icon crop", "zoom", 0, 0.4, 0.01, Pct,
        "How much of a spell icon's edge is trimmed away. A little hides the dark rim baked into the art.")
    LookSlider(L, "Greyed-out icons darker by", "desatDim", 0, 0.8, 0.01, Pct,
        "An icon on cooldown or without the power for it is greyed out and dimmed this much.")
    L:EndCard()

    L:Card("Every HUD: polish")
    if not HUD.Smooth() then
        L:Desc("Smooth motion and polish is off (Animation tab), so none of these show.")
    end
    LookSlider(L, "Icon sheen", "iconSheen", 0, 0.5, 0.01, Pct, "A light gloss over the top half of every icon.")
    LookSlider(L, "Bar sheen", "barSheen", 0, 0.5, 0.01, Pct, "The same gloss on a bar's fill.")
    LookSlider(L, "Glowing bar edge", "barEdge", 0, 1, 0.05, Pct,
        "A soft light at the leading edge of a filling bar. 0% turns it off.")
    AddColor(L, "Cooldown ready flash", "flash", true,
        "The flash over an icon when its cooldown comes back. Its strength is the alpha.")
    L:EndCard()
end

-- The HUD text font, and (alert) the big alert / reminder texts.
-- alert = { label, getSize = fn() -> px, setSize = fn(px), defaultSize }
function HUD.SharedTextCards(L, alert, opts)
    L:Card("HUD text")
    L:Desc("Cooldown timers, counts and bar values on every class HUD, the Drink Ticker and "
        .. "Hesitation's icons. The size is a cooldown timer's; every other text keeps its size next to it.")
    local fp = UI.FontPicker(L.current, {
        label = "HUD text", width = 400,
        get = function() return HUD.Look().font end,
        set = function(spec) SetLook("font", spec) HUD.ApplyLookAll() end,
        defaults = { size = TEXT_REF, outline = "outline", shadow = true },
        minSize = 6, maxSize = 32, sample = "12  3  1:24",
    })
    L:Add(fp, 6)
    L:EndCard()

    -- where each kind of icon text sits, on every HUD's icons
    -- (ZacUIDB.hud.look.anchors.<kind>; nothing saved = where each icon
    -- has always put it)
    L:Card("Where the icon texts sit")
    ZacUIDB.config = ZacUIDB.config or {}
    local function Kind()
        local v = ZacUIDB.config.hudTextKind
        return HUD.ICON_TEXT_LABELS[v] and v or "p"
    end
    local kind = Kind()
    local kdd = UI.Field(L.current, "Text", function(h)
        return UI.Dropdown(h, { width = 200,
            items = function()
                local out = {}
                for _, k in ipairs(HUD.ICON_TEXTS) do out[#out + 1] = { text = HUD.ICON_TEXT_LABELS[k], value = k } end
                return out
            end,
            selected = function() return HUD.ICON_TEXT_LABELS[Kind()] end,
            selectedValue = Kind,
            onSelect = function(v) ZacUIDB.config.hudTextKind = v if ns.RefreshConfig then ns.RefreshConfig() end end })
    end, { width = 200 })
    L:Add(kdd, 8)
    L:Desc(HUD.ICON_TEXT_TIPS[kind])
    -- which icon: every icon (the shared spot) or one of this HUD's own
    -- (opts.icons, { key, label }; iconAnchors.<icon>.<kind>)
    local icons = opts and opts.icons
    local iconKey, iconLabel
    if icons and #icons > 0 then
        local function IconSel()
            local v = ZacUIDB.config.hudTextIcon
            for _, ic in ipairs(icons) do if ic.key == v then return v, ic.label end end
            return nil, "Every icon"
        end
        iconKey, iconLabel = IconSel()
        local idd = UI.Field(L.current, "Icon", function(h)
            return UI.Dropdown(h, { width = 200,
                items = function()
                    local out = { { text = "Every icon", value = "*" } }
                    for _, ic in ipairs(icons) do out[#out + 1] = { text = ic.label, value = ic.key } end
                    return out
                end,
                selected = function() local _, lb = IconSel() return lb end,
                selectedValue = function() return IconSel() or "*" end,
                onSelect = function(v)
                    ZacUIDB.config.hudTextIcon = (v ~= "*") and v or nil
                    if ns.RefreshConfig then ns.RefreshConfig() end
                end })
        end, { width = 200 })
        L:Add(idd, 8)
    end
    local targets = { { value = "icon", text = "The icon" } }
    for _, k in ipairs(HUD.ICON_TEXTS) do
        if k ~= kind then targets[#targets + 1] = { value = k, text = HUD.ICON_TEXT_LABELS[k] } end
    end
    -- (never written into the defaults table itself before the save exists)
    local function Owner() local l = HUD.Look() if l ~= HUD.LOOK_DEFAULTS then return l end end
    local get, set
    if iconKey then
        get, set = HUD.IconSpotAccess(iconKey, kind, HUD.ApplyLookAll)
    else
        get, set = ns.CustomAccess(Owner, "anchors", kind, HUD.ApplyLookAll)
    end
    UI.TextElement(L, { key = "hud." .. kind, anchorGet = get, anchorSet = set,
        anchorDefaults = function() return HUD.ICON_TEXT_DEFAULTS[kind] end, targets = targets,
        defaultTargetLabel = "The icon", anchorMin = -60, anchorMax = 60 })
    if iconKey then
        L:Desc("Only on " .. iconLabel .. ". Reset puts it back on the spot every icon shares.")
    else
        L:Desc("For every HUD. Reset puts it back where each icon puts it.")
    end
    L:EndCard()

    -- the numbers on the bars (anchors.barText; nothing saved = where each
    -- bar puts its number)
    L:Card("Where the bar numbers sit")
    local bget, bset = ns.CustomAccess(Owner, "anchors", "barText", HUD.ApplyLookAll)
    UI.TextElement(L, { key = "hud.barText", anchorGet = bget, anchorSet = bset,
        anchorDefaults = function() return HUD.BAR_TEXT_DEFAULTS end, targets = { { value = "bar", text = "The bar" } },
        defaultTargetLabel = "The bar", anchorMin = -60, anchorMax = 60 })
    L:Desc("Rage, mana and energy on every HUD, and the Drink Ticker's label.")
    L:EndCard()
    if alert then
        L:Card(alert.label or "Alert text")
        L:Desc(alert.desc or "The big reminder texts. The face, outline and shadow are shared by every HUD's alert text.")
        local ap = UI.FontPicker(L.current, {
            label = alert.label or "Alert text", width = 400,
            get = function()
                local s = ns.CopySetting and ns.CopySetting(HUD.Look().alertFont) or {}
                s.size = alert.getSize and alert.getSize() or nil
                return s
            end,
            set = function(spec)
                if alert.setSize and spec.size then alert.setSize(spec.size) end
                local keep = {}
                for k, v in pairs(spec) do if k ~= "size" then keep[k] = v end end
                SetLook("alertFont", keep)
                HUD.ApplyLookAll()
            end,
            defaults = { size = alert.defaultSize or 20, outline = alert.outline or "outline", shadow = true },
            minSize = alert.minSize or 10, maxSize = alert.maxSize or 40, sample = alert.sample or "Blessing",
        })
        L:Add(ap, 6)
        L:EndCard()
    end
end

local function MotionPicker(L, label, key, styles, desc)
    local p = UI.AnimationPicker(L.current, {
        label = label, styles = styles,
        get = function() return HUD.Motion()[key] end,
        set = function(spec) HUD.Motion()[key] = spec end,
    })
    L:Add(p, 4)
    if desc then L:Desc(desc) end
    UI.SetEnabled(p, HUD.Smooth(), 'Needs "Smooth motion and polish" turned on.')
    return p
end

-- The styles that make sense for something going away (a repeat only
-- applies while a thing stays on screen).
HUD.EXIT_STYLES = { "none", "fade", "slide", "pop", "bounce" }

function HUD.SharedAnimCards(L)
    local on = HUD.Smooth()
    L:Card("Motion")
    L:Desc("Shared by every class HUD, the Drink Ticker and Hesitation's nameplate row. ZacUI's "
        .. "own Play animations switch and speed (Appearance > Motion) apply on top.")
    HUD.MotionCheck(L)
    L:EndCard()
    L:Card("Icons in the HUD rows")
    MotionPicker(L, "When an icon appears", "appear", nil,
        "An icon joining a row: a buff going up, a cooldown that shows when it is usable.")
    MotionPicker(L, "When an icon goes", "disappear", HUD.EXIT_STYLES,
        "None is how it has always been: gone at once.")
    -- the row sliding along: on/off, how long, on what curve (a direction
    -- or a distance would mean nothing here: the icons go where the row puts them)
    local g = HUD.Motion().glide or {}
    local cb = UI.Checkbox(L.current, "Slide icons into their new place", g.style ~= "none", function(v)
        local cur = ns.CopySetting and ns.CopySetting(HUD.Motion().glide or {}) or {}
        cur.style = v and "slide" or "none"
        HUD.Motion().glide = cur
        HUD.RefreshPage()
    end)
    L:Row(cb, UI.M.ROW)
    L:Desc("When an icon joins or leaves a row, the others slide over instead of jumping.")
    local function SetGlide(field, v)
        local cur = ns.CopySetting and ns.CopySetting(HUD.Motion().glide or {}) or {}
        cur[field] = v
        HUD.Motion().glide = cur
    end
    local sl = UI.Slider(L.current, { width = 240, label = "Slide time", min = 0.05, max = 1, step = 0.05,
        value = tonumber(g.duration) or 0.3, format = function(v) return string.format("%.2fs", v) end,
        onChange = function(v) SetGlide("duration", math.floor(v * 100 + 0.5) / 100) end })
    L:Row(sl, UI.M.BLOCK)
    local easeLabel = {}
    local items = {}
    for _, e in ipairs((ns.Motion and ns.Motion.EASINGS) or {}) do
        easeLabel[e.id] = e.label
        items[#items + 1] = { text = e.label, value = e.id }
    end
    local dd = UI.Field(L.current, "Easing", function(host)
        return UI.Dropdown(host, { width = 160, items = function() return items end,
            selected = function() return easeLabel[(HUD.Motion().glide or {}).easing or "easeOutCubic"] or "Quick start" end,
            selectedValue = function() return (HUD.Motion().glide or {}).easing or "easeOutCubic" end,
            onSelect = function(v) SetGlide("easing", v) end })
    end, { width = 160 })
    L:Add(dd, 6)
    local WHY_SMOOTH = 'Needs "Smooth motion and polish" turned on.'
    UI.SetEnabled(cb, on, WHY_SMOOTH)
    UI.SetEnabled(sl, on and g.style ~= "none", on and 'Needs "Slide icons into their new place" turned on.' or WHY_SMOOTH)
    UI.SetEnabled(dd, on and g.style ~= "none", on and 'Needs "Slide icons into their new place" turned on.' or WHY_SMOOTH)
    L:EndCard()
    L:Card("Cooldown ready")
    MotionPicker(L, "Ready flash", "ready", { "none", "fade", "pop" },
        "Played on the flash over an icon whose cooldown just came back (its colour is on the Look tab).")
    L:EndCard()
end

-- Page layout helpers shared by the HUD pages ------------------------
local SLIDER_W, COL2_X = 200, 290

-- Card width at build time. The card is anchored to both sides of the
-- content pane so its own width is not resolved yet, but the pane's is.
function HUD.CardW(L)
    local w = L.parent and L.parent.GetWidth and L.parent:GetWidth()
    if not w or w < 200 then return 534 end
    return w - 2 * UI.M.MARGIN
end

-- A checkbox row; indent shifts it right of the usual control column.
function HUD.CheckIndent(L, label, checked, onSet, indent, desc)
    if not indent then return HUD.Check(L, label, checked, onSet, desc) end
    local w = UI.Checkbox(L.current, label, checked and true or false, function(v) onSet(v and true or false) end)
    L:Row(w, UI.M.ROW, UI.M.CONTROL_X + indent)
    if desc then L:Desc(desc) end
    return w
end

-- Two sliders side by side. Each spec is { label, min, max, cur,
-- onChange, format, step }; right may be nil.
function HUD.SliderPair(L, left, right)
    local card = L.current
    local twoCols = HUD.CardW(L) >= COL2_X + SLIDER_W + 10
    local made = {}
    local function make(x, spec)
        local step = spec[7] or 1
        local w = UI.Slider(card, {
            width = SLIDER_W, min = spec[2], max = spec[3], step = step, value = spec[4], label = spec[1],
            format = spec[6],
            onChange = function(v)
                if step >= 1 then v = math.floor(v + 0.5) else v = math.floor(v / step + 0.5) * step end
                spec[5](v)
            end,
        })
        w:SetPoint("TOPLEFT", card, "TOPLEFT", x, card._y)
        made[#made + 1] = w
        -- (a row as tall as its slider: a bigger font makes it taller)
        return math.max(UI.M.BLOCK, (w:GetHeight() or 0) + 8)
    end
    local h = make(UI.M.CONTROL_X, left)
    if right then
        if not twoCols then card._y = card._y - h h = 0 end
        h = math.max(h, make(twoCols and COL2_X or UI.M.CONTROL_X, right))
    end
    card._y = card._y - h
    return made[1], made[2]
end

-- Two-column checkbox grid, filled column by column (first half left).
-- label(def) names a row, checked(def) reads it, onSet(def, v) writes it.
function HUD.CheckGrid(L, list, label, checked, onSet)
    local card = L.current
    local half = math.ceil(#list / 2)
    local colW = math.floor((HUD.CardW(L) - UI.M.CONTROL_X - 8) / 2)
    local top = card._y
    for i, def in ipairs(list) do
        local col = (i > half) and 1 or 0
        local rowY = top - ((i - 1) % half) * UI.M.ROW
        local cb = UI.Checkbox(card, label(def), checked(def) and true or false, function(v)
            onSet(def, v and true or false)
        end)
        cb:SetPoint("TOPLEFT", card, "TOPLEFT", UI.M.CONTROL_X + col * colW, rowY)
    end
    card._y = top - half * UI.M.ROW - 8
end

-- The potion dropdown's entries (the Warrior HUD's list, shared).
function HUD.PotionLabel(idx)
    local WH = ns.WarriorHUD
    if not idx or idx == 1 then return "Automatic" end
    local e = WH and WH.POTION_DROPDOWN and WH.POTION_DROPDOWN[idx]
    return e and e.label or "Automatic"
end

function HUD.PotionItems()
    local WH = ns.WarriorHUD
    local items = { { text = "Automatic", value = 1 } }
    if WH and WH.POTION_DROPDOWN then
        for idx = 2, 20 do
            local e = WH.POTION_DROPDOWN[idx]
            if e then items[#items + 1] = { text = e.label, value = idx } end
        end
    end
    return items
end

-- The Unlock button every HUD page carries on its Position tab.
function HUD.UnlockButton(L, prefix, label)
    return HUD.Button(L, label or "Unlock / lock HUD anchors", 170, function() HUD.ToggleMovers(prefix) end,
        "Also on ZacUI's Movers page and in Edit Mode. The 'move all' handle drags the whole HUD at once.")
end

-- A percentage scale slider over a store field (1 = 100%).
function HUD.ScaleSlider(L, label, tbl, key, onChange)
    return HUD.Slider(L, label, 50, 200, math.floor((tbl[key] or 1) * 100 + 0.5), function(v)
        tbl[key] = v / 100
        if onChange then onChange() end
    end, { width = 240, format = function(v) return v .. "%" end })
end

-- Colour pickers two to a row. entries: { { label, get = fn() -> r,g,b,a
-- (or the colour table), set = fn(r,g,b,a), alpha }, ... }
function HUD.ColorGrid(L, entries)
    local card = L.current
    local w = card and card.GetWidth and card:GetWidth()
    if not w or w < 200 then
        w = (L.parent and L.parent.GetWidth and L.parent:GetWidth() or 0) - 2 * UI.M.MARGIN
    end
    if not w or w < 200 then w = 534 end
    local colW = 245
    local twoCols = w >= UI.M.CONTROL_X + 2 * colW
    local i = 1
    while i <= #entries do
        local rowH = 0
        for col = 0, (twoCols and 1 or 0) do
            local e = entries[i]
            if e then
                local p = UI.ColorPicker(card, { label = e[1] or e.label, alpha = e.alpha ~= false,
                    get = e.get, set = e.set, width = colW - 15 })
                p:SetPoint("TOPLEFT", card, "TOPLEFT", UI.M.CONTROL_X + col * colW, card._y)
                rowH = math.max(rowH, p:GetHeight() or 20)
                i = i + 1
            end
        end
        card._y = card._y - rowH - 6
    end
end

-- Search words every HUD page answers to, on top of its own.
HUD.PAGE_KEYWORDS = "look colour color texture bar texture font text size outline shadow border "
    .. "background swipe crop zoom sheen gloss glow edge flash ready animation motion fade slide "
    .. "appear preview test scale position unlock move reset"

-- Puts the shared look and motion back to the defaults (every HUD).
function HUD.ResetLookButton(L)
    return HUD.Button(L, "Reset the shared look", 170, function()
        local root = Root()
        if root then root.look, root.motion = nil, nil end
        HUD.ApplyLookAll()
        ns.SettingsChanged("reset")
        HUD.RefreshPage()
    end, "Bar texture, borders, sheen, HUD text and the HUD animations back to the defaults, for every HUD.")
end

-- Preview helpers -----------------------------------------------------
-- Every HUD sample hangs off one stage on its canvas. The stage is what
-- HUD.FitSample scales and slides, so the whole sample sits inside the
-- canvas however far apart the pieces sit on screen.
function HUD.SampleStage(canvas)
    local st = canvas._zStage
    if not st then
        st = CreateFrame("Frame", nil, canvas)
        st:SetPoint("CENTER", canvas, "CENTER", 0, 0)
        st:SetSize(math.max(1, canvas:GetWidth() or 1), math.max(1, canvas:GetHeight() or 1))
        canvas._zStage = st
    end
    return st
end

-- A plain anchor on a preview canvas, standing in for a HUD's holder +
-- anchor pair: same role, no name, no mover, no events.
function HUD.SampleAnchor(canvas, w, h)
    local stage = HUD.SampleStage(canvas)
    local f = CreateFrame("Frame", nil, stage)
    f:SetSize(w or 26, h or 26)
    f:SetPoint("CENTER", stage, "CENTER", 0, 0)
    return f
end

-- Puts a sample anchor's CENTER at (x, y) from the canvas centre, in
-- canvas units whatever the anchor's own scale. (On the stage: x and y
-- are stage units, and FitSample sizes the stage to the canvas.)
function HUD.PlaceSample(f, canvas, x, y)
    local s = f:GetScale() or 1
    if s <= 0 then s = 1 end
    local rel = canvas
    if canvas._zStage and f:GetParent() == canvas._zStage then rel = canvas._zStage end
    f:ClearAllPoints()
    f:SetPoint("CENTER", rel, "CENTER", x / s, y / s)
end

-- The HUD's pieces put themselves in the MEDIUM (or HIGH) strata so they
-- sit right on screen. On a preview canvas that strata is below the
-- settings window's, so they would draw behind the dock's own background
-- and the preview would look empty: every frame on the canvas is put in
-- the canvas's strata instead.
local function AdoptStrata(root, strata, depth)
    if depth > 30 then return end
    local kids = { root:GetChildren() }
    for i = 1, #kids do
        local k = kids[i]
        if k.GetFrameStrata and k:GetFrameStrata() ~= strata then k:SetFrameStrata(strata) end
        AdoptStrata(k, strata, depth + 1)
    end
end

-- The box everything visible on the stage covers, in stage units from the
-- stage's centre (independent of the stage's own scale and offset).
local function StageBox(stage)
    local ses = stage:GetEffectiveScale() or 1
    local scx, scy = stage:GetCenter()
    if not (scx and ses > 0) then return nil end
    scx, scy = scx * ses, scy * ses
    local minX, maxX, minY, maxY
    local function visit(f, depth)
        if depth > 30 then return end
        local kids = { f:GetChildren() }
        for i = 1, #kids do
            local k = kids[i]
            if k:IsShown() then
                local w, h = k:GetWidth() or 0, k:GetHeight() or 0
                local l, b = k:GetLeft(), k:GetBottom()
                -- (alpha is not asked: an icon about to fade in counts)
                if w > 1 and h > 1 and l and b then
                    local es = k:GetEffectiveScale() or 1
                    local x0, y0 = (l * es - scx) / ses, (b * es - scy) / ses
                    local x1, y1 = x0 + w * es / ses, y0 + h * es / ses
                    minX = minX and math.min(minX, x0) or x0
                    maxX = maxX and math.max(maxX, x1) or x1
                    minY = minY and math.min(minY, y0) or y0
                    maxY = maxY and math.max(maxY, y1) or y1
                end
                visit(k, depth + 1)
            end
        end
    end
    visit(stage, 0)
    if not minX then return nil end
    return (minX + maxX) / 2, (minY + maxY) / 2, maxX - minX, maxY - minY
end
HUD.SampleBox = StageBox

-- Where an element's holder sits on screen: its CENTER offset from
-- UIParent's centre, in UIParent units, from the dragged position of
-- record (any anchor point) or else the store's default. w, h: the
-- holder's size (a mover saved at a corner names the holder's corner).
local POINT_FX = { LEFT = 0, TOPLEFT = 0, BOTTOMLEFT = 0, RIGHT = 1, TOPRIGHT = 1, BOTTOMRIGHT = 1 }
local POINT_FY = { BOTTOM = 0, BOTTOMLEFT = 0, BOTTOMRIGHT = 0, TOP = 1, TOPLEFT = 1, TOPRIGHT = 1 }
function HUD.ScreenPos(moverKey, store, w, h)
    local pos = moverKey and HUD.MoverPos(moverKey)
    if pos then
        local p = pos.point or "CENTER"
        local fx, fy = POINT_FX[p] or 0.5, POINT_FY[p] or 0.5
        local uw, uh = UIParent:GetWidth() or 0, UIParent:GetHeight() or 0
        return (fx - 0.5) * (uw - (w or 0)) + (pos.x or 0), (fy - 0.5) * (uh - (h or 0)) + (pos.y or 0)
    end
    return (store and store.x) or 0, (store and store.y) or 0
end

-- A HUD sample laid out exactly as the HUD sits on screen: each piece
-- { a = sample anchor, mover = its mover key, store = its position store,
-- scale =, on = (shown at all) } goes where its live holder is, relative
-- to the others (HUD.FitSample then centres the lot and makes the canvas
-- its box; the preview strip shows it at its real size).
function HUD.RealSample(canvas, pieces)
    for _, p in ipairs(pieces) do
        local s = p.scale or 1
        if s <= 0 then s = 1 end
        p.a:SetScale(s)
        p.a:SetShown(p.on and true or false)
        if p.on then
            local x, y = HUD.ScreenPos(p.mover, p.store, p.a:GetWidth(), p.a:GetHeight())
            HUD.PlaceSample(p.a, canvas, x, y)
        end
    end
end

-- A HUD sample's pieces, wide and short for the preview strip: each piece
-- { a = anchor, h = its height, scale =, edgeTop = (the anchor is its top
-- edge), off = (from its top to the anchor, unscaled) } in order, stacked
-- in columns no taller than maxH, the columns side by side (each piece
-- centred in its column on what it draws). A piece the game has not laid
-- out yet counts as 200 wide, and the stack is done again next frame.
function HUD.StackSample(canvas, pieces, maxH)
    local GAP_Y, GAP_X = 6, 16
    maxH = maxH or 96
    local cols, col, missing = {}, nil, false
    for _, p in ipairs(pieces) do
        local s = p.scale or 1
        if s <= 0 then s = 1 end
        p.a:SetScale(s)
        local hh = p.h * s
        local cx, _, w = StageBox(p.a)
        if not cx then
            -- nothing shown on it (an empty row) or not laid out yet
            missing, cx, w = true, 0, p.w or 200
            if not p.a:IsShown() then w = 0 end
        end
        p._cx, p._w, p._h = cx * s, w * s, hh
        if not col or (#col > 0 and col.h + GAP_Y + hh > maxH) then
            col = { h = 0, w = 0 }
            cols[#cols + 1] = col
        end
        col[#col + 1] = p
        col.h = col.h + (#col > 1 and GAP_Y or 0) + hh
        col.w = math.max(col.w, p._w)
    end
    local total = -GAP_X
    for _, c in ipairs(cols) do total = total + c.w + GAP_X end
    local x = -total / 2
    for _, c in ipairs(cols) do
        local top = c.h / 2
        for _, p in ipairs(c) do
            local off = p.off and p.off * (p.scale or 1) or (p.edgeTop and 0 or p._h / 2)
            HUD.PlaceSample(p.a, canvas, x + c.w / 2 - p._cx, top - off)
            top = top - p._h - GAP_Y
        end
        x = x + c.w + GAP_X
    end
    -- (a few times at most: a piece that draws nothing never measures)
    if not missing then
        canvas._zStackTries = nil
    elseif not canvas._zStackAgain and (canvas._zStackTries or 0) < 3 then
        canvas._zStackAgain = true
        canvas._zStackTries = (canvas._zStackTries or 0) + 1
        C_Timer.After(0, function()
            canvas._zStackAgain = nil
            if canvas:IsVisible() then
                HUD.StackSample(canvas, pieces, maxH)
                HUD.FitSample(canvas, nil, canvas._zFitP, canvas._zFitNatural)
            end
        end)
    end
end

-- Makes a preview sample fit its canvas: the pieces in the canvas's
-- strata, then the stage shrunk (never grown) and slid so the box of
-- everything visible sits centred inside the canvas with a margin.
-- `box` (optional) is the box to use when the game cannot measure yet.
-- With P (the preview strip's), the canvas is first made that box plus
-- the margin (P.Resize), so the sample shows at its real size and the
-- strip scales it; natural(canvas, P), when given and it answers, is the
-- size to make the canvas instead (a sample at 100%, so its own scale
-- setting still shows: smaller, or held to fit).
local FIT_PAD = 8
function HUD.FitSample(canvas, box, P, natural)
    if not canvas then return end
    if P then canvas._zFitP, canvas._zFitNatural = P, natural end
    local strata = canvas:GetFrameStrata()
    if strata then AdoptStrata(canvas, strata, 0) end
    local stage = canvas._zStage
    if not stage then return end
    local cw, ch = canvas:GetWidth() or 0, canvas:GetHeight() or 0
    if cw < 4 or ch < 4 then return end
    stage:SetSize(cw, ch)
    local cx, cy, w, h = StageBox(stage)
    if not cx then
        if box then cx, cy, w, h = box() end
        if not cx then
            -- nothing measurable yet (the game lays frames out lazily): once more next frame
            if not canvas._zFitAgain then
                canvas._zFitAgain = true
                C_Timer.After(0, function()
                    canvas._zFitAgain = nil
                    if canvas:IsVisible() and StageBox(stage) then HUD.FitSample(canvas, nil, P, natural) end
                end)
            end
            return
        end
    end
    if P and P.Resize then
        local nw, nh
        if natural then nw, nh = natural(canvas, P) end
        P.Resize((nw or w) + 2 * FIT_PAD, (nh or h) + 2 * FIT_PAD)
        cw, ch = canvas:GetWidth() or cw, canvas:GetHeight() or ch
        stage:SetSize(cw, ch)
    end
    local k = math.min(1, (cw - 2 * FIT_PAD) / math.max(1, w), (ch - 2 * FIT_PAD) / math.max(1, h))
    k = math.max(0.1, k)
    stage:SetScale(k)
    stage:ClearAllPoints()
    stage:SetPoint("CENTER", canvas, "CENTER", -cx, -cy)
    canvas._zFit = k
end

-- A HUD page's L:Preview spec with the fitting added after every update:
-- the canvas becomes the sample's box (the preview strip scales it).
-- `box` as for FitSample; natural(canvas, P) as for FitSample.
function HUD.FitSpec(spec, box, natural)
    -- an icon text picked in the sample: its kind in "Where the icon texts
    -- sit", on the Text tab
    if ns.CustomPick and spec.key then
        ns.CustomPick.SetHandler(spec.key, function(el)
            local k = type(el) == "string" and el:match("^hud%.(.+)$")
            -- (the Hesitation alert's own pieces: its texts on Text, its icon on Position)
            local alertPart = k == "alertText" or k == "alertTime" or k == "alertIcon"
            if not (k and ((HUD.ICON_TEXT_LABELS and HUD.ICON_TEXT_LABELS[k]) or k == "barText" or alertPart)) then return end
            ZacUIDB.config = ZacUIDB.config or {}
            if k ~= "barText" and not alertPart then
                ZacUIDB.config.hudTextKind = k
                -- clicked on a sample (ElementAt found it): that icon's own
                -- spot when it names itself, else every icon's
                local r = ns.CustomPick.lastRegion
                if r and r._zElement == el and r._hudIcon then
                    ZacUIDB.config.hudTextIcon = HUD.IconKey(r._hudIcon)
                end
            end
            local st = ns.ConfigState and ns.ConfigState()
            if st and st.selected then
                st.tabs = st.tabs or {}
                st.tabs[st.selected] = (k == "alertIcon") and "pos" or "text"
            end
            if ns.RefreshConfig then ns.RefreshConfig() end
        end)
    end
    local update = spec.update
    spec.update = function(canvas, P)
        if update then update(canvas, P) end
        HUD.FitSample(canvas, box and function() return box(canvas, P) end or nil, P, natural)
    end
    return spec
end

-- The replay of a HUD preview: every shown icon under the given roots
-- plays its entrance, and one cooldown shows the ready flash.
function HUD.ReplayIcons(lists, flashOne)
    local Motion = ns.Motion
    local spec = HUD.Motion().appear
    local flashed = false
    for _, list in ipairs(lists) do
        for _, icon in pairs(list) do
            if type(icon) == "table" and icon.IsShown and icon:IsShown() then
                if Motion and HUD.Smooth() then
                    Motion.Stop(icon)
                    Motion.Play(icon, spec, "in")
                end
                if flashOne and not flashed and icon.Flash then
                    flashed = true
                    icon:Flash(true)
                end
            end
        end
    end
end

-- Cross-addon reads --------------------------------------------------
-- The Warrior HUD can follow a Readycheck smart macro. Readycheck is a
-- soft dependency here: present, its macros are listed; absent, the
-- binding editor simply does not appear.
function HUD.SmartMacro()
    local RC = _G.Readycheck
    return RC and RC.SmartMacro or nil
end
