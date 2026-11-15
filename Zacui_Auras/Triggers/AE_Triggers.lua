-- AE_Triggers - how a display's triggers are wired up, and the custom
-- (Lua) trigger kinds: event, status and the trigger-state updater.
-- Part of ZacUI (Zacui_Auras). Written for ZacUI.
--
-- Each trigger kind registers a handler in E.TriggerTypes[type]:
--   handler.Add(ctx)    start listening; ctx = { id, index, trigger,
--                       untrigger, states } (states: cloneId -> state)
--   handler.Remove(ctx) stop
-- A handler changes ctx.states and calls E.Changed(ctx.id).
--
-- The event lists custom triggers name ("UNIT_AURA:player, CLEU:SPELL_CAST_SUCCESS,
-- TRIGGER:2, WA_MY_EVENT, STATUS") are read by Events() below.
local ns = _G.ZacUI
if not ns then return end
local E = ns.AuraEngine
if not E then return end

local Tr = {}
E.Triggers = Tr
E.TriggerTypes = E.TriggerTypes or {}
local Types = E.TriggerTypes

local live = {}        -- id -> { ctx, ... }
Tr.live = live

function Tr.Register(id)
    Tr.Unregister(id)
    local d = E.data[id]
    if not d then return end
    local list = {}
    live[id] = list
    E.states[id] = E.states[id] or {}
    for i, t in ipairs(type(d.triggers) == "table" and d.triggers or {}) do
        if type(t) == "table" then
            local tr = type(t.trigger) == "table" and t.trigger or {}
            local states = {}
            E.states[id][i] = states
            local ctx = { id = id, index = i, trigger = tr, untrigger = type(t.untrigger) == "table" and t.untrigger or {},
                states = states, key = id .. "\31" .. i }
            local h = Types[tr.type]
            if h then
                ctx.handler = h
                local ok, err = pcall(h.Add, ctx)
                if not ok then E.Error(id, "trigger " .. i, err) end
            else
                E.Error(id, "trigger " .. i, "trigger type '" .. tostring(tr.type) .. "' is not supported yet")
            end
            list[i] = ctx
        end
    end
    -- triggers that asked for a first look (STATUS) get it now
    for _, ctx in pairs(list) do
        if ctx.wantsStatus and ctx.handler and ctx.handler.Fire then
            pcall(ctx.handler.Fire, ctx, "STATUS")
        end
    end
end

function Tr.Unregister(id)
    local list = live[id]
    if not list then return end
    for _, ctx in pairs(list) do
        if ctx.handler and ctx.handler.Remove then pcall(ctx.handler.Remove, ctx) end
        if ctx.subs then
            for _, ev in ipairs(ctx.subs) do E.Off(ev, ctx.key) end
        end
    end
    live[id] = nil
end

-- another trigger of the same display changed: "TRIGGER:n" listeners
function Tr.Notify(id, index)
    local list = live[id]
    if not list then return end
    for _, ctx in pairs(list) do
        if ctx.triggerWatch and ctx.triggerWatch[index] and ctx.handler.Fire then
            ctx.handler.Fire(ctx, "TRIGGER", index, E.states[id][index])
        end
    end
end

-- ============================================================
-- THE EVENT LIST OF A CUSTOM TRIGGER
-- ============================================================
-- returns { [event] = filter } where filter is nil (all), a set of units
-- ("UNIT_AURA:player:target") or a set of combat log sub-events
function Tr.Events(s)
    local out = {}
    if type(s) ~= "string" then return out end
    for token in s:gmatch("[^,%s]+") do
        local parts = {}
        for p in token:gmatch("[^:]+") do parts[#parts + 1] = p end
        local ev = parts[1]
        if ev then
            if ev == "CLEU" or ev == "COMBAT_LOG_EVENT_UNFILTERED" then ev = "COMBAT_LOG_EVENT_UNFILTERED" end
            local filter = out[ev]
            if #parts > 1 then
                if filter == nil and out[ev] == nil then filter = {} end
                if type(filter) == "table" then
                    for i = 2, #parts do filter[parts[i]] = true end
                end
            else
                filter = false        -- everything
            end
            if out[ev] == false then filter = false end
            out[ev] = filter
        end
    end
    return out
end

-- does this firing pass the token's filter?
local function Passes(ev, filter, ...)
    if not filter then return true end
    if ev == "COMBAT_LOG_EVENT_UNFILTERED" then
        local sub = select(2, ...)
        return filter[sub] and true or false
    end
    local unit = ...
    return type(unit) == "string" and filter[unit] and true or false
end
Tr.Passes = Passes

-- subscribes ctx to every event in its list; fire(ctx, event, ...) runs
-- on each that passes. "STATUS" and "OPTIONS" are the engine's own.
function Tr.Listen(ctx, list, fire)
    ctx.subs = ctx.subs or {}
    for ev, filter in pairs(list) do
        if ev == "STATUS" then
            ctx.wantsStatus = true
        elseif ev == "TRIGGER" then
            ctx.triggerWatch = ctx.triggerWatch or {}
            if type(filter) == "table" then
                for n in pairs(filter) do ctx.triggerWatch[tonumber(n) or n] = true end
            end
        elseif ev == "FRAME_UPDATE" then
            ctx.everyFrame = true
            Tr.EveryFrame(ctx, true)
        elseif ev ~= "OPTIONS" then
            ctx.subs[#ctx.subs + 1] = ev
            E.On(ev, ctx.key, function(event, ...)
                if Passes(event, filter, ...) then fire(ctx, event, ...) end
            end)
        end
    end
end

-- ============================================================
-- EVERY FRAME (custom "status" triggers set to update, FRAME_UPDATE)
-- ============================================================
local frameList = {}
local frameDriver = CreateFrame("Frame")
frameDriver:Hide()
function Tr.EveryFrame(ctx, on)
    frameList[ctx] = on and true or nil
    if on then frameDriver:Show() end
end
frameDriver:SetScript("OnUpdate", function(self)
    local any = false
    for ctx in pairs(frameList) do
        if live[ctx.id] and live[ctx.id][ctx.index] == ctx then
            any = true
            ctx.handler.Fire(ctx, "FRAME_UPDATE")
        else
            frameList[ctx] = nil
        end
    end
    if not any then self:Hide() end
end)

-- the engine's "after the loading screen" event, which many packs wait on
E.On("PLAYER_ENTERING_WORLD", "triggers.delayedPEW", function()
    C_Timer.After(0.8, function() E.Dispatch("WA_DELAYED_PLAYER_ENTERING_WORLD") end)
end)

-- ============================================================
-- CUSTOM TRIGGERS
-- ============================================================
local Custom = {}
Types.custom = Custom

-- the optional "what to show" functions of an event / status trigger
local function InfoFns(ctx)
    local id, tr = ctx.id, ctx.trigger
    local V = E.Env
    ctx.fn = V.Function(id, tr.custom, "trigger " .. ctx.index)
    ctx.fnUntrigger = (tr.custom_hide == "custom") and V.Function(id, ctx.untrigger.custom, "untrigger " .. ctx.index) or nil
    ctx.fnDuration = V.Function(id, tr.customDuration, "duration " .. ctx.index)
    ctx.fnName = V.Function(id, tr.customName, "name " .. ctx.index)
    ctx.fnIcon = V.Function(id, tr.customIcon, "icon " .. ctx.index)
    ctx.fnStacks = V.Function(id, tr.customStacks, "stacks " .. ctx.index)
    ctx.fnTexture = V.Function(id, tr.customTexture, "texture " .. ctx.index)
end

-- fills one state from the info functions
local function Info(ctx, st)
    local id = ctx.id
    local V = E.Env
    local region = E.regions[id]
    if ctx.fnDuration then
        -- duration, expirationTime for a timer; value, total, true for a
        -- plain amount
        local a, b, c = V.Run(id, ctx.fnDuration, st, ctx.states, region)
        if c then
            st.progressType, st.value, st.total = "static", tonumber(a) or 0, tonumber(b) or 0
        elseif tonumber(a) then
            st.progressType, st.duration = "timed", tonumber(a)
            st.expirationTime = tonumber(b) or math.huge
        end
    elseif ctx.trigger.custom_hide == "timed" then
        st.progressType = "timed"
        st.duration = tonumber(ctx.trigger.duration) or 0
        if not st.expirationTime then st.expirationTime = GetTime() + st.duration end
        st.autoHide = true
    end
    if ctx.fnName then st.name = V.Run(id, ctx.fnName, st, ctx.states, region) end
    if ctx.fnIcon then st.icon = V.Run(id, ctx.fnIcon, st, ctx.states, region) end
    if ctx.fnStacks then st.stacks = V.Run(id, ctx.fnStacks, st, ctx.states, region) end
    if ctx.fnTexture then st.texture = V.Run(id, ctx.fnTexture, st, ctx.states, region) end
end

local function Show(ctx, on)
    local states = ctx.states
    local st = states[""]
    if on then
        if not st then
            st = {}
            states[""] = st
        end
        local fresh = not st.show
        st.show, st.changed = true, true
        if fresh then st.expirationTime = nil end
        Info(ctx, st)
    elseif st and st.show then
        st.show, st.changed = false, true
    else
        return false
    end
    return true
end

function Custom.Fire(ctx, event, ...)
    local id, tr = ctx.id, ctx.trigger
    local V = E.Env
    local region = E.regions[id]
    local kind = tr.custom_type or "event"
    local changed = false
    if kind == "stateupdate" then
        if not ctx.fn then return end
        local res = V.Run(id, ctx.fn, nil, ctx.states, region, ctx.states, event, ...)
        changed = res and true or false
        if changed then
            -- the engine's own housekeeping on what the code left
            for cid, st in pairs(ctx.states) do
                if type(st) ~= "table" then
                    ctx.states[cid] = nil
                elseif st.show == false and not st.changed then
                    ctx.states[cid] = nil
                else
                    st.cloneId = cid
                    if st.progressType == nil then
                        if st.duration and st.expirationTime then st.progressType = "timed"
                        elseif st.value and st.total then st.progressType = "static" end
                    end
                end
            end
        end
    elseif kind == "status" then
        if not ctx.fn then return end
        local res = V.Run(id, ctx.fn, ctx.states[""], ctx.states, region, event, ...)
        changed = Show(ctx, res and true or false)
        if not changed and res and ctx.states[""] then
            -- still showing: its name, icon and timer may have moved on
            Info(ctx, ctx.states[""])
            changed = true
        end
    else
        -- event: the trigger function shows it, the untrigger (or the
        -- timer) hides it
        local st = ctx.states[""]
        local shownNow = st and st.show
        if ctx.fn then
            local res = V.Run(id, ctx.fn, st, ctx.states, region, event, ...)
            if res then
                changed = Show(ctx, true)
                -- a new firing restarts a timed one
                if tr.custom_hide == "timed" and ctx.states[""] then
                    local s = ctx.states[""]
                    s.duration = tonumber(tr.duration) or s.duration or 0
                    s.expirationTime = GetTime() + (s.duration or 0)
                    s.progressType, s.autoHide = "timed", true
                end
                shownNow = true
            end
        end
        if not changed and shownNow and ctx.fnUntrigger then
            local un = V.Run(id, ctx.fnUntrigger, st, ctx.states, region, event, ...)
            if un then changed = Show(ctx, false) end
        end
    end
    if changed then
        E.Changed(id)
        Tr.Notify(id, ctx.index)
    end
end

function Custom.Add(ctx)
    local tr = ctx.trigger
    InfoFns(ctx)
    if tr.custom_type == "stateupdate" then
        -- clones (one display, many states) come from the code itself
    end
    local list = Tr.Events(tr.events or tr.event)
    if tr.custom_type == "status" then
        ctx.wantsStatus = true
        if tr.check == "update" then
            ctx.everyFrame = true
            Tr.EveryFrame(ctx, true)
        end
    end
    -- the untrigger may listen to more events than the trigger
    if tr.custom_hide == "custom" and ctx.untrigger.events then
        for ev, filter in pairs(Tr.Events(ctx.untrigger.events)) do
            if list[ev] == nil then list[ev] = filter end
        end
    end
    Tr.Listen(ctx, list, Custom.Fire)
end

function Custom.Remove(ctx)
    if ctx.everyFrame then Tr.EveryFrame(ctx, false) end
end
