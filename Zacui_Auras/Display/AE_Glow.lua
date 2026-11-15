-- AE_Glow - glows round a frame: the pixel lines, the autocast shine,
-- and the action-button glow. ZacUI's own drawing.
-- Part of ZacUI (Zacui_Auras). Written for ZacUI.
--
-- E.Glow.Show(frame, o, key)   o: type ("Pixel", "ACShine", "buttonOverlay";
--                                  "Proc" draws as the button glow - the
--                                  format has no proc glow on Classic Era),
--                                  color {r,g,b,a}, lines, frequency, length,
--                                  thickness, xOffset, yOffset, scale, border
-- E.Glow.Hide(frame, key)
-- One frame can carry several glows under different keys.
local ns = _G.ZacUI
if not ns then return end
local E = ns.AuraEngine
if not E then return end

local G = {}
E.Glow = G

local WHITE = "Interface\\Buttons\\WHITE8x8"
local driver = CreateFrame("Frame")
local live = {}           -- glow object -> true
local pool = {}

local function Holder(frame, key)
    frame._aeGlows = frame._aeGlows or {}
    return frame._aeGlows[key or "default"]
end

local function Release(g)
    live[g] = nil
    g:Hide()
    g:ClearAllPoints()
    for _, t in ipairs(g.tex) do t:Hide() end
    if g.native and g.owner and ActionButton_HideOverlayGlow then pcall(ActionButton_HideOverlayGlow, g.owner) end
    g.native = nil
    g.owner = nil
    pool[#pool + 1] = g
end

local function New(frame)
    local g = table.remove(pool)
    if not g then
        g = CreateFrame("Frame")
        g.tex = {}
    end
    g:SetParent(frame)
    g:SetFrameLevel(frame:GetFrameLevel() + 8)
    g:Show()
    return g
end

local function Tex(g, i)
    local t = g.tex[i]
    if not t then
        t = g:CreateTexture(nil, "OVERLAY")
        g.tex[i] = t
    end
    t:SetTexture(WHITE)
    t:Show()
    return t
end

-- ============================================================
-- PIXEL: lines running round the edge
-- ============================================================
local function PixelStep(g, now)
    local w, h = g:GetWidth() or 0, g:GetHeight() or 0
    local per = 2 * (w + h)
    if per <= 0 then return end
    local n, len, th = g.lines, g.len, g.th
    local phase = (now * g.freq) % 1
    for i = 1, n do
        local t = g.tex[i]
        local pos = ((i - 1) / n + phase) % 1 * per
        t:ClearAllPoints()
        if pos < w then
            t:SetPoint("TOPLEFT", g, "TOPLEFT", pos, 0)
            t:SetSize(math.min(len, w - pos), th)
        elseif pos < w + h then
            t:SetPoint("TOPRIGHT", g, "TOPRIGHT", 0, -(pos - w))
            t:SetSize(th, math.min(len, w + h - pos))
        elseif pos < 2 * w + h then
            t:SetPoint("BOTTOMRIGHT", g, "BOTTOMRIGHT", -(pos - w - h), 0)
            t:SetSize(math.min(len, 2 * w + h - pos), th)
        else
            t:SetPoint("BOTTOMLEFT", g, "BOTTOMLEFT", 0, pos - 2 * w - h)
            t:SetSize(th, math.min(len, per - pos))
        end
    end
end

-- ============================================================
-- ACSHINE: four little trails of dots going round
-- ============================================================
local function ShineStep(g, now)
    local w, h = g:GetWidth() or 0, g:GetHeight() or 0
    local per = 2 * (w + h)
    if per <= 0 then return end
    local groups, dots = 4, g.dots
    for gi = 1, groups do
        local speed = g.freq * (gi % 2 == 0 and 1 or 0.7)
        local head = ((now * speed) + (gi - 1) / groups) % 1
        for di = 1, dots do
            local t = g.tex[(gi - 1) * dots + di]
            local pos = (head - di * 0.012) % 1 * per
            local x, y
            if pos < w then x, y = pos, 0
            elseif pos < w + h then x, y = w, -(pos - w)
            elseif pos < 2 * w + h then x, y = w - (pos - w - h), -h
            else x, y = 0, -(h - (pos - 2 * w - h)) end
            local s = g.size * (1 - di / (dots + 2))
            t:ClearAllPoints()
            t:SetPoint("CENTER", g, "TOPLEFT", x, y)
            t:SetSize(s, s)
        end
    end
end

-- ============================================================
-- BUTTON GLOW: the game's own action-button glow where the client has
-- it; otherwise a soft border that breathes
-- ============================================================
local function PulseStep(g, now)
    local a = 0.45 + 0.45 * math.sin(now * 6)
    for i = 1, 4 do g.tex[i]:SetAlpha(a) end
end

driver:SetScript("OnUpdate", function()
    local now = GetTime()
    local any = false
    for g in pairs(live) do
        any = true
        if g:IsVisible() and g.step then g.step(g, now) end
    end
    if not any then driver:Hide() end
end)

function G.Show(frame, o, key)
    if not frame then return end
    key = key or "default"
    G.Hide(frame, key)
    o = o or {}
    local g = New(frame)
    frame._aeGlows = frame._aeGlows or {}
    frame._aeGlows[key] = g
    local r, gg, b, a = E.Color(o.color, 0.95, 0.95, 0.32, 1)
    local kind = o.type or "buttonOverlay"
    local xo, yo = tonumber(o.xOffset) or 0, tonumber(o.yOffset) or 0
    g:ClearAllPoints()
    g:SetPoint("TOPLEFT", frame, "TOPLEFT", -xo, yo)
    g:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", xo, -yo)
    if kind == "Pixel" then
        g.lines = math.max(1, tonumber(o.lines) or 8)
        g.freq = tonumber(o.frequency) or 0.25
        g.th = tonumber(o.thickness) or 2
        local w, h = frame:GetWidth() or 32, frame:GetHeight() or 32
        g.len = tonumber(o.length) or math.floor((w + h) * 2 / g.lines * 0.6)
        for i = 1, g.lines do
            local t = Tex(g, i)
            t:SetVertexColor(r, gg, b, a)
        end
        -- glowBorder: a dark frame inside the running lines
        if o.border then
            local th = g.th
            local edges = {
                { "TOPLEFT", "TOPRIGHT", nil, th }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, th },
                { "TOPLEFT", "BOTTOMLEFT", th, nil }, { "TOPRIGHT", "BOTTOMRIGHT", th, nil },
            }
            for k, e in ipairs(edges) do
                local t = Tex(g, g.lines + k)
                t:ClearAllPoints()
                t:SetPoint(e[1], g, e[1], 0, 0)
                t:SetPoint(e[2], g, e[2], 0, 0)
                if e[3] then t:SetWidth(e[3]) else t:SetHeight(e[4]) end
                t:SetVertexColor(0.3, 0.3, 0.3, 0.9)
            end
        end
        g.step = PixelStep
    elseif kind == "ACShine" then
        g.dots = math.max(1, tonumber(o.lines) or 4)
        g.freq = tonumber(o.frequency) or 0.125
        g.size = 6 * (tonumber(o.scale) or 1)
        for i = 1, 4 * g.dots do
            local t = Tex(g, i)
            t:SetTexture("Interface\\Cooldown\\star4")
            t:SetBlendMode("ADD")
            t:SetVertexColor(r, gg, b, a)
        end
        g.step = ShineStep
    else
        if ActionButton_ShowOverlayGlow and frame.GetObjectType then
            local ok = pcall(ActionButton_ShowOverlayGlow, frame)
            if ok and (frame.overlay or frame.SpellActivationAlert) then
                g.native = true
                g.owner = frame
                g.step = nil
                return g
            end
        end
        local th = 2
        local edges = {
            { "TOPLEFT", "TOPRIGHT", nil, th }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, th },
            { "TOPLEFT", "BOTTOMLEFT", th, nil }, { "TOPRIGHT", "BOTTOMRIGHT", th, nil },
        }
        for i, e in ipairs(edges) do
            local t = Tex(g, i)
            t:ClearAllPoints()
            t:SetPoint(e[1], g, e[1], 0, 0)
            t:SetPoint(e[2], g, e[2], 0, 0)
            if e[3] then t:SetWidth(e[3]) else t:SetHeight(e[4]) end
            t:SetVertexColor(r, gg, b, a)
            t:SetBlendMode("ADD")
        end
        g.step = PulseStep
    end
    live[g] = true
    driver:Show()
    return g
end

function G.Hide(frame, key)
    if not frame then return end
    local g = Holder(frame, key)
    if not g then return end
    frame._aeGlows[key or "default"] = nil
    Release(g)
end

function G.HideAll(frame)
    if not (frame and frame._aeGlows) then return end
    for key in pairs(frame._aeGlows) do G.Hide(frame, key) end
end
