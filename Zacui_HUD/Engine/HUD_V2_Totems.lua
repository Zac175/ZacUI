-- HUD_V2_Totems - Class HUD v2: totem timers (2026-11-18). A row of the
-- totems you have down, each with its icon, a sweep and the time it has
-- left, on the Shaman HUD. Off until turned on (General tab); its own
-- anchor and mover while it is on.
--   what it reads   GetTotemInfo for the four totem slots, on the HUD's
--                   0.2 s tick (four calls); the time text on the 0.1 s
--                   text tick, from what the tick stored. No event.
--   hidden values   a slot the game will not read plainly (a client that
--                   hides it in a fight) shows nothing: never compared.
-- Settings: cfg.v2.totems { enabled, iconSize, spacing }.
-- Part of ZacUI; load order is set by the TOC (after HUD_V2_Resources).

local ns = _G.ZacUI
if not ns or not ns.HUD or not ns.HUD.V2 then return end
local HUD = ns.HUD
local V2 = HUD.V2
local Engine = HUD.ClassEngine

local GetTime = GetTime
local HUD_STRATA = "MEDIUM"
local SLOTS = 4
local POS = { x = 0, y = -330 }        -- where its mover starts (never written)
local SIZE, SPACE = 28, 4
-- the preview's made-up totems: one spell of each element, for its icon
-- (Searing, Strength of Earth, Mana Spring, Windfury Totem)
local SAMPLE = { { 3599, 22, 55 }, { 8075, 96, 120 }, { 5675, 40, 60 }, { 8512, 71, 120 } }

local function Cfg(cfg, create) return V2.Sub(cfg, "totems", create) end
V2.TotemsCfg = Cfg

local function Plain(v)
    if v == nil or ns.IsSecret(v) then return nil end
    return v
end

function Engine:V2HasTotems()
    return self.def.class == "SHAMAN" and type(GetTotemInfo) == "function"
end

function V2.TotemsOn(cfg)
    local t = Cfg(cfg)
    return (t and t.enabled) and true or false
end

-- ------------------------------------------------------------
-- element, anchor, icons
-- ------------------------------------------------------------
local BaseElements = Engine.V2Elements
function Engine:V2Elements(list)
    if BaseElements then BaseElements(self, list) end
    local cfg = self:Store()
    if not (cfg and self:V2HasTotems() and V2.TotemsOn(cfg)) then return end
    if not self.sample and not self.anchors.Totems then return end
    list[#list + 1] = { key = "Totems", mover = self.def.prefix .. "Totems", label = "Totem Timers",
        cfg = function() return POS end }
end

local function BuildTotems(eng)
    local W, anchor = eng.W, eng.anchors.Totems
    if not (W and anchor) or eng.totemIcons then return end
    eng.totemIcons, eng.totemActive = {}, {}
    eng.memo.totems = eng.memo.totems or {}
    local c = Cfg(eng:Store())
    local size = (c and c.iconSize) or SIZE
    for slot = 1, SLOTS do
        local icon = W.CreateIcon(anchor, { width = size, height = size, zoom = W.ICON_ZOOM, keepAspect = true, inverse = true })
        icon:SetFrameStrata(HUD_STRATA)
        icon:Hide()
        icon.def = { key = "totem" .. slot, totem = slot }
        icon:AddText("p", "BELOW", 12, { 1, 1, 1, 1 }, 0, 0)
        icon:SetText("p", "")
        eng.totemIcons[slot] = icon
    end
end

-- turned on after login: the anchor and its mover are made now
function Engine:V2EnsureTotems()
    if self.sample or self.anchors.Totems or not self.S.isClass or not self:V2HasTotems() then return end
    self:MakeAnchor("Totems", SIZE, SIZE)
    local key = self.def.prefix .. "Totems"
    HUD.PlaceAnchor(key, self.holders.Totems, POS)
    HUD.RegisterMover(key, self.def.label .. " Totem Timers", self.holders.Totems, POS)
    if self.built then BuildTotems(self) end
end

local BaseBuild = Engine.V2Build
function Engine:V2Build(cfg)
    if BaseBuild then BaseBuild(self, cfg) end
    if self.anchors.Totems then BuildTotems(self) end
end

local BaseLogin = Engine.V2Login
function Engine:V2Login(cfg)
    if BaseLogin then BaseLogin(self, cfg) end
    if cfg and V2.TotemsOn(cfg) then self:V2EnsureTotems() end
end

-- ------------------------------------------------------------
-- the 0.2 s pass
-- ------------------------------------------------------------
local function RefreshTotems(eng, cfg)
    local anchor = eng.anchors.Totems
    if not anchor and eng.sample and eng.canvas and eng:V2HasTotems() and V2.TotemsOn(cfg) then
        -- the row was turned on while the preview's sample was up
        anchor = HUD.SampleAnchor(eng.canvas, SIZE, SIZE)
        eng.anchors.Totems, eng.holders.Totems = anchor, anchor
    end
    if not anchor and not eng.sample and eng:V2HasTotems() and V2.TotemsOn(cfg) then
        -- switched on by something other than the page (a profile, an import)
        eng:V2EnsureTotems()
        anchor = eng.anchors.Totems
    end
    if not anchor then return end
    if not eng.totemIcons then BuildTotems(eng) end
    local icons = eng.totemIcons
    if not icons then return end
    local W = eng.W
    local c = Cfg(cfg)
    local on = eng:On(cfg) and c and c.enabled
    local active = eng.totemActive
    wipe(active)
    local now = GetTime()
    for slot = 1, SLOTS do
        local icon = icons[slot]
        local shown = false
        if on then
            if eng.sample or eng.preview then
                local s = SAMPLE[slot]
                icon:SetIconTexture((HUD.GetSpellTexture and HUD.GetSpellTexture(s[1])) or 134400)
                icon.tStart, icon.tDur = now - (s[3] - s[2]), s[3]
                icon:SetSwipe(icon.tStart, icon.tDur)
                shown = eng.preview or eng.S.inCombat or slot <= 2
            else
                local ok, have, _, start, duration, tex = pcall(GetTotemInfo, slot)
                have, start, duration = Plain(have), Plain(start), Plain(duration)
                if ok and have == true and type(start) == "number" and type(duration) == "number" then
                    icon:SetIconTexture(Plain(tex) or 134400)
                    icon.tStart, icon.tDur = start, duration
                    if duration > 0 then icon:SetSwipe(start, duration) else icon:ClearSwipe() end
                    shown = true
                end
            end
        end
        if not shown then icon.tStart, icon.tDur = nil, nil end
        W.SetShownAnimated(icon, shown)
        if shown then active[#active + 1] = icon end
    end
    local size = (c and c.iconSize) or SIZE
    eng:LayoutRow("totems", eng.memo.totems, active, anchor, size, size, (c and c.spacing) or SPACE)
end

local BaseRefresh = Engine.V2Refresh
function Engine:V2Refresh(cfg)
    if BaseRefresh then BaseRefresh(self, cfg) end
    if self:V2HasTotems() then RefreshTotems(self, cfg) end
end

local BaseTextTick = Engine.V2TextTick
function Engine:V2TextTick()
    if BaseTextTick then BaseTextTick(self) end
    local active = self.totemActive
    if not active or #active == 0 then return end
    local W, now = self.W, GetTime()
    for _, icon in ipairs(active) do
        local left = (icon.tDur or 0) > 0 and (icon.tStart + icon.tDur - now) or 0
        icon:SetText("p", left > 0 and W.FormatTime(left, 0) or "")
    end
end

local BaseHideAll = Engine.V2HideAll
function Engine:V2HideAll()
    if BaseHideAll then BaseHideAll(self) end
    for _, icon in pairs(self.totemIcons or {}) do icon:Hide() end
    if self.memo.totems then HUD.ForgetLayout(self.memo.totems) end
end

local BaseApplySizes = Engine.V2ApplySizes
function Engine:V2ApplySizes(cfg)
    if BaseApplySizes then BaseApplySizes(self, cfg) end
    if self.memo.totems then HUD.ForgetLayout(self.memo.totems) end
end

local BaseSampleOn = Engine.V2SampleOn
function Engine:V2SampleOn(on, scale, cfg)
    if BaseSampleOn then BaseSampleOn(self, on, scale, cfg) end
    on.Totems = self:V2HasTotems() and V2.TotemsOn(cfg)
end

-- ------------------------------------------------------------
-- the page (General)
-- ------------------------------------------------------------
local BaseTabGeneral = Engine.V2Tab_General
function Engine:V2Tab_General(L, cfg)
    if BaseTabGeneral then BaseTabGeneral(self, L, cfg) end
    if not self:V2HasTotems() then return end
    local eng = self
    local c = Cfg(cfg)
    L:Card("Totem timers")
    L:Desc("The totems you have down, each with the time it has left. A row of its own: its spot is under Position.")
    HUD.CheckIndent(L, "Show totem timers", V2.TotemsOn(cfg), function(v)
        Cfg(cfg, true).enabled = v or nil
        V2.Tidy(cfg)
        if v then eng:V2EnsureTotems() end
        eng:Refresh()
        HUD.RefreshPage()
    end)
    if V2.TotemsOn(cfg) then
        HUD.SliderPair(L,
            { "Totem icon size", 16, 48, (c and c.iconSize) or SIZE, function(v)
                Cfg(cfg, true).iconSize = (v ~= SIZE) and v or nil
                eng:ApplySizes()
            end, function(v) return v .. " px" end },
            { "Totem spacing", 0, 12, (c and c.spacing) or SPACE, function(v)
                Cfg(cfg, true).spacing = (v ~= SPACE) and v or nil
                eng:ApplySizes()
            end, function(v) return v .. " px" end })
    end
    L:EndCard()
end
