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

-- A NEW INSTALL STARTS WITH THE FOCUS FRAME ON (2026-11-15, Zac: "focus
-- frames not styled to match the style picked" - the game's own focus
-- frame beside ZacUI's player and target). Where the game has a focus,
-- ZacUI's focus frame is the one that wears the picked style, like the
-- target frame; switched off, the game's own shows. So a fresh install (or
-- Reset ZacUI) switches it on, once; an install from before keeps what it
-- has (off until ticked on the Unit frames page), and the focus-target
-- frame stays off for everyone until asked for.
local function FreshOn()
    local z = ns.ZUI or _G.ZacUI
    if not (z and (z.freshInstall == true or z.openSetupAfterReset == true)) then return end
    local f = ns.db and ns.db.frames and ns.db.frames.focus
    if type(f) ~= "table" or f._zFreshOn then return end
    f._zFreshOn = true
    f.enabled = true
end

-- AND ON WOW FOREVER UNDER THE 2004 OR BLIZZARD LOOK, ONCE (2026-11-15, Zac
-- again, his focus frame switched off in a save from before: "also the
-- focus frame is still forever style"). There the game's own focus frame
-- can only ever be the client's bronze one, whatever look is picked, so
-- the look's focus frame has to be ZacUI's: it is switched on the first
-- time such a look is worn (marked, so it happens once - switched off
-- again on the Unit frames page it stays off). WoW Forever's own look and
-- every other client keep what the save has: the game's frame is that look.
local function LookOn()
    if _G.ZACUI_IS_FOREVER ~= true then return end
    local kit = ns.Kit and ns.Kit.Active and ns.Kit.Active()
    if type(kit) ~= "table" or kit.id == "forever" then return end
    local f = ns.db and ns.db.frames and ns.db.frames.focus
    if type(f) ~= "table" or f._zLookOn then return end
    f._zLookOn = true
    f.enabled = true
end

local function Spawn()
    pcall(FreshOn)
    pcall(LookOn)
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
