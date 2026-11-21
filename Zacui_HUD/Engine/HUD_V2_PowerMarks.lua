-- HUD_V2_PowerMarks - Class HUD v2: marks on the mana / power bar and the
-- cost of the spell being cast (2026-11-18). Both off until set.
--   marks          thin lines across the bar at values you type per power
--                  ("35, 60") or at a share of the bar ("50%"): where
--                  there is enough for a spell. A value mark needs the
--                  bar's maximum as a plain number (a maximum the game
--                  hides shows none of them; a share needs no maximum).
--   cost           while you cast a spell with a cast time, a block over
--                  the end of the bar's fill as wide as what the spell is
--                  going to take. It hangs off the fill's own edge, so
--                  the amount you have is never read for it; the cost and
--                  the maximum have to be plain numbers, else no block.
--   what it reads  UnitPowerMax on the HUD's 0.2 s tick while there is a
--                  mark or a cast to draw; C_Spell.GetSpellPowerCost once
--                  per cast, on UNIT_SPELLCAST_START (your own casts, the
--                  event only stores what it carries); the block is put
--                  up and taken down on the 0.1 s text tick.
-- Settings: cfg.v2.pmarks { at = { MANA = "35, 60", ENERGY = "50%" }, color,
--           cost, costColor }.
-- Part of ZacUI; load order is set by the TOC (after HUD_V2_Assist).

local ns = _G.ZacUI
if not ns or not ns.HUD or not ns.HUD.V2 then return end
local HUD = ns.HUD
local V2 = HUD.V2
local Engine = HUD.ClassEngine
local UI = ns.UI

local WHITE = "Interface\\Buttons\\WHITE8X8"
local MARK_COL = { r = 1, g = 1, b = 1, a = 0.75 }
local COST_COL = { r = 1, g = 1, b = 1, a = 0.45 }
local MAX_MARKS = 8
V2.POWER_MARKS_MAX = MAX_MARKS
-- the engine's bars by the power they show (Retail names its own)
local PT_KEY = { [0] = "MANA", [1] = "RAGE", [2] = "FOCUS", [3] = "ENERGY", [6] = "RUNIC_POWER" }
local CAST_EVENTS = { "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED" }

local function Cfg(cfg, create) return V2.Sub(cfg, "pmarks", create) end
V2.PowerMarksCfg = Cfg

local function Plain(v)
    if v == nil or ns.IsSecret(v) then return nil end
    return v
end

local function Num(n)
    if n == math.floor(n) then return string.format("%d", n) end
    return tostring(n)
end

-- "35, 60%" -> { { v = 35 }, { p = 60 } }, and the same text tidied
-- (what cannot be a mark is dropped: no number, zero, a share of 100% up)
local parsed = {}
function V2.ParseMarks(text)
    if type(text) ~= "string" then return {}, "" end
    local hit = parsed[text]
    if hit then return hit.list, hit.text end
    local list, out = {}, {}
    for tok in text:gmatch("[^,;%s]+") do
        local num, pct = tok:match("^(%d+%.?%d*)(%%?)$")
        local n = tonumber(num)
        if n and n > 0 and #list < MAX_MARKS then
            if pct == "%" then
                if n < 100 then
                    list[#list + 1] = { p = n }
                    out[#out + 1] = Num(n) .. "%"
                end
            else
                list[#list + 1] = { v = n }
                out[#out + 1] = Num(n)
            end
        end
    end
    hit = { list = list, text = table.concat(out, ", ") }
    parsed[text] = hit
    return hit.list, hit.text
end

function V2.CostOn(cfg)
    local c = Cfg(cfg)
    return (c and c.cost) and true or false
end

local function MarksText(cfg, key)
    local c = Cfg(cfg)
    local at = c and c.at
    local t = key and type(at) == "table" and at[key] or nil
    return (type(t) == "string" and t ~= "") and t or nil
end
V2.PowerMarksText = MarksText

local function AnyMarks(cfg)
    local c = Cfg(cfg)
    return (c and type(c.at) == "table" and next(c.at) ~= nil) and true or false
end

-- ------------------------------------------------------------
-- which power a bar shows now, and its maximum
-- ------------------------------------------------------------
-- the power bar's: ptype, key, max (max may be hidden: the caller checks)
local function PowerOf(eng)
    local S = eng.S
    if eng.def.retail then
        local ptype, token = UnitPowerType("player")
        ptype, token = Plain(ptype), Plain(token)
        local max
        if eng.sample then max = S.powerMax else max = UnitPowerMax("player") end
        return ptype, (type(token) == "string" and token) or PT_KEY[ptype], max
    end
    local ptype = S.powerType or 3
    if ptype == 0 then ptype = 3 end
    local max
    if eng.sample then max = S.powerMax else max = UnitPowerMax("player", ptype) end
    return ptype, PT_KEY[ptype], max
end

local function ManaMax(bar)
    if bar.readMana then
        local _, max = bar.readMana()
        return max
    end
    return UnitPowerMax("player", 0)
end

-- the powers this HUD's bars can show, for the page: { { key, label } }
function Engine:V2PowerMarkKeys()
    local out = {}
    if self.manaBar or self.bars.mana then out[#out + 1] = { "MANA", "Mana" } end
    if self.bars.power then
        if self.def.retail then
            -- the power in use now, under the game's own name for it
            local _, key = PowerOf(self)
            key = key or "MANA"
            local name = _G[key]
            out[#out + 1] = { key, (type(name) == "string" and name ~= "") and name or key }
        elseif self.def.class == "ROGUE" then
            out[#out + 1] = { "ENERGY", "Energy" }
        else
            out[#out + 1] = { "ENERGY", "Energy" }
            out[#out + 1] = { "RAGE", "Rage" }
        end
    end
    return out
end

-- ------------------------------------------------------------
-- the marks on one bar
-- ------------------------------------------------------------
local function HideMarks(bar)
    if not bar._v2mk then return end
    bar._v2mk = nil
    for _, m in ipairs(bar._v2marks or {}) do m:Hide() end
end

local function PlaceMarks(bar, text, max, r, g, b, a)
    local list = text and V2.ParseMarks(text) or nil
    if not list or #list == 0 then return HideMarks(bar) end
    max = Plain(max)
    if type(max) ~= "number" or max <= 0 then max = nil end
    local bw = bar:GetWidth() or 0
    local col = r * 1e9 + g * 1e6 + b * 1e3 + a
    local mk = bar._v2mk
    -- placed again only when the text, the bar, the maximum or the colour changed
    if mk and mk.text == text and mk.bw == bw and mk.max == max and mk.col == col then return end
    if not mk then mk = {} bar._v2mk = mk end
    mk.text, mk.bw, mk.max, mk.col = text, bw, max, col
    local marks = bar._v2marks
    if not marks then marks = {} bar._v2marks = marks end
    for i = 1, math.max(#list, #marks) do
        local e, m = list[i], marks[i]
        local frac = e and ((e.p and e.p / 100) or (max and e.v / max)) or nil
        if frac and frac > 0 and frac < 1 and bw > 0 then
            if not m then
                -- on the StatusBar, over its fill (a texture on the bar's
                -- own frame draws under the fill)
                m = bar.bar:CreateTexture(nil, "OVERLAY", nil, 3)
                m:SetTexture(WHITE)
                -- (2026-11-19: whole screen pixels under ZacUI's look, Core_Pixel; one unit everywhere else, as before)
                m:SetWidth(ns.Snap and ns.Snap(1, bar.bar) or 1)
                marks[i] = m
            end
            local x = math.floor(bw * frac + 0.5)
            m:ClearAllPoints()
            m:SetPoint("TOP", bar.bar, "TOPLEFT", x, 1)
            m:SetPoint("BOTTOM", bar.bar, "BOTTOMLEFT", x, -1)
            m:SetVertexColor(r, g, b, a)
            m.frac = frac
            m:Show()
        elseif m then
            m.frac = nil
            m:Hide()
        end
    end
end

-- ------------------------------------------------------------
-- the cost block on one bar
-- ------------------------------------------------------------
local function CostTex(bar)
    local t = bar._v2cost
    if t then return t end
    -- over the fill and its sheen, under the bar's number and edge
    t = bar.bar:CreateTexture(nil, "ARTWORK", nil, 5)
    t:SetTexture(WHITE)
    local fill = bar.bar:GetStatusBarTexture()
    t:SetPoint("TOPRIGHT", fill, "TOPRIGHT", 0, 0)
    t:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", 0, 0)
    -- held inside the bar (a cost larger than what is left would reach
    -- past the bar's start)
    if bar.bar.CreateMaskTexture and t.AddMaskTexture then
        local mask = bar.bar:CreateMaskTexture()
        mask:SetTexture(WHITE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(bar.bar)
        t:AddMaskTexture(mask)
    end
    t:Hide()
    bar._v2cost = t
    return t
end

local function ShowCost(bar, cost, max, r, g, b, a)
    cost, max = Plain(cost), Plain(max)
    local bw = bar:GetWidth() or 0
    if type(cost) ~= "number" or type(max) ~= "number" or cost <= 0 or max <= 0 or bw <= 0 then
        if bar._v2cost and bar._v2costW then
            bar._v2costW = nil
            bar._v2cost:Hide()
        end
        return
    end
    local w = math.max(1, math.floor(bw * math.min(cost, max) / max + 0.5))
    local t = CostTex(bar)
    local col = r * 1e9 + g * 1e6 + b * 1e3 + a
    if bar._v2costW ~= w or bar._v2costC ~= col then
        bar._v2costW, bar._v2costC = w, col
        t:SetWidth(w)
        t:SetVertexColor(r, g, b, a)
        t:Show()
    end
end

local function HideCost(bar)
    if bar and bar._v2cost and bar._v2costW then
        bar._v2costW = nil
        bar._v2cost:Hide()
    end
end

-- ------------------------------------------------------------
-- the cast in hand (your own casts; the events store, nothing more)
-- ------------------------------------------------------------
local GetCost = (C_Spell and C_Spell.GetSpellPowerCost) or GetSpellPowerCost

-- what a spell takes: { [power type] = cost }, nil when it takes nothing
-- that can be read plainly
local function CostsOf(spellID)
    if not GetCost then return nil end
    local ok, list = pcall(GetCost, spellID)
    if not ok or type(list) ~= "table" then return nil end
    local out
    for _, c in ipairs(list) do
        if type(c) == "table" then
            local ptype, cost, aura, has = Plain(c.type), Plain(c.cost), Plain(c.requiredAuraID), Plain(c.hasRequiredAura)
            if type(ptype) == "number" and type(cost) == "number" and cost > 0
                and (aura == nil or aura == 0 or has == true) then
                out = out or {}
                out[ptype] = cost
            end
        end
    end
    return out
end

function Engine:V2WatchCasts(on)
    if self.sample or on == (self._v2castWatch or false) then return end
    self._v2castWatch = on
    local ev = self.ev
    if on then
        for _, e in ipairs(CAST_EVENTS) do pcall(ev.RegisterUnitEvent, ev, e, "player") end
    else
        for _, e in ipairs(CAST_EVENTS) do ev:UnregisterEvent(e) end
        self._v2cast = nil
    end
end

local BaseEvent = Engine.V2Event
function Engine:V2Event(event, a1, a2, a3)
    if event == "UNIT_SPELLCAST_START" then
        -- (unit, cast id, spell id)
        local guid, id = Plain(a2), Plain(a3)
        local costs = id and CostsOf(id) or nil
        self._v2cast = costs and { guid = guid, costs = costs } or nil
        return
    elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
        -- a second spell pressed during a cast fails with a cast id of its
        -- own: only the cast in hand ends the block
        local cast = self._v2cast
        if cast then
            local guid = Plain(a2)
            if cast.guid == nil or guid == nil or guid == cast.guid then self._v2cast = nil end
        end
        return
    end
    if BaseEvent then return BaseEvent(self, event, a1, a2, a3) end
end

-- ------------------------------------------------------------
-- the passes
-- ------------------------------------------------------------
local function MarkColor(cfg)
    local c = Cfg(cfg)
    return HUD.Col(c and c.color, MARK_COL)
end
local function CostColor(cfg)
    local c = Cfg(cfg)
    return HUD.Col(c and c.costColor, COST_COL)
end

-- 0.2 s: the marks, the cast watch, and a cast the events lost
local BaseRefresh = Engine.V2Refresh
function Engine:V2Refresh(cfg)
    if BaseRefresh then BaseRefresh(self, cfg) end
    if not self.built then return end
    local marks, cost = AnyMarks(cfg), V2.CostOn(cfg)
    if not (marks or cost or self._v2pmOn) then return end
    local on = self:On(cfg)
    self._v2pmOn = (marks or cost) and true or nil
    if not self.sample then
        self:V2WatchCasts(on and cost)
        if self._v2cast then
            -- no cast in hand any more (an event that never came)
            local info = UnitCastingInfo or CastingInfo
            if info then
                local ok, name = pcall(info, "player")
                if ok and name == nil then self._v2cast = nil end
            end
        end
    end
    local r, g, b, a = MarkColor(cfg)
    local mana, power = self.manaBar, self.powerBar
    if mana then
        if on and marks and mana:IsShown() then
            PlaceMarks(mana, MarksText(cfg, "MANA"), ManaMax(mana), r, g, b, a)
        else
            HideMarks(mana)
        end
    end
    if power then
        if on and marks and power:IsShown() then
            local _, key, max = PowerOf(self)
            PlaceMarks(power, MarksText(cfg, key), max, r, g, b, a)
        else
            HideMarks(power)
        end
    end
    if not (on and cost) then
        HideCost(mana)
        HideCost(power)
    end
end

-- 0.1 s: the cost block
local BaseTextTick = Engine.V2TextTick
function Engine:V2TextTick()
    if BaseTextTick then BaseTextTick(self) end
    local cast = self._v2cast
    local mana, power = self.manaBar, self.powerBar
    if not cast then
        if self._v2costUp then
            self._v2costUp = nil
            HideCost(mana)
            HideCost(power)
        end
        return
    end
    local cfg = self:Store()
    if not (cfg and V2.CostOn(cfg)) then return end
    self._v2costUp = true
    local r, g, b, a = CostColor(cfg)
    local costs = cast.costs
    if mana then
        if costs[0] and mana:IsShown() then ShowCost(mana, costs[0], ManaMax(mana), r, g, b, a) else HideCost(mana) end
    end
    if power then
        local ptype, _, max = PowerOf(self)
        local c = ptype and costs[ptype]
        -- (a HUD with a mana bar of its own shows a mana cost there)
        if c and power:IsShown() and not (ptype == 0 and mana) then ShowCost(power, c, max, r, g, b, a) else HideCost(power) end
    end
end

local BaseHideAll = Engine.V2HideAll
function Engine:V2HideAll()
    if BaseHideAll then BaseHideAll(self) end
    for _, bar in ipairs({ self.manaBar or false, self.powerBar or false }) do
        if bar then
            HideMarks(bar)
            HideCost(bar)
        end
    end
    self._v2costUp = nil
end

local BaseApplySizes = Engine.V2ApplySizes
function Engine:V2ApplySizes(cfg)
    if BaseApplySizes then BaseApplySizes(self, cfg) end
    -- a new width: the marks and the block are placed again
    for _, bar in ipairs({ self.manaBar or false, self.powerBar or false }) do
        if bar then
            if bar._v2mk then bar._v2mk.bw = nil end
            bar._v2costW = bar._v2costW and 0 or nil
        end
    end
end

-- the preview: a cast in hand in a fight (a tenth of the bar)
local BaseFillSample = Engine.V2FillSample
function Engine:V2FillSample(mode, combat)
    if BaseFillSample then BaseFillSample(self, mode, combat) end
    local cfg = self:Store()
    if not (cfg and combat and V2.CostOn(cfg)) then
        self._v2cast = nil
        return
    end
    local S = self.S
    local costs = {}
    if self.manaBar then costs[0] = math.floor((S.manaMax or 0) / 10) end
    if self.powerBar then
        local ptype = PowerOf(self)
        if ptype then costs[ptype] = math.floor((S.powerMax or 0) / 10) end
    end
    self._v2cast = { costs = costs }
end

-- ------------------------------------------------------------
-- the page (General)
-- ------------------------------------------------------------
local BaseTabGeneral = Engine.V2Tab_General
function Engine:V2Tab_General(L, cfg)
    if BaseTabGeneral then BaseTabGeneral(self, L, cfg) end
    local keys = self:V2PowerMarkKeys()
    if #keys == 0 then return end
    local eng = self
    L:Card("Marks and spell cost")
    L:Desc("A thin line across the bar at each value you type: where there is enough for a spell. "
        .. "Numbers with a comma between them, up to " .. MAX_MARKS .. "; a number with % is a share of the bar (50%).")
    for _, k in ipairs(keys) do
        local key, label = k[1], k[2]
        local function Keep(text)
            local _, tidy = V2.ParseMarks(text or "")
            local c = Cfg(cfg, true)
            if tidy ~= "" then
                c.at = type(c.at) == "table" and c.at or {}
                c.at[key] = tidy
            elseif type(c.at) == "table" then
                c.at[key] = nil
                if next(c.at) == nil then c.at = nil end
            end
            V2.Tidy(cfg)
            eng:Refresh()
        end
        HUD.Label(L, label .. " marks at")
        local eb = UI.EditBox(L.current, { width = 220, text = MarksText(cfg, key) or "", hint = "35, 60 or 50%",
            onChange = Keep, onEnter = function(text) Keep(text) HUD.RefreshPage() end })
        L:Row(eb, UI.M.EDIT_H + 8)
    end
    HUD.CheckIndent(L, "Show what the spell you are casting will cost", V2.CostOn(cfg), function(v)
        Cfg(cfg, true).cost = v or nil
        V2.Tidy(cfg)
        eng:Refresh()
        HUD.RefreshPage()
    end, nil, "A block over the end of the bar while you cast a spell with a cast time, as wide as what it takes.")
    local colours = {}
    if AnyMarks(cfg) then
        colours[#colours + 1] = { "Marks",
            get = function() return MarkColor(cfg) end,
            set = function(r, g, b, a)
                Cfg(cfg, true).color = { r = r, g = g, b = b, a = a or 1 }
                eng:Refresh()
            end }
    end
    if V2.CostOn(cfg) then
        colours[#colours + 1] = { "Spell cost",
            get = function() return CostColor(cfg) end,
            set = function(r, g, b, a)
                Cfg(cfg, true).costColor = { r = r, g = g, b = b, a = a or 1 }
                eng:Refresh()
            end }
    end
    if #colours > 0 then HUD.ColorGrid(L, colours) end
    L:EndCard()
end
