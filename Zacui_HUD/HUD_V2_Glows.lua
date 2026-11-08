-- HUD_V2_Glows - Class HUD v2: glows with conditions. A rule on an icon
-- (cfg.glows[iconKey], a list) lights a glow while its condition holds:
-- ready, ready and usable, on cooldown, its buff or debuff up, down,
-- about to run out, at a stack count, a refresh now would clip the DoT
-- (anti-clip: casting after your current cast and the global cooldown
-- would land at or after the aura's expiry - on every game version,
-- vanilla auras carry no time over), the next-swing attack queued, or
-- the game's own proc highlight; with an optional second buff that must
-- be up or down, "only in combat", a colour (the style's, the class's or
-- your own) and a sound when it lights. Styles are ZacUI's own: Edge
-- (the HUD's pulsing border), Solid, Pulse, Sweep, Shine, and on clients
-- that have it the game's own button overlay glow.
-- Perf: nothing runs until a rule is saved; rules are evaluated on the
-- engine's 0.2 s tick for the icons that have one, from state the tick
-- already holds; proc and queue events only set flags. Animations are
-- the client's animation groups (no Lua per frame).
-- Part of ZacUI; load order is set by the TOC (after HUD_V2_Icon).

local ns = _G.ZacUI
if not ns or not ns.HUD or not ns.HUD.V2 then return end
local HUD = ns.HUD
local V2 = HUD.V2
local Engine = HUD.ClassEngine

local GetTime = GetTime
local GetSpellInfo = HUD.GetSpellInfo
local WHITE = "Interface\\Buttons\\WHITE8X8"
local STAR = "Interface\\Cooldown\\star4"
local GOLD = { 1, 0.82, 0, 1 }

V2.GLOW_WHEN = {
    { id = "ready",    label = "Ready" },
    { id = "usable",   label = "Ready and usable" },
    { id = "oncd",     label = "On cooldown" },
    { id = "active",   label = "Its buff or debuff is up" },
    { id = "missing",  label = "Its buff or debuff is down" },
    { id = "expiring", label = "About to run out" },
    { id = "stacks",   label = "At a stack count" },
    { id = "anticlip", label = "Safe to recast (it would not clip)" },
    { id = "queued",   label = "Queued for the next swing" },
    { id = "proc",     label = "The game highlights it (proc)" },
}
V2.GLOW_STYLES = {
    { id = "edge",  label = "Edge (the HUD's glow)" },
    { id = "solid", label = "Solid border" },
    { id = "pulse", label = "Pulse" },
    { id = "sweep", label = "Sweep" },
    { id = "shine", label = "Shine" },
}
-- the game's own overlay glow, where the client has the function (Classic
-- Era / TBC; the modern clients draw spell alerts another way)
if type(ActionButton_ShowOverlayGlow) == "function" and type(ActionButton_HideOverlayGlow) == "function"
    and not (ns.ModernClient and ns.ModernClient()) then
    V2.GLOW_STYLES[#V2.GLOW_STYLES + 1] = { id = "blizzard", label = "The game's own glow" }
    V2.BLIZZ_GLOW = true
end
V2.STACK_OPS = { { id = ">=", label = "at least" }, { id = "==", label = "exactly" }, { id = "<=", label = "at most" } }

-- ------------------------------------------------------------
-- the glow drawings, per icon and rule
-- ------------------------------------------------------------
local function Strips(parent, px, r, g, b, a)
    local f = CreateFrame("Frame", nil, parent)
    f:SetPoint("TOPLEFT", parent, "TOPLEFT", -px, px)
    f:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", px, -px)
    f:SetFrameLevel((parent:GetFrameLevel() or 1) + 6)
    f.strips = {}
    for i = 1, 4 do
        local t = f:CreateTexture(nil, "OVERLAY")
        t:SetTexture(WHITE)
        f.strips[i] = t
    end
    f.strips[1]:SetPoint("TOPLEFT") f.strips[1]:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 0, -px)
    f.strips[2]:SetPoint("BOTTOMLEFT") f.strips[2]:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, px)
    f.strips[3]:SetPoint("TOPLEFT") f.strips[3]:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", px, 0)
    f.strips[4]:SetPoint("TOPRIGHT") f.strips[4]:SetPoint("BOTTOMLEFT", f, "BOTTOMRIGHT", -px, 0)
    function f:Paint(cr, cg, cb, ca)
        for i = 1, 4 do self.strips[i]:SetVertexColor(cr, cg, cb, ca) end
    end
    f:Paint(r, g, b, a)
    return f
end

local Make = {}

function Make.edge(icon, key, r, g, b, a)
    local gl = icon:AddGlow(key, "Pixel", { color = { r, g, b, a } })
    return { f = gl, show = function() icon:SetGlow(key, true) end, hide = function() icon:SetGlow(key, false) end,
        paint = function(cr, cg, cb, ca)
            local Wd = ns.WarriorHUD and ns.WarriorHUD.Widgets
            if Wd and Wd.SetGlowColor then Wd.SetGlowColor(gl, cr, cg, cb, ca) end
        end }
end

function Make.solid(icon, key, r, g, b, a)
    local f = Strips(icon, 2, r, g, b, a)
    f:Hide()
    return { f = f, show = function() f:Show() end, hide = function() f:Hide() end, paint = function(...) f:Paint(...) end }
end

function Make.pulse(icon, key, r, g, b, a)
    local f = CreateFrame("Frame", nil, icon)
    f:SetAllPoints(icon.icon or icon)
    f:SetFrameLevel((icon:GetFrameLevel() or 1) + 6)
    local t = f:CreateTexture(nil, "OVERLAY")
    t:SetAllPoints(f)
    t:SetTexture(WHITE)
    t:SetBlendMode("ADD")
    t:SetVertexColor(r, g, b, a)
    local ag = f:CreateAnimationGroup()
    local al = ag:CreateAnimation("Alpha")
    al:SetFromAlpha(0.08) al:SetToAlpha(0.55) al:SetDuration(0.6)
    ag:SetLooping("BOUNCE")
    f:Hide()
    return { f = f, show = function() f:Show() ag:Play() end, hide = function() ag:Stop() f:Hide() end,
        paint = function(cr, cg, cb, ca) t:SetVertexColor(cr, cg, cb, ca) end }
end

function Make.sweep(icon, key, r, g, b, a)
    local f = CreateFrame("Frame", nil, icon)
    f:SetPoint("TOPLEFT", icon, "TOPLEFT", -2, 2)
    f:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 2, -2)
    f:SetFrameLevel((icon:GetFrameLevel() or 1) + 6)
    local SPARK = 6
    local t = f:CreateTexture(nil, "OVERLAY")
    t:SetTexture(WHITE)
    t:SetBlendMode("ADD")
    t:SetSize(SPARK, SPARK)
    t:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    t:SetVertexColor(r, g, b, a)
    -- a spark running the four legs of the edge, round and round (the
    -- texture's own animation: a frame's translation would move the icon)
    local ag = t:CreateAnimationGroup()
    local legs = {}
    for i = 1, 4 do
        local tr = ag:CreateAnimation("Translation")
        tr:SetDuration(0.25)
        tr:SetOrder(i)
        legs[i] = tr
    end
    ag:SetLooping("REPEAT")
    -- the legs follow the icon's size at the time it lights
    local function Fit()
        local w = (icon:GetWidth() or 30) + 4 - SPARK
        local h = (icon:GetHeight() or 30) + 4 - SPARK
        legs[1]:SetOffset(w, 0) legs[2]:SetOffset(0, -h) legs[3]:SetOffset(-w, 0) legs[4]:SetOffset(0, h)
    end
    f:Hide()
    return { f = f, show = function() Fit() f:Show() ag:Play() end, hide = function() ag:Stop() f:Hide() end,
        paint = function(cr, cg, cb, ca) t:SetVertexColor(cr, cg, cb, ca) end }
end

function Make.shine(icon, key, r, g, b, a)
    local f = CreateFrame("Frame", nil, icon)
    f:SetAllPoints(icon)
    f:SetFrameLevel((icon:GetFrameLevel() or 1) + 6)
    local t = f:CreateTexture(nil, "OVERLAY")
    t:SetTexture(STAR)
    t:SetBlendMode("ADD")
    t:SetPoint("CENTER", f, "CENTER", 0, 0)
    t:SetVertexColor(r, g, b, a)
    -- (a rotation turns textures only: the group is the star's own)
    local ag = t:CreateAnimationGroup()
    local ro = ag:CreateAnimation("Rotation")
    ro:SetDegrees(-360) ro:SetDuration(2.5)
    ag:SetLooping("REPEAT")
    local function Fit()
        local w, h = icon:GetWidth() or 30, icon:GetHeight() or 30
        t:SetSize(w * 1.7, h * 1.7)
    end
    f:Hide()
    return { f = f, show = function() Fit() f:Show() ag:Play() end, hide = function() ag:Stop() f:Hide() end,
        paint = function(cr, cg, cb, ca) t:SetVertexColor(cr, cg, cb, ca) end }
end

function Make.blizzard(icon, key, r, g, b, a)
    return { show = function() if ActionButton_ShowOverlayGlow then pcall(ActionButton_ShowOverlayGlow, icon) end end,
        hide = function() if ActionButton_HideOverlayGlow then pcall(ActionButton_HideOverlayGlow, icon) end end,
        paint = function() end }
end

-- the glow of one rule on one icon: made on first need, one drawing per
-- style it has worn (kept, so switching back makes nothing new), the
-- colour repainted on change
local function GlowOf(icon, rule, idx)
    local list = icon._v2rules
    if not list then list = {} icon._v2rules = list end
    local key = "v2g" .. idx
    local slot = list[key]
    if not slot then slot = { drawings = {}, on = false } list[key] = slot end
    local style = Make[rule.style] and rule.style or "edge"
    local r, gg, b, a = V2.GlowColor(rule)
    local g = slot.g
    if g and slot.style ~= style then
        if slot.on then g.hide() slot.on = false end
        g = nil
    end
    if not g then
        g = slot.drawings[style]
        if not g then
            g = Make[style](icon, key .. style, r, gg, b, a)
            g.r, g.g, g.b, g.a = r, gg, b, a
            slot.drawings[style] = g
        end
        slot.g, slot.style = g, style
    end
    if g.r ~= r or g.g ~= gg or g.b ~= b or g.a ~= a then
        g.r, g.g, g.b, g.a = r, gg, b, a
        g.paint(r, gg, b, a)
    end
    return slot
end

function V2.GlowColor(rule)
    local mode = rule.colorMode or "default"
    if mode == "class" and ns.ClassColor then
        local _, cls = UnitClass("player")
        local cr, cg, cb = ns.ClassColor(cls)
        if type(cr) == "table" then cr, cg, cb = cr.r or cr[1], cr.g or cr[2], cr.b or cr[3] end
        if type(cr) == "number" then return cr, cg or 1, cb or 1, 1 end
    elseif mode == "custom" and type(rule.color) == "table" then
        local c = rule.color
        return c.r or c[1] or 1, c.g or c[2] or 1, c.b or c[3] or 1, c.a or c[4] or 1
    end
    return GOLD[1], GOLD[2], GOLD[3], GOLD[4]
end

-- ------------------------------------------------------------
-- conditions
-- ------------------------------------------------------------
-- spell id and spell name -> true while the game highlights it (by name
-- too: the event names the rank you know, the HUD the top rank)
local procs = {}
local procFrame
local function WatchProcs(on)
    if not procFrame then
        procFrame = CreateFrame("Frame")
        procFrame:SetScript("OnEvent", function(_, event, id)
            if type(id) ~= "number" or ns.IsSecret(id) then return end
            local v = (event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW") and true or nil
            procs[id] = v
            local name = GetSpellInfo and GetSpellInfo(id)
            if type(name) == "string" and not ns.IsSecret(name) then procs[name] = v end
        end)
    end
    if on and not procFrame._on then
        procFrame._on = true
        pcall(procFrame.RegisterEvent, procFrame, "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
        pcall(procFrame.RegisterEvent, procFrame, "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
    elseif not on and procFrame._on then
        procFrame._on = nil
        procFrame:UnregisterAllEvents()
        wipe(procs)
    end
end
V2.procs = procs

-- the aura behind an icon: an aura-row icon's own, or the grid spell's
-- buff on you / debuff on the target by name
local function AuraOf(eng, icon)
    local b = icon.auraRef
    if b then return b end
    local def = icon.def
    local S = eng.S
    local name
    if def.kind == "spell" and def.spell then
        local sp = S.spells[def.spell]
        name = sp and sp.name
    elseif def.id then
        name = S.auraNames[def.key]
    end
    if not name then return nil end
    local l = name:lower()
    return S.buffs[l] or S.targetDebuffs[l]
end

-- seconds until you can cast again: the cast running now, then the GCD
local function FreeIn(eng)
    if eng.sample then return 0 end
    local free = 0
    if UnitCastingInfo then
        local _, _, _, _, endMS = UnitCastingInfo("player")
        if type(endMS) == "number" and not ns.IsSecret(endMS) then
            free = math.max(0, endMS / 1000 - GetTime())
        end
    end
    local gcd = ns.GCDSpell and ns.GCDSpell()
    if gcd and HUD.GetSpellCooldown then
        local s, d = HUD.GetSpellCooldown(gcd)
        if type(s) == "number" and type(d) == "number" and d > 0 then
            free = math.max(free, s + d - GetTime())
        end
    end
    return free
end

local function CastTime(eng, icon)
    local def = icon.def
    local id = (def.kind == "spell" and def.spell and eng.def.spells[def.spell]) or def.id
    if not id or not GetSpellInfo then return 0 end
    local _, _, _, castMS = GetSpellInfo(id)
    if type(castMS) ~= "number" or ns.IsSecret(castMS) then return 0 end
    return castMS / 1000
end

-- on cooldown (not the global one): a spell by its read cooldown, an
-- item by the engine's word, a trinket / racial by its swipe
local function OnCD(eng, icon)
    local def = icon.def
    if def.kind == "spell" and def.spell then
        local cd = eng.S.cds[def.spell]
        return (cd and cd.real) and true or false
    end
    if icon.state == "cooldown" then return true end
    if icon.state == "ready" then return false end
    local d = icon.cdDuration
    return type(d) == "number" and not ns.IsSecret(d) and d > 1.51 or false
end

local function Stacks(a)
    local c = a and a.count
    if type(c) ~= "number" or ns.IsSecret(c) then return 0 end
    return c
end

local function Holds(eng, icon, rule, now)
    local S = eng.S
    local when = rule.when or "ready"
    local def = icon.def
    if rule.combatOnly and not S.inCombat then return false end
    local r
    if when == "ready" then
        r = not OnCD(eng, icon)
    elseif when == "usable" then
        local us = def.spell and S.usable[def.spell]
        r = not OnCD(eng, icon) and icon.state ~= "nopower" and not (us and us.usable == false)
    elseif when == "oncd" then
        r = OnCD(eng, icon)
    elseif when == "active" or when == "missing" then
        local a = AuraOf(eng, icon)
        local up = a ~= nil and (icon.auraRef == nil or icon:IsShown())
        r = (when == "active") == up
    elseif when == "expiring" then
        local a = AuraOf(eng, icon)
        local exp = a and a.expirationTime
        if type(exp) == "number" and not ns.IsSecret(exp) and exp > 0 then
            local v = eng:Store().v2
            r = (exp - now) <= ((v and tonumber(v.expiring)) or V2.EXPIRING_DEFAULT)
        else
            r = false
        end
    elseif when == "stacks" then
        local n = Stacks(AuraOf(eng, icon))
        local want = tonumber(rule.stacksN) or 1
        local op = rule.stacksOp or ">="
        if op == "==" then r = n == want elseif op == "<=" then r = n > 0 and n <= want else r = n >= want end
    elseif when == "anticlip" then
        -- casting it now (after your current cast and the global cooldown)
        -- would land at or after the running aura's end: vanilla auras
        -- carry no time over, so earlier would waste what is left
        local a = AuraOf(eng, icon)
        local exp = a and a.expirationTime
        if type(exp) == "number" and not ns.IsSecret(exp) and exp > 0 then
            local left = exp - now
            local window = CastTime(eng, icon) + FreeIn(eng)
            if eng.sample then window = math.max(window, 10) end   -- (the preview shows one lit)
            r = left > 0 and left <= window
        else
            r = false
        end
    elseif when == "queued" then
        local sp = def.spell and S.spells[def.spell]
        r = sp and sp.name and S.queued and S.queued[sp.name] or false
        if eng.sample then r = def.nextSwing and S.inCombat or false end
    elseif when == "proc" then
        local id = def.spell and eng.def.spells[def.spell] or def.id
        local sp = def.spell and S.spells[def.spell]
        r = (id ~= nil and procs[id] == true) or (sp ~= nil and sp.name ~= nil and procs[sp.name] == true)
        if eng.sample then r = icon.state == "ready" and (def.key:len() % 2 == 0) end
    else
        r = false
    end
    if r and rule.andKey then
        local name = S.auraNames[rule.andKey]
        local up = name ~= nil and S.buffs[name:lower()] ~= nil
        if (rule.andState or "up") == "up" then r = up else r = not up end
    end
    return r and true or false
end

-- ------------------------------------------------------------
-- the pass (engine hook: V2Glows from V2Icons)
-- ------------------------------------------------------------
-- A rule's icon key: the grid's and the utility row's keys as they are
-- (no key is on both), the other rows' as "row:key" (a buff row entry
-- often shares its spell's key on the grid).
function V2.GlowKey(row, key)
    if row == "main" or row == "utility" then return key end
    return row .. ":" .. key
end

function Engine:V2IconByKey(gk)
    local row, key = gk:match("^(%a+):(.+)$")
    if row then
        local field = V2.ROW_ICONS[row]
        local icons = field and self[field]
        return icons and icons[key] or nil
    end
    return self.mainIcons[gk] or (self.utilIcons and self.utilIcons[gk]) or nil
end

-- the definition entry behind a rule's icon key (nil: not on this HUD)
function Engine:V2EntryByKey(gk)
    local row, key = gk:match("^(%a+):(.+)$")
    if row == "aux" then return { key = key } end
    local lists = row and { self.def[V2.LIST_OF[row] or ""] } or { self.def.grid, self.def.utility }
    for _, list in ipairs(lists) do
        for _, e in ipairs(list or {}) do if e.key == (key or gk) then return e end end
    end
    return nil
end

-- The conditions that can hold on an icon: cooldown ones where it has a
-- cooldown, aura ones where it has an aura, the anti-clip one only on a
-- DoT a refresh would clip (or the spell that casts it), the queued one
-- only on a next-swing attack. A saved rule keeps its condition listed.
function Engine:V2GlowWhenFor(gk, keep)
    local row = gk:match("^(%a+):") or "main"
    local e = self:V2EntryByKey(gk) or {}
    local S = self.S
    local isAura = row == "buffs" or row == "debuffs"
    local isSpell = e.kind == "spell"
    local dot = e.castsDot and true or false
    if isSpell and not dot then
        local sp = S.spells[e.spell or ""]
        local lname = sp and sp.name and sp.name:lower()
        for _, d in ipairs(self.def.debuffRow or {}) do
            if d.castsDot and (d.key == e.key or d.key == e.spell
                or (lname and S.auraNames[d.key] and S.auraNames[d.key]:lower() == lname)) then dot = true end
        end
    end
    local ok = {
        ready = not isAura, usable = isSpell, oncd = not isAura,
        active = isAura or isSpell, missing = isAura or isSpell, expiring = isAura or isSpell,
        stacks = isAura or isSpell, anticlip = dot, queued = e.nextSwing and true or false,
        proc = isSpell,
    }
    local out = {}
    for _, w in ipairs(V2.GLOW_WHEN) do
        if ok[w.id] or w.id == keep then out[#out + 1] = w end
    end
    return out
end

function Engine:V2Event(event)
    if event == "ACTIONBAR_UPDATE_STATE" then self._v2queueDirty = true end
end

-- the HUD hidden or switched off: every glow out, the proc / queue
-- watches stood down (the next pass with rules starts them again)
function Engine:V2GlowsOff()
    if not self._v2glowsOn then return end
    self._v2glowsOn = nil
    for _, field in pairs(V2.ROW_ICONS) do
        for _, icon in pairs(self[field] or {}) do
            for _, slot in pairs(icon._v2rules or {}) do
                if slot.on then slot.on = false slot.g.hide() end
            end
        end
    end
    if not self.sample then
        WatchProcs(false)
        self:V2WatchQueue(self:V2QueueWanted(self:Store(), true))
    end
end

-- the rules in force: yours, else the spec's (HUD_V2_Specs); without
-- that file, yours alone
local function EachGlow(eng, cfg, fn)
    if eng.V2EachGlow then return eng:V2EachGlow(cfg, fn) end
    if type(cfg.glows) == "table" then for gk, rules in pairs(cfg.glows) do fn(gk, rules) end end
end
local function RulesFor(eng, cfg, gk)
    if eng.V2RulesFor then return (eng:V2RulesFor(cfg, gk)) end
    return type(cfg.glows) == "table" and cfg.glows[gk] or nil
end
local function AnyWhen(eng, cfg, when)
    local hit = false
    EachGlow(eng, cfg, function(_, rules)
        if not hit and type(rules) == "table" then
            for _, rule in ipairs(rules) do if type(rule) == "table" and rule.when == when then hit = true end end
        end
    end)
    return hit
end

function Engine:V2Glows(cfg)
    local any
    if self.V2AnyGlows then any = self:V2AnyGlows(cfg)
    else any = type(cfg.glows) == "table" and next(cfg.glows) ~= nil end
    if not any then
        self:V2GlowsOff()
        return
    end
    self._v2glowsOn = true
    if not self.sample then
        WatchProcs(AnyWhen(self, cfg, "proc"))
        self:V2WatchQueue(self:V2QueueWanted(cfg))
    end
    local now = GetTime()
    -- icons whose rules went (another icon picked, a list emptied)
    for _, field in pairs(V2.ROW_ICONS) do
        for _, icon in pairs(self[field] or {}) do
            if icon._v2rules then
                for k, slot in pairs(icon._v2rules) do
                    if slot.on then
                        local n = tonumber(k:match("^v2g(%d+)$")) or 0
                        local rules = icon._v2gk and RulesFor(self, cfg, icon._v2gk)
                        if type(rules) ~= "table" or n > #rules then slot.on = false slot.g.hide() end
                    end
                end
            end
        end
    end
    EachGlow(self, cfg, function(key, rules)
        local icon = type(key) == "string" and self:V2IconByKey(key)
        if icon and type(rules) == "table" then
            icon._v2gk = key
            for idx, rule in ipairs(rules) do
                if type(rule) == "table" then
                    local slot = GlowOf(icon, rule, idx)
                    local on = icon:IsShown() and Holds(self, icon, rule, now)
                    if on ~= slot.on then
                        slot.on = on
                        if on then
                            slot.g.show()
                            if rule.sound and rule.sound ~= "none" and not self.sample and ns.PlaySoundSpec then
                                ns.PlaySoundSpec({ sound = rule.sound, throttle = 1 }, nil, "hudglow." .. key .. idx)
                            end
                        else
                            slot.g.hide()
                        end
                    end
                end
            end
        end
    end)
end

-- whether anything reads the queued attack: a glow rule on it, or the
-- swing bar's queued colour (HUD_V2_Resources); noGlows: the glows are out
function Engine:V2QueueWanted(cfg, noGlows)
    if type(cfg) ~= "table" then return false end
    if not noGlows and AnyWhen(self, cfg, "queued") then return true end
    return (self.V2ResWantsQueue and self:V2ResWantsQueue(cfg)) and true or false
end

-- the next-swing attack queued (Heroic Strike / Cleave / Maul / Raptor
-- Strike): ACTIONBAR_UPDATE_STATE only flags; the tick asks IsCurrentSpell
-- for the entries flagged nextSwing (a hidden answer = not queued)
function Engine:V2WatchQueue(on)
    if on == (self._v2queueOn or false) then return end
    self._v2queueOn = on
    local ev = self.ev
    if on then
        pcall(ev.RegisterEvent, ev, "ACTIONBAR_UPDATE_STATE")
        self.S.queued = self.S.queued or {}
        self._v2queueDirty = true
    else
        ev:UnregisterEvent("ACTIONBAR_UPDATE_STATE")
        self.S.queued = nil
    end
end

function Engine:V2ReadQueue()
    local S = self.S
    if not (S.queued and self._v2queueDirty) then return end
    self._v2queueDirty = false
    wipe(S.queued)
    local IsCur = HUD.IsCurrentSpell
    if not IsCur then return end
    for _, list in ipairs({ self.def.grid or {}, self.def.utility or {} }) do
        for _, e in ipairs(list) do
            if e.nextSwing and e.spell then
                local sp = S.spells[e.spell]
                if sp and sp.known and sp.name then
                    local ok, cur = pcall(IsCur, sp.name)
                    if ok and not ns.IsSecret(cur) and cur then S.queued[sp.name] = true end
                end
            end
        end
    end
end
