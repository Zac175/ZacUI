-- QoL_Stats - a small block of your character's stats on the screen:
-- attack power, crit, hit, spell power, mana per 5, armour, dodge... the
-- ones you pick, the numbers the character pane shows, kept up to date.
-- Off by default (Quality of life > On screen).
-- Part of ZacUI; load order is set by the TOC.
--
-- WHICH STATS: every stat the client can read (a stat whose call this
-- client lacks is not offered), grouped as Melee / Ranged / Spell /
-- Defence / Other. With nothing picked yet, the block shows a set that
-- suits your class (a warrior: attack power, crit, hit, speed; a mage:
-- spell power, spell crit, spell hit, speed...). Hit on TBC adds the hit
-- rating's bonus to the talents' hit, as the character pane does.
--
-- THE LOOK: one row per stat, its name on the left in the stat's colour
-- (or plain), the number on the right in white; text outlined, the font
-- picked here; ZacUI's panel behind it (or nothing); a mover places it.
-- Shown always, only in combat, or only out of combat.
--
-- FOREVER: a value the game hides from addons in a fight is handed to the
-- text as it is when it needs no sum; a stat that is a sum or a best-of
-- (attack power, spell power) shows "?" while hidden. Never compared.
--
-- COST: nothing while off. On and shown: one 0.5 s ticker reading the
-- picked stats (a few calls each); stopped while the block is hidden.

local ADDON_NAME = ...
local ns = _G.ZacUI
if not ns then return end

local GetColor = ns.GetColor
local QoL = ns.QoL
if not QoL then return end

local ST = {}
QoL.Stats = ST

local OWN_ID = "qol_stats"
local MOVER = "qolstats"
local W, ROW, PAD = 140, 16, 6
local TICK = 0.5
ST.FONT_DEFAULTS = { size = 12, outline = "outline", shadow = false }
ST.SHOW = {
    { value = "always", text = "Always" },
    { value = "combat", text = "Only in combat" },
    { value = "nocombat", text = "Only out of combat" },
}

local function Hidden(v) return ns.IsSecret and ns.IsSecret(v) or false end
local floor = math.floor

-- ============================================================
-- THE STATS
-- ============================================================
-- a sum of the values handed in; nil when one is hidden
local function Sum(...)
    local t = 0
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if Hidden(v) then return nil end
        t = t + (tonumber(v) or 0)
    end
    return t
end
local function Fn(name) return type(_G[name]) == "function" and _G[name] or nil end
local function RatingBonus(cr)
    local f = Fn("GetCombatRatingBonus")
    local id = _G[cr]
    if not f or not id then return 0 end
    return f(id) or 0
end
local function Best(fn, from, to)
    local best = 0
    for i = from, to do
        local v = fn(i)
        if Hidden(v) then return nil end
        v = tonumber(v) or 0
        if v > best then best = v end
    end
    return best
end
local NUM, PCT = "%d", "%.2f%%"

-- key, label, hue, format, getter, needs (the call it needs), raw (the
-- getter's value is the game's own, so a hidden one is drawn as it is)
local function S(key, label, hue, fmt, needs, get, raw)
    return { key = key, label = label, hue = hue, fmt = fmt, needs = needs, get = get, raw = raw }
end
ST.GROUPS = {
    { title = "Melee", stats = {
        S("ap", "Attack Power", "ap", NUM, "UnitAttackPower", function() return Sum(UnitAttackPower("player")) end),
        S("mcrit", "Crit", "crit", PCT, "GetCritChance", function() return GetCritChance() end, true),
        S("mhit", "Hit", "hit", PCT, "GetHitModifier", function()
            local h = GetHitModifier()
            return Sum(h, RatingBonus("CR_HIT_MELEE"))
        end),
        S("mhaste", "Haste", "haste", PCT, "GetMeleeHaste", function() return GetMeleeHaste() end, true),
        S("expertise", "Expertise", "hit", NUM, "GetExpertise", function() return (GetExpertise()) end, true),
    } },
    { title = "Ranged", stats = {
        S("rap", "Ranged AP", "ap", NUM, "UnitRangedAttackPower", function() return Sum(UnitRangedAttackPower("player")) end),
        S("rcrit", "Ranged Crit", "crit", PCT, "GetRangedCritChance", function() return GetRangedCritChance() end, true),
        S("rhit", "Ranged Hit", "hit", PCT, "GetHitModifier", function()
            return Sum(GetHitModifier(), RatingBonus("CR_HIT_RANGED"))
        end),
    } },
    { title = "Spell", stats = {
        S("sp", "Spell Power", "sp", NUM, "GetSpellBonusDamage", function() return Best(GetSpellBonusDamage, 2, 7) end),
        S("healing", "Healing", "healing", NUM, "GetSpellBonusHealing", function() return GetSpellBonusHealing() end, true),
        S("scrit", "Spell Crit", "crit", PCT, "GetSpellCritChance", function() return Best(GetSpellCritChance, 2, 7) end),
        S("shit", "Spell Hit", "hit", PCT, "GetSpellHitModifier", function()
            -- Classic hands back the hit chance in tenths of a percent on some clients: shown as the pane does
            local h = GetSpellHitModifier()
            if Hidden(h) then return nil end
            h = tonumber(h) or 0
            return Sum(h, RatingBonus("CR_HIT_SPELL"))
        end),
        S("mp5", "Mana per 5", "mp5", NUM, "GetManaRegen", function()
            local base = GetManaRegen()
            if Hidden(base) then return nil end
            return floor((tonumber(base) or 0) * 5 + 0.5)
        end),
    } },
    { title = "Defence", stats = {
        S("armor", "Armour", "armor", NUM, "UnitArmor", function() return (select(2, UnitArmor("player"))) end, true),
        S("defense", "Defence", "armor", NUM, "UnitDefense", function() return Sum(UnitDefense("player")) end),
        S("dodge", "Dodge", "avoid", PCT, "GetDodgeChance", function() return GetDodgeChance() end, true),
        S("parry", "Parry", "avoid", PCT, "GetParryChance", function() return GetParryChance() end, true),
        S("block", "Block", "avoid", PCT, "GetBlockChance", function() return GetBlockChance() end, true),
    } },
    { title = "Other", stats = {
        S("speed", "Speed", "speed", "%d%%", "GetUnitSpeed", function()
            local run = select(2, GetUnitSpeed("player"))
            if Hidden(run) then return nil end
            return floor((tonumber(run) or 7) / 7 * 100 + 0.5)
        end),
    } },
}
ST.BY_KEY = {}
for _, g in ipairs(ST.GROUPS) do for _, s in ipairs(g.stats) do ST.BY_KEY[s.key] = s end end

-- the colours (ZacUI's own picks)
ST.HUES = {
    ap = { 1, 0.5, 0.25 }, crit = { 1, 0.82, 0.24 }, hit = { 0.47, 0.86, 0.35 }, haste = { 0.95, 0.95, 0.45 },
    sp = { 0.75, 0.51, 1 }, healing = { 0.35, 0.9, 0.75 }, mp5 = { 0.35, 0.63, 1 }, armor = { 0.75, 0.75, 0.75 },
    avoid = { 0.55, 0.8, 1 }, speed = { 0.86, 0.86, 0.86 },
}

-- the class's set when nothing is picked
ST.CLASS_SET = {
    WARRIOR = { "ap", "mcrit", "mhit", "speed" },
    ROGUE   = { "ap", "mcrit", "mhit", "speed" },
    HUNTER  = { "rap", "rcrit", "rhit", "speed" },
    PALADIN = { "ap", "mcrit", "sp", "healing", "speed" },
    SHAMAN  = { "sp", "scrit", "mp5", "speed" },
    DRUID   = { "sp", "scrit", "mp5", "speed" },
    MAGE    = { "sp", "scrit", "shit", "speed" },
    WARLOCK = { "sp", "scrit", "shit", "speed" },
    PRIEST  = { "healing", "scrit", "mp5", "speed" },
}

function ST.Available(s) return s and Fn(s.needs) ~= nil end

-- ============================================================
-- SETTINGS (qol.stats; nothing saved = off)
-- ============================================================
local function DB()
    local q = QoL.DB()
    if type(q.stats) ~= "table" then q.stats = {} end
    return q.stats
end
ST.DB = DB
local function Allowed() return not (ns.FeatureOn and not ns.FeatureOn(OWN_ID)) end
function ST.On() return Allowed() and QoL.enabled == true and DB().enabled == true end
function ST.ShowMode() return DB().show or "always" end
function ST.Background() return DB().background ~= false end
function ST.Colored() return DB().plain ~= true end

-- the picked keys in order (the class's set when nothing is picked)
function ST.Keys()
    local d = DB()
    local out = {}
    if type(d.pick) == "table" then
        for _, g in ipairs(ST.GROUPS) do
            for _, s in ipairs(g.stats) do
                if d.pick[s.key] and ST.Available(s) then out[#out + 1] = s.key end
            end
        end
        return out
    end
    local file = UnitClass and select(2, UnitClass("player"))
    for _, k in ipairs(ST.CLASS_SET[file or ""] or ST.CLASS_SET.WARRIOR) do
        if ST.Available(ST.BY_KEY[k]) then out[#out + 1] = k end
    end
    return out
end

-- the text for one stat: a string, or (fmt, hidden value) to hand to the game
function ST.Value(s)
    local ok, v = pcall(s.get)
    if not ok or v == nil then return "?" end
    if Hidden(v) then
        if s.raw then return nil, s.fmt, v end
        return "?"
    end
    v = tonumber(v)
    if not v then return "?" end
    if s.fmt == NUM then
        local n = floor(v + 0.5)
        if ns.Numbers and ns.Numbers.Comma then
            local good, t = pcall(ns.Numbers.Comma, n)
            if good and type(t) == "string" then return t end
        end
        return tostring(n)
    end
    return string.format(s.fmt, v)
end

-- ============================================================
-- THE BLOCK (live, and the page's sample)
-- ============================================================
local function Font(fs)
    if ns.ApplyFontSpec then ns.ApplyFontSpec(fs, DB().font, ST.FONT_DEFAULTS)
    elseif ns.HouseFont then ns.HouseFont(fs, 12, "OUTLINE")
    else fs:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 12, "OUTLINE") end
end

function ST.Build(parent, name)
    local UI = ns.UI
    local f = CreateFrame("Frame", name, parent or UIParent)
    f:SetSize(W, PAD * 2 + ROW)
    f:EnableMouse(false)
    if UI then
        UI.Fill(f, "ui", "windowBg", 0.6)
        UI.Border(f, "ui", "border")
        if UI.PaintBox then UI.PaintBox(f) end
    end
    f.rows = {}
    return f
end

local function RowOf(f, i)
    local r = f.rows[i]
    if r then return r end
    r = {}
    r.label = f:CreateFontString(nil, "OVERLAY")
    r.value = f:CreateFontString(nil, "OVERLAY")
    Font(r.label) Font(r.value)
    r.label:SetJustifyH("LEFT")
    r.value:SetJustifyH("RIGHT")
    f.rows[i] = r
    return r
end

-- fills a block with the stats `keys` (sample: made-up numbers)
function ST.Fill(f, keys, sample)
    local size = tonumber(type(DB().font) == "table" and DB().font.size) or ST.FONT_DEFAULTS.size
    local row = math.max(ROW, size + 4)
    local widest = 0
    for i, k in ipairs(keys) do
        local s = ST.BY_KEY[k]
        local r = RowOf(f, i)
        Font(r.label) Font(r.value)
        r.label:ClearAllPoints()
        r.label:SetPoint("LEFT", f, "TOPLEFT", PAD, -(PAD + (i - 1) * row + row / 2))
        r.value:ClearAllPoints()
        r.value:SetPoint("RIGHT", f, "TOPRIGHT", -PAD, -(PAD + (i - 1) * row + row / 2))
        r.label:SetText(s.label)
        local h = ST.Colored() and ST.HUES[s.hue] or { 1, 1, 1 }
        r.label:SetTextColor(h[1], h[2], h[3])
        r.value:SetTextColor(1, 1, 1)
        if sample then
            r.value:SetText(s.fmt == PCT and "12.34%" or (s.key == "speed" and "100%" or "1,234"))
        else
            local text, fmt, v = ST.Value(s)
            if text then r.value:SetText(text) else r.value:SetFormattedText(fmt, v) end
        end
        r.label:Show() r.value:Show()
        local lw = r.label.GetStringWidth and r.label:GetStringWidth() or 0
        if Hidden(lw) or type(lw) ~= "number" then lw = 80 end
        widest = math.max(widest, lw)
    end
    for i = #keys + 1, #f.rows do f.rows[i].label:Hide() f.rows[i].value:Hide() end
    -- wide enough for the longest name and a number beside it: nothing cut
    f:SetSize(math.max(W, floor(widest + 70 + 2 * PAD + 0.5)), PAD * 2 + math.max(1, #keys) * row)
    if f._zFill then f._zFill:SetShown(ST.Background()) end
    if f._zBorder then for _, t in ipairs(f._zBorder) do t:SetShown(ST.Background()) end end
    return f
end

local block, ticker
local function Block()
    if block then return block end
    block = ST.Build(UIParent, "ZacUIStats")
    block:SetFrameStrata("LOW")
    block:Hide()
    block:ClearAllPoints()
    block:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 300, 220)
    if ns.ApplyMover then ns.ApplyMover(MOVER) end
    return block
end
ST.Frame = function() return block end

local function Repaint() if block and block:IsShown() then pcall(ST.Fill, block, ST.Keys()) end end
ST.Repaint = Repaint

local function StopTick() if ticker then ticker:Cancel() ticker = nil end end
local function StartTick()
    if ticker then return end
    ticker = C_Timer.NewTicker(TICK, Repaint)
    if ns.Profiler and ns.Profiler.TrackTicker then ns.Profiler.TrackTicker(ticker, "qol.stats") end
end
function ST.Ticking() return ticker ~= nil end

-- shows or hides the block for the combat state now
function ST.Update()
    if not ST.On() then
        StopTick()
        if block then block:Hide() end
        return false
    end
    local fight = InCombatLockdown and InCombatLockdown() or false
    local mode = ST.ShowMode()
    local show = mode == "always" or (mode == "combat" and fight) or (mode == "nocombat" and not fight)
    if not show then
        StopTick()
        if block then block:Hide() end
        return false
    end
    Block()
    block:Show()
    ST.Fill(block, ST.Keys())
    StartTick()
    return true
end

local ev
function ST.Apply()
    if not ST.On() then
        if ev then ev:UnregisterAllEvents() end
        ST.Update()
        return
    end
    if not ev then
        ev = CreateFrame("Frame")
        ev:SetScript("OnEvent", function(_, event)
            if event == "PLAYER_REGEN_DISABLED" then
                -- the lockdown flag turns a moment after this event
                C_Timer.After(0, ST.Update)
            else
                ST.Update()
            end
        end)
    end
    ev:RegisterEvent("PLAYER_REGEN_DISABLED")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    -- (2026-11-10) switched on = there is a frame, even while nothing
    -- calls for it: Edit Mode places what exists and reads a missing
    -- frame as "switched off".
    if not block then Block() block:Hide() end
    ST.Update()
end

local function Live() if QoL.enabled then ST.Apply() end end
ST.Live = Live
if Allowed() then
    if ns.RegisterMover then
        ns.RegisterMover(MOVER, "Character stats", function() return block end, "BOTTOMLEFT", 300, 220, nil, { own = true })
    end
    if ns.OnSettingsChanged then ns.OnSettingsChanged(function() if QoL.enabled and block then Repaint() end end) end
    local base = QoL.EnableAutomation
    function QoL.EnableAutomation(...)
        if base then base(...) end
        pcall(ST.Apply)
    end
end

-- ============================================================
-- THE PAGE: Quality of life > On screen
-- ============================================================
local function AddTab(page, tab, label, build)
    if ns.AddPageTab then return ns.AddPageTab(page, tab, label, build) end
    ns.PageTabs = ns.PageTabs or {}
    local l = ns.PageTabs[page] or {}
    ns.PageTabs[page] = l
    l[#l + 1] = { tab = tab, label = label, build = build }
end

local view = setmetatable({}, {
    __index = function(_, k) return DB()[k] end,
    __newindex = function(_, k, v) DB()[k] = v end,
})

AddTab("qol", "onscreen", "On screen", function(L)
    if not Allowed() then return end
    local UI = ns.UI
    local Kit = ns.CorePageKit
    local d = DB()
    local function Changed()
        Live()
        if ns.RefreshConfig then ns.RefreshConfig() end
    end
    L:Card("Character stats")
    local on = UI.Checkbox(L.current, "Show my stats on the screen", d.enabled == true, function(v)
        d.enabled = v and true or nil
        Changed()
    end, { tooltip = "A small block of the stats you pick, the numbers your character pane shows, kept up to date." })
    L:Row(on, 17)
    -- the sample, as it looks
    local holder = UI.Holder(L.current)
    local keys = ST.Keys()
    local sample = ST.Build(holder)
    sample:SetPoint("TOPLEFT")
    ST.Fill(sample, keys, true)
    holder:SetSize(sample:GetWidth(), sample:GetHeight())
    L:Row(holder, sample:GetHeight() + 6)
    local kids = {}
    kids[#kids + 1] = UI.Field(L.current, "Show", function(h)
        return UI.Dropdown(h, { width = 180,
            items = function() return ST.SHOW end,
            selectedValue = function() return ST.ShowMode() end,
            selected = function()
                for _, m in ipairs(ST.SHOW) do if m.value == ST.ShowMode() then return m.text end end
                return ST.SHOW[1].text
            end,
            onSelect = function(v) d.show = (v ~= "always") and v or nil Changed() end })
    end, { width = 180 })
    kids[#kids + 1] = UI.Checkbox(L.current, "Panel behind it", ST.Background(), function(v)
        if v then d.background = nil else d.background = false end
        Changed()
    end)
    kids[#kids + 1] = UI.Checkbox(L.current, "Names in each stat's colour", ST.Colored(), function(v)
        d.plain = (not v) and true or nil
        Changed()
    end)
    L:Dependent(kids, d.enabled == true, 1, nil, "Show my stats on the screen")
    if Kit then
        Kit.Font(L, "Text", function() return view end, "font", ST.FONT_DEFAULTS,
            { sample = "Attack Power  1,234", after = function() Changed() end })
        if Kit.Mover and ns.MOVERS and ns.MOVERS[MOVER] then Kit.Mover(L, MOVER, "the block") end
    end
    L:EndCard()

    L:Card("Which stats")
    if type(d.pick) ~= "table" then
        L:Desc("Nothing picked yet: your class's set is shown. Tick any stat to make your own list.")
    end
    local picked = {}
    for _, k in ipairs(keys) do picked[k] = true end
    for _, g in ipairs(ST.GROUPS) do
        local row = {}
        for _, s in ipairs(g.stats) do
            if ST.Available(s) then
                row[#row + 1] = UI.Checkbox(L.current, s.label, picked[s.key] == true, function(v)
                    if type(d.pick) ~= "table" then
                        -- the class's set becomes the starting list
                        d.pick = {}
                        for _, k in ipairs(keys) do d.pick[k] = true end
                    end
                    d.pick[s.key] = v and true or nil
                    Changed()
                end)
            end
        end
        if #row > 0 then
            L:Desc(g.title)
            if L.Flow then L:Flow(row) else for _, w in ipairs(row) do L:Row(w, 17) end end
        end
    end
    local reset = UI.Button(L.current, "My class's set", { width = 120,
        tooltip = "Forget the ticks: the block shows the set that suits your class again.",
        onClick = function() d.pick = nil Changed() end })
    L:Row(reset, 26)
    L:EndCard()
end)

if ns.AddMenuKeywords then
    ns.AddMenuKeywords("qol", "stats character crit hit attack power spell power mana regen mp5 armor dodge parry block speed haste secondary block")
end
