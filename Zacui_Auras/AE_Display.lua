-- AE_Display - a display's life: loaded or not, which of its states are
-- showing, the frames that show them, and the clock that moves timers.
-- Part of ZacUI (Zacui_Auras). Written for ZacUI.
--
-- Triggers (AE_Trigger*.lua) keep, per display and per trigger, a table
-- of states keyed by clone id ("" for a display with one), and call
-- E.Changed(id) after changing them. Everything visible follows from
-- that: which triggers count as active, which one supplies what is
-- shown, one frame per showing state.
local ns = _G.ZacUI
if not ns then return end
local E = ns.AuraEngine
if not E then return end

local R, Gp = E.Regions, E.Groups

E.states = {}        -- id -> { [triggerIndex] = { [cloneId] = state } }

-- ============================================================
-- BUILDING AND TEARING DOWN
-- ============================================================
local function TriggerCount(d)
    local n = 0
    for i, t in ipairs(type(d.triggers) == "table" and d.triggers or {}) do
        if type(t) == "table" then n = i end
    end
    return n
end
E.TriggerCount = TriggerCount

local function RegionFor(id, cloneId)
    cloneId = cloneId or ""
    if cloneId == "" then
        local r = E.regions[id]
        if not r then
            r = R.New(id, "")
            if not r then return nil end
            E.regions[id] = r
            local d = E.data[id]
            if d.parent and E.data[d.parent] then Gp.Join(d.parent, r) end
            if d.customText and d.customText ~= "" then
                r.customFn = E.Env.Function(id, d.customText, "custom text")
            end
        end
        return r
    end
    local list = E.clones[id]
    if not list then
        list = {}
        E.clones[id] = list
    end
    local r = list[cloneId]
    if not r then
        r = R.New(id, cloneId)
        if not r then return nil end
        list[cloneId] = r
        local d = E.data[id]
        if d.parent and E.data[d.parent] then Gp.Join(d.parent, r) end
        local main = E.regions[id] or RegionFor(id, "")
        r.customFn = main and main.customFn
    end
    return r
end
E.RegionFor = RegionFor

function E.Build(id)
    local d = E.data[id]
    if not d or E.IsGroup(d) then return end
    E.loaded[id] = true
    E.states[id] = E.states[id] or {}
    E.Env.AuraEnv(id)
    -- the groups above it exist and sit where they should
    local p = d.parent
    while p and E.data[p] do
        local g = Gp.Get(p)
        if g and not g.compiled then
            g.compiled = true
            Gp.Compile(g)
        end
        p = E.data[p].parent
    end
    local main = RegionFor(id, "")
    if main then E.Env.AuraEnv(id).region = main end
    E.Env.Init(id)
    if E.Triggers and E.Triggers.Register then E.Triggers.Register(id) end
    E.Changed(id)
end

local function HideRegion(r)
    if not r then return end
    if (r:IsShown() or r.showing) and not r.finishing then
        r.showing = nil
        if E.OnHide then E.OnHide(r) end
        if E.SubRegions then E.SubRegions.Hide(r) end
        -- a finish animation plays first; the region hides at its end
        r.finishing = true
        local function done()
            if r.finishing then
                r.finishing = nil
                r:Hide()
                Gp.Changed(r)
            end
        end
        if not (E.FinishThenHide and E.FinishThenHide(r, done)) then done() end
    end
end
E.HideRegion = HideRegion

function E.Unbuild(id)
    if not E.loaded[id] then return end
    E.loaded[id] = nil
    if E.Triggers and E.Triggers.Unregister then E.Triggers.Unregister(id) end
    HideRegion(E.regions[id])
    for _, r in pairs(E.clones[id] or {}) do HideRegion(r) end
    E.states[id] = {}
end

-- every display's load conditions, again
function E.CheckLoads()
    for id, d in pairs(E.data) do
        if not E.IsGroup(d) then
            local want = E.Load.Check(d.load)
            if want and not E.loaded[id] then
                local ok, err = pcall(E.Build, id)
                if not ok then E.Error(id, "build", err) end
            elseif not want and E.loaded[id] then
                local ok, err = pcall(E.Unbuild, id)
                if not ok then E.Error(id, "unload", err) end
            end
        end
    end
end

-- ============================================================
-- WHICH STATES SHOW
-- ============================================================
local function Active(triggerStates)
    if not triggerStates then return false end
    for _, st in pairs(triggerStates) do
        if st.show then return true end
    end
    return false
end

local function Logic(id, d, act)
    local t = d.triggers or {}
    -- WeakAuras' own default when the key is missing is "all" (its exports
    -- leave defaults out): the raid packs' "+ Combat" / "- Combat" texts are an
    -- event (3 s) AND an in/out of combat condition - read as "any" they
    -- stayed up the whole fight / the whole time out of combat.
    local mode = t.disjunctive or "all"
    local n = TriggerCount(d)
    if n == 0 then return false end
    if mode == "all" then
        for i = 1, n do if not act[i] then return false end end
        return true
    elseif mode == "custom" then
        local fn = E.customLogic and E.customLogic[id]
        if fn == nil then
            E.customLogic = E.customLogic or {}
            fn = E.Env.Function(id, t.customTriggerLogic, "trigger logic") or false
            E.customLogic[id] = fn
        end
        if fn then
            local args = {}
            for i = 1, n do args[i] = act[i] and true or false end
            local res = E.Env.Run(id, fn, nil, nil, nil, args)
            return res and true or false
        end
    end
    for i = 1, n do if act[i] then return true end end
    return false
end

local function FirstShown(triggerStates)
    if not triggerStates then return nil end
    local best
    for cid, st in pairs(triggerStates) do
        if st.show and (not best or tostring(cid) < tostring(best[1])) then best = { cid, st } end
    end
    return best and best[2] or nil
end

-- what custom text returns, for %c
local function Custom(r, st)
    if not r.customFn then return nil end
    local res = { E.Env.Run(r.id, r.customFn, st, E.states[r.id], r) }
    return res
end

local ticking = {}
local clock = CreateFrame("Frame")
clock:Hide()

local function NeedsClock(r, st)
    if r.d.customText and r.d.customTextUpdate == "update" then return true end
    if st and st.progressType == "timed" and not st.paused and st.expirationTime
        and st.expirationTime ~= math.huge and (tonumber(st.duration) or 0) > 0 then return true end
    return false
end

local function ShowState(id, r, st, ctx)
    r.ctx = ctx
    R.Apply(r, st)
    r.timedText = (r.regionType == "text") and E.Text.IsTimed(r.d.displayText)
    if r.finishing then
        -- back before its finish animation ended: it simply stays
        r.finishing = nil
        r:Hide()
    end
    if not (r:IsShown() or r.showing) then
        r.showing = true
        if not r.groupFrame or not (r.group and r.group.dynamic) then R.Place(r, r.d, st) end
        r:Show()
        Gp.Changed(r)
        if E.OnShow then E.OnShow(r) end
        if E.SubRegions then E.SubRegions.Apply(r, st) end
    elseif r.group and r.group.dynamic then
        Gp.Changed(r)
    end
    if E.Conditions and E.Conditions.Apply then E.Conditions.Apply(r) end
    -- a display on the mouse follows it every frame it is up, not only
    -- while a timer runs (Zac 2026-11-03: a pack's cursor circle stood
    -- still where the GCD ended - "this yellow circle ... stuck on my screen")
    local timed = NeedsClock(r, st) or r.timedSubs or r.timedText
    r._mouseOnly = (r.followMouse and not timed) or nil
    if timed or r.followMouse then
        ticking[r] = true
        clock:Show()
    else
        ticking[r] = nil
    end
end

function E.Changed(id)
    local d = E.data[id]
    if not d or not E.loaded[id] then return end
    local states = E.states[id] or {}
    local n = TriggerCount(d)
    local act = {}
    for i = 1, n do act[i] = Active(states[i]) end
    local on = Logic(id, d, act)
    local shown = {}
    if on then
        local mode = d.triggers and tonumber(d.triggers.activeTriggerMode) or -10
        local src
        if mode and mode >= 1 and act[mode] then src = mode end
        if not src then
            for i = 1, n do if act[i] then src = i break end end
        end
        if src then
            for cid, st in pairs(states[src] or {}) do
                if st.show then
                    local r = RegionFor(id, cid)
                    if r then
                        local trig = {}
                        for i = 1, n do
                            local ts = states[i]
                            trig[i] = ts and (ts[cid] or FirstShown(ts)) or nil
                        end
                        local ctx = { state = st, triggers = trig }
                        ctx.custom = Custom(r, st)
                        ShowState(id, r, st, ctx)
                        shown[r] = true
                    end
                end
            end
        end
    end
    -- what was shown has been shown: the next pass starts clean, and a
    -- state that went away is forgotten
    for i = 1, n do
        local ts = states[i]
        if ts then
            for cid, st in pairs(ts) do
                if type(st) ~= "table" or not st.show then ts[cid] = nil else st.changed = false end
            end
        end
    end
    local main = E.regions[id]
    if main and not shown[main] then HideRegion(main) ticking[main] = nil end
    for _, r in pairs(E.clones[id] or {}) do
        if not shown[r] then HideRegion(r) ticking[r] = nil end
    end
end

-- ============================================================
-- THE CLOCK
-- ============================================================
local acc = 0
clock:SetScript("OnUpdate", function(self, elapsed)
    acc = acc + elapsed
    local now = GetTime()
    local any = false
    local expired
    for r in pairs(ticking) do
        if r:IsShown() then
            any = true
            local st = r.state
            if st and st.autoHide and st.progressType == "timed" and st.expirationTime
                and st.expirationTime ~= math.huge and now >= st.expirationTime then
                st.show = false
                st.changed = true
                expired = expired or {}
                expired[r.id] = true
            else
                if r.customFn and r.d.customTextUpdate == "update" and acc >= 0.05 then
                    r.ctx = r.ctx or { state = st }
                    r.ctx.custom = Custom(r, st)
                end
                local ok, err
                if r._mouseOnly then
                    ok, err = pcall(R.Place, r, r.baseD or r.d, st)
                else
                    ok, err = pcall(R.Tick, r, now)
                end
                if not ok then E.Error(r.id, "update", err) ticking[r] = nil end
            end
        else
            ticking[r] = nil
        end
    end
    if acc >= 0.05 then acc = 0 end
    if expired then for id in pairs(expired) do E.Changed(id) end end
    if not any then self:Hide() end
end)

-- ============================================================
-- UNIT FRAMES (for displays anchored to one)
-- ============================================================
-- ZacUI's own raid frames answer first (ZacUF's public lookup: the raid /
-- party slot showing the unit, else the single); then the game's.
function E.UnitFrame(unit)
    local get = ns.UnitFrameFor or _G.ZacUF_GetUnitFrame
    if get then
        local ok, f = pcall(get, unit)
        if ok and f then return f end
    end
    local guid = UnitGUID(unit)
    if not guid then return nil end
    for i = 1, 40 do
        local f = _G["CompactRaidFrame" .. i]
        if f and f.unit and f:IsVisible() and UnitGUID(f.unit) == guid then return f end
    end
    for i = 1, 4 do
        local f = _G["CompactPartyFrameMember" .. i]
        if f and f.unit and f:IsVisible() and UnitGUID(f.unit) == guid then return f end
    end
    if UnitIsUnit(unit, "player") and PlayerFrame then return PlayerFrame end
    return nil
end

-- ============================================================
-- STARTUP
-- ============================================================
E.AtLogin(function()
    E.CheckLoads()
end)
