-- AE_Conditions - "when this is true, look like that": a display's
-- conditions list.
-- Part of ZacUI (Zacui_Auras). Written for ZacUI.
--
-- conditions[i] = { check = { trigger, variable, op, value, checks },
--                   changes = { { property, value }, ... },
--                   linked = true when it is an "else if" of the one above }
--   trigger n    a state field of trigger n (expirationTime compares the
--                time left; a yes/no field compares with value 1/0)
--   trigger -1   a global check: incombat, hastarget, attackabletarget,
--                rangecheck, customcheck (code, re-run on the events in
--                its op), alwaystrue
--   trigger -2   AND / OR over checks
-- Conditions are read top to bottom; a later one wins a property. A
-- property no condition sets goes back to the display's own value. The
-- one-off changes (sound, chat, custom code, a glow on another frame)
-- happen when their condition turns true.
--
-- What a trigger's field is (a number, a timer, text...) comes from the
-- trigger code when it says (E.ConditionTemplate); otherwise it is read
-- from the check itself.
local ns = _G.ZacUI
if not ns then return end
local E = ns.AuraEngine
if not E then return end

local C = {}
E.Conditions = C
local Color = E.Color

-- the global checks and the events that can change them
C.GLOBALS = {
    incombat = { "bool", { "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED" } },
    hastarget = { "bool", { "PLAYER_TARGET_CHANGED", "PLAYER_ENTERING_WORLD" } },
    attackabletarget = { "bool", { "PLAYER_TARGET_CHANGED", "UNIT_FACTION" } },
    rangecheck = { "range", { "RANGE_POLL" } },
    customcheck = { "customcheck" },
    alwaystrue = { "alwaystrue" },
}
C.OPS = { ["=="] = true, ["~="] = true, ["<"] = true, ["<="] = true, [">"] = true, [">="] = true,
    ["find('%s')"] = true, ["match('%s')"] = true }

-- ============================================================
-- CHECKS
-- ============================================================
local function Op(a, op, b)
    if op == "find('%s')" then return type(a) == "string" and type(b) == "string" and a:find(b, 1, true) ~= nil end
    if op == "match('%s')" then return type(a) == "string" and type(b) == "string" and a:match(b) ~= nil end
    local na, nb = tonumber(a), tonumber(b)
    if na and nb then
        if op == "<" then return na < nb elseif op == "<=" then return na <= nb
        elseif op == ">" then return na > nb elseif op == ">=" then return na >= nb
        elseif op == "~=" or op == "!=" then return na ~= nb end
        return na == nb
    end
    if op == "~=" or op == "!=" then return tostring(a) ~= tostring(b) end
    return tostring(a) == tostring(b)
end
C.Op = Op

local function Yes(v) return tonumber(v) == 1 or v == true end

local customChecks = setmetatable({}, { __mode = "k" })   -- check table -> compiled function (or false)

-- units in (or beyond) a range, counted as the format's range check does
local function InRange(c)
    local found = 0
    local op, range = c.op_range or "<=", tonumber(c.range) or 5
    if c.type == "enemies" then
        for i = 1, 40 do
            local unit = "nameplate" .. i
            if UnitExists(unit) and UnitCanAttack("player", unit) and E.WA.CheckRange(unit, range, op) then found = found + 1 end
        end
    elseif WA_IterateGroupMembers then
        for unit in WA_IterateGroupMembers() do
            if not UnitIsUnit(unit, "player") and E.WA.CheckRange(unit, range, op) then found = found + 1 end
        end
    end
    return Op(found, c.op or ">=", tonumber(c.value) or 0)
end

local function Global(r, c)
    local v = c.variable
    if v == "alwaystrue" then return true end
    if v == "incombat" then
        return (UnitAffectingCombat("player") and true or false) == Yes(c.value)
    end
    if v == "hastarget" then
        return (UnitExists("target") and true or false) == Yes(c.value)
    end
    if v == "attackabletarget" then
        return (UnitCanAttack("player", "target") and true or false) == Yes(c.value)
    end
    if v == "rangecheck" then
        if c.type then return InRange(c) end
        -- an older single-unit form
        return UnitExists("target") and E.WA.CheckRange("target", tonumber(c.value) or 5, c.op) or false
    end
    if v == "customcheck" then
        local fn = customChecks[c]
        if fn == nil then
            fn = E.Env.Function(r.id, c.value, "condition") or false
            customChecks[c] = fn
        end
        if not fn then return false end
        local states = r.ctx and r.ctx.triggers or {}
        return E.Env.Run(r.id, fn, r.state, E.states[r.id], r, states) and true or false
    end
    return false
end

local nextFlip                 -- earliest time a time-left check changes (per pass)

local function Flip(at)
    if at > GetTime() and (not nextFlip or at < nextFlip) then nextFlip = at end
end

-- a timer field: the time left (paused: what was left), scaled by its rate
local function TimerCheck(st, var, op, want, meta)
    local exp = tonumber(st[var])
    if not exp or exp == 0 then return false end
    local paused = meta and meta.paused and st[meta.paused] or (var == "expirationTime" and st.paused)
    local left
    if paused then
        left = tonumber(meta and meta.remaining and st[meta.remaining] or st.remaining) or 0
    else
        if exp == math.huge then return false end
        left = exp - GetTime()
        local mod = tonumber(meta and meta.modRate and st[meta.modRate] or (var == "expirationTime" and st.modRate)) or 1
        left = left / mod
        Flip(exp - want * mod)
    end
    if op == "==" then return math.abs(left - want) < 0.05 end
    return Op(left, op or "<=", want)
end

local function Check(r, c)
    if type(c) ~= "table" then return false end
    local t = tonumber(c.trigger)
    if t == -2 or c.variable == "AND" or c.variable == "OR" then
        local list = c.checks or {}
        if c.variable == "OR" then
            for _, sub in ipairs(list) do if Check(r, sub) then return true end end
            return false
        end
        local any = false
        for _, sub in ipairs(list) do
            if type(sub) == "table" and (sub.variable or sub.checks) then
                any = true
                if not Check(r, sub) then return false end
            end
        end
        return any
    end
    if t == -1 then return Global(r, c) end
    local st = r.ctx and r.ctx.triggers and r.ctx.triggers[t or 1]
    if t == nil then st = r.state end
    local var = c.variable
    if var == nil then return false end
    if var == "show" then
        local on = st and st.show and true or false
        return on == Yes(c.value)
    end
    if not st then return false end
    local meta = E.ConditionTemplate and E.ConditionTemplate(r.d, t, var)
    local kind = type(meta) == "table" and meta.type or nil
    if kind == "customcheck" then
        local fn = customChecks[c]
        if fn == nil then
            fn = E.Env.Function(r.id, c.value, "condition") or false
            customChecks[c] = fn
        end
        return fn and E.Env.Run(r.id, fn, r.state, E.states[r.id], r, r.ctx and r.ctx.triggers or {}) and true or false
    end
    if type(meta) == "table" and type(meta.test) == "function" then
        local ok, res = pcall(meta.test, st, c.value, c.op)
        return ok and res and true or false
    end
    local v = st[var]
    if kind == "alwaystrue" then return true end
    if v == nil then return false end
    if kind == "timer" or (kind == nil and (var == "expirationTime" or var == "remaining")) then
        local want = tonumber(c.value)
        if not want or not c.op then return false end
        if var == "remaining" and not kind then
            -- older data: the time left itself
            return Op(v, c.op, want)
        end
        return TimerCheck(st, var, c.op, want, meta)
    end
    if kind == "elapsedTimer" then
        local want, start = tonumber(c.value), tonumber(v)
        if not (want and start and c.op) then return false end
        Flip(start + want)
        if c.op == "==" then return math.abs(GetTime() - start - want) < 0.05 end
        return Op(GetTime() - start, c.op, want)
    end
    if kind == "bool" or (kind == nil and c.op == nil) then
        if c.value == nil then return false end
        local on = v and v ~= 0 and true or false
        return on == Yes(c.value)
    end
    if c.op == nil or c.value == nil then return false end
    if kind == "string" and c.op == "match('%s')" then
        return type(v) == "string" and v:match(tostring(c.value)) ~= nil
    end
    return Op(v, c.op, c.value)
end
C.Check = Check

-- ============================================================
-- APPLYING PROPERTIES
-- ============================================================
local R = E.Regions
local ONE_OFF = { sound = true, chat = true, customcode = true, glowexternal = true }
C.ONE_OFF = ONE_OFF

-- what a property is on this region: { kind, method }
local function PropInfo(r, prop)
    local t = R.properties[r.regionType]
    return t and t[prop]
end
C.PropInfo = PropInfo

local function SetProp(r, prop, value)
    local sub, rest = prop:match("^sub%.(%d+)%.(.+)$")
    if sub then
        E.SubRegions.Set(r, tonumber(sub), rest, value)
        return
    end
    local info = PropInfo(r, prop)
    local method = info and r[info[2]]
    if not method then
        -- names older ZacUI data used
        if prop == "barColor" and r.Color then method, info = r.Color, { "color" }
        elseif prop == "foregroundColor" and r.Color then method, info = r.Color, { "color" }
        else return end
    end
    if info[1] == "color" then
        local cr, cg, cb, ca = Color(value)
        method(r, cr, cg, cb, ca)
    elseif info[1] == "bool" then
        method(r, value and true or false)
    else
        method(r, value)
    end
end
C.SetProp = SetProp

-- what the display itself says a property is (to go back to)
local function BaseValue(r, prop)
    if type(prop) ~= "string" then return nil end
    local d = r.baseD or r.d
    local sub, rest = prop:match("^sub%.(%d+)%.(.+)$")
    if sub then
        local s = d.subRegions and d.subRegions[tonumber(sub)]
        if not s then return nil end
        local n = rest:match("^tick_placements%.(%d+)$")
        if n then return type(s.tick_placements) == "table" and s.tick_placements[tonumber(n)] or nil end
        if rest == "tick_use_texture" then return s.use_texture end
        local v = s[rest]
        if v == nil then
            if rest == "text_visible" or rest == "border_visible" or rest == "textureVisible"
                or rest == "tick_visible" or rest == "model_visible" or rest == "stopmotionVisible"
                or rest == "linearTextureVisible" or rest == "circularTextureVisible" then v = true end
            if rest == "text_anchorXOffset" then v = s.anchorXOffset end
            if rest == "text_anchorYOffset" then v = s.anchorYOffset end
            if rest == "glow" then v = false end
        end
        return v
    end
    if prop == "xOffsetRelative" or prop == "yOffsetRelative" then return 0 end
    local v = R.Value(d, prop)
    if v == nil and prop == "alpha" then v = 1 end
    return v
end
C.BaseValue = BaseValue

local function OneOff(r, prop, value, turningOn)
    if prop == "glowexternal" then
        if E.Actions and E.Actions.FrameGlow then E.Actions.FrameGlow(r, value, turningOn) end
        return
    end
    if not turningOn then return end
    if prop == "sound" and type(value) == "table" then
        if E.Actions then E.Actions.SoundPlay(r, value) end
    elseif prop == "chat" and type(value) == "table" then
        if E.Actions then
            local fn
            if value.message_custom and value.message_custom ~= "" then
                r.chatFns = r.chatFns or {}
                fn = r.chatFns[value]
                if fn == nil then
                    fn = E.Env.Function(r.id, value.message_custom, "condition message") or false
                    r.chatFns[value] = fn
                end
            end
            E.Actions.Message(r, value.message, value.message_type, value.message_dest, value.message_channel, value,
                value.message_dest_isunit, value.message_color, fn or nil)
        end
    elseif prop == "customcode" and type(value) == "table" and value.custom then
        r.codeFns = r.codeFns or {}
        local fn = r.codeFns[value]
        if fn == nil then
            fn = E.Env.Body(r.id, value.custom, "condition code") or false
            r.codeFns[value] = fn
        end
        if fn then E.Env.Run(r.id, fn, r.state, E.states[r.id], r) end
    end
end

-- ============================================================
-- RE-CHECKING ON EVENTS (global checks, custom checks' events)
-- ============================================================
local eventsOf = setmetatable({}, { __mode = "k" })   -- display table -> { event = true }
local watching = {}         -- event -> { id = true }
local dirty = {}            -- id -> true
local everyFrame = {}       -- id -> true
local polled = {}           -- id -> true (range checks, 5 times a second)
local driver = CreateFrame("Frame")
driver:Hide()

local function Collect(d, out, c)
    if type(c) ~= "table" then return end
    local t = tonumber(c.trigger)
    if t == -2 or c.variable == "AND" or c.variable == "OR" then
        for _, sub in ipairs(c.checks or {}) do Collect(d, out, sub) end
        return
    end
    if t == -1 then
        if c.variable == "customcheck" then
            for ev in tostring(c.op or ""):gmatch("[%w_:]+") do out[ev] = true end
        else
            local g = C.GLOBALS[c.variable]
            for _, ev in ipairs(g and g[2] or {}) do out[ev] = true end
        end
        return
    end
    local meta = E.ConditionTemplate and t and c.variable and E.ConditionTemplate(d, t, c.variable)
    if type(meta) == "table" and type(meta.events) == "table" then
        for _, ev in ipairs(meta.events) do out[ev] = true end
    end
end

local function EventsOf(d)
    local e = eventsOf[d]
    if e then return e end
    e = {}
    for _, cond in ipairs(type(d.conditions) == "table" and d.conditions or {}) do
        if type(cond) == "table" then Collect(d, e, cond.check) end
    end
    eventsOf[d] = e
    return e
end

local function Mark(id)
    dirty[id] = true
    driver:Show()
end

local function Watch(event, id)
    if event == "FRAME_UPDATE" then everyFrame[id] = true driver:Show() return end
    if event == "RANGE_POLL" or event == "WA_SPELL_RANGECHECK" then polled[id] = true driver:Show() return end
    local base, unit = event:match("^([^:]+):(.+)$")
    base = base or event
    local list = watching[event]
    if not list then
        list = {}
        watching[event] = list
        local lowUnit = unit and unit:lower()
        E.On(base, "cond.dyn." .. event, function(_, arg1)
            if lowUnit and (type(arg1) ~= "string" or arg1:lower() ~= lowUnit) then return end
            for wid in pairs(list) do Mark(wid) end
        end)
    end
    list[id] = true
end

local function Shown(id, fn)
    local main = E.regions[id]
    if main and (main:IsShown() or main.showing) and not main.finishing then fn(main) end
    for _, r in pairs(E.clones[id] or {}) do
        if (r:IsShown() or r.showing) and not r.finishing then fn(r) end
    end
end

local pollAcc = 0
driver:SetScript("OnUpdate", function(self, elapsed)
    pollAcc = pollAcc + (elapsed or 0)
    local list = dirty
    dirty = {}
    for id in pairs(everyFrame) do list[id] = true end
    if pollAcc >= 0.2 then
        pollAcc = 0
        for id in pairs(polled) do list[id] = true end
    end
    local any = false
    for id in pairs(list) do
        if E.loaded[id] then
            any = true
            Shown(id, function(r) local ok, err = pcall(C.Apply, r) if not ok then E.Error(id, "conditions", err) end end)
        else
            everyFrame[id], polled[id] = nil, nil
        end
    end
    if not any and not next(everyFrame) and not next(polled) and not next(dirty) then self:Hide() end
end)

-- ============================================================
-- THE PASS
-- ============================================================
function C.Apply(r)
    local d = r.baseD or r.d
    local list = d.conditions
    if type(list) ~= "table" or #list == 0 then return end
    if not r.condWatched then
        r.condWatched = true
        for ev in pairs(EventsOf(d)) do Watch(ev, r.id) end
    end
    nextFlip = nil
    local want = {}
    r.condOn = r.condOn or {}
    local chainHit = false
    for i, cond in ipairs(list) do
        local on = false
        if type(cond) == "table" then
            if cond.linked and i > 1 then
                -- an "else if": only when nothing above in its chain held
                if not chainHit then
                    on = Check(r, cond.check)
                    if on then chainHit = true end
                end
            else
                on = Check(r, cond.check)
                chainHit = on
            end
            local was = r.condOn[i]
            for _, ch in ipairs(type(cond.changes) == "table" and cond.changes or {}) do
                local p = ch.property
                if type(p) == "string" then
                    if ONE_OFF[p] then
                        if on and not was then OneOff(r, p, ch.value, true)
                        elseif was and not on then OneOff(r, p, ch.value, false) end
                    elseif on then
                        want[p] = { ch.value }
                    end
                end
            end
        end
        r.condOn[i] = on
    end
    -- set what is wanted; put back what no longer is
    local had = r.condProps or {}
    for p, v in pairs(want) do SetProp(r, p, v[1]) end
    for p in pairs(had) do
        if not want[p] then
            if p == "displayText" then r.textOverride = nil end
            SetProp(r, p, BaseValue(r, p))
            if p == "displayText" then r.textOverride = nil end
        end
    end
    r.condProps = want
    -- a time-left check changes by itself: look again then
    if nextFlip then
        local at = nextFlip
        if not r.flipAt or r.flipAt > at or r.flipAt < GetTime() then
            r.flipAt = at
            C_Timer.After(math.max(0.01, at - GetTime()), function()
                if (r:IsShown() or r.showing) and r.flipAt == at then
                    r.flipAt = nil
                    C.Apply(r)
                end
            end)
        end
    end
end

-- a region going away: its glows on other frames go with it and every
-- property a condition set goes back, so the next show starts clean
function C.Reset(r)
    local d = r.baseD or r.d
    if r.condOn then
        for i, on in pairs(r.condOn) do
            if on then
                local cond = d.conditions and d.conditions[i]
                for _, ch in ipairs(cond and type(cond.changes) == "table" and cond.changes or {}) do
                    if ch.property == "glowexternal" then OneOff(r, "glowexternal", ch.value, false) end
                end
            end
        end
    end
    for p in pairs(r.condProps or {}) do
        if p == "displayText" then r.textOverride = nil end
        pcall(SetProp, r, p, BaseValue(r, p))
        if p == "displayText" then r.textOverride = nil end
    end
    r.condOn = nil
    r.condProps = nil
    r.condWatched = nil
end
