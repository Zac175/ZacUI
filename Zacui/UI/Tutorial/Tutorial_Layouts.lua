-- Tutorial_Layouts - named layouts for the setup's Layout step: a few
-- arrangements of the frames, bars, meter windows, minimap and chat for
-- this screen, previewed as ghost boxes over the world before anything
-- moves, then applied through each frame's own position storage.
-- Part of ZacUI; load order is set by the TOC (after Tutorial_Hints,
-- before Tutorial_Setup2, which draws the step from BuildStep).
--
-- TARGETS. Everything with a ZacUI-owned position that the setup can
-- place, found when the step builds (parts that are not loaded are simply
-- not there):
--   * the mover registry (UIF_Movers): the minimap, the buffs, the loot
--     rolls, every class HUD anchor, through their own saved spot
--   * the unit frames (Zacui_UnitFrames): player, target, target of
--     target, pet, party, raid, through their own point / x / y and
--     ApplySettings
--   * the action bars (Zacui_Bars): every bar header, through its cfg and
--     AB.Place
--   * the meter windows (Zacui_Meter): point / x / y of each open window
--   * the chat (ChatFrame1, the game's own window, which Blz_Chat records)
-- A part may add one of its own: ns.RegisterLayoutTarget(key, spec) with
-- spec = { label, size = fn() -> w, h, place = fn(point, x, y, scale),
-- reset = fn(), group = "frames" | "bars" | "windows" }.
--
-- A PLACEMENT is resolution-aware: { point, fx, fy, scale }, x and y as
-- FRACTIONS of the screen's width and height from the anchor point, so a
-- layout lands the same on a 1080p and a 4K screen. "Keep mine" is always
-- offered and selected first; "ZacUI default" puts every target back to
-- its own default. Nothing moves until Apply.
--
--   ns.LayoutPresets.Available()        a target exists on this install
--   ns.LayoutPresets.Targets()          the targets, discovered now
--   ns.LayoutPresets.PRESETS            the presets, in order
--   ns.LayoutPresets.Resolve(place)     point, x, y for this screen
--   ns.LayoutPresets.Preview(id)        the ghost overlay (false: nothing to show)
--   ns.LayoutPresets.EndPreview()
--   ns.LayoutPresets.Apply(id)          moves everything; returns how many
--   ns.LayoutPresets.BuildStep(host, y, ctx)   the setup's step

local ADDON_NAME, ns = ...

local FLAT = ns.FLAT
local GetColor = ns.GetColor
local Print = ns.Print
local UI = ns.UI
local M, F = UI.M, UI.F

local LP = {}
local extra = {}        -- [key] = spec, from ns.RegisterLayoutTarget

function ns.RegisterLayoutTarget(key, spec)
    if type(key) ~= "string" or type(spec) ~= "table" then return end
    extra[key] = spec
end

local function InCombat()
    return (InCombatLockdown and InCombatLockdown()) or false
end

local function Loaded(addon)
    return ns.AddonLoaded and ns.AddonLoaded(addon) or false
end

local function Screen()
    local w = UIParent and UIParent.GetWidth and UIParent:GetWidth() or 0
    local h = UIParent and UIParent.GetHeight and UIParent:GetHeight() or 0
    if not (w and w > 0) then w = 1920 end
    if not (h and h > 0) then h = 1080 end
    return w, h
end

-- ============================================================
-- TARGETS
-- ============================================================
local function FrameSize(f)
    if not (f and f.GetWidth) then return 100, 30 end
    local w, h = f:GetWidth(), f:GetHeight()
    if type(w) ~= "number" or w < 2 then w = 100 end
    if type(h) ~= "number" or h < 2 then h = 30 end
    return w, h
end

local function CurrentPoint(f)
    if not (f and f.GetPoint) then return nil end
    local ok, point, rel, relPoint, x, y = pcall(f.GetPoint, f, 1)
    if ok and point and (rel == nil or rel == UIParent) then return point, x or 0, y or 0 end
    return nil
end

function LP.Targets()
    local out = {}
    local function Add(t) out[#out + 1] = t end

    -- the mover registry
    for _, m in ipairs(ns.MOVERS or {}) do
        local key = m.key
        local f = m.getFrame and m.getFrame()
        if f and not (ns.MoverBlocked and ns.MoverBlocked(key, f)) then
            Add({
                key = "mover:" .. key, label = m.label or key, group = "frames",
                size = function() return FrameSize(f) end,
                current = function() return CurrentPoint(f) end,
                default = function() return m.defPoint, m.defX, m.defY end,
                place = function(point, x, y)
                    if m.set then m.set(point, x, y)
                    else
                        ZacUIDB.movers = ZacUIDB.movers or {}
                        ZacUIDB.movers[key] = { point = point, x = x, y = y }
                    end
                    if ns.ApplyMover then ns.ApplyMover(key) end
                end,
                reset = function() if ns.ResetMover then ns.ResetMover(key, true) end end,
            })
        end
    end

    -- the unit frames
    local Z = _G.ZacUF
    if Z and type(Z.db) == "table" and Loaded("Zacui_UnitFrames") then
        local function UF(key, label, cfgFn)
            local cfg = cfgFn()
            if type(cfg) ~= "table" then return end
            local f = Z.frames and Z.frames[key]
            Add({
                key = "uf:" .. key, label = label, group = "frames",
                size = function() return FrameSize(f) end,
                current = function()
                    local c = cfgFn()
                    if c and c.point then return c.point, c.x or 0, c.y or 0 end
                    return CurrentPoint(f)
                end,
                place = function(point, x, y)
                    local c = cfgFn()
                    c.point, c.x, c.y = point, x, y
                    if Z.ApplySettings then pcall(Z.ApplySettings) end
                end,
            })
        end
        UF("player", "Player frame", function() return Z.db.frames and Z.db.frames.player end)
        UF("target", "Target frame", function() return Z.db.frames and Z.db.frames.target end)
        UF("targettarget", "Target of target", function() return Z.db.frames and Z.db.frames.targettarget end)
        UF("pet", "Pet frame", function() return Z.db.frames and Z.db.frames.pet end)
        UF("party", "Party frames", function() return Z.db.party end)
        UF("raid", "Raid frames", function() return Z.db.raid end)
    end

    -- the action bars
    local AB = ns.Bars
    if AB and type(AB.headers) == "table" and Loaded("Zacui_Bars") then
        local keys = {}
        for k in pairs(AB.headers) do keys[#keys + 1] = k end
        table.sort(keys)
        for _, k in ipairs(keys) do
            local h = AB.headers[k]
            if h and h.cfg then
                Add({
                    key = "bar:" .. k, label = h.label or k, group = "bars", scalable = true, secure = true,
                    scale = function() return h.cfg.scale or 1 end,
                    size = function()
                        local ov = h.overlay or h
                        local w, hh = FrameSize(ov)
                        local s = h.cfg.scale or 1
                        return w * s, hh * s
                    end,
                    current = function()
                        if h.cfg.point then return h.cfg.point, h.cfg.x or 0, h.cfg.y or 0 end
                        return CurrentPoint(h)
                    end,
                    place = function(point, x, y, scale)
                        if scale then h.cfg.scale = scale end
                        h.cfg.point, h.cfg.x, h.cfg.y = point, x, y
                        if AB.Place then pcall(AB.Place, h, h.cfg) end
                    end,
                    reset = function()
                        h.cfg.point, h.cfg.x, h.cfg.y = nil, nil, nil
                        if AB.Place then pcall(AB.Place, h, h.cfg) end
                    end,
                })
            end
        end
    end

    -- the meter windows
    local Meter = ns.Meter
    if Meter and Meter.Windows and Meter.Windows.Each and Loaded("Zacui_Meter") then
        pcall(Meter.Windows.Each, function(win)
            local s = win.settings
            if type(s) == "table" and s.open ~= false and win.frame then
                Add({
                    key = "meter:" .. tostring(win.id), group = "windows",
                    label = "Meter window " .. tostring(win.id) .. (s.display == "threat" and " (threat)" or ""),
                    size = function() return s.w or 200, s.h or 150 end,
                    current = function() return s.point or "CENTER", s.x or 0, s.y or 0 end,
                    place = function(point, x, y)
                        s.point, s.x, s.y = point, x, y
                        win.frame:ClearAllPoints()
                        win.frame:SetPoint(point, UIParent, point, x, y)
                    end,
                })
            end
        end)
    end

    -- the chat
    local cf = _G.ChatFrame1
    if cf and ns.Chat and ns.Chat.DB then
        Add({
            key = "chat", label = "Chat", group = "windows",
            size = function() return FrameSize(cf) end,
            current = function()
                local l, b = cf:GetLeft(), cf:GetBottom()
                if l and b then return "BOTTOMLEFT", l, b end
                return nil
            end,
            place = function(point, x, y)
                cf:ClearAllPoints()
                cf:SetPoint(point, UIParent, point, x, y)
                if FCF_SavePositionAndDimensions then pcall(FCF_SavePositionAndDimensions, cf) end
                local d = ns.Chat.DB()
                if d.sameSpot then
                    local l, b = cf:GetLeft(), cf:GetBottom()
                    if l and b then
                        d.spot = { x = math.floor(l * 100 + 0.5) / 100, y = math.floor(b * 100 + 0.5) / 100,
                                   w = math.floor(cf:GetWidth() * 100 + 0.5) / 100, h = math.floor(cf:GetHeight() * 100 + 0.5) / 100 }
                    end
                end
            end,
        })
    end

    -- the parts' own
    local keys = {}
    for k in pairs(extra) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
        local s = extra[k]
        Add({ key = k, label = s.label or k, group = s.group or "frames", size = s.size or function() return 100, 30 end,
              current = s.current, place = s.place, reset = s.reset, scalable = s.scalable, secure = s.secure })
    end
    return out
end

function LP.Available()
    if (ns.MOVERS and #ns.MOVERS > 0) then return true end
    if _G.ZacUF and Loaded("Zacui_UnitFrames") then return true end
    if ns.Bars and Loaded("Zacui_Bars") then return true end
    if next(extra) ~= nil then return true end
    return false
end

-- ============================================================
-- PRESETS
-- ============================================================
-- places[key] = { point, fx, fy, scale }; a key not listed is left as it
-- is. "reset = true" puts every target at its own default first.
local function P(point, fx, fy, scale) return { point = point, fx = fx, fy = fy, scale = scale } end

LP.PRESETS = {
    { id = "keep", name = "Keep mine", desc = "Nothing moves. Every frame stays exactly where it is." },
    { id = "default", name = "ZacUI default", reset = true,
      desc = "Every bar, minimap and HUD piece back at its own default spot (the frames that keep their own position - unit frames, meter windows, chat - stay where they are; Edit Mode's right-click resets those)." },
    { id = "minimal", name = "Minimal",
      desc = "One row of bars at the bottom, the frames just above them, the meter small in the corner, the chat low on the left.",
      places = {
          ["uf:player"] = P("BOTTOM", -0.11, 0.20), ["uf:target"] = P("BOTTOM", 0.11, 0.20),
          ["uf:targettarget"] = P("BOTTOM", 0.25, 0.20), ["uf:pet"] = P("BOTTOM", -0.25, 0.20),
          ["uf:party"] = P("LEFT", 0.01, 0.05), ["uf:raid"] = P("BOTTOMLEFT", 0.01, 0.30),
          ["bar:bar1"] = P("BOTTOM", 0, 0.015), ["bar:bar2"] = P("BOTTOM", 0, 0.06),
          ["bar:stance"] = P("BOTTOM", -0.2, 0.015), ["bar:pet"] = P("BOTTOM", 0, 0.105),
          ["bar:bagbar"] = P("BOTTOMRIGHT", -0.005, 0.01), ["bar:micro"] = P("BOTTOMRIGHT", -0.08, 0.01),
          ["meter:1"] = P("BOTTOMRIGHT", -0.005, 0.07), ["meter:2"] = P("BOTTOMRIGHT", -0.005, 0.26),
          ["mover:minimap"] = P("TOPRIGHT", -0.005, -0.01),
          ["chat"] = P("BOTTOMLEFT", 0.005, 0.03),
      } },
    { id = "healer", name = "Healer",
      desc = "The raid frames in the middle, just above the bars, where the eye already is; the party on the left; player and target either side of the raid; the meter and the trackers on the right.",
      places = {
          ["uf:raid"] = P("BOTTOM", 0, 0.16), ["uf:party"] = P("LEFT", 0.02, 0.0),
          ["uf:player"] = P("BOTTOM", -0.22, 0.26), ["uf:target"] = P("BOTTOM", 0.22, 0.26),
          ["uf:targettarget"] = P("BOTTOM", 0.34, 0.26), ["uf:pet"] = P("BOTTOM", -0.34, 0.26),
          ["bar:bar1"] = P("BOTTOM", 0, 0.015), ["bar:bar2"] = P("BOTTOM", 0, 0.06),
          ["meter:1"] = P("RIGHT", -0.005, -0.1), ["meter:2"] = P("BOTTOMRIGHT", -0.005, 0.02),
          ["mover:minimap"] = P("TOPRIGHT", -0.005, -0.01),
          ["chat"] = P("BOTTOMLEFT", 0.005, 0.03),
      } },
    { id = "big", name = "Big screen",
      desc = "For a large or distant screen: everything pulled in toward the middle, the bars a little bigger, so nothing sits in the far corners.",
      places = {
          ["uf:player"] = P("BOTTOM", -0.14, 0.28), ["uf:target"] = P("BOTTOM", 0.14, 0.28),
          ["uf:targettarget"] = P("BOTTOM", 0.28, 0.28), ["uf:pet"] = P("BOTTOM", -0.28, 0.28),
          ["uf:party"] = P("LEFT", 0.08, 0.05), ["uf:raid"] = P("BOTTOMLEFT", 0.08, 0.30),
          ["bar:bar1"] = P("BOTTOM", 0, 0.03, 1.15), ["bar:bar2"] = P("BOTTOM", 0, 0.085, 1.15),
          ["bar:bar3"] = P("BOTTOM", 0, 0.14, 1.15), ["bar:stance"] = P("BOTTOM", -0.22, 0.03, 1.15),
          ["bar:pet"] = P("BOTTOM", 0, 0.195, 1.15),
          ["bar:bagbar"] = P("BOTTOMRIGHT", -0.06, 0.03, 1.15), ["bar:micro"] = P("BOTTOMRIGHT", -0.14, 0.03, 1.15),
          ["meter:1"] = P("BOTTOMRIGHT", -0.06, 0.1), ["meter:2"] = P("BOTTOMRIGHT", -0.06, 0.3),
          ["mover:minimap"] = P("TOPRIGHT", -0.06, -0.04),
          ["chat"] = P("BOTTOMLEFT", 0.06, 0.06),
      } },
    { id = "small", name = "Small screen",
      desc = "For a small or low-resolution screen: everything tight to the edges and the bars a little smaller, so the middle stays clear.",
      places = {
          ["uf:player"] = P("BOTTOM", -0.12, 0.18), ["uf:target"] = P("BOTTOM", 0.12, 0.18),
          ["uf:targettarget"] = P("BOTTOM", 0.26, 0.18), ["uf:pet"] = P("BOTTOM", -0.26, 0.18),
          ["uf:party"] = P("LEFT", 0.005, 0.1), ["uf:raid"] = P("BOTTOMLEFT", 0.005, 0.28),
          ["bar:bar1"] = P("BOTTOM", 0, 0.005, 0.9), ["bar:bar2"] = P("BOTTOM", 0, 0.045, 0.9),
          ["bar:bar3"] = P("BOTTOM", 0, 0.085, 0.9), ["bar:stance"] = P("BOTTOM", -0.2, 0.005, 0.9),
          ["bar:pet"] = P("BOTTOM", 0, 0.125, 0.9),
          ["bar:bagbar"] = P("BOTTOMRIGHT", 0, 0.005, 0.9), ["bar:micro"] = P("BOTTOMRIGHT", -0.07, 0.005, 0.9),
          ["meter:1"] = P("BOTTOMRIGHT", 0, 0.06), ["meter:2"] = P("BOTTOMRIGHT", 0, 0.24),
          ["mover:minimap"] = P("TOPRIGHT", 0, 0),
          ["chat"] = P("BOTTOMLEFT", 0, 0.02),
      } },
}

function LP.Preset(id)
    for _, p in ipairs(LP.PRESETS) do if p.id == id then return p end end
    return nil
end

-- a placement for this screen: point, x, y (UIParent units), scale
function LP.Resolve(place)
    local w, h = Screen()
    return place.point or "CENTER", math.floor((place.fx or 0) * w + 0.5), math.floor((place.fy or 0) * h + 0.5), place.scale
end

-- ============================================================
-- GHOSTS: where each target would land
-- ============================================================
-- For a preset: every target with a placement (or, for the default, its
-- default spot where known; else its current spot). Returns a list of
-- { target, point, x, y, w, h, moves }.
function LP.Ghosts(id, targets)
    local preset = LP.Preset(id)
    if not preset then return {} end
    targets = targets or LP.Targets()
    local out = {}
    for _, t in ipairs(targets) do
        local pl = preset.places and preset.places[t.key]
        local point, x, y, scale
        local moves = false
        if pl then
            point, x, y, scale = LP.Resolve(pl)
            moves = true
        elseif preset.reset then
            if t.default then point, x, y = t.default() end
            if point then moves = true end
        end
        if not point and t.current then point, x, y = t.current() end
        if point then
            local w, h = t.size()
            if scale and t.scalable then
                -- size() is at the current scale: show it at the preset's
                local cur = (t.scale and t.scale()) or 1
                if cur <= 0 then cur = 1 end
                w, h = w / cur * scale, h / cur * scale
            end
            out[#out + 1] = { target = t, point = point, x = x or 0, y = y or 0, w = w, h = h, moves = moves }
        end
    end
    return out
end

local overlay, control
-- the preview never outlives a fight: watched only while it shows (made on
-- the first preview, so nothing exists until the step is used)
local watch
local function Watch(on)
    if on and not watch then
        watch = CreateFrame("Frame")
        watch:SetScript("OnEvent", function() LP.EndPreview() end)
    end
    if not watch then return end
    if on then watch:RegisterEvent("PLAYER_REGEN_DISABLED") else watch:UnregisterEvent("PLAYER_REGEN_DISABLED") end
end

local function BuildOverlay()
    overlay = CreateFrame("Frame", "ZacUILayoutGhosts", UIParent)
    overlay:SetAllPoints(UIParent)
    overlay:SetFrameStrata("FULLSCREEN")
    overlay:EnableMouse(false)
    local dim = overlay:CreateTexture(nil, "BACKGROUND")
    dim._zui_own = true
    dim:SetAllPoints()
    dim:SetTexture(FLAT)
    dim:SetVertexColor(0, 0, 0, 0.45)
    overlay.dim = dim
    overlay.ghosts = {}
    overlay:Hide()

    control = UI.Window("ZacUILayoutPreview", 300, 112, "Layout preview")
    control:SetFrameStrata("FULLSCREEN_DIALOG")
    control:ClearAllPoints()
    control:SetPoint("TOP", UIParent, "TOP", 0, -80)
    control.text = UI.Font(control, F.LABEL, { width = 260 })
    control.text:SetPoint("TOPLEFT", control, "TOPLEFT", 20, -(control.headerHeight + 12))
    control.apply = UI.Button(control, "Apply", { width = 100, onClick = function()
        local id = control.presetId
        LP.EndPreview()
        local n = LP.Apply(id)
        if control.onApplied then control.onApplied(id, n) end
    end })
    control.apply:SetPoint("BOTTOMLEFT", control, "BOTTOMLEFT", 20, 14)
    control.apply:SetActive(true)
    control.cancel = UI.Button(control, "Cancel", { width = 100, onClick = function() LP.EndPreview() end })
    control.cancel:SetPoint("LEFT", control.apply, "RIGHT", 8, 0)
    control:HookScript("OnHide", function()
        if overlay then overlay:Hide() end
    end)
end

local function Ghost(i)
    local g = overlay.ghosts[i]
    if not g then
        g = CreateFrame("Frame", nil, overlay)
        UI.Fill(g, "ui", "accent", 0.18)
        UI.Border(g, "ui", "accent")
        g._zPaint = UI.PaintBox
        g:_zPaint()
        g.label = UI.Font(g, F.SMALL, { justify = "CENTER", width = 200 })
        g.label:SetPoint("CENTER")
        g.label:SetWordWrap(false)
        overlay.ghosts[i] = g
    end
    return g
end

function LP.Preview(id, onApplied)
    local ghosts = LP.Ghosts(id)
    if #ghosts == 0 then return false end
    if not overlay then BuildOverlay() end
    for i, gh in ipairs(ghosts) do
        local g = Ghost(i)
        g:ClearAllPoints()
        g:SetSize(math.max(12, gh.w), math.max(8, gh.h))
        g:SetPoint(gh.point, UIParent, gh.point, gh.x, gh.y)
        g.label:SetText(gh.target.label)
        g.label:SetWidth(math.max(40, gh.w - 4))
        g:SetAlpha(gh.moves and 1 or 0.45)
        g:Show()
    end
    for i = #ghosts + 1, #overlay.ghosts do overlay.ghosts[i]:Hide() end
    local preset = LP.Preset(id)
    control.presetId = id
    control.onApplied = onApplied
    control.text:SetText((preset and preset.name or id) .. ": the lit boxes are where things land. Nothing has moved yet.")
    overlay:Show()
    UI.OpenWindow(control)
    Watch(true)
    return true
end

function LP.EndPreview()
    Watch(false)
    if overlay then overlay:Hide() end
    if control and control:IsShown() then UI.CloseWindow(control) end
end

function LP.PreviewShown()
    return overlay ~= nil and overlay:IsShown()
end

-- ============================================================
-- APPLY
-- ============================================================
-- Every target with a placement goes to it through its own place();
-- with reset, every target goes to its own default first. Secure targets
-- in combat are left for after the fight (their own place() queues).
-- Returns how many were placed.
function LP.Apply(id)
    local preset = LP.Preset(id)
    if not preset or id == "keep" then return 0 end
    local targets = LP.Targets()
    local n = 0
    for _, t in ipairs(targets) do
        local pl = preset.places and preset.places[t.key]
        if preset.reset and t.reset then
            local ok = pcall(t.reset)
            if ok then n = n + 1 end
        end
        if pl and t.place and not (t.secure and InCombat()) then
            local point, x, y, scale = LP.Resolve(pl)
            local ok, err = pcall(t.place, point, x, y, t.scalable and scale or nil)
            if ok then n = n + 1 elseif Print then Print("layout: " .. t.label .. ": " .. tostring(err)) end
        end
    end
    if ns.Hints then
        ns.Hints.Say("layout_applied", "A layout was applied. Every frame can still be dragged: /zui edit shows them all over a grid.")
    end
    return n
end

-- ============================================================
-- THE STEP
-- ============================================================
-- ctx: note(key, text), needsReload(key, label), pageW, pad, canvas(parent, w, h)
function LP.BuildStep(host, y, ctx)
    local x = ctx.pad or 16
    local pageW = ctx.pageW or 520
    local chosen = "keep"
    local targets = LP.Targets()

    -- the thumbnail: the screen in miniature with the ghost boxes
    local TW = 240
    local sw, sh = Screen()
    local TH = math.floor(TW * sh / sw + 0.5)
    local thumb = ctx.canvas(host, TW, TH)
    thumb:SetPoint("TOPRIGHT", host, "TOPRIGHT", -x, y)
    host.layoutThumb = thumb
    local function DrawThumb()
        thumb:Reset()
        local k = TW / sw
        for _, gh in ipairs(LP.Ghosts(chosen, targets)) do
            -- the box's bottom-left on screen, from its anchor point
            local l, b
            local p = gh.point
            local w, h = gh.w * k, gh.h * k
            local ax = p:find("LEFT") and 0 or p:find("RIGHT") and TW or TW / 2
            local ay = p:find("TOP") and TH or p:find("BOTTOM") and 0 or TH / 2
            local px, py = ax + gh.x * k, ay + gh.y * k
            if p:find("LEFT") then l = px elseif p:find("RIGHT") then l = px - w else l = px - w / 2 end
            if p:find("TOP") then b = py - h elseif p:find("BOTTOM") then b = py else b = py - h / 2 end
            l = math.max(0, math.min(TW - w, l))
            b = math.max(0, math.min(TH - h, b))
            thumb:Rect(l, TH - b - h, math.max(2, w), math.max(2, h), "ui", "accent", gh.moves and 0.7 or 0.3)
        end
        thumb:_zPaint()
    end

    local wide = pageW - 2 * x - TW - 16
    local lbl = UI.Font(host, F.LABEL, { text = "Layout", cat = "text", key = "gold" })
    lbl:SetPoint("TOPLEFT", host, "TOPLEFT", x, y)
    y = y - 18
    local descFs = UI.Font(host, F.DESC, { cat = "text", key = "gray", width = wide })
    local function Describe()
        local p = LP.Preset(chosen)
        local n = 0
        for _, gh in ipairs(LP.Ghosts(chosen, targets)) do if gh.moves then n = n + 1 end end
        descFs:SetText((p and p.desc or "") .. (chosen ~= "keep" and (" Moves " .. n .. " of " .. #targets .. " frames.") or ""))
    end
    local dd = UI.Dropdown(host, { width = 220,
        items = function()
            local out = {}
            for _, p in ipairs(LP.PRESETS) do out[#out + 1] = { text = p.name, value = p.id } end
            return out
        end,
        selected = function() local p = LP.Preset(chosen) return p and p.name or chosen end,
        onSelect = function(v) chosen = v Describe() DrawThumb() end })
    dd:SetPoint("TOPLEFT", host, "TOPLEFT", x, y)
    host.layoutDropdown = dd
    y = y - M.DROPDOWN_H - 8
    descFs:SetPoint("TOPLEFT", host, "TOPLEFT", x, y)
    Describe()
    y = y - math.max(26, (descFs:GetStringHeight() or 12) + 2) - 10

    local function Applied(id, n)
        local p = LP.Preset(id)
        ctx.note("layout", "Layout: " .. (p and p.name or id) .. " (" .. n .. " frames placed)")
        if host.layoutStatus then host.layoutStatus:SetText((p and p.name or id) .. " applied: " .. n .. " frames placed.") end
        DrawThumb()
    end
    local preview = UI.Button(host, "Preview on screen", { width = 140,
        tooltip = "Dims the world and shows a box where every frame would land. Nothing moves until you apply.",
        onClick = function()
            if chosen == "keep" then Print("Keep mine moves nothing - there is nothing to preview.") return end
            if not LP.Preview(chosen, Applied) then Print("Nothing to preview on this install.") end
        end })
    preview:SetPoint("TOPLEFT", host, "TOPLEFT", x, y)
    host.layoutPreview = preview
    local apply = UI.Button(host, "Apply", { width = 90,
        tooltip = "Moves every frame the layout names. Each frame can still be dragged afterwards.",
        onClick = function()
            if chosen == "keep" then Print("Keep mine: every frame stays where it is.") return end
            if InCombat() then Print("Layouts apply after combat.") return end
            LP.EndPreview()
            Applied(chosen, LP.Apply(chosen))
        end })
    apply:SetPoint("LEFT", preview, "RIGHT", 8, 0)
    host.layoutApply = apply
    y = y - M.BUTTON_H - 10
    host.layoutStatus = UI.Font(host, F.DESC, { cat = "text", key = "gray", width = wide })
    host.layoutStatus:SetPoint("TOPLEFT", host, "TOPLEFT", x, y)
    y = y - 28
    local names = {}
    for _, t in ipairs(targets) do names[#names + 1] = t.label end
    local list = UI.Font(host, F.DESC, { cat = "text", key = "gray", width = wide,
        text = "On this install a layout can place: " .. (#names > 0 and table.concat(names, ", ") or "nothing yet") .. "." })
    list:SetPoint("TOPLEFT", host, "TOPLEFT", x, y)
    host.layoutTargets = targets
    DrawThumb()
end


-- shared with later ZacUI files
ns.LayoutPresets = LP
