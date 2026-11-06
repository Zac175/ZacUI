-- QoL_GCDTracker - a small row of icons showing what you pressed and what
-- went off, with the global cooldown drawn under it. Part of ZacUI; load
-- order is set by the TOC.
--
-- WHAT IT SHOWS. By default, every cast that went off adds its icon at
-- the right end of the row (older ones slide left; the oldest drop off).
-- With "show presses" on, every bar press adds an icon as well: dim
-- while the game thinks about it, lit when the cast went off, red with a
-- cross when the game refused it (no rage, on cooldown, nothing
-- happened); a press repeated while the last one is still refused is
-- counted on that icon ("x3") instead of filling the row with crosses -
-- a rage-starved Heroic Strike spam is one icon. Under the row, a thin bar fills
-- while the global cooldown runs; an ability that is off the GCD leaves
-- it alone. Nothing is drawn while the row is empty, and icons fade out
-- a few seconds after the last press, so out of a fight there is nothing
-- on screen.
--
-- HOW: presses come from a hook on UseAction (every bar button, every
-- bar addon, goes through it); results from UNIT_SPELLCAST_SUCCEEDED /
-- FAILED / FAILED_QUIET for the player. A press is matched to a result
-- by spell id (a macro's by GetMacroSpell), else by order. The GCD is
-- read from the game (spell 61304) when the cast lands.
--
-- THE ROW is built and drawn by NewRow / StyleRow / LayoutRow, which the
-- settings preview calls too, on its own row with made-up casts: what the
-- preview shows is what the fight shows. Every look and timing below is
-- a setting whose default is how the row has always looked.
--
-- COST: no per-frame work. A 0.1s ticker runs only while an icon is on
-- screen (fading, expiring pending presses, the GCD bar) and stops when
-- the row is empty. A slide (off by default) runs an OnUpdate on the row
-- only while icons are moving.

local ADDON_NAME = ...
-- Zacui_QoL is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

local GetColor = ns.GetColor
local QoL = ns.QoL
local UI = ns.UI

local GT = {}
QoL.GCDTracker = GT

local MOVER = "gcdtracker"
local GCD_SPELL = 61304            -- the game's own "Global Cooldown" spell
local PENDING_FOR = 0.5            -- a press with no answer by then: nothing happened
local SAME_WITHIN = 0.6            -- a repeat of a refused press this soon: counted, not added
local CROSS = "Interface\\RaidFrame\\ReadyCheck-NotReady"

-- ============================================================
-- SETTINGS
-- ============================================================
-- Look and motion; nil in the colours, fonts and texture means "as it
-- has always been" (the accent colour, the game's red, ZacUI's font...).
GT.DEFAULTS = {
    gap = 2,                 -- between icons
    grow = "left",           -- the newest at the right, older ones move left
    border = true,           -- a thin border round each icon
    barHeight = 3,           -- the global cooldown bar
    barPos = "below",
    barTexture = nil,        -- nil: plain flat
    barColor = nil,          -- nil: the accent colour
    barBg = nil,             -- nil: the window colour, half see-through
    countFont = nil,         -- nil: ZacUI's font, 10, outlined
    countColor = nil,        -- nil: white
    pendingColor = nil,      -- nil: grey (a press waiting for the game)
    failColor = nil,         -- nil: the palette's red
    cross = true,            -- a cross over a refused press
    fadeOut = 1.5,           -- seconds an icon takes to fade at the end
    slide = 0,               -- seconds the row takes to slide along; 0: at once
    slideEase = "easeOutQuad",
    showAnim = { style = "none", duration = 0.2, delay = 0, easing = "easeOutQuad", dir = "right", distance = 12 },
}

local function DB()
    local q = QoL.DB()
    q.gcd = q.gcd or {}
    local d = q.gcd
    if d.enabled == nil then d.enabled = false end
    if d.size == nil then d.size = 26 end
    if d.count == nil then d.count = 10 end
    if d.fade == nil then d.fade = 5 end          -- seconds after the last press
    -- off by default (2026-10-26, Zac: "shows every time i pressed the
    -- key and not just successful casts"): only casts that went off,
    -- unless asked for the presses as well
    if d.showFails == nil or d._rev == nil then d.showFails = false end
    if d.showGCD == nil then d.showGCD = true end
    d._rev = 1
    if ns.FillDefaults then ns.FillDefaults(d, GT.DEFAULTS)
    else for k, v in pairs(GT.DEFAULTS) do if d[k] == nil then d[k] = v end end end
    return d
end
GT.DB = DB
GT.COUNT_DEFAULTS = { point = "BOTTOMRIGHT", relPoint = "BOTTOMRIGHT", x = -1, y = 1 }

local function Col(c, fallback)
    if ns.ColorOf and type(c) == "table" then return ns.ColorOf(c) end
    return fallback.r, fallback.g, fallback.b, fallback.a or 1
end

local function MotionOn() return not (ns.Motion and not ns.Motion.Enabled()) end
local function MotionSpeed() return ns.Motion and ns.Motion.Speed() or 1 end

-- the count's font: as it always was until a font is picked
local function CountFont(fs, d)
    local spec = d.countFont
    if type(spec) == "table" and next(spec) and ns.ApplyFontSpec then
        local delta = ZacUIDB and ZacUIDB.font and tonumber(ZacUIDB.font.delta) or 0
        ns.ApplyFontSpec(fs, spec, { size = 10 + delta, outline = "outline" })
    else
        ns.HouseFont(fs, 10, "OUTLINE", STANDARD_TEXT_FONT)
    end
    fs:SetTextColor(Col(d.countColor, { r = 1, g = 1, b = 1 }))
end

-- ============================================================
-- THE ROW (the live one and the preview's)
-- ============================================================
-- row = { holder, strip (the icons ride on it, so a slide moves one
-- frame), gcdBar, bg, slots = {}, shift (the slide still to go) }
-- name: the live row keeps the global name it always had (ZacUIGCDTracker);
-- the preview's sample has none.
function GT.NewRow(parent, name)
    local row = { slots = {}, shift = 0 }
    local h = CreateFrame("Frame", name, parent)
    row.holder = h
    local strip = CreateFrame("Frame", nil, h)
    strip:SetPoint("TOPLEFT", h, "TOPLEFT", 0, 0)
    strip:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", 0, 0)
    row.strip = strip
    local bar = CreateFrame("StatusBar", nil, h)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture(ns.FLAT)
    row.gcdBar, row.bg = bar, bg
    bar:Hide()
    return row
end

local function Slot(row, i)
    local s = row.slots[i]
    if s then return s end
    s = CreateFrame("Frame", nil, row.strip)
    UI.Border(s, "ui", "border")
    UI.PaintBox(s)                 -- the strips take the border colour here, not on creation
    s.icon = s:CreateTexture(nil, "ARTWORK")
    s.icon:SetAllPoints()
    s.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    s.cross = s:CreateTexture(nil, "OVERLAY")
    s.cross:SetAllPoints()
    s.cross:SetTexture(CROSS)
    s.cross:Hide()
    s.num = s:CreateFontString(nil, "OVERLAY")
    s.num:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", -1, 1)
    s:Hide()
    row.slots[i] = s
    row.styled = nil
    return s
end

-- Sizes, the bar and the count font: the settings that are the same for
-- every icon. Cheap; called on every layout.
function GT.StyleRow(row, d)
    local size, gap = d.size, tonumber(d.gap) or 2
    local h = row.holder
    h:SetSize(math.max(1, d.count * (size + gap) - gap), size + 6)
    local bar = row.gcdBar
    bar:ClearAllPoints()
    local bh = math.max(1, tonumber(d.barHeight) or 3)
    if d.barPos == "above" then
        bar:SetPoint("TOPLEFT", h, "TOPLEFT", 0, bh + 2)
        bar:SetPoint("TOPRIGHT", h, "TOPRIGHT", 0, bh + 2)
    else
        bar:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", 0, 0)
        bar:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", 0, 0)
    end
    bar:SetHeight(bh)
    local tex = d.barTexture and ns.ResolveBarTexture and ns.ResolveBarTexture(d.barTexture) or ns.FLAT
    bar:SetStatusBarTexture(tex)
    bar:SetStatusBarColor(Col(d.barColor, GetColor("ui", "accent")))
    if type(d.barBg) == "table" then
        row.bg:SetVertexColor(Col(d.barBg))
    else
        local w = GetColor("ui", "windowBg")
        row.bg:SetVertexColor(w.r, w.g, w.b, 0.5)
    end
    -- where the repeat count sits (gcdTracker.anchors.count, ZacUI's anchor
    -- shape; the icon's bottom right corner is its spot). Nothing saved =
    -- never touched.
    local ca = type(d.anchors) == "table" and d.anchors.count or nil
    for _, s in ipairs(row.slots) do
        if ns.TagElement then ns.TagElement(s.num, "gcd.count") end
        if (ca or s._zMoved) and ns.ApplyAnchor then
            s._zMoved = ca and true or nil
            local D = s._zDef or {}
            s._zDef = D
            D.point, D.to, D.relPoint, D.x, D.y = "BOTTOMRIGHT", s, "BOTTOMRIGHT", -1, 1
            if not s._zAnchorTo then s._zAnchorTo = function(k) if k == "icon" then return s end end end
            ns.ApplyAnchor(s.num, ca, D, s._zAnchorTo)
        end
        CountFont(s.num, d)
        if s._zBorder then
            for _, t in ipairs(s._zBorder) do t:SetShown(d.border ~= false) end
        end
    end
end

-- age -> alpha: fading out over the last fadeOut seconds before `fade`
local function FadeAlpha(age, d)
    local fo = MotionOn() and (tonumber(d.fadeOut) or 1.5) / MotionSpeed() or 0
    if fo <= 0 then return age < d.fade and 1 or 0 end
    if age > d.fade - fo then return math.max(0, (d.fade - age) / fo) end
    return 1
end
GT.FadeAlpha = FadeAlpha

-- state -> how the icon looks
local function Paint(s, e, now, d)
    s.icon:SetTexture(e.tex)
    if e.state == "ok" then
        s.icon:SetDesaturated(false)
        s.icon:SetVertexColor(1, 1, 1)
        s.cross:Hide()
    elseif e.state == "fail" then
        local r, g, b = Col(d.failColor, GetColor("text", "red"))
        s.icon:SetDesaturated(true)
        s.icon:SetVertexColor(r, g, b)
        s.cross:SetShown(d.cross ~= false)
    else -- pressed, waiting for the game
        local r, g, b = Col(d.pendingColor, { r = 0.55, g = 0.55, b = 0.55 })
        s.icon:SetDesaturated(false)
        s.icon:SetVertexColor(r, g, b)
        s.cross:Hide()
    end
    s.num:SetText(e.n > 1 and ("x" .. e.n) or "")
    -- an icon arriving animates its own alpha; the fade waits for it
    if not (ns.Motion and ns.Motion.IsPlaying(s)) then s:SetAlpha(FadeAlpha(now - e.at, d)) end
end

-- the slide: the strip starts one icon back and glides home
local function SlideStep(h, elapsed)
    local row = h._zRow
    if not row then return end
    row.slideT = row.slideT + elapsed
    local p = math.min(1, row.slideT / row.slideDur)
    local ease = ns.Motion and ns.Motion.EASE and ns.Motion.EASE[row.slideEase] or function(t) return t end
    row.shift = row.slideFrom * (1 - ease(p))
    row.strip:ClearAllPoints()
    row.strip:SetPoint("TOPLEFT", h, "TOPLEFT", row.shift, 0)
    row.strip:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", row.shift, 0)
    if p >= 1 then
        row.shift = 0
        h:SetScript("OnUpdate", nil)
    end
end

-- The icons for `list` (newest last) onto the row. arrived: a new icon
-- joined at the newest end - the row slides and the newest icon plays
-- its entrance, as the settings say.
function GT.LayoutRow(row, list, d, now, arrived)
    GT.StyleRow(row, d)
    local h = row.holder
    local size, gap = d.size, tonumber(d.gap) or 2
    local step = size + gap
    local right = d.grow ~= "right"
    local n = #list
    for i = 1, math.max(n, #row.slots) do
        local s = Slot(row, i)
        if not row.styled then
            CountFont(s.num, d)
            if s._zBorder then for _, t in ipairs(s._zBorder) do t:SetShown(d.border ~= false) end end
        end
        local e = list[n - i + 1]
        if e then
            local playing = ns.Motion and ns.Motion.IsPlaying(s)
            if playing and (s._zSize ~= size or s._zStep ~= step or s._zRight ~= right) then
                ns.Motion.Stop(s)
                playing = false
            end
            if not playing then
                s:SetSize(size, size)
                s:ClearAllPoints()
                if right then
                    s:SetPoint("TOPRIGHT", row.strip, "TOPRIGHT", -((i - 1) * step), 0)
                else
                    s:SetPoint("TOPLEFT", row.strip, "TOPLEFT", (i - 1) * step, 0)
                end
                s._zSize, s._zStep, s._zRight = size, step, right
            end
            Paint(s, e, now, d)
            s:Show()
        else
            if ns.Motion then ns.Motion.Stop(s) end
            s:Hide()
        end
    end
    row.styled = true
    if arrived and n > 0 then
        -- the row moves along by one icon: start it one icon back
        local dur = tonumber(d.slide) or 0
        if dur > 0 and MotionOn() and n > 1 then
            row.slideDur = dur / MotionSpeed()
            row.slideT = 0
            row.slideEase = d.slideEase or "easeOutQuad"
            row.slideFrom = (right and step or -step) + (row.shift or 0)
            h._zRow = row
            SlideStep(h, 0)
            h:SetScript("OnUpdate", SlideStep)
        end
        local spec = d.showAnim
        if ns.Motion and type(spec) == "table" and spec.style and spec.style ~= "none" then
            local s = row.slots[1]
            s:Hide()
            ns.Motion.Show(s, spec)
        end
    end
    if n > 0 then h:Show() else h:Hide() end
end

-- the GCD bar: fill (0..1) or nil to hide it
function GT.SetGCD(row, d, value)
    if d.showGCD and value then
        row.gcdBar:SetValue(value)
        row.gcdBar:Show()
    else
        row.gcdBar:Hide()
    end
end

-- ============================================================
-- THE LIVE ROW
-- ============================================================
local live                       -- the row on screen
local entries = {}               -- newest last: { tex, spell, state, at, n }
local ticker
local lastPressAt = 0
local hooked = false

local function Live()
    if live then return live end
    live = GT.NewRow(UIParent, "ZacUIGCDTracker")
    local holder = live.holder
    holder:SetFrameStrata("MEDIUM")
    holder:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -10, 215)
    if ns.RegisterMover then
        ns.RegisterMover(MOVER, "GCD tracker", function() return holder end, "BOTTOMRIGHT", -10, 215)
        if ns.ApplyMover then ns.ApplyMover(MOVER) end
    end
    holder:Hide()
    return live
end

local function Layout(arrived)
    GT.LayoutRow(Live(), entries, DB(), GetTime(), arrived)
end

local function Tick()
    local d = DB()
    local now = GetTime()
    local changed = false
    -- presses the game never answered
    for _, e in ipairs(entries) do
        if e.state == "pressed" and now - e.at > PENDING_FOR then
            e.state = d.showFails and "fail" or "ok"
            changed = true
        end
    end
    -- the oldest gone
    while entries[1] and now - entries[1].at > d.fade do
        table.remove(entries, 1)
        changed = true
    end
    if changed then Layout()
    elseif live then
        -- just the fades
        local n = #entries
        for i = 1, n do
            local s = live.slots[i]
            local e = entries[n - i + 1]
            if s and e and not (ns.Motion and ns.Motion.IsPlaying(s)) then
                s:SetAlpha(FadeAlpha(now - e.at, d))
            end
        end
    end
    -- the GCD bar
    if live then
        local st, du = GetSpellCooldown(GCD_SPELL)
        if st and du and du > 0 and du <= 2 and st + du > now then
            GT.SetGCD(live, d, (now - st) / du)
        else
            GT.SetGCD(live, d, nil)
        end
    end
    if #entries == 0 and ticker then
        ticker:Cancel()
        ticker = nil
    end
end

local function StartTicker()
    if ticker then return end
    ticker = C_Timer.NewTicker(0.1, Tick)
    if ns.Profiler and ns.Profiler.TrackTicker then ns.Profiler.TrackTicker(ticker, "QoL.gcdTracker") end
end

-- a new entry, or a count on the last one when it is the same refused press
local function Add(tex, spell, state)
    local d = DB()
    local now = GetTime()
    local last = entries[#entries]
    if last and state == "pressed" and last.state ~= "ok" and last.tex == tex and now - last.at < SAME_WITHIN then
        last.n = last.n + 1
        last.at = now
        last.state = "pressed"
        last.spell = spell or last.spell
        Layout()
        StartTicker()
        return last
    end
    local e = { tex = tex, spell = spell, state = state, at = now, n = 1 }
    entries[#entries + 1] = e
    while #entries > d.count do table.remove(entries, 1) end
    Layout(true)
    StartTicker()
    return e
end

-- the newest pressed entry for this spell (or the newest pressed at all)
local function Pending(spell)
    for i = #entries, 1, -1 do
        local e = entries[i]
        if e.state == "pressed" and (spell == nil or e.spell == nil or e.spell == spell) then return e end
    end
    return nil
end

-- ============================================================
-- PRESSES AND RESULTS
-- ============================================================
local function OnPress(slot)
    local d = DB()
    -- presses only when asked: otherwise the row is what went off
    if not (d.enabled and d.showFails) then return end
    local tex = GetActionTexture(slot)
    if not tex then return end
    local kind, id = GetActionInfo(slot)
    local spell
    if kind == "spell" then spell = id
    elseif kind == "macro" then
        local ms = GetMacroSpell and GetMacroSpell(id)
        if type(ms) == "number" then spell = ms end
    end
    lastPressAt = GetTime()
    Add(tex, spell, "pressed")
end

local function OnResult(event, spellId)
    if not DB().enabled then return end
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        local e = Pending(spellId)
        if e then
            e.state = "ok"
            if spellId then e.tex = GetSpellTexture(spellId) or e.tex end
        else
            -- not from a bar press (a /click button, a trinket's own use)
            local tex = spellId and GetSpellTexture(spellId)
            if tex then Add(tex, spellId, "ok") return end
        end
    else
        local e = Pending(spellId)
        if e then e.state = DB().showFails and "fail" or "ok" end
    end
    Layout()
    StartTicker()
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event, unit, _, spellId)
    if event == "PLAYER_LOGIN" then GT.Apply() return end
    if unit ~= "player" then return end
    OnResult(event, spellId)
end)
ev:RegisterEvent("PLAYER_LOGIN")

function GT.Apply()
    local d = DB()
    if QoL.enabled and d.enabled then
        if not hooked then
            hooked = true
            hooksecurefunc("UseAction", function(slot) OnPress(slot) end)
        end
        ev:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        ev:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
        ev:RegisterUnitEvent("UNIT_SPELLCAST_FAILED_QUIET", "player")
        Live()
        Layout()
    else
        ev:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
        ev:UnregisterEvent("UNIT_SPELLCAST_FAILED")
        ev:UnregisterEvent("UNIT_SPELLCAST_FAILED_QUIET")
        wipe(entries)
        if live then Layout() end
        if ticker then ticker:Cancel() ticker = nil end
    end
end

-- the look changed (the settings page): the row on screen follows
function GT.Restyle()
    if live and live.holder:IsShown() then Layout() end
end

-- a demo row, for placing it (/zui config "Move it")
GT.DEMO = {
    { "Interface\\Icons\\Ability_Rogue_Ambush", "ok" },             -- Heroic Strike, went off
    { "Interface\\Icons\\Ability_Warrior_Charge", "fail" },         -- Charge, refused
    { "Interface\\Icons\\Ability_Warrior_SavageBlow", "pressed" },  -- Mortal Strike, waiting
}
function GT.Demo()
    if not DB().enabled then return end
    for _, x in ipairs(GT.DEMO) do Add(x[1], nil, x[2]) end
end
