-- HUD_V2_Specs - Class HUD v2: the spec defaults. Each class definition's
-- roles are spec presets (HUD_V2_Sources): what a strong player of that
-- spec tracks on the grid, the utility row, the buff and debuff rows, the
-- trinket row, which glows and which resource extras. The HUD starts as
-- the preset of the spec in force:
--   - the one you picked on the page (cfg.v2.role; "baseline" = none), else
--   - the one your talents point at (Classic Era / TBC: the tree with most
--     points; WoW Forever: the trait group with most ranks), the druid's
--     Feral Combat split by the form you fight in (bear: rage, else cat),
--   - no talents or under level 10: the class baseline (every entry's own
--     default: the HUD as it always was).
-- An entry you never ticked or unticked follows the spec; one you did
-- stays as you set it. "Reset to spec defaults" (Sources) clears yours.
-- The spec is read again after a talent / level / form change, half a
-- second after the last one and only out of combat (a change in a fight
-- waits for its end); the events only note the time. The preview can show
-- any spec (a picker on the preview's strip, never saved).
-- Part of ZacUI; load order is set by the TOC (right after HUD_V2_Sources).

local ns = _G.ZacUI
if not ns or not ns.HUD or not ns.HUD.V2 or not ns.HUD.ClassEngine then return end
local HUD = ns.HUD
local V2 = HUD.V2
local Engine = HUD.ClassEngine

local GetTime = GetTime
local SETTLE = 0.5
local SPEC_EVENTS = { "CHARACTER_POINTS_CHANGED", "PLAYER_TALENT_UPDATE", "ACTIVE_TALENT_GROUP_CHANGED",
    "TRAIT_CONFIG_UPDATED", "PLAYER_LEVEL_UP" }
-- (Retail plays by spec: its own event for a spec swap, watched there only)
if HUD.RETAIL then SPEC_EVENTS[#SPEC_EVENTS + 1] = "PLAYER_SPECIALIZATION_CHANGED" end

-- ------------------------------------------------------------
-- the spec in force
-- ------------------------------------------------------------
-- the HUD on screen behind a preview's sample
function Engine:V2Live()
    if not self.sample then return self end
    for _, e in ipairs(HUD.ClassInstances or {}) do
        if e.def == self.def and not e.sample then return e end
    end
    return nil
end

-- what the talents point at (applied out of combat), nil = baseline
function Engine:V2DetectedSpec()
    local live = self:V2Live()
    return live and live._v2spec or nil
end

-- your pick, else the talents'; nil = the class baseline
function Engine:V2ActiveSpec()
    if self.sample then
        local p = self._v2previewSpec
        if p == "baseline" then return nil end
        if p and V2.RoleByKey(self.def, p) then return p end
    end
    local cfg = self:Store()
    local v = cfg and cfg.v2
    local pick = v and v.role
    if pick == "baseline" then return nil end
    if pick and V2.RoleByKey(self.def, pick) then return pick end
    return self:V2DetectedSpec()
end

function Engine:V2SpecRole()
    local key = self:V2ActiveSpec()
    return key and V2.RoleByKey(self.def, key) or nil
end

-- an entry off its row: your tick (true / false) first, then the spec's
-- preset for that row (the game's own catalogue entries keep theirs),
-- then the entry's own default
function Engine:V2Off(row, hidden, def)
    local v = hidden and hidden[def.key]
    if v ~= nil then return v and true or false end
    if def.fromGame and self.def.retail then
        -- Retail: every entry is the game's, and the spec's preset TICKS
        -- the ones it names (by the entry's own id, its override or a
        -- linked one); the rest keep their own default
        local role = self:V2SpecRole()
        local set = role and role.show[row]
        if set then
            if set[def.key] then return false end
            for _, k in ipairs(def.altKeys or {}) do
                if set[k] then return false end
            end
        end
    elseif not def.fromGame then
        local role = self:V2SpecRole()
        local set = role and role.show[row]
        if set then return not set[def.key] end
    end
    return def.defaultHidden and true or false
end

-- the trinket and racial row: your switch, else the spec's
function Engine:V2AuxOn(cfg)
    local v = cfg.v2 and cfg.v2.aux
    if v ~= nil then return v and true or false end
    if cfg.aux and cfg.aux.enabled then return true end
    local role = self:V2SpecRole()
    return (role and role.aux) and true or false
end

-- the glow rules of one icon: yours (an empty list = none), else the spec's
function Engine:V2RulesFor(cfg, gk)
    local mine = type(cfg.glows) == "table" and cfg.glows[gk]
    if mine ~= nil then return mine, true end
    local role = self:V2SpecRole()
    local g = role and role.glows
    return g and g[gk] or nil, false
end

-- every icon key with rules in force: fn(gk, rules)
function Engine:V2EachGlow(cfg, fn)
    local mine = type(cfg.glows) == "table" and cfg.glows or nil
    local role = self:V2SpecRole()
    local spec = role and role.glows
    if spec then
        for gk, rules in pairs(spec) do
            if not (mine and mine[gk] ~= nil) then fn(gk, rules) end
        end
    end
    if mine then
        for gk, rules in pairs(mine) do fn(gk, rules) end
    end
end

function Engine:V2AnyGlows(cfg)
    if type(cfg.glows) == "table" and next(cfg.glows) ~= nil then return true end
    local role = self:V2SpecRole()
    return (role and role.glows and next(role.glows) ~= nil) and true or false
end

-- a resource extra: your switch, else the spec's
function Engine:V2ResValue(cfg, key)
    local r = V2.Sub(cfg, "res")
    local v = r and r[key]
    if v ~= nil then return v end
    local role = self:V2SpecRole()
    return role and role.res and role.res[key] or nil
end

-- ------------------------------------------------------------
-- reading the spec: events note the time, the tick applies it
-- ------------------------------------------------------------
function Engine:V2MarkSpec()
    if self.sample then return end
    self._v2specAt = self._v2specAt or GetTime()
end

function Engine:V2ApplySpec(force)
    local new = V2.GuessRole(self.def, self._v2feralPT)
    if new ~= self._v2spec or force then
        self._v2spec = new
        for _, m in pairs(self.memo or {}) do HUD.ForgetLayout(m) end
        return true
    end
    return false
end

-- on the engine's 0.2 s tick (HUD_V2_Rows' refresh hook)
function Engine:V2SpecTick()
    if self.sample or not (self.def.roles and self.def.roles[1]) then return end
    local S = self.S
    -- the druid's form: rage = bear, energy = cat; caster form keeps the last
    if self.def.class == "DRUID" then
        local pt = S.powerType
        if (pt == 1 or pt == 3) and pt ~= self._v2feralPT then
            self._v2feralPT = pt
            self:V2MarkSpec()
        end
    end
    local at = self._v2specAt
    if not at or S.inCombat or GetTime() - at < SETTLE then return end
    self._v2specAt = nil
    self:V2ApplySpec()
end

local function WatchSpec(eng)
    if eng._v2specFrame then return end
    local f = CreateFrame("Frame")
    eng._v2specFrame = f
    local valid = C_EventUtils and C_EventUtils.IsEventValid
    for _, ev in ipairs(SPEC_EVENTS) do
        if not valid or valid(ev) then pcall(f.RegisterEvent, f, ev) end
    end
    f:SetScript("OnEvent", function() eng:V2MarkSpec() end)
end

-- at login (after the class check): the spec read now when out of
-- combat, else at the fight's end; the talent events watched
local BaseLogin = Engine.V2Login
function Engine:V2Login(cfg)
    if BaseLogin then BaseLogin(self, cfg) end
    if self.sample or not (self.def.roles and self.def.roles[1]) or not self.S.isClass then return end
    WatchSpec(self)
    self._v2feralPT = (self.S.powerType == 1 or self.S.powerType == 3) and self.S.powerType or nil
    if self.S.inCombat then self:V2MarkSpec() else self:V2ApplySpec() end
end

-- ------------------------------------------------------------
-- the preview: a spec picker on its strip (never saved)
-- ------------------------------------------------------------
function Engine:V2SpecItems(withAuto)
    local items = {}
    if withAuto then
        local d = self:V2DetectedSpec()
        local r = d and V2.RoleByKey(self.def, d)
        items[#items + 1] = { value = "auto", text = r and ("Automatic (" .. r.label .. ")") or "Automatic (class baseline)" }
    end
    for _, r in ipairs(self.def.roles or {}) do items[#items + 1] = { value = r.key, text = r.label } end
    items[#items + 1] = { value = "baseline", text = "Class baseline" }
    return items
end

function Engine:V2PreviewControls(holder, P)
    if not (self.def.roles and self.def.roles[1] and ns.UI and ns.UI.Dropdown) then return end
    local eng = self
    local items = {}
    local function Items()
        wipe(items)
        items[1] = { value = "current", text = "This HUD's spec" }
        for _, r in ipairs(eng.def.roles) do items[#items + 1] = { value = r.key, text = r.label } end
        items[#items + 1] = { value = "baseline", text = "Class baseline" }
        return items
    end
    local function Text()
        local cur = P.store.v2spec or "current"
        for _, it in ipairs(Items()) do if it.value == cur then return it.text end end
        return "This HUD's spec"
    end
    local dd = ns.UI.Dropdown(holder, { width = 150, items = Items, selected = Text,
        selectedValue = function() return P.store.v2spec or "current" end,
        onSelect = function(v)
            P.store.v2spec = (v ~= "current") and v or nil
            if P.Update then P.Update() end
        end })
    dd:SetPoint("LEFT", holder, "LEFT", 0, 0)
    if dd.SetText then dd:SetText(Text()) end
    P.store.v2specDropdown = dd
end

-- the sample takes the preview's pick before each update
function Engine:V2PreviewUpdate(s, P)
    local pick = P.store.v2spec
    if s._v2previewSpec ~= pick then
        s._v2previewSpec = pick
        for _, m in pairs(s.memo or {}) do HUD.ForgetLayout(m) end
    end
end

-- for the setup and other pages: the presets of a class HUD
function V2.SpecPresets(store)
    for _, e in ipairs(HUD.ClassInstances or {}) do
        if e.def.store == store and not e.sample then return e.def.roles, e end
    end
    return nil
end
