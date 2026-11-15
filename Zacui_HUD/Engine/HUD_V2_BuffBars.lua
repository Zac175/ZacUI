-- HUD_V2_BuffBars - Class HUD v2: tracked buff bars. Your own buffs (and
-- your own debuffs on the target) as a stack of bars: icon, name, time
-- left and stacks, the fill draining with the time left. The class
-- definition seeds the list (def.buffBars: buff row keys); you tick any
-- buff or debuff row entry on or off. Off until turned on; its spot is a
-- mover of its own ("Buff bars").
-- Classic Era / TBC: each bar fills from the aura's end time on the HUD's
-- 0.1 s text tick. WoW Forever: an aura whose time the game hides runs on
-- the game's own clock (its duration object on the bar, HUD.TimedSwing),
-- its time and stacks go straight to the texts (ns.ShowText /
-- ShowAuraCount); a buff the game will not even name in combat is asked
-- for by spell id (C_UnitAuras.GetPlayerAuraBySpellID), and when that
-- answers nothing in a fight the bar keeps the state it had. Nothing is
-- compared on a hidden value.
-- Hooks onto the Rows / Page hooks (each calls the one before it); with
-- the bars off they do nothing.
-- Part of ZacUI; load order is set by the TOC (after HUD_V2_Page).

local ns = _G.ZacUI
if not ns or not ns.HUD or not ns.HUD.V2 then return end
local HUD = ns.HUD
local V2 = HUD.V2
local Engine = HUD.ClassEngine

local GetTime = GetTime
local HUD_STRATA = "MEDIUM"
local BARS_POS = { x = 0, y = -290 }   -- where the mover starts (never written)
local BUFF_COL = { r = 0.95, g = 0.75, b = 0.2, a = 1 }
local DEBUFF_COL = { r = 0.85, g = 0.25, b = 0.25, a = 1 }
V2.BAR_DEFAULTS = { width = 180, height = 16, spacing = 2, textSize = 10 }
V2.BAR_TIME_DEFAULTS = { time = "short", timeDecimalsUnder = 0 }
local D = V2.BAR_DEFAULTS

-- cfg.v2.buffBars, nil until saved
local function BB(cfg, create) return V2.Sub(cfg, "buffBars", create) end
V2.BuffBarsCfg = BB
function V2.BuffBarsOn(cfg)
    local b = BB(cfg)
    return (b and b.enabled) and true or false
end

local function Num(b, key) return (b and tonumber(b[key])) or D[key] end

-- ------------------------------------------------------------
-- what is tracked
-- ------------------------------------------------------------
-- every entry a bar can track: the buff row's and the debuff row's
function Engine:V2BarCandidates()
    local out = {}
    for _, e in ipairs(self.def.buffRow or {}) do out[#out + 1] = { gk = "buffs:" .. e.key, row = "buffs", e = e } end
    for _, e in ipairs(self.def.debuffRow or {}) do out[#out + 1] = { gk = "debuffs:" .. e.key, row = "debuffs", e = e } end
    return out
end

-- the class's seeds, as rule keys
function Engine:V2BarSeeds()
    local s = self._v2barSeeds
    if s then return s end
    s = {}
    local inRow = {}
    for _, e in ipairs(self.def.buffRow or {}) do inRow[e.key] = true end
    for _, k in ipairs(self.def.buffBars or {}) do
        if inRow[k] then s[#s + 1] = "buffs:" .. k end
    end
    self._v2barSeeds = s
    return s
end

-- the tracked list: yours once you ticked one, else the seeds
function Engine:V2BarList(cfg)
    local b = BB(cfg)
    if b and type(b.list) == "table" then return b.list end
    return self:V2BarSeeds()
end

-- a tick on or off: the list kept in the candidates' order; a list that
-- is the seeds again is not kept
function Engine:V2BarSet(cfg, gk, on)
    local cur = {}
    for _, k in ipairs(self:V2BarList(cfg)) do cur[k] = true end
    cur[gk] = on or nil
    local list = {}
    for _, c in ipairs(self:V2BarCandidates()) do if cur[c.gk] then list[#list + 1] = c.gk end end
    local seeds = self:V2BarSeeds()
    local same = #list == #seeds
    if same then
        local inSeeds = {}
        for _, k in ipairs(seeds) do inSeeds[k] = true end
        for _, k in ipairs(list) do if not inSeeds[k] then same = false end end
    end
    BB(cfg, true).list = (not same) and list or nil
    V2.Tidy(cfg)
end

local function EntryOf(eng, gk)
    local row, key = gk:match("^(%a+):(.+)$")
    local list = row == "buffs" and eng.def.buffRow or row == "debuffs" and eng.def.debuffRow or nil
    for _, e in ipairs(list or {}) do if e.key == key then return row, e end end
    return nil
end

-- a bar's colour: the row's, the class's or your own
function V2.BarColor(eng, cfg, gk, row)
    local b = BB(cfg)
    local c = b and type(b.colors) == "table" and b.colors[gk]
    local mode = type(c) == "table" and c.mode or nil
    if mode == "class" and ns.ClassColor then
        local _, cls = UnitClass("player")
        local r, g, bl = ns.ClassColor(cls)
        if type(r) == "number" then return r, g, bl, 1 end
    elseif mode == "custom" and type(c.color) == "table" then
        return HUD.Col(c.color, BUFF_COL)
    end
    return HUD.Col(nil, row == "debuffs" and DEBUFF_COL or BUFF_COL)
end

-- ------------------------------------------------------------
-- the anchor, the bars
-- ------------------------------------------------------------
function Engine:V2EnsureBars()
    if self.sample or self.anchors.BuffBars or not self.S.isClass then return end
    local cfg = self:Store()
    if not cfg then return end
    local b = BB(cfg)
    self:MakeAnchor("BuffBars", Num(b, "width"), Num(b, "height"))
    local key = self.def.prefix .. "BuffBars"
    HUD.PlaceAnchor(key, self.holders.BuffBars, BARS_POS)
    HUD.RegisterMover(key, self.def.label .. " Buff bars", self.holders.BuffBars, BARS_POS)
    self.v2bars = self.v2bars or {}
end

-- the bar's icon crop: ZacUI's look crop (ns.Look.CropIcon) where it
-- crops at least as far as the bar's own 8%, else the bar's own; at
-- creation and when the size changes only
local OWN_CROP = 0.08
local function CropIcon(ic, size)
    local L = ns.Look
    local c = L and L.CropIcon and L.IconCrop and L.IconCrop("hud")
    if type(c) == "number" and c > 0 and c + 0.0001 >= OWN_CROP then
        L.CropIcon(ic, size, size, { border = false, part = "hud", minCrop = OWN_CROP })
        return
    end
    if L and L.ForgetIcon then L.ForgetIcon(ic) end
    ic:SetTexCoord(OWN_CROP, 1 - OWN_CROP, OWN_CROP, 1 - OWN_CROP)
end

local function MakeBar(eng, anchor, b)
    local W = eng.W
    local w, h = Num(b, "width"), Num(b, "height")
    local f = W.CreateBar(anchor, { width = w, height = h })
    f:SetFrameStrata(HUD_STRATA)
    local ic = f:CreateTexture(nil, "ARTWORK")
    ic:SetSize(h, h)
    ic:SetPoint("RIGHT", f, "LEFT", -2, 0)
    CropIcon(ic, h)
    f.iconTex = ic
    local size = Num(b, "textSize")
    local name = HUD.Text(f.bar, size, "OUTLINE", "OVERLAY", "text")
    name:SetPoint("LEFT", f, "LEFT", 4, 0)
    name:SetJustifyH("LEFT")
    f.nameFS = name
    local tm = HUD.Text(f.bar, size, "OUTLINE", "OVERLAY", "text")
    tm:SetPoint("RIGHT", f, "RIGHT", -4, 0)
    tm:SetJustifyH("RIGHT")
    f.timeFS = tm
    local st = HUD.Text(f.bar, size, "OUTLINE", "OVERLAY", "text")
    st:SetPoint("RIGHT", tm, "LEFT", -4, 0)
    f.stackFS = st
    f._v2size, f._v2w, f._v2h = size, w, h
    f:Hide()
    return f
end

-- the size settings onto a bar made before they changed
local function Fit(f, b)
    local w, h, size = Num(b, "width"), Num(b, "height"), Num(b, "textSize")
    if f._v2w ~= w or f._v2h ~= h then
        f._v2w, f._v2h = w, h
        f:SetSize(w, h)
        f.iconTex:SetSize(h, h)
        CropIcon(f.iconTex, h)
    end
    if f._v2size ~= size then
        f._v2size = size
        HUD.ApplyFont(f.nameFS, size, "OUTLINE", "text")
        HUD.ApplyFont(f.timeFS, size, "OUTLINE", "text")
        HUD.ApplyFont(f.stackFS, size, "OUTLINE", "text")
    end
end

-- ------------------------------------------------------------
-- the read: what each bar shows (0.2 s tick)
-- ------------------------------------------------------------
-- WoW Forever: a buff the plain read left out (its very name hidden in
-- a fight), asked for by the entry's spell id
local function HiddenBuff(e)
    if not (ns.ModernClient and ns.ModernClient() and type(e.id) == "number") then return nil end
    local UA = C_UnitAuras
    local get = UA and UA.GetPlayerAuraBySpellID
    if not get then return nil end
    local ok, a = pcall(get, e.id)
    if ok and type(a) == "table" then return a end
    return nil
end

local function SetName(f, text)
    if f._v2name ~= text then
        f._v2name = text
        f.nameFS:SetText(text or "")
    end
end

-- one bar from a plain aura: icon, name, stacks; the fill and the time
-- follow on the text tick
local function ShowPlain(f, a, name, now)
    if f._zTimed then HUD.UntimedSwing(f) end
    f._v2mode = "plain"
    f._v2exp, f._v2dur = a.expirationTime or 0, a.duration or 0
    if a.icon then f.iconTex:SetTexture(a.icon) end
    SetName(f, name)
    local n = a.count
    f.stackFS:SetText((type(n) == "number" and n > 1) and tostring(n) or "")
    if f._v2dur <= 0 then
        f.bar:SetMinMaxValues(0, 1)
        f.bar:SetValue(1)
        f.timeFS:SetText("")
    end
end

-- one bar from a hidden aura (the game's table): the game's clock drives it
local function ShowHidden(f, unit, a, name)
    f._v2mode = "hidden"
    f._v2unit, f._v2aura = unit, a
    local dur = ns.AuraDuration(unit, a)
    if not (dur and HUD.TimedSwing(f, dur)) then
        if f._zTimed then HUD.UntimedSwing(f) end
        ns.ShowBar(f.bar, 1, 1)
    end
    if a.icon ~= nil then pcall(f.iconTex.SetTexture, f.iconTex, a.icon) end
    if name then SetName(f, name) elseif a.name ~= nil then
        f._v2name = nil
        if not ns.ShowText(f.nameFS, "%s", a.name) then f.nameFS:SetText("") end
    end
    if not ns.ShowAuraCount(f.stackFS, unit, a) then f.stackFS:SetText("") end
end

function Engine:V2RefreshBars(cfg)
    local b = BB(cfg)
    local on = b and b.enabled and self:On(cfg)
    local anchor = self.anchors.BuffBars
    if on and not anchor and self.sample and self.canvas then
        -- turned on while the preview's sample is up
        anchor = HUD.SampleAnchor(self.canvas, Num(b, "width"), Num(b, "height"))
        self.anchors.BuffBars, self.holders.BuffBars = anchor, anchor
    end
    if not anchor then return end
    local pool = self.v2bars or {}
    self.v2bars = pool
    local active = self.v2barActive or {}
    self.v2barActive = active
    wipe(active)
    if not on then
        for _, f in pairs(pool) do f:Hide() end
        return
    end
    local S = self.S
    local now = GetTime()
    local keepEmpty = b.keepEmpty and true or false
    local showIcon = b.noIcon ~= true
    for _, gk in ipairs(self:V2BarList(cfg)) do
        local row, e = EntryOf(self, gk)
        if e then
            local f = pool[gk]
            if not f then
                f = MakeBar(self, anchor, b)
                pool[gk] = f
            end
            f._v2gk = gk
            Fit(f, b)
            local name = S.auraNames[e.key]
            local lname = name and name:lower()
            local src = row == "buffs" and S.buffs or S.targetDebuffs
            local a = lname and src[lname] or nil
            local up = false
            if a and a.hidden then
                ShowHidden(f, "target", a.hidden, name)
                up = true
            elseif a then
                ShowPlain(f, a, name, now)
                up = true
            elseif row == "buffs" and not self.sample then
                local ha = HiddenBuff(e)
                if ha then
                    ShowHidden(f, "player", ha, name)
                    up = true
                elseif f._v2mode == "hidden" and S.inCombat then
                    -- the game answers nothing in a fight: the bar keeps
                    -- the state it had (its own clock drains it)
                    up = true
                end
            end
            if not up then
                f._v2mode = nil
                if f._zTimed then HUD.UntimedSwing(f) end
                f.iconTex:SetTexture(S.auraIcons[e.key] or 134400)
                SetName(f, name or e.label or e.key)
                f.bar:SetMinMaxValues(0, 1)
                f.bar:SetValue(0)
                f.timeFS:SetText("")
                f.stackFS:SetText("")
            end
            f.iconTex:SetShown(showIcon)
            f:SetBarColor(V2.BarColor(self, cfg, gk, row))
            local tc = self:Col("barText")
            if f._v2tc ~= tc then
                f._v2tc = tc
                for _, fs in ipairs({ f.nameFS, f.timeFS, f.stackFS }) do fs:SetTextColor(tc[1], tc[2], tc[3], tc[4]) end
            end
            local shown = up or keepEmpty
            f:SetShown(shown)
            if shown then active[#active + 1] = f end
        end
    end
    -- bars of entries no longer tracked
    local tracked = {}
    for _, gk in ipairs(self:V2BarList(cfg)) do tracked[gk] = true end
    for gk, f in pairs(pool) do if not tracked[gk] then f:Hide() end end
    self:V2LayoutBars(b, anchor, active)
end

-- a stack down (or up) from the anchor's top (or bottom)
-- the bars in the order dragged in the preview (buffBars.order: their
-- keys; nil = the tracked list's order, the list untouched). Kept until
-- the bars or the saved order change: the refresh makes no garbage.
local function BarKey(f) return f and f._v2gk end
function Engine:V2BarsOrdered(b, active)
    local saved = b and b.order
    if type(saved) ~= "table" or #saved == 0 or not ns.OrderedList then
        self.v2barOrd = nil
        return active
    end
    local c = self.v2barOrd
    if c and c.saved == saved and c.n == #active then
        local same = true
        for i = 1, #active do if c.src[i] ~= active[i] then same = false break end end
        if same then return c.out end
    end
    c = c or { src = {} }
    self.v2barOrd = c
    c.saved, c.n = saved, #active
    for i = 1, #active do c.src[i] = active[i] end
    for i = #active + 1, #c.src do c.src[i] = nil end
    c.out = ns.OrderedList(active, saved, BarKey)
    return c.out
end

function Engine:V2LayoutBars(b, anchor, active)
    active = self:V2BarsOrdered(b, active)
    local w, h, space = Num(b, "width"), Num(b, "height"), Num(b, "spacing")
    local up = b.grow == "UP"
    local n = #active
    anchor:SetSize(w, math.max(h, n * h + math.max(0, n - 1) * space))
    for i, f in ipairs(active) do
        local off = (i - 1) * (h + space)
        f:ClearAllPoints()
        if up then
            f:SetPoint("BOTTOM", anchor, "BOTTOM", 0, off)
        else
            f:SetPoint("TOP", anchor, "TOP", 0, -off)
        end
    end
end

-- the fill and the time left of the plain bars (0.1 s text tick)
function Engine:V2BarsTextTick(cfg)
    local active = self.v2barActive
    if not (active and active[1]) then return end
    local now = GetTime()
    local fmt = cfg.formats and cfg.formats.buffBars
    local W = self.W
    for _, f in ipairs(active) do
        if f._v2mode == "plain" and (f._v2dur or 0) > 0 then
            local left = math.max(0, f._v2exp - now)
            f.bar:SetMinMaxValues(0, f._v2dur)
            f.bar:SetValue(left)
            f.timeFS:SetText(fmt and ns.FormatTime(left, fmt, V2.BAR_TIME_DEFAULTS) or W.FormatTime(left, 0))
        elseif f._v2mode == "hidden" then
            local left = ns.AuraTimeLeft and ns.AuraTimeLeft(f._v2unit, f._v2aura)
            if left == nil or not ns.ShowText(f.timeFS, "%.0f", left) then f.timeFS:SetText("") end
        end
    end
end

-- ------------------------------------------------------------
-- onto the earlier hooks (each calls the one before it)
-- ------------------------------------------------------------
local Base = {}
for _, n in ipairs({ "V2Elements", "V2Refresh", "V2HideAll", "V2Positions", "V2SampleOn", "V2TextTick",
    "V2Login", "V2FillSample", "V2Tab_General", "V2Tab_Look", "V2Tab_Text", "V2Tab_PositionCard" }) do
    Base[n] = Engine[n]
end

function Engine:V2Elements(list)
    if Base.V2Elements then Base.V2Elements(self, list) end
    local cfg = self:Store()
    if not (cfg and V2.BuffBarsOn(cfg)) then return end
    if not self.sample and not self.anchors.BuffBars then return end
    list[#list + 1] = { key = "BuffBars", mover = self.def.prefix .. "BuffBars", label = "Buff bars",
        cfg = function(c) local b = BB(c) return (b and (b.x or b.y)) and b or BARS_POS end }
end

function Engine:V2Login(cfg)
    if Base.V2Login then Base.V2Login(self, cfg) end
    if cfg and V2.BuffBarsOn(cfg) then self:V2EnsureBars() end
end

function Engine:V2Refresh(cfg)
    if Base.V2Refresh then Base.V2Refresh(self, cfg) end
    if self.v2bars or V2.BuffBarsOn(cfg) then self:V2RefreshBars(cfg) end
end

function Engine:V2HideAll()
    if Base.V2HideAll then Base.V2HideAll(self) end
    for _, f in pairs(self.v2bars or {}) do f:Hide() end
    if self.v2barActive then wipe(self.v2barActive) end
end

function Engine:V2Positions(cfg)
    if Base.V2Positions then Base.V2Positions(self, cfg) end
    local a = self.anchors.BuffBars
    if a then
        local b = BB(cfg)
        a:SetScale((b and b.scale) or 1)
    end
end

function Engine:V2SampleOn(on, scale, cfg)
    if Base.V2SampleOn then Base.V2SampleOn(self, on, scale, cfg) end
    local b = BB(cfg)
    on.BuffBars = V2.BuffBarsOn(cfg)
    scale.BuffBars = (b and b.scale) or 1
end

function Engine:V2TextTick()
    if Base.V2TextTick then Base.V2TextTick(self) end
    if self.v2barActive and self.v2barActive[1] then
        local cfg = self:Store()
        if cfg then self:V2BarsTextTick(cfg) end
    end
end

-- the preview: every tracked bar up with a timer (stacks on the second)
function Engine:V2FillSample(mode, combat)
    if Base.V2FillSample then Base.V2FillSample(self, mode, combat) end
    local cfg = self:Store()
    if not (cfg and V2.BuffBarsOn(cfg)) then return end
    local S = self.S
    local now = GetTime()
    for i, gk in ipairs(self:V2BarList(cfg)) do
        local row, e = EntryOf(self, gk)
        local name = e and S.auraNames[e.key]
        if name then
            local src = row == "buffs" and S.buffs or S.targetDebuffs
            local l = name:lower()
            if not src[l] then
                local dur = combat and 20 or 600
                src[l] = { name = name, icon = S.auraIcons[e.key], count = (i == 2) and 3 or 0,
                    duration = dur, expirationTime = now + dur - 3 * i }
            end
        end
    end
end

-- ------------------------------------------------------------
-- the page: General (the list), Look (sizes, colours), Text (time
-- format), Position (scale)
-- ------------------------------------------------------------
local Check = HUD.CheckIndent
local function Px(v) return v .. " px" end

function Engine:V2Tab_General(L, cfg)
    if Base.V2Tab_General then Base.V2Tab_General(self, L, cfg) end
    local eng = self
    local cands = self:V2BarCandidates()
    if #cands == 0 then return end
    L:Card("Buff bars")
    L:Desc("Your own buffs and your debuffs on the target as bars with the time left. Their spot is under Position once they are on.")
    Check(L, "Show buff bars", V2.BuffBarsOn(cfg), function(v)
        BB(cfg, true).enabled = v or nil
        V2.Tidy(cfg)
        if v then eng:V2EnsureBars() end
        eng:Refresh()
        HUD.RefreshPage()
    end)
    if V2.BuffBarsOn(cfg) then
        local cur = {}
        for _, k in ipairs(self:V2BarList(cfg)) do cur[k] = true end
        HUD.CheckGrid(L, cands,
            function(c) return (c.row == "debuffs" and "Debuff: " or "") .. (c.e.label or eng.S.auraNames[c.e.key] or c.e.key) end,
            function(c) return cur[c.gk] end,
            function(c, v)
                eng:V2BarSet(cfg, c.gk, v)
                eng:Refresh()
            end)
        local b = BB(cfg)
        Check(L, "Keep a bar when its buff is down", b and b.keepEmpty or false, function(v)
            BB(cfg, true).keepEmpty = v or nil
            V2.Tidy(cfg)
            eng:Refresh()
        end, nil, "An empty bar holds its place, so the others never shift.")
    end
    L:EndCard()
end

function Engine:V2Tab_Look(L, cfg)
    if Base.V2Tab_Look then Base.V2Tab_Look(self, L, cfg) end
    if not V2.BuffBarsOn(cfg) then return end
    local eng = self
    local b = BB(cfg)
    local function Set(key, def)
        return function(v)
            BB(cfg, true)[key] = (v ~= def) and v or nil
            V2.Tidy(cfg)
            eng:Refresh()
        end
    end
    L:Card("Buff bars")
    HUD.SliderPair(L,
        { "Bar width", 80, 400, Num(b, "width"), Set("width", D.width), Px },
        { "Bar height", 6, 40, Num(b, "height"), Set("height", D.height), Px })
    HUD.SliderPair(L,
        { "Bar spacing", 0, 12, Num(b, "spacing"), Set("spacing", D.spacing), Px },
        { "Bar text size", 6, 20, Num(b, "textSize"), Set("textSize", D.textSize), Px })
    local grows = { { value = "DOWN", text = "New bars below" }, { value = "UP", text = "New bars above" } }
    HUD.Dropdown(L, 220, grows, function()
        local g = b and b.grow or "DOWN"
        for _, it in ipairs(grows) do if it.value == g then return it.text end end
        return grows[1].text
    end, function(v)
        BB(cfg, true).grow = (v ~= "DOWN") and v or nil
        V2.Tidy(cfg)
        eng:Refresh()
    end)
    Check(L, "Show the icon", not (b and b.noIcon), function(v)
        BB(cfg, true).noIcon = (not v) or nil
        V2.Tidy(cfg)
        eng:Refresh()
    end)
    -- a colour per bar: pick the bar, then its colour
    local items = {}
    for _, gk in ipairs(self:V2BarList(cfg)) do
        local row, e = EntryOf(self, gk)
        if e then items[#items + 1] = { value = gk, text = (row == "debuffs" and "Debuff: " or "") .. (e.label or eng.S.auraNames[e.key] or e.key) } end
    end
    if #items > 0 then
        ZacUIDB.config = ZacUIDB.config or {}
        local mem = ZacUIDB.config
        local pick = mem.hudV2BarColor
        local okPick = false
        for _, it in ipairs(items) do if it.value == pick then okPick = true end end
        if not okPick then pick = items[1].value mem.hudV2BarColor = nil end
        HUD.Dropdown(L, 220, items, function()
            for _, it in ipairs(items) do if it.value == pick then return it.text end end
            return items[1].text
        end, function(v) mem.hudV2BarColor = v HUD.RefreshPage() end)
        local c = b and type(b.colors) == "table" and b.colors[pick] or nil
        local modes = { { value = "default", text = "The HUD's bar colour" }, { value = "class", text = "Class colour" },
            { value = "custom", text = "A colour of mine" } }
        HUD.Dropdown(L, 220, modes, function()
            local m = (c and c.mode) or "default"
            for _, it in ipairs(modes) do if it.value == m then return it.text end end
            return modes[1].text
        end, function(v)
            local t = BB(cfg, true)
            t.colors = type(t.colors) == "table" and t.colors or {}
            if v == "default" then t.colors[pick] = nil else
                t.colors[pick] = t.colors[pick] or {}
                t.colors[pick].mode = v
            end
            if next(t.colors) == nil then t.colors = nil end
            V2.Tidy(cfg)
            eng:Refresh()
            HUD.RefreshPage()
        end)
        if c and c.mode == "custom" then
            HUD.ColorGrid(L, { { "Bar colour",
                get = function() return HUD.Col(c.color, BUFF_COL) end,
                set = function(r, g, bl, a) c.color = { r = r, g = g, b = bl, a = a or 1 } eng:Refresh() end } })
        end
    end
    L:EndCard()
end

function Engine:V2Tab_Text(L, cfg)
    if Base.V2Tab_Text then Base.V2Tab_Text(self, L, cfg) end
    if not V2.BuffBarsOn(cfg) then return end
    local eng = self
    L:Card("Buff bar time")
    local fg, fs = ns.CustomAccess(cfg, "formats", "buffBars", function() V2.Tidy(cfg) eng:Refresh() end)
    L:Add(ns.UI.TextFormatPicker(L.current, { width = ns.UI.CardInnerWidth(L), get = fg, set = fs,
        kinds = { time = true }, defaults = V2.BAR_TIME_DEFAULTS,
        sample = function(spec) return ns.FormatTime(83, spec, V2.BAR_TIME_DEFAULTS) .. "  /  " .. ns.FormatTime(7.4, spec, V2.BAR_TIME_DEFAULTS) end }), 6)
    L:Desc("How the time left on a buff bar reads; nothing saved reads as the HUD's other timers.")
    L:EndCard()
end

function Engine:V2Tab_PositionCard(L, cfg)
    if Base.V2Tab_PositionCard then Base.V2Tab_PositionCard(self, L, cfg) end
    if V2.BuffBarsOn(cfg) then
        local eng = self
        HUD.ScaleSlider(L, "Buff bars scale", BB(cfg, true), "scale", function() eng:ApplyAnchorPositions() end)
    end
end
