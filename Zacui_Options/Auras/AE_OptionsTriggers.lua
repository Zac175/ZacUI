-- AE_OptionsTriggers - the aura editor's Triggers tab: every trigger kind
-- the format has, drawn from the kind tables in AE_Protos.
-- Part of ZacUI (Zacui_Auras). Written for ZacUI.
--
-- Loads after AE_Options and replaces its O.Triggers. Every option writes
-- the format's own keys (use_<name>, <name>, <name>_operator, ...) into
-- the trigger, the same as WeakAuras would, so a trigger built here reads
-- the same there. Number checks the format keeps as lists (a range: two
-- checks) are written as lists.
local ns = _G.ZacUI
if not ns then return end
local E = ns.AuraEngine
if not E then return end
local O = E.Options
if not O then return end

local P = E.Protos
local V = P and P.values or {}

-- ============================================================
-- SMALL BUILDERS (the same shape as AE_Options' own)
-- ============================================================
local order = 0
local function N() order = order + 1 return order end

local function Changed(d)
    if O.Changed then O.Changed(d) elseif E.Rebuild then E.Rebuild(d.id) end
end

local function Opt(t, extra)
    t.order = N()
    for k, v in pairs(extra or {}) do t[k] = v end
    return t
end

local function Field(d, t, key, conv)
    return function()
        local v = t[key]
        if conv and conv.get then return conv.get(v) end
        return v
    end, function(_, v)
        if conv and conv.set then v = conv.set(v) end
        t[key] = v
        Changed(d)
    end
end

local function Toggle(d, t, key, name, extra)
    local get, set = Field(d, t, key, { get = function(v) return v and true or false end,
        set = function(v) return v and true or nil end })
    return Opt({ type = "toggle", name = name, get = get, set = set }, extra)
end

local function Input(d, t, key, name, extra)
    local get, set = Field(d, t, key, { get = function(v) return v ~= nil and type(v) ~= "table" and tostring(v) or "" end })
    return Opt({ type = "input", name = name, get = get, set = set }, extra)
end

local function NumInput(d, t, key, name, extra)
    local get, set = Field(d, t, key, { get = function(v) return v ~= nil and tostring(v) or "" end,
        set = function(v) return tonumber(v) end })
    return Opt({ type = "input", name = name, get = get, set = set }, extra)
end

local function Select(d, t, key, name, values, extra)
    local get, set = Field(d, t, key)
    return Opt({ type = "select", name = name, values = values, get = get, set = set }, extra)
end

local function Code(d, t, key, name, lines)
    return Input(d, t, key, name, { multiline = lines or 10, width = "full" })
end

local function Header(name, extra) return Opt({ type = "header", name = name }, extra) end
local function Desc(text, extra) return Opt({ type = "description", name = text }, extra) end

-- nil / true / false as Either / Yes / No
local TRI = { [1] = "Either", [2] = "Yes", [3] = "No" }
local function Tri(d, t, key, name, extra)
    return Opt({ type = "select", name = name, values = TRI,
        get = function() local v = t[key] if v == true then return 2 elseif v == false then return 3 end return 1 end,
        set = function(_, v) t[key] = (v == 2) or (v == 3 and false) or nil Changed(d) end }, extra)
end

-- a comma list stored as a list of strings
local function ListInput(d, t, key, name, extra)
    return Opt({ type = "input", name = name, width = "full",
        get = function()
            local v = t[key]
            if type(v) == "table" then
                local out = {}
                for _, s in ipairs(v) do out[#out + 1] = tostring(s) end
                return table.concat(out, ", ")
            end
            return v ~= nil and tostring(v) or ""
        end,
        set = function(_, v)
            local out = {}
            for part in tostring(v or ""):gmatch("[^,]+") do
                part = part:gsub("^%s+", ""):gsub("%s+$", "")
                if part ~= "" then out[#out + 1] = part end
            end
            t[key] = out
            Changed(d)
        end }, extra)
end

-- a list option's own values (a function or a name in P.values)
local function Values(f, tr)
    return function() return P.Values(f, tr) end
end

local function All(...)
    local fns = { ... }
    return function(info)
        for _, fn in ipairs(fns) do if fn and fn(info) then return true end end
        return false
    end
end

-- ============================================================
-- ONE FIELD OF A BUILT-IN KIND
-- ============================================================
local function Hidden(f, tr) return function() return not P.Enabled(f, tr) end end

local OPS = {
    all = V.operator_types, noeq = V.operator_types_without_equal, eq = V.equality_operator_types,
}

-- slot i of a list option (number checks kept as lists)
local function Slot(d, tr, key, i, asNumber)
    return function()
        local v = tr[key]
        if type(v) == "table" then v = v[i] elseif i > 1 then v = nil end
        return v ~= nil and tostring(v) or ""
    end, function(_, v)
        local cur = tr[key]
        if type(cur) ~= "table" then cur = (cur ~= nil and cur ~= "") and { cur } or {} end
        if asNumber then v = tonumber(v) and tostring(v) or nil end
        if v == "" then v = nil end
        cur[i] = v
        -- keep it a list without holes
        local clean = {}
        for j = 1, 2 do if cur[j] ~= nil then clean[#clean + 1] = cur[j] end end
        tr[key] = clean
        Changed(d)
    end
end

local function OpSlot(d, tr, key, i)
    return function()
        local v = tr[key]
        if type(v) == "table" then return v[i] end
        if i == 1 then return v end
        return nil
    end, function(_, v)
        local cur = tr[key]
        if type(cur) ~= "table" then cur = cur and { cur } or {} end
        cur[i] = v
        tr[key] = cur
        Changed(d)
    end
end

local function UseToggle(d, tr, f, args, k, hidden)
    args[k .. "u"] = Toggle(d, tr, "use_" .. f.name, f.label, { hidden = hidden })
    return function() return hidden() or not tr["use_" .. f.name] end
end

local function UnitSelect(d, tr, f, args, k, hidden)
    local key = f.name
    local spec = "use_specific_" .. key
    local function vals()
        local out = {}
        for kk, vv in pairs(P.Values(f, tr)) do out[kk] = vv end
        return out
    end
    local off = hidden
    if f.check then off = UseToggle(d, tr, f, args, k, hidden) end
    args[k .. "s"] = Opt({ type = "select", name = f.check and "  is" or f.label, values = vals, hidden = off,
        get = function() if tr[spec] then return "member" end return tr[key] end,
        set = function(_, v)
            if v == "member" then
                tr[spec] = true
                if vals()[tr[key]] then tr[key] = "" end
            else
                tr[spec] = nil
                tr[key] = v
            end
            Changed(d)
        end })
    args[k .. "id"] = Input(d, tr, key, "  unit id (e.g. party1, boss1)", {
        hidden = function() return off() or not tr[spec] end })
end

local function DrawField(d, tr, f, args, k)
    local kind = f.kind
    local hidden = Hidden(f, tr)
    if kind == "header" then
        args[k] = Header(f.label, { hidden = hidden })
    elseif kind == "description" then
        args[k] = Desc(f.label, { hidden = hidden })
    elseif kind == "state" then
        return
    elseif kind == "unit" then
        UnitSelect(d, tr, f, args, k, hidden)
    elseif kind == "number" then
        local off = UseToggle(d, tr, f, args, k, hidden)
        local ops = OPS[f.ops or "all"] or V.operator_types
        if f.multi then
            for i = 1, 2 do
                local og, os = OpSlot(d, tr, f.name .. "_operator", i)
                local vg, vs = Slot(d, tr, f.name, i, true)
                local slotOff = off
                if i == 2 then
                    slotOff = function() return off() or type(tr[f.name]) ~= "table" or tr[f.name][1] == nil end
                end
                args[k .. "o" .. i] = Opt({ type = "select", name = i == 1 and "  is" or "  and", values = ops,
                    get = og, set = os, hidden = slotOff })
                args[k .. "v" .. i] = Opt({ type = "input", name = "  value", get = vg, set = vs, hidden = slotOff })
            end
        else
            if not f.noOperator then
                args[k .. "o"] = Select(d, tr, f.name .. "_operator", "  is", ops, { hidden = off })
            end
            args[k .. "v"] = Input(d, tr, f.name, "  value", { hidden = off })
        end
    elseif kind == "string" or kind == "strlist" or kind == "namerealm" or kind == "zones" then
        local off = f.req and hidden or UseToggle(d, tr, f, args, k, hidden)
        local hint = (kind == "strlist" and "  (comma list; - in front leaves one out)")
            or (kind == "namerealm" and "  (Name, Name-Realm or -Realm; comma list)")
            or (kind == "zones" and "  (map ids; g group, c with sub-zones, a area, i instance; - leaves out)") or ""
        if f.list then
            args[k .. "v"] = ListInput(d, tr, f.name, (f.req and f.label or "  value") .. hint, { hidden = off })
        else
            args[k .. "v"] = Input(d, tr, f.name, (f.req and f.label or "  value") .. hint, { hidden = off,
                multiline = (kind ~= "string") and 2 or nil, width = "full" })
        end
        if f.req then
            local get, set = args[k .. "v"].get, args[k .. "v"].set
            args[k .. "v"].set = function(info, v) tr["use_" .. f.name] = true set(info, v) end
        end
    elseif kind == "longstring" then
        local off = UseToggle(d, tr, f, args, k, hidden)
        args[k .. "o"] = Select(d, tr, f.name .. "_operator", "  ", V.string_operator_types, { hidden = off })
        args[k .. "v"] = Input(d, tr, f.name, "  text", { hidden = off, width = "full" })
        if f.caseless then
            args[k .. "c"] = Toggle(d, tr, f.name .. "_caseInsensitive", "  ignore upper / lower case", { hidden = off })
        end
    elseif kind == "select" then
        local off = hidden
        if not f.req then off = UseToggle(d, tr, f, args, k, hidden) end
        args[k .. "v"] = Select(d, tr, f.name, f.req and f.label or "  value", Values(f, tr), { hidden = off })
        if f.req then
            local set = args[k .. "v"].set
            args[k .. "v"].set = function(info, v) tr["use_" .. f.name] = true set(info, v) end
        end
    elseif kind == "multiselect" then
        local use = "use_" .. f.name
        local modes = f.noSingle and { [1] = "Off", [3] = "Any of these" } or { [1] = "Off", [2] = "This one", [3] = "Any of these" }
        args[k .. "m"] = Opt({ type = "select", name = f.label, values = modes, hidden = hidden,
            get = function() local u = tr[use] if u == true and not f.noSingle then return 2 elseif u == false or u == true then return 3 end return 1 end,
            set = function(_, v)
                if v == 2 then tr[use] = true
                elseif v == 3 then tr[use] = false
                else tr[use] = nil end
                if v ~= 1 and type(tr[f.name]) ~= "table" then tr[f.name] = {} end
                Changed(d)
            end })
        args[k .. "one"] = Opt({ type = "select", name = "  which", values = Values(f, tr),
            hidden = function() return hidden() or tr[use] ~= true or f.noSingle end,
            get = function() return type(tr[f.name]) == "table" and tr[f.name].single or nil end,
            set = function(_, v)
                tr[f.name] = type(tr[f.name]) == "table" and tr[f.name] or {}
                tr[f.name].single = v
                Changed(d)
            end })
        args[k .. "any"] = Opt({ type = "multiselect", name = "  any of", values = Values(f, tr),
            hidden = function() return hidden() or not (tr[use] == false or (f.noSingle and tr[use] == true)) end,
            get = function(_, key)
                local t = type(tr[f.name]) == "table" and tr[f.name].multi
                return t and (t[key] or t[tonumber(key) or key]) and true or false
            end,
            set = function(_, key, on)
                tr[f.name] = type(tr[f.name]) == "table" and tr[f.name] or {}
                tr[f.name].multi = type(tr[f.name].multi) == "table" and tr[f.name].multi or {}
                tr[f.name].multi[key] = on and true or nil
                Changed(d)
            end })
    elseif kind == "tristate" then
        args[k] = Tri(d, tr, "use_" .. f.name, f.label, { hidden = hidden })
    elseif kind == "toggle" then
        args[k] = Toggle(d, tr, "use_" .. f.name, f.label, { hidden = hidden })
    elseif kind == "spell" or kind == "item" then
        local off = f.req and hidden or UseToggle(d, tr, f, args, k, hidden)
        args[k .. "v"] = Input(d, tr, f.name, f.req and (f.label .. " (name or id)") or "  name or id", { hidden = off })
        if f.req then
            local set = args[k .. "v"].set
            args[k .. "v"].set = function(info, v) tr["use_" .. f.name] = true set(info, v) end
        end
        if f.exact then
            args[k .. "x"] = Toggle(d, tr, "use_exact_" .. f.name, "  exactly this id", { hidden = off })
        end
    elseif kind == "spells" then
        local off = UseToggle(d, tr, f, args, k, hidden)
        args[k .. "v"] = ListInput(d, tr, f.name, f.exact and "  spell ids (comma list)" or "  names or ids (comma list)", { hidden = off })
    end
end

-- the options the format adds to timed event kinds
local function EventExtras(d, tr, def, args, k)
    if def.timed then
        args[k .. "dur"] = Input(d, tr, "duration", "Show for (seconds)")
    end
    if def.count then
        args[k .. "cu"] = Toggle(d, tr, "use_count", "Only some of them")
        args[k .. "cv"] = Input(d, tr, "count", "  which (e.g. 2 or 1-3 or 2/2)", { hidden = function() return not tr.use_count end })
    end
    if def.delay then
        args[k .. "du"] = Toggle(d, tr, "use_delay", "Wait before showing")
        args[k .. "dv"] = NumInput(d, tr, "delay", "  seconds", { hidden = function() return not tr.use_delay end })
    end
end

-- the defaults a kind starts with
local function Defaults(tr, def)
    for _, f in ipairs(def.fields) do
        if f.default ~= nil and tr[f.name] == nil then tr[f.name] = f.default end
    end
    if def.defaultUnit and tr.unit == nil then tr.unit = def.defaultUnit end
end
O.TriggerDefaults = Defaults

-- ============================================================
-- BUFF / DEBUFF
-- ============================================================
local function AuraArgs(d, tr, args, k)
    local function group() return tr.unit == "group" or tr.unit == "party" or tr.unit == "raid" end
    local function multi() local u = tr.unit return group() or u == "nameplate" or u == "boss" or u == "multi" end
    local function notMulti() return not multi() end
    local function single() return not multi() end
    local function canCheck()
        if multi() then return tr.unit ~= "multi" end
        local m = tr.matchesShowOn
        if m == "showOnMissing" then return false end
        if m == nil or m == "showOnActive" or m == "showOnMatches" then return true end
        return tr.showClones and true or false
    end
    args[k .. "unit"] = Select(d, tr, "unit", "On", V.unit_types_bufftrigger_2)
    args[k .. "spec"] = Input(d, tr, "specificUnit", "  unit id (e.g. party1)", { hidden = function() return tr.unit ~= "member" end })
    args[k .. "dt"] = Select(d, tr, "debuffType", "Kind of aura", V.debuff_types)
    args[k .. "un"] = Toggle(d, tr, "useName", "Only these (names; ids stand for their names)")
    args[k .. "names"] = ListInput(d, tr, "auranames", "  names", { hidden = function() return not tr.useName end })
    args[k .. "ue"] = Toggle(d, tr, "useExactSpellId", "Only these exact spell ids")
    args[k .. "ids"] = ListInput(d, tr, "auraspellids", "  spell ids", { hidden = function() return not tr.useExactSpellId end })
    args[k .. "uin"] = Toggle(d, tr, "useIgnoreName", "Leave out these names", { hidden = function() return not canCheck() end })
    args[k .. "inames"] = ListInput(d, tr, "ignoreAuraNames", "  names", { hidden = function() return not (canCheck() and tr.useIgnoreName) end })
    args[k .. "uie"] = Toggle(d, tr, "useIgnoreExactSpellId", "Leave out these spell ids", { hidden = function() return not canCheck() end })
    args[k .. "iids"] = ListInput(d, tr, "ignoreAuraSpellids", "  spell ids", { hidden = function() return not (canCheck() and tr.useIgnoreExactSpellId) end })
    args[k .. "own"] = Opt({ type = "select", name = "Cast by", values = { [1] = "Anyone", [2] = "Me", [3] = "Not me" },
        get = function() if tr.ownOnly == true then return 2 elseif tr.ownOnly == false then return 3 end return 1 end,
        set = function(_, v) tr.ownOnly = (v == 2) or (v == 3 and false) or nil Changed(d) end })
    args[k .. "show"] = Select(d, tr, "matchesShowOn", "Show", V.bufftrigger_2_progress_behavior_types, { hidden = multi })
    args[k .. "mco"] = Select(d, tr, "match_countOperator", "  match count", V.operator_types,
        { hidden = function() return multi() or tr.matchesShowOn ~= "showOnMatches" end })
    args[k .. "mcv"] = Input(d, tr, "match_count", "  value", { hidden = function() return multi() or tr.matchesShowOn ~= "showOnMatches" end })
    args[k .. "ux"] = Toggle(d, tr, "unitExists", "Show even when the unit is not there",
        { hidden = function() return multi() or tr.unit == "player" end })
    args[k .. "clones"] = Toggle(d, tr, "showClones", "A display per match",
        { hidden = function() return single() and tr.matchesShowOn == "showOnMissing" end })
    args[k .. "cpu"] = Toggle(d, tr, "combinePerUnit", "  one per unit", { hidden = function() return not (multi() and tr.showClones) end })
    args[k .. "pum"] = Select(d, tr, "perUnitMode", "  which units", V.bufftrigger_2_per_unit_mode,
        { hidden = function() return not (multi() and tr.showClones and tr.combinePerUnit and tr.unit ~= "multi") end })
    args[k .. "cm"] = Select(d, tr, "combineMode", "Prefer", V.bufftrigger_2_preferred_match_types,
        { hidden = function() return tr.showClones and not (multi() and tr.combinePerUnit) end })

    args[k .. "h2"] = Header("Each aura", { hidden = function() return not canCheck() end })
    local function chk(fn) return function() return not canCheck() or (fn and fn()) end end
    args[k .. "stu"] = Toggle(d, tr, "useStacks", "Stack count", { hidden = chk() })
    args[k .. "sto"] = Select(d, tr, "stacksOperator", "  is", V.operator_types, { hidden = chk(function() return not tr.useStacks end) })
    args[k .. "stv"] = Input(d, tr, "stacks", "  value", { hidden = chk(function() return not tr.useStacks end) })
    args[k .. "rmu"] = Toggle(d, tr, "useRem", "Time left", { hidden = chk() })
    args[k .. "rmo"] = Select(d, tr, "remOperator", "  is", V.operator_types, { hidden = chk(function() return not tr.useRem end) })
    args[k .. "rmv"] = Input(d, tr, "rem", "  seconds", { hidden = chk(function() return not tr.useRem end) })
    args[k .. "ttu"] = Toggle(d, tr, "useTotal", "Total duration", { hidden = chk() })
    args[k .. "tto"] = Select(d, tr, "totalOperator", "  is", V.operator_types, { hidden = chk(function() return not tr.useTotal end) })
    args[k .. "ttv"] = Input(d, tr, "total", "  seconds", { hidden = chk(function() return not tr.useTotal end) })
    args[k .. "steal"] = Tri(d, tr, "use_stealable", "Can be stolen / purged", { hidden = chk() })
    args[k .. "boss"] = Tri(d, tr, "use_isBossDebuff", "Cast by a boss", { hidden = chk() })
    args[k .. "bypl"] = Tri(d, tr, "use_castByPlayer", "Cast by a player", { hidden = chk() })
    args[k .. "dcu"] = Toggle(d, tr, "use_debuffClass", "Debuff type", { hidden = chk() })
    args[k .. "dcv"] = Opt({ type = "multiselect", name = "  any of", values = V.debuff_class_types,
        hidden = chk(function() return not tr.use_debuffClass end),
        get = function(_, key) return type(tr.debuffClass) == "table" and tr.debuffClass[key] and true or false end,
        set = function(_, key, on)
            tr.debuffClass = type(tr.debuffClass) == "table" and tr.debuffClass or {}
            tr.debuffClass[key] = on and true or nil
            Changed(d)
        end })
    args[k .. "npu"] = Toggle(d, tr, "useNamePattern", "Name pattern", { hidden = chk() })
    args[k .. "npo"] = Select(d, tr, "namePattern_operator", "  ", V.string_operator_types, { hidden = chk(function() return not tr.useNamePattern end) })
    args[k .. "npv"] = Input(d, tr, "namePattern_name", "  text", { hidden = chk(function() return not tr.useNamePattern end) })
    args[k .. "ft"] = Toggle(d, tr, "fetchTooltip", "Read the tooltip", { hidden = function() return tr.unit == "multi" or (single() and tr.matchesShowOn == "showOnMissing") end })
    local function tipOff() return not canCheck() or not tr.fetchTooltip end
    args[k .. "tpu"] = Toggle(d, tr, "use_tooltip", "  tooltip text", { hidden = tipOff })
    args[k .. "tpo"] = Select(d, tr, "tooltip_operator", "    ", V.string_operator_types, { hidden = function() return tipOff() or not tr.use_tooltip end })
    args[k .. "tpv"] = Input(d, tr, "tooltip", "    text", { hidden = function() return tipOff() or not tr.use_tooltip end })
    args[k .. "tvu"] = Toggle(d, tr, "use_tooltipValue", "  a number in the tooltip", { hidden = tipOff })
    args[k .. "tvn"] = Select(d, tr, "tooltipValueNumber", "    which number", V.tooltip_count, { hidden = function() return tipOff() or not tr.use_tooltipValue end })
    args[k .. "tvo"] = Select(d, tr, "tooltipValue_operator", "    is", V.operator_types, { hidden = function() return tipOff() or not tr.use_tooltipValue end })
    args[k .. "tvv"] = Input(d, tr, "tooltipValue", "    value", { hidden = function() return tipOff() or not tr.use_tooltipValue end })

    args[k .. "h3"] = Header("Units", { hidden = notMulti })
    args[k .. "gcu"] = Toggle(d, tr, "useGroup_count", "Units with it", { hidden = function() return not multi() or tr.unit == "multi" end })
    args[k .. "gco"] = Select(d, tr, "group_countOperator", "  is", V.operator_types, { hidden = function() return not multi() or not tr.useGroup_count end })
    args[k .. "gcv"] = Input(d, tr, "group_count", "  how many (a number, 50% or 1/2)", { hidden = function() return not multi() or not tr.useGroup_count end })
    args[k .. "mtu"] = Toggle(d, tr, "useMatch_count", "Matches in all", { hidden = notMulti })
    args[k .. "mto"] = Select(d, tr, "match_countOperator", "  is", V.operator_types, { hidden = function() return not multi() or not tr.useMatch_count end })
    args[k .. "mtv"] = Input(d, tr, "match_count", "  value", { hidden = function() return not multi() or not tr.useMatch_count end })
    local function perUnit() return multi() and tr.showClones and tr.combinePerUnit and tr.perUnitMode ~= "unaffected" end
    args[k .. "mpu"] = Toggle(d, tr, "useMatchPerUnit_count", "Matches on each unit", { hidden = function() return not perUnit() end })
    args[k .. "mpo"] = Select(d, tr, "matchPerUnit_countOperator", "  is", V.operator_types, { hidden = function() return not perUnit() or not tr.useMatchPerUnit_count end })
    args[k .. "mpv"] = Input(d, tr, "matchPerUnit_count", "  value", { hidden = function() return not perUnit() or not tr.useMatchPerUnit_count end })
    local function notGroup() return not group() end
    local function notGroupOrPlate() return not (group() or tr.unit == "nameplate") end
    args[k .. "self"] = Toggle(d, tr, "ignoreSelf", "Leave yourself out", { hidden = notGroupOrPlate })
    args[k .. "dead"] = Toggle(d, tr, "ignoreDead", "Leave the dead out", { hidden = notGroup })
    args[k .. "dc"] = Toggle(d, tr, "ignoreDisconnected", "Leave the offline out", { hidden = notGroup })
    args[k .. "inv"] = Toggle(d, tr, "ignoreInvisible", "Leave out the ones too far to see", { hidden = notGroup })
    args[k .. "pets"] = Toggle(d, tr, "use_includePets", "Include pets", { hidden = notGroup })
    args[k .. "petsv"] = Select(d, tr, "includePets", "  which", V.include_pets_types, { hidden = function() return notGroup() or not tr.use_includePets end })
    local function MultiOf(key, useKey, name, values, hide)
        args[k .. useKey] = Toggle(d, tr, useKey, name, { hidden = hide })
        args[k .. key] = Opt({ type = "multiselect", name = "  any of", values = values,
            hidden = function() return hide() or not tr[useKey] end,
            get = function(_, kk) return type(tr[key]) == "table" and tr[key][kk] and true or false end,
            set = function(_, kk, on)
                tr[key] = type(tr[key]) == "table" and tr[key] or {}
                tr[key][kk] = on and true or nil
                Changed(d)
            end })
    end
    MultiOf("group_role", "useGroupRole", "Role", V.role_types, notGroup)
    MultiOf("raid_role", "useRaidRole", "Raid role", V.raid_role_types, notGroup)
    MultiOf("class", "useClass", "Class", V.class_types, notGroup)
    args[k .. "hu"] = Toggle(d, tr, "useHostility", "Hostility", { hidden = notGroupOrPlate })
    args[k .. "hv"] = Select(d, tr, "hostility", "  is", V.hostility_types, { hidden = function() return notGroupOrPlate() or not tr.useHostility end })
    args[k .. "nmu"] = Toggle(d, tr, "useUnitName", "Unit name / realm", { hidden = notGroup })
    args[k .. "nmv"] = Input(d, tr, "unitName", "  Name, Name-Realm or -Realm (comma list)", { hidden = function() return notGroup() or not tr.useUnitName end })
    local function notPlateBoss() return not (tr.unit == "nameplate" or tr.unit == "boss") end
    args[k .. "npcu"] = Toggle(d, tr, "useNpcId", "Npc id(s)", { hidden = notPlateBoss })
    args[k .. "npcv"] = Input(d, tr, "npcId", "  ids (comma list; - leaves one out)", { hidden = function() return notPlateBoss() or not tr.useNpcId end })
    args[k .. "aff"] = Toggle(d, tr, "useAffected", "Name who has it and who has not", { hidden = notGroup })
    args[k .. "h4"] = Header("More")
    args[k .. "role"] = Toggle(d, tr, "fetchRole", "Know the unit's role", { hidden = function() return tr.unit == "multi" end })
    args[k .. "mark"] = Toggle(d, tr, "fetchRaidMark", "Know the unit's raid mark", { hidden = function() return tr.unit == "multi" end })
end

-- ============================================================
-- CUSTOM CODE
-- ============================================================
local function CustomArgs(d, t, tr, args, k)
    args[k .. "ct"] = Select(d, tr, "custom_type", "Style", V.custom_trigger_types)
    args[k .. "ev"] = Input(d, tr, "events", "Events", { width = "full",
        hidden = function() return tr.custom_type == "status" and tr.check == "update" end,
        desc = "Comma separated: UNIT_AURA:player, CLEU:SPELL_CAST_SUCCESS, WA_MY_EVENT" })
    args[k .. "chk"] = Select(d, tr, "check", "Check", V.check_types,
        { hidden = function() return tr.custom_type ~= "status" end })
    args[k .. "code"] = Code(d, tr, "custom", "Code", 14)
    args[k .. "hide"] = Select(d, tr, "custom_hide", "Hide", V.eventend_types,
        { hidden = function() return tr.custom_type ~= "event" end })
    args[k .. "dur"] = Input(d, tr, "duration", "  seconds", { hidden = function() return tr.custom_type ~= "event" or tr.custom_hide ~= "timed" end })
    args[k .. "un"] = Code(d, t.untrigger, "custom", "Hide code", 6)
    args[k .. "un"].hidden = function() return tr.custom_type ~= "event" or tr.custom_hide ~= "custom" end
    args[k .. "cv"] = Code(d, tr, "customVariables", "Condition fields (optional)", 4)
    args[k .. "cv"].hidden = function() return tr.custom_type ~= "stateupdate" end
    args[k .. "cd"] = Code(d, tr, "customDuration", "Duration / progress (optional)", 4)
    args[k .. "cn"] = Code(d, tr, "customName", "Name (optional)", 3)
    args[k .. "ci"] = Code(d, tr, "customIcon", "Icon (optional)", 3)
    args[k .. "cs"] = Code(d, tr, "customStacks", "Stacks (optional)", 3)
    args[k .. "cx"] = Code(d, tr, "customTexture", "Texture (optional)", 3)
    for _, key in ipairs({ "cd", "cn", "ci", "cs", "cx" }) do
        args[k .. key].hidden = function() return tr.custom_type == "stateupdate" end
    end
end

-- ============================================================
-- ONE TRIGGER
-- ============================================================
local function FirstEvent(cat)
    local best
    for name in pairs(P.Category(cat)) do if not best or name < best then best = name end end
    return best
end

local function TriggerArgs(d, i, t, args)
    local tr = t.trigger
    local k = "t" .. i
    args[k .. "h"] = Header("Trigger " .. i)
    args[k .. "type"] = Opt({ type = "select", name = "Kind", values = V.trigger_types,
        get = function() return tr.type end,
        set = function(_, v)
            tr.type = v
            if v == "aura2" then
                tr.unit = tr.unit or "player"
                tr.debuffType = tr.debuffType or "HELPFUL"
            elseif v ~= "custom" then
                local def = P.Get(tr.event)
                if not def or def.type ~= v then tr.event = FirstEvent(v) end
                def = P.Get(tr.event)
                if def then Defaults(tr, def) end
            else
                tr.custom_type = tr.custom_type or "event"
            end
            Changed(d)
        end })
    local ty = tr.type
    if ty == "aura2" then
        AuraArgs(d, tr, args, k)
    elseif ty == "custom" then
        CustomArgs(d, t, tr, args, k)
    elseif P.Category(ty) and next(P.Category(ty)) or ty == "status" then
        local cat = ty == "status" and "unit" or ty
        args[k .. "ev"] = Opt({ type = "select", name = "Which", values = function() return P.Category(cat) end,
            get = function() return tr.event end,
            set = function(_, v)
                tr.event = v
                local def = P.Get(v)
                if def then Defaults(tr, def) end
                Changed(d)
            end })
        local def = P.Get(tr.event)
        if def then
            for j, f in ipairs(def.fields) do
                DrawField(d, tr, f, args, k .. "f" .. j)
            end
            EventExtras(d, tr, def, args, k)
        elseif tr.event then
            args[k .. "nos"] = Desc("'" .. tostring(tr.event) .. "' is not a kind this engine knows.")
        end
    else
        args[k .. "nos"] = Desc("This kind of trigger ('" .. tostring(ty) .. "') is not one the engine runs.")
    end
    args[k .. "rm"] = Opt({ type = "execute", name = "Remove trigger " .. i,
        hidden = function() return E.TriggerCount(d) <= 1 end,
        func = function() table.remove(d.triggers, i) Changed(d) end })
end

function O.Triggers(d)
    order = 0
    local args = {}
    d.triggers = type(d.triggers) == "table" and d.triggers or {}
    if E.IsGroup(d) then
        args.none = Desc("Groups have no triggers; each display inside has its own.")
        return { type = "group", args = args }
    end
    if not P then
        args.none = Desc("The trigger kinds did not load.")
        return { type = "group", args = args }
    end
    args.logic = Select(d, d.triggers, "disjunctive", "Shows when", { any = "Any trigger is active",
        all = "All triggers are active", custom = "Custom code decides" })
    do  -- missing reads as "all" (as WeakAuras); show that
        local get = args.logic.get
        if get then args.logic.get = function(...) return get(...) or "all" end end
    end
    args.logicCode = Code(d, d.triggers, "customTriggerLogic", "Logic code", 5)
    args.logicCode.hidden = function() return d.triggers.disjunctive ~= "custom" end
    for i, t in ipairs(d.triggers) do
        if type(t) == "table" then
            t.trigger = type(t.trigger) == "table" and t.trigger or {}
            t.untrigger = type(t.untrigger) == "table" and t.untrigger or {}
            TriggerArgs(d, i, t, args)
        end
    end
    args.add = Opt({ type = "execute", name = "Add a trigger", func = function()
        table.insert(d.triggers, { trigger = { type = "aura2", unit = "player", debuffType = "HELPFUL" }, untrigger = {} })
        Changed(d)
    end })
    return { type = "group", args = args }
end
