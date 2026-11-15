-- ============================================================================
-- Zacui_UnitFrames - Focus.lua
-- The focus frame and the focus-target frame, where the game has a focus
-- (TBC, Forever, Retail; Classic Era has none, so on Era nothing here runs
-- and no setting is added). They are ordinary single frames - Units.lua
-- makes them, the page sets them up like the target frame, the preview
-- shows a sample, Edit Mode and the move dialog move them, portraits and
-- the cast bar come with the frame - with the target frame's defaults
-- (switched off) and a spot of their own above it.
-- The removal in the cfgVersion-7 migration stays as it was (that dropped
-- an old ZacUF copy); Core.lua fills the frame back in after it.
-- Part of Zacui_UnitFrames; load order is set by the TOC (after Extras).
-- ============================================================================
local ADDON, ns = ...

local function Available()
    return ns.UFFeatureOn("uf_focus") and ns.ClientEvent("PLAYER_FOCUS_CHANGED") and ns.ClientUnit("focus")
end

local KEYS = { "focus", "focustarget" }

-- the game's own focus frame goes while ours is on (its target-of-focus
-- and cast bar with it)
local function HideGame()
    local b, f = ns.db.blizzard, ns.db.frames.focus
    if b and b.focus ~= false and f and f.enabled then ns.HideGameFrames({ "FocusFrame" }) end
end

local function Spawn()
    for _, k in ipairs(KEYS) do
        local cfg = ns.db.frames[k]
        if cfg and cfg.enabled and not ns.frames[k] then ns.SpawnUnit(k) end
    end
    HideGame()
end

-- live: switched on = made now; switched off = put away (no watch, hidden)
local function Apply()
    if not ns.db then return end
    for _, k in ipairs(KEYS) do
        local cfg, f = ns.db.frames[k], ns.frames[k]
        if cfg and cfg.enabled and not f then
            ns.SpawnUnit(k)
        elseif f then
            f._zOn = cfg and cfg.enabled and true or false
            if not f._zOn then ns.WatchUnitButton(f, false) end
        end
    end
    HideGame()
end

-- the preview's samples (and the Test): a caster you keep an eye on, and
-- who it is hitting
local function FocusSample(P)
    local A = P.A
    return P.person({ name = "Shade of Aran", reaction = 2, pct = 0.71, maxHp = 820000,
        ptoken = "MANA", ptype = 0, pp = 64, maxPp = 100,
        portrait = P.ICON .. "Spell_Frost_FrostBolt02", creature = 16524,
        buffs = {}, debuffs = { P.aura(A.sunder, "player", 3), P.aura(A.faerie) },
        combat = true, marker = 2,
        cast = { "Arcane Missiles", P.ICON .. "Spell_Nature_StarFall", 4.0 } })
end
local function FocusTargetSample(P)
    return P.person({ name = "Holyclone", class = "PRIEST", isPlayer = true, friendly = true, pct = 0.54,
        buffs = {}, debuffs = {}, marker = nil,
        cast = { "Greater Heal", P.ICON .. "Spell_Holy_GreaterHeal", 2.5 } })
end

local function Defaults(from, over)
    local d = ns.defaults and ns.defaults.frames and ns.defaults.frames[from]
    if not d then return nil end
    return ns.CopyDefaults(d, over)
end

if ns.RegisterExtraFrame then
    -- (Defaults first: Config.lua's target table is the model)
    local focusDef = Defaults("target", { enabled = false, point = "CENTER", x = 240, y = -60 })
    local fotDef   = Defaults("targettarget", { enabled = false, point = "CENTER", x = 400, y = -60 })
    if focusDef and fotDef then
        ns.RegisterExtraFrame({ key = "focus", label = "Focus", short = "Focus", after = "pet",
            available = Available, defaults = focusDef, blizzard = { focus = true },
            spawn = Spawn, apply = Apply, moveDialog = true, sample = FocusSample })
        ns.RegisterExtraFrame({ key = "focustarget", label = "Focus target", short = "Focus target", after = "focus",
            available = Available, defaults = fotDef, moveDialog = true, sample = FocusTargetSample })
    end
end

-- the page: a card of its own on the General tab for either frame
ns.UFPageCards[#ns.UFPageCards + 1] = function(L, tab, key, cfg, H)
    if tab ~= "general" or (key ~= "focus" and key ~= "focustarget") or not ns.ExtraFrame(key) then return end
    L:Card("Focus")
    L:Desc("Set a focus with /focus (or the unit menu); /clearfocus clears it. The focus frame shows it like the "
        .. "target frame, the focus-target frame who it is targeting. Both are off until you switch them on; "
        .. "switching one on or off takes effect at once (out of combat).")
    H.Checks(L, {
        { "Focus frame", function() return ns.db.frames.focus.enabled end, function(v) ns.db.frames.focus.enabled = v end },
        { "Focus-target frame", function() return ns.db.frames.focustarget.enabled end, function(v) ns.db.frames.focustarget.enabled = v end },
        { "Hide the game's focus frame", function() return ns.db.blizzard.focus ~= false end,
          function(v) ns.db.blizzard.focus = v and true or false end,
          "While ZacUI's focus frame is on. Showing the game's again takes a reload." },
    }, 3)
    H.Button(L, "Test on screen", 130, function()
        local PV, list = ns.UFPreview, {}
        local P = PV and PV.Kit and PV.Kit()
        if not P then return end
        if ns.frames.focus then list[#list + 1] = { ns.frames.focus, FocusSample(P) } end
        if ns.frames.focustarget then list[#list + 1] = { ns.frames.focustarget, FocusTargetSample(P) } end
        if #list == 0 then
            if ns.Print then ns.Print("switch the focus frame on first (General tab).") end
            return
        end
        ns.TestExtra(list)
    end, "Shows the preview's sample focus on your real frames for a few seconds.")
    L:EndCard()
end
