-- HUD_V2_Sources - Class HUD v2, part one: WHAT a class HUD shows. The
-- class definition (HUD_Hunter.lua and friends) is normalised here when
-- it is defined: its utility list, its roles, the entries one game
-- version adds or drops, and on the modern clients (WoW Forever, later
-- Retail) the spells the game's own Cooldown Manager lists for the class
-- (HUD_V2_Modern reads them), merged into the definition's rows. The
-- v2 settings of a HUD live under its store as cfg.v2 (nil = exactly
-- today's HUD; the table exists only once something was changed).
-- Part of ZacUI; load order is set by the TOC (right after HUD_ClassHUD,
-- before the class definitions).
--
-- Definition fields v2 reads (every one optional):
--   utility  = { entries like grid's }       the utility row's icons
--   roles    = { { key, label, tab, form, show = { row = { key, ... } }, aux, glows, res } }
--              a role is a SPEC PRESET and the HUD's default for that spec:
--              tab: the talent tree (1-3) that marks it; form: "cat" /
--              "bear" where one tree holds two (the druid's Feral Combat);
--              show: per row (main / utility / buffs / debuffs) the entries
--              on by default (a row it does not name keeps every entry's
--              own default); aux: the trinket and racial row on; glows:
--              { [ruleKey] = { rule, ... } } (HUD_V2_Glows' shape); res: the
--              resource extras on (HUD_V2_Resources' keys). No spec read
--              (no talents, under level 10): the class baseline - every
--              entry's own default, the HUD as it always was.
--   flavors  = { tbc = { add = { entry, ... }, drop = { key, ... }, spells = { key = id } },
--                forever = { ... } }
--              entry.row names the list it joins ("main" | "utility" |
--              "buffs" | "debuffs"); drop removes a key from every list;
--              an addition starts unticked (defaultHidden = false: ticked)
--   an entry may carry castsDot / nextSwing / seal / charges flags (later phases)

local ns = _G.ZacUI
if not ns or not ns.HUD or not ns.HUD.ClassEngine then return end
local HUD = ns.HUD
local Engine = HUD.ClassEngine
local V2 = HUD.V2 or {}
HUD.V2 = V2

local GetSpellInfo = HUD.GetSpellInfo

V2.ROWS = { "main", "utility", "buffs", "debuffs", "reminders", "aux" }
V2.ROW_LABELS = { main = "Cooldown grid", utility = "Utility row", buffs = "Active buff row",
    debuffs = "Target debuff row", reminders = "Reminders", aux = "Trinkets and racial" }
-- row -> the engine's anchor key
V2.ROW_ANCHOR = { main = "Main", utility = "Utility", buffs = "AuraRow", debuffs = "DebuffRow",
    reminders = "Reminders", aux = "Aux" }
-- the lists a flavor's add / drop and a role's show can name
local LIST_OF = { main = "grid", utility = "utility", buffs = "buffRow", debuffs = "debuffRow" }
V2.LIST_OF = LIST_OF

-- ------------------------------------------------------------
-- the v2 settings table (cfg.v2), read as nil until something is saved
-- ------------------------------------------------------------
function V2.Cfg(cfg, create)
    if type(cfg) ~= "table" then return nil end
    local v = cfg.v2
    if type(v) ~= "table" then
        if not create then return nil end
        v = {}
        cfg.v2 = v
    end
    return v
end

-- one sub-table of it (cfg.v2.<key>)
function V2.Sub(cfg, key, create)
    local v = V2.Cfg(cfg, create)
    if not v then return nil end
    local t = v[key]
    if type(t) ~= "table" then
        if not create then return nil end
        t = {}
        v[key] = t
    end
    return t
end

-- an emptied sub-table goes, and the v2 table with it, so Reset leaves
-- the save as it was
function V2.Tidy(cfg)
    local v = type(cfg) == "table" and cfg.v2
    if type(v) ~= "table" then return end
    for k, t in pairs(v) do
        if type(t) == "table" and next(t) == nil then v[k] = nil end
    end
    if next(v) == nil then cfg.v2 = nil end
end

-- the user's own hidden set for a row (today's tables for the rows the
-- HUD always had; cfg.v2.utility.hidden for the utility row), nil = none
function V2.HiddenSet(cfg, row, create)
    if row == "main" then return cfg.mainRow and cfg.mainRow.hidden end
    if row == "buffs" then return cfg.auraRow and cfg.auraRow.hidden end
    if row == "debuffs" then return cfg.debuffRow and cfg.debuffRow.hidden end
    if row == "utility" then
        local u = V2.Sub(cfg, "utility", create)
        if not u then return nil end
        if type(u.hidden) ~= "table" then
            if not create then return nil end
            u.hidden = {}
        end
        return u.hidden
    end
    return nil
end

-- is this entry off its row: the user's tick (true / false) wins, else the
-- entry's own default (a utility spell the game listed starts hidden)
function V2.IsHidden(hidden, entry)
    local v = hidden and hidden[entry.key]
    if v ~= nil then return v and true or false end
    return entry.defaultHidden and true or false
end

-- ------------------------------------------------------------
-- the definition, normalised once
-- ------------------------------------------------------------
local function Find(list, key)
    for i, e in ipairs(list) do if e.key == key then return i, e end end
    return nil
end

local function DropKey(def, key)
    for _, name in pairs(LIST_OF) do
        local list = def[name]
        if list then
            local i = Find(list, key)
            if i then table.remove(list, i) end
        end
    end
end

local function AddEntry(def, entry, unticked)
    local name = LIST_OF[entry.row or "main"] or "grid"
    def[name] = def[name] or {}
    if Find(def[name], entry.key) then return end
    local copy = {}
    for k, v in pairs(entry) do if k ~= "row" then copy[k] = v end end
    -- a game version's addition starts unticked (one click away, or ticked
    -- by "Set up for <role>"), so a HUD nobody touched stays as it was
    if unticked and copy.defaultHidden == nil then copy.defaultHidden = true end
    if copy.defaultHidden == false then copy.defaultHidden = nil end
    if copy.kind == nil and copy.spell then copy.kind = "spell" end
    if copy.kind == "spell" and copy.spellId then
        def.spells = def.spells or {}
        def.spells[copy.spell or copy.key] = copy.spellId
        copy.spell = copy.spell or copy.key
        copy.spellId = nil
    end
    local list = def[name]
    list[#list + 1] = copy
end

function V2.Normalize(def)
    if type(def) ~= "table" or def._v2 then return def end
    def._v2 = true
    def.utility = def.utility or {}
    def.spells = def.spells or {}
    -- the game version's own additions and drops
    local fl = ns.Flavor and ns.Flavor() or "era"
    local f = type(def.flavors) == "table" and def.flavors[fl]
    if type(f) == "table" then
        for k, id in pairs(f.spells or {}) do def.spells[k] = id end
        for _, key in ipairs(f.drop or {}) do DropKey(def, key) end
        for _, e in ipairs(f.add or {}) do AddEntry(def, e, true) end
    end
    -- roles: key, label, tab, show (per row sets); a role's own block for
    -- this game version (r.tbc = { show = { row = ... }, glows, res, aux })
    -- replaces the rows and fields it names (WoW Forever plays Era's)
    local roles = {}
    for i, r in ipairs(def.roles or {}) do
        if type(r) == "table" and r.key then
            local over = type(r[fl]) == "table" and r[fl] or nil
            local rows = {}
            for row, keys in pairs(r.show or {}) do rows[row] = keys end
            if over then for row, keys in pairs(over.show or {}) do rows[row] = keys end end
            local show = {}
            for row, keys in pairs(rows) do
                local set = {}
                for _, k in ipairs(keys) do set[k] = true end
                show[row] = set
            end
            if over then
                if over.glows ~= nil then r = setmetatable({ glows = over.glows }, { __index = r }) end
                if over.res ~= nil then r = setmetatable({ res = over.res }, { __index = r }) end
                if over.aux ~= nil then r = setmetatable({ aux = over.aux }, { __index = r }) end
            end
            -- (specID: Retail's roles are keyed by the game's spec id, HUD_Retail.lua; nil elsewhere)
            roles[#roles + 1] = { key = r.key, label = r.label or r.key, tab = r.tab or i, form = r.form,
                show = show, aux = r.aux, glows = r.glows, res = r.res, specID = r.specID }
        end
    end
    def.roles = roles
    return def
end

-- ------------------------------------------------------------
-- roles
-- ------------------------------------------------------------
-- the talent tree with most points, 1-3 (Classic Era / TBC), or nil
local function TalentTab()
    if not (GetNumTalentTabs and GetTalentTabInfo) then return nil end
    local ok, n = pcall(GetNumTalentTabs)
    n = (ok and type(n) == "number" and not ns.IsSecret(n)) and n or 0
    local best, bestPts = nil, 0
    for i = 1, math.min(n, 3) do
        -- Classic Era: name, icon, pointsSpent, background; a client on
        -- the later shape: id, name, description, icon, pointsSpent, ...;
        -- a table on the newest. Whatever comes back secret counts nothing.
        local okI, a, b, c, d, e = pcall(GetTalentTabInfo, i)
        local pts = 0
        if okI then
            if type(a) == "table" then pts = a.pointsSpent
            elseif type(a) == "number" and not ns.IsSecret(a) then pts = e
            else pts = c end
        end
        if type(pts) ~= "number" or ns.IsSecret(pts) then pts = 0 end
        if pts > bestPts then best, bestPts = i, pts end
    end
    return best
end

-- WoW Forever: the trait group (one per vanilla tree) with most ranks
-- bought; the groups come in tree order
local function TraitTab()
    local CT, Tr = C_ClassTalents, C_Traits
    if not (CT and Tr and CT.GetActiveConfigID and Tr.GetConfigInfo and Tr.GetTreeNodes and Tr.GetNodeInfo) then return nil end
    local ok, best = pcall(function()
        local configID = CT.GetActiveConfigID()
        if not configID then return nil end
        local cfg = Tr.GetConfigInfo(configID)
        local treeID = cfg and cfg.treeIDs and cfg.treeIDs[1]
        if not treeID then return nil end
        local groups = {}
        local order = {}
        if Tr.GetGroupDisplayInfoByTreeID then
            local gl = Tr.GetGroupDisplayInfoByTreeID(treeID)
            for i, g in ipairs(gl or {}) do
                local gid = type(g) == "table" and g.groupID or g
                if gid then groups[gid] = 0 order[#order + 1] = gid end
            end
        end
        for _, nodeID in ipairs(Tr.GetTreeNodes(treeID) or {}) do
            local info = Tr.GetNodeInfo(configID, nodeID)
            local ranks = info and info.ranksPurchased or 0
            if ns.IsSecret(ranks) then ranks = 0 end
            if type(ranks) == "number" and ranks > 0 and type(info.groupIDs) == "table" then
                for _, gid in ipairs(info.groupIDs or {}) do
                    if groups[gid] == nil then groups[gid] = 0 order[#order + 1] = gid end
                    groups[gid] = groups[gid] + ranks
                end
            end
        end
        local bi, bp = nil, 0
        for i, gid in ipairs(order) do
            if groups[gid] > bp then bi, bp = i, groups[gid] end
        end
        return bi
    end)
    if ok then return best end
    return nil
end

V2.TalentTab, V2.TraitTab = TalentTab, TraitTab

-- the spec the talents point at, or nil (no roles, no talents, under
-- level 10: the class baseline). WoW Forever: its own talent data (the
-- trait group with most ranks, one group per vanilla tree), then the old
-- talent tabs where that client still has them. A tree holding two
-- presets (Feral Combat: cat, bear) picks by the power you run on now:
-- rage = bear. powerType: the HUD's own read (nil = cat).
-- Retail: the game's own id of the spec you play (62 Arcane, 71 Arms,
-- ...), or nil when the client gives none (no spec picked yet, a value it
-- hides, a client without the call)
function V2.RetailSpecID()
    local CSI = C_SpecializationInfo
    local getIndex = (CSI and CSI.GetSpecialization) or GetSpecialization
    local getInfo = (CSI and CSI.GetSpecializationInfo) or GetSpecializationInfo
    if not (getIndex and getInfo) then return nil end
    local ok, index = pcall(getIndex)
    if not ok or ns.IsSecret(index) or type(index) ~= "number" then return nil end
    local okI, id = pcall(getInfo, index)
    if not okI or ns.IsSecret(id) or type(id) ~= "number" then return nil end
    return id
end

function V2.GuessRole(def, powerType)
    if not (def.roles and #def.roles > 0) then return nil end
    if HUD.RETAIL then
        -- Retail plays by spec: the role whose specID is the spec in force
        -- (none listed for it: the class baseline)
        local specID = V2.RetailSpecID()
        if specID then
            for _, r in ipairs(def.roles) do
                if r.specID == specID then return r.key end
            end
        end
        return nil
    end
    local lvl = UnitLevel and UnitLevel("player")
    if type(lvl) == "number" and not ns.IsSecret(lvl) and lvl < 10 then return nil end
    local tab
    if ns.ModernClient and ns.ModernClient() then tab = TraitTab() end
    if not tab then tab = TalentTab() end
    if not tab then return nil end
    local first
    for _, r in ipairs(def.roles) do
        if r.tab == tab then
            if not r.form then return r.key end
            first = first or r.key
            if (r.form == "bear") == (powerType == 1) then return r.key end
        end
    end
    return first
end

function V2.RoleByKey(def, key)
    for _, r in ipairs(def.roles or {}) do if r.key == key then return r end end
    return nil
end

-- "Reset to spec defaults": every tick you made on the rows, your glow
-- rules, your resource extras and the trinket row's switch go, so the
-- spec in force (yours if picked, else your talents') decides them again.
-- The spec pick, the utility row's switch and every other setting stay.
function Engine:V2ResetToSpec()
    local cfg = self:Store()
    if not cfg then return false end
    for _, row in ipairs({ "main", "utility", "buffs", "debuffs" }) do
        local hidden = V2.HiddenSet(cfg, row)
        if hidden then wipe(hidden) end
    end
    cfg.glows = nil
    local v = V2.Cfg(cfg)
    if v then v.res, v.aux = nil, nil end
    if cfg.aux then cfg.aux.enabled = false end
    V2.Tidy(cfg)
    for _, m in pairs(self.memo or {}) do HUD.ForgetLayout(m) end
    if ns.SettingsChanged then ns.SettingsChanged("hud.role") end
    self:Refresh()
    return true
end

-- "Set up for <role>" (the page, the setup): that spec in force (the
-- talents' own pick saves nothing), then its defaults as above
function Engine:V2ApplyRole(roleKey)
    local cfg = self:Store()
    local role = cfg and V2.RoleByKey(self.def, roleKey)
    if not role then return false end
    local detected = self.V2DetectedSpec and self:V2DetectedSpec() or nil
    V2.Cfg(cfg, true).role = (roleKey ~= detected) and roleKey or nil
    return self:V2ResetToSpec()
end

-- ------------------------------------------------------------
-- the game's own list (HUD_V2_Modern reads the Cooldown Manager)
-- ------------------------------------------------------------
-- every spell name the definition already shows, to tell a game entry
-- that is new from one it has
local function KnownNames(def)
    local names = {}
    for key, id in pairs(def.spells or {}) do
        local name = GetSpellInfo and GetSpellInfo(id)
        if name then names[name:lower()] = key end
    end
    for _, listName in pairs(LIST_OF) do
        for _, e in ipairs(def[listName] or {}) do
            if e.id then
                local name = e.name or (GetSpellInfo and GetSpellInfo(e.id))
                if name then names[name:lower()] = e.key end
            end
        end
    end
    return names
end

-- Merge the catalogue into the definition: a listed spell the HUD does
-- not know joins the row the game puts it on (essential -> the grid,
-- utility -> the utility row, starting hidden, a tracked buff -> the buff
-- row). Returns true when a row gained an entry (icons to build).
local CAT_ROW = { essential = "main", utility = "utility", buffs = "buffs" }

-- Retail (HUD_Retail.lua's class HUD): the list IS the HUD, and it is the
-- spec's. Essential -> the grid, Utility -> the utility row (off unless
-- the spec's preset ticks it), TrackedBuff -> the buff row, TrackedBar ->
-- a buff row entry the buff bars are seeded with (no icon of its own
-- unless the game also lists it as a tracked buff). An entry the game
-- hides by default starts unticked. An entry of the game's that is not
-- in this read's set leaves its row (another spec's) - but only on a row
-- this read filled: a list the game did not serve judges nothing, and an
-- empty read changes nothing at all. Every entry keeps the game's word
-- on it (known, the id in force, its other ids) for the HUD's reads.
-- def._rver moves when a row changed: HUD_Retail rebuilds icons on it.
local RCAT_LIST = { essential = "grid", utility = "utility", buffs = "buffRow", bars = "buffRow" }
local RLIST_ROW = { grid = "main", utility = "utility", buffRow = "buffs" }
local function RetailMerge(self, cat)
    if #cat == 0 then return false end
    local def = self.def
    def.utility, def.buffRow, def.spells = def.utility or {}, def.buffRow or {}, def.spells or {}
    local want = { grid = {}, utility = {}, buffRow = {} }
    local order = { grid = {}, utility = {}, buffRow = {} }
    local asBuff, asBar, barOrder = {}, {}, {}
    for _, e in ipairs(cat) do
        local listName = RCAT_LIST[e.category]
        if listName and e.spellID and e.name then
            local key = "game" .. e.spellID
            -- (a key sits on the grid or the utility row, never both)
            if not (listName == "utility" and want.grid[key]) then
                if not want[listName][key] then
                    want[listName][key] = e
                    order[listName][#order[listName] + 1] = key
                end
                if e.category == "buffs" then asBuff[key] = true end
                if e.category == "bars" and not asBar[key] then
                    asBar[key] = true
                    barOrder[#barOrder + 1] = key
                end
            end
        end
    end
    local changed = false
    for listName, set in pairs(want) do
        local list = def[listName]
        if not list then list = {} def[listName] = list end
        if next(set) ~= nil then
            for i = #list, 1, -1 do
                local en = list[i]
                if en.fromGame and not set[en.key] then
                    table.remove(list, i)
                    if listName ~= "buffRow" then def.spells[en.key] = nil end
                    changed = true
                end
            end
        end
        for _, key in ipairs(order[listName]) do
            local e = set[key]
            local _, en = Find(list, key)
            if not en then
                local row = RLIST_ROW[listName]
                if row == "buffs" then
                    AddEntry(def, { key = key, id = e.spellID, label = e.name, row = row, fromGame = true })
                else
                    AddEntry(def, { key = key, kind = "spell", spell = key, spellId = e.spellID, label = e.name,
                        row = row, fromGame = true, noRange = not e.hasRange })
                end
                _, en = Find(list, key)
                changed = true
            end
            if en and en.fromGame then
                local hide
                if listName == "utility" then hide = true
                elseif listName == "buffRow" then hide = (e.defaultHidden or not asBuff[key]) and true or nil
                else hide = e.defaultHidden and true or nil end
                en.defaultHidden = hide
                en.isKnown = e.isKnown
                en.curId = e.overrideSpellID or e.spellID
                en.cdID, en.hasAura, en.selfAura, en.charges = e.cdID, e.hasAura, e.selfAura, e.charges
                -- its other ids (the override, the linked spells): a preset or an
                -- aura read may name the spell by any of them
                local alt = en.altIds
                if not alt then alt = {} en.altIds = alt else wipe(alt) end
                local keys = en.altKeys
                if not keys then keys = {} en.altKeys = keys else wipe(keys) end
                local function add(id)
                    if type(id) == "number" and id ~= e.spellID then
                        alt[#alt + 1] = id
                        keys[#keys + 1] = "game" .. id
                    end
                end
                add(e.overrideSpellID)
                for _, l in ipairs(e.linked or {}) do add(l) end
            end
        end
    end
    -- the buff bars' seeds: the game's tracked bars, in its order
    local seeds = def.buffBars
    local same = type(seeds) == "table" and #seeds == #barOrder
    if same then
        for i, k in ipairs(barOrder) do if seeds[i] ~= k then same = false break end end
    end
    if not same then
        def.buffBars = barOrder
        self._v2barSeeds = nil
        changed = true
    end
    if changed then
        def._rver = (def._rver or 0) + 1
        self.dirty.spells = true
        if self.V2BuildMissing then self:V2BuildMissing() end
    end
    return changed
end

function Engine:V2MergeCatalogue()
    if not (V2.Catalogue) then return false end
    local cat = V2.Catalogue()
    if type(cat) ~= "table" then return false end
    if HUD.RETAIL and self.def.retail then return RetailMerge(self, cat) end
    local def = self.def
    local names = KnownNames(def)
    local added = false
    for _, e in ipairs(cat) do
        local row = CAT_ROW[e.category]
        local lname = e.name and e.name:lower()
        if row and lname and not names[lname] and e.spellID then
            names[lname] = true
            local key = "game" .. e.spellID
            if row == "buffs" then
                AddEntry(def, { key = key, id = e.spellID, label = e.name, row = row, fromGame = true })
            else
                AddEntry(def, { key = key, kind = "spell", spell = key, spellId = e.spellID, label = e.name,
                    row = row, fromGame = true, noRange = not e.hasRange,
                    defaultHidden = (row == "utility") or nil })
            end
            added = true
        end
    end
    if added then
        self.dirty.spells = true
        if self.V2BuildMissing then self:V2BuildMissing() end
    end
    return added
end

-- icons for entries that joined a list after the HUD was built
function Engine:V2BuildMissing()
    if not self.built then return end
    local W = self.W
    if not W then return end
    local cfg = self:Store()
    for _, def in ipairs(self.def.grid or {}) do
        if not self.mainIcons[def.key] then
            local icon = W.CreateIcon(self.anchors.Main, { width = 30, height = 30, zoom = W.ICON_ZOOM, keepAspect = true, inverse = true })
            icon:SetFrameStrata("MEDIUM")
            icon:Hide()
            icon.def = def
            icon:AddText("p", "CENTER", 14, { 1, 1, 1, 1 })
            icon:SetText("p", "")
            self.mainIcons[def.key] = icon
        end
    end
    if self.anchors.AuraRow and cfg then
        for _, def in ipairs(self.def.buffRow or {}) do
            if not self.auraIcons[def.key] then
                local size = cfg.auraRow.iconSize or 25
                local icon = W.CreateIcon(self.anchors.AuraRow, { width = size, height = size, zoom = W.ICON_ZOOM, keepAspect = true, inverse = true })
                icon:SetFrameStrata("MEDIUM")
                icon:Hide()
                icon.def = def
                icon:AddText("p", "BELOW", 14, { 1, 1, 1, 1 }, 0, 0)
                icon:AddText("s", "INNER_TOPRIGHT", 14, { 1, 1, 1, 1 }, 0, 0)
                self.auraIcons[def.key] = icon
            end
        end
    end
    if self.V2BuildUtility then self:V2BuildUtility() end
end

-- at login (after the class check): the game's list, then again whenever
-- the spells change (the engine's SPELLS_CHANGED flag runs ResolveSpells;
-- the catalogue is re-read there through V2.CatalogueDirty)
function Engine:V2Login(cfg)
    self:V2MergeCatalogue()
    -- the utility row's anchor (the saved variables were not there when
    -- the class was defined, so the element list could not include it)
    if cfg and V2.UtilityOn and V2.UtilityOn(cfg) and self.V2EnsureUtility then self:V2EnsureUtility() end
    if self.V2LoginIcons then self:V2LoginIcons(cfg) end
end
