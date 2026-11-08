-- HUD_V2_Resources - Class HUD v2: extras on the HUD's resource bars, all
-- off until turned on, each only where it applies:
--   regen ticks    after the five-second rule the FSR bar keeps sweeping
--                  every 2 s (the spirit ticks; on mana you can read, a
--                  gain lines the sweep up again; on WoW Forever, whose
--                  mana is hidden in a fight, the 2 s cadence alone), in
--                  the tick colour, the five-second window staying red
--   queued attack  the swing bar in a colour of its own, and the attack's
--                  name over it, while Raptor Strike / Maul waits for the
--                  next swing (classes with such an attack)
--   range dim      WoW Forever: the swing (and Auto Shot) bar dims while
--                  the target is out of reach (the game's own swing range
--                  check, PLAYER_SWING_RANGE_UPDATE)
--   druid mana     a thin mana bar under the energy / rage bar while in
--                  an animal form
-- Settings under cfg.v2.res. The engine's own bars and their code are
-- unchanged: these hang off the v2 hooks (each calls the one before it),
-- run on the 0.2 s tick and the 0.1 s text tick, and the one event they
-- add stores what it carries. Nothing compared on a hidden value.
-- Part of ZacUI; load order is set by the TOC (after HUD_V2_BuffBars).

local ns = _G.ZacUI
if not ns or not ns.HUD or not ns.HUD.V2 then return end
local HUD = ns.HUD
local V2 = HUD.V2
local Engine = HUD.ClassEngine

local GetTime = GetTime
local HUD_STRATA = "MEDIUM"
local QUEUED_COL = { r = 1, g = 0.55, b = 0.1, a = 1 }
V2.RANGE_ALPHA_DEFAULT = 0.35
local TICK = 2

local function Res(cfg, create) return V2.Sub(cfg, "res", create) end
V2.ResCfg = Res

local function Hidden(v) return ns.IsSecret(v) end

-- ------------------------------------------------------------
-- what applies here
-- ------------------------------------------------------------
function Engine:V2HasNextSwing()
    for _, list in ipairs({ self.def.grid or {}, self.def.utility or {} }) do
        for _, e in ipairs(list) do if e.nextSwing then return true end end
    end
    return false
end

function V2.SwingRangeAvailable()
    return (_G.ZACUI_IS_FOREVER and C_SwingTimer and C_SwingTimer.EnableRangeCheck) and true or false
end

function Engine:V2ResApplies()
    local b = self.bars
    return {
        regen = b.mana and b.fsr and true or false,
        queued = b.swing and self:V2HasNextSwing() or false,
        range = (b.swing or b.ranged) and V2.SwingRangeAvailable() or false,
        druidMana = (self.def.class == "DRUID" and b.power and b.mana) and true or false,
    }
end

-- the extras in force: your switch, else the spec's (HUD_V2_Specs);
-- the colour / name / alpha options are yours. nil when none is on.
local SWITCHES = { "regen", "queued", "rangeDim", "druidMana" }
function Engine:V2ResEff(cfg)
    local r = Res(cfg)
    local eff = self._v2resEff
    if not eff then eff = {} self._v2resEff = eff end
    local any = false
    for _, k in ipairs(SWITCHES) do
        local v
        if self.V2ResValue then v = self:V2ResValue(cfg, k) else v = r and r[k] end
        eff[k] = v and true or false
        if v then any = true end
    end
    eff.queuedColor = r and r.queuedColor
    eff.noQueuedName = r and r.noQueuedName
    eff.rangeAlpha = r and r.rangeAlpha
    return any and eff or nil
end

function Engine:V2ResWantsQueue(cfg)
    local r = self:V2ResEff(cfg)
    return (r and r.queued and self.bars.swing and self:V2HasNextSwing()) and true or false
end

-- ------------------------------------------------------------
-- regen ticks (0.2 s tick)
-- ------------------------------------------------------------
-- at full mana nothing ticks; a hidden reading is "not full" in a fight
local function ManaFull(eng)
    if eng.sample then return false end
    local cur, max = UnitPower("player", 0), UnitPowerMax("player", 0)
    if Hidden(cur) or Hidden(max) or type(cur) ~= "number" or type(max) ~= "number" then
        return not eng.S.inCombat
    end
    return max > 0 and cur >= max
end

function Engine:V2RegenTicks(r)
    local bar = self.fsrBar
    if not bar then return end
    local S = self.S
    local fsr = S.fsr
    local on = r and r.regen and true or false
    if on then
        local now = GetTime()
        local ends = (fsr.start or 0) + (fsr.duration or 0)
        -- the window (or the last sweep) over: the next 2 s sweep starts
        -- where it ended (a gap of more than one tick: from now)
        if (fsr.duration or 0) > 0 and now >= ends and (S.powerType or 0) == 0 and not ManaFull(self) then
            local start = ends
            if now - ends > TICK then start = now end
            fsr.start, fsr.duration = start, TICK
        end
        -- the five-second window red, the ticks in the tick colour
        local c = self:Col((fsr.duration or 0) > TICK + 0.01 and "fsr" or "tick")
        if bar._v2col ~= c then
            bar._v2col = c
            bar:SetBarColor(c[1], c[2], c[3], c[4])
        end
    elseif bar._v2col then
        bar._v2col = nil
        local c = self:Col("fsr")
        bar:SetBarColor(c[1], c[2], c[3], c[4])
    end
end

-- ------------------------------------------------------------
-- the queued attack on the swing bar
-- ------------------------------------------------------------
function Engine:V2QueuedSwing(r)
    local bar = self.swingBar
    if not bar then return end
    local S = self.S
    local name
    if r and r.queued and S.queued then
        for _, list in ipairs({ self.def.grid or {}, self.def.utility or {} }) do
            for _, e in ipairs(list) do
                local sp = e.nextSwing and e.spell and S.spells[e.spell]
                if sp and sp.name and S.queued[sp.name] then name = sp.name break end
            end
            if name then break end
        end
    end
    if name then
        local cr, cg, cb, ca = HUD.Col(r.queuedColor, QUEUED_COL)
        -- every tick (the bar skips a colour it has): a colour change on
        -- the Look tab repaints the bar its own colour in between
        bar._v2q = name
        bar:SetBarColor(cr, cg, cb, ca)
        if not r.noQueuedName then
            local fs = bar._v2qText
            if not fs then
                fs = HUD.Text(bar.bar, 10, "OUTLINE", "OVERLAY", "text")
                fs:SetPoint("BOTTOM", bar, "TOP", 0, 2)
                bar._v2qText = fs
            end
            if fs._name ~= name then fs._name = name fs:SetText(name) end
            fs:SetTextColor(cr, cg, cb, 1)
            fs:Show()
        elseif bar._v2qText then
            bar._v2qText:Hide()
        end
    elseif bar._v2q then
        bar._v2q = nil
        local c = self:Col("swing")
        bar:SetBarColor(c[1], c[2], c[3], c[4])
        if bar._v2qText then bar._v2qText:Hide() end
    end
end

-- ------------------------------------------------------------
-- WoW Forever: the swing range check
-- ------------------------------------------------------------
local function SwingTypes()
    local E = Enum and Enum.PlayerSwingType
    return (E and E.MainHand) or 0, (E and E.Ranged) or 2
end

function Engine:V2WatchRange(on)
    if self.sample or on == (self._v2rangeOn or false) then return end
    if on and not V2.SwingRangeAvailable() then return end
    self._v2rangeOn = on
    local ev = self.ev
    local mh, rg = SwingTypes()
    if on then
        local valid = C_EventUtils and C_EventUtils.IsEventValid
        if valid and not valid("PLAYER_SWING_RANGE_UPDATE") then self._v2rangeOn = false return end
        pcall(ev.RegisterEvent, ev, "PLAYER_SWING_RANGE_UPDATE")
        if self.bars.swing then pcall(C_SwingTimer.EnableRangeCheck, mh, true) end
        if self.bars.ranged then pcall(C_SwingTimer.EnableRangeCheck, rg, true) end
        self.S.swingOOR = self.S.swingOOR or {}
    else
        ev:UnregisterEvent("PLAYER_SWING_RANGE_UPDATE")
        if C_SwingTimer and C_SwingTimer.EnableRangeCheck then
            if self.bars.swing then pcall(C_SwingTimer.EnableRangeCheck, mh, false) end
            if self.bars.ranged then pcall(C_SwingTimer.EnableRangeCheck, rg, false) end
        end
        self.S.swingOOR = nil
    end
end

-- (swingType, isInRange, checksRange): stored as it comes, a hidden
-- answer keeps the last one
function Engine:V2RangeEvent(swingType, inRange, checks)
    local oor = self.S.swingOOR
    if not oor or Hidden(swingType) or Hidden(inRange) or Hidden(checks) then return end
    local mh, rg = SwingTypes()
    local hand = (swingType == rg) and "ranged" or (swingType == mh) and "mh" or nil
    if not hand then return end
    if checks == false then oor[hand] = nil else oor[hand] = (inRange == false) or nil end
end

function Engine:V2RangeDim(r)
    local on = r and r.rangeDim and true or false
    if not self.sample then self:V2WatchRange(on and V2.SwingRangeAvailable()) end
    local oor = self.S.swingOOR
    local a = (r and tonumber(r.rangeAlpha)) or V2.RANGE_ALPHA_DEFAULT
    for _, pair in ipairs({ { self.swingBar, "mh" }, { self.rangedBar, "ranged" } }) do
        local bar, hand = pair[1], pair[2]
        if bar then
            local want = (on and oor and oor[hand]) and a or 1
            if bar._v2alpha ~= want then
                bar._v2alpha = want
                bar:SetAlpha(want)
            end
        end
    end
end

-- ------------------------------------------------------------
-- druid mana while shifted
-- ------------------------------------------------------------
function Engine:V2DruidMana(r, cfg)
    local on = r and r.druidMana and self.bars.power and self.def.class == "DRUID"
    local bar = self.v2manaBar
    if not on then
        if bar then bar:Hide() end
        return
    end
    local S = self.S
    if not bar then
        local pos = cfg.resources.pos.power
        bar = self.W.CreateBar(self.anchors.Power, { width = pos.w or 234, height = 3, barColor = self:Col("mana") })
        bar:SetFrameStrata(HUD_STRATA)
        bar:SetPoint("TOP", self.tickBar or self.powerBar, "BOTTOM", 0, -1)
        bar:Hide()
        self.v2manaBar = bar
    end
    local w = cfg.resources.pos.power.w or 234
    if bar._v2w ~= w then bar._v2w = w bar:SetWidth(w) end
    local c = self:Col("mana")
    if bar._v2c ~= c then bar._v2c = c bar:SetBarColor(c[1], c[2], c[3], c[4]) end
    local shifted = (S.powerType or 0) ~= 0
    local show = self:On(cfg) and (shifted or self.preview) and true or false
    bar:SetShown(show)
    if not show then return end
    local cur, max
    if self.sample then
        cur, max = S.mana or 0, S.manaMax or 1
    else
        cur, max = UnitPower("player", 0), UnitPowerMax("player", 0)
    end
    if Hidden(cur) or Hidden(max) then
        -- the bar takes the hidden values as they are
        bar._v2plain = nil
        ns.ShowBar(bar.bar, cur, max)
    else
        cur, max = tonumber(cur) or 0, tonumber(max) or 0
        bar.bar:SetMinMaxValues(0, 1)
        bar.bar:SetValue(max > 0 and cur / max or 0)
    end
end

-- ------------------------------------------------------------
-- onto the earlier hooks
-- ------------------------------------------------------------
local Base = {}
for _, n in ipairs({ "V2Refresh", "V2HideAll", "V2Event", "V2FillSample", "V2Tab_General" }) do Base[n] = Engine[n] end

function Engine:V2Refresh(cfg)
    if Base.V2Refresh then Base.V2Refresh(self, cfg) end
    if not self.built then return end
    local r = self:V2ResEff(cfg)
    if not (r or self._v2resOn) then return end
    self._v2resOn = r and true or nil
    if not self.sample and self.V2WatchQueue then self:V2WatchQueue(self:V2QueueWanted(cfg)) end
    self:V2RegenTicks(r)
    self:V2QueuedSwing(r)
    self:V2RangeDim(r)
    self:V2DruidMana(r, cfg)
end

function Engine:V2HideAll()
    if Base.V2HideAll then Base.V2HideAll(self) end
    if self.v2manaBar then self.v2manaBar:Hide() end
    if self.swingBar and self.swingBar._v2qText then self.swingBar._v2qText:Hide() end
end

function Engine:V2Event(event, a1, a2, a3)
    if event == "PLAYER_SWING_RANGE_UPDATE" then return self:V2RangeEvent(a1, a2, a3) end
    if Base.V2Event then return Base.V2Event(self, event, a1, a2, a3) end
end

-- the preview: an attack queued and the swing out of reach in a fight
-- (when those are on), the druid in cat form with its mana
function Engine:V2FillSample(mode, combat)
    if Base.V2FillSample then Base.V2FillSample(self, mode, combat) end
    local cfg = self:Store()
    local r = cfg and self:V2ResEff(cfg)
    if not r then return end
    local S = self.S
    if r.queued and combat then
        S.queued = S.queued or {}
        wipe(S.queued)
        for _, list in ipairs({ self.def.grid or {}, self.def.utility or {} }) do
            for _, e in ipairs(list) do
                local sp = e.nextSwing and e.spell and S.spells[e.spell]
                if sp and sp.name then S.queued[sp.name] = true end
            end
        end
    elseif S.queued then
        wipe(S.queued)
    end
    if r.rangeDim then S.swingOOR = combat and { mh = true } or {} end
    if r.druidMana and combat then S.powerType = 3 end
end

-- ------------------------------------------------------------
-- the page: one card on General with what applies here
-- ------------------------------------------------------------
local Check = HUD.CheckIndent

function Engine:V2Tab_General(L, cfg)
    if Base.V2Tab_General then Base.V2Tab_General(self, L, cfg) end
    local ap = self:V2ResApplies()
    if not (ap.regen or ap.queued or ap.range or ap.druidMana) then return end
    local eng = self
    local r = Res(cfg)
    -- a switch shows what is in force (yours, else the spec's); a click
    -- is yours for good (true / false), the other options nil when default
    local function On(key)
        if eng.V2ResValue then return eng:V2ResValue(cfg, key) and true or false end
        return r and r[key] and true or false
    end
    local function Set(key, v)
        Res(cfg, true)[key] = v
        V2.Tidy(cfg)
        eng:Refresh()
    end
    local function Switch(key, v) Set(key, v and true or false) end
    L:Card("Resource bar extras")
    if ap.regen then
        Check(L, "Regen ticks after the five-second rule", On("regen"), function(v) Switch("regen", v) end,
            nil, "The bar under the mana bar keeps sweeping every 2 s once the five seconds are up: each sweep is a spirit tick.")
    end
    if ap.queued then
        Check(L, "Colour the swing bar while an attack is queued", On("queued"), function(v)
            Switch("queued", v)
            HUD.RefreshPage()
        end, nil, "Raptor Strike or Maul waiting for your next swing.")
        if On("queued") then
            Check(L, "With the attack's name", not (r and r.noQueuedName), function(v) Set("noQueuedName", (not v) or nil) end, 16)
            HUD.ColorGrid(L, { { "Queued colour",
                get = function() return HUD.Col(r and r.queuedColor, QUEUED_COL) end,
                set = function(cr, cg, cb, ca) Set("queuedColor", { r = cr, g = cg, b = cb, a = ca or 1 }) end } })
        end
    end
    if ap.range then
        Check(L, "Dim the swing bar while out of range", On("rangeDim"), function(v)
            Switch("rangeDim", v)
            HUD.RefreshPage()
        end, nil, "The game's own swing range check (WoW Forever).")
        if On("rangeDim") then
            HUD.Slider(L, "Dimmed to", 0, 90, math.floor(((tonumber(r and r.rangeAlpha) or V2.RANGE_ALPHA_DEFAULT) * 100) + 0.5), function(v)
                local a = v / 100
                Set("rangeAlpha", (math.abs(a - V2.RANGE_ALPHA_DEFAULT) > 0.001) and a or nil)
            end, { width = 240, format = function(v) return v .. "%" end })
        end
    end
    if ap.druidMana then
        Check(L, "Mana bar while shapeshifted", On("druidMana"), function(v) Switch("druidMana", v) end,
            nil, "A thin mana bar under the energy / rage bar in Cat and Bear Form.")
    end
    L:EndCard()
end
