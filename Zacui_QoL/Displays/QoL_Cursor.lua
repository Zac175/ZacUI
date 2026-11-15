-- QoL_Cursor - rings around your mouse cursor, so you never lose it in a
-- fight (and viewers on a stream can follow it):
--   Circle       a ring round the cursor (size, weight, colour, opacity)
--   GCD ring     a ring just outside it that sweeps while the global
--                cooldown runs
--   Cast ring    a ring outside that, sweeping while you cast or channel
-- Each its own switch, all off by default; shown always, only in combat,
-- or only inside dungeons and raids. Quality of life > On screen.
-- Part of ZacUI; load order is set by the TOC.
--
-- THE ART is ZacUI's own: three white ring weights drawn for this
-- (Zacui_QoL\Media\cursor_ring*.tga), tinted in the game. The sweeps are
-- the game's own cooldown swipe drawn through the ring texture, so they
-- are smooth at any frame rate and cost nothing to animate.
--
-- FOLLOWING THE CURSOR: one OnUpdate on the holder, only while a ring is
-- shown, moving it only when the cursor moved; hidden while the cursor is
-- hidden (holding the right button to turn the camera).
--
-- THE GCD AND CASTS are read when you cast (the player's own cast events,
-- one read each), never in a cooldown event. WoW Forever may hide the
-- cooldown in a fight: a hidden start / duration is handed to the swipe
-- as it is (the game draws it); a cast whose times are hidden shows no
-- cast ring (its start would need sums).
--
-- COST: nothing while off. On: the holder's OnUpdate while shown (two
-- reads a frame) and a handful of the player's own cast events.

local ADDON_NAME = ...
local ns = _G.ZacUI
if not ns then return end

local GetColor = ns.GetColor
local QoL = ns.QoL
if not QoL then return end

local CU = {}
QoL.Cursor = CU

local OWN_ID = "qol_cursor"
local MEDIA = "Interface\\AddOns\\Zacui_QoL\\Media\\"
CU.WEIGHTS = {
    { value = "thin", text = "Thin", tex = MEDIA .. "cursor_ring_thin" },
    { value = "normal", text = "Normal", tex = MEDIA .. "cursor_ring" },
    { value = "thick", text = "Thick", tex = MEDIA .. "cursor_ring_thick" },
}
CU.SHOW = {
    { value = "always", text = "Always" },
    { value = "combat", text = "Only in combat" },
    { value = "instance", text = "Only in dungeons and raids" },
}
CU.COLORS = {
    { value = "class", text = "My class colour" },
    { value = "accent", text = "ZacUI's accent" },
    { value = "custom", text = "A colour of my own" },
}
-- each ring: its size, weight, colour and opacity when nothing is saved
CU.RINGS = {
    { id = "circle", label = "Circle", size = 28, weight = "normal", color = "class", alpha = 0.8 },
    { id = "gcd", label = "GCD ring", size = 40, weight = "thin", color = "custom", alpha = 0.9, rgb = { 1, 1, 1 } },
    { id = "cast", label = "Cast ring", size = 52, weight = "thin", color = "custom", alpha = 0.9, rgb = { 1, 0.82, 0.24 } },
}
CU.BY_ID = {}
for _, r in ipairs(CU.RINGS) do CU.BY_ID[r.id] = r end

local function Hidden(v) return ns.IsSecret and ns.IsSecret(v) or false end

-- ============================================================
-- SETTINGS (qol.cursor.<ring>; nothing saved = off)
-- ============================================================
local function DB()
    local q = QoL.DB()
    if type(q.cursor) ~= "table" then q.cursor = {} end
    return q.cursor
end
CU.DB = DB
local function RingDB(id)
    local d = DB()
    if type(d[id]) ~= "table" then d[id] = {} end
    return d[id]
end
local function Peek(id) local d = DB() return type(d[id]) == "table" and d[id] or {} end
CU.RingDB = RingDB
local function Allowed() return not (ns.FeatureOn and not ns.FeatureOn(OWN_ID)) end
function CU.RingOn(id) return Allowed() and QoL.enabled == true and Peek(id).enabled == true end
function CU.AnyOn() for _, r in ipairs(CU.RINGS) do if CU.RingOn(r.id) then return true end end return false end
function CU.ShowMode() return DB().show or "always" end

function CU.Size(id)
    local v = tonumber(Peek(id).size) or CU.BY_ID[id].size
    return math.max(12, math.min(160, v))
end
function CU.Alpha(id)
    local v = tonumber(Peek(id).alpha) or CU.BY_ID[id].alpha
    return math.max(0.1, math.min(1, v))
end
function CU.Weight(id) return Peek(id).weight or CU.BY_ID[id].weight end
function CU.Texture(id)
    local w = CU.Weight(id)
    for _, e in ipairs(CU.WEIGHTS) do if e.value == w then return e.tex end end
    return CU.WEIGHTS[2].tex
end
function CU.ColorMode(id) return Peek(id).color or CU.BY_ID[id].color end
function CU.Color(id)
    local mode = CU.ColorMode(id)
    if mode == "class" and UnitClass then
        local file = select(2, UnitClass("player"))
        local c = file and RAID_CLASS_COLORS and RAID_CLASS_COLORS[file]
        if c then return c.r, c.g, c.b end
    elseif mode == "accent" then
        local c = GetColor("ui", "accent")
        return c.r, c.g, c.b
    end
    local c = Peek(id).rgb
    if type(c) == "table" and ns.ColorOf then return ns.ColorOf(c) end
    local def = CU.BY_ID[id].rgb or { 1, 1, 1 }
    return def[1], def[2], def[3]
end

-- ============================================================
-- THE RINGS
-- ============================================================
local holder
local parts = {}     -- id -> the circle texture, or the GCD / cast cooldown frame

local function MakeSweep(id)
    local cd = CreateFrame("Cooldown", nil, holder, "CooldownFrameTemplate")
    cd:SetPoint("CENTER")
    if cd.SetDrawEdge then cd:SetDrawEdge(false) end
    if cd.SetDrawBling then cd:SetDrawBling(false) end
    if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end
    if cd.SetUseCircularEdge then cd:SetUseCircularEdge(true) end
    if cd.SetReverse then cd:SetReverse(true) end
    cd.noCooldownCount = true      -- other addons' cooldown numbers left off
    cd:EnableMouse(false)
    return cd
end

local function Holder()
    if holder then return holder end
    holder = CreateFrame("Frame", "ZacUICursorRings", UIParent)
    holder:SetSize(1, 1)
    holder:SetFrameStrata("TOOLTIP")
    holder:EnableMouse(false)
    holder:Hide()
    local tex = holder:CreateTexture(nil, "OVERLAY")
    tex:SetPoint("CENTER")
    parts.circle = tex
    parts.gcd = MakeSweep("gcd")
    parts.cast = MakeSweep("cast")
    local lastX, lastY
    holder:SetScript("OnUpdate", function(self)
        if IsMouselooking and IsMouselooking() then
            if not self._zLook then self._zLook = true self:SetAlpha(0) end
            return
        elseif self._zLook then
            self._zLook = nil
            self:SetAlpha(1)
        end
        local x, y = GetCursorPosition()
        if x == lastX and y == lastY then return end
        lastX, lastY = x, y
        local s = UIParent:GetEffectiveScale()
        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / s, y / s)
    end)
    return holder
end
CU.Frame = function() return holder end
CU.Part = function(id) return parts[id] end

local function Style()
    if not holder then return end
    for _, r in ipairs(CU.RINGS) do
        local p = parts[r.id]
        local size = CU.Size(r.id)
        local cr, cg, cb = CU.Color(r.id)
        local a = CU.Alpha(r.id)
        p:SetSize(size, size)
        if r.id == "circle" then
            p:SetTexture(CU.Texture(r.id))
            p:SetVertexColor(cr, cg, cb, a)
            p:SetShown(CU.RingOn(r.id))
        else
            if p.SetSwipeTexture then p:SetSwipeTexture(CU.Texture(r.id)) end
            if p.SetSwipeColor then p:SetSwipeColor(cr, cg, cb, a) end
            if not CU.RingOn(r.id) then p:Hide() end
        end
    end
end
CU.Style = Style

-- ============================================================
-- GCD AND CASTS
-- ============================================================
local function GCD()
    local id = ns.GCDSpell and ns.GCDSpell() or 61304
    if C_Spell and type(C_Spell.GetSpellCooldown) == "function" then
        local info = C_Spell.GetSpellCooldown(id)
        if type(info) == "table" then return info.startTime, info.duration end
        return nil
    end
    if type(GetSpellCooldown) == "function" then return GetSpellCooldown(id) end
    return nil
end

function CU.ReadGCD()
    if not CU.RingOn("gcd") or not holder then return false end
    local cd = parts.gcd
    local st, du = GCD()
    if Hidden(st) or Hidden(du) then
        -- hidden in a fight (Forever): the game's own swipe draws it
        cd:Show()
        return pcall(cd.SetCooldown, cd, st, du)
    end
    st, du = tonumber(st), tonumber(du)
    if st and du and du > 0 and du <= 2 then
        cd:Show()
        cd:SetCooldown(st, du)
        return true
    end
    return false
end

function CU.ReadCast()
    if not CU.RingOn("cast") or not holder then return false end
    local cd = parts.cast
    local s, e
    if UnitCastingInfo then s, e = select(4, UnitCastingInfo("player")) end
    if not s and UnitChannelInfo then s, e = select(4, UnitChannelInfo("player")) end
    if s == nil or e == nil or Hidden(s) or Hidden(e) then
        if cd.Clear then cd:Clear() else cd:SetCooldown(0, 0) end
        cd:Hide()
        return false
    end
    cd:Show()
    cd:SetCooldown(s / 1000, (e - s) / 1000)
    return true
end

-- ============================================================
-- WHEN THEY SHOW
-- ============================================================
function CU.ShouldShow()
    if not CU.AnyOn() then return false end
    local mode = CU.ShowMode()
    if mode == "combat" then return (InCombatLockdown and InCombatLockdown()) and true or false end
    if mode == "instance" then
        local inside, kind
        if IsInInstance then inside, kind = IsInInstance() end
        return (inside and (kind == "party" or kind == "raid")) and true or false
    end
    return true
end

function CU.Update()
    if not CU.ShouldShow() then
        if holder then holder:Hide() end
        return false
    end
    Holder()
    Style()
    holder:Show()
    return true
end

local ev
local CAST_EVENTS = { "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_DELAYED",
    "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_CHANNEL_UPDATE" }

local function OnEvent(_, event)
    if event == "PLAYER_REGEN_DISABLED" then C_Timer.After(0, CU.Update) return end
    if event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        CU.Update()
        return
    end
    if not (holder and holder:IsShown()) then return end
    if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_SUCCEEDED" or event == "UNIT_SPELLCAST_CHANNEL_START" then
        -- the cooldown is set a moment after the cast event
        C_Timer.After(0, CU.ReadGCD)
    end
    CU.ReadCast()
end

function CU.Apply()
    if not CU.AnyOn() then
        if ev then ev:UnregisterAllEvents() end
        if holder then holder:Hide() end
        return
    end
    if not ev then
        ev = CreateFrame("Frame")
        ev:SetScript("OnEvent", OnEvent)
    end
    ev:RegisterEvent("PLAYER_REGEN_DISABLED")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    local want = CU.RingOn("gcd") or CU.RingOn("cast")
    for _, e in ipairs(CAST_EVENTS) do
        if want then
            if ev.RegisterUnitEvent then pcall(ev.RegisterUnitEvent, ev, e, "player") else pcall(ev.RegisterEvent, ev, e) end
        else
            pcall(ev.UnregisterEvent, ev, e)
        end
    end
    CU.Update()
end
function CU.Registered(e) return ev ~= nil and ev:IsEventRegistered(e) or false end

local function Live() if QoL.enabled then CU.Apply() end end
CU.Live = Live
if Allowed() then
    local base = QoL.EnableAutomation
    function QoL.EnableAutomation(...)
        if base then base(...) end
        pcall(CU.Apply)
    end
end

-- ============================================================
-- THE PAGE: Quality of life > On screen
-- ============================================================
local function AddTab(page, tab, label, build)
    if ns.AddPageTab then return ns.AddPageTab(page, tab, label, build) end
    ns.PageTabs = ns.PageTabs or {}
    local l = ns.PageTabs[page] or {}
    ns.PageTabs[page] = l
    l[#l + 1] = { tab = tab, label = label, build = build }
end

local function Pick(L, label, list, get, set, width)
    local UI = ns.UI
    return UI.Field(L.current, label, function(h)
        return UI.Dropdown(h, { width = width or 160,
            items = function() return list end,
            selectedValue = get,
            selected = function()
                for _, m in ipairs(list) do if m.value == get() then return m.text end end
                return list[1].text
            end,
            onSelect = set })
    end, { width = width or 160 })
end

-- the page's sample: the three rings as they look, still
local function Sample(L)
    local UI = ns.UI
    local box = UI.Holder(L.current)
    box:SetSize(80, 80)
    for i = #CU.RINGS, 1, -1 do
        local r = CU.RINGS[i]
        local t = box:CreateTexture(nil, "ARTWORK", nil, i)
        t:SetPoint("CENTER", box, "CENTER")
        local size = math.min(76, CU.Size(r.id))
        t:SetSize(size, size)
        t:SetTexture(CU.Texture(r.id))
        local cr, cg, cb = CU.Color(r.id)
        t:SetVertexColor(cr, cg, cb, Peek(r.id).enabled and CU.Alpha(r.id) or 0.15)
    end
    L:Row(box, 84)
end

AddTab("qol", "onscreen", "On screen", function(L)
    if not Allowed() then return end
    local UI = ns.UI
    local d = DB()
    local function Changed()
        Live()
        if ns.RefreshConfig then ns.RefreshConfig() end
    end
    L:Card("Rings round the cursor")
    L:Desc("Rings that follow your mouse cursor, so it is easy to find in a fight. The ones you have not ticked are drawn faint here.")
    Sample(L)
    L:Row(Pick(L, "Show", CU.SHOW, function() return CU.ShowMode() end,
        function(v) d.show = (v ~= "always") and v or nil Changed() end, 200), 44)
    L:EndCard()
    for _, r in ipairs(CU.RINGS) do
        local rd = Peek(r.id)
        L:Card(r.label)
        local tip = ({
            circle = "A ring round the cursor.",
            gcd = "A ring just outside the circle that sweeps while your global cooldown runs.",
            cast = "A ring outside the GCD ring that sweeps while you cast or channel.",
        })[r.id]
        local on = UI.Checkbox(L.current, "Show the " .. r.label:lower(), rd.enabled == true, function(v)
            RingDB(r.id).enabled = v and true or nil
            Changed()
        end, { tooltip = tip })
        L:Row(on, 17)
        local kids = {}
        kids[#kids + 1] = UI.Slider(L.current, { width = 220, min = 12, max = 160, step = 1,
            value = CU.Size(r.id), label = "Size",
            onChange = function(v) RingDB(r.id).size = (v ~= r.size) and v or nil Live() end })
        kids[#kids + 1] = UI.Slider(L.current, { width = 220, min = 10, max = 100, step = 5,
            value = math.floor(CU.Alpha(r.id) * 100 + 0.5), label = "Opacity",
            format = function(v) return v .. "%" end,
            onChange = function(v) local a = v / 100 RingDB(r.id).alpha = (math.abs(a - r.alpha) > 0.001) and a or nil Live() end })
        kids[#kids + 1] = Pick(L, "Weight", CU.WEIGHTS, function() return CU.Weight(r.id) end,
            function(v) RingDB(r.id).weight = (v ~= r.weight) and v or nil Changed() end)
        kids[#kids + 1] = Pick(L, "Colour", CU.COLORS, function() return CU.ColorMode(r.id) end,
            function(v) RingDB(r.id).color = (v ~= r.color) and v or nil Changed() end, 180)
        kids[#kids + 1] = UI.ColorPicker(L.current, { label = "Own colour",
            get = function()
                local c = Peek(r.id).rgb
                if type(c) == "table" and ns.ColorOf then return ns.ColorOf(c) end
                local def = r.rgb or { 1, 1, 1 }
                return def[1], def[2], def[3], 1
            end,
            set = function(cr, cg, cb) RingDB(r.id).rgb = { r = cr, g = cg, b = cb, a = 1 } Live() end })
        L:Dependent(kids, rd.enabled == true, 1, nil, "Show the " .. r.label:lower())
        L:EndCard()
    end
end)

if ns.AddMenuKeywords then
    ns.AddMenuKeywords("qol", "cursor ring circle mouse find cursor gcd global cooldown cast ring stream")
end
