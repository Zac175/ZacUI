-- ============================================================================
-- Zacui_UnitFrames - PartyTargets.lua
-- Party targets: a small frame beside each party member's frame showing who
-- that member is targeting (party1target .. party4target), click to target
-- it (secure, combat-legal). One settings table (ns.db.frames.partytargets),
-- the side and the gap from the party frames; each button sits beside the
-- party cell that shows its member, found again when the group changes (out
-- of combat; in a fight it waits for the end - the units themselves are
-- always right, only the spot waits). Shown while its unit exists, by a
-- secure rule; hidden in a raid unless the party frames show there too.
-- The units have no change event, so each polls lightly while shown (the
-- target of target's 0.2 s poll). Off by default; nothing made while off.
-- Part of Zacui_UnitFrames; load order is set by the TOC (after Extras).
-- ============================================================================
local ADDON, ns = ...

local KEY = "partytargets"
local COUNT = 4

local function Cfg() return ns.db and ns.db.frames and ns.db.frames[KEY] end
-- the four buttons' holder: kept out of ns.frames (Edit Mode would outline
-- it as one frame, and the buttons sit by the party cells, not on it);
-- restyled by Apply on every settings change instead
local holder
function ns.PartyTargetsHolder() return holder end

local function Rule(i)
    local p = ns.db.party
    local cond = "[@party" .. i .. "target,exists] show; hide"
    if not (p and p.showInRaid) then cond = "[group:raid] hide; " .. cond end
    return cond
end

-- the party cell showing party<i> (a header child), else in move mode the
-- placeholder in its place
local function CellFor(i)
    local pc = ns.frames.party
    for _, h in ipairs(pc and pc.headers or {}) do
        for _, child in ipairs({ h:GetChildren() }) do
            if child:GetAttribute("unit") == "party" .. i and child:IsShown() then return child end
        end
    end
    if ns.db.locked == false and ns.MockFrames then
        local mf, n = ns.MockFrames("party")
        -- (move mode's column always shows five: you first)
        local m = mf and mf[i + 1]
        if m and m:IsShown() then return m end
    end
    return nil
end

local placePending = false
local function PlaceAll()
    local c = holder
    local cfg = Cfg()
    if not (c and cfg) then return end
    if InCombatLockdown() then placePending = true return end
    placePending = false
    local left = (cfg.side == "LEFT")
    for i, b in ipairs(c.buttons) do
        local cell = CellFor(i)
        b:ClearAllPoints()
        if cell then
            if left then b:SetPoint("RIGHT", cell, "LEFT", -(cfg.gap or 4), 0)
            else b:SetPoint("LEFT", cell, "RIGHT", cfg.gap or 4, 0) end
        else
            -- no cell to sit by (not in a party): out of sight, the rule
            -- keeps it hidden anyway
            b:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
    end
end
ns.PlacePartyTargets = PlaceAll

local function Spawn()
    local cfg = Cfg()
    if not (cfg and cfg.enabled) or holder or InCombatLockdown() then return holder end
    local c = CreateFrame("Frame", "ZacUF_partyTargets", UIParent)
    c.cfg = cfg
    c:SetSize(1, 1)
    c:SetPoint("CENTER")
    c.buttons = {}
    for i = 1, COUNT do
        local b = ns.NewUnitButton("oUF_ZacUFPartyTarget" .. i, UIParent, "party" .. i .. "target", cfg,
            { poll = true, watch = Rule(i) })
        c.buttons[i] = b
    end
    c.LeanRestyle = function(self)
        local unlocked = not ns.db.locked
        for i, b in ipairs(self.buttons) do
            b._zOn = cfg.enabled and true or false
            b._zWatch = Rule(i)
            if not InCombatLockdown() then b:SetSize(cfg.width, cfg.height) end
            ns.UI:FrameBackdrop(b, cfg.bgColor, cfg.borderColor)
            ns.StyleElements(b)
            ns.RegisterFrameEvents(b)
            ns.UpdateAuras(b)
            ns.UpdateIndicators(b)
            ns.UpdateHealth(b)
            ns.ExtraMover(b, "Target " .. i, unlocked and cfg.enabled)
        end
        PlaceAll()
    end
    holder = c
    -- the group changing (ZacUI's coalesced roster notice), the party
    -- header re-laying, a fight ending with a move waiting
    local Z = ns.ZUI or _G.ZacUI
    if Z and Z.Roster and Z.Roster.On then
        Z.Roster.On("ZacUF.partyTargets", function() C_Timer.After(0, PlaceAll) end)
    end
    local w = CreateFrame("Frame")
    w:RegisterEvent("PLAYER_REGEN_ENABLED")
    w:SetScript("OnEvent", function() if placePending then PlaceAll() end end)
    c._regen = w
    local pc = ns.frames.party
    if pc and pc.LeanRestyle then hooksecurefunc(pc, "LeanRestyle", function() C_Timer.After(0, PlaceAll) end) end
    if type(ns.UpdateMocks) == "function" then
        hooksecurefunc(ns, "UpdateMocks", function() if holder then C_Timer.After(0, PlaceAll) end end)
    end
    c:LeanRestyle()
    return c
end

local function Apply()
    local cfg, c = Cfg(), holder
    if not cfg then return end
    if cfg.enabled and not c then Spawn() return end
    if c and cfg.enabled then c:LeanRestyle() end
    if c and not cfg.enabled then
        for _, b in ipairs(c.buttons) do
            b._zOn = false
            if b.moverTex then b.moverTex:Hide() b.mover:Hide() end
            ns.WatchUnitButton(b, false)
        end
    end
end

-- ----------------------------------------------------------------------------
-- Samples: what each member of the preview's party is hitting
-- ----------------------------------------------------------------------------
local function TargetPeople(P)
    return {
        P.person({ name = "Onyxia", reaction = 2, pct = 0.64, maxHp = 1200000, buffs = {}, debuffs = {}, marker = 8 }),
        P.person({ name = "Onyxian Whelp", reaction = 2, pct = 0.30, maxHp = 3000, buffs = {}, debuffs = {} }),
        P.person({ name = "Holyclone", class = "PRIEST", isPlayer = true, friendly = true, pct = 0.95, buffs = {}, debuffs = {} }),
        P.person({ name = "Onyxia", reaction = 2, pct = 0.64, maxHp = 1200000, buffs = {}, debuffs = {}, marker = 8 }),
    }
end

-- the preview: the party column (you first) with each member's target beside
local function PreviewLayout(cfg, P)
    local pcfg = ns.db.party
    local targets = TargetPeople(P)
    local people = {}
    for i = 1, COUNT do people[i] = targets[i] end
    local party = {}
    local names = { P.playerName(), "Holyclone", "Stabbz", "Frostie", "Treehug" }
    local classes = { P.playerClass(), "PRIEST", "ROGUE", "MAGE", "DRUID" }
    for i = 1, 5 do
        local d = P.person({ name = names[i], class = classes[i], isPlayer = true, friendly = true,
            pct = 0.5 + i * 0.09, buffs = {}, debuffs = {} })
        d._cfg = pcfg
        d.cast = nil
        party[i] = d
        people[#people + 1] = d
    end
    local sp = pcfg.spacing or 4
    local colH = 5 * pcfg.height + 4 * sp
    local gap = cfg.gap or 4
    local total = pcfg.width + gap + cfg.width
    local left = (cfg.side == "LEFT")
    local x0, y0 = -total / 2, colH / 2
    local partyX = left and (x0 + cfg.width + gap) or x0
    local targetX = left and x0 or (x0 + pcfg.width + gap)
    return people, function(i)
        if i <= COUNT then
            -- beside party<i>: the column's i+1-th cell, centred on it
            local cy = y0 - i * (pcfg.height + sp) - pcfg.height / 2
            return targetX, cy + cfg.height / 2
        end
        local r = i - COUNT
        return partyX, y0 - (r - 1) * (pcfg.height + sp)
    end
end

if ns.RegisterExtraFrame and ns.defaults and ns.defaults.frames and ns.defaults.frames.targettarget then
    local def = ns.CopyDefaults(ns.defaults.frames.targettarget, {
        enabled = false, width = 104, height = 22, side = "RIGHT", gap = 4,
        point = "CENTER", x = 0, y = 0,
        power = false, name = true, healthText = "none", castbar = false, showBuffs = false, showDebuffs = false,
        nameAnchor = "CENTER", nameClassColor = false,
        raidIcon = true, raidAnchor = "LEFT", raidX = 0, raidY = 0, raidSize = 12, rangeFade = false,
    })
    def.portrait = nil
    ns.RegisterExtraFrame({ key = KEY, label = "Party targets", short = "Targets", after = "party",
        available = function() return ns.UFFeatureOn("uf_party_targets") end, defaults = def,
        spawn = Spawn, apply = Apply, layout = PreviewLayout })
end

-- ----------------------------------------------------------------------------
-- The page
-- ----------------------------------------------------------------------------
ns.UFPageCards[#ns.UFPageCards + 1] = function(L, tab, key, cfg, H)
    if key ~= KEY or not ns.ExtraFrame(KEY) then return end
    if tab == "general" then
        L:Card("Party targets")
        L:Desc("A small frame beside each party member's frame with who they are targeting; click it to target "
            .. "the same. Shown only while they have a target, and only where the party frames show.")
        H.Button(L, "Test on screen", 130, function()
            local c, PV = holder, ns.UFPreview
            if not (c and cfg.enabled) then
                if ns.Print then ns.Print("switch the party targets on first (Show this frame, above).") end
                return
            end
            local people = TargetPeople(PV.Kit())
            local list = {}
            for i, b in ipairs(c.buttons) do list[i] = { b, people[i] } end
            ns.TestExtra(list)
        end, "The preview's targets on your real frames for a few seconds (beside your party frames when you are in a party).")
        L:EndCard()
    elseif tab == "pos" then
        L:Card("Party targets layout")
        H.Drops(L, { label = "Side", items = { { text = "Right of the party frames", value = "RIGHT" },
            { text = "Left of the party frames", value = "LEFT" } },
            get = function() return cfg.side or "RIGHT" end, set = function(v) cfg.side = v end })
        H.Sliders(L, { label = "Gap", min = 0, max = 40, format = H.PX, get = function() return cfg.gap or 4 end,
            set = function(v) cfg.gap = v end })
        L:Desc("They sit beside the party frames wherever those are; the X / Y above is not used.")
        L:EndCard()
    end
end
