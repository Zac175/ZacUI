-- HUD_V2_Conditions - Class HUD v2: an icon shown only with (or without)
-- a talent, or only in (or out of) a stance or form (2026-11-18). No
-- rule: nothing here runs. A rule never turns an icon ON that its row has
-- off (your tick, the spec's preset): it only takes one away.
--   where          the grid, the utility row, the buff row and the debuff
--                  row: the same "is this entry off its row" question the
--                  engine asks on its 0.2 s pass (V2Off), answered here
--                  only during a pass, so the page's ticks stay your own.
--   talents        Classic Era / TBC: the talent by tree and place
--                  (checked against its name), a rank in it = you have
--                  it. WoW Forever / Retail: the talent's spell among the
--                  game's talent nodes, the node bought (a choice node:
--                  the entry picked). Read when a rule first needs it and
--                  again only after a talent event (the events only count
--                  up a number).
--   stance / form  the spell of the stance bar's active entry
--                  (GetShapeshiftForm + GetShapeshiftFormInfo), read once
--                  per pass and only when a rule asks.
--   hidden values  an answer the game hides decides nothing: the icon
--                  shows as if it had no rule.
-- Settings: cfg.v2.cond[row][key] = { tMode = "with" | "without",
--           tab, index (Classic) or spell (Forever / Retail), tName,
--           fMode = "in" | "out", form = <spell id, 0 = none>, fName }.
-- Part of ZacUI; load order is set by the TOC (after HUD_V2_CastBar).

local ns = _G.ZacUI
if not ns or not ns.HUD or not ns.HUD.V2 then return end
local HUD = ns.HUD
local V2 = HUD.V2
local Engine = HUD.ClassEngine

local ROWS = { "main", "utility", "buffs", "debuffs" }
local ROW_LIST = { main = "grid", utility = "utility", buffs = "buffRow", debuffs = "debuffRow" }
local ROW_PREFIX = { main = "", utility = "Utility: ", buffs = "Buff: ", debuffs = "Debuff: " }
local TALENT_EVENTS = { "CHARACTER_POINTS_CHANGED", "PLAYER_TALENT_UPDATE", "ACTIVE_TALENT_GROUP_CHANGED",
    "TRAIT_CONFIG_UPDATED", "PLAYER_LEVEL_UP", "PLAYER_SPECIALIZATION_CHANGED" }

local function Cond(cfg, create) return V2.Sub(cfg, "cond", create) end
V2.CondCfg = Cond

local function Plain(v)
    if v == nil or ns.IsSecret(v) then return nil end
    return v
end

-- the rule of one entry (nil = none)
local function RuleOf(cfg, row, key, create)
    local c = Cond(cfg, create)
    if not c then return nil end
    local r = c[row]
    if type(r) ~= "table" then
        if not create then return nil end
        r = {}
        c[row] = r
    end
    local rule = r[key]
    if type(rule) ~= "table" then
        if not create then return nil end
        rule = {}
        r[key] = rule
    end
    return rule
end
V2.CondRule = RuleOf

-- emptied rules and rows go, and the cond table with them. A talent mode
-- with no talent picked says nothing: it goes too, except on the entry
-- the page is on (keepRow, keepKey), where the talent is picked next.
local function Prune(cfg, keepRow, keepKey)
    local c = Cond(cfg)
    if not c then return end
    for row, r in pairs(c) do
        if type(r) ~= "table" then
            c[row] = nil
        else
            for key, rule in pairs(r) do
                if type(rule) ~= "table" then
                    r[key] = nil
                else
                    if rule.tMode and not (rule.tab or rule.spell) and not (row == keepRow and key == keepKey) then
                        rule.tMode = nil
                    end
                    if not rule.tMode then rule.tab, rule.index, rule.spell, rule.tName = nil, nil, nil, nil end
                    if not rule.fMode then rule.form, rule.fName = nil, nil end
                    if next(rule) == nil then r[key] = nil end
                end
            end
            if next(r) == nil then c[row] = nil end
        end
    end
    V2.Tidy(cfg)
end

-- ------------------------------------------------------------
-- talents
-- ------------------------------------------------------------
-- which talent data this client has: "talents" (trees and places),
-- "traits" (talent nodes) or nil
function V2.TalentBackend()
    local CSI = C_SpecializationInfo
    if GetNumTalentTabs and GetNumTalents and ((CSI and CSI.GetTalentInfo) or GetTalentInfo) then return "talents" end
    local CT, Tr = C_ClassTalents, C_Traits
    if CT and Tr and CT.GetActiveConfigID and Tr.GetConfigInfo and Tr.GetTreeNodes and Tr.GetNodeInfo
        and Tr.GetEntryInfo and Tr.GetDefinitionInfo then
        return "traits"
    end
    return nil
end

-- a Classic talent: name, rank (nil where the client gives none)
local function TalentAt(tab, i)
    local CSI = C_SpecializationInfo
    if CSI and CSI.GetTalentInfo then
        local ok, t = pcall(CSI.GetTalentInfo, { specializationIndex = tab, talentIndex = i })
        if ok and type(t) == "table" then return Plain(t.name), Plain(t.rank) end
    end
    if GetTalentInfo then
        local ok, name, _, _, _, rank = pcall(GetTalentInfo, tab, i)
        if ok then return Plain(name), Plain(rank) end
    end
    return nil
end

local function EachTalent(fn)
    local okN, tabs = pcall(GetNumTalentTabs)
    tabs = okN and Plain(tabs) or 0
    if type(tabs) ~= "number" then return end
    for tab = 1, tabs do
        local okT, n = pcall(GetNumTalents, tab)
        n = okT and Plain(n) or 0
        if type(n) == "number" then
            for i = 1, n do
                local name, rank = TalentAt(tab, i)
                if type(name) == "string" and name ~= "" then fn(tab, i, name, rank) end
            end
        end
    end
end

-- the talent nodes (WoW Forever, Retail): fn(spellID, name, has)
local function EachTrait(fn)
    local CT, Tr = C_ClassTalents, C_Traits
    pcall(function()
        local configID = CT.GetActiveConfigID()
        if not configID then return end
        local cfg = Tr.GetConfigInfo(configID)
        for _, treeID in ipairs(cfg and cfg.treeIDs or {}) do
            for _, nodeID in ipairs(Tr.GetTreeNodes(treeID) or {}) do
                local info = Tr.GetNodeInfo(configID, nodeID)
                -- (another spec's nodes sit in the same tree, not visible)
                if type(info) == "table" and info.isVisible ~= false and type(info.entryIDs) == "table" then
                    local rank = Plain(info.currentRank) or Plain(info.activeRank) or Plain(info.ranksPurchased) or 0
                    local bought = type(rank) == "number" and rank > 0
                    local active = type(info.activeEntry) == "table" and Plain(info.activeEntry.entryID) or nil
                    for _, entryID in ipairs(info.entryIDs) do
                        local e = Tr.GetEntryInfo(configID, entryID)
                        local d = type(e) == "table" and e.definitionID and Tr.GetDefinitionInfo(e.definitionID)
                        local spellID = type(d) == "table" and Plain(d.spellID) or nil
                        if type(spellID) == "number" then
                            local name = Plain(d.overrideName)
                            if type(name) ~= "string" or name == "" then
                                name = HUD.GetSpellInfo and Plain(HUD.GetSpellInfo(spellID)) or nil
                            end
                            -- a choice node: only the entry picked is had
                            fn(spellID, name, bought and (#info.entryIDs == 1 or active == entryID))
                        end
                    end
                end
            end
        end
    end)
end

-- the talents for the page's list, by name: { { value, text } }
function V2.TalentItems()
    local out, seen = {}, {}
    local backend = V2.TalentBackend()
    if backend == "talents" then
        EachTalent(function(tab, i, name)
            out[#out + 1] = { value = "t:" .. tab .. ":" .. i, text = name }
        end)
    elseif backend == "traits" then
        EachTrait(function(spellID, name)
            if type(name) == "string" and name ~= "" and not seen[spellID] then
                seen[spellID] = true
                out[#out + 1] = { value = "s:" .. spellID, text = name }
            end
        end)
    end
    table.sort(out, function(a, b)
        if a.text ~= b.text then return a.text < b.text end
        return a.value < b.value
    end)
    return out
end

-- talents changed: a number counts up (the event does nothing else)
local talentVer = 1
local watch
local function WatchTalents()
    if watch then return end
    watch = CreateFrame("Frame")
    local valid = C_EventUtils and C_EventUtils.IsEventValid
    for _, e in ipairs(TALENT_EVENTS) do
        if not valid or valid(e) then pcall(watch.RegisterEvent, watch, e) end
    end
    watch:SetScript("OnEvent", function() talentVer = talentVer + 1 end)
end
function V2.CondTalentsChanged() talentVer = talentVer + 1 end

local traitSet, traitVer
local function Traits()
    if traitVer ~= talentVer then
        traitVer = talentVer
        traitSet = {}
        EachTrait(function(spellID, _, has) if has then traitSet[spellID] = true end end)
    end
    return traitSet
end

-- whether you have a rule's talent: true / false, nil = cannot tell
-- (no talent picked, no talent data here). Kept until the talents change.
local cache = setmetatable({}, { __mode = "k" })
local function HasTalent(rule)
    local c = cache[rule]
    local sig = (rule.tab or 0) * 1000 + (rule.index or 0) + (rule.spell or 0) * 1e6
    if c and c.ver == talentVer and c.sig == sig then return c.has end
    local has
    local backend = V2.TalentBackend()
    if rule.tab and rule.index and backend == "talents" then
        local name, rank = TalentAt(rule.tab, rule.index)
        if rule.tName and name ~= rule.tName then
            -- another game version's tree: the talent of that name, wherever it is
            rank = nil
            EachTalent(function(_, _, n, r) if n == rule.tName and rank == nil then rank = r or 0 end end)
            has = type(rank) == "number" and rank > 0
        elseif type(rank) == "number" then
            has = rank > 0
        end
    elseif rule.spell and backend == "traits" then
        has = Traits()[rule.spell] == true
    end
    if not c then c = {} cache[rule] = c end
    c.ver, c.sig, c.has = talentVer, sig, has
    return has
end

-- ------------------------------------------------------------
-- stances and forms
-- ------------------------------------------------------------
-- the stance bar's entries: { { id = spell, name } }
function V2.FormItems()
    local out = {}
    if not (GetNumShapeshiftForms and GetShapeshiftFormInfo) then return out end
    local okN, n = pcall(GetNumShapeshiftForms)
    n = okN and Plain(n) or 0
    if type(n) ~= "number" then return out end
    for i = 1, n do
        local ok, _, _, _, spellID = pcall(GetShapeshiftFormInfo, i)
        spellID = ok and Plain(spellID) or nil
        if type(spellID) == "number" then
            local name = HUD.GetSpellInfo and Plain(HUD.GetSpellInfo(spellID)) or nil
            out[#out + 1] = { id = spellID, name = (type(name) == "string" and name ~= "") and name or ("Form " .. i) }
        end
    end
    return out
end

-- the spell of the stance or form you are in: 0 = none, nil = cannot tell
local function FormNow()
    if not (GetShapeshiftForm and GetShapeshiftFormInfo) then return nil end
    local ok, idx = pcall(GetShapeshiftForm)
    idx = ok and Plain(idx) or nil
    if type(idx) ~= "number" then return nil end
    if idx <= 0 then return 0 end
    local okI, _, _, _, spellID = pcall(GetShapeshiftFormInfo, idx)
    spellID = okI and Plain(spellID) or nil
    if type(spellID) ~= "number" then return nil end
    return spellID
end

-- ------------------------------------------------------------
-- a rule against now
-- ------------------------------------------------------------
local function Holds(eng, rule)
    if rule.tMode then
        local has = HasTalent(rule)
        if has ~= nil and (rule.tMode == "with") ~= has then return false end
    end
    if rule.fMode and rule.form then
        local now = eng._v2formNow
        if now == nil then
            now = FormNow()
            if now == nil then now = false end
            eng._v2formNow = now
        end
        if now ~= false and (rule.fMode == "in") ~= (now == rule.form) then return false end
    end
    return true
end
V2.CondHolds = Holds

-- only during a pass: the page's ticks ask the same question and must
-- hear your own answer
local BaseOff = Engine.V2Off
function Engine:V2Off(row, hidden, def)
    local off = BaseOff(self, row, hidden, def)
    local rules = self._v2cond
    if off or not rules then return off end
    local r = rules[row]
    local rule = r and r[def.key]
    if type(rule) ~= "table" then return false end
    return not Holds(self, rule)
end

local BaseRefresh = Engine.Refresh
function Engine:Refresh()
    local cfg = self:Store()
    local rules = cfg and type(cfg.v2) == "table" and cfg.v2.cond or nil
    if type(rules) ~= "table" then
        self._v2cond = nil
        return BaseRefresh(self)
    end
    WatchTalents()
    self._v2cond, self._v2formNow = rules, nil
    local r = BaseRefresh(self)
    self._v2cond = nil
    return r
end

-- ------------------------------------------------------------
-- the page (General)
-- ------------------------------------------------------------
local function IconItems(eng, cfg)
    local def, S = eng.def, eng.S
    local out = {}
    for _, row in ipairs(ROWS) do
        for _, e in ipairs(def[ROW_LIST[row]] or {}) do
            local text = ROW_PREFIX[row] .. tostring(e.label or S.auraNames[e.key] or e.key)
            local rule = RuleOf(cfg, row, e.key)
            if rule and ((rule.tMode and (rule.tab or rule.spell)) or rule.fMode) then text = text .. "  (has a condition)" end
            out[#out + 1] = { value = row .. "|" .. e.key, text = text }
        end
    end
    return out
end

local function Sel(items, cur, none)
    for _, it in ipairs(items) do if it.value == cur then return it.text end end
    return none or (items[1] and items[1].text) or ""
end

local T_MODES = {
    { value = "any", text = "Whatever your talents" },
    { value = "with", text = "Only with the talent..." },
    { value = "without", text = "Only without the talent..." },
}

local BaseTabGeneral = Engine.V2Tab_General
function Engine:V2Tab_General(L, cfg)
    if BaseTabGeneral then BaseTabGeneral(self, L, cfg) end
    if not V2.RowPick then return end
    local eng = self
    local items = IconItems(eng, cfg)
    if #items == 0 then return end
    local backend = V2.TalentBackend()
    local forms = V2.FormItems()
    L:Card("Icon conditions")
    L:Desc("An icon that shows only with a talent, or only in (or out of) a stance or form. Pick the icon, then when it shows. "
        .. "An icon unticked on its row stays off.")
    local pick = V2.RowPick(L, eng, "hudV2CondIcon", items)
    local row, key = pick:match("^(%a+)|(.+)$")
    local rule = RuleOf(cfg, row, key)
    local function After(structure)
        Prune(cfg, row, key)
        eng:Refresh()
        if structure then HUD.RefreshPage() end
    end
    if backend then
        HUD.Dropdown(L, 260, T_MODES, function() return Sel(T_MODES, rule and rule.tMode or "any") end, function(v)
            RuleOf(cfg, row, key, true).tMode = (v ~= "any") and v or nil
            After(true)
        end)
        if rule and rule.tMode then
            local talents = V2.TalentItems()
            local cur = (rule.tab and ("t:" .. rule.tab .. ":" .. rule.index)) or (rule.spell and ("s:" .. rule.spell)) or nil
            HUD.Dropdown(L, 260, talents, function() return Sel(talents, cur, rule.tName or "Pick a talent") end, function(v)
                local rl = RuleOf(cfg, row, key, true)
                local tab, index = v:match("^t:(%d+):(%d+)$")
                local spell = v:match("^s:(%d+)$")
                rl.tab, rl.index, rl.spell = tonumber(tab), tonumber(index), tonumber(spell)
                rl.tName = Sel(talents, v)
                After(true)
            end)
        end
    end
    if #forms > 0 or (rule and rule.fMode) then
        local fItems = { { value = "any", text = "In any stance or form" } }
        for _, f in ipairs(forms) do
            fItems[#fItems + 1] = { value = "in:" .. f.id, text = "Only in " .. f.name }
            fItems[#fItems + 1] = { value = "out:" .. f.id, text = "Not in " .. f.name }
        end
        fItems[#fItems + 1] = { value = "in:0", text = "Only in no stance or form" }
        local cur = (rule and rule.fMode and rule.form) and (rule.fMode .. ":" .. rule.form) or "any"
        local none = (rule and rule.fMode) and ((rule.fMode == "in" and "Only in " or "Not in ") .. tostring(rule.fName or rule.form)) or nil
        HUD.Dropdown(L, 260, fItems, function() return Sel(fItems, cur, none) end, function(v)
            local rl = RuleOf(cfg, row, key, true)
            local mode, id = v:match("^(%a+):(%d+)$")
            if mode then
                rl.fMode, rl.form = mode, tonumber(id)
                rl.fName = nil
                for _, f in ipairs(forms) do if f.id == rl.form then rl.fName = f.name end end
            else
                rl.fMode, rl.form, rl.fName = nil, nil, nil
            end
            After(true)
        end)
    end
    if not backend and #forms == 0 and not (rule and rule.fMode) then
        HUD.Label(L, "This character has no talents or stances to go by yet.", "gray")
    end
    L:EndCard()
end
