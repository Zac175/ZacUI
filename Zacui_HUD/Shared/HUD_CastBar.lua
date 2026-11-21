-- HUD_CastBar - a cast bar for a class HUD (2026-11-18): your own casts
-- and channels as a bar that sits with the HUD, with the spell's icon and
-- name, the time left, a mark for each tick of a channelled spell and the
-- latency of the cast. One object per HUD (HUD.CastBar.New); the HUD owns
-- the anchor, the mover and the settings table, and calls Update on its
-- own tick. Off until its HUD turns it on.
--   what it reads   UnitCastingInfo / UnitChannelInfo for "player", once
--                   per cast event (start, delay, stop, failed,
--                   interrupted and the channel's three); nothing while
--                   you are not casting. The fill and the time text run
--                   on the bar's own OnUpdate only while a cast shows.
--   channel ticks   Classic Era and The Burning Crusade only, for the
--                   channelled spells in CHANNELS below: either a tick
--                   count the spell always has, or the seconds between
--                   two ticks where the length differs by rank or game
--                   version (the count then comes from the channel's own
--                   length, with spell haste taken back out). A tick sits
--                   at the moment it lands: time lost to a hit moves the
--                   marks, and a tick that will not land any more goes.
--   latency         the time from your key press reaching the game
--                   (UNIT_SPELLCAST_SENT) to the cast starting, as a
--                   block at the end the bar runs towards: the game has
--                   the cast finished there already.
--   hidden values   WoW Forever and Retail can hide a cast in a fight:
--                   the game's own duration object then drives the fill
--                   (ns.CastDuration / ns.ShowCastTimer), the name and
--                   icon go on as they are, and there is no time text,
--                   tick or latency (nothing is compared or counted with).
-- Settings (the HUD's table): enabled, w, h, noIcon, noName, noTime,
--           noTicks, noLag, color, chanColor, lagColor.
-- Part of ZacUI; load order is set by the TOC (after HUD_Shared).

local ns = _G.ZacUI
if not ns or not ns.HUD then return end
local HUD = ns.HUD
local CB = {}
HUD.CastBar = CB

local GetTime = GetTime
local WHITE = "Interface\\Buttons\\WHITE8X8"
local STRATA = "MEDIUM"
local QUESTION = 134400
CB.W, CB.H = 234, 14
CB.MIN_W, CB.MAX_W, CB.MIN_H, CB.MAX_H = 100, 500, 6, 30
local COL = {
    cast = { r = 1, g = 0.7, b = 0, a = 1 },
    channel = { r = 0.25, g = 0.78, b = 0.35, a = 1 },
    lag = { r = 0.85, g = 0.2, b = 0.2, a = 0.6 },
}
CB.COLORS = COL
local TICK_A = 0.7
local LAG_MAX = 1          -- a key press older than this is not this cast's
local GRACE = 0.4          -- a cast whose end event never came goes this long after its end
local ICON_GAP = 2
local EVENTS = { "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_STOP",
    "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP" }

-- tick marks only where this table is the game's (see the header)
CB.TICKS_HERE = not (_G.ZACUI_IS_FOREVER or _G.ZACUI_IS_RETAIL)
-- one id of each spell (for its name on this client), then n = the ticks
-- it always has, or every = seconds between two ticks
local CHANNELS = {
    { 5143,  every = 1 },   -- Arcane Missiles (3, 4 or 5 missiles by rank)
    { 10,    n = 8 },       -- Blizzard
    { 15407, n = 3 },       -- Mind Flay
    { 689,   n = 5 },       -- Drain Life
    { 5138,  n = 5 },       -- Drain Mana
    { 1120,  n = 5 },       -- Drain Soul
    { 755,   n = 10 },      -- Health Funnel
    { 5740,  n = 4 },       -- Rain of Fire
    { 1949,  n = 15 },      -- Hellfire
    { 16914, n = 10 },      -- Hurricane
    { 740,   every = 2 },   -- Tranquility (10 s in Classic Era, 8 s after)
    { 1510,  n = 6 },       -- Volley
}
CB.CHANNELS = CHANNELS

local function Secret(v) return ns.IsSecret ~= nil and ns.IsSecret(v) or false end
local function Plain(v)
    if v == nil or Secret(v) then return nil end
    return v
end
local function Widgets() return ns.WarriorHUD and ns.WarriorHUD.Widgets or nil end

local byName
local function ChannelData(name)
    if not (CB.TICKS_HERE and type(name) == "string") then return nil end
    if not byName then
        byName = {}
        for _, c in ipairs(CHANNELS) do
            local n = HUD.GetSpellInfo and HUD.GetSpellInfo(c[1])
            if type(n) == "string" then byName[n] = c end
        end
    end
    return byName[name]
end

-- how many times a channel of this length ticks
function CB.TickCount(data, dur)
    if data.n then return data.n end
    local haste = UnitSpellHaste and Plain(UnitSpellHaste("player")) or 0
    if type(haste) ~= "number" then haste = 0 end
    return math.floor(dur * (1 + haste / 100) / data.every + 0.5)
end

local function Size(s)
    local w = math.max(CB.MIN_W, math.min(CB.MAX_W, tonumber(s.w) or CB.W))
    local h = math.max(CB.MIN_H, math.min(CB.MAX_H, tonumber(s.h) or CB.H))
    return w, h
end
function CB.Size(s) return Size(s or {}) end

-- ------------------------------------------------------------
-- the object
-- ------------------------------------------------------------
local Bar = {}
Bar.__index = Bar
local EMPTY = {}

-- o.anchor     the frame it sits on (the HUD sizes and places it)
-- o.settings   function -> the settings table (nil = none saved)
-- o.sample     true on a settings preview: never reads a cast
-- o.sampleSpell function -> name, icon for the preview's made-up cast
function CB.New(o)
    return setmetatable({ anchor = o.anchor, settings = o.settings, sample = o.sample and true or false,
        sampleSpell = o.sampleSpell }, Bar)
end

function Bar:Build()
    if self.f then return self.f end
    local W = Widgets()
    if not (W and self.anchor) then return nil end
    local s = self.settings() or EMPTY
    local w, h = Size(s)
    local f = W.CreateBar(self.anchor, { width = w, height = h, barColor = { COL.cast.r, COL.cast.g, COL.cast.b, 1 } })
    f:SetFrameStrata(STRATA)
    f:Hide()
    local icon = W.CreateIcon(self.anchor, { width = h, height = h, zoom = W.ICON_ZOOM, noCooldown = true })
    icon:SetFrameStrata(STRATA)
    icon:SetPoint("LEFT", self.anchor, "LEFT", 0, 0)
    icon:Hide()
    f.icon = icon
    local time = HUD.Text(f.bar, 10, "OUTLINE", "OVERLAY", "text")
    time:SetPoint("RIGHT", f, "RIGHT", -4, 0)
    time:SetTextColor(1, 1, 1)
    f.time = time
    local name = HUD.Text(f.bar, 10, "OUTLINE", "OVERLAY", "text")
    name:SetPoint("LEFT", f, "LEFT", 4, 0)
    name:SetPoint("RIGHT", time, "LEFT", -4, 0)
    name:SetJustifyH("LEFT")
    if name.SetWordWrap then name:SetWordWrap(false) end
    name:SetTextColor(1, 1, 1)
    f.name = name
    -- over the fill and its sheen, under the texts
    local lag = f.bar:CreateTexture(nil, "ARTWORK", nil, 5)
    lag:SetTexture(WHITE)
    lag:Hide()
    f.lag = lag
    f.ticks = {}
    local bar = self
    f:SetScript("OnUpdate", function() bar:OnUpdate() end)
    self.f = f
    return f
end

-- sizes, parts and colours from the settings; laid out again only when
-- one of them changed
function Bar:Apply(s)
    local f = self.f
    if not f then return end
    s = s or EMPTY
    local w, h = Size(s)
    local showIcon = not s.noIcon
    local sig = w * 1000 + h + (showIcon and 0.5 or 0) + (s.noName and 0.25 or 0) + (s.noTime and 0.125 or 0)
    if f._sig ~= sig then
        f._sig = sig
        local bw = showIcon and (w - h - ICON_GAP) or w
        f:SetSize(bw, h)
        f:ClearAllPoints()
        f:SetPoint("RIGHT", self.anchor, "RIGHT", 0, 0)
        f.icon:SetSize(h, h)
        f.iconOn = showIcon
        if not showIcon then f.icon:Hide() elseif f:IsShown() then f.icon:Show() end
        local size = math.max(8, math.min(12, h - 4))
        HUD.ApplyFont(f.name, size, "OUTLINE", "text")
        HUD.ApplyFont(f.time, size, "OUTLINE", "text")
        f.nameOn, f.timeOn = not s.noName, not s.noTime
        f.name:SetShown(f.nameOn)
        f.time:SetShown(f.timeOn)
        if not f.timeOn then f.time:SetText("") end
        f._tenths = nil
        if f.endT then
            self:PlaceTicks()
            self:PlaceLag()
        end
    end
    local ticksOn, lagOn = CB.TICKS_HERE and not s.noTicks, not s.noLag
    if f.ticksOn ~= ticksOn or f.lagOn ~= lagOn then
        f.ticksOn, f.lagOn = ticksOn, lagOn
        if f.endT then
            self:PlaceTicks()
            self:PlaceLag()
        end
    end
    local lr, lg, lb, la = HUD.Col(s.lagColor, COL.lag)
    f.lag:SetVertexColor(lr, lg, lb, la)
    f.castCol, f.chanCol = s.color, s.chanColor
    if f:IsShown() then self:Paint() end
end

function Bar:Paint()
    local f = self.f
    local r, g, b, a = HUD.Col(f.channel and f.chanCol or f.castCol, f.channel and COL.channel or COL.cast)
    local c = r * 1e9 + g * 1e6 + b * 1e3 + a
    if f._col ~= c then
        f._col = c
        f:SetBarColor(r, g, b, a)
    end
end

-- ------------------------------------------------------------
-- ticks and latency
-- ------------------------------------------------------------
function Bar:HideTicks()
    local f = self.f
    for _, t in ipairs(f.ticks) do t:Hide() end
    f.tickN = nil
end

-- a mark at each tick still to land: where the fill will be at that moment
function Bar:PlaceTicks()
    local f = self.f
    local N = f.tickN
    if not (N and f.ticksOn and f.channel and f.endT) then
        for _, t in ipairs(f.ticks) do t:Hide() end
        return
    end
    local dur = f.endT - f.startT
    local bw = f:GetWidth() or 0
    for i = 1, math.max(N - 1, #f.ticks) do
        local t = f.ticks[i]
        local pos = (i <= N - 1 and dur > 0) and (f.endT - (f.tick0 + i * f.tickEvery)) / dur or nil
        if pos and pos > 0.001 and pos < 0.999 and bw > 0 then
            if not t then
                t = f.bar:CreateTexture(nil, "OVERLAY", nil, 3)
                t:SetTexture(WHITE)
                t:SetVertexColor(1, 1, 1, TICK_A)
                -- (2026-11-19: whole screen pixels under ZacUI's look, Core_Pixel; one unit everywhere else, as before)
                t:SetWidth(ns.Snap and ns.Snap(1, f.bar) or 1)
                f.ticks[i] = t
            end
            local x = math.floor(bw * pos + 0.5)
            t:ClearAllPoints()
            t:SetPoint("TOP", f.bar, "TOPLEFT", x, 0)
            t:SetPoint("BOTTOM", f.bar, "BOTTOMLEFT", x, 0)
            t.pos = pos
            t:Show()
        elseif t then
            t.pos = nil
            t:Hide()
        end
    end
end

function Bar:PlaceLag()
    local f = self.f
    local lag = self.lag
    local dur = f.endT and (f.endT - f.startT) or 0
    local bw = f:GetWidth() or 0
    if not (lag and f.lagOn and dur > 0 and bw > 0) then
        f.lag:Hide()
        f.lagW = nil
        return
    end
    local w = math.floor(bw * math.min(lag, dur) / dur + 0.5)
    if w < 1 then
        f.lag:Hide()
        f.lagW = nil
        return
    end
    -- a cast fills towards the right end, a channel drains towards the left
    f.lag:ClearAllPoints()
    if f.channel then
        f.lag:SetPoint("TOPLEFT", f.bar, "TOPLEFT", 0, 0)
        f.lag:SetPoint("BOTTOMLEFT", f.bar, "BOTTOMLEFT", 0, 0)
    else
        f.lag:SetPoint("TOPRIGHT", f.bar, "TOPRIGHT", 0, 0)
        f.lag:SetPoint("BOTTOMRIGHT", f.bar, "BOTTOMRIGHT", 0, 0)
    end
    f.lag:SetWidth(w)
    f.lagW = w
    f.lag:Show()
end

-- ------------------------------------------------------------
-- a cast on the bar
-- ------------------------------------------------------------
local function ShowParts(f)
    f:Show()
    if f.iconOn then f.icon:Show() end
end

-- plain times (seconds on GetTime's clock). fresh = a cast that just
-- started (its ticks are counted, its latency taken); else the cast in
-- hand read again (a delay, a channel that lost time)
function Bar:Start(name, texture, startT, endT, channel, fresh)
    local f = self.f
    if f.hiddenCast then
        -- (after a hidden cast the bar's range is the game's)
        f.hiddenCast = nil
        f.bar:SetMinMaxValues(0, 1)
    end
    if not fresh and (f.channel ~= channel or not f.endT or f.fake) then fresh = true end
    f.fake = nil
    f.channel, f.startT, f.endT, f._tenths = channel, startT, endT, nil
    self:Paint()
    f.icon:SetIconTexture(texture or QUESTION)
    f.name:SetText(name or "")
    if fresh then
        f.tickN = nil
        local data = channel and ChannelData(name) or nil
        local dur = endT - startT
        if data and dur > 0 then
            local n = CB.TickCount(data, dur)
            if n and n > 1 then
                f.tickN, f.tick0, f.tickEvery = n, startT, dur / n
            end
        end
        local sent = self.sentAt
        self.sentAt = nil
        local lag = sent and (GetTime() - sent) or nil
        self.lag = (lag and lag >= 0 and lag <= LAG_MAX) and lag or nil
    end
    self:PlaceTicks()
    self:PlaceLag()
    ShowParts(f)
    self:OnUpdate()
end

-- a cast the game hides: its own clock on the bar
function Bar:StartHidden(name, text, texture, channel)
    local f = self.f
    if not (ns.CastDuration and ns.ShowCastTimer) then return false end
    local dur = ns.CastDuration("player", channel)
    if not dur or not ns.ShowCastTimer(f.bar, dur, channel) then return false end
    f.hiddenCast, f.fake = true, nil
    f.channel, f.startT, f.endT, f._tenths = channel, nil, nil, nil
    self.lag, self.sentAt = nil, nil
    self:Paint()
    self:HideTicks()
    f.lag:Hide()
    f.lagW = nil
    f.icon.curTexture = nil
    pcall(f.icon.icon.SetTexture, f.icon.icon, texture)
    if not pcall(f.name.SetText, f.name, text or name) then f.name:SetText("") end
    f.time:SetText("")
    ShowParts(f)
    return true
end

function Bar:Hide()
    local f = self.f
    if not f then return end
    f.hiddenCast, f.fake, f.startT, f.endT, f.channel = nil, nil, nil, nil, nil
    f.tickN = nil
    self.lag = nil
    f:Hide()
    f.icon:Hide()
end

-- what you are casting now, onto the bar (or the bar away)
function Bar:Read(fresh)
    local f = self.f
    if not f or self.sample then return end
    local info, chan = UnitCastingInfo, UnitChannelInfo
    local channel = false
    local name, text, texture, startMS, endMS
    if info then name, text, texture, startMS, endMS = info("player") end
    if Secret(name) or Secret(startMS) or Secret(endMS) then
        if not self:StartHidden(name, text, texture, false) then self:Hide() end
        return
    end
    if not name and chan then
        name, text, texture, startMS, endMS = chan("player")
        channel = true
        if Secret(name) or Secret(startMS) or Secret(endMS) then
            if not self:StartHidden(name, text, texture, true) then self:Hide() end
            return
        end
    end
    if not (name and type(startMS) == "number" and type(endMS) == "number" and endMS > startMS) then
        return self:Hide()
    end
    self:Start(Plain(text) or name, Plain(texture), startMS / 1000, endMS / 1000, channel, fresh)
end

function Bar:OnUpdate()
    local f = self.f
    if f.hiddenCast or f.fake or not f.endT then return end
    local dur = f.endT - f.startT
    local left = f.endT - GetTime()
    if left <= 0 then
        -- its end event hides it; one that never came does here
        if left < -GRACE then return self:Hide() end
        left = 0
    end
    if left > dur then left = dur end
    f.bar:SetValue(f.channel and (left / dur) or (1 - left / dur))
    if f.timeOn then
        local tenths = math.floor(left * 10 + 0.5)
        if tenths ~= f._tenths then
            f._tenths = tenths
            f.time:SetText(string.format("%.1f", tenths / 10))
        end
    end
end

-- a made-up cast (the settings preview; Edit Mode and the HUD's "show
-- every element" test, so the bar can be seen where it sits): a little
-- past half way, with its latency
function Bar:ShowSample()
    local f = self.f
    local name, icon
    if self.sampleSpell then name, icon = self.sampleSpell() end
    if f.hiddenCast then f.bar:SetMinMaxValues(0, 1) end
    f.hiddenCast, f.fake = nil, true
    f.tickN = nil
    f.channel, f.startT, f.endT = false, 0, 2.5
    self.lag = 0.15
    self:Paint()
    f.icon:SetIconTexture(icon or QUESTION)
    f.name:SetText(name or "Spell")
    f.bar:SetMinMaxValues(0, 1)
    f.bar:SetValue(0.6)
    if f.timeOn then f.time:SetText("1.0") end
    self:PlaceTicks()
    self:PlaceLag()
    ShowParts(f)
end

-- ------------------------------------------------------------
-- events (your own casts; each reads the cast once)
-- ------------------------------------------------------------
local function OnEvent(bar, event, unit, a2, a3)
    if event == "UNIT_SPELLCAST_SENT" then
        bar.sentAt = GetTime()
    elseif event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" then
        bar:Read(true)
    else
        -- a delay, a channel that lost time, or an end: read again (a
        -- cast still in hand stays, a second spell's failure included)
        bar:Read(false)
    end
end
CB.OnEvent = OnEvent

function Bar:Watch(on)
    if self.sample or on == (self.watching or false) then return end
    self.watching = on
    local ev = self.ev
    if on then
        if not ev then
            ev = CreateFrame("Frame")
            local bar = self
            ev:SetScript("OnEvent", function(_, event, ...) OnEvent(bar, event, ...) end)
            self.ev = ev
        end
        for _, e in ipairs(EVENTS) do pcall(ev.RegisterUnitEvent, ev, e, "player") end
    elseif ev then
        for _, e in ipairs(EVENTS) do ev:UnregisterEvent(e) end
        self.sentAt = nil
    end
end

-- the HUD's tick: on = the HUD is up; test = the HUD shows every element
-- (Edit Mode, its test switch). Builds on first need, follows the
-- settings, starts and stops the cast events.
function Bar:Update(on, test)
    local s = self.settings()
    on = (on and s and s.enabled) and true or false
    if not on then
        if self.on then
            self.on = false
            self:Watch(false)
            self:Hide()
        end
        return
    end
    if not self:Build() then return end
    self:Apply(s)
    if self.sample then
        self.on = true
        return self:ShowSample()
    end
    if not self.on then
        self.on = true
        self:Watch(true)
        self.sentAt = nil
        self:Read(true)
    end
    -- the test: a made-up cast while nothing is cast; a cast of yours
    -- takes the bar, and the test over hands it back to what you cast
    local f = self.f
    if test then
        if not f:IsShown() then self:ShowSample() end
    elseif f.fake then
        self:Hide()
        self:Read(true)
    end
end

-- ------------------------------------------------------------
-- the page's card
-- ------------------------------------------------------------
-- o.get(create)  -> the settings table (made when create)
-- o.changed(structure)  after a change (structure = the page's rows changed)
-- o.sizes()      after a size change (the HUD sizes the anchor)
function CB.Card(L, o)
    local function On(key) local s = o.get() return (s and s[key]) and true or false end
    local function Set(key, v, structure)
        o.get(true)[key] = v
        o.changed(structure)
    end
    L:Card("Cast bar")
    L:Desc("Your own casts and channels as a bar that sits with the HUD. A piece of its own: its spot is under Position.")
    HUD.CheckIndent(L, "Show a cast bar", On("enabled"), function(v) Set("enabled", v or nil, true) end)
    if On("enabled") then
        local s = o.get() or EMPTY
        local w, h = Size(s)
        local function Px(v) return v .. " px" end
        HUD.SliderPair(L,
            { "Cast bar width", CB.MIN_W, CB.MAX_W, w, function(v)
                o.get(true).w = (v ~= CB.W) and v or nil
                o.sizes()
            end, Px },
            { "Cast bar height", CB.MIN_H, CB.MAX_H, h, function(v)
                o.get(true).h = (v ~= CB.H) and v or nil
                o.sizes()
            end, Px })
        HUD.CheckIndent(L, "Spell icon", not On("noIcon"), function(v) Set("noIcon", (not v) or nil) end)
        HUD.CheckIndent(L, "Spell name", not On("noName"), function(v) Set("noName", (not v) or nil) end)
        HUD.CheckIndent(L, "Time left", not On("noTime"), function(v) Set("noTime", (not v) or nil) end)
        if CB.TICKS_HERE then
            HUD.CheckIndent(L, "Channel ticks", not On("noTicks"), function(v) Set("noTicks", (not v) or nil) end, nil,
                "A mark for each tick of a channelled spell, where it lands.")
        end
        HUD.CheckIndent(L, "Latency", not On("noLag"), function(v) Set("noLag", (not v) or nil) end, nil,
            "A block at the end of the bar as long as the game took to answer your key press: the cast is already done there.")
        local function Colour(label, key, def)
            return { label,
                get = function() local c = o.get() return HUD.Col(c and c[key], def) end,
                set = function(r, g, b, a) Set(key, { r = r, g = g, b = b, a = a or 1 }) end }
        end
        HUD.ColorGrid(L, { Colour("Cast colour", "color", COL.cast), Colour("Channel colour", "chanColor", COL.channel),
            Colour("Latency colour", "lagColor", COL.lag) })
    end
    L:EndCard()
end
