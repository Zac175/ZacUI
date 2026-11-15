-- ============================================================================
-- Zacui_UnitFrames - MissingBuffs.lua
-- Small icons on each party / raid cell for the buffs YOU can give that the
-- unit lacks: a mage sees Arcane Intellect on the casters without it, a
-- priest Fortitude, a druid the Mark, a warrior Battle Shout on their own
-- party. The buff families are the buff reminders' (Zacui_BuffReminders,
-- ns.BuffRem: who gives what, who wants it, who it reaches); without that
-- part loaded there is nothing to show and the setting says so.
--
-- OFF until switched on, per group (Unit frames > Look, with Party or Raid
-- picked: cfg.missingBuffs, nil = off), so a cell without it is built,
-- styled and laid out exactly as before - nothing here runs for it beyond
-- a nil check. Size, corner and how many icons at most are settings; the
-- preview's sample party and raid wear them, worked out from the samples'
-- own buffs.
--
-- Wired in from the outside like Portrait.lua: this file wraps
-- ns.StyleElements (the holder laid out) and the preview's Fill (the
-- samples), so Elements.lua is not touched. The holder is a plain child
-- frame made out of combat the first time a cell is styled with the
-- feature on; in combat only its textures are shown or hidden.
--
-- COST: nothing per aura. UNIT_AURA only marks the unit; a half-second
-- ticker (only while the feature is on somewhere) repaints the marked
-- cells, and every few seconds all of them (raid tokens move). Each
-- repaint is one buff loop for the unit.
--
-- SECRET-SAFE (WoW Forever): the buffs are read through UnitBuff, or the
-- shared reader ns.ReadAura where UnitBuff is gone; a hidden name or
-- field means the answer is not known, and a cell shows nothing then.
-- ============================================================================
local ADDON, ns = ...

local OWN_ID = "uf_missing_buffs"
local ICON_FALLBACK = "Interface\\Icons\\INV_Misc_QuestionMark"

local MB = {}
ns.MissingBuffs = MB

MB.DEFAULTS = { size = 14, limit = 3, point = "TOPRIGHT" }
MB.POINTS = {
    { value = "TOPRIGHT", text = "Top right" },
    { value = "TOPLEFT", text = "Top left" },
    { value = "BOTTOMRIGHT", text = "Bottom right" },
    { value = "BOTTOMLEFT", text = "Bottom left" },
    { value = "CENTER", text = "Centre" },
}
local POINT_OK = {}
for _, p in ipairs(MB.POINTS) do POINT_OK[p.value] = true end

local function Z() return _G.ZacUI end
local function BR()
    local z = Z()
    return z and z.BuffRem
end
local function Hidden(v)
    local z = Z()
    if z and z.IsSecret then return z.IsSecret(v) end
    if issecretvalue ~= nil then return issecretvalue(v) and true or false end
    return false
end
local function FeatureOn()
    local z = Z()
    if z and z.FeatureOn and not z.FeatureOn(OWN_ID) then return false end
    return true
end

-- a group's settings, when it has any and they say on (read: nothing written)
local function Settings(cfg)
    local s = type(cfg) == "table" and cfg.missingBuffs
    if type(s) ~= "table" or not s.enabled then return nil end
    if not FeatureOn() then return nil end
    return s
end
MB.Settings = Settings
function MB.Size(s) return math.max(8, math.min(28, tonumber(s and s.size) or MB.DEFAULTS.size)) end
function MB.Limit(s) return math.max(1, math.min(8, math.floor(tonumber(s and s.limit) or MB.DEFAULTS.limit))) end
function MB.Point(s) local p = s and s.point return POINT_OK[p] and p or MB.DEFAULTS.point end

-- ----------------------------------------------------------------------------
-- What is missing
-- ----------------------------------------------------------------------------
-- the buffs this character gives that could matter on a cell: the
-- reminders' families, minus "chosen" ones not chosen for this unit
local function Candidates(unit, sample)
    local br = BR()
    if not (br and br.MyBuffs) then return {} end
    local out = {}
    for _, def in ipairs(br.MyBuffs()) do
        local want = true
        if def.reach == "chosen" then
            want = false
            if not sample and br.Listed then
                local ok, listed = pcall(br.Listed, def, unit)
                want = ok and listed and true or false
            end
        elseif def.reach == "party" and not sample then
            -- your own party only (a raid subgroup)
            if br.Subgroup and unit ~= "player" then
                local ok, mine = pcall(br.Subgroup, "player")
                local ok2, theirs = pcall(br.Subgroup, unit)
                want = ok and ok2 and mine == theirs
            end
        end
        if want then out[#out + 1] = def end
    end
    return out
end
MB.Candidates = Candidates

-- the names of a unit's buffs (a set), or nil when the game hides them
local function UnitBuffNames(unit)
    local names = {}
    local fn = _G.UnitBuff
    if fn then
        for i = 1, 40 do
            local ok, name = pcall(fn, unit, i)
            if not ok then return nil end
            if name == nil then break end
            if Hidden(name) then return nil end
            names[name] = true
        end
        return names
    end
    local z = Z()
    if not (z and z.ReadAura) then return nil end
    for i = 1, 40 do
        local a = z.ReadAura(unit, i, "HELPFUL")
        if a == false then return nil end
        if not a then break end
        if (z.AuraFieldsHidden and z.AuraFieldsHidden(a)) or Hidden(a.name) then return nil end
        if a.name then names[a.name] = true end
    end
    return names
end
MB.UnitBuffNames = UnitBuffNames

local function ClassOf(unit)
    if not UnitClass then return nil end
    local ok, _, cls = pcall(UnitClass, unit)
    if not ok or Hidden(cls) then return nil end
    return cls
end

-- the icons a unit should show (a list of textures), or nil when unknown
function MB.Missing(unit, s)
    local br = BR()
    if not br then return nil end
    if not (UnitExists and UnitExists(unit)) then return nil end
    local okD, dead = pcall(UnitIsDeadOrGhost, unit)
    if not okD or Hidden(dead) or dead then return nil end
    if UnitIsConnected then
        local okC, on = pcall(UnitIsConnected, unit)
        if not okC or Hidden(on) or not on then return nil end
    end
    local cls = ClassOf(unit)
    local names = UnitBuffNames(unit)
    if not names then return nil end
    local out, limit = {}, MB.Limit(s)
    for _, def in ipairs(Candidates(unit, false)) do
        if (not def.classes) or (cls and def.classes[cls]) then
            local has = false
            for n in pairs(br.BuffNames(def)) do if names[n] then has = true break end end
            if not has then
                out[#out + 1] = (br.Icon_ and br.Icon_(def)) or def.icon or ICON_FALLBACK
                if #out >= limit then break end
            end
        end
    end
    return out
end

-- the same for a preview sample (its own buff list and class)
function MB.MissingSample(d, s)
    local br = BR()
    if not (br and type(d) == "table") then return {} end
    if d.status == "Dead" or d.online == false then return {} end
    local names = {}
    for _, a in ipairs(d.buffs or {}) do if a.name then names[a.name] = true end end
    local out, limit = {}, MB.Limit(s)
    for _, def in ipairs(Candidates(nil, true)) do
        if (not def.classes) or (d.class and def.classes[d.class]) then
            local has = false
            for n in pairs(br.BuffNames(def)) do if names[n] then has = true break end end
            if not has then
                out[#out + 1] = (br.Icon_ and br.Icon_(def)) or def.icon or ICON_FALLBACK
                if #out >= limit then break end
            end
        end
    end
    return out
end

-- ----------------------------------------------------------------------------
-- The icons on a cell
-- ----------------------------------------------------------------------------
local function Holder(frame, make)
    local h = rawget(frame, "MissingBuffs")
    if h or not make then return h end
    if InCombatLockdown and InCombatLockdown() and not frame.isPreview then return nil end
    h = CreateFrame("Frame", nil, frame)
    h:SetFrameLevel((frame:GetFrameLevel() or 1) + 12)
    h:EnableMouse(false)
    h.icons = {}
    frame.MissingBuffs = h
    return h
end

local function Layout(frame, s)
    local h = Holder(frame, s ~= nil)
    if not h then return end
    if not s then h:Hide() return end
    local size, point = MB.Size(s), MB.Point(s)
    local limit = MB.Limit(s)
    -- right-hand corners grow to the left, the rest to the right
    local dir = point:find("RIGHT") and -1 or 1
    local inset = 2
    h:ClearAllPoints()
    h:SetSize(limit * (size + 1), size)
    local ox = (point == "CENTER") and 0 or (dir < 0 and -inset or inset)
    local oy = point:find("TOP") and -inset or (point:find("BOTTOM") and inset or 0)
    h:SetPoint(point, frame, point, ox, oy)
    for i = 1, limit do
        local t = h.icons[i]
        if not t then
            t = h:CreateTexture(nil, "OVERLAY")
            ZacUI.Look.CropIcon(t)
            h.icons[i] = t
        end
        t:SetSize(size, size)
        t:ClearAllPoints()
        local anchor = (dir < 0) and "RIGHT" or "LEFT"
        t:SetPoint(anchor, h, anchor, dir * (i - 1) * (size + 1), 0)
    end
    for i = limit + 1, #h.icons do h.icons[i]:Hide() end
    h._limit = limit
    h:Show()
end
MB.Layout = Layout

local function Paint(frame, list)
    local h = rawget(frame, "MissingBuffs")
    if not h then return end
    local n = 0
    for i = 1, (h._limit or 0) do
        local t = h.icons[i]
        local tex = list and list[i]
        if t then
            if tex then t:SetTexture(tex) t:Show() n = n + 1 else t:Hide() end
        end
    end
    h._shown = n
end
MB.Paint = Paint

-- ----------------------------------------------------------------------------
-- Live cells
-- ----------------------------------------------------------------------------
local dirty, sweepAt = {}, 0
local ticker, ev

local function GroupCells(fn)
    for f in pairs(ns.unitButtons or {}) do
        if f.isGroupUnit then fn(f) end
    end
end

function MB.RefreshCell(f)
    local s = Settings(f.cfg)
    if not s then
        local h = rawget(f, "MissingBuffs")
        if h then h:Hide() end
        return
    end
    if not rawget(f, "MissingBuffs") then Layout(f, s) end
    local unit = f.unit
    if not (unit and f.IsVisible and f:IsVisible()) then Paint(f, nil) return end
    local ok, list = pcall(MB.Missing, unit, s)
    Paint(f, ok and list or nil)
end

local function AnyOn()
    if not FeatureOn() then return false end
    local db = ns.db
    if not db then return false end
    return Settings(db.party) ~= nil or Settings(db.raid) ~= nil
end
MB.AnyOn = AnyOn

local function Tick()
    local now = GetTime()
    local all = now >= sweepAt
    if all then sweepAt = now + 4 end
    GroupCells(function(f)
        if all or (f.unit and dirty[f.unit]) then MB.RefreshCell(f) end
    end)
    wipe(dirty)
end
MB.Tick = Tick

-- on / off: the ticker and the two events only while some group wants it
function MB.Apply()
    local on = AnyOn()
    if on then
        if not ev then
            ev = CreateFrame("Frame")
            ev:SetScript("OnEvent", function(_, event, unit)
                if event == "UNIT_AURA" then
                    if unit then dirty[unit] = true end
                else
                    sweepAt = 0   -- the roster or the spellbook changed: all of them next tick
                end
            end)
        end
        ev:RegisterEvent("UNIT_AURA")
        ev:RegisterEvent("GROUP_ROSTER_UPDATE")
        pcall(ev.RegisterEvent, ev, "SPELLS_CHANGED")
        pcall(ev.RegisterEvent, ev, "PLAYER_REGEN_ENABLED")
        if not ticker then
            ticker = C_Timer.NewTicker(0.5, Tick)
            local z = Z()
            if z and z.Profiler and z.Profiler.TrackTicker then z.Profiler.TrackTicker(ticker, "UF.missingBuffs") end
        end
        sweepAt = 0
    else
        if ev then ev:UnregisterAllEvents() end
        if ticker then ticker:Cancel() ticker = nil end
        wipe(dirty)
    end
    -- every cell laid out (or put away) for its group's settings
    if not (InCombatLockdown and InCombatLockdown()) then
        GroupCells(function(f)
            local s = Settings(f.cfg)
            if s or rawget(f, "MissingBuffs") then Layout(f, s) end
            if not s then Paint(f, nil) end
        end)
    end
end
MB.Running = function() return ticker ~= nil end

-- ----------------------------------------------------------------------------
-- On top of Elements.lua and Preview.lua
-- ----------------------------------------------------------------------------
do
    local style = ns.StyleElements
    if style then
        ns.StyleElements = function(frame, ...)
            style(frame, ...)
            local s = Settings(frame.cfg)
            if s or rawget(frame, "MissingBuffs") then Layout(frame, s) end
        end
    end
    local PV = ns.UFPreview
    if PV and PV.Fill then
        local fill = PV.Fill
        PV.Fill = function(f, d, ...)
            fill(f, d, ...)
            local s = Settings(f.cfg)
            if s then
                Layout(f, s)
                Paint(f, MB.MissingSample(d, s))
            elseif rawget(f, "MissingBuffs") then
                Paint(f, nil)
                rawget(f, "MissingBuffs"):Hide()
            end
        end
    end
end

-- started with the group frames (each header's spawn), and on every
-- settings change; with the feature off neither makes anything
do
    local spawn = ns.SpawnHeader
    if spawn then
        ns.SpawnHeader = function(kind, ...)
            local r = spawn(kind, ...)
            if kind == "party" or kind == "raid" then pcall(MB.Apply) end
            return r
        end
    end
    local z = Z()
    if z and z.OnSettingsChanged then z.OnSettingsChanged(function() if ns.db then pcall(MB.Apply) end end) end
end

-- ----------------------------------------------------------------------------
-- The setting: Unit frames > Look, with Party or Raid picked
-- ----------------------------------------------------------------------------
local function CurrentKind()
    local z = Z()
    local st = z and z.ConfigState and z.ConfigState()
    local m = st and st.preview and st.preview.modes
    local v = m and m["unitframes.frames"]
    if v == "party" or v == "raid" then return v end
    return nil
end

do
    local z = Z()
    local function AddTab(page, tab, label, build)
        if z and z.AddPageTab then return z.AddPageTab(page, tab, label, build) end
        if not z then return end
        z.PageTabs = z.PageTabs or {}
        local list = z.PageTabs[page] or {}
        z.PageTabs[page] = list
        list[#list + 1] = { tab = tab, label = label, build = build }
    end
    AddTab("unitframes", "look", "Look", function(L)
        if not FeatureOn() or not ns.db then return end
        local kind = CurrentKind()
        if not kind then return end
        local UI = z.UI
        local cfg = ns.db[kind]
        if type(cfg) ~= "table" then return end
        local s = type(cfg.missingBuffs) == "table" and cfg.missingBuffs or {}
        local function W()
            if type(cfg.missingBuffs) ~= "table" then cfg.missingBuffs = {} end
            return cfg.missingBuffs
        end
        local function Changed()
            pcall(MB.Apply)
            if z.RefreshConfig then z.RefreshConfig() end
        end
        L:Card("Buffs you can give that are missing")
        local br = BR()
        if not br then
            L:Desc("Needs ZacUI's buff reminders part (Zacui_BuffReminders): it knows who gives which buff.")
            L:EndCard()
            return
        end
        local on = UI.Checkbox(L.current, "Show them on each " .. (kind == "raid" and "raid" or "party") .. " frame",
            s.enabled == true, function(v)
                W().enabled = v or nil
                Changed()
            end, { tooltip = "A small icon for each of your buffs a member lacks (the ones your class gives: "
                .. "Fortitude, Arcane Intellect, the Mark, Battle Shout on your own party...). "
                .. "Thorns and Soulstones only on the people you picked for them." })
        L:Row(on, 17)
        local kids = {}
        kids[#kids + 1] = UI.Slider(L.current, { width = 220, min = 8, max = 28, step = 1,
            value = MB.Size(s), label = "Icon size", format = function(v) return v .. " px" end,
            onChange = function(v) W().size = (v ~= MB.DEFAULTS.size) and v or nil Changed() end })
        kids[#kids + 1] = UI.Slider(L.current, { width = 220, min = 1, max = 8, step = 1,
            value = MB.Limit(s), label = "Icons at most",
            onChange = function(v) W().limit = (v ~= MB.DEFAULTS.limit) and v or nil Changed() end })
        kids[#kids + 1] = UI.Field(L.current, "Corner", function(h)
            return UI.Dropdown(h, { width = 160,
                items = function() return MB.POINTS end,
                selectedValue = function() return MB.Point(s) end,
                selected = function()
                    for _, p in ipairs(MB.POINTS) do if p.value == MB.Point(s) then return p.text end end
                    return MB.POINTS[1].text
                end,
                onSelect = function(v) W().point = (v ~= MB.DEFAULTS.point) and v or nil Changed() end })
        end, { width = 160 })
        L:Dependent(kids, s.enabled == true, 1, nil, "Show them on each " .. (kind == "raid" and "raid" or "party") .. " frame")
        local mine = br.MyBuffs and br.MyBuffs() or {}
        if #mine == 0 then
            L:Desc("This character gives no group buffs, so there is nothing to show.")
        else
            local labels = {}
            for _, def in ipairs(mine) do labels[#labels + 1] = def.label end
            L:Desc("Yours: " .. table.concat(labels, ", ") .. ". The preview's samples show them.")
        end
        L:EndCard()
    end)
    if z and z.AddMenuKeywords then
        z.AddMenuKeywords("unitframes", "missing buffs buff icons raid party fortitude intellect mark shout")
    end
end
