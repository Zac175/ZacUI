-- HUD_V2_Custom - Class HUD v2: your own icons (2026-11-18). A spell, an
-- item, a buff on you or a debuff of yours on the target that the HUD's
-- lists do not have, added by name or id on the General tab and removed
-- there. An entry of yours joins the definition's list for its row the
-- way a game version's additions do (V2.AddEntry), so everything a row's
-- entries get - ticks, order, layout, glow rules, key text, tooltips - it
-- gets too.
--   cooldown   a spell on the cooldown grid (by id, or by the name of a
--              spell in your spellbook)
--   item       an item on the cooldown grid, with its count and cooldown
--              (by id, or by the name of an item the client knows)
--   buff       on the active buff row (by id or by name: a buff is found
--              by its name, so a proc you cannot cast works by name)
--   debuff     on the target debuff row, where the HUD has one
-- Settings: cfg.v2.custom, a list of { row, kind, id, name }. Nothing
-- runs for it: the entries are read by the engine's own passes.
-- Part of ZacUI; load order is set by the TOC (after HUD_V2_Totems).

local ns = _G.ZacUI
if not ns or not ns.HUD or not ns.HUD.V2 then return end
local HUD = ns.HUD
local V2 = HUD.V2
local Engine = HUD.ClassEngine
local UI = ns.UI

local GetSpellInfo = HUD.GetSpellInfo
local LIST_OF = V2.LIST_OF
local ROW_FIELD = { main = "mainIcons", buffs = "auraIcons", debuffs = "debuffIcons" }

local function List(cfg, create)
    local v = V2.Cfg(cfg, create)
    if not v then return nil end
    if type(v.custom) ~= "table" then
        if not create then return nil end
        v.custom = {}
    end
    return v.custom
end
V2.CustomList = List

local function Plain(v)
    if v == nil or ns.IsSecret(v) then return nil end
    return v
end

-- the entry's key on its row
local function KeyOf(c)
    if c.kind == "item" then return "ownitem" .. tostring(c.id) end
    local tag = (c.row == "buffs" and "ownbuff") or (c.row == "debuffs" and "owndebuff") or "ownspell"
    return tag .. tostring(c.id or c.name)
end
V2.CustomKey = KeyOf

-- the kinds this HUD can take
function Engine:V2CustomKinds()
    local kinds = {
        { value = "spell", text = "Cooldown (cooldown grid)" },
        { value = "item", text = "Item (cooldown grid)" },
        { value = "buffs", text = "Buff on you" },
    }
    if self.def.debuffRow and not HUD.RETAIL then
        kinds[#kinds + 1] = { value = "debuffs", text = "Debuff on the target" }
    end
    return kinds
end

-- What was typed, as an entry: { row, kind, id, name }, or nil and why not.
function V2.CustomResolve(kind, text)
    text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return nil, "Type a name or an id first." end
    local num = tonumber(text)
    if kind == "item" then
        local name, link
        if GetItemInfo then name, link = GetItemInfo(num or text) end
        name, link = Plain(name), Plain(link)
        local id = num or (type(link) == "string" and tonumber(link:match("item:(%d+)"))) or nil
        if not id then return nil, "No item by that name is known here yet. Type its id instead." end
        return { row = "main", kind = "item", id = id, name = name or ("Item " .. id) }
    end
    local row = (kind == "buffs" or kind == "debuffs") and kind or "main"
    if num then
        local name = GetSpellInfo and Plain(GetSpellInfo(num)) or nil
        if not name then return nil, "No spell has that id on this game version." end
        return { row = row, kind = "spell", id = num, name = name }
    end
    -- a name: the spellbook knows the id of a spell you have
    local name, id
    if GetSpellInfo then
        local n, _, _, _, _, _, sid = GetSpellInfo(text)
        name, id = Plain(n), Plain(sid)
    end
    if name and type(id) == "number" then return { row = row, kind = "spell", id = id, name = name } end
    if row == "main" then return nil, "That spell is not in your spellbook. Type its id instead." end
    -- a buff or debuff is found by its name: the name alone will do
    return { row = row, kind = "spell", name = text }
end

-- one entry of yours into the definition (no-op when its key is there)
local function Join(def, c)
    local key = KeyOf(c)
    if c.kind == "item" then
        V2.AddEntry(def, { key = key, kind = "item", items = { { id = c.id } }, label = c.name, row = "main",
            fromUser = true })
    elseif c.row == "main" then
        V2.AddEntry(def, { key = key, kind = "spell", spell = key, spellId = c.id, label = c.name, row = "main",
            fromUser = true })
    else
        -- (by name alone: id 0 is no spell on any client, and the row's reads
        -- take a number there; the name is what finds the aura)
        V2.AddEntry(def, { key = key, id = c.id or 0, name = (not c.id) and c.name or nil, label = c.name, row = c.row,
            fromUser = true })
    end
end

-- your list and the definition made the same: entries of yours that are
-- not on your list any more leave their row, the ones that are join it
function Engine:V2SyncCustom()
    local cfg = self:Store()
    if not cfg then return false end
    local def = self.def
    local want = {}
    for _, c in ipairs(List(cfg) or {}) do
        if type(c) == "table" and (c.id or c.name) and (c.row ~= "debuffs" or def.debuffRow) then
            want[KeyOf(c)] = c
        end
    end
    local changed = false
    for _, listName in pairs(LIST_OF) do
        local list = def[listName]
        for i = #(list or {}), 1, -1 do
            local e = list[i]
            if e.fromUser and not want[e.key] then
                table.remove(list, i)
                if def.spells then def.spells[e.key] = nil end
                changed = true
            end
        end
    end
    local n = 0
    for _, listName in pairs(LIST_OF) do n = n + #(def[listName] or {}) end
    for _, c in ipairs(List(cfg) or {}) do
        if want[KeyOf(c)] == c then Join(def, c) end
    end
    local n2 = 0
    for _, listName in pairs(LIST_OF) do n2 = n2 + #(def[listName] or {}) end
    if n2 ~= n then changed = true end
    if changed then
        def._ownVer = (def._ownVer or 0) + 1
        self.dirty.spells, self.dirty.bags = true, true
    end
    return changed
end

-- the icons follow the lists: made for an entry that joined, hidden for
-- one that left. Once per engine (the HUD and each preview sample) after
-- the lists changed.
local function FollowLists(eng)
    local def, W = eng.def, eng.W
    eng._itemLists = nil
    if eng.V2BuildMissing then eng:V2BuildMissing() end
    local cfg = eng:Store()
    if W and cfg and eng.anchors.DebuffRow then
        local size = cfg.debuffRow.iconSize or 26
        for _, d in ipairs(def.debuffRow or {}) do
            if not eng.debuffIcons[d.key] then
                local icon = W.CreateIcon(eng.anchors.DebuffRow, { width = size, height = size, zoom = W.ICON_ZOOM,
                    keepAspect = true, inverse = true })
                icon:SetFrameStrata("MEDIUM")
                icon:Hide()
                icon.def = d
                icon:AddText("p", "BELOW", 14, { 1, 1, 1, 1 }, 0, 0)
                icon:AddText("s", "INNER_TOPRIGHT", 14, { 1, 1, 1, 1 }, 0, 0)
                eng.debuffIcons[d.key] = icon
            end
        end
    end
    -- (an item icon of yours carries a count, as the engine's item icons do)
    for _, g in ipairs(def.grid or {}) do
        local icon = eng.mainIcons[g.key]
        if icon and g.fromUser and g.kind == "item" and not icon.texts.count then
            icon:AddText("count", "INNER_BOTTOMRIGHT", 12, { 1, 0.82, 0, 1 }, 0, 0)
        end
    end
    for row, field in pairs(ROW_FIELD) do
        local inList = {}
        for _, e in ipairs(def[LIST_OF[row]] or {}) do inList[e.key] = e end
        for key, icon in pairs(eng[field] or {}) do
            if icon.def and icon.def.fromUser and not inList[key] then
                icon:Hide()
                icon.auraRef = nil
            end
        end
    end
    for _, m in pairs(eng.memo or {}) do HUD.ForgetLayout(m) end
    eng:ApplyColors()
end

local BaseRefresh = Engine.Refresh
function Engine:Refresh()
    local ver = self.def._ownVer
    if self.built and self._ownSeen ~= ver then
        self._ownSeen = ver
        FollowLists(self)
    elseif not self.built then
        self._ownSeen = ver
    end
    return BaseRefresh(self)
end

-- the preview's sample resolves the spells again after the lists changed
local BaseFill = Engine.FillSample
function Engine:FillSample(mode)
    if self._ownFill ~= self.def._ownVer then
        self._ownFill = self.def._ownVer
        self._resolved = nil
    end
    return BaseFill(self, mode)
end

-- an entry of yours is on its row unless you untick it (a spec's preset
-- names the definition's own entries, never yours)
local BaseOff = Engine.V2Off
function Engine:V2Off(row, hidden, def)
    if def.fromUser then
        local v = hidden and hidden[def.key]
        return (v ~= nil and v) and true or false
    end
    return BaseOff(self, row, hidden, def)
end

-- Retail reads a cooldown by the id in force: yours is the id you gave
local BaseResolve = Engine.ResolveSpells
function Engine:ResolveSpells()
    BaseResolve(self)
    if not HUD.RETAIL then return end
    local S, def = self.S, self.def
    for _, e in ipairs(def.grid or {}) do
        local sp = e.fromUser and e.kind == "spell" and S.spells[e.key]
        if sp then sp.id = def.spells and def.spells[e.key] or nil end
    end
end

local BaseLogin = Engine.V2Login
function Engine:V2Login(cfg)
    if BaseLogin then BaseLogin(self, cfg) end
    self:V2SyncCustom()
end

-- add / remove (the page's buttons)
function Engine:V2CustomAdd(kind, text)
    local cfg = self:Store()
    if not cfg then return false, "The HUD's settings are not there yet." end
    local c, why = V2.CustomResolve(kind, text)
    if not c then return false, why end
    if c.row == "debuffs" and not self.def.debuffRow then return false, "This HUD has no target debuff row." end
    local key = KeyOf(c)
    for _, e in ipairs(List(cfg) or {}) do
        if KeyOf(e) == key then return false, "That one is on your list already." end
    end
    -- (the HUD's own lists may have it under another key: by name)
    local lname = c.name and c.name:lower()
    local S = self.S
    for _, e in ipairs(self.def[LIST_OF[c.row]] or {}) do
        local have
        if e.kind == "spell" or (e.spell and not e.kind) then
            local sp = S.spells[e.spell or e.key]
            have = sp and sp.name
        elseif e.id or e.name then
            have = S.auraNames[e.key] or e.name
        end
        if c.kind ~= "item" and have and lname and have:lower() == lname then
            return false, "The HUD already has " .. c.name .. " on that row (tick it under " .. (V2.ROW_LABELS[c.row] or c.row) .. ")."
        end
    end
    local list = List(cfg, true)
    list[#list + 1] = c
    self:V2SyncCustom()
    self:Refresh()
    return true
end

function Engine:V2CustomRemove(index)
    local cfg = self:Store()
    local list = cfg and List(cfg)
    local c = list and list[index]
    if not c then return false end
    table.remove(list, index)
    local hidden = V2.HiddenSet(cfg, c.row)
    if hidden then hidden[KeyOf(c)] = nil end
    if #list == 0 then cfg.v2.custom = nil end
    V2.Tidy(cfg)
    self:V2SyncCustom()
    self:Refresh()
    return true
end

-- ------------------------------------------------------------
-- the page (General)
-- ------------------------------------------------------------
local KIND_WORD = { spell = "cooldown", item = "item", buffs = "buff", debuffs = "debuff" }

local BaseTabGeneral = Engine.V2Tab_General
function Engine:V2Tab_General(L, cfg)
    if BaseTabGeneral then BaseTabGeneral(self, L, cfg) end
    local eng = self
    local M, F = UI.M, UI.F
    L:Card("Your own icons")
    L:Desc("A spell, an item, a buff or a debuff the lists above do not have. Type its name or its id, pick what it is, Add. "
        .. "It joins that row and can be unticked, reordered and given glow rules like any other.")
    local card = L.current
    local kinds = eng:V2CustomKinds()
    local sel = "spell"
    local function KindText(v)
        for _, k in ipairs(kinds) do if k.value == v then return k.text end end
        return kinds[1].text
    end
    local eb = UI.EditBox(card, { width = 170, hint = "Name or id" })
    local dd = UI.Dropdown(card, {
        width = 200,
        items = function() return kinds end,
        selected = function() return KindText(sel) end,
        selectedValue = function() return sel end,
        onSelect = function(value) sel = value end,
    })
    local note
    local add = UI.Button(card, "Add", { width = 50, onClick = function()
        local ok, why = eng:V2CustomAdd(sel, eb:GetText())
        if ok then
            HUD.RefreshPage()
        elseif note then
            note:SetText(why or "")
        end
    end })
    L:Flow({ eb, dd, add }, 6, 8, M.CONTROL_X)
    note = UI.Font(card, F.LABEL, { text = "", cat = "text", key = "gray", width = math.max(60, L:Room()) })
    note:SetPoint("TOPLEFT", card, "TOPLEFT", M.CONTROL_X, card._y - 2)
    card._y = card._y - 18
    for i, c in ipairs(List(cfg) or {}) do
        local rm = UI.Button(card, "Remove", { width = 60, height = 20, onClick = function()
            eng:V2CustomRemove(i)
            HUD.RefreshPage()
        end })
        rm:SetPoint("TOPRIGHT", card, "TOPRIGHT", -M.CONTROL_X, card._y)
        local what = (c.kind == "item") and "item" or (KIND_WORD[c.row == "main" and "spell" or c.row] or "cooldown")
        local fs = UI.Font(card, F.LABEL, {
            text = string.format("%s  |cff999999(%s%s)|r", tostring(c.name or c.id), what, c.id and (", id " .. c.id) or ""),
            cat = "text", key = "normal",
            width = math.max(60, L:Room() - (M.DESC_X - M.CONTROL_X) - (rm:GetWidth() or 60) - 8),
        })
        fs:SetPoint("TOPLEFT", card, "TOPLEFT", M.DESC_X, card._y - 5)
        card._y = card._y - math.max(24, (fs:GetStringHeight() or 12) + 10)
    end
    L:EndCard()
end
