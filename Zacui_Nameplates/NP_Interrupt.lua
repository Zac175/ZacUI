-- NP_Interrupt - the interrupt-ready tint on the nameplates' cast bars
-- (feature cluster 2, 2026-11-07). A cast you could interrupt is coloured
-- by whether YOUR interrupt can land on it right now:
--   ready         your interrupt is off cooldown, usable, and the caster
--                 is in its range
--   cooldown      every interrupt you have is on cooldown (or not usable
--                 here: the wrong stance, no shield for Shield Bash)
--   out of range  one is ready but the caster is out of its reach
-- The interrupts per class: Pummel and Shield Bash, Kick, Counterspell,
-- Earth Shock, Silence, Feral Charge, Silencing Shot, the Felhunter's Spell
-- Lock (and Retail's own where the client is Retail). A cast that can't be
-- interrupted keeps its colour; a cast alert's colour outranks the tint.
-- SECRET-SAFE (WoW Forever): a cooldown, a range or a usable flag the game
-- hides from addons reads as "unknown", and an unknown state is no tint
-- (the bar keeps its normal colour); a hidden cast (its "can't be
-- interrupted" flag hidden too) is never tinted.
-- COST: nothing at all while off (no frame, no event, no ticker). On, the
-- cast bar's own paint only marks the bar; one 0.1 s ticker (tracked) runs
-- while at least one interruptible cast is on a plate and stops with the
-- last one: one cooldown read per interrupt per tick, one range read per
-- casting plate. Nothing in a cooldown, aura or combat-log event.
-- Settings: ZacUIDB.nameplates.kickTint (nil = off, nothing written by
-- browsing). Card: Nameplates > General, with three sample bars.
-- Part of ZacUI; load order is set by the TOC (after NP_Cast).

local ns = _G.ZacUI
if not ns then return end
local NP = ns.Nameplates
if not NP then return end

local OWN_ID = "np_kick"
local KI = {}
NP.Kick = KI

local GetTime, pcall, type, ipairs, pairs, next = GetTime, pcall, type, ipairs, pairs, next

-- the three colours: ready green, cooldown violet (apart from the grey of
-- "can't be interrupted" and the red interrupted flash), out of range amber
KI.DEFAULTS = {
    ready    = { 0.20, 0.85, 0.35 },
    cooldown = { 0.55, 0.35, 0.85 },
    range    = { 1.00, 0.60, 0.15 },
}
KI.STATES = { "ready", "cooldown", "range" }
KI.LABELS = { ready = "Ready", cooldown = "On cooldown", range = "Out of range" }

-- every rank (and Retail's own spell) per class; pet = the pet's spell
KI.SPELLS = {
    WARRIOR = { { 6552, 6554 }, { 72, 1671, 1672, 29704 } },               -- Pummel, Shield Bash
    ROGUE   = { { 1766, 1767, 1768, 1769, 38768 } },                       -- Kick
    MAGE    = { { 2139 } },                                                -- Counterspell
    SHAMAN  = { { 8042, 8044, 8045, 8046, 10412, 10413, 10414, 25454 }, { 57994 } }, -- Earth Shock, Wind Shear
    PRIEST  = { { 15487 } },                                               -- Silence
    DRUID   = { { 16979 }, { 106839 } },                                   -- Feral Charge, Skull Bash
    HUNTER  = { { 34490 }, { 147362, 187707 } },                           -- Silencing Shot, Counter Shot / Muzzle
    WARLOCK = { { 19244, 19647, pet = true } },                            -- Spell Lock (the Felhunter)
    PALADIN = { { 96231 } },                                               -- Rebuke (Retail)
    DEATHKNIGHT = { { 47528 } }, MONK = { { 116705 } }, DEMONHUNTER = { { 183752 } }, EVOKER = { { 351338 } },
}

local function Sec(v) return ns.IsSecret and ns.IsSecret(v) or false end
local function DB() return NP.DB() end

-- the settings, as saved (nil: never switched on)
function KI.Cfg()
    local d = DB()
    local k = d and d.kickTint
    return type(k) == "table" and k or nil
end
function KI.Saved()
    local d = DB()
    if type(d.kickTint) ~= "table" then d.kickTint = {} end
    return d.kickTint
end
function KI.On()
    local k = KI.Cfg()
    if not (k and k.enabled) then return false end
    return (not ns.FeatureOn) or ns.FeatureOn(OWN_ID)
end
function KI.Color(state)
    local k = KI.Cfg()
    local c = k and type(k[state]) == "table" and k[state] or KI.DEFAULTS[state]
    return c[1] or 1, c[2] or 1, c[3] or 1
end

-- ------------------------------------------------------------
-- YOUR INTERRUPTS (read again when your spells change: marked, not read)
-- ------------------------------------------------------------
local mine, mineDirty = {}, true
local function Known(id, pet)
    if not pet and IsPlayerSpell then
        local ok, v = pcall(IsPlayerSpell, id)
        if ok and v and not Sec(v) then return true end
    end
    if IsSpellKnown then
        local ok, v = pcall(IsSpellKnown, id, pet and true or nil)
        if ok and v and not Sec(v) then return true end
    end
    return false
end
local function SpellName(id)
    if C_Spell and C_Spell.GetSpellName then
        local ok, n = pcall(C_Spell.GetSpellName, id)
        if ok and type(n) == "string" then return n end
    end
    if GetSpellInfo then
        local ok, n = pcall(GetSpellInfo, id)
        if ok and type(n) == "string" then return n end
    end
    return nil
end

function KI.Mine()
    if not mineDirty then return mine end
    mineDirty = false
    mine = {}
    local _, class = UnitClass("player")
    for _, ranks in ipairs(KI.SPELLS[class or ""] or {}) do
        -- the highest rank known stands for the spell
        for i = #ranks, 1, -1 do
            local id = ranks[i]
            if Known(id, ranks.pet) then
                mine[#mine + 1] = { id = id, name = SpellName(id) or tostring(id), pet = ranks.pet }
                break
            end
        end
    end
    return mine
end
function KI.MarkSpells() mineDirty = true end

-- ------------------------------------------------------------
-- READS (each nil when the game hides it: unknown)
-- ------------------------------------------------------------
-- seconds left on the spell's cooldown: 0 = ready (the global cooldown
-- counts as ready), nil = hidden or unreadable
local function CooldownLeft(sp)
    local start, dur
    if C_Spell and C_Spell.GetSpellCooldown then
        local ok, t = pcall(C_Spell.GetSpellCooldown, sp.id)
        if ok and type(t) == "table" then start, dur = t.startTime, t.duration end
    elseif GetSpellCooldown then
        local ok, s, d = pcall(GetSpellCooldown, sp.name)
        if ok then start, dur = s, d end
    end
    if start == nil or dur == nil or Sec(start) or Sec(dur) then return nil end
    if start == 0 or dur <= 1.5 then return 0 end
    local left = start + dur - GetTime()
    return left > 0 and left or 0
end
-- usable here and now (stance, a shield, mana): true / false / nil
local function Usable(sp)
    local fn = (C_Spell and C_Spell.IsSpellUsable) or IsUsableSpell
    if not fn then return true end
    local ok, u = pcall(fn, (fn == IsUsableSpell) and sp.name or sp.id)
    if not ok or Sec(u) then return nil end
    return u and true or false
end
-- the unit in this spell's range: true / false / nil (no answer)
local function InRange(sp, unit)
    local ok, r
    if C_Spell and C_Spell.IsSpellInRange then ok, r = pcall(C_Spell.IsSpellInRange, sp.id, unit)
    elseif IsSpellInRange then ok, r = pcall(IsSpellInRange, sp.name, unit)
    else return nil end
    if not ok or r == nil or Sec(r) then return nil end
    if r == 1 or r == true then return true end
    if r == 0 or r == false then return false end
    return nil
end

-- the per-tick read of your interrupts: { ready = bool|nil } each
local function SpellStates()
    local out = {}
    for i, sp in ipairs(KI.Mine()) do
        local left = CooldownLeft(sp)
        local use = Usable(sp)
        local ready
        if left == nil or use == nil then ready = nil
        else ready = (left == 0) and use end
        out[i] = { sp = sp, ready = ready }
    end
    return out
end

-- "ready" | "cooldown" | "range" | nil (unknown: no tint) for a unit
function KI.StateFor(unit, states)
    states = states or SpellStates()
    if #states == 0 then return nil end
    local anyReady, anyUnknown, outOfRange = false, false, false
    for _, s in ipairs(states) do
        if s.ready == nil then anyUnknown = true
        elseif s.ready then
            anyReady = true
            local r = InRange(s.sp, unit)
            if r == true then return "ready" end
            if r == false then outOfRange = true else anyUnknown = true end
        end
    end
    if outOfRange then return "range" end
    if not anyReady and not anyUnknown then return "cooldown" end
    return nil
end

-- ------------------------------------------------------------
-- THE BARS
-- ------------------------------------------------------------
local watch             -- the frame that hears your spells change (made when first on)
local active = {}        -- [cast bar] = true while an interruptible cast is on it
local base = setmetatable({}, { __mode = "k" })   -- [cast bar] = the colour the cast bar painted
local ticker

local function Paint(cb, state)
    cb._kickState = state
    if state then
        local r, g, b = KI.Color(state)
        cb:SetStatusBarColor(r, g, b, 0.95)
    else
        local c = base[cb]
        if c then cb:SetStatusBarColor(c[1], c[2], c[3], 0.95) end
    end
end

local function Untrack(cb)
    active[cb] = nil
    if cb._kickState then Paint(cb, nil) end
end

local function StopTicker()
    if ticker then ticker:Cancel() ticker = nil end
end

local function Tick()
    if not KI.On() then
        for cb in pairs(active) do Untrack(cb) end
        StopTicker()
        return
    end
    local states
    for cb in pairs(active) do
        local f = cb:GetParent()
        local unit = f and f.unit
        if not (cb:IsShown() and cb.startMS and unit) then
            Untrack(cb)
        else
            states = states or SpellStates()
            local st = KI.StateFor(unit, states)
            if st ~= cb._kickState then Paint(cb, st) end
        end
    end
    if not next(active) then StopTicker() end
end
KI.Tick = Tick

local function StartTicker()
    if ticker then return end
    ticker = C_Timer.NewTicker(0.1, Tick)
    if ns.Profiler and ns.Profiler.TrackTicker then ns.Profiler.TrackTicker(ticker, "Nameplates.kickTint") end
end
function KI.Ticking() return ticker ~= nil end
function KI.Active() local n = 0 for _ in pairs(active) do n = n + 1 end return n end

-- the settings preview's sample plates (no unit) wear this state
KI.previewState = "ready"

-- Called by the cast bar's paint (NP_Cast) with the colour it just set.
-- Only marks the bar: the reads are the ticker's (the first one a frame
-- later, so a new cast is tinted before it is a tenth of a second old).
function NP.KickPaint(cb, c, notInterruptible, alert)
    base[cb] = c
    cb._kickState = nil
    if not KI.On() then active[cb] = nil return end
    local f = cb:GetParent()
    if alert or notInterruptible or cb._zTimer or not f then active[cb] = nil return end
    if not f.unit then
        -- a sample plate in the settings preview
        if rawget(f, "_pvCombat") ~= nil and KI.previewState then Paint(cb, KI.previewState) end
        return
    end
    if not watch then KI.Apply() end
    active[cb] = true
    StartTicker()
end

-- ------------------------------------------------------------
-- YOUR SPELLS CHANGING (only while on; the event marks, the next tick reads)
-- ------------------------------------------------------------
function KI.Apply()
    local on = KI.On()
    if on and not watch then
        watch = CreateFrame("Frame")
        watch:SetScript("OnEvent", KI.MarkSpells)
    end
    if watch then
        for _, ev in ipairs({ "SPELLS_CHANGED", "PLAYER_TALENT_UPDATE", "UNIT_PET", "LEARNED_SPELL_IN_TAB" }) do
            if on then pcall(watch.RegisterEvent, watch, ev) else watch:UnregisterEvent(ev) end
        end
    end
    KI.MarkSpells()
    KI.watch = watch
    if not on then
        for cb in pairs(active) do Untrack(cb) end
        StopTicker()
    end
end

-- (no login frame of its own: the first interruptible cast painted while on
-- sets the watch up, so a UI with the tint off has nothing of it at all)

-- ------------------------------------------------------------
-- THE CARD (Nameplates > General): the switch, the three colours and
-- three sample bars in them, the interrupts this character has
-- ------------------------------------------------------------
local function AddTab(page, tab, label, build)
    if ns.AddPageTab then return ns.AddPageTab(page, tab, label, build) end
    ns.PageTabs = ns.PageTabs or {}
    local list = ns.PageTabs[page] or {}
    ns.PageTabs[page] = list
    list[#list + 1] = { tab = tab, label = label, build = build }
end

local function Refresh()
    KI.Apply()
    if NP.RefreshAll then NP.RefreshAll() end
    if ns.SettingsChanged then ns.SettingsChanged("kickTint") end
end

-- three sample cast bars, each in one state's colour, on the card. Made
-- ONCE (the first build) and lent to each build of the card after that:
-- the page is built again on every tab switch and change, and a bar made
-- per build was a new frame each time (the settings pool, UIF_Pool, only
-- takes back the house widgets). The pool lets go of it with the card; the
-- next build takes it again, laid out for its width.
local sample
local function MakeSample()
    local UI = ns.UI
    local host = CreateFrame("Frame", nil, UIParent)
    host:Hide()
    host.bars, host.labels = {}, {}
    for _, st in ipairs(KI.STATES) do
        local cb = CreateFrame("StatusBar", nil, host)
        cb:SetStatusBarTexture(NP.BarTexture("castTexture"))
        cb:SetMinMaxValues(0, 1)
        cb:SetValue(0.6)
        local bg = cb:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        cb.bg = bg
        if ns.AddPixelBorder then ns.AddPixelBorder(cb, nil, nil, "nameplates") end
        host.bars[st] = cb
        host.labels[st] = UI.Font(host, UI.F.SMALL, { cat = "text", key = "gray", text = KI.LABELS[st], justify = "LEFT" })
    end
    function host.Refresh()
        local w = ns.Col("windowBg")
        for st, cb in pairs(host.bars) do
            cb:SetStatusBarTexture(NP.BarTexture("castTexture"))
            cb.bg:SetColorTexture(w.r, w.g, w.b, 0.85)
            cb:SetStatusBarColor(KI.Color(st))
        end
    end
    return host
end

function KI.BuildSample(parent, width)
    sample = sample or MakeSample()
    local host = sample
    host:SetParent(parent)
    host:ClearAllPoints()
    local barW = math.max(60, math.floor((width - 16) / 3))
    for i, st in ipairs(KI.STATES) do
        local x = (i - 1) * (barW + 8)
        local cb, lab = host.bars[st], host.labels[st]
        cb:ClearAllPoints()
        cb:SetSize(barW, 12)
        cb:SetPoint("TOPLEFT", host, "TOPLEFT", x, -16)
        lab:ClearAllPoints()
        lab:SetWidth(barW)
        lab:SetPoint("TOPLEFT", host, "TOPLEFT", x, 0)
    end
    host:SetSize(width, 30)
    host.Refresh()
    host:Show()
    return host
end

AddTab("nameplates", "general", "General", function(L)
    if ns.FeatureOn and not ns.FeatureOn(OWN_ID) then return end
    local UI = ns.UI
    local k = KI.Cfg()
    L:Card("Interrupt-ready cast bars")
    local on = UI.Checkbox(L.current, "Colour casts by your interrupt", (k and k.enabled) and true or false, function(v)
        KI.Saved().enabled = v and true or nil
        Refresh()
        if ns.RefreshConfig then ns.RefreshConfig() end
    end, { tooltip = "A cast you could interrupt is coloured by whether your interrupt can land on it now: ready "
        .. "and in range, on cooldown (or not usable in this stance), or ready but out of its range. Casts that "
        .. "can't be interrupted, and cast alerts, keep their colours." })
    L:Row(on, 17)
    local sample = KI.BuildSample(L.current, UI.CardInnerWidth and UI.CardInnerWidth(L) or 400)
    L:Add(sample, 8)
    local kids = {}
    for _, st in ipairs(KI.STATES) do
        kids[#kids + 1] = UI.ColorPicker(L.current, { label = KI.LABELS[st],
            get = function() return { KI.Color(st) } end,
            set = function(r, g, b)
                KI.Saved()[st] = { r, g, b }
                sample.Refresh()
                Refresh()
            end,
            default = function() local d = KI.DEFAULTS[st] return d[1], d[2], d[3], 1 end,
            reset = function()
                local s = KI.Cfg()
                if s then s[st] = nil end
                sample.Refresh()
                Refresh()
            end })
    end
    L:Dependent(kids, (k and k.enabled) and true or false, 3, nil, "Colour casts by your interrupt")
    local names = {}
    for _, sp in ipairs(KI.Mine()) do names[#names + 1] = sp.name end
    L:Desc(#names > 0 and ("Your interrupts: " .. table.concat(names, ", ") .. ".")
        or "This character has no interrupt yet, so casts keep their colours.")
    L:Desc("When the game hides a cooldown or the range from addons (WoW Forever in a fight) the bar keeps its normal colour. "
        .. "The preview's sample plate shows the Ready colour.")
    L:EndCard()
end)
