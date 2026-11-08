-- Core_CVar - the game settings ZacUI changes that outlive it, and what
-- puts them back: every console variable ZacUI writes goes through here,
-- the first write records the value the player had, and the value goes
-- back when the feature that set it is off, or when ZacUI is uninstalled.
-- Part of ZacUI; load order is set by the TOC (right after Core_Flavor,
-- before anything that writes a CVar).
--
--   ns.CVar.Set(name, value, owner)       SetCVar, recorded
--   ns.CVar.Get(name)                     GetCVar, nil when unknown
--   ns.CVar.Hold(name, value, owner)      a value borrowed for a while
--   ns.CVar.Release(name, owner)          ...and handed back
--   ns.CVar.RestoreOwner(owner)           a feature turned off: its CVars go back
--   ns.CVar.RestoreAll()                  everything ZacUI changed goes back
--   ns.CVar.Uninstall()                   RestoreAll, every Zacui_* addon off;
--                                         the caller reloads
--   ns.CVar.LoginPass()                   the CVars of owners that are off this
--                                         session go back (Boot_Events' login
--                                         calls ns.CVar.AtLogin, which runs it a
--                                         beat later when the record holds any)
--   ns.CVar.Record()                      the record (tests, diagnostics)
--
-- OWNERS. A string: the module key the write belongs to ("nameplates",
-- "qol", "chat"...), a part addon ("Zacui_WorldMap") or a plain tag
-- ("setup" for the interface scale). An owner is OFF when its module
-- switch is false (ZacUIDB.modules), its addon is not loaded, or the game
-- version does not run it (ns.PartOff). ns.CVar.OwnerOff(owner) decides;
-- a part may replace it for its own key with ns.CVar.OwnerCheck(owner, fn).
--
-- THE RULES (the reference suite's, in plain words):
--   * the first write of a CVar records the value from before (b); every
--     write records the value ZacUI left (a) and the owner (o)
--   * a CVar goes back only while it still holds ZacUI's value: one the
--     player changed since is the player's and stays
--   * the value from before is trusted only on an account that started
--     with this system (a fresh install, or since an Uninstall); on an
--     older account ZacUI may have written the CVar before the record
--     existed, so it goes back to the game's default instead
--   * per-character CVars are recorded per character (by GUID), the rest
--     for the account
--   * a HOLD keeps what the record held before it, so the value handed
--     back on Release is never mistaken for one of ZacUI's
--
-- Record: ZacUIDB.cvarRecord (bookkeeping, outside every profile)
--   fresh      the snapshots are trusted
--   cvar       [lowername] = { b = before, a = ours, o = owner }
--   held       [lowername] = { e = the cvar entry before the hold (false: none),
--              v = the value then, o = owner }
--   chars      [GUID] = { cvar = ..., held = ... } for per-character CVars

local ADDON_NAME, ns = ...

local pairs, type, tostring, tonumber, pcall = pairs, type, tostring, tonumber, pcall

local CVar = {}
local KEY = "cvarRecord"
local uninstalled = false
local checks = {}       -- [owner] = fn() -> true when off

-- ============================================================
-- THE GAME'S FUNCTIONS, GUARDED
-- ============================================================
local function GetFn()
    return (C_CVar and C_CVar.GetCVar) or _G.GetCVar
end
local function SetFn()
    return (C_CVar and C_CVar.SetCVar) or _G.SetCVar
end

local function Read(name)
    local f = GetFn()
    if not f then return nil end
    local ok, v = pcall(f, name)
    if ok and v ~= nil then return tostring(v) end
    return nil
end
CVar.Get = Read

local function Write(name, value)
    local f = SetFn()
    if not f then return false end
    local ok, res = pcall(f, name, value)
    if not ok then return false end
    -- the client's SetCVar returns true when the write took; the old
    -- global returned nothing, so only an explicit false is a refusal
    return res ~= false
end

-- what the game's own SetCVar passes on: booleans as "1" / "0"
local function Str(value)
    if type(value) == "boolean" then return value and "1" or "0" end
    if value == nil then return nil end
    return tostring(value)
end

local function Default(name)
    if C_CVar and C_CVar.GetCVarDefault then
        local ok, v = pcall(C_CVar.GetCVarDefault, name)
        if ok and v ~= nil then return tostring(v) end
    end
    return nil
end

local function PerCharacter(name)
    if C_CVar and C_CVar.GetCVarInfo then
        local ok, _, _, _, perChar = pcall(C_CVar.GetCVarInfo, name)
        if ok then return perChar and true or false end
    end
    return false
end

-- ============================================================
-- THE RECORD
-- ============================================================
local function Record(peek)
    if type(ZacUIDB) ~= "table" then return nil end
    local r = ZacUIDB[KEY]
    if type(r) ~= "table" then
        -- (peek: a reader; nothing is written down before the first write)
        if peek then return nil end
        -- A record started on a fresh install (Boot_Events saw no saved
        -- variables) can trust what it writes down; one started on an
        -- older account cannot: ZacUI may have set these CVars before.
        r = { fresh = ns.freshInstall == true }
        ZacUIDB[KEY] = r
    end
    return r
end
CVar.Record = Record

local function Sub(t, k)
    local s = t[k]
    if type(s) ~= "table" then s = {} t[k] = s end
    return s
end

local function Guid()
    return UnitGUID and UnitGUID("player") or nil
end

-- the part of the record a CVar belongs to (nil: nowhere to write yet)
local function Root(name)
    local r = Record()
    if not r then return nil end
    if PerCharacter(name) then
        local guid = Guid()
        if not guid then return nil end
        return Sub(Sub(r, "chars"), guid), r
    end
    return r, r
end

local function Note(root, r, key, before, owner)
    local t = Sub(root, "cvar")
    local e = t[key]
    if not e then
        e = {}
        t[key] = e
        if r.fresh and before ~= nil then e.b = before end
    end
    e.a = Read(key)
    e.o = owner
    return e
end

-- ============================================================
-- WRITING
-- ============================================================
function CVar.Set(name, value, owner)
    if uninstalled or type(name) ~= "string" then return false end
    local key = name:lower()
    local before = Read(name)
    local ok = Write(name, Str(value))
    if not ok then return false end
    local root, r = Root(name)
    if root then Note(root, r, key, before, owner) end
    return true
end

-- Set, keeping what the record held before the hold (Release puts it back).
function CVar.Hold(name, value, owner)
    if uninstalled or type(name) ~= "string" then return false end
    local key = name:lower()
    local cur = Read(name)
    local root, r = Root(name)
    local snap
    if root and cur ~= nil and not (root.held and root.held[key]) then
        local e = root.cvar and root.cvar[key]
        snap = { e = e and { b = e.b, a = e.a, o = e.o } or false, v = cur, o = owner }
    end
    local ok = CVar.Set(name, value, owner)
    if ok and snap then Sub(root, "held")[key] = snap end
    return ok
end

-- the end of a hold: the value from before it goes back (while the CVar
-- still holds ours), and the record goes back as it was then
local function EndHold(root, key, h, write)
    local e = root.cvar and root.cvar[key]
    local cur = Read(key)
    if write and h.v ~= nil and (not e or cur == e.a) then
        Write(key, h.v)
    end
    if h.e then
        Sub(root, "cvar")[key] = h.e
    elseif root.cvar then
        root.cvar[key] = nil
    end
    root.held[key] = nil
end

function CVar.Release(name, owner)
    if type(name) ~= "string" then return false end
    local key = name:lower()
    local root = Root(name)
    local h = root and root.held and root.held[key]
    if not h then return false end
    if owner ~= nil and h.o ~= nil and h.o ~= owner then return false end
    EndHold(root, key, h, not uninstalled)
    return true
end

-- ============================================================
-- PUTTING BACK
-- ============================================================
-- A recorded CVar goes back while it still holds ours: to the value
-- from before when that is trusted, else the game's default.
local function RestoreEntry(root, r, key, e)
    local cur = Read(key)
    if cur == nil or cur ~= e.a then return false end
    local want = r.fresh and e.b or nil
    if want == nil then want = Default(key) end
    if want == nil or want == cur then return false end
    return Write(key, want)
end

local function RestoreRoot(root, r, pick)
    local n = 0
    if not root then return 0 end
    if root.held then
        for key, h in pairs(root.held) do
            if pick(h.o) then
                EndHold(root, key, h, true)
                n = n + 1
            end
        end
        if next(root.held) == nil then root.held = nil end
    end
    if root.cvar then
        for key, e in pairs(root.cvar) do
            if pick(e.o) then
                if RestoreEntry(root, r, key, e) then n = n + 1 end
                root.cvar[key] = nil
            end
        end
        if next(root.cvar) == nil then root.cvar = nil end
    end
    return n
end

local function Everywhere(pick)
    local r = Record(true)
    if not r then return 0 end
    local n = RestoreRoot(r, r, pick)
    local guid = Guid()
    local c = r.chars and guid and r.chars[guid]
    if c then
        n = n + RestoreRoot(c, r, pick)
        if next(c) == nil then r.chars[guid] = nil end
    end
    return n
end

function CVar.RestoreOwner(owner)
    if owner == nil then return 0 end
    return Everywhere(function(o) return o == owner end)
end

function CVar.RestoreAll()
    local n = Everywhere(function() return true end)
    local r = Record(true)
    -- everything is back, so from here on every snapshot is the player's
    if r then r.fresh = true end
    return n
end

-- ============================================================
-- WHICH OWNERS ARE OFF
-- ============================================================
function CVar.OwnerCheck(owner, fn)
    checks[owner] = fn
end

local function AddonLoaded(name)
    if ns.AddonLoaded then return ns.AddonLoaded(name) end
    local f = (C_AddOns and C_AddOns.IsAddOnLoaded) or _G.IsAddOnLoaded
    if not f then return true end
    local ok, v = pcall(f, name)
    return ok and v and true or false
end

function CVar.OwnerOff(owner)
    if type(owner) ~= "string" then return false end
    if checks[owner] then
        local ok, off = pcall(checks[owner])
        if ok then return off and true or false end
    end
    if owner:find("^Zacui_") then
        if ns.PartOff and ns.PartOff(owner) then return true end
        return not AddonLoaded(owner)
    end
    local mods = type(ZacUIDB) == "table" and ZacUIDB.modules
    if type(mods) == "table" and mods[owner] == false then return true end
    local part = ns.MODULE_ADDON and ns.MODULE_ADDON[owner]
    if part and ns.PartOff and ns.PartOff(part) then return true end
    return false
end

-- At login, out of combat: what an owner that is off this session left
-- behind goes back. Returns how many CVars were written.
function CVar.LoginPass()
    if uninstalled then return 0 end
    return Everywhere(function(o) return CVar.OwnerOff(o) end)
end

-- ============================================================
-- UNINSTALL
-- ============================================================
-- Puts back everything ZacUI changed and turns every ZacUI addon off for
-- every character. The caller reloads. Refused in combat (some CVars
-- cannot change then). Saved variables are left alone.
function CVar.Uninstall()
    if uninstalled then return false end
    if InCombatLockdown and InCombatLockdown() then return false end
    CVar.RestoreAll()
    uninstalled = true
    local disable = C_AddOns and C_AddOns.DisableAddOn or _G.DisableAddOn
    local count = (C_AddOns and C_AddOns.GetNumAddOns or _G.GetNumAddOns)
    local info = (C_AddOns and C_AddOns.GetAddOnInfo or _G.GetAddOnInfo)
    if disable and count and info then
        local okN, n = pcall(count)
        for i = 1, (okN and tonumber(n)) or 0 do
            local okI, name = pcall(info, i)
            if okI and type(name) == "string" and (name == ADDON_NAME or name:find("^Zacui")) then
                pcall(disable, name)
            end
        end
    end
    local save = C_AddOns and C_AddOns.SaveAddOns or _G.SaveAddOns
    if save then pcall(save) end
    return true
end

function CVar.Uninstalled() return uninstalled end

-- ============================================================
-- RESET (the General page's "Reset ZacUI"): a fresh install
-- ============================================================
-- Puts back every game setting ZacUI changed, then clears ZacUI's saved
-- settings (account-wide and this character's) as the UI unloads, so the
-- next load is a fresh install: defaults, the welcome and the setup. No
-- addon is turned off. The wipe runs from a PLAYER_LOGOUT handler made
-- here, after every handler registered at load (theirs write their last
-- state first; ours empties it after). The caller reloads.
function CVar.ResetAll()
    if uninstalled then return false end
    if InCombatLockdown and InCombatLockdown() then return false end
    CVar.RestoreAll()
    uninstalled = true
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGOUT")
    f:SetScript("OnEvent", function()
        -- one mark survives: the next load counts as a fresh install and
        -- opens the setup straight away (Boot_Events, Tutorial_Core)
        _G.ZacUIDB = { resetOpenSetup = true }
        _G.ZacUICharDB = nil
    end)
    return true
end

-- ============================================================
-- LOGIN
-- ============================================================
-- Boot_Events' PLAYER_LOGIN calls AtLogin once. Nothing is made or
-- registered unless the record holds something to put back: an install
-- that never had a CVar written through here costs nothing at all. A pass
-- due in combat waits for the fight to end (the only frame this file ever
-- makes, made then).
local waiter
local function Pass()
    if InCombatLockdown and InCombatLockdown() then
        if not waiter then
            waiter = CreateFrame("Frame")
            waiter:SetScript("OnEvent", function(self)
                self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                pcall(CVar.LoginPass)
            end)
        end
        waiter:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    pcall(CVar.LoginPass)
end

function CVar.AtLogin()
    local r = Record(true)
    if not (r and (r.cvar or r.held or r.chars)) then return false end
    -- a beat after login, so every part has registered its owner check and
    -- the module switches have settled
    C_Timer.After(1, Pass)
    return true
end

-- shared with later ZacUI files and the parts
ns.CVar = CVar
