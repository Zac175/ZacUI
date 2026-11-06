-- AE_Env - the custom code inside displays: compiling it once, and the
-- environment it runs in (aura_env and friends).
-- Part of ZacUI (Zacui_Auras). Written for ZacUI.
--
-- A display's code sees:
--   aura_env      that display's own table: id, cloneId, region, state,
--                 states, config (its custom options), saved (kept across
--                 sessions), plus anything its code puts there
--   WeakAuras     the public table (AE_Core)
--   every global  as normal; a global it sets is a real global
-- A handful of functions that could do real harm from code someone
-- pasted in (run arbitrary script, delete items, send mail...) are not
-- reachable from it.
local ns = _G.ZacUI
if not ns then return end
local E = ns.AuraEngine
if not E then return end

local V = {}
E.Env = V

local BLOCKED = {
    RunScript = true, DeleteCursorItem = true, SendMail = true, SetTradeMoney = true,
    AddTradeMoney = true, PickupTradeMoney = true, PickupPlayerMoney = true, AcceptTrade = true,
    GuildDisband = true, GuildUninvite = true, SetCurrentTitle = true, DemoteAssistant = true,
    getfenv = true, setfenv = true, loadstring = true,
    hash_SlashCmdList = true, SlashCmdList = true, ChatEdit_SendText = true,
    EditMacro = true, CreateMacro = true, DeleteMacro = true,
}

-- Custom code that plays a file from the old raid-pack media folder (a
-- path it builds at run time) gets what took its place: the words
-- spoken, the game's own blip, or nothing. Any other file plays as before.
local function PlaySoundFileBridged(file, channel, ...)
    local Snd = ns.Sounds
    if Snd and Snd.IsLegacy and Snd.IsLegacy(file) then
        return Snd.Play(file, channel)
    end
    return PlaySoundFile(file, channel, ...)
end

local envs = {}        -- id -> aura_env
local fenvs = {}       -- id -> the function environment
V.envs = envs

local function Saved(d)
    d.information = type(d.information) == "table" and d.information or {}
    if type(d.information.saved) ~= "table" then d.information.saved = {} end
    return d.information.saved
end

-- the custom options' values: what the user set (config) over each
-- option's default (authorOptions)
local function Config(d)
    local out = {}
    for _, opt in ipairs(type(d.authorOptions) == "table" and d.authorOptions or {}) do
        if type(opt) == "table" and opt.key then
            if opt.default ~= nil then out[opt.key] = E.Copy(opt.default) end
        end
    end
    for k, v in pairs(type(d.config) == "table" and d.config or {}) do out[k] = E.Copy(v) end
    return out
end

function V.AuraEnv(id)
    local env = envs[id]
    if env then return env end
    local d = E.data[id]
    env = { id = id, cloneId = "" }
    if d then
        env.config = Config(d)
        env.saved = Saved(d)
    end
    envs[id] = env
    return env
end

-- a fresh aura_env (after the display changed, or on a reload of its
-- code): the saved part carries over
function V.Reset(id)
    envs[id] = nil
    fenvs[id] = nil
end

local function FEnv(id)
    local f = fenvs[id]
    if f then return f end
    local env = V.AuraEnv(id)
    f = setmetatable({}, {
        __index = function(_, k)
            if k == "aura_env" then return envs[id] or env end
            if k == "WeakAuras" then return E.WA end
            if BLOCKED[k] then return nil end
            if k == "PlaySoundFile" then return PlaySoundFileBridged end
            return _G[k]
        end,
        __newindex = function(_, k, v)
            if k == "aura_env" then
                envs[id] = v
                return
            end
            _G[k] = v
        end,
    })
    fenvs[id] = f
    return f
end
V.FEnv = FEnv

-- ============================================================
-- COMPILING
-- ============================================================
-- "function(...) ... end" -> the function, in the display's environment
function V.Function(id, src, where)
    if type(src) ~= "string" or not src:find("%S") then return nil end
    local chunk, err = loadstring("return " .. src, "=[" .. tostring(id) .. "] " .. tostring(where))
    if not chunk then
        E.Error(id, where or "code", err)
        return nil
    end
    local ok, fn = pcall(setfenv(chunk, FEnv(id)))
    if not ok then
        E.Error(id, where or "code", fn)
        return nil
    end
    if type(fn) ~= "function" then return nil end
    return fn
end

-- a plain block of statements (an action's custom code, init)
function V.Body(id, src, where)
    if type(src) ~= "string" or not src:find("%S") then return nil end
    local chunk, err = loadstring(src, "=[" .. tostring(id) .. "] " .. tostring(where))
    if not chunk then
        E.Error(id, where or "code", err)
        return nil
    end
    return setfenv(chunk, FEnv(id))
end

-- runs fn with aura_env pointing at this display (and this clone's
-- state); errors are kept per display and never thrown
function V.Run(id, fn, state, states, region, ...)
    if not fn then return nil end
    local env = envs[id] or V.AuraEnv(id)
    local prevState, prevStates, prevRegion, prevClone = env.state, env.states, env.region, env.cloneId
    env.state, env.states = state, states
    if region then env.region = region end
    if state and state.cloneId ~= nil then env.cloneId = state.cloneId end
    local prev = E.current
    E.current = id
    local res = { pcall(fn, ...) }
    E.current = prev
    env.state, env.states, env.region, env.cloneId = prevState, prevStates, prevRegion or env.region, prevClone
    if not res[1] then
        E.Error(id, "custom code", res[2])
        return nil
    end
    return unpack(res, 2, table.maxn(res))
end

-- the display's "on init" code: once each time it is (re)built
function V.Init(id)
    local d = E.data[id]
    local a = d and d.actions and d.actions.init
    if not (a and a.do_custom and a.custom) then return end
    local fn = V.Body(id, a.custom, "init")
    if fn then V.Run(id, fn) end
end
