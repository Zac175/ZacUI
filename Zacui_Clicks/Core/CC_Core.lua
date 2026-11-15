-- CC_Core - click-casting: a spell, macro, target or menu on any mouse
-- button or key, with Shift / Ctrl / Alt, cast on the unit frame you
-- click or hover. ZacUI's own system, written from scratch; Clique did
-- the job before and its bindings are brought over once (CC_Import).
-- Part of ZacUI; load order is set by the TOC.
--
-- A BINDING is { key, type, spell, rank, macrotext, sets }:
--   key   "BUTTON1".."BUTTON5", "MOUSEWHEELUP"/"DOWN" or a keyboard key,
--         with any of "ALT-", "CTRL-", "SHIFT-" in front ("SHIFT-BUTTON5")
--   type  "spell" | "macro" | "target" | "menu"
--   sets  where it works (any number of them):
--         default    on unit frames; a key works while the mouse is on one
--         ooc        like default, only out of combat
--         friend     like default, on a friendly unit only
--         enemy      like default, on a hostile unit only
--         hovercast  anywhere: on the unit under the mouse, frame or world
--         global     anywhere, on your target
--
-- WHICH FRAMES. ZacUI's unit frames (they register themselves the way
-- they always did for Clique: the ClickCastFrames table and, for the
-- party and raid headers, ClickCastHeader - both provided here now),
-- the game's own unit frames when that is on, and any other addon's
-- frames put in ClickCastFrames.
--
-- HOW. A mouse button on a frame is that frame's own attributes
-- ("shift-type5" = "spell", "shift-spell5" = "Flash of Light(Rank 6)").
-- Friend-only / enemy-only buttons and every key go through a virtual
-- button "zcc<n>". Keys over a frame are bindings the frame takes while
-- the mouse is on it: a secure OnEnter sets them, OnLeave / OnHide clear
-- them, so that works in combat. Hovercast and global bindings are
-- override bindings to one hidden secure button. Attributes and override
-- bindings are only ever written out of combat - and once more as a
-- fight starts (PLAYER_REGEN_DISABLED, the last moment it is allowed),
-- to drop the out-of-combat ones.
--
-- WHILE CLIQUE IS ON this file stands down completely: Clique owns
-- ClickCastFrames / ClickCastHeader then, and two click-casters on one
-- frame fight. CC_Import brings Clique's bindings over and offers to
-- turn it off.

local ADDON_NAME = ...
local ns = _G.ZacUI
if not ns then return end

local Print = ns.Print

local CC = {}
ns.ClickCast = CC

CC.SETS = { "default", "ooc", "friend", "enemy", "hovercast", "global" }
CC.SET_LABEL = {
    default = "Unit frames", ooc = "Out of combat", friend = "Friendly only", enemy = "Hostile only",
    hovercast = "Hover anywhere", global = "Anywhere (target)",
}
CC.TYPES = { "spell", "macro", "target", "menu" }
CC.TYPE_LABEL = { spell = "Cast a spell", macro = "Run a macro", target = "Target the unit", menu = "Open the unit menu" }
CC.MOUSE = { BUTTON1 = 1, BUTTON2 = 2, BUTTON3 = 3, BUTTON4 = 4, BUTTON5 = 5 }
-- the menu type ZacUI's unit frames use for right-click
CC.MENU_TYPE = "togglemenu"

local AddonLoaded = ns.AddonLoaded

-- Clique is on: everything below stays dark (decided at file load,
-- after Clique's own files - it is an OptionalDep - so this is final)
CC.standDown = AddonLoaded("Clique")

-- ============================================================
-- SETTINGS - ZacUIDB.clickcast (account-wide, bindings per character;
-- not a profile section: a profile swap must never wipe bindings)
-- ============================================================
local function Cfg()
    if type(ZacUIDB) ~= "table" then return nil end
    local c = ZacUIDB.clickcast
    if type(c) ~= "table" then
        c = {}
        ZacUIDB.clickcast = c
    end
    if c.enabled == nil then c.enabled = true end
    if c.blizzard == nil then c.blizzard = true end
    if type(c.profiles) ~= "table" then c.profiles = {} end
    return c
end
CC.Cfg = Cfg

-- "Name - Realm": the key Clique used, so imported sets line up
local function CharKey()
    local name = UnitName("player") or "?"
    local realm = (GetRealmName and GetRealmName()) or "?"
    return name .. " - " .. realm
end
CC.CharKey = CharKey

CC.DEFAULT_BINDINGS = {
    { key = "BUTTON1", type = "target", sets = { default = true } },
    { key = "BUTTON2", type = "menu", sets = { default = true } },
}

local function Copy(t)
    if type(t) ~= "table" then return t end
    local o = {}
    for k, v in pairs(t) do o[k] = Copy(v) end
    return o
end
CC.Copy = Copy

-- this character's bindings (the two everyone expects, when new)
local function Bindings()
    local c = Cfg()
    if not c then return {} end
    local key = CharKey()
    local p = c.profiles[key]
    if type(p) ~= "table" then
        p = { bindings = Copy(CC.DEFAULT_BINDINGS) }
        c.profiles[key] = p
    end
    if type(p.bindings) ~= "table" then p.bindings = {} end
    return p.bindings
end
CC.Bindings = Bindings

-- ============================================================
-- KEYS
-- ============================================================
-- "SHIFT-CTRL-BUTTON5" -> "ctrl-shift-", "BUTTON5", "CTRL-SHIFT-BUTTON5"
-- (the secure templates read the prefix in the order alt, ctrl, shift;
-- bindings want the same order in capitals)
local function SplitKey(key)
    key = (key or ""):upper()
    local alt, ctrl, shift = false, false, false
    local base = key
    while true do
        local m, rest = base:match("^(%u+)%-(.+)$")
        if m == "ALT" then alt = true; base = rest
        elseif m == "CTRL" then ctrl = true; base = rest
        elseif m == "SHIFT" then shift = true; base = rest
        else break end
    end
    local prefix = (alt and "alt-" or "") .. (ctrl and "ctrl-" or "") .. (shift and "shift-" or "")
    local bindKey = (alt and "ALT-" or "") .. (ctrl and "CTRL-" or "") .. (shift and "SHIFT-" or "") .. base
    return prefix, base, bindKey
end
CC.SplitKey = SplitKey

function CC.KeyLabel(key)
    if not key or key == "" then return "(no key)" end
    local prefix, base = SplitKey(key)
    local mods = prefix:gsub("alt%-", "Alt+"):gsub("ctrl%-", "Ctrl+"):gsub("shift%-", "Shift+")
    local names = { BUTTON1 = "Left click", BUTTON2 = "Right click", BUTTON3 = "Middle click",
        BUTTON4 = "Mouse 4", BUTTON5 = "Mouse 5", MOUSEWHEELUP = "Wheel up", MOUSEWHEELDOWN = "Wheel down" }
    local b = names[base]
    if not b then
        b = base
        if GetBindingText then
            local ok, t = pcall(GetBindingText, base)
            if ok and t and t ~= "" then b = t end
        end
    end
    return mods .. b
end

-- the spell as a cast attribute wants it: "Name(Rank 3)" or "Name"
local function SpellString(b)
    if type(b.spell) ~= "string" or b.spell == "" then return nil end
    if type(b.rank) == "string" and b.rank ~= "" then return b.spell .. "(" .. b.rank .. ")" end
    return b.spell
end
CC.SpellString = SpellString

function CC.ActionLabel(b)
    if b.type == "spell" then return (b.spell or "?") .. ((b.rank and b.rank ~= "") and (" (" .. b.rank .. ")") or "") end
    if b.type == "macro" then
        local first = (b.macrotext or ""):match("^[^\n]*") or ""
        if #first > 40 then first = first:sub(1, 38) .. ".." end
        return "Macro: " .. first
    end
    if b.type == "target" then return "Target" end
    if b.type == "menu" then return "Unit menu" end
    return tostring(b.type)
end

function CC.SetsLabel(b)
    local out = {}
    for _, s in ipairs(CC.SETS) do
        if b.sets and b.sets[s] then out[#out + 1] = CC.SET_LABEL[s] end
    end
    return #out > 0 and table.concat(out, ", ") or "nowhere (tick a set)"
end

-- ============================================================
-- WHAT EACH FRAME GETS
-- ============================================================
local function Action(attrs, name, b, unit)
    if b.type == "spell" then
        local s = SpellString(b)
        if not s then return false end
        attrs[#attrs + 1] = { name("type"), "spell" }
        attrs[#attrs + 1] = { name("spell"), s }
    elseif b.type == "macro" then
        if type(b.macrotext) ~= "string" or b.macrotext == "" then return false end
        attrs[#attrs + 1] = { name("type"), "macro" }
        attrs[#attrs + 1] = { name("macrotext"), b.macrotext }
    elseif b.type == "target" then
        attrs[#attrs + 1] = { name("type"), "target" }
    elseif b.type == "menu" then
        attrs[#attrs + 1] = { name("type"), CC.MENU_TYPE }
    else
        return false
    end
    if unit then attrs[#attrs + 1] = { name("unit"), unit } end
    return true
end

local function Virtual(vb) return function(a) return "*" .. a .. "-" .. vb end end
local function Direct(prefix, n) return function(a) return prefix .. a .. n end end

-- a key the binding strings below can carry
local function SafeKey(k) return type(k) == "string" and k ~= "" and not k:find("[;=\t\n]") end

-- The bindings as four lists:
--   frameAttrs  { {name, value} }   on every registered frame
--   keys        { {bindKey, vb} }   bound while the mouse is on one
--   world       { {bindKey, vb} }   override bindings to the world button
--   worldAttrs  { {name, value} }   that button's attributes
-- plus the bindings skipped (a plain left / right click is never taken
-- away from the camera).
function CC.Build(inCombat)
    local frameAttrs, keys, world, worldAttrs, skipped = {}, {}, {}, {}, {}
    local n = 0
    local function NewVB() n = n + 1 return "zcc" .. n end
    -- keys are grouped: one key may do one thing on friends and another
    -- on enemies; the key binds one virtual button that remaps by unit
    local keyGroups, keyOrder = {}, {}
    for _, b in ipairs(Bindings()) do
        local sets = b.sets or {}
        local plain = sets.default or (sets.ooc and not inCombat)
        local prefix, base, bindKey = SplitKey(b.key)
        local mouse = CC.MOUSE[base]
        if SafeKey(b.key) then
            if plain or sets.friend or sets.enemy then
                if mouse then
                    if plain then
                        local before = #frameAttrs
                        Action(frameAttrs, Direct(prefix, mouse), b)
                        -- a plain left / right click doing what a unit
                        -- frame already does by itself (target, menu)
                        -- yields to the frame's own choice: the soft
                        -- target frame targets on right click
                        if prefix == "" and (b.type == "target" or b.type == "menu") then
                            for i = before + 1, #frameAttrs do frameAttrs[i].soft = true end
                        end
                    end
                    if sets.friend or sets.enemy then
                        local vb = NewVB()
                        if Action(frameAttrs, Virtual(vb), b) then
                            if sets.friend then frameAttrs[#frameAttrs + 1] = { prefix .. "helpbutton" .. mouse, vb } end
                            if sets.enemy then frameAttrs[#frameAttrs + 1] = { prefix .. "harmbutton" .. mouse, vb } end
                        end
                    end
                else
                    local g = keyGroups[bindKey]
                    if not g then g = {} keyGroups[bindKey] = g keyOrder[#keyOrder + 1] = bindKey end
                    if plain then g.plain = b end
                    if sets.friend then g.friend = b end
                    if sets.enemy then g.enemy = b end
                end
            end
            if sets.hovercast or sets.global then
                if bindKey == "BUTTON1" or bindKey == "BUTTON2" then
                    skipped[#skipped + 1] = b
                else
                    local vb = NewVB()
                    if Action(worldAttrs, Virtual(vb), b, sets.hovercast and "mouseover" or nil) then
                        world[#world + 1] = { bindKey, vb }
                    end
                end
            end
        end
    end
    for _, bindKey in ipairs(keyOrder) do
        local g = keyGroups[bindKey]
        local vb = NewVB()
        local any = false
        if g.plain and Action(frameAttrs, Virtual(vb), g.plain) then any = true end
        if g.friend then
            local vf = NewVB()
            if Action(frameAttrs, Virtual(vf), g.friend) then
                frameAttrs[#frameAttrs + 1] = { "*helpbutton-" .. vb, vf }
                any = true
            end
        end
        if g.enemy then
            local ve = NewVB()
            if Action(frameAttrs, Virtual(ve), g.enemy) then
                frameAttrs[#frameAttrs + 1] = { "*harmbutton-" .. vb, ve }
                any = true
            end
        end
        if any then keys[#keys + 1] = { bindKey, vb } end
    end
    return frameAttrs, keys, world, worldAttrs, skipped
end

-- ============================================================
-- THE SECURE SIDE
-- ============================================================
CC.frames = setmetatable({}, { __mode = "k" })   -- every registered frame
local adopted = setmetatable({}, { __mode = "k" }) -- frames already wrapped
local waiting = setmetatable({}, { __mode = "k" }) -- registered in combat: adopt after
local everSet = {}                               -- attribute names we have written
local header, worldButton

-- the strings the secure snippets read
local attrString, clearString, keyString = "", "", ""

local REGISTER = [[
    local b = self:GetAttribute("clickcast_button")
    if not b then return end
    local clear = self:GetAttribute("zcc_clear") or ""
    for n in string.gmatch(clear, "[^\n]+") do b:SetAttribute(n, nil) end
    local attrs = self:GetAttribute("zcc_attrs") or ""
    for n, v in string.gmatch(attrs, "([^\t\n]+)\t([^\n]*)") do
        v = string.gsub(v, "\001", "\n")
        if string.sub(n, 1, 1) == "?" then
            n = string.sub(n, 2)
            if b:GetAttribute("*" .. n) == nil then b:SetAttribute(n, v) end
        else
            b:SetAttribute(n, v)
        end
    end
    local name = b:GetName()
    if name then self:CallMethod("ZccAdopt", name) end
]]

local ON_ENTER = [[
    local keys = owner:GetAttribute("zcc_keys") or ""
    self:ClearBindings()
    for k, vb in string.gmatch(keys, "([^;=]+)=([^;]+)") do self:SetBindingClick(true, k, self, vb) end
]]
local ON_LEAVE = [[ self:ClearBindings() ]]

-- a nameplate's unit frame (the game builds it with the same compact
-- unit frame setup as the raid frames) - forbidden inside instances,
-- where touching it at all is an error, and never a click-cast target
local function Nameplate(f)
    if type(f) ~= "table" then return false end
    if f.IsForbidden and f:IsForbidden() then return true end
    return f.namePlateFrame ~= nil
end

local function Usable(f)
    if type(f) ~= "table" or type(f.GetObjectType) ~= "function" then return false end
    if Nameplate(f) then return false end
    -- a secure unit button; the unit frames' mock previews are plain
    -- frames and stay out
    local ok, prot = pcall(f.IsProtected, f)
    return ok and prot and true or false
end

local function ApplyTo(f)
    if Nameplate(f) then CC.frames[f] = nil waiting[f] = nil return end
    if InCombatLockdown() then waiting[f] = true return end
    for name in pairs(everSet) do f:SetAttribute(name, nil) end
    local list = CC._frameAttrs or {}
    for _, a in ipairs(list) do
        if not (a.soft and f:GetAttribute("*" .. a[1]) ~= nil) then f:SetAttribute(a[1], a[2]) end
    end
    -- hover keys bind by frame name; a nameless frame gets clicks only
    if not adopted[f] and header and f:GetName() then
        adopted[f] = true
        SecureHandlerWrapScript(f, "OnEnter", header, ON_ENTER)
        SecureHandlerWrapScript(f, "OnLeave", header, ON_LEAVE)
        SecureHandlerWrapScript(f, "OnHide", header, ON_LEAVE)
    end
end

function CC.Register(f)
    if CC.standDown or not Usable(f) then return end
    CC.frames[f] = true
    if CC.running then ApplyTo(f) end
end

function CC.Unregister(f)
    if not f then return end
    CC.frames[f] = nil
    waiting[f] = nil
    if not InCombatLockdown() and Usable(f) then
        for name in pairs(everSet) do f:SetAttribute(name, nil) end
    end
end

local function BuildHeader()
    if header then return end
    header = CreateFrame("Frame", "ClickCastHeader", UIParent, "SecureHandlerBaseTemplate")
    header:SetAttribute("clickcast_register", REGISTER)
    header:SetAttribute("clickcast_unregister", [[ ]])
    -- the raid / party headers' new children arrive here from the secure
    -- side; the insecure side wraps their OnEnter once it may
    function header:ZccAdopt(name)
        local f = name and _G[name]
        if not f then return end
        CC.frames[f] = true
        if not CC.running then return end
        if InCombatLockdown() then waiting[f] = true return end
        ApplyTo(f)
    end
    worldButton = CreateFrame("Button", "ZacUIClickCastWorld", UIParent, "SecureActionButtonTemplate")
    -- a binding press counts as a key press: the button acts on the down
    -- or the up depending on the "cast on key down" option, so it must
    -- hear both
    worldButton:RegisterForClicks("AnyUp", "AnyDown")
    worldButton:Hide()
end

-- the ClickCastFrames table every unit-frame addon writes into
local function OwnTables()
    local old = rawget(_G, "ClickCastFrames")
    local proxy = setmetatable({}, {
        __newindex = function(_, f, v)
            if v then CC.Register(f) else CC.Unregister(f) end
        end,
        __index = function(_, f) return CC.frames[f] end,
    })
    _G.ClickCastFrames = proxy
    if type(old) == "table" then
        for f, v in pairs(old) do if v then CC.Register(f) end end
    end
end

-- the game's own unit frames (ZacUF hides most of them; registering a
-- hidden one does no harm)
local BLIZZARD = { "PlayerFrame", "PetFrame", "TargetFrame", "TargetFrameToT",
    "PartyMemberFrame1", "PartyMemberFrame2", "PartyMemberFrame3", "PartyMemberFrame4",
    "PartyMemberFrame1PetFrame", "PartyMemberFrame2PetFrame", "PartyMemberFrame3PetFrame", "PartyMemberFrame4PetFrame" }
local compactHooked = false
local function RegisterBlizzard()
    local c = Cfg()
    if not (c and c.blizzard) then return end
    for _, name in ipairs(BLIZZARD) do
        local f = _G[name]
        if f then CC.Register(f) end
    end
    -- 1.15.9 builds the party frames from a pool, without names
    local pool = _G.PartyFrame and _G.PartyFrame.PartyMemberFramePool
    if pool and pool.EnumerateActive then
        for f in pool:EnumerateActive() do
            CC.Register(f)
            if f.PetFrame then CC.Register(f.PetFrame) end
        end
    end
    if not compactHooked and type(_G.CompactUnitFrame_SetUpFrame) == "function" then
        compactHooked = true
        hooksecurefunc("CompactUnitFrame_SetUpFrame", function(frame)
            local cc = Cfg()
            -- a secure unit frame only, in combat too (a frame let in here
            -- would get attributes and wrapped scripts when it ends)
            if cc and cc.blizzard and frame and not CC.frames[frame] and Usable(frame) then
                if InCombatLockdown() then waiting[frame] = true; CC.frames[frame] = true
                else CC.Register(frame) end
            end
        end)
    end
end

-- ============================================================
-- APPLY
-- ============================================================
local function Serialize(attrs)
    local s = {}
    for _, a in ipairs(attrs) do
        local v = a[2]
        if type(v) == "string" then
            -- newlines travel as \001 (the records are one per line)
            s[#s + 1] = (a.soft and "?" or "") .. a[1] .. "\t" .. (v:gsub("\001", ""):gsub("\n", "\001"))
        end
    end
    return table.concat(s, "\n")
end

local pendingApply = false
function CC.Apply(inCombat)
    if CC.standDown or not CC.running then return end
    if InCombatLockdown() then pendingApply = true return end
    pendingApply = false
    local frameAttrs, keys, world, worldAttrs, skipped = CC.Build(inCombat)
    CC._frameAttrs = frameAttrs
    CC.skipped = skipped
    local clear = {}
    for _, a in ipairs(frameAttrs) do everSet[a[1]] = true end
    for name in pairs(everSet) do clear[#clear + 1] = name end
    clearString = table.concat(clear, "\n")
    attrString = Serialize(frameAttrs)
    local k = {}
    for _, e in ipairs(keys) do k[#k + 1] = e[1] .. "=" .. e[2] end
    keyString = table.concat(k, ";")
    header:SetAttribute("zcc_clear", clearString)
    header:SetAttribute("zcc_attrs", attrString)
    header:SetAttribute("zcc_keys", keyString)
    for f in pairs(CC.frames) do ApplyTo(f) end
    for f in pairs(waiting) do waiting[f] = nil; if CC.frames[f] then ApplyTo(f) end end
    -- the world button: its attributes, and the override bindings to it
    ClearOverrideBindings(worldButton)
    for name in pairs(worldButton.__zccSet or {}) do worldButton:SetAttribute(name, nil) end
    worldButton.__zccSet = {}
    for _, a in ipairs(worldAttrs) do
        worldButton:SetAttribute(a[1], a[2])
        worldButton.__zccSet[a[1]] = true
    end
    for _, e in ipairs(world) do
        SetOverrideBindingClick(worldButton, true, e[1], "ZacUIClickCastWorld", e[2])
    end
end

-- after any change on the page
function CC.Changed()
    if CC.standDown then return end
    if InCombatLockdown() then
        pendingApply = true
        Print("click casting: your change applies when this fight ends.")
        return
    end
    CC.Apply(false)
end

-- out of combat only: everything off (the module switched off)
function CC.Clear()
    if InCombatLockdown() or not header then return end
    CC._frameAttrs = {}
    for f in pairs(CC.frames) do
        for name in pairs(everSet) do f:SetAttribute(name, nil) end
    end
    header:SetAttribute("zcc_attrs", "")
    header:SetAttribute("zcc_keys", "")
    ClearOverrideBindings(worldButton)
end

-- ============================================================
-- START
-- ============================================================
local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        -- the last moment attributes may change: drop the out-of-combat set
        local hasOoc = false
        for _, b in ipairs(Bindings()) do if b.sets and b.sets.ooc then hasOoc = true break end end
        if hasOoc then CC.Apply(true) end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if CC._needClear and not CC.running then CC._needClear = nil; CC.Clear() return end
        -- one Apply covers a change made in the fight, frames that arrived
        -- in it, and putting the out-of-combat set back
        local again = pendingApply or next(waiting) ~= nil
        if not again then
            for _, b in ipairs(Bindings()) do if b.sets and b.sets.ooc then again = true break end end
        end
        if again then CC.Apply(false) end
    elseif event == "PLAYER_LOGIN" then
        local c = Cfg()
        if not (c and c.enabled) then return end
        CC.running = true
        RegisterBlizzard()
        -- ZacUF registers its frames in its own PLAYER_LOGIN; one frame
        -- later everything that wants click casting is in the table
        C_Timer.After(0, function() CC.Apply(false) end)
        events:RegisterEvent("PLAYER_REGEN_DISABLED")
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
    end
end)

if not CC.standDown then
    BuildHeader()
    OwnTables()
    events:RegisterEvent("PLAYER_LOGIN")
end

-- switched on / off from the page (off takes everything back out)
function CC.SetEnabled(on)
    local c = Cfg()
    if not c then return end
    c.enabled = on and true or false
    if CC.standDown then return end
    if on then
        if not CC.running then
            CC.running = true
            RegisterBlizzard()
            events:RegisterEvent("PLAYER_REGEN_DISABLED")
            events:RegisterEvent("PLAYER_REGEN_ENABLED")
        end
        CC.Changed()
    else
        CC.running = false
        if InCombatLockdown() then
            Print("click casting: switches off when this fight ends.")
            pendingApply = false
            CC._needClear = true
        else
            CC.Clear()
        end
    end
end
