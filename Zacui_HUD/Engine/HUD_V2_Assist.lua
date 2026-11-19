-- HUD_V2_Assist - Class HUD v2: the rotation helper's next spell,
-- highlighted (2026-11-18). The game has a rotation helper of its own
-- (C_AssistedCombat: the spell it would cast next). With this on, the
-- icon of that spell on the cooldown grid or the utility row wears a
-- glow of its own colour while the helper names it.
--   what it reads   C_AssistedCombat.GetNextCastSpell on the HUD's 0.2 s
--                   tick (the game's own action bars poll it on a timer
--                   too); nothing when the setting is off or the helper
--                   is not available on this character (IsAvailable).
--   which icon      the one whose spell has that id (on Retail the id in
--                   force or one of its other ids), else the one with
--                   that spell's name (a Classic HUD names rank 1, the
--                   helper the rank you know).
--   hidden values   an id the game hides is never compared: no glow.
-- Settings: cfg.v2.assist { enabled, color }.
-- Part of ZacUI; load order is set by the TOC (after HUD_V2_Custom).

local ns = _G.ZacUI
if not ns or not ns.HUD or not ns.HUD.V2 then return end
local HUD = ns.HUD
local V2 = HUD.V2
local Engine = HUD.ClassEngine

local GetSpellInfo = HUD.GetSpellInfo
local GLOW_KEY = "v2assist"
local COLOR = { r = 0.35, g = 0.78, b = 1, a = 1 }
V2.ASSIST_COLOR = COLOR

local function Cfg(cfg, create) return V2.Sub(cfg, "assist", create) end
V2.AssistCfg = Cfg

-- the game's helper exists and says it can be used on this character
function V2.AssistAvailable()
    local AC = C_AssistedCombat
    if not (AC and AC.GetNextCastSpell and AC.IsAvailable) then return false end
    local ok, can = pcall(AC.IsAvailable)
    return (ok and not ns.IsSecret(can) and can == true) and true or false
end

function V2.AssistOn(cfg)
    local a = Cfg(cfg)
    return (a and a.enabled) and true or false
end

local function Color(cfg)
    local a = Cfg(cfg)
    return HUD.Col(a and a.color, COLOR)
end

-- the glow on one icon, made on first need
local function Light(eng, icon, on, r, g, b, a)
    if on and not icon._v2assist then
        icon._v2assist = icon:AddGlow(GLOW_KEY, "Pixel", { color = { r, g, b, a } })
        icon._v2assistC = r * 1e6 + g * 1e3 + b
    end
    if not icon._v2assist then return end
    if on then
        local c = r * 1e6 + g * 1e3 + b
        if icon._v2assistC ~= c then
            icon._v2assistC = c
            local Wd = eng.W
            if Wd and Wd.SetGlowColor then Wd.SetGlowColor(icon._v2assist, r, g, b, a) end
        end
    end
    if (icon._v2assistOn or false) ~= on then
        icon._v2assistOn = on
        icon:SetGlow(GLOW_KEY, on)
    end
end

-- the shown icon the helper's spell belongs to
local function IconFor(eng, id)
    local S, def = eng.S, eng.def
    local name = GetSpellInfo and GetSpellInfo(id) or nil
    if ns.IsSecret(name) then name = nil end
    local byName
    for li = 1, 2 do
        local list = (li == 1) and eng.mainActive or eng.utilActive
        for _, icon in ipairs(list or {}) do
            local e = icon.def
            if e and e.kind == "spell" and e.spell then
                if (def.spells and def.spells[e.spell] == id) or e.curId == id then return icon end
                for _, alt in ipairs(e.altIds or {}) do
                    if alt == id then return icon end
                end
                local sp = S.spells[e.spell]
                if not byName and name and sp and sp.name == name then byName = icon end
            end
        end
    end
    return byName
end

local function AssistOff(eng)
    local cur = eng._v2assistIcon
    if cur then
        Light(eng, cur, false)
        eng._v2assistIcon = nil
    end
end

local function AssistPass(eng, cfg)
    if not (eng:On(cfg) and V2.AssistOn(cfg)) then return AssistOff(eng) end
    local icon
    if eng.sample then
        -- the preview lights the first ready spell while "in combat"
        if eng.S.inCombat then
            for _, ic in ipairs(eng.mainActive) do
                if ic.def and ic.def.kind == "spell" and ic.state == "ready" then icon = ic break end
            end
        end
    else
        -- (availability is asked once a pass: it changes with level and spec)
        if not V2.AssistAvailable() then return AssistOff(eng) end
        local ok, id = pcall(C_AssistedCombat.GetNextCastSpell, false)
        if ok and type(id) == "number" and not ns.IsSecret(id) and id > 0 then
            icon = IconFor(eng, id)
        end
    end
    local cur = eng._v2assistIcon
    if cur and cur ~= icon then Light(eng, cur, false) end
    eng._v2assistIcon = icon
    if icon then
        local r, g, b, a = Color(cfg)
        Light(eng, icon, icon:IsShown() and true or false, r, g, b, a)
    end
end

local BaseRefresh = Engine.V2Refresh
function Engine:V2Refresh(cfg)
    if BaseRefresh then BaseRefresh(self, cfg) end
    if self._v2assistIcon or V2.AssistOn(cfg) then AssistPass(self, cfg) end
end

local BaseHideAll = Engine.V2HideAll
function Engine:V2HideAll()
    if BaseHideAll then BaseHideAll(self) end
    AssistOff(self)
end

-- ------------------------------------------------------------
-- the page (Look, after the glow rules)
-- ------------------------------------------------------------
local BaseTabLook = Engine.V2Tab_Look
function Engine:V2Tab_Look(L, cfg)
    if BaseTabLook then BaseTabLook(self, L, cfg) end
    -- (no card where the game's helper cannot be used: nothing to switch)
    if not V2.AssistAvailable() and not V2.AssistOn(cfg) then return end
    local eng = self
    L:Card("Rotation helper")
    L:Desc("The game's own rotation helper picks the spell it would cast next. With this on, that spell's icon on the "
        .. "cooldown grid or the utility row wears a glow in the colour below while the helper names it.")
    HUD.CheckIndent(L, "Highlight the helper's next spell", V2.AssistOn(cfg), function(v)
        Cfg(cfg, true).enabled = v or nil
        V2.Tidy(cfg)
        eng:Refresh()
    end)
    HUD.ColorGrid(L, { { "Helper highlight",
        get = function() return Color(cfg) end,
        set = function(r, g, b, a)
            Cfg(cfg, true).color = { r = r, g = g, b = b, a = a or 1 }
            eng:Refresh()
        end } })
    L:EndCard()
end
