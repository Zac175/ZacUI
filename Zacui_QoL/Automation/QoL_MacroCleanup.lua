-- QoL_MacroCleanup - finds the macros nothing uses, so they can go.
-- Part of ZacUI; load order is set by the TOC.
--
-- WHAT "USED" MEANS. A macro is used when it sits in one of the 120
-- action slots (every bar addon, ZacUI's own bars included, draws those)
-- or a key is bound straight to it. Action bars live on the server, so
-- the only way to know is to look from inside the game: each character
-- writes down what it uses a few seconds after it logs in, and again
-- whenever the Macros tab is open.
--
-- ACCOUNT MACROS are shared by every character on the account, so one is
-- unused only when no character seen so far has it on a bar or a key.
-- The tab says which characters have been seen; a character never
-- logged in since this file arrived counts as unknown, so log into each
-- one before trusting the list. CHARACTER MACROS only need this
-- character.
--
-- NOTHING IS DELETED BY ITSELF. The tab lists what is unused and you
-- press Delete. Every deleted macro goes into a bin first (name, icon,
-- text, account or character), and Restore makes it again.
--
-- A macro is told apart by its name AND its text, so two macros with the
-- same name are two macros here. Never listed: the remover's linked
-- macros, anything carrying its #ZB (or older #ZacUIBuffs) lines, "dummy",
-- and (2026-11-20) the smart mount macro while that feature keeps it.
--
-- THE CLEANER (2026-11-20, Zac: "a fast macro deleter with maybe the
-- option to do it automatically as well"). Its window is
-- QoL_MacroWindow.lua (/zui macros): every macro with a tick, deleted in
-- one go. This file holds what it runs on:
--   MC.Survey()            every macro with what uses it
--   MC.DeleteAll(list)     many at once, each binned first
--   MC.Always()            names deleted again whenever they come back
--   MC.AutoPass(why)       the automatic part, ALL OFF AS SHIPPED:
--     autoNames    delete on sight the names on the always-delete list
--                  (the macros another addon keeps making)
--     autoMine     delete this character's own macros once they have
--                  gone unused for `days` days
--     autoAccount  the same for account macros no seen character uses
--   Settings in qol.macros (MC.DEFAULTS; nothing saved = what ships).
-- "Unused for N days" is counted from the first login that saw the macro
-- unused (ZacUIDB.macroIdle), whether or not anything is switched on, so
-- the days are real days. An automatic delete bins the macro like any
-- other; it runs a few seconds after login, never in a fight (it waits
-- for the fight to end), and a macro that another addon makes again more
-- than three times in a session is left alone with one line in chat.

local ADDON_NAME = ...
-- Zacui_QoL is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

-- shared state from earlier ZacUI files
local Print = ns.Print
local QoL = ns.QoL

local MC = {}
QoL.MacroCleanup = MC

local NEVER = { dummy = true }

local function MaxAccount() return MAX_ACCOUNT_MACROS or 120 end
local function MaxChar() return MAX_CHARACTER_MACROS or 18 end

local function Ident(name, body) return tostring(name) .. "\n" .. tostring(body or "") end

local function CharKey()
    return (UnitName("player") or "?") .. "-" .. ((GetRealmName and GetRealmName()) or "?")
end

local function Store()
    ZacUIDB.macroUse = type(ZacUIDB.macroUse) == "table" and ZacUIDB.macroUse or {}
    return ZacUIDB.macroUse
end

local function Bin()
    ZacUIDB.macroBin = type(ZacUIDB.macroBin) == "table" and ZacUIDB.macroBin or {}
    return ZacUIDB.macroBin
end
MC.Bin = Bin

-- Every macro now, in index order: { idx, name, icon, body, account }.
local function AllMacros()
    local out = {}
    local a, c = 0, 0
    if GetNumMacros then a, c = GetNumMacros() end
    for i = 1, a or 0 do
        local name, icon, body = GetMacroInfo(i)
        if name then out[#out + 1] = { idx = i, name = name, icon = icon, body = body or "", account = true } end
    end
    for i = MaxAccount() + 1, MaxAccount() + (c or 0) do
        local name, icon, body = GetMacroInfo(i)
        if name then out[#out + 1] = { idx = i, name = name, icon = icon, body = body or "", account = false } end
    end
    return out
end
MC.AllMacros = AllMacros

-- What this character uses right now: idents of macros on its action
-- slots, and of macros a key is bound to (bound by name).
local function UsedNow()
    local used = {}
    do
        local At = ns.ActionSlots.At
        for slot = 1, 120 do
            local kind, id = At(slot)
            if kind == "macro" and id then
                local name, _, body = GetMacroInfo(id)
                if name then used[Ident(name, body)] = true end
            end
        end
    end
    local boundNames = {}
    if GetNumBindings and GetBinding then
        for i = 1, GetNumBindings() do
            local command, _, key1, key2 = GetBinding(i)
            if type(command) == "string" and (key1 or key2) then
                local mname = command:match("^MACRO (.+)$")
                if mname then boundNames[mname] = true end
            end
        end
    end
    if next(boundNames) then
        for _, m in ipairs(AllMacros()) do
            if boundNames[m.name] then used[Ident(m.name, m.body)] = true end
        end
    end
    return used
end

-- Writes down what this character uses: the NAMES of the account macros
-- on its bars or keys (a character macro is only ever this character's
-- business). By name on purpose - another character's note must not go
-- stale when a macro's text is edited, and two macros sharing a name are
-- then both kept, which errs the safe way.
function MC.Record()
    if not GetMacroInfo then return end
    local used = UsedNow()
    local names, cnames = {}, {}
    for _, m in ipairs(AllMacros()) do
        if used[Ident(m.name, m.body)] then
            if m.account then names[m.name] = true else cnames[m.name] = true end
        end
    end
    -- cnames: this character's own macros in use - only ever read to
    -- answer "what do I actually use" from outside the game, never by
    -- the unused list (which looks at a character's own macros live)
    Store()[CharKey()] = { t = time(), names = names, cnames = cnames }
    return used
end

-- The names of macros a key is bound to on this character.
function MC.BoundNames()
    local out = {}
    if GetNumBindings and GetBinding then
        for i = 1, GetNumBindings() do
            local command, _, key1, key2 = GetBinding(i)
            if type(command) == "string" and (key1 or key2) then
                local mname = command:match("^MACRO (.+)$")
                if mname then out[mname] = true end
            end
        end
    end
    return out
end

-- Account macro names other seen characters have on their bars or keys:
-- { [name] = "Zacw, Zaccw" }.
function MC.UsedByOthers()
    local me = CharKey()
    local who = {}
    for ch, rec in pairs(Store()) do
        if ch ~= me and type(rec) == "table" then
            for n in pairs(type(rec.names) == "table" and rec.names or {}) do
                who[n] = who[n] or {}
                table.insert(who[n], (ch:match("^(.-)%-") or ch))
            end
        end
    end
    local out = {}
    for n, list in pairs(who) do table.sort(list) out[n] = table.concat(list, ", ") end
    return out
end

-- The smart mount macro while that feature keeps it (QoL_SmartMount makes
-- it again when it is missing, so deleting it only empties its bar slots).
local smartKey, smartIdx
local function SmartMountIndex()
    local SM = QoL.SmartMount
    if not (SM and SM.Cfg and SM.FindMacro and QoL.enabled) then return nil end
    local c = SM.Cfg()
    if not (type(c) == "table" and c.enabled and type(c.macro) == "string" and c.macro ~= "") then return nil end
    local key = c.macro .. "\031" .. ns.Macros.Version() .. "\031" .. ns.ActionSlots.Version()
    if key ~= smartKey then
        smartKey = key
        local okF, idx = pcall(SM.FindMacro, c.macro)
        smartIdx = okF and idx or 0
    end
    return (smartIdx and smartIdx ~= 0) and smartIdx or nil
end

local function Protected(m)
    if NEVER[m.name] then return true end
    if m.idx and m.idx == SmartMountIndex() then return true end
    if m.body:find("#ZacUIBuffs", 1, true) then return true end
    local BR = QoL.BuffRemover
    if BR and BR.HasMark and BR.HasMark(m.body) then return true end
    if BR and BR.IsLinked and BR.IsLinked(m.name) then return true end
    return false
end

-- The unused ones: account macros no seen character uses, and this
-- character's own macros it does not use. Also returns the characters
-- seen on this account, by name.
function MC.Unused()
    local used = MC.Record() or {}
    local me = CharKey()
    local otherNames = {}
    local seen = {}
    for who, rec in pairs(Store()) do
        seen[#seen + 1] = who
        if who ~= me and type(rec) == "table" then
            for n in pairs(type(rec.names) == "table" and rec.names or {}) do otherNames[n] = true end
        end
    end
    table.sort(seen)
    -- by name here too: a macro sharing its name with one in use is kept
    local all = AllMacros()
    local usedNames = {}
    for _, m in ipairs(all) do
        if used[Ident(m.name, m.body)] then usedNames[m.name] = true end
    end
    local account, mine = {}, {}
    for _, m in ipairs(all) do
        if not Protected(m) and not usedNames[m.name] then
            if m.account then
                if not otherNames[m.name] then account[#account + 1] = m end
            else
                mine[#mine + 1] = m
            end
        end
    end
    return account, mine, seen
end

-- Old mount macros the smart mount macro replaces (QoL_SmartMount):
-- other macros of its name, and macros that are nothing but mount
-- lines. They are on bars (so not "unused") but are done with.
function MC.Retired()
    local SM = QoL.SmartMount
    if not (SM and SM.Retired and SM.Cfg().enabled) then return {}, {} end
    return SM.Retired()
end

-- Deletes one macro (found again by name and text, since indexes move),
-- binning it first. Out of combat only.
-- opts.dedupe: not binned a second time when the very same macro is in
-- the bin already (a macro deleted on sight at every login).
function MC.Delete(m, opts)
    if InCombatLockdown() then return false, "not in combat" end
    for _, cur in ipairs(AllMacros()) do
        if cur.name == m.name and cur.body == m.body and cur.account == m.account then
            local bin = Bin()
            local binned = false
            if opts and opts.dedupe then
                for _, b in ipairs(bin) do
                    if b.name == cur.name and b.body == cur.body and (b.account and true or false) == cur.account then
                        binned = true
                        break
                    end
                end
            end
            if not binned then
                bin[#bin + 1] = { name = cur.name, icon = cur.icon, body = cur.body, account = cur.account,
                                  who = CharKey(), t = time() }
            end
            DeleteMacro(cur.idx)
            -- the indexes after it moved: shared maps read again
            ns.Macros.Invalidate()
            ns.ActionSlots.Invalidate()
            return true
        end
    end
    return false, "that macro is not there any more"
end

function MC.DeleteAll(list)
    local n = 0
    for _, m in ipairs(list) do
        if MC.Delete(m) then n = n + 1 end
    end
    return n
end

-- Makes a binned macro again (as an account macro where it was one and
-- there is room, else a character macro) and takes it out of the bin.
function MC.Restore(i)
    if InCombatLockdown() then return false, "not in combat" end
    local bin = Bin()
    local m = bin[i]
    if not m then return false, "not in the bin" end
    local a, c = 0, 0
    if GetNumMacros then a, c = GetNumMacros() end
    local asAccount
    if m.account and (a or 0) < MaxAccount() then
        asAccount = true
    elseif (c or 0) < MaxChar() then
        asAccount = false
    else
        return false, "no room for another macro"
    end
    -- (wanted back: no longer deleted on sight, or it would go again at once)
    if MC.IsAlways and MC.IsAlways(m.name) then MC.SetAlways(m.name, false) end
    CreateMacro(m.name, m.icon or 134400, m.body, (not asAccount) and true or nil)
    ns.Macros.Invalidate()
    ns.ActionSlots.Invalidate()
    table.remove(bin, i)
    return true
end

-- First line worth showing, for the list.
function MC.Preview(body)
    for line in ((body or "") .. "\n"):gmatch("([^\n]*)\n") do
        if line ~= "" and not line:find("^#") then
            if #line > 48 then line = line:sub(1, 46) .. ".." end
            return line
        end
    end
    return ""
end

-- ============================================================
-- THE CLEANER'S SETTINGS (qol.macros; nothing saved = what ships)
-- ============================================================
MC.DEFAULTS = { confirm = true, button = true, announce = true,
                autoNames = false, autoMine = false, autoAccount = false, days = 14 }
MC.DAYS_MIN, MC.DAYS_MAX = 1, 90
local function DB()
    local q = QoL.DB()
    if type(q.macros) ~= "table" then q.macros = {} end
    return q.macros
end
MC.DB = DB
function MC.Opt(key)
    local v = DB()[key]
    if v == nil then return MC.DEFAULTS[key] end
    return v
end
function MC.SetOpt(key, v)
    if MC.DEFAULTS[key] == nil then return end
    if key == "days" then
        v = math.floor((tonumber(v) or MC.DEFAULTS.days) + 0.5)
        if v < MC.DAYS_MIN then v = MC.DAYS_MIN elseif v > MC.DAYS_MAX then v = MC.DAYS_MAX end
    else
        v = v and true or false
    end
    if v == MC.DEFAULTS[key] then DB()[key] = nil else DB()[key] = v end
    if MC.Apply then MC.Apply() end
    -- the "Clean up" button on the macro window follows its setting at once
    if key == "button" then
        if ns.MacroCoverButton then pcall(ns.MacroCoverButton, v) end
        if MC.Window and MC.Window.SyncGameButton then pcall(MC.Window.SyncGameButton) end
    end
end

-- the always-delete list: { [name] = true }
function MC.Always()
    local d = DB()
    return type(d.always) == "table" and d.always or {}
end
function MC.IsAlways(name) return MC.Always()[name] == true end
function MC.SetAlways(name, on)
    if type(name) ~= "string" or name == "" then return end
    local d = DB()
    if on then
        if type(d.always) ~= "table" then d.always = {} end
        d.always[name] = true
    elseif type(d.always) == "table" then
        d.always[name] = nil
        if not next(d.always) then d.always = nil end
    end
    if MC.Apply then MC.Apply() end
end
function MC.AlwaysNames()
    local out = {}
    for n in pairs(MC.Always()) do out[#out + 1] = n end
    table.sort(out, function(x, y) return x:lower() < y:lower() end)
    return out
end

-- ============================================================
-- EVERY MACRO, AND WHAT USES IT (the window's list)
--   { idx, name, icon, body, account,
--     bar      on one of this character's action slots
--     key      a key is bound to it on this character
--     others   "Zacw, Zaccw": seen characters using this account macro
--     protected  ZacUI's own (never offered)
--     unused   nothing above, by the same rule as MC.Unused
--     always   its name is on the always-delete list
--     id       tells it apart in the window, two identical ones included }
-- ============================================================
function MC.Survey()
    local all = AllMacros()
    pcall(MC.Record)
    local onBar = {}
    do
        local At = ns.ActionSlots.At
        for slot = 1, 120 do
            local kind, id = At(slot)
            if kind == "macro" and id then
                local name, _, body = GetMacroInfo(id)
                if name then onBar[Ident(name, body)] = true end
            end
        end
    end
    local bound, others, always = MC.BoundNames(), MC.UsedByOthers(), MC.Always()
    local usedNames, seen = {}, {}
    for _, m in ipairs(all) do
        m.bar = onBar[Ident(m.name, m.body)] or false
        m.key = bound[m.name] or false
        if m.bar or m.key then usedNames[m.name] = true end
    end
    for _, m in ipairs(all) do
        m.others = m.account and others[m.name] or nil
        m.protected = Protected(m)
        m.always = always[m.name] == true
        -- (by name, as MC.Unused: a macro sharing its name with one in use is kept)
        m.unused = (not m.protected) and (not usedNames[m.name]) and not (m.account and m.others ~= nil)
        local base = (m.account and "a" or "c") .. "\n" .. Ident(m.name, m.body)
        seen[base] = (seen[base] or 0) + 1
        m.id = base .. "\n" .. seen[base]
    end
    return all
end

function MC.EmptyBin()
    local bin = Bin()
    local n = #bin
    for i = n, 1, -1 do bin[i] = nil end
    return n
end

-- several binned macros at once; `indexes` are places in the bin
function MC.RestoreMany(indexes)
    local list = {}
    for _, i in ipairs(indexes) do list[#list + 1] = i end
    table.sort(list, function(x, y) return x > y end)      -- from the end: the places before stay
    local n, why = 0, nil
    for _, i in ipairs(list) do
        local ok, w = MC.Restore(i)
        if ok then n = n + 1 else why = why or w end
    end
    return n, why
end

-- ============================================================
-- UNUSED FOR HOW LONG
-- ============================================================
local function Idle()
    ZacUIDB.macroIdle = type(ZacUIDB.macroIdle) == "table" and ZacUIDB.macroIdle or {}
    return ZacUIDB.macroIdle
end
local function IdleKey(m) return (m.account and "a" or CharKey()) .. "\n" .. Ident(m.name, m.body) end

-- Notes when each unused macro was first seen unused, forgets the ones in
-- use again or gone, and returns the unused ones with .idle = seconds.
function MC.Aging()
    local account, mine = MC.Unused()
    local idle, now = Idle(), time()
    local live, out = {}, {}
    for _, list in ipairs({ account, mine }) do
        for _, m in ipairs(list) do
            local k = IdleKey(m)
            live[k] = true
            idle[k] = tonumber(idle[k]) or now
            m.idle = math.max(0, now - idle[k])
            out[#out + 1] = m
        end
    end
    local mine2 = CharKey() .. "\n"
    for k in pairs(idle) do
        if not live[k] and (k:sub(1, 2) == "a\n" or k:sub(1, #mine2) == mine2) then idle[k] = nil end
    end
    return out
end

-- What the two unused rules would delete right now. all = true: as if
-- both were switched on (the settings page's "right now" line).
function MC.Due(all)
    local out = {}
    local limit = MC.Opt("days") * 86400
    local mineOn, accountOn = all or MC.Opt("autoMine"), all or MC.Opt("autoAccount")
    for _, m in ipairs(MC.Aging()) do
        if m.idle >= limit and ((m.account and accountOn) or (not m.account and mineOn)) then
            out[#out + 1] = m
        end
    end
    return out
end

-- ============================================================
-- THE AUTOMATIC PART (all off as shipped)
-- ============================================================
local SIGHT_MAX = 3
local sightCount, gaveUp = {}, {}
local autoPending = false
MC.SIGHT_MAX = SIGHT_MAX

function MC.AutoWanted()
    return (MC.Opt("autoNames") and next(MC.Always()) ~= nil) or MC.Opt("autoMine") or MC.Opt("autoAccount") or false
end

-- why: "login" | "combat" (a fight just ended) | "macros" (the macro list
-- changed: only the always-delete names are looked at) | anything else
function MC.AutoPass(why)
    if not QoL.enabled then return 0 end
    -- (the unused stamps are kept even with everything off: see the header)
    if why ~= "macros" then pcall(MC.Aging) end
    if not MC.AutoWanted() then
        autoPending = false
        return 0
    end
    if InCombatLockdown() then
        autoPending = true
        return 0
    end
    autoPending = false
    local gone = {}
    if MC.Opt("autoNames") then
        local always, counted = MC.Always(), {}
        for _, m in ipairs(AllMacros()) do
            if always[m.name] and not Protected(m) then
                if (sightCount[m.name] or 0) >= SIGHT_MAX and not counted[m.name] then
                    if not gaveUp[m.name] then
                        gaveUp[m.name] = true
                        Print("macros: \"" .. m.name .. "\" keeps being made again (another addon makes it), "
                            .. "so it is left alone until you log in again. Switch that addon's macro off to be rid of it.")
                    end
                elseif MC.Delete(m, { dedupe = true }) then
                    if not counted[m.name] then
                        counted[m.name] = true
                        sightCount[m.name] = (sightCount[m.name] or 0) + 1
                    end
                    gone[#gone + 1] = m.name
                end
            end
        end
    end
    if why ~= "macros" and (MC.Opt("autoMine") or MC.Opt("autoAccount")) then
        for _, m in ipairs(MC.Due()) do
            if MC.Delete(m) then
                gone[#gone + 1] = m.name
                Idle()[IdleKey(m)] = nil
            end
        end
    end
    if #gone > 0 then
        if MC.Opt("announce") then
            local shown = {}
            for i = 1, math.min(#gone, 6) do shown[i] = gone[i] end
            Print("macros: deleted " .. #gone .. " by itself (" .. table.concat(shown, ", ")
                .. (#gone > 6 and ", ..." or "") .. "). /zui macros > Bin brings one back.")
        end
        if MC.OnChanged then pcall(MC.OnChanged) end
    end
    return #gone, gone
end
function MC.AutoPending() return autoPending end
function MC._ResetSession() sightCount, gaveUp, autoPending = {}, {}, false end

-- The watcher: only armed while something automatic is switched on. The
-- macro list changing starts one short timer; nothing is done in the event.
local watch, watchTimer = nil, false
function MC.Apply()
    local want = QoL.enabled and MC.AutoWanted()
    if not want then
        if watch then watch:UnregisterAllEvents() end
        return
    end
    if not watch then
        watch = CreateFrame("Frame")
        watch:SetScript("OnEvent", function(_, event)
            if event == "PLAYER_REGEN_ENABLED" then
                if autoPending then C_Timer.After(1, function() pcall(MC.AutoPass, "combat") end) end
                return
            end
            if watchTimer then return end
            watchTimer = true
            C_Timer.After(2, function()
                watchTimer = false
                pcall(MC.AutoPass, "macros")
            end)
        end)
    end
    watch:RegisterEvent("PLAYER_REGEN_ENABLED")
    if MC.Opt("autoNames") and next(MC.Always()) ~= nil then
        watch:RegisterEvent("UPDATE_MACROS")
    else
        watch:UnregisterEvent("UPDATE_MACROS")
    end
end
function MC.Armed() return watch ~= nil and watch:IsEventRegistered("PLAYER_REGEN_ENABLED") or false end
do
    local base = QoL.EnableAutomation
    function QoL.EnableAutomation(...)
        if base then base(...) end
        pcall(MC.Apply)
    end
end

-- Each login: a few seconds in (the bars are filled by then), out of
-- combat, write down what this character uses.
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_ENTERING_WORLD")
boot:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    local function Try(n)
        if InCombatLockdown() then
            if n < 30 then C_Timer.After(5, function() Try(n + 1) end) end
            return
        end
        local ok, err = pcall(MC.Record)
        if not ok then Print("macros: could not read the bars (" .. tostring(err) .. ")") end
        -- the automatic part (nothing unless switched on), once the bars are read
        pcall(MC.Apply)
        if ok then pcall(MC.AutoPass, "login") end
    end
    C_Timer.After(5, function() Try(0) end)
end)
