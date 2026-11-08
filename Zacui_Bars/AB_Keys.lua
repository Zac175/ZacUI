-- AB_Keys - ZacUI's keybind mode (hover a button, press a key) and the
-- login note about keys on buttons that cannot be seen.
-- Part of ZacUI; load order is set by the TOC (after AB_Extras: it reads
-- the action, pet and stance buttons those files make).
--
-- KEYBIND MODE (/zui kb, the Keys card on the Action bars page). Every
-- ZacUI bar shows - faded bars come up, bars hidden by their visibility
-- rule show, empty slots show - and every key is written on its button.
-- Hovering a button lays a catcher over it: a plain frame of ours, not a
-- secure one, so the button underneath never casts and Blizzard's own
-- binding input is never driven from addon code. A key, a mouse button
-- or the wheel binds to that button's command (the Blizzard name on bars
-- 1 and 3-6 and on the pet and stance bars, the CLICK name on bars 2 and
-- 7-10 - the same command the hotkey corner reads); Escape clears it;
-- right-click, the strip's X or /zui kb again finishes. Keys are saved
-- once, when the mode ends. Nothing here runs in combat: SetBinding is
-- refused there, so the mode ends the moment a fight starts (before the
-- lockdown) and keeps what was bound.
--
-- THE HIDDEN KEY NOTE. A key bound to a button nobody can see (its bar is
-- off or always hidden, or the button is past the bar's button count)
-- still fires - the hidden button casts. Once after login, and again only
-- when that set changes, chat says which keys and bars; no binding is
-- touched. core.warnHiddenKeys false turns it off.

local ADDON_NAME = ...
local ns = _G.ZacUI
if not ns then return end

local AB = ns.Bars
local function Print(m) ns.Print(m) end    -- (looked up per call)
local UI = ns.UI

local KM = {}
AB.KeyMode = KM
AB.keyMode = false

-- ============================================================
-- WHAT A BUTTON IS
-- ============================================================
-- every ZacUI button keybind mode can bind (made on the first apply)
local function EachButton(fn)
    for _, header in pairs(AB.actionBars or {}) do
        for _, btn in ipairs(header.buttons or {}) do fn(btn) end
    end
    for _, key in ipairs({ "pet", "stance" }) do
        local h = AB.headers and AB.headers[key]
        for _, btn in ipairs(h and h.buttons or {}) do fn(btn) end
    end
end

-- The command a button answers to, and what to call it.
local function CommandOf(btn)
    if btn.zBar and btn.zIndex and AB.BindingNameFor then
        return (AB.BindingNameFor(btn.zBar, btn.zIndex)), "Bar " .. btn.zBar .. " button " .. btn.zIndex
    end
    local cmd = rawget(btn, "commandName")
    if type(cmd) ~= "string" then return nil end
    local i = tonumber(cmd:match("(%d+)$"))
    if cmd:find("^BONUSACTIONBUTTON") then return cmd, "Pet bar button " .. (i or "?") end
    if cmd:find("^SHAPESHIFTBUTTON") then return cmd, "Stance bar button " .. (i or "?") end
    return cmd, cmd
end
KM.CommandOf = CommandOf

local function KeysOf(cmd)
    if not (cmd and GetBindingKey) then return {} end
    return { GetBindingKey(cmd) }
end

-- ============================================================
-- BINDING
-- ============================================================
-- keys that are only half a chord: never bound on their own
local MODIFIER = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
    LMETA = true, RMETA = true, UNKNOWN = true }
local MOUSE = { LeftButton = "BUTTON1", RightButton = "BUTTON2", MiddleButton = "BUTTON3" }

-- the key as the binding system names it, with the modifiers held now
function KM.Chord(key)
    if not key or MODIFIER[key] then return nil end
    key = MOUSE[key] or key
    local b = key:match("^Button(%d+)$")
    if b then key = "BUTTON" .. b end
    key = key:upper()
    local mods = ""
    if IsAltKeyDown and IsAltKeyDown() then mods = mods .. "ALT-" end
    if IsControlKeyDown and IsControlKeyDown() then mods = mods .. "CTRL-" end
    if IsShiftKeyDown and IsShiftKeyDown() then mods = mods .. "SHIFT-" end
    if IsMetaKeyDown and IsMetaKeyDown() then mods = mods .. "META-" end
    return mods .. key
end

KM.changed = false

-- Binds `chord` to the hovered button's command (its old keys come off,
-- so one button carries the one key it was just given), or clears the
-- button when chord is "ESCAPE". Out of combat only.
function KM.Bind(btn, chord)
    if not (btn and chord) or InCombatLockdown() then return false end
    local cmd, label = CommandOf(btn)
    if not cmd then return false end
    local old = KeysOf(cmd)
    if chord == "ESCAPE" then
        if #old == 0 then Print(label .. ": nothing bound.") return false end
        for _, k in ipairs(old) do SetBinding(k) end
        KM.changed = true
        Print(label .. ": unbound " .. table.concat(old, ", ") .. ".")
        return true
    end
    local was = GetBindingAction and GetBindingAction(chord) or ""
    for _, k in ipairs(old) do if k ~= chord then SetBinding(k) end end
    if not SetBinding(chord, cmd) then
        for _, k in ipairs(old) do SetBinding(k, cmd) end
        Print(label .. ": " .. chord .. " could not be bound.")
        return false
    end
    KM.changed = true
    local note = (was ~= "" and was ~= cmd) and (" (it was on " .. tostring(was) .. ")") or ""
    Print(label .. ": " .. chord .. note .. ".")
    return true
end

-- ============================================================
-- THE CATCHER (over the hovered button)
-- ============================================================
local catcher, strip

local function Accent()
    local a = ns.Col and ns.Col("accent") or { r = 0.85, g = 0.65, b = 0.25 }
    return a.r, a.g, a.b
end

local function Tip(btn)
    if not GameTooltip then return end
    local cmd, label = CommandOf(btn)
    GameTooltip:SetOwner(catcher, "ANCHOR_RIGHT")
    GameTooltip:AddLine(label, 1, 1, 1)
    local keys = KeysOf(cmd)
    if #keys > 0 then
        GameTooltip:AddLine("Key: " .. table.concat(keys, ", "), 0.45, 0.85, 0.45)
    else
        GameTooltip:AddLine("Not bound", 0.9, 0.3, 0.3)
    end
    GameTooltip:AddLine("Press a key to bind it, Esc to clear", 0.65, 0.65, 0.65)
    GameTooltip:Show()
end

local function Catcher()
    if catcher then return catcher end
    catcher = CreateFrame("Frame", "ZacUIKeybindCatcher", UIParent)
    catcher:SetFrameStrata("DIALOG")
    catcher:Hide()
    local fill = catcher:CreateTexture(nil, "ARTWORK")
    fill._zui_own = true
    fill:SetAllPoints()
    fill:SetTexture(ns.FLAT or "Interface\\Buttons\\WHITE8X8")
    catcher.fill = fill
    if ns.Pixel and ns.Pixel.Border then
        catcher.ring = ns.Pixel.Border(catcher, 1, 1, 1, 1, "OVERLAY", 7)
    end
    catcher:EnableMouse(true)
    catcher:EnableKeyboard(true)
    if catcher.EnableMouseWheel then catcher:EnableMouseWheel(true) end
    catcher:SetScript("OnLeave", function(self)
        self.btn = nil
        self:Hide()
        if GameTooltip and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
    catcher:SetScript("OnKeyDown", function(self, key)
        if not self.btn then return end
        local chord = (key == "ESCAPE") and "ESCAPE" or KM.Chord(key)
        if chord and KM.Bind(self.btn, chord) then Tip(self.btn) end
    end)
    catcher:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then KM.Stop() return end
        if button == "LeftButton" or not self.btn then return end
        local chord = KM.Chord(button)
        if chord and KM.Bind(self.btn, chord) then Tip(self.btn) end
    end)
    catcher:SetScript("OnMouseWheel", function(self, delta)
        if not self.btn then return end
        local chord = KM.Chord(delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN")
        if chord and KM.Bind(self.btn, chord) then Tip(self.btn) end
    end)
    return catcher
end

-- Lays the catcher over `btn` by position, not by anchor: anchored to a
-- secure button it would join its protected family.
local function Cover(btn)
    if not (AB.keyMode and btn and btn:IsVisible()) or InCombatLockdown() then return end
    local c = Catcher()
    local l, b, w, h = btn:GetLeft(), btn:GetBottom(), btn:GetWidth(), btn:GetHeight()
    if not (l and b and w and h) then return end
    local s = (btn:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
    c:ClearAllPoints()
    c:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l * s, b * s)
    c:SetSize(w * s, h * s)
    local r, g, bb = Accent()
    c.fill:SetVertexColor(r, g, bb, 0.25)
    for _, t in ipairs(c.ring or {}) do t:SetColorTexture(r, g, bb, 1) end
    c.btn = btn
    c:Show()
    Tip(btn)
end
KM.Cover = Cover

local hooked = setmetatable({}, { __mode = "k" })
local function HookButtons()
    EachButton(function(btn)
        if hooked[btn] then return end
        hooked[btn] = true
        btn:HookScript("OnEnter", function(self) if AB.keyMode then Cover(self) end end)
    end)
end

-- ============================================================
-- THE STRIP (what the mode is and how to leave it)
-- ============================================================
KM.TEXT = "Keybind mode: hover a button and press a key, Esc clears, right-click or /zui kb to finish"
local function Strip()
    if strip then return strip end
    strip = CreateFrame("Frame", "ZacUIKeybindStrip", UIParent)
    strip:SetFrameStrata("DIALOG")
    strip:SetFrameLevel(50)
    strip:SetPoint("TOP", UIParent, "TOP", 0, -120)
    if ns.SkinBackdrop then ns.SkinBackdrop(strip, "windowBg", 0.95) end
    local edge = strip:CreateTexture(nil, "OVERLAY", nil, 6)
    edge._zui_own = true
    edge:SetTexture(ns.FLAT or "Interface\\Buttons\\WHITE8X8")
    edge:SetPoint("TOPLEFT", 1, -1)
    edge:SetPoint("BOTTOMLEFT", 1, 1)
    if ns.Pixel and ns.Pixel.Edge then ns.Pixel.Edge(edge, "LEFT", strip, 3) else edge:SetWidth(3) end
    strip.edge = edge
    local fs = strip:CreateFontString(nil, "OVERLAY")
    if ns.HouseFont then ns.HouseFont(fs, 12, "") else fs:SetFontObject(GameFontHighlight) end
    fs:SetPoint("LEFT", strip, "LEFT", 12, 0)
    fs:SetText(KM.TEXT)
    strip.text = fs
    local x
    if UI and UI.CloseX then
        x = UI.CloseX(strip, 18, function() KM.Stop() end)
    else
        x = CreateFrame("Button", nil, strip, "UIPanelCloseButton")
        x:SetScript("OnClick", function() KM.Stop() end)
        x:SetSize(18, 18)
    end
    x:SetPoint("RIGHT", strip, "RIGHT", -6, 0)
    strip.close = x
    -- right-click anywhere on the strip finishes too
    strip:EnableMouse(true)
    strip:SetScript("OnMouseUp", function(_, button) if button == "RightButton" then KM.Stop() end end)
    strip:Hide()
    return strip
end

local function ShowStrip()
    local s = Strip()
    local r, g, b = Accent()
    s.edge:SetVertexColor(r, g, b, 1)
    local w = (s.text:GetStringWidth() or 400) + 12 + 10 + 18 + 8
    s:SetSize(math.floor(w + 0.5), 28)
    s:Show()
end

-- ============================================================
-- ON / OFF
-- ============================================================
local combatWatch = CreateFrame("Frame")
combatWatch:SetScript("OnEvent", function()
    -- (REGEN_DISABLED runs before the lockdown: everything below is legal)
    if AB.keyMode then
        KM.Stop()
        Print("Keybind mode ended for combat; keys bound so far are kept.")
    end
end)

function KM.Start()
    if AB.keyMode then return end
    if InCombatLockdown() then Print("Keys cannot be bound in combat.") return end
    if not AB.active then Print("ZacUI's action bars are not running.") return end
    if KeybindFrames_InQuickKeybindMode and KeybindFrames_InQuickKeybindMode() and QuickKeybindFrame then
        QuickKeybindFrame:Hide()
    end
    AB.keyMode = true
    KM.changed = false
    AB.ApplyAll()
    -- every enabled bar shows, whatever its visibility rule (put back by
    -- the apply in Stop)
    for _, header in pairs(AB.headers or {}) do
        local key = header.key
        local bindable = (type(key) == "string" and key:find("^bar%d")) or key == "pet"
            or (key == "stance" and (header.appliedForms or 0) > 0)
        if bindable and header.cfg and header.cfg.enabled then
            UnregisterStateDriver(header, "visibility")
            header:Show()
        end
    end
    HookButtons()
    AB.PollFade()
    if AB.RefreshAllEmpty then AB.RefreshAllEmpty() end
    ShowStrip()
    combatWatch:RegisterEvent("PLAYER_REGEN_DISABLED")
end

function KM.Stop()
    if not AB.keyMode then return end
    AB.keyMode = false
    combatWatch:UnregisterEvent("PLAYER_REGEN_DISABLED")
    if catcher then catcher.btn = nil catcher:Hide() end
    if strip then strip:Hide() end
    if GameTooltip and catcher and GameTooltip:IsOwned(catcher) then GameTooltip:Hide() end
    if KM.changed and SaveBindings and GetCurrentBindingSet then
        SaveBindings(GetCurrentBindingSet())
        KM.changed = false
    end
    AB.ApplyAll()
    AB.PollFade()
    if AB.RefreshAllEmpty then AB.RefreshAllEmpty() end
end

function KM.Toggle()
    if AB.keyMode then KM.Stop() else KM.Start() end
end
AB.ToggleKeyMode = KM.Toggle

-- ============================================================
-- KEYS ON BUTTONS NOBODY CAN SEE
-- ============================================================
-- { { bar = label, keys = { "S-1", ... }, why = "off" | "hidden" | "past" } ...}
function AB.HiddenKeys()
    local out = {}
    local p = AB.Profile()
    for n = 1, AB.NUM_BARS do
        local cfg = p.bars[n] or {}
        local vis = cfg.visibility or {}
        local whole = (not cfg.enabled) and "off" or (vis.always and "hidden") or nil
        local count = math.min(cfg.buttons or 12, AB.PER_BAR)
        local keys = {}
        local why = whole
        for i = 1, AB.PER_BAR do
            if whole or i > count then
                local list = KeysOf((AB.BindingNameFor(n, i)))
                if AB.BLIZZ_BINDS and AB.BLIZZ_BINDS[n] then
                    for _, k in ipairs(KeysOf("CLICK " .. AB.ButtonName((n - 1) * AB.PER_BAR + i) .. ":LeftButton")) do
                        list[#list + 1] = k
                    end
                end
                for _, k in ipairs(list) do keys[#keys + 1] = k end
                if #list > 0 and not whole then why = "past" end
            end
        end
        if #keys > 0 then out[#out + 1] = { n = n, bar = "Bar " .. n, keys = keys, why = why } end
    end
    return out
end

local WHY = { off = "bar off", hidden = "bar always hidden", past = "past the bar's last button" }
function AB.WarnHiddenKeys(force)
    if not AB.active then return end
    local core = AB.CoreCfg()
    if core.warnHiddenKeys == false and not force then return end
    local list = AB.HiddenKeys()
    local parts, sig = {}, {}
    for _, e in ipairs(list) do
        local shown = {}
        for _, k in ipairs(e.keys) do shown[#shown + 1] = AB.ShortKey(k, "short") sig[#sig + 1] = e.n .. "=" .. k end
        parts[#parts + 1] = e.bar .. " (" .. WHY[e.why] .. "): " .. table.concat(shown, ", ")
    end
    table.sort(sig)
    local s = table.concat(sig, ";")
    ZacUICharDB = ZacUICharDB or {}
    if not force and ZacUICharDB.barsHiddenKeys == s then return end
    ZacUICharDB.barsHiddenKeys = s
    if #parts == 0 then
        if force then Print("No keys on bar buttons you cannot see.") end
        return
    end
    Print("Keys on bar buttons you cannot see - they still fire: " .. table.concat(parts, "; ")
        .. ". Turn the bar on or move the keys (/zui kb). This note is under Action bars > Advanced > Keys.")
end

local login = CreateFrame("Frame")
login:RegisterEvent("PLAYER_ENTERING_WORLD")
login:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    -- after the loadout (4 s) and the bindings from the server have landed
    C_Timer.After(8, function() pcall(AB.WarnHiddenKeys) end)
end)
