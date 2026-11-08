-- HUD_V2_Icon - Class HUD v2: one icon's extras. Every icon the engine
-- shows carries a state word (ready, cooldown, nopower, oor, active,
-- expiring, missing); a saved per-state style (ZacUI's states shape,
-- cfg.states) restyles it on top of the HUD's own paint, only the fields
-- the user set. Cooldown text can turn a colour under N seconds and read
-- by a saved time format (cfg.formats.cooldown). Keybind text in the
-- icon's "key" text spot (HUD_V2_Keybinds' cache) per row, and the press
-- mirror: the icon darkens while its key is held.
-- All of it is off until saved; with nothing saved the icons draw as
-- the engine always drew them. Runs on the engine's 0.2s tick (states,
-- keys) and 0.1s text tick (thresholds); nothing per frame.
-- Part of ZacUI; load order is set by the TOC (after HUD_V2_Rows).

local ns = _G.ZacUI
if not ns or not ns.HUD or not ns.HUD.V2 then return end
local HUD = ns.HUD
local V2 = HUD.V2
local Engine = HUD.ClassEngine
local Keys = V2.Keys

local GetTime = GetTime
local GetSpellInfo = HUD.GetSpellInfo

V2.STATES = {
    { id = "ready",    label = "Ready" },
    { id = "cooldown", label = "On cooldown" },
    { id = "nopower",  label = "Not enough power" },
    { id = "oor",      label = "Out of range" },
    { id = "active",   label = "Buff or debuff up" },
    { id = "expiring", label = "About to run out" },
    { id = "missing",  label = "Buff down (placeholder)" },
}
-- today's paint per state is the engine's own: nothing to override, so
-- every default field is nil (ApplyState applies only what the user set)
V2.STATE_DEFAULTS = {}
for _, s in ipairs(V2.STATES) do V2.STATE_DEFAULTS[s.id] = {} end
V2.STATE_FIELDS = { color = true, desat = true, border = true, glow = true, textColor = true, anim = true }
V2.EXPIRING_DEFAULT = 5
V2.TIME_DEFAULTS = { time = "short", timeDecimalsUnder = 0 }
V2.KEY_SIZE_DEFAULT = 10

local SV = ns.StateValue

-- ------------------------------------------------------------
-- per-state styles
-- ------------------------------------------------------------
local function GlowFn(icon)
    local fn = icon._v2glowFn
    if fn then return fn end
    fn = function(on, r, g, b, a)
        local gl = icon.glows and icon.glows.v2state
        if on then
            if not gl then
                gl = icon:AddGlow("v2state", "Pixel", { color = { r or 1, g or 0.82, b or 0, a or 1 } })
            else
                local Wd = ns.WarriorHUD and ns.WarriorHUD.Widgets
                if Wd and Wd.SetGlowColor then Wd.SetGlowColor(gl, r or 1, g or 0.82, b or 0, a or 1) end
            end
            icon:SetGlow("v2state", true)
        elseif gl then
            icon:SetGlow("v2state", false)
        end
    end
    icon._v2glowFn = fn
    return fn
end

local parts = {}
local function Restyle(eng, icon, states, name)
    local prev = icon._v2state
    if prev and prev ~= name then
        -- what the old state set and the new one does not: back to the HUD's own
        if SV(states, prev, "border", nil) ~= nil and SV(states, name, "border", nil) == nil then icon:ApplyLook() end
        if SV(states, prev, "textColor", nil) ~= nil and SV(states, name, "textColor", nil) == nil then
            local tc = eng:Col("timer")
            local fs = icon.texts and icon.texts.p
            if fs then fs:SetTextColor(tc[1], tc[2], tc[3], tc[4]) end
        end
    end
    icon._v2state = name
    parts.frame, parts.icon = icon, icon.icon
    parts.text = icon.texts and icon.texts.p
    parts.border = icon.border
    parts.glow = GlowFn(icon)
    ns.ApplyState(states, name, V2.STATE_DEFAULTS, parts)
    -- a colour or desaturation set here: the engine's own paint must land
    -- again next tick (it skips a value it thinks is already on)
    -- (the icon's remembered colour becomes the one now on it: a value
    -- the engine's next paint differs from, and still a colour should a
    -- look change repaint the icon before then)
    if SV(states, name, "color", nil) ~= nil and icon.icon and icon.icon.GetVertexColor then
        local r, g, b, a = icon.icon:GetVertexColor()
        if type(r) == "number" then icon.colR, icon.colG, icon.colB, icon.colA = r, g or 1, b or 1, a or 1 end
    end
    if SV(states, name, "desat", nil) ~= nil then icon.curDesat = nil end
end

local function AuraState(icon, expiring, now)
    local b = icon.auraRef
    if b and not b.hidden and (b.expirationTime or 0) > 0 and (b.expirationTime - now) <= expiring then
        return "expiring"
    end
    return "active"
end

function Engine:V2ApplyStates(cfg)
    local states = cfg.states
    if type(states) ~= "table" or next(states) == nil then
        if self._v2statesOn then
            -- the last rule went: every icon back to its own look
            self._v2statesOn = nil
            for _, field in pairs(V2.ROW_ICONS) do
                for _, icon in pairs(self[field] or {}) do
                    if icon._v2state then
                        icon._v2state = nil
                        icon:ApplyLook()
                        icon.curDesat = nil
                        if icon.SetIconColor then icon:SetIconColor(1, 1, 1, 1) end
                        if icon.glows and icon.glows.v2state then icon:SetGlow("v2state", false) end
                    end
                end
            end
        end
        return
    end
    self._v2statesOn = true
    local now = GetTime()
    local v = cfg.v2
    local expiring = (v and tonumber(v.expiring)) or V2.EXPIRING_DEFAULT
    for _, icon in ipairs(self.mainActive) do Restyle(self, icon, states, icon.state or "ready") end
    for _, icon in ipairs(self.utilActive or {}) do Restyle(self, icon, states, icon.state or "ready") end
    for _, icon in ipairs(self.auraActive) do Restyle(self, icon, states, AuraState(icon, expiring, now)) end
    for _, icon in ipairs(self.debuffActive) do Restyle(self, icon, states, AuraState(icon, expiring, now)) end
    for _, icon in pairs(self.auxIcons) do
        if icon:IsShown() then
            local cdOn = icon.cdDuration and icon.cdDuration > 1.51
            Restyle(self, icon, states, cdOn and "cooldown" or "ready")
        end
    end
    for _, ph in pairs(self.phIcons or {}) do
        if ph:IsShown() then Restyle(self, ph, states, "missing") end
    end
end

-- ------------------------------------------------------------
-- keybind text
-- ------------------------------------------------------------
local SAMPLE_KEYS = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "=", "F1", "F2", "F3", "F4", "Q", "E", "R", "T" }

local function KeyText(eng, icon, def)
    local S = eng.S
    if def.kind == "spell" and def.spell then
        local sp = S.spells[def.spell]
        return Keys.ForSpell(eng.def.spells[def.spell], sp and sp.name)
    elseif def.slot then
        local id = GetInventoryItemID and GetInventoryItemID("player", def.slot)
        if ns.IsSecret(id) then id = nil end
        return Keys.ForItem(id)
    elseif def.key == "racial" then
        return Keys.ForSpell(nil, S.racial and S.racial.name)
    elseif icon.curItem then
        return Keys.ForItem(icon.curItem.id)
    end
    return nil
end

function Engine:V2ApplyKeys(cfg)
    local v = cfg.v2
    local keys = v and v.keys
    local size = (keys and tonumber(keys.size)) or V2.KEY_SIZE_DEFAULT
    local version = Keys.version
    local n = 0
    for row, field in pairs(V2.ROW_ICONS) do
        local on = keys and keys[row] and true or false
        local icons = self[field]
        if icons then
            for _, icon in pairs(icons) do
                local fs = icon.texts and icon.texts.key
                if on then
                    if not fs then
                        fs = icon:AddText("key", "INNER_TOPLEFT", size, { 1, 1, 1, 1 }, 1, -1)
                        icon._v2keySize = size
                    elseif icon._v2keySize ~= size then
                        icon._v2keySize = size
                        HUD.ApplyFont(fs, size, "OUTLINE", "text")
                    end
                    n = n + 1
                    local text
                    if self.sample then
                        text = SAMPLE_KEYS[(n - 1) % #SAMPLE_KEYS + 1]
                    else
                        local ident = icon.curItem and icon.curItem.id or (icon.def.spell or icon.def.key)
                        if icon._v2keyVer ~= version or icon._v2keyFor ~= ident then
                            icon._v2keyVer, icon._v2keyFor = version, ident
                            icon._v2keyText = KeyText(self, icon, icon.def)
                        end
                        text = icon._v2keyText
                    end
                    icon:SetText("key", text or "")
                elseif fs then
                    icon:SetText("key", "")
                end
            end
        end
    end
end

-- what this HUD wants of the shared cache: keys while any row shows
-- them, the press hooks while the mirror is on
function Engine:V2SyncWants(cfg)
    if self.sample then return end
    local v = cfg and cfg.v2
    local keys = v and v.keys
    local want = false
    if keys then
        for row in pairs(V2.ROW_ICONS) do if keys[row] then want = true end end
    end
    if want ~= (self._v2wantKeys or false) then
        self._v2wantKeys = want
        Keys.Want(want)
    end
    local mirror = (v and v.pressMirror) and true or false
    if mirror ~= (self._v2mirror or false) then
        self._v2mirror = mirror
        Keys.MirrorPresses(self, mirror)
    end
end

function Engine:V2LoginIcons(cfg)
    self:V2SyncWants(cfg)
end

function Engine:V2Icons(cfg)
    self:V2ApplyStates(cfg)
    self:V2ApplyKeys(cfg)
    if self.V2Glows then
        if self.V2ReadQueue then self:V2ReadQueue() end
        self:V2Glows(cfg)
    end
end

-- ------------------------------------------------------------
-- cooldown text: threshold colour and a saved time format (0.1s tick)
-- ------------------------------------------------------------
local function CdRemaining(cd, now)
    if not cd or not cd.real then return 0 end
    return math.max(0, cd.start + cd.duration - now)
end

local function ThresholdText(eng, icons, S, fmt, thr, thrC, now)
    for _, icon in ipairs(icons) do
        local def = icon.def
        if def.kind == "spell" then
            local rem = CdRemaining(S.cds[def.spell], now)
            if rem > 0 and fmt then
                icon:SetText("p", ns.FormatTime(rem, fmt, V2.TIME_DEFAULTS))
            end
            local fs = icon.texts.p
            if fs then
                local under = thr and rem > 0 and rem <= thr
                if under and not icon._v2thr then
                    icon._v2thr = true
                    fs:SetTextColor(thrC[1], thrC[2], thrC[3], thrC[4])
                elseif not under and icon._v2thr then
                    icon._v2thr = nil
                    local tc = eng:Col("timer")
                    fs:SetTextColor(tc[1], tc[2], tc[3], tc[4])
                end
            end
        end
    end
end

function Engine:V2TextTick()
    local cfg = self:Store()
    if not cfg then return end
    local v = cfg.v2
    local thr = v and v.threshold
    local fmt = cfg.formats and cfg.formats.cooldown
    if not (thr or fmt) then
        if self._v2thrOn then
            self._v2thrOn = nil
            local tc = self:Col("timer")
            for _, field in pairs(V2.ROW_ICONS) do
                for _, icon in pairs(self[field] or {}) do
                    if icon._v2thr then
                        icon._v2thr = nil
                        if icon.texts.p then icon.texts.p:SetTextColor(tc[1], tc[2], tc[3], tc[4]) end
                    end
                end
            end
        end
        return
    end
    self._v2thrOn = true
    local secs = thr and tonumber(thr.seconds)
    if secs and secs <= 0 then secs = nil end
    local c = thr and thr.color
    local thrC = c and { c.r or c[1] or 1, c.g or c[2] or 0.2, c.b or c[3] or 0.2, c.a or c[4] or 1 } or { 1, 0.2, 0.2, 1 }
    local now = GetTime()
    ThresholdText(self, self.mainActive, self.S, fmt, secs, thrC, now)
    ThresholdText(self, self.utilActive or {}, self.S, fmt, secs, thrC, now)
end

-- ------------------------------------------------------------
-- the press mirror
-- ------------------------------------------------------------
local PRESS_MIN = 0.12   -- a tap stays visible this long
local PRESS_MAX = 2      -- a press never sticks longer than this

local function PressTex(icon)
    local t = icon._v2press
    if t then return t end
    t = icon:CreateTexture(nil, "OVERLAY", nil, 3)
    t:SetAllPoints(icon.icon or icon)
    t:SetTexture("Interface\\Buttons\\WHITE8X8")
    t:SetVertexColor(0, 0, 0, 0.45)
    t:Hide()
    icon._v2press = t
    return t
end

local function Release(icon)
    local t = icon._v2press
    if t then t:Hide() end
    icon._v2pressedAt = nil
end

local function Matches(eng, icon, kind, id, name)
    local def = icon.def
    if not def then return false end
    if kind == "spell" then
        if def.kind == "spell" and def.spell then
            if eng.def.spells[def.spell] == id then return true end
            local sp = eng.S.spells[def.spell]
            return name ~= nil and sp and sp.name == name or false
        end
        if def.key == "racial" and eng.S.racial then return eng.S.racial.name == name end
        return false
    elseif kind == "item" then
        if icon.curItem and icon.curItem.id == id then return true end
        if def.slot and GetInventoryItemID then
            local eq = GetInventoryItemID("player", def.slot)
            return not ns.IsSecret(eq) and eq == id
        end
    elseif kind == "macro" then
        return false
    end
    return false
end

function Engine:V2Press(kind, id, name, down)
    if not self.built then return end
    local now = GetTime()
    for _, field in pairs(V2.ROW_ICONS) do
        for _, icon in pairs(self[field] or {}) do
            if icon:IsShown() and Matches(self, icon, kind, id, name) then
                if down then
                    PressTex(icon):Show()
                    icon._v2pressedAt = now
                    C_Timer.After(PRESS_MAX, function()
                        if icon._v2pressedAt == now then Release(icon) end
                    end)
                else
                    local held = icon._v2pressedAt and (now - icon._v2pressedAt) or PRESS_MIN
                    if held < PRESS_MIN then
                        C_Timer.After(PRESS_MIN - held, function() Release(icon) end)
                    else
                        Release(icon)
                    end
                end
            end
        end
    end
end
