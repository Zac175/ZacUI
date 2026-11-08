-- ============================================================================
-- Zacui_UnitFrames - Extras.lua
-- The frames some games have and others do not (feature cluster 2,
-- 2026-11-07): the focus and focus-target frames, the boss frames, and the
-- small sets that ride beside the groups. This file is their common ground:
--   * ns.RegisterExtraFrame(e)  one frame key: its defaults (put in only
--     where it runs, so a game without it keeps a save byte for byte as it
--     was), its spawn, its preview sample or layout, its place in the
--     page's "Settings for" list, the move dialog and the preview's modes
--   * ns.NewUnitButton          a secure unit button of the frames' own
--     make (Units.lua's handler, the elements, click to target), for the
--     frames that come in sets
--   * ns.ExtraMover / ns.TestExtra   move mode's tint and label on such a
--     button, and a Test that paints the preview's samples on the live
--     frames for a few seconds
--   * the page's own cards for them (ns.UFPageCards, Options.lua calls)
-- Every one is off by default: an existing save gains them switched off and
-- nothing is made, registered or ticking until one is switched on.
-- Part of Zacui_UnitFrames; load order is set by the TOC (after the frames'
-- code, before Preview / Options / MoveDialog, which read the list).
-- ============================================================================
local ADDON, ns = ...

local function Z() return ns.ZUI or _G.ZacUI end

ns.UF_EXTRA_FRAMES = ns.UF_EXTRA_FRAMES or {}   -- { key, label, short, after, moveDialog, sample, layout, ... }
ns.ExtraSpawns     = ns.ExtraSpawns or {}       -- run once at login after the frames (Core.lua)
ns.UFPageCards     = ns.UFPageCards or {}       -- function(L, tab, key, cfg, H): the page's own cards

-- ----------------------------------------------------------------------------
-- Does this game have it? The feature table (Core_Flavor) first - that is
-- also what the developer's game-version override changes - then the
-- client itself: an event the client does not know means the unit is not
-- there, whatever the table says (a TBC run simulated on Era).
-- ----------------------------------------------------------------------------
function ns.UFFeatureOn(id)
    local z = Z()
    if z and z.FeatureOn then return z.FeatureOn(id) and true or false end
    return true
end

function ns.ClientEvent(ev)
    local eu = C_EventUtils
    if eu and eu.IsEventValid then
        local ok, v = pcall(eu.IsEventValid, ev)
        return (ok and v) and true or false
    end
    return true   -- a client without the check: the feature table decides
end

-- a unit token the client takes without complaint (UnitExists never errors
-- on a real token; an unknown one may on some clients)
function ns.ClientUnit(token)
    if type(UnitExists) ~= "function" then return false end
    return (pcall(UnitExists, token))
end

-- ----------------------------------------------------------------------------
-- The registry
-- ----------------------------------------------------------------------------
local byKey = {}
function ns.ExtraFrame(key) return byKey[key] end

-- e = { key, label, short (the preview's mode button), after (a key the
-- page's list puts it behind), available() (runs on this game),
-- defaults (the frame's settings table), blizzard ({ key = true }: the
-- game's own frame to hide while ours is on), spawn(), moveDialog,
-- sample(P) (a person for a single sample) or layout(cfg, P) (people and
-- where they go, for a set) }
function ns.RegisterExtraFrame(e)
    if e.available and not e.available() then return false end
    byKey[e.key] = e
    local list = ns.UF_EXTRA_FRAMES
    list[#list + 1] = e
    -- (the match pass's numbers for this frame land with the overlay at
    -- login: Config.lua's ns.ApplyMatchOverlay, ZacUI's look only)
    if e.defaults and ns.defaults and ns.defaults.frames then ns.defaults.frames[e.key] = e.defaults end
    if e.blizzard and ns.defaults and ns.defaults.blizzard then
        for k, v in pairs(e.blizzard) do ns.defaults.blizzard[k] = v end
    end
    if e.spawn then ns.ExtraSpawns[#ns.ExtraSpawns + 1] = e.spawn end
    return true
end

-- a list of frame keys with the extras put in (after the key each names,
-- else at the end); labels filled in `labels` when given
function ns.WithExtraKeys(keys, labels, filter)
    local out = {}
    for _, k in ipairs(keys) do out[#out + 1] = k end
    for _, e in ipairs(ns.UF_EXTRA_FRAMES) do
        if not filter or filter(e) then
            local at = #out + 1
            if e.after then
                for i, k in ipairs(out) do if k == e.after then at = i + 1 end end
            end
            table.insert(out, at, e.key)
            if labels then labels[e.key] = e.label end
        end
    end
    return out
end

-- a copy of a defaults table (one level of tables deep, as the frames' are).
-- Each copy remembers what it was copied from and what it set itself, so
-- the match overlay decided at login (Config.lua) reaches it exactly as
-- if it had been copied after the overlay.
ns.DEFAULT_COPIES = setmetatable({}, { __mode = "k" })
function ns.CopyDefaults(src, over)
    local t = {}
    for k, v in pairs(src) do
        if type(v) == "table" then
            local c = {}
            for k2, v2 in pairs(v) do c[k2] = v2 end
            t[k] = c
        else
            t[k] = v
        end
    end
    for k, v in pairs(over or {}) do t[k] = v end
    ns.DEFAULT_COPIES[t] = { src = src, over = over or {} }
    return t
end

-- ----------------------------------------------------------------------------
-- The game's own frame, hidden while ours is on (Blizzard.lua's way: out of
-- combat, or when the fight ends)
-- ----------------------------------------------------------------------------
local pendingKill = {}
local killWaiter
function ns.HideGameFrames(names)
    local kill = ns.KillBlizzardFrame
    if not kill then return end
    if InCombatLockdown() then
        for _, n in ipairs(names) do pendingKill[#pendingKill + 1] = n end
        if not killWaiter then
            killWaiter = CreateFrame("Frame")
            killWaiter:SetScript("OnEvent", function(self)
                self:UnregisterAllEvents()
                local list = pendingKill
                pendingKill = {}
                for _, n in ipairs(list) do kill(n) end
            end)
        end
        killWaiter:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    for _, n in ipairs(names) do kill(n) end
end

-- ----------------------------------------------------------------------------
-- A secure unit button for a frame of a set
-- ----------------------------------------------------------------------------
-- opts: events (more events to listen to; one the client lacks is
-- skipped), poll (the target-of-target's 0.2 s poll while shown, for a
-- unit with no change event), menu = false (both buttons target), watch
-- (a visibility rule for RegisterAttributeDriver instead of the unit watch)
function ns.NewUnitButton(name, parent, unit, cfg, opts)
    opts = opts or {}
    local f = CreateFrame("Button", name, parent or UIParent, "SecureUnitButtonTemplate,BackdropTemplate")
    f.unit, f.cfg = unit, cfg
    f:SetSize(cfg.width, cfg.height)
    ns.UI:FrameBackdrop(f, cfg.bgColor, cfg.borderColor)
    f:SetClampedToScreen(true)
    f:SetAttribute("unit", unit)
    f:SetAttribute("*type1", "target")
    f:SetAttribute("*type2", (opts.menu == false) and "target" or "togglemenu")
    f:RegisterForClicks("AnyUp")
    -- click-cast addons (Clique and the like) pick it up like every frame
    ClickCastFrames = ClickCastFrames or {}
    ClickCastFrames[f] = true

    ns.BuildElements(f)
    ns.RegisterFrameEvents(f)
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    for _, ev in ipairs(opts.events or {}) do
        if ns.ClientEvent(ev) then pcall(f.RegisterEvent, f, ev) end
    end
    f:SetScript("OnEvent", ns.UnitOnEvent)
    f:SetScript("OnShow", function(self) ns.UpdateAll(self) end)
    f:HookScript("OnEnter", function(self) self.hovered = true;  ns.UpdatePvP(self) end)
    f:HookScript("OnLeave", function(self) self.hovered = false; ns.UpdatePvP(self) end)
    if opts.poll and ns.UnitPollOnUpdate then
        f.elapsed = 0
        f:SetScript("OnUpdate", ns.UnitPollOnUpdate)
    end
    f._zWatch = opts.watch
    ns.WatchUnitButton(f, true)
    return f
end

-- the button shows with its unit (or by its rule); off: hidden, no watch.
-- Out of combat only (both are protected on a secure button).
function ns.WatchUnitButton(f, on)
    if InCombatLockdown() then return false end
    if f._zWatch then
        if on then RegisterAttributeDriver(f, "state-visibility", f._zWatch)
        else UnregisterAttributeDriver(f, "state-visibility") end
    else
        if on then RegisterUnitWatch(f) else UnregisterUnitWatch(f) end
    end
    if not on then f:Hide() end
    return true
end

-- Move mode on a set's button: the frames' own tint and a label, every
-- button shown (no watch) so the set can be placed; off puts the watch back.
function ns.ExtraMover(f, label, unlocked)
    if not f.moverTex then
        local host = f.Overlay or f
        local m = host:CreateTexture(nil, "OVERLAY")
        m:SetAllPoints(f)
        m:SetColorTexture(0.85, 0.65, 0.25, 0.15)
        f.moverTex = m
        f.mover = ns.UI:FS(host, 11)
        f.mover:SetPoint("CENTER")
        f.mover:SetTextColor(1, 0.82, 0)
    end
    f.mover:SetText(label)
    if InCombatLockdown() then return end
    if unlocked then
        ns.WatchUnitButton(f, false)
        f:Show()
        f.moverTex:Show(); f.mover:Show()
        f:SetBackdropBorderColor(0.85, 0.65, 0.25, 1)
    else
        f.moverTex:Hide(); f.mover:Hide()
        f:SetBackdropBorderColor(ns.UI:FrameBorderColor(f, f.cfg.borderColor))
        if f._zOn ~= false then ns.WatchUnitButton(f, true) end
        ns.UpdateAll(f)
    end
end

-- ----------------------------------------------------------------------------
-- Test: the preview's samples painted on the live frames for a few seconds
-- (out of combat: showing a secure frame is protected), then the frames go
-- back to their units. pairs: { { frame, person }, ... }
-- ----------------------------------------------------------------------------
local TEST_SECONDS = 8
local testing
function ns.TestExtra(pairsList)
    if InCombatLockdown() then
        if ns.Print then ns.Print("the test waits until combat ends.") end
        return false
    end
    local PV = ns.UFPreview
    if not (PV and PV.Fill) then return false end
    local token = {}
    testing = token
    local shown = {}
    for _, p in ipairs(pairsList) do
        local f, d = p[1], p[2]
        if f and d then
            ns.WatchUnitButton(f, false)
            f:Show()
            local ok = pcall(PV.Fill, f, d)
            if ok and d.cast and f.cfg and f.cfg.castbar and ns.CastbarStart then
                local now = GetTime()
                pcall(ns.CastbarStart, f, d.cast[1], d.cast[2], now, now + (d.cast[3] or 2), false, false)
            end
            shown[#shown + 1] = f
        end
    end
    C_Timer.After(TEST_SECONDS, function()
        if testing ~= token then return end
        testing = nil
        local function back()
            for _, f in ipairs(shown) do
                f._previewPerson = nil
                if f.Castbar then ns.CastbarStopMotion(f.Castbar) f.Castbar.endT = nil f.Castbar:Hide() end
                f:SetAlpha(1)
                if ns.db.locked ~= false and f._zOn ~= false then
                    ns.WatchUnitButton(f, true)
                    -- (the watch shows it again the moment its unit is there)
                    if not (f.unit and UnitExists(f.unit)) then f:Hide() end
                elseif f._zOn == false then f:Hide() end
                ns.UpdateAll(f)
            end
        end
        if InCombatLockdown() then
            local w = CreateFrame("Frame")
            w:RegisterEvent("PLAYER_REGEN_ENABLED")
            w:SetScript("OnEvent", function(self) self:UnregisterAllEvents() back() end)
        else
            back()
        end
    end)
    return true
end
function ns.ExtraTesting() return testing ~= nil end

-- ----------------------------------------------------------------------------
-- Live: a frame of these switched on is made there and then (out of
-- combat; else when the fight ends), one switched off is put away. The
-- frames from before (player, target...) still wait for a reload.
-- ----------------------------------------------------------------------------
local applyWaiter
local function ApplyExtras()
    if InCombatLockdown() then
        if not applyWaiter then
            applyWaiter = CreateFrame("Frame")
            applyWaiter:SetScript("OnEvent", function(self)
                self:UnregisterAllEvents()
                ApplyExtras()
            end)
        end
        applyWaiter:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    for _, e in ipairs(ns.UF_EXTRA_FRAMES) do
        if e.apply then pcall(e.apply) end
    end
end
ns.ApplyExtras = ApplyExtras

if type(ns.ApplySettings) == "function" then
    hooksecurefunc(ns, "ApplySettings", function()
        if #ns.UF_EXTRA_FRAMES > 0 then ApplyExtras() end
    end)
end

-- ----------------------------------------------------------------------------
-- The page's cards (Options.lua calls this on the General and Position
-- tabs with its own helpers in H)
-- ----------------------------------------------------------------------------
function ns.ExtraPageCards(L, tab, key, cfg, H)
    for _, fn in ipairs(ns.UFPageCards) do
        local ok, err = pcall(fn, L, tab, key, cfg, H)
        if not ok and ns.Print then ns.Print("unit frames page: " .. tostring(err)) end
    end
end

-- ----------------------------------------------------------------------------
-- Painted stand-ins on screen (move mode, a Test) for a set whose real
-- frames are a secure header's children (the tank frames): plain sample
-- frames (the preview's own, Preview.lua) hung off `owner`, each painted
-- as a person, laid out by place(i) -> x, y from the owner's top left.
-- ----------------------------------------------------------------------------
function ns.ShowStandIns(owner, people, place, cfg)
    local PV = ns.UFPreview
    if not (PV and PV.NewSample and owner) then return end
    owner._zStandIns = owner._zStandIns or {}
    local list = owner._zStandIns
    for i, d in ipairs(people) do
        local f = list[i]
        if not f then
            f = PV.NewSample(UIParent)
            f:SetFrameStrata("MEDIUM")
            list[i] = f
        end
        PV.Style(f, d._cfg or cfg)
        pcall(PV.Fill, f, d)
        local x, y = place(i)
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", owner, "TOPLEFT", x, y)
        f:Show()
    end
    for i = #people + 1, #list do list[i]:Hide() end
end
function ns.HideStandIns(owner)
    for _, f in ipairs(owner and owner._zStandIns or {}) do
        if f.Castbar then ns.CastbarStopMotion(f.Castbar) f.Castbar:Hide() end
        f:Hide()
    end
end
