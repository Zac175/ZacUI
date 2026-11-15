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
-- macros, anything carrying its #ZB (or older #ZacUIBuffs) lines, and "dummy".

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

local function Protected(m)
    if NEVER[m.name] then return true end
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
function MC.Delete(m)
    if InCombatLockdown() then return false, "not in combat" end
    for _, cur in ipairs(AllMacros()) do
        if cur.name == m.name and cur.body == m.body and cur.account == m.account then
            local bin = Bin()
            bin[#bin + 1] = { name = cur.name, icon = cur.icon, body = cur.body, account = cur.account,
                              who = CharKey(), t = time() }
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
    if m.account and (a or 0) < MaxAccount() then
        CreateMacro(m.name, m.icon or 134400, m.body, nil)
    elseif (c or 0) < MaxChar() then
        CreateMacro(m.name, m.icon or 134400, m.body, true)
    else
        return false, "no room for another macro"
    end
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
    end
    C_Timer.After(5, function() Try(0) end)
end)
