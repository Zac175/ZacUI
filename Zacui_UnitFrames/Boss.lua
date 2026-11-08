-- ============================================================================
-- Zacui_UnitFrames - Boss.lua
-- Boss frames: boss1 to boss5 in a column, where the game hands boss units
-- to addons (TBC, Forever, Retail; Classic Era has none, so on Era nothing
-- here runs and no setting is added). One settings table for the five
-- (ns.db.frames.boss: everything a single frame has, plus the gap between
-- them and which way they grow), one insecure holder that owns the place
-- (the page's X / Y, Edit Mode, a drag in move mode) with the five secure
-- buttons hung from it. Each button shows with its unit (the unit watch);
-- an encounter starting repaints them (INSTANCE_ENCOUNTER_ENGAGE_UNIT).
-- Off by default for everybody: the setup offers them.
-- Part of Zacui_UnitFrames; load order is set by the TOC (after Extras).
-- ============================================================================
local ADDON, ns = ...

local COUNT = 5
local KEY = "boss"

local function Available()
    return ns.UFFeatureOn("uf_boss") and ns.ClientEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT") and ns.ClientUnit("boss1")
end

local function Cfg() return ns.db and ns.db.frames and ns.db.frames[KEY] end

-- the five laid out on the holder: down from its top, or up from its bottom
local function Layout(c, cfg)
    local h, sp = cfg.height, cfg.spacing or 28
    c:SetSize(cfg.width, COUNT * h + (COUNT - 1) * sp)
    for i, b in ipairs(c.buttons) do
        b:SetSize(cfg.width, cfg.height)
        b:ClearAllPoints()
        if cfg.growth == "UP" then
            b:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", 0, (i - 1) * (h + sp))
        else
            b:SetPoint("TOPLEFT", c, "TOPLEFT", 0, -(i - 1) * (h + sp))
        end
    end
end

local function Place(c, cfg)
    c:ClearAllPoints()
    c:SetPoint(cfg.point or "CENTER", UIParent, cfg.point or "CENTER", cfg.x or 0, cfg.y or 0)
end

local function HideGame()
    local b, cfg = ns.db.blizzard, Cfg()
    if not (b and b.boss ~= false and cfg and cfg.enabled) then return end
    local names = { "BossTargetFrameContainer" }
    for i = 1, COUNT do names[#names + 1] = "Boss" .. i .. "TargetFrame" end
    ns.HideGameFrames(names)
end

local function Spawn()
    local cfg = Cfg()
    if not (cfg and cfg.enabled) or ns.frames[KEY] or InCombatLockdown() then return ns.frames[KEY] end
    local c = CreateFrame("Frame", "ZacUF_bossHeader", UIParent)
    c.cfg = cfg
    c:SetMovable(true)
    c:SetClampedToScreen(true)
    c.buttons = {}
    for i = 1, COUNT do
        local b = ns.NewUnitButton("oUF_ZacUFBoss" .. i, c, "boss" .. i, cfg,
            { events = { "INSTANCE_ENCOUNTER_ENGAGE_UNIT", "UNIT_TARGETABLE_CHANGED" } })
        b._zSet = c
        -- in move mode a drag on any of the five moves all of them
        b:RegisterForDrag("LeftButton")
        b:SetScript("OnDragStart", function()
            if not ns.db.locked and not InCombatLockdown() then c:StartMoving() end
        end)
        b:SetScript("OnDragStop", function()
            c:StopMovingOrSizing()
            local cx, cy = c:GetCenter()
            local ux, uy = UIParent:GetCenter()
            if cx and ux then
                local nx, ny = cx - ux, cy - uy
                if ns.SnapValue then nx, ny = ns.SnapValue(nx), ns.SnapValue(ny) end
                cfg.point, cfg.x, cfg.y = "CENTER", nx, ny
            end
            if not InCombatLockdown() then Place(c, cfg) end
            if ns.RefreshOptions then ns.RefreshOptions() end
        end)
        c.buttons[i] = b
    end
    Layout(c, cfg)
    Place(c, cfg)

    c.LeanRestyle = function(self)
        local unlocked = not ns.db.locked
        if not InCombatLockdown() then
            Layout(self, cfg)
            Place(self, cfg)
        end
        for i, b in ipairs(self.buttons) do
            b._zOn = cfg.enabled and true or false
            ns.UI:FrameBackdrop(b, cfg.bgColor, cfg.borderColor)
            ns.StyleElements(b)
            ns.RegisterFrameEvents(b)
            ns.UpdateAuras(b)
            ns.UpdateIndicators(b)
            ns.UpdateHealth(b)
            ns.CastbarPreview(b, unlocked and cfg.enabled)
            ns.ExtraMover(b, "Boss " .. i, unlocked and cfg.enabled)
        end
        local Zr = ns.ZUI or _G.ZacUI
        if Zr and Zr.Visibility then Zr.Visibility.Refresh(self) end
    end

    ns.frames[KEY] = c
    local Zv = ns.ZUI or _G.ZacUI
    if Zv and Zv.Visibility then
        Zv.Visibility.Register(c, function() return cfg.visibility end,
            { control = "gate", onChange = ns.VisibilityApply })
    end
    c:LeanRestyle()
    HideGame()
    return c
end

-- live: on = made now (out of combat); off = the five put away
local function Apply()
    local cfg, c = Cfg(), ns.frames[KEY]
    if not cfg then return end
    if cfg.enabled and not c then Spawn() return end
    if c and not cfg.enabled then
        for _, b in ipairs(c.buttons) do
            b._zOn = false
            if b.moverTex then b.moverTex:Hide() b.mover:Hide() end
            ns.WatchUnitButton(b, false)
        end
    end
    HideGame()
end

-- ----------------------------------------------------------------------------
-- The preview: a council of five, one of them casting, one at low health
-- ----------------------------------------------------------------------------
local COUNCIL = {
    { "High King Maulgar", 0.62, "Whirlwind", "Ability_Whirlwind", 2.0, 8 },
    { "Kiggler the Crazed", 0.88, "Greater Polymorph", "Spell_Nature_Polymorph", 1.5, 7 },
    { "Blindeye the Seer", 0.21, "Prayer of Healing", "Spell_Holy_PrayerOfHealing02", 3.0, 6 },
    { "Olm the Summoner", 0.97 },
    { "Krosh Firehand", 0.45, "Greater Fireball", "Spell_Fire_FlameBolt", 3.0, 3 },
}
local function People(P)
    local out = {}
    for i, b in ipairs(COUNCIL) do
        out[i] = P.person({ name = b[1], reaction = 2, pct = b[2], maxHp = 600000,
            ptoken = "MANA", ptype = 0, pp = 80, maxPp = 100, buffs = {}, debuffs = {},
            marker = b[6], cast = b[3] and { b[3], P.ICON .. b[4], b[5] } or nil })
    end
    return out
end

local function PreviewLayout(cfg, P)
    local people = People(P)
    local h, sp = cfg.height, cfg.spacing or 28
    local total = COUNT * h + (COUNT - 1) * sp
    return people, function(i)
        local x = -cfg.width / 2
        if cfg.growth == "UP" then
            return x, -total / 2 + (i - 1) * (h + sp) + h
        end
        return x, total / 2 - (i - 1) * (h + sp)
    end
end

if ns.RegisterExtraFrame and ns.defaults and ns.defaults.frames and ns.defaults.frames.target then
    local def = ns.CopyDefaults(ns.defaults.frames.target, {
        enabled = false, width = 170, height = 32, point = "CENTER", x = 520, y = 160,
        spacing = 28, growth = "DOWN",
        power = true, name = true, showBuffs = false, showDebuffs = false, castbar = true, healthText = "percent",
        combatIcon = false, leaderIcon = false, roleIcon = false, raidIcon = true, pvpIcon = false, rezIcon = false,
        raidSize = 18,
    })
    ns.RegisterExtraFrame({ key = KEY, label = "Boss frames", short = "Boss", after = "focustarget",
        available = Available, defaults = def, blizzard = { boss = true },
        spawn = Spawn, apply = Apply, layout = PreviewLayout })
end

-- ----------------------------------------------------------------------------
-- The page
-- ----------------------------------------------------------------------------
ns.UFPageCards[#ns.UFPageCards + 1] = function(L, tab, key, cfg, H)
    if key ~= KEY or not ns.ExtraFrame(KEY) then return end
    if tab == "general" then
        L:Card("Boss frames")
        L:Desc("Up to five, one per boss the encounter hands over (a council shows them all). Off until you "
            .. "switch them on; on or off takes effect at once (out of combat). Click one to target that boss.")
        H.Checks(L, {
            { "Hide the game's boss frames", function() return ns.db.blizzard.boss ~= false end,
              function(v) ns.db.blizzard.boss = v and true or false end,
              "While ZacUI's boss frames are on. Showing the game's again takes a reload." },
        }, 1)
        H.Button(L, "Test on screen", 130, function()
            local c, PV = ns.frames[KEY], ns.UFPreview
            if not (c and cfg.enabled) then
                if ns.Print then ns.Print("switch the boss frames on first (Show this frame, above).") end
                return
            end
            local people = People(PV.Kit())
            local list = {}
            for i, b in ipairs(c.buttons) do list[i] = { b, people[i] } end
            ns.TestExtra(list)
        end, "Shows the preview's five sample bosses on your real frames for a few seconds.")
        L:EndCard()
    elseif tab == "pos" then
        L:Card("Boss frames layout")
        H.Sliders(L, { label = "Gap between them", min = 0, max = 60, format = H.PX,
            get = function() return cfg.spacing or 28 end, set = function(v) cfg.spacing = v end })
        H.Drops(L, { label = "Grow", items = { { text = "Down", value = "DOWN" }, { text = "Up", value = "UP" } },
            get = function() return cfg.growth or "DOWN" end, set = function(v) cfg.growth = v end })
        L:Desc("The position above is the middle of the five. Leave room for the cast bar under each in the gap.")
        L:EndCard()
    end
end
