-- UIF_Settings - the "a setting changed" signal, and the small helpers
-- every module uses to give its settings defaults without touching what
-- a user already saved.
-- Part of ZacUI; load order is set by the TOC (before UIF_Controls,
-- whose widgets raise the signal).
--
--   ns.SettingsChanged(source)     raise it: every listener runs, now
--   ns.OnSettingsChanged(fn)       listen (fn(source)); keep fn CHEAP -
--                                  set a flag or call a Coalesce'd fn
--   ns.Coalesce(fn)                -> a function that, however often it is
--                                  called in a frame, runs fn ONCE on the
--                                  next frame
--   ns.FillDefaults(dst, defaults) copy in every key dst lacks (deep);
--                                  never overwrites a value already there
--   ns.RunMigrations(db, revKey, steps)
--                                  one-time fixes, in order: steps[n] runs
--                                  once for a db whose db[revKey] < n
--
-- WHO RAISES IT. Every ZacUI widget - Checkbox, Slider, Dropdown, an
-- EditBox commit (Enter, or its clear button), Swatch and the pickers in
-- UIF_Pickers - calls ns.SettingsChanged() after it has run the page's
-- own callback, so the callback has already written the new value when
-- listeners look. A page never has to remember to; a hand-made control
-- (a button that changes a setting, say) calls it itself.
--
-- WHY LISTENERS RUN AT ONCE AND NOT ON THE NEXT FRAME. The preview dock
-- listens, and so does the page rebuild that most callbacks start
-- (RefreshConfig). Both ask the dock for an update; if this signal waited
-- a frame and then asked, the dock's own coalescing would already have
-- run and the second ask would cost a second update. Running listeners
-- immediately lets every ask in one click land in the same frame and
-- come out as one update.

local ADDON_NAME, ns = ...

-- ============================================================
-- COALESCE
-- ============================================================
function ns.Coalesce(fn)
    local pending = false
    local function Run()
        pending = false
        fn()
    end
    return function()
        if pending then return end
        pending = true
        C_Timer.After(0, Run)
    end
end

-- ============================================================
-- THE SIGNAL
-- ============================================================
local listeners = {}

function ns.OnSettingsChanged(fn)
    if type(fn) ~= "function" then return end
    for _, f in ipairs(listeners) do
        if f == fn then return end
    end
    listeners[#listeners + 1] = fn
end

-- A listener that throws is reported once and never takes the others
-- (or the widget that raised the signal) down with it.
local complained = {}
function ns.SettingsChanged(source)
    for _, fn in ipairs(listeners) do
        local ok, err = pcall(fn, source)
        if not ok and not complained[fn] then
            complained[fn] = true
            if ns.Print then ns.Print("a settings listener failed: " .. tostring(err)) end
        end
    end
end

-- ============================================================
-- DEFAULTS
-- ============================================================
-- Fill, never replace. A key the user has (even false, even 0) is theirs;
-- only a key that is nil gets the default. Tables are copied, so two
-- settings never end up sharing one defaults table and a write to one
-- silently changing the other.
local function Copy(v, depth)
    if type(v) ~= "table" or (depth or 0) > 20 then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = Copy(x, (depth or 0) + 1) end
    return out
end

function ns.FillDefaults(dst, defaults, depth)
    if type(dst) ~= "table" or type(defaults) ~= "table" then return dst end
    depth = depth or 0
    if depth > 20 then return dst end
    for k, v in pairs(defaults) do
        local cur = dst[k]
        if cur == nil then
            dst[k] = Copy(v)
        elseif type(cur) == "table" and type(v) == "table" then
            ns.FillDefaults(cur, v, depth + 1)
        end
    end
    return dst
end

-- When a shipped default really must change for people who already have
-- the old one saved, the fill above cannot do it (their value wins). A
-- numbered step does it exactly once per saved table:
--   ns.RunMigrations(cfg, "rev", {
--       [1] = function(c) if c.size == 12 then c.size = 13 end end,
--   })
-- Only touch a value that is exactly the old default - one the user
-- picked is never theirs to lose.
function ns.RunMigrations(db, revKey, steps)
    if type(db) ~= "table" or type(steps) ~= "table" then return 0 end
    local rev = tonumber(db[revKey]) or 0
    local top, ran = rev, 0
    for n in pairs(steps) do
        if type(n) == "number" and n > top then top = n end
    end
    for n = rev + 1, top do
        local fn = steps[n]
        if type(fn) == "function" then
            local ok, err = pcall(fn, db)
            if not ok and ns.Print then ns.Print("settings migration " .. n .. " failed: " .. tostring(err)) end
            ran = ran + 1
        end
    end
    if top > rev then db[revKey] = top end
    return ran
end

ns.CopySetting = Copy
