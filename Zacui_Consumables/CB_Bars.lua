-- CB_Bars - the three live bars: their frames, their secure buttons (one
-- click uses the item, puts a stone on a weapon, casts a juju on
-- yourself), the events they hear and the two tickers that keep them
-- current. Readycheck's consumables, potion and weapon bars, ZacUI's way.
-- Part of ZacUI; load order is set by the TOC.
--
-- SECURE BUTTONS. A button that uses an item has to be a secure one, and
-- in combat nothing about it may change: no Show / Hide, no attribute, no
-- moving. So a bar is laid out out of combat only; anything that wants a
-- new layout mid-fight waits for PLAYER_REGEN_ENABLED (pending). In
-- combat only alpha moves: a used item's button fades out, a bar set to
-- hide in combat goes see-through (its buttons still take a click).
--
-- COST. The hot events (BAG_UPDATE_DELAYED, BAG_UPDATE_COOLDOWN,
-- SPELL_UPDATE_COOLDOWN, the aura news) only mark something dirty or
-- start a ticker. The work runs in:
--   the drain     a rebuild a moment after its news (at most one per bar
--                 per half second)
--   the fast tick 0.2 s while a swirl, a cooldown or a cast is live (the
--                 full button pass about once a second unless you just
--                 clicked or are casting); it stops itself
--   the slow tick 1 s while a bar is up: running-out times, the voice

local ADDON_NAME = ...
local ns = _G.ZacUI
if not ns then return end
local D, CB = ns.ConsData, ns.ConsBars
if not (D and CB and CB.Button) then return end

local B, W = CB.Button, CB.World
local UI = ns.UI
local FLAT = ns.FLAT or "Interface\\Buttons\\WHITE8X8"
local GetTime, pairs, ipairs, type, tonumber = GetTime, pairs, ipairs, type, tonumber

local Live = { bars = {}, pending = {}, dirty = {}, lastBuild = {}, stable = true }
CB.Live = Live
local SHORT = { main = "Main", potions = "Potions", weapons = "Weapons" }
function CB.MoverKey(key) return "consbars_" .. key end

local function Track(t, name)
    if ns.Profiler and ns.Profiler.TrackTicker then ns.Profiler.TrackTicker(t, name) end
    return t
end

-- ============================================================
-- THE FRAME - a plain holder (the mover drags it, the visibility rule
-- fades it) with the bar inside at its own scale
-- ============================================================
local function Bar(key)
    local st = Live.bars[key]
    if not st then st = { key = key, buttons = {}, shown = {} } Live.bars[key] = st end
    return st
end
Live.Bar = Bar

-- the bar's spot: the mover's, else where it starts
function Live.Place(key)
    local st = Bar(key)
    local h = st.holder
    if not h or InCombatLockdown() then return end
    local pos = ZacUIDB and ZacUIDB.movers and ZacUIDB.movers[CB.MoverKey(key)]
    local d = CB.DefaultSpot(key)
    h:ClearAllPoints()
    if type(pos) == "table" then
        h:SetPoint(pos.point or "CENTER", UIParent, pos.point or "CENTER", pos.x or 0, pos.y or 0)
    else
        h:SetPoint(d.point, UIParent, d.point, d.x, d.y)
    end
end

-- where the bar is now, as a mover spot (its top left corner)
local function SaveSpot(key)
    local h = Bar(key).holder
    local l, t = h:GetLeft(), h:GetTop()
    if not (l and t) then return end
    local k = h:GetEffectiveScale() / UIParent:GetEffectiveScale()
    ZacUIDB.movers = ZacUIDB.movers or {}
    ZacUIDB.movers[CB.MoverKey(key)] = { point = "TOPLEFT", x = l * k, y = t * k - UIParent:GetHeight() }
end

-- the bar's fill, edge (gold while it can be dragged) and accent line
function Live.PaintChrome(box, cfg, unlocked)
    local show = cfg.showBackground and true or false
    local r, g, b, a = B.BarColor(cfg, "frameBackground")
    if show then box.bg:SetVertexColor(r, g, b, a) else box.bg:SetVertexColor(0, 0, 0, 0) end
    local er, eg, eb, ea = B.BarColor(cfg, "frameBorder")
    if unlocked then
        local c = ns.GetColor and ns.GetColor("ui", "accent") or { r = 0.85, g = 0.65, b = 0.25 }
        er, eg, eb, ea = c.r, c.g, c.b, 0.9
    end
    B.EachStrip(box.edge, function(t) t:SetVertexColor(er, eg, eb, ea) t:SetShown(show or unlocked) end)
    local ar, ag, ab, aa = B.BarColor(cfg, "accentLine")
    box.accent:SetVertexColor(ar, ag, ab, aa * 0.5)
    box.accent:SetShown(show)
end
-- a bar's frame pieces (the preview builds its sample with the same)
function Live.NewBox(parent)
    local box = CreateFrame("Frame", nil, parent)
    box.bg = box:CreateTexture(nil, "BACKGROUND")
    box.bg:SetAllPoints()
    box.bg:SetTexture(FLAT)
    box.edge = B.Strips(box, "BORDER")
    box.accent = box:CreateTexture(nil, "BORDER", nil, 1)
    box.accent:SetTexture(FLAT)
    -- (one physical pixel, inside the edge, under ZacUI's look: HD polish)
    local px = ZacUI.Pixel and ZacUI.Pixel.One(box) or 1
    box.accent:SetPoint("TOPLEFT", px, -px)
    box.accent:SetPoint("TOPRIGHT", -px, -px)
    if ZacUI.Pixel then ZacUI.Pixel.Edge(box.accent, "TOP", box) else box.accent:SetHeight(1) end
    return box
end

local function Hovered(key, on)
    local st = Bar(key)
    st.hover = on
    Live.ApplyFade(key)
end

-- the box's alpha: see-through in combat when it hides then, the
-- mouseover fade otherwise (the holder's alpha is the visibility rule's)
function Live.ApplyFade(key, instant)
    local st = Bar(key)
    local box = st.box
    if not box then return end
    local cfg = CB.Bar(key)
    local target = 1
    if Live.combat and cfg.hideInCombat and not (key == "main" and Live.keepInCombat) then target = 0
    elseif cfg.mouseoverFade and not st.hover then target = tonumber(cfg.mouseoverFadeAlpha) or 0.15 end
    -- the visibility rule's opacity on top (nil: none saved)
    local va = st.holder and ns.Visibility and ns.Visibility.TargetAlpha and ns.Visibility.TargetAlpha(st.holder)
    if va then target = target * va end
    local fi, fo = B.FadeTimes(cfg)
    local M = ns.Motion
    if instant or not (M and M.FadeTo) or target == 0 then
        if M and M.TweenStop then pcall(M.TweenStop, box) end
        box:SetAlpha(target)
    else
        M.FadeTo(box, target, { style = "fade", duration = target < (box:GetAlpha() or 1) and fo or fi })
    end
end

local function Build(key)
    local st = Bar(key)
    if st.holder then return true end
    if InCombatLockdown() then return false end
    local h = CreateFrame("Frame", "ZacUIConsBar" .. SHORT[key], UIParent)
    h:SetSize(46, 46)
    h:SetClampedToScreen(true)
    h:SetMovable(true)
    h:EnableMouse(true)
    h:RegisterForDrag("LeftButton")
    h:Hide()
    local box = Live.NewBox(h)
    box:SetPoint("TOPLEFT", h, "TOPLEFT", 0, 0)
    box:SetSize(46, 46)
    st.holder, st.box = h, box
    -- unlocked: drag the bar itself; right click locks / unlocks it
    h:SetScript("OnDragStart", function(self)
        if InCombatLockdown() or CB.Bar(key).locked ~= false then return end
        self:StartMoving()
    end)
    h:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if not InCombatLockdown() then SaveSpot(key) Live.Place(key) end
    end)
    h:SetScript("OnMouseUp", function(_, mb)
        if mb == "RightButton" and not InCombatLockdown() then Live.ToggleLock(key) end
    end)
    h:SetScript("OnEnter", function(self)
        Hovered(key, true)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(CB.LABELS[key], 1, 1, 1)
        GameTooltip:AddLine(CB.Bar(key).locked ~= false and "Right click to unlock" or "Drag to move - right click to lock",
            0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    h:SetScript("OnLeave", function() Hovered(key, false) GameTooltip:Hide() end)
    if ns.RegisterMover then
        local d = CB.DefaultSpot(key)
        -- secure: the bar holds the item buttons, so its box locks in a fight
        ns.RegisterMover(CB.MoverKey(key), CB.LABELS[key], function() return h end, d.point, d.x, d.y, nil,
            { secure = true, reset = function() Live.Place(key) end })
    end
    -- when it shows (visibility, ZacUI's shape): its opacity goes into the
    -- box's (alpha only - the bar holds secure buttons; the holder's own
    -- alpha is its show / hide animation's). Nothing saved = never touched.
    if ns.Visibility and ns.Visibility.Register then
        ns.Visibility.Register(h, function() return CB.Bar(key).visibility end,
            { control = "gate", onChange = function() Live.ApplyFade(key) end })
    end
    Live.Place(key)
    return true
end
Live.Build = Build

function Live.ToggleLock(key)
    local cfg = CB.Bar(key)
    cfg.locked = cfg.locked == false
    Live.Request(key)
    if ns.SettingsChanged then ns.SettingsChanged("consbars.lock") end
end

-- ============================================================
-- THE BUTTONS
-- ============================================================
local function ForwardDrag(btn, script)
    local h = Bar(btn.barKey).holder
    local f = h and h:GetScript(script)
    if f then f(h) end
end

local Tooltip   -- below
local modHover  -- the grouped button under the mouse (its modifier preview)

local function NewButton(key, id)
    local st = Bar(key)
    local b = CreateFrame("Button", "ZacUICons" .. SHORT[key] .. id, st.box, "SecureActionButtonTemplate")
    b:SetSize(32, 32)
    b:EnableMouse(true)
    b:SetAttribute("useOnKeyDown", false)
    b:RegisterForClicks("AnyUp")
    B.Dress(b, false)
    b.barKey = key
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnDragStart", function(self) ForwardDrag(self, "OnDragStart") end)
    b:SetScript("OnDragStop", function(self) ForwardDrag(self, "OnDragStop") end)
    b:SetScript("OnEnter", function(self)
        B.SetHover(self, true)
        Hovered(key, true)
        if self.entry and self.entry.grouped then modHover = self Live.ModifierPreview() end
        if CB.Bar(key).showTooltips then Tooltip(self) end
    end)
    b:SetScript("OnLeave", function(self)
        B.SetHover(self, false)
        Hovered(key, false)
        if modHover == self then modHover = nil Live.ModifierPreview(true, self) end
        GameTooltip:Hide()
    end)
    -- the click marks the use, so the swirl lands on this button
    b:HookScript("PreClick", function(self)
        Live.lastUse, Live.lastUseId = GetTime(), self.itemId
        CB.NoteNamedUse(self.itemId)
        Live.StartFast()
    end)
    -- right click: the stone picker on a weapon button, the pick of a
    -- grouped button (the weapon bar's clicks are its own settings)
    b:HookScript("OnMouseUp", function(self, mb)
        if InCombatLockdown() then return end
        local data = self.data or {}
        if key == "weapons" then
            if (data.unified or data.bagWeapon) and Live.WeaponClickAction(Live.ClickSlot(mb)) == "picker" then
                Live.StonePicker(self)
            end
            return
        end
        if mb ~= "RightButton" then return end
        if data.unified or data.bagWeapon then Live.StonePicker(self)
        elseif self.entry and self.entry.grouped and self.entry.group then Live.GroupPicker(self, self.entry.group) end
    end)
    st.buttons[id] = b
    return b
end

-- ---- what a click does (out of combat only) ----
local WEAPON_CLICK_DEFAULTS = { left = "stone", right = "picker", shiftLeft = "equipMH", shiftRight = "equipOH",
    ctrlLeft = "none", ctrlRight = "none" }
CB.WEAPON_CLICK_DEFAULTS = WEAPON_CLICK_DEFAULTS
CB.CLICK_SLOTS = { { "left", "Left click" }, { "right", "Right click" }, { "shiftLeft", "Shift + left" },
    { "shiftRight", "Shift + right" }, { "ctrlLeft", "Ctrl + left" }, { "ctrlRight", "Ctrl + right" } }
CB.CLICK_ACTIONS = { { "stone", "Put the stone on" }, { "picker", "Choose the stone" }, { "equipMH", "Equip in the main hand" },
    { "equipOH", "Equip in the off hand" }, { "none", "Nothing" } }
function Live.WeaponClickAction(slot)
    local ca = CB.T(CB.Bar("weapons"), "clickActions")
    if ca and ca[slot] ~= nil then return ca[slot] end
    return WEAPON_CLICK_DEFAULTS[slot] or "none"
end
function Live.ClickSlot(mb)
    local right = mb == "RightButton"
    if IsShiftKeyDown and IsShiftKeyDown() then return right and "shiftRight" or "shiftLeft" end
    if IsControlKeyDown and IsControlKeyDown() then return right and "ctrlRight" or "ctrlLeft" end
    return right and "right" or "left"
end
local CLAUSE = { left = "button:1,nomod", right = "button:2,nomod", shiftLeft = "button:1,mod:shift",
    shiftRight = "button:2,mod:shift", ctrlLeft = "button:1,mod:ctrl", ctrlRight = "button:2,mod:ctrl" }
local CLEAR = { "type1", "macrotext1", "type2", "macrotext2", "shift-type1", "shift-macrotext1", "shift-type2",
    "shift-macrotext2", "ctrl-type1", "ctrl-macrotext1", "ctrl-type2", "ctrl-macrotext2", "alt-type1", "alt-item1",
    "alt-macrotext1", "shift-item1", "ctrl-item1", "item", "macrotext", "type" }

-- The weapon macro: the stone, then the weapon (slot 16 / 17, or the bag
-- slot), then the "replace the enchant?" popup's Yes - but never while
-- dead, when the first popup is Release Spirit.
function CB.WeaponMacro(key, data, stone)
    local target, wname
    if data.bagWeapon then
        target, wname = data.bag .. " " .. data.bagSlot, data.name
    else
        local inv = data.slot == "mainhand" and 16 or 17
        target = tostring(inv)
        local link = GetInventoryItemLink and GetInventoryItemLink("player", inv)
        wname = link and link:match("%[(.-)%]")
    end
    local cond = { stone = "", equipMH = "", equipOH = "" }
    if key == "weapons" then
        for _, s in ipairs(CB.CLICK_SLOTS) do
            local act = Live.WeaponClickAction(s[1])
            if cond[act] ~= nil then cond[act] = cond[act] .. "[" .. CLAUSE[s[1]] .. "]" end
        end
    else
        cond.stone = "[" .. CLAUSE.left .. "][" .. CLAUSE.right .. "]"
    end
    local lines = {}
    if cond.stone ~= "" then
        lines[#lines + 1] = "/use " .. cond.stone .. " item:" .. tostring(stone)
        lines[#lines + 1] = "/use " .. cond.stone .. " " .. target
    end
    if cond.equipMH ~= "" and wname then lines[#lines + 1] = "/equipslot " .. cond.equipMH .. " 16 " .. wname end
    if cond.equipOH ~= "" and wname then lines[#lines + 1] = "/equipslot " .. cond.equipOH .. " 17 " .. wname end
    lines[#lines + 1] = "/click [nodead] StaticPopup1Button1"
    return table.concat(lines, "\n")
end

-- what one click on an item does: use it (a juju on yourself; the flask
-- of petrification with a /camp when asked)
local function UseAttrs(key, cfg, data, prefix, suffix)
    local name = data.name
    if not name then return nil end
    if data.id == 13506 and cfg.petrificationCampMode then
        return { [prefix .. "type" .. suffix] = "macro", [prefix .. "macrotext" .. suffix] = "/use Flask of Petrification\n/camp" }
    end
    if data.selfCastOnly and (key ~= "main" or cfg.selfCastJujus ~= false) then
        return { [prefix .. "type" .. suffix] = "macro", [prefix .. "macrotext" .. suffix] = "/use [@player] " .. name }
    end
    return { [prefix .. "type" .. suffix] = "item", [prefix .. "item" .. suffix] = name }
end
CB.UseAttrs = UseAttrs

local MODS = { { "shiftClick", "shift-" }, { "altClick", "alt-" }, { "ctrlClick", "ctrl-" } }
CB.QUICK_MODS = { { "click", "Click" }, { "shiftClick", "Shift" }, { "altClick", "Alt" }, { "ctrlClick", "Ctrl" } }
local function ItemData(id)
    local it = D.BY_ID[id]
    if it then
        local t = {}
        for k, v in pairs(it) do t[k] = v end
        t.id = id
        return t
    end
    local nm = GetItemInfo and GetItemInfo(id)
    return nm and { id = id, name = nm } or nil
end

function Live.Secure(b, key, cfg, e)
    if InCombatLockdown() then return false end
    for _, a in ipairs(CLEAR) do b:SetAttribute(a, nil) end
    local data = e.data
    if data.unified or data.bagWeapon then
        b:SetAttribute("type", "macro")
        b:SetAttribute("macrotext", CB.WeaponMacro(key, data, data.baseItemId))
        -- on the consumables bar the right click is the stone picker
        if key == "weapons" then b:RegisterForClicks("AnyUp") else b:RegisterForClicks("LeftButtonUp") end
        return true
    end
    b:RegisterForClicks("AnyUp")
    local d = {}
    for k, v in pairs(data) do d[k] = v end
    d.id = e.id
    -- a grouped button's click: its pick for that group, or the item itself
    local base = d
    local quick = e.grouped and CB.T(cfg, "conflictGroupQuickUse") and cfg.conflictGroupQuickUse[e.group]
    if quick and quick.click then base = ItemData(quick.click) or d end
    for k, v in pairs(UseAttrs(key, cfg, base, "", "") or {}) do b:SetAttribute(k, v) end
    -- shift / alt / ctrl + click: the group's other picks (secure modifier
    -- attributes, so it holds in combat)
    if quick then
        for _, m in ipairs(MODS) do
            local qid = quick[m[1]]
            local qd = qid and ItemData(qid)
            if qd then for k, v in pairs(UseAttrs(key, cfg, qd, m[2], "1") or {}) do b:SetAttribute(k, v) end end
        end
    end
    return true
end

-- the grouped button under the mouse shows what a modifier would use
function Live.ModifierPreview(restore, btn)
    local b = btn or modHover
    if not (b and b.entry) then return end
    local e = b.entry
    if restore then
        b.icon:SetTexture(B.IconFor(e.id, e.data, W, CB.Cfg().weaponIcons))
        return
    end
    local quick = CB.T(CB.Bar(b.barKey), "conflictGroupQuickUse") and CB.Bar(b.barKey).conflictGroupQuickUse[e.group]
    if not quick then return end
    local k = "click"
    if IsControlKeyDown and IsControlKeyDown() then k = "ctrlClick"
    elseif IsAltKeyDown and IsAltKeyDown() then k = "altClick"
    elseif IsShiftKeyDown and IsShiftKeyDown() then k = "shiftClick" end
    local id = quick[k]
    b.icon:SetTexture((id and W.ItemIcon(id)) or B.IconFor(e.id, e.data, W, CB.Cfg().weaponIcons))
end

Tooltip = function(b)
    local e, data = b.entry, b.data or {}
    if not e then return end
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    local cid = data.baseItemId or b.itemId
    if data.bagWeapon and data.weaponLink then
        GameTooltip:SetHyperlink(data.weaponLink)
        local n = W.Count(cid)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Apply: " .. CB.StoneName(cid), 0.5, 0.8, 1)
        GameTooltip:AddLine("Stones in bags: " .. n, 0.7, 0.7, 0.7)
        if n > 0 then GameTooltip:AddLine("Click to apply stone", 0.3, 1, 0.3)
        else GameTooltip:AddLine("No stones available!", 1, 0.3, 0.3) end
        GameTooltip:Show()
        return
    end
    if GameTooltip.SetItemByID then GameTooltip:SetItemByID(cid) end
    local n = W.Count(cid)
    local has, rem, eid, lowCh = B.OwnState(b, W)
    local g = (not D.OWN_TIMER[cid]) and D.GROUP_OF[cid] or nil
    local hasG, gt, gi = false, 0, nil
    if g then hasG, gt, gi = W.GroupBuff(g) end
    local function Time(t) local m, s = math.floor(t / 60), math.floor(t % 60) return m > 0 and (m .. "m " .. s .. "s") or (s .. "s") end
    GameTooltip:AddLine(" ")
    if has then
        if data.slot then
            local stone = eid and D.ENCHANT_TO_STONE[eid]
            GameTooltip:AddLine("Applied to " .. (data.slot == "mainhand" and "Main Hand" or "Off Hand") .. ": "
                .. (stone and CB.StoneName(stone) or "Unknown enchant"), 0.3, 1, 0.3)
            local _, _, _, ch, _, real = W.Enchant(data.slot)
            if (ch or 0) > 0 then rem = real or rem end
            GameTooltip:AddLine("Active: " .. Time(rem) .. " remaining", 0.3, 1, 0.3)
            if (ch or 0) > 0 then
                local c = ns.GetColor("text", ch <= D.POISON_LOW_CHARGES and "red" or "green")
                GameTooltip:AddLine(ch .. " charges left", c.r, c.g, c.b)
            end
            if n > 0 then GameTooltip:AddLine("Left-click to reapply", 1, 1, 0.5) end
        else
            GameTooltip:AddLine("Active: " .. Time(rem) .. " remaining", 0.3, 1, 0.3)
        end
    elseif hasG and gi ~= cid then
        GameTooltip:AddLine("Conflict buff active: " .. Time(gt), 1, 0.8, 0.3)
    elseif n > 0 then
        local t = data.slot == "mainhand" and "Left-click to apply to main hand"
            or data.slot == "offhand" and "Left-click to apply to off hand" or "Left-click to use"
        GameTooltip:AddLine(t, 0.3, 1, 0.3)
    else
        GameTooltip:AddLine("Not in bags", 1, 0.3, 0.3)
    end
    if data.unified then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Current: " .. CB.ShortStone(CB.ValidStone(data.slot)), 0.9, 0.8, 0.5)
        GameTooltip:AddLine(CB.IsRogue() and "Right-click to change poison or stone" or "Right-click to change stone type", 0.7, 0.7, 0.7)
    end
    GameTooltip:Show()
end

-- ---- the two pickers ----
function Live.SelectStone(id, b)
    local c = CB.Cfg()
    local slot = b and b.data and b.data.slot
    if (slot == "mainhand" or slot == "offhand") and CB.IsRogue() then
        if type(c.stoneBySlot) ~= "table" then c.stoneBySlot = {} end
        c.stoneBySlot[slot] = id
    else
        c.stone = id
    end
    Live.Request("main", true) Live.Request("weapons", true)
    if ns.SettingsChanged then ns.SettingsChanged("consbars.stone") end
end
function Live.StonePicker(b)
    if not (UI and UI.ContextMenu) then return end
    local slot = b.data and b.data.slot
    local cur = CB.ValidStone(slot)
    local items = { { text = CB.IsRogue() and "Select Poison or Stone" or "Select Stone Type", isTitle = true } }
    for _, s in ipairs(D.STONES) do
        local n = W.Count(s.id)
        if n > 0 then
            local id = s.id
            local icon = W.ItemIcon(id)
            items[#items + 1] = { text = (icon and ("|T" .. icon .. ":14|t ") or "") .. s.name .. " (" .. n .. ")",
                checked = id == cur, func = function() Live.SelectStone(id, b) end }
        end
    end
    if #items == 1 then items[2] = { text = CB.IsRogue() and "No poisons or stones in bags" or "No stones in bags", disabled = true } end
    UI.ContextMenu(items, { anchor = b })
end
-- the clash group's menu: Auto, then each rival with how many you carry
-- (world: the live bags, or the settings preview's made-up ones)
function Live.GroupPickerItems(barKey, g, world)
    local prio = D.PRIORITY[g]
    if not prio then return nil end
    world = world or W
    local cfg = CB.Bar(barKey)
    local prefs = CB.T(cfg, "conflictGroupPreferences") or {}
    local function Set(v)
        if type(cfg.conflictGroupPreferences) ~= "table" then cfg.conflictGroupPreferences = {} end
        cfg.conflictGroupPreferences[g] = v
        if next(cfg.conflictGroupPreferences) == nil then cfg.conflictGroupPreferences = nil end
        Live.Request(barKey, true)
        if ns.SettingsChanged then ns.SettingsChanged("consbars.group") end
    end
    local items = { { text = "Auto (first available)", checked = prefs[g] == nil, func = function() Set(nil) end },
        { separator = true } }
    for _, id in ipairs(prio) do
        local nm = world.ItemName(id) or (D.BY_ID[id] and D.BY_ID[id].name) or ("Item #" .. id)
        local n = world.Count(id)
        local iid = id
        items[#items + 1] = { text = nm .. (n > 0 and (" (" .. n .. ")") or " |cff888888(none)|r"),
            checked = prefs[g] == id, func = function() Set(iid) end }
    end
    return items
end
function Live.GroupPicker(b, g)
    if not (UI and UI.ContextMenu) then return end
    local items = Live.GroupPickerItems(b.barKey, g, W)
    if items then UI.ContextMenu(items, { anchor = b }) end
end

-- ============================================================
-- LAYING A BAR OUT (out of combat only)
-- ============================================================
local function Wanted(key)
    local cfg = CB.Bar(key)
    if not cfg.enabled then return false end
    if Live.moving then return true end
    return CB.ShowIn(cfg)
end
Live.Wanted = Wanted

local function ShowHolder(key, cfg)
    local h = Bar(key).holder
    if h:IsShown() then return end
    local M = ns.Motion
    if M and not InCombatLockdown() then M.Show(h, B.Spec(cfg, "showAnim")) else h:Show() end
end
local function HideHolder(key, cfg)
    local h = Bar(key).holder
    if not (h and h:IsShown()) then return end
    local M = ns.Motion
    if M and not InCombatLockdown() then M.Hide(h, B.Spec(cfg, "hideAnim")) else h:Hide() end
end

function Live.Rebuild(key)
    local cfg = CB.Bar(key)
    if InCombatLockdown() then Live.pending[key] = true return false end
    Live.pending[key] = nil
    Live.dirty[key] = nil
    Live.lastBuild[key] = GetTime()
    if not Wanted(key) then
        if Bar(key).holder then HideHolder(key, cfg) end
        return true
    end
    if not Build(key) then Live.pending[key] = true return false end
    local st = Bar(key)
    local entries, nextCross = CB.Collect(key, cfg, W)
    st.entries, st.nextCross = entries, nextCross
    local size, per, gap, grow = CB.Geo(cfg)
    local used = {}
    st.shown = {}
    for i, e in ipairs(entries) do
        local b = st.buttons[e.id] or NewButton(key, e.id)
        used[e.id] = true
        b:SetSize(size, size)
        if b._zSize ~= size then b._zSig = nil end
        b._zSize = size
        B.Fill(b, e, key, cfg, W)
        Live.Secure(b, key, cfg, e)
        local x, y, row, col = CB.GridOffset(i, per, size, gap, grow)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", st.box, "TOPLEFT", x, y)
        b.gridRow, b.gridCol = row, col
        if b._zSpent and not Live.combat then b._zSpent = nil B.SetHidden(b, false) end
        b:Show()
        st.shown[#st.shown + 1] = b
    end
    for id, b in pairs(st.buttons) do if not used[id] then b:Hide() end end
    local w, h = CB.BarSize(#entries, per, size, gap, grow)
    local sc = tonumber(cfg.scale) or 1
    if sc <= 0 then sc = 1 end
    st.box:SetScale(sc)
    st.box:SetSize(w, h)
    st.holder:SetSize(w * sc, h * sc)
    Live.PaintChrome(st.box, cfg, cfg.locked == false)
    -- layer / level / keep on screen (position); shadow and glow (chrome)
    if ns.ApplyFramePosition and (CB.T(cfg, "position") or st._zPos) then
        st._zPos = CB.T(cfg, "position") ~= nil
        local p = CB.T(cfg, "position") or {}
        ns.ApplyFramePosition(st.holder, { strata = p.strata, level = p.level, clamp = p.clamp })
    end
    if ns.ApplyChrome and (CB.T(cfg, "chrome") or st.holder._zcShadow or st.holder._zcGlow) then
        ns.ApplyChrome(st.holder, cfg.chrome)
    end
    if #entries == 0 then HideHolder(key, cfg) else ShowHolder(key, cfg) end
    Live.ApplyFade(key, true)
    if ns.Visibility and ns.Visibility.Refresh then ns.Visibility.Refresh(st.holder, true) end
    Live.TickBar(key, true)
    Live.StartSlow()
    return true
end

-- a rebuild soon (news in): at most one per bar per half second
local drainQueued = false
local function Drain()
    drainQueued = false
    if Live.auraDirty then Live.CheckAuras() end
    local now = GetTime()
    local again = false
    for _, key in ipairs(CB.BARS) do
        if Live.dirty[key] then
            if InCombatLockdown() then Live.pending[key] = true Live.dirty[key] = nil
            elseif now - (Live.lastBuild[key] or 0) < 0.5 then again = true
            else Live.Rebuild(key) end
        end
    end
    if again and not drainQueued then
        drainQueued = true
        C_Timer.After(0.5, Drain)
    end
end
function Live.Request(key, now)
    if key == nil then
        for _, k in ipairs(CB.BARS) do Live.dirty[k] = true end
    else
        Live.dirty[key] = true
    end
    if now and not InCombatLockdown() then
        if key then Live.lastBuild[key] = 0 else for _, k in ipairs(CB.BARS) do Live.lastBuild[k] = 0 end end
    end
    if not drainQueued then
        drainQueued = true
        C_Timer.After(0.1, Drain)
    end
end
Live.Drain = Drain

-- ============================================================
-- KEEPING THE BUTTONS CURRENT
-- ============================================================
local ctx = {}
local function Context()
    ctx.now = GetTime()
    ctx.eating, ctx.eatLeft = W.Eating()
    ctx.lastUse, ctx.lastUseId = Live.lastUse, Live.lastUseId
    local name, s, e = W.Cast()
    ctx.cast = ctx.cast or {}
    ctx.cast.name, ctx.cast.start, ctx.cast.stop = name, s, e
    return ctx
end
function Live.TickBar(key, force)
    local st = Live.bars[key]
    if not (st and st.holder and st.holder:IsShown()) then return false end
    local cfg = CB.Bar(key)
    local c = Context()
    local live = false
    for _, b in ipairs(st.shown) do
        if b:IsShown() then
            B.Tick(b, key, cfg, W, c, force)
            if b.cooldownFrame:IsShown() or b.gcdFrame:IsShown() or b.castFrame:IsShown() then live = true end
        end
    end
    return live
end

-- the fast pass (0.2 s): only while something moves
local fast, fastTicks = nil, 0
function Live.StartFast()
    if fast then return end
    fastTicks = 0
    fast = Track(C_Timer.NewTicker(0.2, function()
        fastTicks = fastTicks + 1
        local now = GetTime()
        local busy = (W.Cast() ~= nil) or (Live.lastUse and now - Live.lastUse < 1.0)
        if not busy and fastTicks % 5 ~= 1 then return end
        local any, live = false, false
        for _, key in ipairs(CB.BARS) do
            local st = Live.bars[key]
            if st and st.holder and st.holder:IsShown() then
                any = true
                if Live.TickBar(key, busy) then live = true end
            end
        end
        if (W.Eating()) then live = true end
        if not any or (not live and not busy) then Live.StopFast() end
    end), "consbars.fast")
end
function Live.StopFast()
    if fast then fast:Cancel() fast = nil end
    local eating = W.Eating()
    for _, st in pairs(Live.bars) do
        for _, b in ipairs(st.shown or {}) do B.ClearLive(b, eating) end
    end
end

-- the slow pass (1 s): a buff crossing into its warning window brings
-- its button back, running-out times, the voice
local slow
function Live.StartSlow()
    if slow then return end
    slow = Track(C_Timer.NewTicker(1.0, function()
        local any = false
        local now = GetTime()
        for _, key in ipairs(CB.BARS) do
            local cfg = CB.Bar(key)
            local st = Live.bars[key]
            -- running while a bar is up, a hidden button is waiting for its
            -- buff to run low, or the voice is listening
            if cfg.enabled and ((st and st.holder and st.holder:IsShown()) or (st and st.nextCross) or cfg.tts
                or (key == "main" and (CB.Cfg().potionReadyTTS or CB.Cfg().ttsRepeat))) then
                any = true
                if st and st.nextCross and now >= st.nextCross then
                    st.nextCross = nil
                    if InCombatLockdown() then Live.pending[key] = true
                        -- the button cannot come back mid-fight; the bar can
                        if key == "main" and CB.Bar(key).hideInCombat then Live.keepInCombat = true Live.ApplyFade(key) end
                    else Live.Request(key) end
                end
                if not fast then Live.TickBar(key, false) end
            end
        end
        if CB.Voice then CB.Voice.Tick(now) end
        if not any then slow:Cancel() slow = nil end
    end), "consbars.slow")
end

-- ============================================================
-- USED IN COMBAT - its button goes for the rest of the fight
-- ============================================================
function Live.Spend(id)
    if not (id and InCombatLockdown()) then return end
    local cfg = CB.Bar("main")
    if cfg.hideUsedInCombat == false then return end
    local st = Live.bars.main
    if not st then return end
    local base = D.BY_ID[id] and D.BY_ID[id].baseItemId
    for bid, b in pairs(st.buttons) do
        local d = b.data or {}
        if (bid == id or bid == base or (d.baseItemId and not d.unified and not d.bagWeapon
            and (d.baseItemId == id or d.baseItemId == base))) and not b._zSpent then
            b._zSpent = true
            B.SetHidden(b, true)
        end
    end
end

-- ============================================================
-- THE AURA NEWS (a frame after the burst, through the shared read)
-- ============================================================
local lastConsumables
local function ConsumableBuffs()
    local ids, names = CB.BuffMaps()
    local out = {}
    for sid, a in pairs(ids) do
        if D.BY_BUFF[sid] then out[sid] = tonumber(a.expirationTime) or 0 end
    end
    -- (TBC / Forever: the buffs known only by name, keyed by that name)
    for n in pairs(D.BY_BUFF_NAME or {}) do
        local a = names[n]
        if a and not (a.spellId and D.BY_BUFF[a.spellId]) then out[n] = tonumber(a.expirationTime) or 0 end
    end
    return out
end
function Live.CheckAuras()
    Live.auraDirty = false
    local now = ConsumableBuffs()
    local before = lastConsumables
    lastConsumables = now
    if not before then return end
    local changed, gained = false, nil
    for sid, exp in pairs(now) do
        if before[sid] == nil then changed = true gained = gained or {} gained[#gained + 1] = sid
        elseif math.abs(exp - before[sid]) > 2 then changed = true end
    end
    for sid in pairs(before) do if now[sid] == nil then changed = true end end
    if not changed then return end
    CB.ClearGroupCache()
    if InCombatLockdown() then
        for _, sid in ipairs(gained or {}) do
            for _, id in ipairs(D.BY_BUFF[sid] or (D.BY_BUFF_NAME and D.BY_BUFF_NAME[sid]) or {}) do Live.Spend(id) end
        end
        Live.pending.main, Live.pending.potions = true, true
        -- a buff gone mid-fight still shows: the bar comes back (alpha)
        local lost = false
        for sid in pairs(before) do if now[sid] == nil then lost = true end end
        if lost and CB.Bar("main").hideInCombat then Live.keepInCombat = true Live.ApplyFade("main") end
    else
        Live.Request("main") Live.Request("potions")
    end
end

-- ============================================================
-- EVENTS
-- ============================================================
local ev = CreateFrame("Frame")
Live.events = ev
local equipTimer, zoneQueued
local function Zone()
    zoneQueued = false
    Live.Request()
end
local function OnEvent(_, event, a1, a2, a3)
    if event == "BAG_UPDATE_DELAYED" then
        CB.Bags.Mark()
        CB.ClearBagEnchantCache()
        if Live.stable then Live.Request() end
    elseif event == "BAG_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_COOLDOWN" then
        Live.StartFast()
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if a1 ~= "player" then return end
        local sid = a3
        local used = sid and D.BY_BUFF[sid]
        if used and InCombatLockdown() then for _, id in ipairs(used) do Live.Spend(id) end end
        if Live.lastUse and GetTime() - Live.lastUse < 1.7 then
            if InCombatLockdown() and Live.lastUseId and Live.spentFor ~= Live.lastUse then
                Live.spentFor = Live.lastUse
                Live.Spend(Live.lastUseId)
            end
        end
        Live.StartFast()
    elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED"
        or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        if a1 == "player" then Live.StartFast() end
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        if a1 == 13 or a1 == 14 then return end
        CB.ClearBagEnchantCache()
        CB.ClearEnchantCache()
        if equipTimer then equipTimer:Cancel() end
        equipTimer = C_Timer.NewTimer(0.3, function()
            equipTimer = nil
            Live.Request("main", true) Live.Request("weapons", true)
            -- in combat the faces still follow (a texture is safe)
            if InCombatLockdown() then
                for _, key in ipairs({ "main", "weapons" }) do
                    local st = Live.bars[key]
                    for _, b in pairs(st and st.buttons or {}) do
                        local d = b.data
                        if d and d.unified then
                            local eq = W.Equipped(d.slot == "offhand" and 17 or 16)
                            d.weaponTexture = eq and eq.texture
                            b.icon:SetTexture(B.IconFor(b.itemId, d, W, CB.Cfg().weaponIcons))
                        end
                    end
                end
            end
        end)
    elseif event == "PLAYER_REGEN_DISABLED" then
        Live.combat = true
        Live.keepInCombat = false
        for _, key in ipairs(CB.BARS) do Live.ApplyFade(key, true) end
    elseif event == "PLAYER_REGEN_ENABLED" then
        Live.combat = false
        Live.keepInCombat = false
        for _, st in pairs(Live.bars) do
            for _, b in pairs(st.buttons) do
                if b._zSpent then b._zSpent = nil if not b._zCdHidden then B.SetHidden(b, false) end end
                if b._zCdHidden then b._zCdHidden = nil B.SetHidden(b, false) end
            end
        end
        for _, key in ipairs(CB.BARS) do
            Live.ApplyFade(key)
            if Live.pending[key] then Live.pending[key] = nil Live.Request(key, true) end
        end
        -- the visibility rules read the world again
        Live.Request()
    elseif event == "MODIFIER_STATE_CHANGED" then
        if modHover then Live.ModifierPreview() end
    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        -- the bags settle for two seconds after a loading screen
        Live.stable = false
        C_Timer.After(2, function() Live.stable = true Live.Request() end)
        Live.Request()
    elseif event == "PLAYER_UPDATE_RESTING" or event == "GROUP_ROSTER_UPDATE" or event == "ZONE_CHANGED"
        or event == "ZONE_CHANGED_INDOORS" then
        if not zoneQueued then zoneQueued = true C_Timer.After(0.3, Zone) end
    end
end
ev:SetScript("OnEvent", OnEvent)

local running = false
function Live.AnyOn()
    for _, k in ipairs(CB.BARS) do if CB.Bar(k).enabled then return true end end
    return false
end
-- the events are heard only while a bar is on
function Live.Start()
    if running then Live.Request() return end
    if not Live.AnyOn() then return end
    running = true
    for _, e in ipairs({ "BAG_UPDATE_DELAYED", "BAG_UPDATE_COOLDOWN", "SPELL_UPDATE_COOLDOWN", "PLAYER_EQUIPMENT_CHANGED",
        "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "MODIFIER_STATE_CHANGED", "PLAYER_ENTERING_WORLD",
        "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "PLAYER_UPDATE_RESTING", "GROUP_ROSTER_UPDATE" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    for _, e in ipairs({ "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
        "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_CHANNEL_STOP" }) do
        if ev.RegisterUnitEvent then pcall(ev.RegisterUnitEvent, ev, e, "player") else pcall(ev.RegisterEvent, ev, e) end
    end
    -- the aura news: only marks it (the drain reads it)
    if ns.PlayerAuras and ns.PlayerAuras.On then
        ns.PlayerAuras.On("ConsBars", function()
            Live.auraDirty = true
            if not drainQueued then drainQueued = true C_Timer.After(0.1, Drain) end
        end)
    end
    Live.combat = InCombatLockdown() and true or false
    lastConsumables = ConsumableBuffs()
    Live.Request()
end
function Live.Stop()
    if not running then return end
    running = false
    ev:UnregisterAllEvents()
    if ns.PlayerAuras and ns.PlayerAuras.On then ns.PlayerAuras.On("ConsBars", nil) end
    Live.StopFast()
end
-- a bar switched on or off from the page (or the import)
function Live.Refresh()
    if Live.AnyOn() then Live.Start() Live.Request(nil, true) else
        for _, key in ipairs(CB.BARS) do Live.Request(key, true) end
        Live.Stop()
    end
end

-- a use that does not go through a bar button (a bag click, an action
-- bar key, a /use macro) still marks the item, so its swirl shows
local function MarkUse(id)
    if type(id) ~= "number" then return end
    if D.BY_ID[id] then Live.lastUse, Live.lastUseId = GetTime(), id CB.NoteNamedUse(id) end
end
if C_Container and C_Container.UseContainerItem and hooksecurefunc then
    hooksecurefunc(C_Container, "UseContainerItem", function(bag, slot)
        if type(bag) == "number" and type(slot) == "number" and C_Container.GetContainerItemID then
            MarkUse(C_Container.GetContainerItemID(bag, slot))
        end
    end)
end
if UseAction and GetActionInfo and hooksecurefunc then
    hooksecurefunc("UseAction", function(slot)
        if type(slot) ~= "number" then return end
        local kind, id = GetActionInfo(slot)
        if kind == "item" then MarkUse(tonumber(id)) end
    end)
end
if UseItemByName and GetItemInfoInstant and hooksecurefunc then
    hooksecurefunc("UseItemByName", function(name) if type(name) == "string" then MarkUse((GetItemInfoInstant(name))) end end)
end

-- the page's changes reach the live bars on the next frame
if ns.OnSettingsChanged and ns.Coalesce then
    local soon = ns.Coalesce(function()
        B.Restyle()
        Live.Refresh()
    end)
    ns.OnSettingsChanged(function()
        local P = ns.ConfigPreview
        if P and P.Current and type(P.Current()) == "string" and P.Current():find("^consbars") then soon() end
    end)
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    CB.Cfg()
    Live.Start()
end)
