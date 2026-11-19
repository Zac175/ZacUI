-- HUD_V2_CastBar - Class HUD v2: the cast bar (HUD.CastBar, in
-- Shared\HUD_CastBar.lua) on the class HUD engine (2026-11-18). Off until
-- turned on (General tab); its own anchor and mover while it is on. The
-- bar itself, what it reads and what it does with a hidden cast are in
-- that file; here are its place among the HUD's elements, the engine's
-- tick handing it "the HUD is up", and its card.
-- Settings: cfg.v2.castbar (the bar's own table).
-- Part of ZacUI; load order is set by the TOC (after HUD_V2_PowerMarks).

local ns = _G.ZacUI
if not ns or not ns.HUD or not ns.HUD.V2 or not ns.HUD.CastBar then return end
local HUD = ns.HUD
local V2 = HUD.V2
local Engine = HUD.ClassEngine
local CB = HUD.CastBar

-- where its mover starts (never written): under the HUD; on Retail,
-- whose utility row and buff bars sit there, over the buff row
local POS = { x = 0, y = -370 }
local POS_RETAIL = { x = 0, y = -122 }
local function Pos(eng) return eng.def.retail and POS_RETAIL or POS end

local function Cfg(cfg, create) return V2.Sub(cfg, "castbar", create) end
V2.CastBarCfg = Cfg

function V2.CastBarOn(cfg)
    local c = Cfg(cfg)
    return (c and c.enabled) and true or false
end

-- ------------------------------------------------------------
-- element, anchor, the bar
-- ------------------------------------------------------------
local BaseElements = Engine.V2Elements
function Engine:V2Elements(list)
    if BaseElements then BaseElements(self, list) end
    local cfg = self:Store()
    if not (cfg and V2.CastBarOn(cfg)) then return end
    if not self.sample and not self.anchors.CastBar then return end
    local pos = Pos(self)
    list[#list + 1] = { key = "CastBar", mover = self.def.prefix .. "CastBar", label = "Cast Bar",
        cfg = function() return pos end }
end

local function SizeAnchor(eng, cfg)
    local w, h = CB.Size(Cfg(cfg))
    local a, hd = eng.anchors.CastBar, eng.holders.CastBar
    if a then a:SetSize(w, h) end
    if hd and hd ~= a then hd:SetSize(w, h) end
end

local function MakeBar(eng)
    if eng.castBar or not eng.anchors.CastBar then return end
    eng.castBar = CB.New({
        anchor = eng.anchors.CastBar,
        settings = function() return Cfg(eng:Store()) end,
        sample = eng.sample,
        -- the preview's made-up cast: the grid's first spell
        sampleSpell = function()
            local e = eng.def.grid and eng.def.grid[1]
            local sp = e and e.spell and eng.S.spells[e.spell]
            if sp then return sp.name, sp.icon end
        end,
    })
end

-- turned on after login: the anchor and its mover are made now
function Engine:V2EnsureCastBar()
    if self.sample or self.anchors.CastBar or not self.S.isClass then return end
    local cfg = self:Store()
    local w, h = CB.Size(Cfg(cfg))
    self:MakeAnchor("CastBar", w, h)
    local key = self.def.prefix .. "CastBar"
    HUD.PlaceAnchor(key, self.holders.CastBar, Pos(self))
    HUD.RegisterMover(key, self.def.label .. " Cast Bar", self.holders.CastBar, Pos(self))
    MakeBar(self)
end

local BaseBuild = Engine.V2Build
function Engine:V2Build(cfg)
    if BaseBuild then BaseBuild(self, cfg) end
    if self.anchors.CastBar then
        SizeAnchor(self, cfg)
        MakeBar(self)
    end
end

local BaseLogin = Engine.V2Login
function Engine:V2Login(cfg)
    if BaseLogin then BaseLogin(self, cfg) end
    if cfg and V2.CastBarOn(cfg) then self:V2EnsureCastBar() end
end

-- ------------------------------------------------------------
-- the 0.2 s pass: "the HUD is up" to the bar
-- ------------------------------------------------------------
local BaseRefresh = Engine.V2Refresh
function Engine:V2Refresh(cfg)
    if BaseRefresh then BaseRefresh(self, cfg) end
    local on = V2.CastBarOn(cfg)
    if not (on or self.castBar) then return end
    if on and self.sample and not self.anchors.CastBar and self.canvas then
        -- turned on while the preview's sample was up
        local w, h = CB.Size(Cfg(cfg))
        local a = HUD.SampleAnchor(self.canvas, w, h)
        self.anchors.CastBar, self.holders.CastBar = a, a
    end
    -- (switched on by something other than the page: a profile, an import)
    if on and not self.sample and not self.anchors.CastBar then self:V2EnsureCastBar() end
    if not self.castBar then MakeBar(self) end
    local bar = self.castBar
    if not bar then return end
    if on then
        -- (a size from the page: the anchor follows before the bar lays out)
        local w, h = CB.Size(Cfg(cfg))
        if bar._w ~= w or bar._h ~= h then
            bar._w, bar._h = w, h
            SizeAnchor(self, cfg)
        end
    end
    bar:Update(self:On(cfg) and on, self.preview)
end

local BaseHideAll = Engine.V2HideAll
function Engine:V2HideAll()
    if BaseHideAll then BaseHideAll(self) end
    if self.castBar then self.castBar:Update(false) end
end

local BaseSampleOn = Engine.V2SampleOn
function Engine:V2SampleOn(on, scale, cfg)
    if BaseSampleOn then BaseSampleOn(self, on, scale, cfg) end
    on.CastBar = V2.CastBarOn(cfg)
end

-- ------------------------------------------------------------
-- the page (General)
-- ------------------------------------------------------------
local BaseTabGeneral = Engine.V2Tab_General
function Engine:V2Tab_General(L, cfg)
    if BaseTabGeneral then BaseTabGeneral(self, L, cfg) end
    local eng = self
    CB.Card(L, {
        get = function(create) return Cfg(cfg, create) end,
        changed = function(structure)
            V2.Tidy(cfg)
            if V2.CastBarOn(cfg) then eng:V2EnsureCastBar() end
            eng:Refresh()
            if structure then HUD.RefreshPage() end
        end,
        sizes = function()
            V2.Tidy(cfg)
            eng:ApplySizes()
        end,
    })
end
