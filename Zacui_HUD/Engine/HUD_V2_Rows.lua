-- HUD_V2_Rows - Class HUD v2: the rows. A utility row beside the cooldown
-- grid (the class's lesser cooldowns, off until turned on), every row laid
-- out by a saved layout where one is saved (ZacUI's layout shape, nil =
-- the row's own layout, untouched), a visibility rule per row (ZacUI's
-- visibility shape on the row's anchor: alpha only, events only),
-- placeholders for buffs that are down (kept in place, or greyed), and a
-- tooltip on hover per row (icons stay click-through until it is on).
-- Methods on the class HUD engine (HUD.ClassEngine); the engine calls the
-- V2* hooks and they do nothing until a setting asks for something.
-- Part of ZacUI; load order is set by the TOC (after HUD_V2_Keybinds).

local ns = _G.ZacUI
if not ns or not ns.HUD or not ns.HUD.V2 then return end
local HUD = ns.HUD
local V2 = HUD.V2
local Engine = HUD.ClassEngine

local HUD_STRATA = "MEDIUM"
local GCD_MAX = 1.51
local UTIL_POS = { x = 0, y = -250 }   -- where the utility row's mover starts (never written)
local GOLD_COUNT = { 1, 0.82, 0, 1 }

-- the utility row's settings (cfg.v2.utility), nil until saved
local function Util(cfg, create) return V2.Sub(cfg, "utility", create) end
V2.Util = Util

function V2.UtilityOn(cfg)
    local u = Util(cfg)
    return (u and u.enabled) and true or false
end

-- ------------------------------------------------------------
-- engine hooks: state, anchors, build
-- ------------------------------------------------------------
function Engine:V2Init()
    self.utilIcons, self.utilActive = {}, {}
    self.phIcons = {}
    self.memo.utility = {}
end

-- the utility row joins the element list while it is on (its anchor,
-- mover and settings preview come with it)
function Engine:V2Elements(list)
    local cfg = self:Store()
    if not (cfg and V2.UtilityOn(cfg) and self.def.utility and #self.def.utility > 0) then return end
    -- the live HUD lists it once its anchor exists (V2EnsureUtility makes
    -- it); the sample makes its anchors from this list
    if not self.sample and not self.anchors.Utility then return end
    list[#list + 1] = { key = "Utility", mover = self.def.prefix .. "Utility", label = "Utility row",
        cfg = function(c) local u = Util(c) return (u and (u.x or u.y)) and u or UTIL_POS end }
end

-- turned on after login: the anchor and its mover are made now
function Engine:V2EnsureUtility()
    if self.sample or self.anchors.Utility or not self.S.isClass then return end
    self:MakeAnchor("Utility", 28, 28)
    local cfg = self:Store()
    if not cfg then return end
    local key = self.def.prefix .. "Utility"
    HUD.PlaceAnchor(key, self.holders.Utility, UTIL_POS)
    HUD.RegisterMover(key, self.def.label .. " Utility row", self.holders.Utility, UTIL_POS)
    if self.built then self:V2BuildUtility() end
    self:V2Visibility()
end

function Engine:V2BuildUtility()
    local W = self.W
    local anchor = self.anchors.Utility
    if not (W and anchor) then return end
    local cfg = self:Store()
    local u = cfg and Util(cfg)
    local size = (u and u.iconSize) or 25
    for _, def in ipairs(self.def.utility or {}) do
        if not self.utilIcons[def.key] then
            local icon = W.CreateIcon(anchor, { width = size, height = size, zoom = W.ICON_ZOOM, keepAspect = true, inverse = true })
            icon:SetFrameStrata(HUD_STRATA)
            icon:Hide()
            icon.def = def
            icon:AddText("p", "CENTER", 12, { 1, 1, 1, 1 })
            icon:SetText("p", "")
            if def.kind ~= "spell" then icon:AddText("count", "INNER_BOTTOMRIGHT", 11, GOLD_COUNT, 0, 0) end
            self.utilIcons[def.key] = icon
        end
    end
end

-- the rows' visibility rules: the anchor fades by cfg.visibility.<row>
-- (nothing saved = never touched); live HUD only
function Engine:V2Visibility()
    if self.sample or not (ns.Visibility and ns.Visibility.Register) then return end
    local eng = self
    for row, key in pairs(V2.ROW_ANCHOR) do
        local anchor = self.anchors[key]
        if anchor and not anchor._v2vis then
            anchor._v2vis = true
            ns.Visibility.Register(anchor, function()
                local cfg = eng:Store()
                local v = cfg and cfg.visibility
                return type(v) == "table" and v[row] or nil
            end, { control = "alpha" })
        end
    end
end

function Engine:V2Build(cfg)
    self:V2BuildUtility()
    self:V2Visibility()
    if self.V2BuildIcons then self:V2BuildIcons(cfg) end
end

-- ------------------------------------------------------------
-- refresh (the engine's 0.2s tick, after its own rows)
-- ------------------------------------------------------------
function Engine:V2RefreshUtility(cfg)
    local anchor = self.anchors.Utility
    if not anchor and self.sample and self.canvas and V2.UtilityOn(cfg) then
        -- the row was turned on while the preview's sample was up
        anchor = HUD.SampleAnchor(self.canvas, 28, 28)
        self.anchors.Utility, self.holders.Utility = anchor, anchor
        self:V2BuildUtility()
    end
    if not anchor then return end
    local W, S = self.W, self.S
    local u = Util(cfg)
    local on = u and u.enabled and self:On(cfg)
    local hidden = u and u.hidden
    wipe(self.utilActive)
    for _, def in ipairs(self.def.utility or {}) do
        local icon = self.utilIcons[def.key]
        if icon then
            local shown = false
            if on and not self:V2Off("utility", hidden, def) then
                if self.preview then
                    local sp = def.spell and S.spells[def.spell]
                    icon:SetIconTexture((sp and sp.icon) or 134400)
                    icon:SetDesat(false)
                    icon:ClearSwipe()
                    icon:SetIconColor(1, 1, 1, 1)
                    icon.state = "ready"
                    shown = (not def.spell) or (sp and sp.known) or false
                else
                    shown = self:UpdateMainIcon(icon, def, cfg)
                end
            end
            W.SetShownAnimated(icon, shown)
            if shown then self.utilActive[#self.utilActive + 1] = icon end
        end
    end
    local size = (u and u.iconSize) or 25
    self:LayoutRow("utility", self.memo.utility, self.utilActive, anchor, size, size, (u and u.spacing) or 4)
end

function Engine:V2Refresh(cfg)
    if self.V2SpecTick then self:V2SpecTick() end
    self:V2RefreshUtility(cfg)
    if self.V2Icons then self:V2Icons(cfg) end
    if self.V2Mouse then self:V2Mouse(cfg) end
end

function Engine:V2HideAll()
    for _, icon in pairs(self.utilIcons or {}) do icon:Hide() end
    for _, icon in pairs(self.phIcons or {}) do icon:Hide() end
    HUD.ForgetLayout(self.memo.utility)
    if self.V2GlowsOff then self:V2GlowsOff() end
end

function Engine:V2ApplySizes(cfg)
    HUD.ForgetLayout(self.memo.utility)
end

function Engine:V2Positions(cfg)
    local a = self.anchors.Utility
    if a then
        local u = Util(cfg)
        a:SetScale((u and u.scale) or 1)
    end
end

-- ------------------------------------------------------------
-- layouts: a saved layout (cfg.layouts.<row>) lays the row out through
-- ZacUI's layout helper; nothing saved = the row's own layout
-- ------------------------------------------------------------
function Engine:V2LayoutSpec(row)
    local cfg = self:Store()
    local l = cfg and cfg.layouts
    return type(l) == "table" and l[row] or nil
end

-- the layout defaults a row's own placement amounts to (what the
-- picker shows as "default"; the real default path is the row's own code)
function V2.LayoutDefaults(row, a, b, c)
    if row == "main" then
        local rows, space = a, b
        local r1 = rows and rows[1] or {}
        return { grow = "CENTER", wrap = "DOWN", perLine = r1.limit or 7, spacingX = space or 4, spacingY = space or 4,
            itemW = r1.w or 30, itemH = r1.h or 30, padding = 0 }
    end
    return { grow = "CENTER", wrap = "DOWN", perLine = 0, spacingX = c or 4, spacingY = c or 4,
        itemW = a or 25, itemH = b or 25, padding = 0 }
end

local function SameList(memo, list, spec)
    local n = #list
    if memo.v2spec ~= spec or memo.v2n ~= n then return false end
    for i = 1, n do if memo[i] ~= list[i] then return false end end
    return true
end

local function V2Layout(memo, list, anchor, spec, def)
    if SameList(memo, list, spec) then return end
    memo.v2spec, memo.v2n = spec, #list
    for i = 1, #list do memo[i] = list[i] end
    for i = #list + 1, (memo.n or 0) do memo[i] = nil end
    memo.n = nil   -- the row's own layout lays out afresh if the saved one goes
    ns.LayoutItems(list, #list, anchor, spec, def, nil)
end

-- buff row: placeholders for buffs that are down take their slot
function Engine:V2BuffList(list)
    local cfg = self:Store()
    local v = cfg and cfg.v2
    local mode = v and v.buffsMissing
    local on = (mode == "keep" or mode == "grey") and self.W ~= nil
    if on then
        local rowCfg = cfg.auraRow
        if rowCfg.enabled == false or not self:On(cfg) then on = false end
    end
    if not on then
        -- placeholders of a mode that was turned off
        if self._phOn then
            self._phOn = nil
            for _, ph in pairs(self.phIcons) do ph:Hide() end
        end
        return list
    end
    self._phOn = true
    local S = self.S
    local rowCfg = cfg.auraRow
    local merged = self._phList or {}
    self._phList = merged
    wipe(merged)
    local shown = {}
    for _, icon in ipairs(list) do shown[icon] = true end
    local size = rowCfg.iconSize or 25
    for _, def in ipairs(self.def.buffRow or {}) do
        local icon = self.auraIcons[def.key]
        if icon and not self:V2Off("buffs", rowCfg.hidden, def) and S.auraNames[def.key] then
            if shown[icon] then
                merged[#merged + 1] = icon
                local ph = self.phIcons[def.key]
                if ph then ph:Hide() end
            else
                local ph = self.phIcons[def.key]
                if not ph then
                    ph = self.W.CreateIcon(self.anchors.AuraRow, { width = size, height = size, zoom = self.W.ICON_ZOOM,
                        keepAspect = true, noCooldown = true })
                    ph:SetFrameStrata(HUD_STRATA)
                    ph.def = def
                    ph.placeholder = true
                    self.phIcons[def.key] = ph
                end
                ph:SetIconTexture(S.auraIcons[def.key] or 134400)
                ph:SetDesat(true)
                ph:SetAlpha(mode == "grey" and 1 or 0)
                ph.state = "missing"
                ph:Show()
                merged[#merged + 1] = ph
            end
        end
    end
    -- placeholders of buffs that are hidden or gone
    for key, ph in pairs(self.phIcons) do
        local keep = false
        for _, m in ipairs(merged) do if m == ph then keep = true break end end
        if not keep then ph:Hide() end
    end
    return merged
end

-- ------------------------------------------------------------
-- order: a row's icons in the order dragged in the preview
-- (cfg.v2.order.<row>: entry keys; nil = the row's own order, the list
-- handed in untouched). The ordered list is kept until the row's icons or
-- the saved order change, so the 0.2s refresh makes no garbage.
-- ------------------------------------------------------------
local function IconKey(icon) return icon and icon.def and icon.def.key end
function Engine:V2Ordered(row, memo, list)
    local cfg = self:Store()
    local v = cfg and cfg.v2
    local saved = v and type(v.order) == "table" and v.order[row]
    if type(saved) ~= "table" or #saved == 0 or not ns.OrderedList then
        if memo.v2ord then memo.v2ord = nil end
        return list
    end
    local c = memo.v2ord
    if c and c.saved == saved and c.n == #list then
        local same = true
        for i = 1, #list do if c.src[i] ~= list[i] then same = false break end end
        if same then return c.out end
    end
    c = c or { src = {} }
    memo.v2ord = c
    c.saved, c.n = saved, #list
    for i = 1, #list do c.src[i] = list[i] end
    for i = #list + 1, #c.src do c.src[i] = nil end
    c.out = ns.OrderedList(list, saved, IconKey)
    return c.out
end

function Engine:LayoutGrid(row, memo, list, anchor, rowsCfg, space)
    list = self:V2Ordered(row, memo, list)
    local spec = self:V2LayoutSpec(row)
    if not spec then
        if memo.v2spec then memo.v2spec = nil HUD.ForgetLayout(memo) end
        return HUD.LayoutGrid(memo, list, anchor, rowsCfg, space)
    end
    V2Layout(memo, list, anchor, spec, V2.LayoutDefaults(row, rowsCfg, space))
end

function Engine:LayoutRow(row, memo, list, anchor, w, h, space)
    if row == "buffs" then list = self:V2BuffList(list) end
    list = self:V2Ordered(row, memo, list)
    local spec = self:V2LayoutSpec(row)
    if not spec then
        if memo.v2spec then memo.v2spec = nil HUD.ForgetLayout(memo) end
        return HUD.LayoutRow(memo, list, anchor, w, h, space)
    end
    V2Layout(memo, list, anchor, spec, V2.LayoutDefaults(row, w, h, space))
end

-- ------------------------------------------------------------
-- tooltips on hover (cfg.v2.tooltips.<row>; off = click-through, as always)
-- ------------------------------------------------------------
local function TipFor(icon)
    local def = icon.def
    if not (def and GameTooltip) then return end
    GameTooltip:SetOwner(icon, "ANCHOR_RIGHT")
    local ok = false
    if def.kind == "spell" and icon._v2SpellId then
        ok = pcall(GameTooltip.SetSpellByID, GameTooltip, icon._v2SpellId)
    elseif def.slot then
        ok = pcall(GameTooltip.SetInventoryItem, GameTooltip, "player", def.slot)
    elseif icon.curItem and icon.curItem.id then
        ok = pcall(GameTooltip.SetItemByID, GameTooltip, icon.curItem.id)
    elseif icon._v2SpellId then
        ok = pcall(GameTooltip.SetSpellByID, GameTooltip, icon._v2SpellId)
    end
    if not ok then
        GameTooltip:SetText(def.label or (icon.def.spell and tostring(icon.def.spell)) or "")
    end
    GameTooltip:Show()
end

local function TipOff() if GameTooltip then GameTooltip:Hide() end end

local ROW_ICONS = { main = "mainIcons", utility = "utilIcons", buffs = "auraIcons", debuffs = "debuffIcons",
    reminders = "remindIcons", aux = "auxIcons" }
V2.ROW_ICONS = ROW_ICONS

function Engine:V2Mouse(cfg)
    local v = cfg.v2
    local tips = v and v.tooltips
    local S = self.S
    for row, field in pairs(ROW_ICONS) do
        local on = (tips and tips[row]) and true or false
        local icons = self[field]
        if icons then
            for _, icon in pairs(icons) do
                if icon._v2mouse ~= on then
                    icon._v2mouse = on
                    if icon.EnableMouse then icon:EnableMouse(on) end
                    if on and not icon._v2tip then
                        icon._v2tip = true
                        icon:SetScript("OnEnter", TipFor)
                        icon:SetScript("OnLeave", TipOff)
                    end
                end
                if on then
                    local def = icon.def
                    local id
                    if def.kind == "spell" and def.spell then id = self.def.spells[def.spell]
                    elseif def.id then id = def.id
                    elseif def.key == "racial" and S.racial and HUD.GetSpellInfo then
                        id = select(7, HUD.GetSpellInfo(S.racial.name))
                    end
                    icon._v2SpellId = id
                end
            end
        end
    end
end

-- ------------------------------------------------------------
-- the settings preview's sample
-- ------------------------------------------------------------
function Engine:V2FillSample(mode, combat)
    local S = self.S
    local now = GetTime()
    local i = 0
    for _, g in ipairs(self.def.utility or {}) do
        if g.kind == "spell" and S.spells[g.spell] then
            i = i + 1
            local cd = S.cds[g.spell] or {}
            S.cds[g.spell] = cd
            local us = S.usable[g.spell] or {}
            S.usable[g.spell] = us
            us.usable, us.noPower = true, false
            S.inRange[g.spell] = nil
            if combat and i % 2 == 0 then
                cd.start, cd.duration, cd.real = now - 2 * i, 15 + 10 * i, true
            else
                cd.start, cd.duration, cd.real = 0, 0, false
            end
        end
    end
end

function Engine:V2SampleOn(on, scale, cfg)
    local u = Util(cfg)
    on.Utility = V2.UtilityOn(cfg)
    scale.Utility = (u and u.scale) or 1
end
