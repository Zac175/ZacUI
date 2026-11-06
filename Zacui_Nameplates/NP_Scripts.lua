-- NP_Scripts - the script/mod engine: user Lua running against ZacUI's
-- nameplates, modeled on Plater's two-tier system.
-- Part of ZacUI; load order is set by the TOC.
--
-- THE MODEL, faithfully Plater's:
--   MODS run on every plate, keyed to lifecycle hooks (Constructor,
--   Nameplate Added/Updated/Removed, Cast Start/Stop, Enter/Leave
--   Combat, Target Changed, Initialization).
--   SCRIPTS run on the plates that match a TRIGGER - a cast (spell id
--   or name), an aura, or an npc (id or name) - with OnShow when the
--   trigger starts matching, OnUpdate while it does, OnHide when it
--   stops.
--
-- Every piece of user code is a full function literal, same shape
-- Plater uses:   function(self, unit, envTable, modTable) ... end
-- where self is the plate frame ZacUI built (self.healthBar, self.cast,
-- self.name, ...), unit is the unit token, envTable persists per
-- plate-per-script, modTable persists per script. Code compiles with
-- full API access; errors are caught, printed ONCE with the script's
-- name, and never take the nameplate engine down.

local ADDON_NAME = ...
-- Zacui_Nameplates is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

-- shared state from earlier ZacUI files
local NP = ns.Nameplates
local Print = ns.Print

local Scripts = {}
NP.Scripts = Scripts

-- ============================================================
-- STORAGE
-- ============================================================
local MOD_HOOKS = {
    "Initialization", "Constructor",
    "Nameplate Added", "Nameplate Updated", "Nameplate Removed",
    "Cast Start", "Cast Stop",
    "Target Changed", "Enter Combat", "Leave Combat",
}
local SCRIPT_HOOKS = { "OnShow", "OnUpdate", "OnHide" }
Scripts.MOD_HOOKS = MOD_HOOKS
Scripts.SCRIPT_HOOKS = SCRIPT_HOOKS

local EXAMPLE = [[function(self, unit, envTable, modTable)
    -- self is the plate frame: self.healthBar, self.cast, self.name...
    -- envTable persists on this plate for this script; make your
    -- widgets once and reuse them:
    if not envTable.glow then
        envTable.glow = self.healthBar:CreateTexture(nil, "OVERLAY")
        envTable.glow:SetAllPoints()
        envTable.glow:SetColorTexture(1, 0, 0, 0.35)
        envTable.glow:SetBlendMode("ADD")
    end
    envTable.glow:Show()
end]]

local EXAMPLE_HIDE = [[function(self, unit, envTable, modTable)
    if envTable.glow then envTable.glow:Hide() end
end]]

local function SDB()
    ZacUIDB.npScripts = ZacUIDB.npScripts or {}
    local s = ZacUIDB.npScripts
    s.mods = s.mods or {}
    s.scripts = s.scripts or {}
    if not s.seeded then
        s.seeded = true
        s.scripts[#s.scripts + 1] = {
            name = "Example - red glow while casting",
            enabled = false,
            triggerKind = "cast",
            triggers = "116, Frostbolt",
            rev = 1,
            hooks = { OnShow = EXAMPLE, OnHide = EXAMPLE_HIDE },
        }
    end
    return s
end
Scripts.DB = SDB

-- ============================================================
-- COMPILER
-- ============================================================
-- compiled[entry] = { rev = n, fns = { [hook] = fn } }; the editor bumps
-- entry.rev on save, which invalidates here on the next lookup.
local compiled = setmetatable({}, { __mode = "k" })
local errOnce = {}

local function CompileHook(entry, hook, code)
    if not code or code == "" then return nil end
    local loader = loadstring or load
    local chunk, err = loader("return (" .. code .. ")",
        "ZacUI script: " .. (entry.name or "?") .. " / " .. hook)
    if not chunk then
        local key = tostring(entry) .. hook .. "compile"
        if not errOnce[key] then
            errOnce[key] = true
            Print("|cFFFF6666script '" .. (entry.name or "?") .. "' ("
                .. hook .. ") does not compile:|r " .. tostring(err))
        end
        return nil
    end
    local ok, fn = pcall(chunk)
    if not ok or type(fn) ~= "function" then
        local key = tostring(entry) .. hook .. "shape"
        if not errOnce[key] then
            errOnce[key] = true
            Print("|cFFFF6666script '" .. (entry.name or "?") .. "' ("
                .. hook .. ") must be a function(self, unit, envTable, "
                .. "modTable) ... end|r")
        end
        return nil
    end
    -- scripts see the full API plus ZNP (the nameplate engine itself)
    if setfenv then
        setfenv(fn, setmetatable({ ZNP = NP }, { __index = _G }))
    end
    return fn
end

local function GetCompiled(entry)
    local c = compiled[entry]
    if c and c.rev == (entry.rev or 0) then return c.fns end
    local fns = {}
    for hook, code in pairs(entry.hooks or {}) do
        fns[hook] = CompileHook(entry, hook, code)
    end
    compiled[entry] = { rev = entry.rev or 0, fns = fns }
    return fns
end

function Scripts.Invalidate(entry)
    compiled[entry] = nil
    errOnce = {}
end

-- validate without running: returns ok, err for the editor's Check
function Scripts.CheckCode(code)
    if not code or code == "" then return true end
    local loader = loadstring or load
    local chunk, err = loader("return (" .. code .. ")", "check")
    if not chunk then return false, err end
    local ok, fn = pcall(chunk)
    if not ok then return false, tostring(fn) end
    if type(fn) ~= "function" then
        return false, "code must be a function(...) ... end literal"
    end
    return true
end

-- ============================================================
-- RUNNING
-- ============================================================
-- per-plate script state lives on the frame:
--   f._znpEnv[entry]    = envTable (persists for the plate's lifetime)
--   f._znpActive[entry] = script trigger currently matching
--   f._znpBuilt[entry]  = mod Constructor already ran on this frame
local function PlateState(f)
    f._znpEnv = f._znpEnv or setmetatable({}, { __mode = "k" })
    f._znpActive = f._znpActive or setmetatable({}, { __mode = "k" })
    f._znpBuilt = f._znpBuilt or setmetatable({}, { __mode = "k" })
    return f
end

local function Env(f, entry)
    local e = f._znpEnv[entry]
    if not e then
        e = {}
        f._znpEnv[entry] = e
    end
    return e
end

local function Call(entry, hook, fn, f, unit, envTable, modTable)
    if not fn then return end
    local ok, err = pcall(fn, f, unit, envTable, modTable)
    if not ok then
        local key = tostring(entry) .. hook .. "run"
        if not errOnce[key] then
            errOnce[key] = true
            Print("|cFFFF6666script '" .. (entry.name or "?") .. "' ("
                .. hook .. ") error:|r " .. tostring(err))
        end
    end
end

-- ---------- mods ----------
local function RunModHook(hook, f)
    local s = SDB()
    for _, mod in ipairs(s.mods) do
        if mod.enabled then
            local fns = GetCompiled(mod)
            mod._modTable = mod._modTable or {}
            if not mod._init and fns.Initialization then
                mod._init = true
                Call(mod, "Initialization", fns.Initialization,
                    nil, nil, nil, mod._modTable)
            end
            if f then
                PlateState(f)
                if not f._znpBuilt[mod] and fns.Constructor then
                    f._znpBuilt[mod] = true
                    Call(mod, "Constructor", fns.Constructor,
                        f, f.unit, Env(f, mod), mod._modTable)
                end
                if fns[hook] then
                    Call(mod, hook, fns[hook],
                        f, f.unit, Env(f, mod), mod._modTable)
                end
            elseif fns[hook] then
                Call(mod, hook, fns[hook], nil, nil, nil, mod._modTable)
            end
        end
    end
end

-- ---------- script triggers ----------
local function ParseTriggers(entry)
    if entry._trigRev == (entry.rev or 0) and entry._trig then
        return entry._trig
    end
    local t = { ids = {}, names = {} }
    for token in tostring(entry.triggers or ""):gmatch("[^,;]+") do
        token = token:match("^%s*(.-)%s*$")
        if token ~= "" then
            local n = tonumber(token)
            if n then t.ids[n] = true else t.names[token:lower()] = true end
        end
    end
    entry._trig, entry._trigRev = t, entry.rev or 0
    return t
end

-- This runs for every aura-triggered script on every plate every 0.5s
-- (and on each UNIT_AURA), so the filter list is a constant, a trigger
-- with nothing to match is answered without touching the unit, and a
-- name is lowercased only when the trigger has names to compare.
local AURA_FILTERS = { "HARMFUL", "HELPFUL" }

local function AuraMatches(unit, trig)
    local ids, names = trig.ids, trig.names
    local hasIds, hasNames = next(ids) ~= nil, next(names) ~= nil
    if not hasIds and not hasNames then return false end
    local getData = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    for fi = 1, #AURA_FILTERS do
        local filter = AURA_FILTERS[fi]
        for i = 1, 40 do
            local name, spellId
            if getData then
                local a = getData(unit, i, filter)
                -- (WoW Forever hides auras in combat: read as none)
                if not a or (ns.AuraHidden and ns.AuraHidden(a)) then break end
                name, spellId = a.name, a.spellId
            elseif UnitAura then
                local n, _, _, _, _, _, _, _, _, sid =
                    UnitAura(unit, i, filter)
                if not n then break end
                name, spellId = n, sid
            else
                break
            end
            if spellId and hasIds and ids[spellId] then return true end
            if name and hasNames and names[name:lower()] then return true end
        end
    end
    return false
end

local function ScriptMatches(script, f, castID, castName)
    local trig = ParseTriggers(script)
    local kind = script.triggerKind or "cast"
    if kind == "cast" then
        if not f.cast or not f.cast:IsShown() then return false end
        local id = castID or f.cast.spellID
        local nm = castName or (f.cast.spell and f.cast.spell:GetText())
        return (id and trig.ids[id])
            or (nm and trig.names[tostring(nm):lower():gsub("%s*|c.*", "")])
            or false
    elseif kind == "aura" then
        return f.unit and AuraMatches(f.unit, trig) or false
    else -- npc
        if not f.unit then return false end
        -- the engine caches the id on the plate when the unit binds; only
        -- an undressed plate has to split the GUID here
        local npcId = f.npcId
        if npcId == nil then npcId = NP.NpcIdFromUnit(f.unit) end
        if npcId and trig.ids[npcId] then return true end
        local nm = UnitName(f.unit)
        return (nm and trig.names[nm:lower()]) or false
    end
end

-- drive one script's OnShow/OnUpdate/OnHide off its current match state
local function EvalScript(script, f)
    PlateState(f)
    local fns = GetCompiled(script)
    local matching = ScriptMatches(script, f)
    local active = f._znpActive[script]
    if matching and not active then
        f._znpActive[script] = true
        Call(script, "OnShow", fns.OnShow, f, f.unit, Env(f, script))
    elseif matching and active then
        Call(script, "OnUpdate", fns.OnUpdate, f, f.unit, Env(f, script))
    elseif active and not matching then
        f._znpActive[script] = nil
        Call(script, "OnHide", fns.OnHide, f, f.unit, Env(f, script))
    end
end

local function EvalAllScripts(f)
    local s = SDB()
    for _, script in ipairs(s.scripts) do
        if script.enabled then EvalScript(script, f) end
    end
end

-- force-hide everything active on a plate (unit left, plate recycled)
local function HideAllScripts(f)
    if not f._znpActive then return end
    for script in pairs(f._znpActive) do
        f._znpActive[script] = nil
        local fns = GetCompiled(script)
        Call(script, "OnHide", fns.OnHide, f, f.unit, Env(f, script))
    end
end

-- ============================================================
-- ENTRY POINTS - the engine calls these; every one is total
-- ============================================================
function Scripts.PlateAdded(f)
    RunModHook("Nameplate Added", f)
    EvalAllScripts(f)
end

function Scripts.PlateUpdated(f)
    RunModHook("Nameplate Updated", f)
    EvalAllScripts(f)
end

function Scripts.PlateRemoved(f)
    HideAllScripts(f)
    RunModHook("Nameplate Removed", f)
end

function Scripts.CastStart(f, spellID, spellName)
    RunModHook("Cast Start", f)
    EvalAllScripts(f)
end

function Scripts.CastStop(f)
    RunModHook("Cast Stop", f)
    EvalAllScripts(f)
end

function Scripts.AuraChanged(f)
    EvalAllScripts(f)
end

-- is any user script switched on? (the engine skips aura work for
-- plates when nothing would read it)
function Scripts.AnyEnabled()
    for _, script in ipairs(SDB().scripts) do
        if script.enabled then return true end
    end
    return false
end

function Scripts.TargetChanged()
    for _, f in pairs(NP.activePlates) do
        RunModHook("Target Changed", f)
    end
end

function Scripts.CombatEnter()
    for _, f in pairs(NP.activePlates) do
        RunModHook("Enter Combat", f)
    end
end

function Scripts.CombatLeave()
    for _, f in pairs(NP.activePlates) do
        RunModHook("Leave Combat", f)
    end
end
