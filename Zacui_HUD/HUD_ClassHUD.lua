-- HUD_ClassHUD - one engine for the class HUDs that are data, not code:
-- Hunter, Rogue, Shaman, Mage, Warlock and Druid. The Warrior, Paladin
-- and Priest HUDs were ported one WeakAura at a time and keep their own
-- files; this one builds the same layout from a class definition
-- (HUD_Hunter.lua and friends call HUD.DefineClass with it):
--
--   cooldown grid     spells with cooldown swipe, no-power desaturate and
--                     out-of-range tint, plus item icons (potion, rune,
--                     healthstone, mana gem...) that show the first item
--                     you carry from a priority list, with its count
--   active buff row   your own buffs with time left and stacks
--   target debuff row your own debuffs on the target
--   reminder row      big icons for a self-buff you are missing (or a
--                     weapon enchant, or a low stock of something)
--   resource bars     mana + five-second-rule drain, energy + tick,
--                     rage, combo points, melee swing, ranged auto-shot,
--                     wand - whichever the class asks for
--   trinket/racial    the aux row
--
-- Same look as the other HUDs (the Warrior widget factory), same anchors
-- and movers (one per element plus a MOVE ALL handle), same settings
-- page shape. Perf rules as everywhere in the HUDs: events only flip
-- dirty flags or record timestamps; scans run in the 0.2s core ticker;
-- countdown texts on a 0.1s text ticker; hot events (combat log, power,
-- casts, bags) are registered only while the HUD is on.
-- Part of ZacUI; load order is set by the TOC.

local ADDON_NAME = ...
-- Zacui_HUD is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end
local HUD = ns.HUD
local UI = ns.UI
local Print = ns.Print

-- API compat shims come from HUD_Shared.
local GetSpellInfo       = HUD.GetSpellInfo
local CompatUnitAura     = HUD.UnitAura
local GetSpellCooldown_C = HUD.GetSpellCooldown
local IsUsableSpell_C    = HUD.IsUsableSpell
local IsSpellInRange_C   = HUD.IsSpellInRange
local GetSpellTexture_C  = HUD.GetSpellTexture
local GetItemCount_C     = HUD.GetItemCount

local RED_OOR    = { 1, 0.2431, 0.2275 }
local GOLD_COUNT = { 1, 0.82, 0, 1 }
local PINK_TEXT  = { 0.9569, 0.5490, 0.7294, 1 }
local MANA_BLUE  = { 0, 0.44, 0.87 }
local FSR_RED    = { 1, 0, 0 }
local ENERGY_YEL = { 1, 0.85, 0.1 }
local RAGE_RED   = { 0.85, 0.15, 0.15 }
local TICK_GREY  = { 0.8, 0.8, 0.8 }
local WAND_CYAN  = { 0.7373, 1, 0.9765 }
local CP_ON      = { 1, 0.6, 0.1, 1 }
local CP_OFF     = { 0.25, 0.25, 0.25, 0.7 }
local HUD_STRATA = "MEDIUM"
local GCD_MAX    = 1.51

-- The colours every class HUD draws with, as settings (Look tab). The
-- defaults are the colours above - what the HUDs always drew.
local COLOR_DEFAULTS = {
    oor    = HUD.RGBA(RED_OOR),    count  = HUD.RGBA(GOLD_COUNT),
    timer  = { r = 1, g = 1, b = 1, a = 1 }, text = HUD.RGBA(PINK_TEXT),
    barText = { r = 1, g = 1, b = 1, a = 1 },
    mana   = HUD.RGBA(MANA_BLUE),  fsr    = HUD.RGBA(FSR_RED),
    energy = HUD.RGBA(ENERGY_YEL), rage   = HUD.RGBA(RAGE_RED),
    tick   = HUD.RGBA(TICK_GREY),  wand   = HUD.RGBA(WAND_CYAN),
    swing  = { r = 1, g = 1, b = 1, a = 1 }, ranged = { r = 0.9, g = 0.75, b = 0.3, a = 1 },
    cpOn   = HUD.RGBA(CP_ON),      cpOff  = HUD.RGBA(CP_OFF),
}

-- Items every grid can show. Potions come from the Warrior HUD's list so
-- the dropdown is the same everywhere.
local RUNE_LIST = {
    { id = 12662, icon = 134417 }, -- Demonic Rune
    { id = 20520, icon = 136192 }, -- Dark Rune
}

-- One spell id per race and class variant; the first one the player
-- knows is the racial. (Berserking and Blood Fury have per-class ids.)
local RACIAL_IDS = { 20594, 20589, 20600, 20580, 7744, 20572, 20549, 20554, 26296, 26297, 20557 }

-- Trackers shared by every instance: one bag scan cache is plenty.
local itemCD = HUD.NewItemCDTracker()

-- ============================================================
-- INSTANCE
-- ============================================================
local Engine = {}
Engine.__index = Engine

local function DefaultsFor(def)
    local d = {
        enabled = false,
        mainRow = {
            x = 0, y = -208, scale = 1,
            rows = {
                { limit = 7, w = 30, h = 30 },
                { limit = 9, w = 25, h = 25 },
                { limit = 8, w = 25, h = 25 },
            },
            spacing = 4,
            hidden = {},
            potionChoice = def.potionChoice or 1,
        },
        auraRow = { enabled = true, x = 0, y = -150, scale = 1, iconSize = 25, spacing = 4, hidden = {} },
        debuffRow = { enabled = true, x = 0, y = -120, iconSize = 26, spacing = 4, hidden = {} },
        reminders = { enabled = true, x = 0, y = 150, iconSize = 40, spacing = 6 },
        resources = {
            -- bar on/off flags are added below from def.bars / def.texts;
            -- positions and sizes live under pos so the two never collide
            pos = {
                swing  = { x = 0, y = -183, w = 316, h = 2 },
                ranged = { x = 0, y = -178, w = 316, h = 2 },
                mana   = { x = 0, y = -188, w = 234, h = 4 },
                power  = { x = 0, y = -188, w = 234, h = 6 },
                wand   = { x = 0, y = -196, w = 300, h = 8 },
                combo  = { x = 0, y = -176, size = 10, spacing = 4 },
                texts  = { x = 0, y = 180, size = 20 },
            },
        },
        aux = {
            enabled = false,
            x = 0, y = -400, iconSize = 30, spacing = 4,
            trinket1 = true, trinket2 = true, racial = true,
        },
        colors = ns.CopySetting and ns.CopySetting(COLOR_DEFAULTS) or COLOR_DEFAULTS,
    }
    for _, r in ipairs(def.reminders or {}) do
        d.reminders[r.key] = (r.default ~= false)
    end
    for _, b in ipairs(def.bars or {}) do
        d.resources[b] = true
    end
    for _, t in ipairs(def.texts or {}) do
        d.resources[t.key] = (t.default ~= false)
    end
    if def.defaults then HUD.CopyDefaults(def.defaults, d) end
    return d
end

-- ------------------------------------------------------------
-- state and scans
-- ------------------------------------------------------------
function Engine:Store()
    return HUD.Store(self.def.store, self.defaults)
end

-- Whether the HUD's pieces may show: the HUD is on - or this is the
-- settings preview's sample, which shows the look whether it is on or not.
function Engine:On(cfg)
    return (cfg.enabled or self.sample) and true or false
end

-- The reads a sample answers from its own fake state instead of the game.
function Engine:ItemCD(itemId)
    if self.sample then
        local c = self.S.itemCDs[itemId]
        if c then return c.start, c.duration end
        return 0, 0
    end
    return itemCD.Get(itemId)
end

function Engine:RacialCD()
    local r = self.S.racial
    if not r then return 0, 0 end
    if self.sample then return r.start or 0, r.duration or 0 end
    local start, duration = GetSpellCooldown_C(r.name)
    return start or 0, duration or 0
end

function Engine:ComboPoints()
    if self.sample then return self.S.cp or 0 end
    return (GetComboPoints and GetComboPoints("player", "target")) or 0
end

-- The colour settings as { r, g, b, a } arrays, rebuilt (new tables, so
-- the bars' own "did it change" checks notice) and painted onto every
-- piece that carries one.
function Engine:ApplyColors()
    local cfg = self:Store()
    local src = (cfg and cfg.colors) or COLOR_DEFAULTS
    local col = {}
    for k, d in pairs(COLOR_DEFAULTS) do
        local r, g, b, a = HUD.Col(src[k], d)
        col[k] = { r, g, b, a }
    end
    self.col = col
    self._serial = HUD.serial
    if not self.built then return end
    local function bar(b, c) if b then b:SetBarColor(c[1], c[2], c[3], c[4]) end end
    bar(self.swingBar, col.swing)
    bar(self.rangedBar, col.ranged)
    bar(self.manaBar, col.mana)
    bar(self.fsrBar, col.fsr)
    bar(self.tickBar, col.tick)
    bar(self.wandBar, col.wand)
    if self.powerBar then self.powerBar.lastColor = nil end
    for _, b in ipairs({ self.manaBar, self.powerBar }) do
        if b and b.text then b.text:SetTextColor(col.barText[1], col.barText[2], col.barText[3], col.barText[4]) end
    end
    if self.comboFrame then self.comboFrame._cp = nil end
    local tc, cc = col.timer, col.count
    for _, set in ipairs({ self.mainIcons, self.auraIcons, self.debuffIcons, self.remindIcons, self.auxIcons }) do
        for _, icon in pairs(set) do
            local t = icon.texts
            if t.p then t.p:SetTextColor(tc[1], tc[2], tc[3], tc[4]) end
            if t.s then t.s:SetTextColor(tc[1], tc[2], tc[3], tc[4]) end
            if t.count then t.count:SetTextColor(cc[1], cc[2], cc[3], cc[4]) end
        end
    end
    local pc = col.text
    for _, fs in pairs(self.textFS or {}) do fs:SetTextColor(pc[1], pc[2], pc[3], pc[4]) end
end

function Engine:Col(key)
    if not self.col or self._serial ~= HUD.serial then self:ApplyColors() end
    return self.col[key]
end

function Engine:ResolveSpells()
    local S = self.S
    for key, id in pairs(self.def.spells or {}) do
        local name = GetSpellInfo and GetSpellInfo(id) or nil
        local known, icon = false, nil
        if name then
            local n2, _, tex = GetSpellInfo(name)
            known = n2 ~= nil
            icon = tex or (GetSpellTexture_C and GetSpellTexture_C(id))
        end
        S.spells[key] = { name = name, known = known, icon = icon }
    end
    for _, list in ipairs({ self.def.buffRow or {}, self.def.debuffRow or {} }) do
        for _, e in ipairs(list) do
            local name, _, icon = GetSpellInfo and GetSpellInfo(e.id)
            S.auraNames[e.key] = e.name or name
            S.auraIcons[e.key] = e.icon or icon
        end
    end
    S.racial = nil
    for _, id in ipairs(RACIAL_IDS) do
        local name = GetSpellInfo and GetSpellInfo(id) or nil
        if name then
            local n2, _, tex = GetSpellInfo(name)
            if n2 then S.racial = { name = name, icon = tex } break end
        end
    end
end

-- The entry for an aura name is kept between scans and its fields
-- rewritten (first application wins, as before); a scan runs up to five
-- times a second in a fight and used to make a fresh table per aura.
-- Entries not seen this pass are dropped afterwards, so a reader finds
-- exactly what a rebuilt table would hold.
local scanPass = 0
local function PutAura(out, lname, pass, name, icon, count, duration, expirationTime, hidden)
    local e = out[lname]
    if e and e.pass == pass then return end
    if not e then
        e = {}
        out[lname] = e
    end
    e.pass = pass
    e.name, e.icon, e.count, e.duration, e.expirationTime = name, icon, count, duration, expirationTime
    -- (WoW Forever: the game's aura table when its icon, timer or stacks
    -- are hidden - the row shows those straight from it)
    e.hidden = hidden
end
local function DropUnseen(out, pass)
    for lname, e in pairs(out) do
        if e.pass ~= pass then out[lname] = nil end
    end
end

-- the player's buffs come from ZacUI's shared read (ns.PlayerAuras)
function Engine:ScanPlayerBuffs()
    local S = self.S
    scanPass = scanPass + 1
    local pass = scanPass
    local list = ns.PlayerAuras.Buffs()
    for i = 1, #list do
        local a = list[i]
        if a.name then
            PutAura(S.buffs, a.name:lower(), pass, a.name, a.icon, a.count, a.duration, a.expirationTime)
        end
    end
    DropUnseen(S.buffs, pass)
end

function Engine:ScanTargetDebuffs()
    local S = self.S
    scanPass = scanPass + 1
    local pass = scanPass
    if HUD.HIDDEN_AURAS then
        -- WoW Forever: details the game hides in combat are shown as they
        -- are; debuffs whose very names are hidden go to S.targetHidden
        local extra = S.targetHidden
        if not extra then extra = {} S.targetHidden = extra end
        wipe(extra)
        if UnitExists("target") then
            HUD.EachMyTargetDebuff(function(name, a)
                if not name then
                    extra[#extra + 1] = a
                elseif ns.AuraFieldsHidden(a) then
                    PutAura(S.targetDebuffs, name:lower(), pass, name, a.icon, nil, nil, nil, a)
                else
                    PutAura(S.targetDebuffs, name:lower(), pass, name, a.icon, a.applications, a.duration, a.expirationTime)
                end
            end)
        end
        DropUnseen(S.targetDebuffs, pass)
        return
    end
    if UnitExists("target") then
        for i = 1, 40 do
            local name, icon, count, _, duration, expirationTime, source =
                CompatUnitAura("target", i, "HARMFUL")
            if not name then break end
            if source == "player" then
                PutAura(S.targetDebuffs, name:lower(), pass, name, icon, count, duration, expirationTime)
            end
        end
    end
    DropUnseen(S.targetDebuffs, pass)
end

-- Every item list the grid and the reminders can ask about.
function Engine:ItemLists()
    if self._itemLists then return self._itemLists end
    local lists = { RUNE_LIST }
    local WH = ns.WarriorHUD
    if WH and WH.POTION_LIST then lists[#lists + 1] = WH.POTION_LIST end
    for _, g in ipairs(self.def.grid or {}) do
        if g.items then lists[#lists + 1] = g.items end
    end
    for _, r in ipairs(self.def.reminders or {}) do
        if r.items then lists[#lists + 1] = r.items end
        if r.item then lists[#lists + 1] = { { id = r.item } } end
    end
    self._itemLists = lists
    return lists
end

function Engine:ScanItems()
    local S = self.S
    wipe(S.items)
    for _, list in ipairs(self:ItemLists()) do
        for _, e in ipairs(list) do
            if S.items[e.id] == nil and GetItemCount_C then
                S.items[e.id] = GetItemCount_C(e.id) or 0
            end
        end
    end
end

function Engine:FirstAvailable(list)
    for _, e in ipairs(list) do
        if (self.S.items[e.id] or 0) > 0 then return e, self.S.items[e.id] end
    end
    return nil, 0
end

function Engine:UpdateSpellSnapshot()
    local S = self.S
    for key, sp in pairs(S.spells) do
        if sp.known and sp.name then
            local start, duration = GetSpellCooldown_C(sp.name)
            start, duration = start or 0, duration or 0
            local cd = S.cds[key]
            if not cd then cd = {} S.cds[key] = cd end
            cd.start, cd.duration = start, duration
            cd.real = duration > GCD_MAX
            local us = S.usable[key]
            if not us then us = {} S.usable[key] = us end
            if IsUsableSpell_C then
                local usable, noPower = IsUsableSpell_C(sp.name)
                us.usable, us.noPower = usable and true or false, noPower and true or false
            else
                us.usable, us.noPower = true, false
            end
            if S.targetAttackable and IsSpellInRange_C then
                S.inRange[key] = IsSpellInRange_C(sp.name, "target")
            else
                S.inRange[key] = nil
            end
        end
    end
end

function Engine:UpdateMisc()
    local S = self.S
    S.targetAttackable = (UnitExists("target") and UnitCanAttack("player", "target")
        and not UnitIsDeadOrGhost("target")) and true or false
    S.powerType = UnitPowerType("player") or 0
    for slotIdx = 13, 14 do
        local t = S.trinkets[slotIdx]
        if not t then t = {} S.trinkets[slotIdx] = t end
        t.texture = GetInventoryItemTexture and GetInventoryItemTexture("player", slotIdx) or nil
        if GetInventoryItemCooldown then
            local start, duration = GetInventoryItemCooldown("player", slotIdx)
            t.start, t.duration = start or 0, duration or 0
        end
    end
    if self.wantsWeaponEnchant and GetWeaponEnchantInfo then
        local hasMain, mainExp, _, _, hasOff, offExp = GetWeaponEnchantInfo()
        S.mhEnchant = hasMain and true or false
        S.ohEnchant = hasOff and true or false
        S.mhEnchantLeft = hasMain and (mainExp or 0) / 1000 or 0
        S.ohEnchantLeft = hasOff and (offExp or 0) / 1000 or 0
        S.hasOffhand = (GetInventoryItemID and GetInventoryItemID("player", 17)) and true or false
    end
end

-- ------------------------------------------------------------
-- events (timestamp writes only)
-- ------------------------------------------------------------
function Engine:OnPowerEvent(event, spellId)
    local S = self.S
    local ptype = UnitPowerType("player") or 0
    local cur = UnitPower("player", ptype) or 0
    if event == "UNIT_POWER_FREQUENT" then
        if ptype == 0 then
            -- mana: regen ticks only after the five-second rule and not
            -- while hardcasting, so procs cannot hijack the bar
            if cur >= (UnitPowerMax("player", 0) or 0) then
                self.lastPower = cur
                return
            end
            if cur > self.lastPower and GetTime() >= self.fsrCastAt + 5
                and not (UnitCastingInfo and UnitCastingInfo("player")) then
                S.fsr.start, S.fsr.duration = GetTime(), 2
            end
        elseif ptype == 3 then
            -- energy ticks every 2s; a gain that is not a full bar marks one
            if cur > self.lastPower and cur < (UnitPowerMax("player", 3) or 100) then
                S.tick.start, S.tick.duration = GetTime(), 2
            end
        end
        self.lastPower = cur
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if spellId == 5019 and S.wand.active then     -- Shoot
            local speed = UnitRangedDamage and UnitRangedDamage("player") or 0
            if speed and speed > 0 then S.wand.start, S.wand.duration = GetTime(), speed end
        end
        if ptype == 0 and cur < self.lastPower then
            S.fsr.start, S.fsr.duration = GetTime(), 5
            self.fsrCastAt = GetTime()
        end
        self.lastPower = cur
    end
end

-- through ZacUI's shared combat-log reader (ns.CLEU)
function Engine:OnCombatLogEvent(_, subevent, _, sourceGUID)
    if sourceGUID ~= self.playerGUID then return end
    local S = self.S
    if subevent == "SWING_DAMAGE" or subevent == "SWING_MISSED" then
        local mhSpeed = UnitAttackSpeed("player")
        S.swing.start, S.swing.duration = GetTime(), mhSpeed or 0
    elseif self.wantsRanged and (subevent == "RANGE_DAMAGE" or subevent == "RANGE_MISSED") then
        local speed = UnitRangedDamage and UnitRangedDamage("player") or 0
        S.ranged.start, S.ranged.duration = GetTime(), speed or 0
    end
end

-- WoW Forever: the game's own swing event instead (ns.Swings)
function Engine:OnSwing(hand, now, dur)
    local S = self.S
    if hand == "mh" then
        S.swing.start, S.swing.duration = now, dur or 0
    elseif hand == "ranged" and self.wantsRanged then
        S.ranged.start, S.ranged.duration = now, dur or 0
    end
end

-- ------------------------------------------------------------
-- anchors and movers
-- ------------------------------------------------------------
function Engine:MakeAnchor(key, w, h)
    local base = "ZacUIHUD_" .. self.def.frameName .. "_" .. key
    local holder = CreateFrame("Frame", base .. "_Holder", UIParent)
    holder:SetSize(w or 26, h or 26)
    holder:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    local f = CreateFrame("Frame", base, holder)
    f:SetSize(w or 26, h or 26)
    f:SetFrameStrata(HUD_STRATA)
    f:SetPoint("CENTER", holder, "CENTER", 0, 0)
    self.anchors[key] = f
    self.holders[key] = holder
    return f
end

-- element key -> { anchor name, mover suffix, label, store path }
function Engine:Elements()
    local p = self.def.prefix
    local list = {
        { key = "Main",     mover = p .. "MainRow",   label = "Cooldown Grid",   cfg = function(c) return c.mainRow end },
        { key = "AuraRow",  mover = p .. "AuraRow",   label = "Active Buffs",    cfg = function(c) return c.auraRow end },
    }
    if self.def.debuffRow then
        list[#list + 1] = { key = "DebuffRow", mover = p .. "DebuffRow", label = "Target Debuffs", cfg = function(c) return c.debuffRow end }
    end
    if self.def.reminders and #self.def.reminders > 0 then
        list[#list + 1] = { key = "Reminders", mover = p .. "Reminders", label = "Reminders", cfg = function(c) return c.reminders end }
    end
    if self.bars.swing then
        list[#list + 1] = { key = "Swing", mover = p .. "Swing", label = "Swing Timer", cfg = function(c) return c.resources.pos.swing end }
    end
    if self.bars.ranged then
        list[#list + 1] = { key = "Ranged", mover = p .. "Ranged", label = "Auto Shot Timer", cfg = function(c) return c.resources.pos.ranged end }
    end
    if self.bars.mana then
        list[#list + 1] = { key = "Mana", mover = p .. "Mana", label = "Mana + FSR", cfg = function(c) return c.resources.pos.mana end }
    end
    if self.bars.power then
        list[#list + 1] = { key = "Power", mover = p .. "Power", label = self.def.powerLabel or "Energy / Rage", cfg = function(c) return c.resources.pos.power end }
    end
    if self.bars.combo then
        list[#list + 1] = { key = "Combo", mover = p .. "Combo", label = "Combo Points", cfg = function(c) return c.resources.pos.combo end }
    end
    if self.bars.wand then
        list[#list + 1] = { key = "Wand", mover = p .. "Wand", label = "Wand Timer", cfg = function(c) return c.resources.pos.wand end }
    end
    if self.def.texts and #self.def.texts > 0 then
        list[#list + 1] = { key = "Texts", mover = p .. "Texts", label = "Reminder Texts", cfg = function(c) return c.resources.pos.texts end }
    end
    list[#list + 1] = { key = "Aux", mover = p .. "Aux", label = "Trinkets/Racial", cfg = function(c) return c.aux end }
    return list
end

function Engine:CreateAnchors()
    local sizes = {
        Main = { 36, 28 }, AuraRow = { 25, 25 }, DebuffRow = { 26, 26 }, Reminders = { 40, 40 },
        Swing = { 316, 2 }, Ranged = { 316, 2 }, Mana = { 234, 10 }, Power = { 234, 6 },
        Combo = { 66, 10 }, Wand = { 300, 8 }, Texts = { 240, 30 }, Aux = { 30, 30 },
    }
    for _, e in ipairs(self:Elements()) do
        local s = sizes[e.key] or { 26, 26 }
        self:MakeAnchor(e.key, s[1], s[2])
    end
    self:MakeAnchor("GroupHandle", 170, 24)
end

function Engine:ApplyAnchorPositions()
    if not self.anchors.Main then return end
    local cfg = self:Store()
    if not cfg then return end
    if self.sample then return self:LayoutSample(cfg) end
    for _, e in ipairs(self:Elements()) do
        HUD.PlaceAnchor(e.mover, self.holders[e.key], e.cfg(cfg))
    end
    if cfg.group then HUD.PlaceAnchor(self.def.prefix .. "Group", self.holders.GroupHandle, cfg.group) end
    self.anchors.Main:SetScale(cfg.mainRow.scale or 1)
    self.anchors.AuraRow:SetScale(cfg.auraRow.scale or 1)
end

function Engine:RegisterMovers()
    local cfg = self:Store()
    if not cfg then
        C_Timer.After(1, function() self:RegisterMovers() end)
        return
    end
    local members = {}
    local label = self.def.label
    for _, e in ipairs(self:Elements()) do
        HUD.RegisterMover(e.mover, label .. " " .. e.label, self.holders[e.key], e.cfg(cfg))
        members[#members + 1] = { key = e.mover, holder = self.holders[e.key] }
    end
    cfg.group = cfg.group or { x = cfg.mainRow.x or 0, y = (cfg.mainRow.y or -208) + 50 }
    local gkey = self.def.prefix .. "Group"
    HUD.PlaceAnchor(gkey, self.holders.GroupHandle, cfg.group)
    HUD.RegisterGroup(gkey, label .. ": move all", self.holders.GroupHandle, cfg.group, members)
    HUD.Debug(label .. " anchors registered with the mover registry")
end

-- ------------------------------------------------------------
-- building
-- ------------------------------------------------------------
function Engine:BuildMainIcons()
    local W = self.W
    for _, def in ipairs(self.def.grid) do
        local icon = W.CreateIcon(self.anchors.Main, {
            width = 30, height = 30, zoom = W.ICON_ZOOM, keepAspect = true, inverse = true,
        })
        icon:SetFrameStrata(HUD_STRATA)
        icon:Hide()
        icon.def = def
        icon:AddText("p", "CENTER", 14, { 1, 1, 1, 1 })
        icon:SetText("p", "")
        if def.kind ~= "spell" then
            icon:AddText("count", "INNER_BOTTOMRIGHT", 12, GOLD_COUNT, 0, 0)
        end
        self.mainIcons[def.key] = icon
    end
end

function Engine:BuildRowIcons(list, anchor, size, store)
    local W = self.W
    for _, def in ipairs(list) do
        local icon = W.CreateIcon(anchor, {
            width = size, height = size, zoom = W.ICON_ZOOM, keepAspect = true, inverse = true,
        })
        icon:SetFrameStrata(HUD_STRATA)
        icon:Hide()
        icon.def = def
        icon:AddText("p", "BELOW", 14, { 1, 1, 1, 1 }, 0, 0)
        icon:AddText("s", "INNER_TOPRIGHT", 14, { 1, 1, 1, 1 }, 0, 0)
        store[def.key] = icon
    end
end

function Engine:BuildReminders()
    local W = self.W
    local cfg = self:Store()
    local size = (cfg and cfg.reminders.iconSize) or 40
    for _, def in ipairs(self.def.reminders or {}) do
        local icon = W.CreateIcon(self.anchors.Reminders, {
            width = size, height = size, zoom = W.ICON_ZOOM, keepAspect = true, noCooldown = true,
        })
        icon:SetFrameStrata(HUD_STRATA)
        icon:Hide()
        icon.def = def
        icon:AddText("count", "INNER_BOTTOMRIGHT", 12, GOLD_COUNT, 0, 0)
        icon:AddText("p", "BELOW", 12, { 1, 1, 1, 1 }, 0, 0)
        self.remindIcons[def.key] = icon
    end
end

function Engine:BuildAux()
    local W = self.W
    local cfg = self:Store()
    local size = (cfg and cfg.aux.iconSize) or 30
    for _, def in ipairs({
        { key = "trinket1", slot = 13 }, { key = "trinket2", slot = 14 }, { key = "racial" } }) do
        local icon = W.CreateIcon(self.anchors.Aux, {
            width = size, height = size, zoom = W.ICON_ZOOM, keepAspect = true, inverse = true,
        })
        icon:SetFrameStrata(HUD_STRATA)
        icon:Hide()
        icon.def = def
        icon:AddText("p", "CENTER", 12, { 1, 1, 1, 1 })
        self.auxIcons[def.key] = icon
    end
end

-- a drain bar: fraction of a { start, duration } window still to run
local function DrainDriver(self, bar, stateKey, previewValue)
    local S = self.S
    bar:SetScript("OnUpdate", function(b)
        if self.preview then
            b.bar:SetValue(previewValue or 0.65)
            if b.UpdateSpark then b:UpdateSpark(previewValue or 0.65) end
            return
        end
        local w = S[stateKey]
        local dur = w.duration or 0
        local remaining = dur > 0 and (w.start + dur - GetTime()) or 0
        -- the preview's sample runs its fake windows round and round
        if self.sample and dur > 0 and remaining <= 0 then
            w.start = GetTime()
            remaining = dur
        end
        local frac = (remaining > 0 and dur > 0) and (remaining / dur) or 0
        b.bar:SetValue(frac)
        if b.UpdateSpark then b:UpdateSpark(frac) end
    end)
end

function Engine:BuildBars()
    local W = self.W
    local cfg = self:Store()
    local r = cfg and cfg.resources or self.defaults.resources
    local S = self.S
    local bars = self.bars

    if bars.swing then
        local b = W.CreateBar(self.anchors.Swing, { width = r.pos.swing.w, height = r.pos.swing.h, spark = true,
            barColor = self:Col("swing") })
        b:SetFrameStrata(HUD_STRATA)
        b:SetPoint("CENTER", self.anchors.Swing, "CENTER", 0, 0)
        DrainDriver(self, b, "swing")
        b:Hide()
        self.swingBar = b
    end
    if bars.ranged then
        local b = W.CreateBar(self.anchors.Ranged, { width = r.pos.swing.w, height = r.pos.swing.h, spark = true,
            barColor = self:Col("ranged") })
        b:SetFrameStrata(HUD_STRATA)
        b:SetPoint("CENTER", self.anchors.Ranged, "CENTER", 0, 0)
        DrainDriver(self, b, "ranged")
        b:Hide()
        self.rangedBar = b
    end
    if bars.mana then
        local b = W.CreateBar(self.anchors.Mana, { width = r.pos.mana.w, height = r.pos.mana.h,
            barColor = self:Col("mana") })
        b:SetFrameStrata(HUD_STRATA)
        b:SetPoint("CENTER", self.anchors.Mana, "CENTER", 0, 2)
        local mt = HUD.Text(b.bar, 10, "OUTLINE", "OVERLAY", "text")
        mt:SetPoint("CENTER", b, "CENTER", 0, 0)
        mt:SetTextColor(1, 1, 1)
        b.text = mt
        if HUD.BarText then HUD.BarText(mt, b) end
        if self.sample then b.readMana = function() return S.mana or 0, S.manaMax or 1 end end
        b:SetScript("OnUpdate", HUD.ManaBarOnUpdate)
        b:Hide()
        self.manaBar = b

        local f = W.CreateBar(self.anchors.Mana, { width = r.pos.mana.w, height = 3,
            barColor = self:Col("fsr") })
        f:SetFrameStrata(HUD_STRATA)
        f:SetPoint("TOP", b, "BOTTOM", 0, -1)
        DrainDriver(self, f, "fsr")
        f:Hide()
        self.fsrBar = f
    end
    if bars.power then
        -- energy or rage, whichever the player runs on right now
        local b = W.CreateBar(self.anchors.Power, { width = r.pos.power.w, height = r.pos.power.h,
            barColor = self:Col("energy") })
        b:SetFrameStrata(HUD_STRATA)
        b:SetPoint("CENTER", self.anchors.Power, "CENTER", 0, 2)
        local pt = HUD.Text(b.bar, 10, "OUTLINE", "OVERLAY", "text")
        pt:SetPoint("CENTER", b, "CENTER", 0, 0)
        pt:SetTextColor(1, 1, 1)
        b.text = pt
        if HUD.BarText then HUD.BarText(pt, b) end
        local eng = self
        b:SetScript("OnUpdate", function(self2)
            local ptype = S.powerType or 3
            if ptype == 0 then ptype = 3 end
            local cur, max
            if eng.sample then
                cur, max = S.power or 0, S.powerMax or 100
            else
                cur = UnitPower("player", ptype) or 0
                max = UnitPowerMax("player", ptype) or 100
            end
            self2.bar:SetValue(max > 0 and cur / max or 0)
            if cur ~= self2.lastPower then
                self2.lastPower = cur
                self2.text:SetText(tostring(cur))
            end
            local c = eng:Col((ptype == 1) and "rage" or "energy")
            if self2.lastColor ~= c then
                self2.lastColor = c
                self2:SetBarColor(c[1], c[2], c[3], 1)
            end
        end)
        b:Hide()
        self.powerBar = b

        local t = W.CreateBar(self.anchors.Power, { width = r.pos.power.w, height = 2,
            barColor = self:Col("tick") })
        t:SetFrameStrata(HUD_STRATA)
        t:SetPoint("TOP", b, "BOTTOM", 0, -1)
        DrainDriver(self, t, "tick")
        t:Hide()
        self.tickBar = t
    end
    if bars.combo then
        local holder = CreateFrame("Frame", nil, self.anchors.Combo)
        holder:SetAllPoints()
        holder.dots = {}
        for i = 1, 5 do
            local d = holder:CreateTexture(nil, "ARTWORK")
            d:SetTexture("Interface\\Buttons\\WHITE8X8")
            holder.dots[i] = d
        end
        holder:Hide()
        self.comboFrame = holder
    end
    if bars.wand then
        local b = W.CreateBar(self.anchors.Wand, { width = r.pos.wand.w, height = r.pos.wand.h, spark = true,
            barColor = self:Col("wand") })
        b:SetFrameStrata(HUD_STRATA)
        b:SetPoint("CENTER", self.anchors.Wand, "CENTER", 0, 0)
        DrainDriver(self, b, "wand")
        b:Hide()
        self.wandBar = b
    end
    -- reminder texts, stacked down from the Texts anchor
    self.textFS = {}
    for i, t in ipairs(self.def.texts or {}) do
        local fs = HUD.Text(self.anchors.Texts, r.pos.texts.size or 20, "OUTLINE", "OVERLAY", "alert")
        fs:SetPoint("CENTER", self.anchors.Texts, "CENTER", 0, 8 - (i - 1) * 22)
        local pc = self:Col("text")
        fs:SetTextColor(pc[1], pc[2], pc[3], pc[4])
        fs:SetText(t.text)
        fs:Hide()
        self.textFS[t.key] = fs
    end
end

-- ------------------------------------------------------------
-- layout (same shapes as the Paladin HUD)
-- ------------------------------------------------------------
-- Row layouts: HUD.LayoutGrid / HUD.LayoutRow (HUD_Shared), laid out
-- again only when the shown icons or the sizes change.

-- ------------------------------------------------------------
-- refresh (0.2s core tick)
-- ------------------------------------------------------------
function Engine:ItemFor(def, cfg)
    local WH = ns.WarriorHUD
    if def.kind == "itemPotion" then
        local sel = (WH and WH.POTION_DROPDOWN) and WH.POTION_DROPDOWN[cfg.mainRow.potionChoice or 1] or nil
        if sel and (self.S.items[sel.id] or 0) > 0 then return sel, self.S.items[sel.id] end
        if WH and WH.POTION_LIST then return self:FirstAvailable(WH.POTION_LIST) end
        return nil, 0
    elseif def.kind == "itemRune" then
        return self:FirstAvailable(RUNE_LIST)
    elseif def.kind == "item" then
        return self:FirstAvailable(def.items or {})
    end
    return nil, 0
end

function Engine:UpdateMainIcon(icon, def, cfg)
    local S = self.S
    if def.kind == "spell" then
        local sp = S.spells[def.spell]
        if not (sp and sp.known) then return false end
        if def.when and not def.when(S) then return false end
        local cd = S.cds[def.spell]
        local us = S.usable[def.spell] or {}
        local inRange = (not def.noRange) and S.inRange[def.spell] or nil
        icon:SetIconTexture(sp.icon)
        if cd then icon:SetSwipe(cd.start, cd.duration) end
        local desat = (cd and cd.real) or us.noPower or false
        if inRange == 0 then
            desat = true
            local c = self:Col("oor")
            icon:SetIconColor(c[1], c[2], c[3], c[4])
        else
            icon:SetIconColor(1, 1, 1, 1)
        end
        icon:SetDesat(desat)
        return true
    end
    local item, count = self:ItemFor(def, cfg)
    icon.curItem = item
    if not item or count == 0 then return false end
    icon:SetIconTexture(item.icon or (HUD.GetItemIcon and HUD.GetItemIcon(item.id)) or 134400)
    icon:SetText("count", tostring(count))
    local start, duration = self:ItemCD(item.id)
    icon:SetSwipe(start, duration)
    icon:SetDesat(duration > GCD_MAX)
    return true
end

function Engine:RefreshMainRow(cfg)
    local S, W = self.S, self.W
    wipe(self.mainActive)
    local m = cfg.mainRow
    for _, def in ipairs(self.def.grid) do
        local icon = self.mainIcons[def.key]
        local shown = false
        if self:On(cfg) and not m.hidden[def.key] then
            if self.preview then
                local sp = def.spell and S.spells[def.spell]
                local first = def.items and def.items[1]
                icon:SetIconTexture((sp and sp.icon) or (def.kind == "itemPotion" and 134856)
                    or (def.kind == "itemRune" and 134417)
                    or (first and (first.icon or (HUD.GetItemIcon and HUD.GetItemIcon(first.id)))) or 134400)
                icon:SetDesat(false)
                icon:ClearSwipe()
                icon:SetIconColor(1, 1, 1, 1)
                shown = (not def.spell) or (sp and sp.known) or false
            else
                shown = self:UpdateMainIcon(icon, def, cfg)
            end
        end
        W.SetShownAnimated(icon, shown)
        if shown then self.mainActive[#self.mainActive + 1] = icon end
    end
    HUD.LayoutGrid(self.memo.main, self.mainActive, self.anchors.Main, m.rows or self.defaults.mainRow.rows, m.spacing or 4)
end

-- buff row and debuff row share one shape: own aura by resolved name
function Engine:RefreshAuraList(cfg, list, icons, active, rowCfg, anchor, source, memo)
    local S, W = self.S, self.W
    wipe(active)
    -- WoW Forever: your debuffs on the target whose names the game hides.
    -- Nothing tells them apart but their own icons, so they take the
    -- row's free icons in the game's order (the per-debuff ticks can't
    -- reach them). nil on every other client.
    local extra = source == S.targetDebuffs and S.targetHidden or nil
    if extra and (#extra == 0 or self.preview or not self:On(cfg) or rowCfg.enabled == false) then extra = nil end
    local free = extra and (self._freeIcons or {}) or nil
    if free then self._freeIcons = free wipe(free) end
    for _, def in ipairs(list) do
        local icon = icons[def.key]
        local shown = false
        if self:On(cfg) and rowCfg.enabled ~= false and not rowCfg.hidden[def.key] then
            if self.preview then
                icon:SetIconTexture(S.auraIcons[def.key] or 134400)
                icon:ClearSwipe()
                icon.auraRef = nil
                shown = S.auraNames[def.key] ~= nil
            else
                local name = S.auraNames[def.key]
                local b = name and source[name:lower()] or nil
                if b and b.hidden then
                    icon:SetHiddenTexture(b.icon)
                    icon:SetHiddenSwipe("target", b.hidden)
                    icon.auraRef = b
                    shown = true
                elseif b then
                    icon:SetIconTexture(b.icon or S.auraIcons[def.key])
                    if (b.duration or 0) > 0 then
                        icon:SetSwipe(b.expirationTime - b.duration, b.duration)
                    else
                        icon:ClearSwipe()
                    end
                    icon.auraRef = b
                    shown = true
                end
            end
        end
        if free and not shown then
            free[#free + 1] = icon
        else
            W.SetShownAnimated(icon, shown)
            if shown then active[#active + 1] = icon end
        end
    end
    if free then
        for i, icon in ipairs(free) do
            local a = extra[i]
            if a then
                local ref = icon._hiddenRef
                if not ref then ref = {} icon._hiddenRef = ref end
                ref.hidden = a
                icon:SetHiddenTexture(a.icon)
                icon:SetHiddenSwipe("target", a)
                icon.auraRef = ref
                W.SetShownAnimated(icon, true)
                active[#active + 1] = icon
            else
                W.SetShownAnimated(icon, false)
            end
        end
    end
    local size = rowCfg.iconSize or 25
    HUD.LayoutRow(memo, active, anchor, size, size, rowCfg.spacing or 4)
end

-- helpers handed to a reminder's check function
function Engine:Helpers()
    if self._helpers then return self._helpers end
    local S = self.S
    local eng = self
    local H = {}
    function H.Buff(nameOrKey)
        local sp = S.spells[nameOrKey]
        local name = sp and sp.name or nameOrKey
        return name and S.buffs[name:lower()] or nil
    end
    function H.AnyBuff(list)
        for _, k in ipairs(list) do if H.Buff(k) then return true end end
        return false
    end
    function H.Known(key)
        local sp = S.spells[key]
        return sp and sp.known or false
    end
    function H.Icon(key)
        local sp = S.spells[key]
        return sp and sp.icon or nil
    end
    function H.Count(itemId) return S.items[itemId] or 0 end
    function H.Left(b) return b and (b.expirationTime or 0) > 0 and (b.expirationTime - GetTime()) or 0 end
    H.S = S
    self._helpers = H
    return H
end

-- scratch lists for the 5 Hz refreshes, wiped and refilled rather than
-- allocated per tick (LayoutRow reads them straight away)
local remindShown, auxShown = {}, {}
local AUX_KEYS = { "trinket1", "trinket2", "racial" }

function Engine:RefreshReminders(cfg)
    if not self.anchors.Reminders then return end
    local r = cfg.reminders
    local shownList = remindShown
    wipe(shownList)
    local H = self:Helpers()
    for _, def in ipairs(self.def.reminders or {}) do
        local icon = self.remindIcons[def.key]
        local shown, tex, count, left = false, nil, nil, nil
        if self:On(cfg) and r.enabled and r[def.key] then
            if self.preview or self.sample then
                shown = true
                tex = (def.spell and H.Icon(def.spell)) or def.icon or 134400
                count = def.previewCount
            else
                local ok, s, t, c, l = pcall(def.check, H, self.S)
                if ok then shown, tex, count, left = s, t, c, l end
                if shown and not tex then tex = (def.spell and H.Icon(def.spell)) or def.icon or 134400 end
            end
        end
        if shown then
            icon:SetIconTexture(tex)
            icon:SetText("count", count and tostring(count) or "")
            icon:SetText("p", (left and left > 0) and self.W.FormatTime(left, 0) or "")
        end
        self.W.SetShownAnimated(icon, shown and true or false)
        if shown then shownList[#shownList + 1] = icon end
    end
    local size = r.iconSize or 40
    HUD.LayoutRow(self.memo.remind, shownList, self.anchors.Reminders, size, size, r.spacing or 6)
end

function Engine:RefreshResources(cfg)
    local S = self.S
    local r = cfg.resources
    local show = self:On(cfg)
    local now = GetTime()
    local bars = self.bars

    if bars.swing then
        local active = S.swing.duration > 0 and (S.swing.start + S.swing.duration) > now
        self.swingBar:SetShown(show and r.swing and (self.preview or (S.inCombat and active)) or false)
    end
    if bars.ranged then
        local active = S.ranged.duration > 0 and (S.ranged.start + S.ranged.duration) > now
        self.rangedBar:SetShown(show and r.ranged and (self.preview or (S.inCombat and active)) or false)
    end
    if bars.mana then
        local manaUser = (S.powerType or 0) == 0
        self.manaBar:SetShown(show and r.mana and (manaUser or self.preview) or false)
        self.fsrBar:SetShown(show and r.fsr and (manaUser or self.preview) or false)
    end
    if bars.power then
        local onPower = (S.powerType or 0) ~= 0
        self.powerBar:SetShown(show and r.power and (onPower or self.preview) or false)
        self.tickBar:SetShown(show and r.tick and ((onPower and S.powerType == 3) or self.preview) or false)
    end
    if bars.combo then
        local cp = self:ComboPoints()
        if self.preview then cp = 3 end
        local onPower = (S.powerType or 0) == 3
        local f = self.comboFrame
        local vis = show and r.combo and (self.preview or (onPower and cp > 0))
        f:SetShown(vis or false)
        if vis then
            local c = r.pos.combo
            local size, gap = c.size or 10, c.spacing or 4
            -- placed again only when the size or gap changed; recoloured
            -- only when the count did
            local placed = f._size == size and f._gap == gap
            local total = 5 * size + 4 * gap
            for i = 1, 5 do
                local d = f.dots[i]
                if not placed then
                    d:SetSize(size, size)
                    d:ClearAllPoints()
                    d:SetPoint("CENTER", f, "CENTER", -total / 2 + size / 2 + (i - 1) * (size + gap), 0)
                end
                if not placed or f._cp ~= cp then
                    local col = self:Col((i <= cp) and "cpOn" or "cpOff")
                    d:SetVertexColor(col[1], col[2], col[3], col[4])
                end
            end
            f._size, f._gap, f._cp = size, gap, cp
        end
    end
    if bars.wand then
        self.wandBar:SetShown(show and r.wand and (self.preview or S.wand.active) or false)
    end
    local H = self:Helpers()
    for _, t in ipairs(self.def.texts or {}) do
        local fs = self.textFS[t.key]
        local vis = false
        if show and r[t.key] then
            if self.preview or self.sample then vis = true
            else
                local ok, v = pcall(t.check, H, S)
                vis = ok and v and true or false
            end
        end
        fs:SetShown(vis)
    end
end

function Engine:RefreshAux(cfg)
    local S = self.S
    local a = cfg.aux
    local shownList = auxShown
    wipe(shownList)
    for _, key in ipairs(AUX_KEYS) do
        local icon = self.auxIcons[key]
        local def = icon.def
        local shown = false
        if self:On(cfg) and a.enabled and a[key] then
            if def.slot then
                local t = S.trinkets[def.slot]
                if t and t.texture then
                    icon:SetIconTexture(t.texture)
                    icon:SetSwipe(t.start, t.duration)
                    icon:SetDesat((t.duration or 0) > GCD_MAX)
                    shown = true
                end
            elseif S.racial then
                icon:SetIconTexture(S.racial.icon)
                local start, duration = self:RacialCD()
                icon:SetSwipe(start, duration)
                icon:SetDesat(duration > GCD_MAX)
                shown = true
            end
        end
        self.W.SetShownAnimated(icon, shown)
        if shown then shownList[#shownList + 1] = icon end
    end
    local size = a.iconSize or 30
    HUD.LayoutRow(self.memo.aux, shownList, self.anchors.Aux, size, size, a.spacing or 4)
end

function Engine:Refresh()
    if not self.anchors.Main then return end
    if not self.W then
        self.W = ns.WarriorHUD and ns.WarriorHUD.Widgets or nil
        if not self.W then return end
    end
    local cfg = self:Store()
    if not cfg then return end
    if not self.built then
        self.built = true
        self:BuildMainIcons()
        self:BuildRowIcons(self.def.buffRow or {}, self.anchors.AuraRow, cfg.auraRow.iconSize or 25, self.auraIcons)
        if self.anchors.DebuffRow then
            self:BuildRowIcons(self.def.debuffRow or {}, self.anchors.DebuffRow, cfg.debuffRow.iconSize or 26, self.debuffIcons)
        end
        if self.anchors.Reminders then self:BuildReminders() end
        self:BuildBars()
        self:BuildAux()
        self:ApplyColors()
        self:ApplyAnchorPositions()
    end
    if self._serial ~= HUD.serial then self:ApplyColors() end
    self:RefreshMainRow(cfg)
    self:RefreshAuraList(cfg, self.def.buffRow or {}, self.auraIcons, self.auraActive, cfg.auraRow, self.anchors.AuraRow, self.S.buffs, self.memo.aura)
    if self.anchors.DebuffRow then
        self:RefreshAuraList(cfg, self.def.debuffRow or {}, self.debuffIcons, self.debuffActive, cfg.debuffRow, self.anchors.DebuffRow, self.S.targetDebuffs, self.memo.debuff)
    end
    self:RefreshReminders(cfg)
    self:RefreshResources(cfg)
    self:RefreshAux(cfg)
end

function Engine:HideAll()
    if not self.built then return end
    for _, m in pairs(self.memo) do HUD.ForgetLayout(m) end
    for _, set in ipairs({ self.mainIcons, self.auraIcons, self.debuffIcons, self.remindIcons, self.auxIcons }) do
        for _, icon in pairs(set) do icon:Hide() end
    end
    for _, b in ipairs({ self.swingBar, self.rangedBar, self.manaBar, self.fsrBar, self.powerBar, self.tickBar, self.comboFrame, self.wandBar }) do
        if b then b:Hide() end
    end
    for _, fs in pairs(self.textFS or {}) do fs:Hide() end
end

function Engine:ApplySizes()
    if not self.built then return end
    local cfg = self:Store()
    if not cfg then return end
    local r = cfg.resources
    local function size(bar, anchorKey, w, h, extra)
        if not bar then return end
        bar:SetSize(w, h)
        self.anchors[anchorKey]:SetSize(w, h + (extra or 0))
        self.holders[anchorKey]:SetSize(w, h + (extra or 0))
    end
    size(self.swingBar, "Swing", r.pos.swing.w or 316, r.pos.swing.h or 2)
    size(self.rangedBar, "Ranged", r.pos.swing.w or 316, r.pos.swing.h or 2)
    size(self.manaBar, "Mana", r.pos.mana.w or 234, r.pos.mana.h or 4, 6)
    if self.fsrBar then self.fsrBar:SetSize(r.pos.mana.w or 234, 3) end
    size(self.powerBar, "Power", r.pos.power.w or 234, r.pos.power.h or 6, 4)
    if self.tickBar then self.tickBar:SetSize(r.pos.power.w or 234, 2) end
    size(self.wandBar, "Wand", r.pos.wand.w or 300, r.pos.wand.h or 8)
    for _, fs in pairs(self.textFS or {}) do HUD.ApplyFont(fs, r.pos.texts.size or 20, "OUTLINE", "alert") end
    self:ApplyAnchorPositions()
    self:Refresh()
end

-- ------------------------------------------------------------
-- tickers
-- ------------------------------------------------------------
local function CdRemaining(cd)
    if not cd or not cd.real then return 0 end
    return math.max(0, cd.start + cd.duration - GetTime())
end

function Engine:TextTick()
    if not (self.sample or self:IsActive()) then return end
    local S, W = self.S, self.W
    for _, icon in ipairs(self.mainActive) do
        local def = icon.def
        if def.kind == "spell" then
            local remaining = CdRemaining(S.cds[def.spell])
            icon:SetText("p", remaining > 0 and W.FormatTime(remaining, 0) or "")
        end
    end
    for li = 1, 2 do
        local list = (li == 1) and self.auraActive or self.debuffActive
        for _, icon in ipairs(list) do
            local b = icon.auraRef
            if b and b.hidden then
                -- (WoW Forever: the time left and the stacks as the game
                -- hands them over, hidden or not)
                local left = ns.AuraTimeLeft("target", b.hidden)
                if left ~= nil then icon:SetHiddenText("p", "%.0f", left) else icon:SetText("p", "") end
                icon:SetHiddenCount("s", "target", b.hidden)
            elseif b and (b.expirationTime or 0) > 0 then
                icon:SetText("p", W.FormatTime(math.max(0, b.expirationTime - GetTime()), 0))
            else
                icon:SetText("p", "")
            end
            if not (b and b.hidden) then
                icon:SetText("s", (b and (b.count or 0) > 1) and tostring(b.count) or "")
            end
        end
    end
    for _, icon in pairs(self.auxIcons) do
        if icon:IsShown() then
            local remaining, def = 0, icon.def
            if def.slot then
                local t = S.trinkets[def.slot]
                if t and (t.duration or 0) > GCD_MAX then remaining = math.max(0, t.start + t.duration - GetTime()) end
            elseif S.racial then
                local start, duration = self:RacialCD()
                if duration > GCD_MAX then remaining = math.max(0, start + duration - GetTime()) end
            end
            icon:SetText("p", remaining > 0 and W.FormatTime(remaining, 0) or "")
        end
    end
end

function Engine:CoreTick()
    local cfg = self:Store()
    if not cfg or not cfg.enabled or not self.S.isClass then return end
    local d = self.dirty
    if d.spells then d.spells = false self:ResolveSpells() end
    if d.bags then d.bags = false self:ScanItems() end
    if d.auras then d.auras = false self:ScanPlayerBuffs() end
    if d.target then d.target = false self:ScanTargetDebuffs() end
    self:UpdateMisc()
    self:UpdateSpellSnapshot()
    self:Refresh()
end

function Engine:StartTicker()
    if self.coreTicker then return end
    self.coreTicker = HUD.Ticker(0.2, function() self:CoreTick() end)
    self.textTicker = HUD.Ticker(0.1, function() self:TextTick() end)
    self:RegisterHotEvents()
    local d = self.dirty
    d.auras, d.bags, d.spells, d.target = true, true, true, true
    itemCD.MarkDirty()
end

function Engine:StopTicker()
    if self.coreTicker then self.coreTicker:Cancel() self.coreTicker = nil end
    if self.textTicker then self.textTicker:Cancel() self.textTicker = nil end
    self:UnregisterHotEvents()
end

function Engine:SetEnabled(on)
    local cfg = self:Store()
    if cfg then cfg.enabled = on and true or false end
    if on and self.S.isClass then
        self:StartTicker()
    else
        self:StopTicker()
        self:HideAll()
    end
end

function Engine:IsActive()
    local cfg = self:Store()
    return (cfg and cfg.enabled and self.S.isClass) and true or false
end

-- ------------------------------------------------------------
-- events
-- ------------------------------------------------------------
local MELEE_SUBS = { "SWING_DAMAGE", "SWING_MISSED" }
local MELEE_RANGED_SUBS = { "SWING_DAMAGE", "SWING_MISSED", "RANGE_DAMAGE", "RANGE_MISSED" }

function Engine:RegisterHotEvents()
    local ev = self.ev
    self.lastPower = UnitPower("player", UnitPowerType("player") or 0) or 0
    if not self.onCLEU then
        self.onCLEU = function(...) self:OnCombatLogEvent(...) end
    end
    ns.CLEU.On("ClassHUD." .. self.def.store, self.wantsRanged and MELEE_RANGED_SUBS or MELEE_SUBS, self.onCLEU)
    if not self.onSwing then
        self.onSwing = function(...) self:OnSwing(...) end
    end
    ns.Swings.On("ClassHUD." .. self.def.store, self.onSwing)
    ev:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
    ev:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    ev:RegisterEvent("BAG_UPDATE_DELAYED")
    if self.anchors.DebuffRow then ev:RegisterUnitEvent("UNIT_AURA", "target") end
    if self.bars.wand then
        ev:RegisterEvent("START_AUTOREPEAT_SPELL")
        ev:RegisterEvent("STOP_AUTOREPEAT_SPELL")
    end
end

function Engine:UnregisterHotEvents()
    local ev = self.ev
    ns.CLEU.Off("ClassHUD." .. self.def.store)
    ns.Swings.On("ClassHUD." .. self.def.store, nil)
    ev:UnregisterEvent("UNIT_POWER_FREQUENT")
    ev:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    ev:UnregisterEvent("BAG_UPDATE_DELAYED")
    ev:UnregisterEvent("START_AUTOREPEAT_SPELL")
    ev:UnregisterEvent("STOP_AUTOREPEAT_SPELL")
    -- target auras only while running; the player's stay on ns.PlayerAuras
    -- (a cheap flag), see OnEvent
    ev:UnregisterEvent("UNIT_AURA")
end

function Engine:OnEvent(event, arg1, arg2, arg3)
    local S, d = self.S, self.dirty
    if event == "PLAYER_LOGIN" then
        local _, class = UnitClass("player")
        S.isClass = class == self.def.class
        if not S.isClass then
            self.ev:UnregisterAllEvents()
            return
        end
        self.playerGUID = UnitGUID("player")
        S.inCombat = InCombatLockdown() or UnitAffectingCombat("player")
        local ev = self.ev
        ev:RegisterEvent("PLAYER_ENTERING_WORLD")
        -- the player's auras: ZacUI's shared read says when they moved
        ns.PlayerAuras.On("ClassHUD." .. self.def.store, function() d.auras = true end)
        ev:RegisterEvent("SPELLS_CHANGED")
        ev:RegisterEvent("PLAYER_REGEN_DISABLED")
        ev:RegisterEvent("PLAYER_REGEN_ENABLED")
        ev:RegisterEvent("PLAYER_TARGET_CHANGED")
        ev:RegisterEvent("UNIT_DISPLAYPOWER")
        local cfg = self:Store()
        if cfg and cfg.enabled then self:StartTicker() end
        HUD.Debug(self.def.label .. " core initialized")
    elseif event == "UNIT_POWER_FREQUENT" or event == "UNIT_SPELLCAST_SUCCEEDED" then
        self:OnPowerEvent(event, arg3)
    elseif event == "UNIT_AURA" then
        d.target = true                    -- target only; the player's come via ns.PlayerAuras
    elseif event == "PLAYER_TARGET_CHANGED" then
        d.target = true
    elseif event == "BAG_UPDATE_DELAYED" then
        d.bags = true
        itemCD.MarkDirty()
    elseif event == "SPELLS_CHANGED" then
        d.spells = true
    elseif event == "UNIT_DISPLAYPOWER" then
        self.lastPower = UnitPower("player", UnitPowerType("player") or 0) or 0
    elseif event == "PLAYER_REGEN_DISABLED" then
        S.inCombat = true
    elseif event == "PLAYER_REGEN_ENABLED" then
        S.inCombat = false
    elseif event == "START_AUTOREPEAT_SPELL" then
        S.wand.active = true
        local speed = UnitRangedDamage and UnitRangedDamage("player") or 0
        S.wand.start = GetTime()
        S.wand.duration = (speed and speed > 0) and math.min(speed, 0.6) or 0.6
    elseif event == "STOP_AUTOREPEAT_SPELL" then
        S.wand.active = false
        S.wand.duration = 0
    elseif event == "PLAYER_ENTERING_WORLD" then
        d.auras, d.bags, d.spells, d.target = true, true, true, true
        itemCD.MarkDirty()
    end
end

-- ============================================================
-- THE SETTINGS PREVIEW'S SAMPLE
-- ============================================================
-- A second instance of this engine whose anchors are plain frames on the
-- preview canvas and whose state is made up: the same Build / Refresh /
-- TextTick code as the HUD on screen draws it, from fake cooldowns,
-- buffs, debuffs, bars and items. It registers nothing, joins no mover,
-- runs no ticker: its bars drain on their own OnUpdate and its timers
-- count on one OnUpdate, both only while the canvas is on screen.
local ANCHOR_SIZES = {
    Main = { 36, 28 }, AuraRow = { 25, 25 }, DebuffRow = { 26, 26 }, Reminders = { 40, 40 },
    Swing = { 316, 2 }, Ranged = { 316, 2 }, Mana = { 234, 10 }, Power = { 234, 6 },
    Combo = { 66, 10 }, Wand = { 300, 8 }, Texts = { 240, 30 }, Aux = { 30, 30 },
}
Engine.SAMPLE_W, Engine.SAMPLE_H = 500, 112   -- the fitting sizes the canvas to the sample

function Engine:NewSample(canvas)
    local s = setmetatable({
        def = self.def, defaults = self.defaults, bars = self.bars,
        wantsRanged = self.wantsRanged, wantsWeaponEnchant = self.wantsWeaponEnchant,
        sample = true, canvas = canvas,
    }, Engine)
    s.S = {
        isClass = true, inCombat = true,
        spells = {}, cds = {}, usable = {}, inRange = {},
        buffs = {}, targetDebuffs = {}, auraNames = {}, auraIcons = {},
        targetAttackable = true, powerType = 0,
        swing = { start = 0, duration = 0 }, ranged = { start = 0, duration = 0 },
        fsr = { start = 0, duration = 0 }, tick = { start = 0, duration = 0 },
        wand = { start = 0, duration = 0, active = false },
        items = {}, itemCDs = {}, trinkets = {}, racial = nil,
    }
    s.dirty = {}
    s.anchors, s.holders = {}, {}
    for _, e in ipairs(s:Elements()) do
        local sz = ANCHOR_SIZES[e.key] or { 26, 26 }
        local a = HUD.SampleAnchor(canvas, sz[1], sz[2])
        s.anchors[e.key], s.holders[e.key] = a, a
    end
    s.mainIcons, s.mainActive = {}, {}
    s.auraIcons, s.auraActive = {}, {}
    s.debuffIcons, s.debuffActive = {}, {}
    s.remindIcons, s.auxIcons = {}, {}
    s.memo = { main = {}, aura = {}, debuff = {}, remind = {}, aux = {} }
    -- the timers count down while the canvas is shown (OnUpdate stops
    -- by itself when the dock or the window hides)
    local tick = CreateFrame("Frame", nil, canvas)
    tick._acc = 0
    tick:SetScript("OnUpdate", function(f, el)
        f._acc = f._acc + (el or 0)
        if f._acc < 0.1 then return end
        f._acc = 0
        if s.built then s:TextTick() end
    end)
    s.ticker = tick
    return s
end

-- Made-up state for one mode: "combat" (cooldowns running, buffs and
-- debuffs up with timers, swing and resource bars moving) or "ready"
-- (everything back, out of combat).
function Engine:FillSample(mode)
    local S = self.S
    local now = GetTime()
    local combat = mode ~= "ready"
    S.inCombat, S.targetAttackable = combat, combat
    if not self._resolved then
        self._resolved = true
        self:ResolveSpells()
    end
    for key, sp in pairs(S.spells) do
        sp.known = true
        sp.name = sp.name or key
        sp.icon = sp.icon or (GetSpellTexture_C and GetSpellTexture_C(self.def.spells[key])) or 134400
    end
    for _, list in ipairs({ self.def.buffRow or {}, self.def.debuffRow or {} }) do
        for _, e in ipairs(list) do
            S.auraNames[e.key] = S.auraNames[e.key] or e.label or e.key
            S.auraIcons[e.key] = S.auraIcons[e.key] or 134400
        end
    end
    -- a few cooldowns running, one without the power for it, one out of range
    local i, oorDone = 0, false
    for _, g in ipairs(self.def.grid or {}) do
        if g.kind == "spell" and S.spells[g.spell] then
            i = i + 1
            local cd = S.cds[g.spell] or {}
            S.cds[g.spell] = cd
            local us = S.usable[g.spell] or {}
            S.usable[g.spell] = us
            us.usable, us.noPower = true, false
            S.inRange[g.spell] = nil
            if combat and i % 3 == 2 then
                cd.start, cd.duration, cd.real = now - 3 * i, 20 + 12 * i, true
            else
                cd.start, cd.duration, cd.real = 0, 0, false
            end
            if combat and i == 4 then us.noPower = true end
            if combat and not oorDone and i >= 5 and not g.noRange then
                oorDone = true
                S.inRange[g.spell] = 0
            end
        end
    end
    -- items: something of everything the grid and the reminders carry
    wipe(S.items)
    wipe(S.itemCDs)
    local WH = ns.WarriorHUD
    local firstPotion = WH and WH.POTION_LIST and WH.POTION_LIST[1]
    if firstPotion then S.items[firstPotion.id] = 5 end
    S.items[12662] = 3
    for _, g in ipairs(self.def.grid or {}) do
        if g.items and g.items[1] then S.items[g.items[1].id] = 2 end
    end
    if combat and firstPotion then S.itemCDs[firstPotion.id] = { start = now - 30, duration = 120 } end
    -- buffs and debuffs: the first few with timers, one with stacks
    wipe(S.buffs)
    wipe(S.targetDebuffs)
    local function put(out, list, n)
        for k, e in ipairs(list or {}) do
            if k > n then break end
            local name = S.auraNames[e.key]
            if name then
                out[name:lower()] = { name = name, icon = S.auraIcons[e.key], count = (k == 2) and 3 or 0,
                    duration = 30, expirationTime = now + 30 - 7 * k }
            end
        end
    end
    if combat then
        put(S.buffs, self.def.buffRow, 4)
        put(S.targetDebuffs, self.def.debuffRow, 3)
    end
    -- resources
    local bars = self.bars
    if bars.power and bars.mana then
        S.powerType = combat and 3 or 0
    elseif bars.power then
        S.powerType = 3
    else
        S.powerType = 0
    end
    S.mana, S.manaMax = combat and 5200 or 7400, 8000
    S.power, S.powerMax = combat and 70 or 100, 100
    S.cp = combat and 3 or 0
    S.swing.start, S.swing.duration = now - 0.9, 2.6
    S.ranged.start, S.ranged.duration = now - 1.2, 3.0
    S.fsr.start, S.fsr.duration = now - 1.5, 5
    S.tick.start, S.tick.duration = now - 0.7, 2
    S.wand.active = combat
    S.wand.start, S.wand.duration = now - 0.6, 1.8
    -- trinkets and the racial
    S.trinkets[13] = { texture = 133447, start = combat and (now - 40) or 0, duration = combat and 120 or 0 }
    S.trinkets[14] = { texture = 133434, start = 0, duration = 0 }
    S.racial = { name = "Racial", icon = 136225, start = combat and (now - 20) or 0, duration = combat and 180 or 0 }
    -- weapon enchants (the poison / imbue reminders read them)
    S.mhEnchant, S.ohEnchant, S.hasOffhand = false, false, true
    S.mhEnchantLeft, S.ohEnchantLeft = 0, 0
end

-- The sample's pieces, each the size its settings make it, exactly where
-- the HUD puts them on screen (HUD.RealSample: the movers' positions of
-- record, else the stores' defaults), so the preview is the HUD as it
-- will look in game.
function Engine:LayoutSample(cfg)
    local r = cfg.resources
    local nTexts = 0
    for _, t in ipairs(self.def.texts or {}) do if r[t.key] then nTexts = nTexts + 1 end end
    local on = {
        Main = true,
        AuraRow = cfg.auraRow.enabled ~= false,
        DebuffRow = cfg.debuffRow and cfg.debuffRow.enabled ~= false,
        Reminders = cfg.reminders and cfg.reminders.enabled,
        Texts = nTexts > 0,
        Ranged = r.ranged, Swing = r.swing,
        Power = r.power or r.tick, Mana = r.mana or r.fsr,
        Combo = r.combo, Wand = r.wand,
        Aux = cfg.aux.enabled,
    }
    local scale = { Main = cfg.mainRow.scale or 1, AuraRow = cfg.auraRow.scale or 1 }
    local pieces = {}
    for _, e in ipairs(self:Elements()) do
        local a = self.anchors[e.key]
        if a then
            pieces[#pieces + 1] = { a = a, mover = e.mover, store = e.cfg(cfg), scale = scale[e.key] or 1,
                on = on[e.key] and true or false }
        end
    end
    HUD.RealSample(self.canvas, pieces)
end

-- The dock preview for this HUD's page.
function Engine:PreviewSpec()
    local eng = self
    return {
        key = "hud." .. self.def.store,
        title = self.def.label,
        width = Engine.SAMPLE_W, height = Engine.SAMPLE_H,
        modes = { { id = "combat", label = "In combat" }, { id = "ready", label = "Out of combat" } },
        build = function(canvas, P)
            P.store.sample = eng:NewSample(canvas)
        end,
        update = function(canvas, P)
            local s = P.store.sample
            if not s then return end
            HUD.CheckLook()
            s:FillSample(P.mode or "combat")
            s:Refresh()
            s:ApplyColors()
            s:ApplySizes()
            s:TextTick()
        end,
        replay = function(canvas, P)
            local s = P.store.sample
            if not (s and s.built) then return end
            HUD.ReplayIcons({ s.mainIcons, s.auraIcons, s.debuffIcons, s.remindIcons, s.auxIcons }, true)
        end,
    }
end

-- ============================================================
-- SETTINGS PAGE (the Paladin page's shape, generic)
-- ============================================================
local M = UI.M
local Check, SliderPair, CheckGrid = HUD.CheckIndent, HUD.SliderPair, HUD.CheckGrid

local function Px(v) return v .. " px" end

-- The colour settings this HUD actually draws, labelled.
local COLOR_LABELS = {
    { "oor", "Out of range tint" }, { "timer", "Timer text" }, { "count", "Count text" },
    { "text", "Reminder text", needs = "texts" }, { "barText", "Bar value text", needs = "manaOrPower" },
    { "mana", "Mana bar", needs = "mana" }, { "fsr", "Five-second rule bar", needs = "fsr" },
    { "energy", "Energy bar", needs = "power" }, { "rage", "Rage bar", needs = "power" },
    { "tick", "Energy tick bar", needs = "tick" }, { "swing", "Swing timer", needs = "swing" },
    { "ranged", "Auto Shot timer", needs = "ranged" }, { "wand", "Wand bar", needs = "wand" },
    { "cpOn", "Combo point", needs = "combo" }, { "cpOff", "Empty combo point", needs = "combo" },
}

function Engine:Tab_General(L, cfg)
    local def, eng, S = self.def, self, self.S
    L:Card(def.label)
    L:Desc((def.blurb or "") .. " " .. def.className .. " characters only.")
    Check(L, "Enable " .. def.label, cfg.enabled, function(v) eng:SetEnabled(v) end)
    Check(L, "Show every element on screen (test)", self.preview and true or false, function(v)
        eng.preview = v
        eng:Refresh()
    end, nil, "Forces every enabled piece visible where it sits, to line things up. Not saved.")
    L:EndCard()

    L:Card("Cooldown grid")
    L:Desc("Untick an icon to remove it from the grid.")
    CheckGrid(L, def.grid,
        function(g) return g.label end,
        function(g) return not cfg.mainRow.hidden[g.key] end,
        function(g, v) cfg.mainRow.hidden[g.key] = (not v) and true or nil eng:Refresh() end)
    local hasPotion = false
    for _, g in ipairs(def.grid) do if g.kind == "itemPotion" then hasPotion = true end end
    if hasPotion then
        HUD.Label(L, "Potion icon")
        HUD.Dropdown(L, 220, HUD.PotionItems(),
            function() return HUD.PotionLabel(cfg.mainRow.potionChoice) end,
            function(value) cfg.mainRow.potionChoice = value eng:Refresh() end,
            "Which potion the grid's potion icon tracks. Automatic shows the first one in your bags, in the standard priority order.")
    end
    L:EndCard()

    if def.buffRow and #def.buffRow > 0 then
        L:Card("Active buff row")
        Check(L, "Show the active buff row", cfg.auraRow.enabled ~= false, function(v) cfg.auraRow.enabled = v eng:Refresh() end)
        CheckGrid(L, def.buffRow,
            function(b) return b.label or S.auraNames[b.key] or b.key end,
            function(b) return not cfg.auraRow.hidden[b.key] end,
            function(b, v) cfg.auraRow.hidden[b.key] = (not v) and true or nil eng:Refresh() end)
        L:EndCard()
    end

    if def.debuffRow and #def.debuffRow > 0 then
        L:Card("Target debuff row")
        L:Desc("Your own debuffs on the current target, with time left.")
        Check(L, "Show the target debuff row", cfg.debuffRow.enabled ~= false, function(v) cfg.debuffRow.enabled = v eng:Refresh() end)
        CheckGrid(L, def.debuffRow,
            function(b) return b.label or S.auraNames[b.key] or b.key end,
            function(b) return not cfg.debuffRow.hidden[b.key] end,
            function(b, v) cfg.debuffRow.hidden[b.key] = (not v) and true or nil eng:Refresh() end)
        L:EndCard()
    end

    if def.reminders and #def.reminders > 0 then
        L:Card("Reminders")
        L:Desc("Big icons that show while something is missing.")
        Check(L, "Show reminders", cfg.reminders.enabled, function(v) cfg.reminders.enabled = v eng:Refresh() end)
        for _, rdef in ipairs(def.reminders) do
            Check(L, rdef.label, cfg.reminders[rdef.key], function(v) cfg.reminders[rdef.key] = v eng:Refresh() end, 16)
        end
        L:EndCard()
    end

    L:Card("Bars and reminder texts")
    local r = cfg.resources
    local LABELS = {
        swing = "Swing timer bar (combat only)", ranged = "Auto Shot timer bar (combat only)",
        mana = "Mana bar", fsr = "Five-second rule / tick bar", power = def.powerLabel and (def.powerLabel .. " bar") or "Energy / rage bar",
        tick = "Energy tick bar", combo = "Combo points", wand = "Wand swing bar",
    }
    for _, b in ipairs(def.bars or {}) do
        Check(L, LABELS[b] or b, r[b], function(v) r[b] = v eng:Refresh() end)
    end
    for _, t in ipairs(def.texts or {}) do
        Check(L, "\"" .. t.text .. "\" text", r[t.key], function(v) r[t.key] = v eng:Refresh() end)
    end
    L:EndCard()

    L:Card("Trinkets and racial")
    Check(L, "Show the trinket and racial row", cfg.aux.enabled, function(v) cfg.aux.enabled = v eng:Refresh() end)
    Check(L, "Trinket slot 1", cfg.aux.trinket1, function(v) cfg.aux.trinket1 = v eng:Refresh() end, 16)
    Check(L, "Trinket slot 2", cfg.aux.trinket2, function(v) cfg.aux.trinket2 = v eng:Refresh() end, 16)
    Check(L, "Racial ability", cfg.aux.racial, function(v) cfg.aux.racial = v eng:Refresh() end, 16)
    L:EndCard()
end

function Engine:Tab_Look(L, cfg)
    local def, eng = self.def, self
    local bars = self.bars
    local r = cfg.resources

    L:Card("Cooldown grid")
    local rows = cfg.mainRow.rows
    SliderPair(L,
        { "Row 1 icon size", 16, 48, rows[1].w, function(v) rows[1].w, rows[1].h = v, v eng:Refresh() end, Px },
        { "Row 1 icon count", 4, 14, rows[1].limit, function(v) rows[1].limit = v eng:Refresh() end })
    SliderPair(L,
        { "Row 2+ icon size", 16, 48, rows[2].w, function(v)
            rows[2].w, rows[2].h = v, v
            rows[3].w, rows[3].h = v, v
            eng:Refresh()
        end, Px },
        { "Spacing", 0, 12, cfg.mainRow.spacing, function(v) cfg.mainRow.spacing = v eng:Refresh() end, Px })
    L:EndCard()

    L:Card("Rows")
    if def.buffRow and #def.buffRow > 0 then
        SliderPair(L,
            { "Active buff icon size", 14, 48, cfg.auraRow.iconSize, function(v) cfg.auraRow.iconSize = v eng:ApplySizes() end, Px },
            { "Active buff spacing", 0, 12, cfg.auraRow.spacing, function(v) cfg.auraRow.spacing = v eng:Refresh() end, Px })
    end
    if def.debuffRow and #def.debuffRow > 0 then
        SliderPair(L,
            { "Target debuff icon size", 14, 48, cfg.debuffRow.iconSize, function(v) cfg.debuffRow.iconSize = v eng:ApplySizes() end, Px },
            { "Target debuff spacing", 0, 12, cfg.debuffRow.spacing, function(v) cfg.debuffRow.spacing = v eng:Refresh() end, Px })
    end
    if def.reminders and #def.reminders > 0 then
        SliderPair(L,
            { "Reminder icon size", 20, 64, cfg.reminders.iconSize, function(v) cfg.reminders.iconSize = v eng:ApplySizes() end, Px },
            { "Reminder spacing", 0, 16, cfg.reminders.spacing, function(v) cfg.reminders.spacing = v eng:Refresh() end, Px })
    end
    SliderPair(L,
        { "Trinket icon size", 16, 56, cfg.aux.iconSize or 30, function(v) cfg.aux.iconSize = v eng:Refresh() end, Px },
        { "Trinket spacing", 0, 12, cfg.aux.spacing or 4, function(v) cfg.aux.spacing = v eng:Refresh() end, Px })
    L:EndCard()

    L:Card("Bars")
    if bars.mana then
        SliderPair(L,
            { "Mana bar width", 100, 500, r.pos.mana.w, function(v) r.pos.mana.w = v eng:ApplySizes() end, Px },
            { "Mana bar height", 2, 16, r.pos.mana.h, function(v) r.pos.mana.h = v eng:ApplySizes() end, Px })
    end
    if bars.power then
        SliderPair(L,
            { "Power bar width", 100, 500, r.pos.power.w, function(v) r.pos.power.w = v eng:ApplySizes() end, Px },
            { "Power bar height", 2, 16, r.pos.power.h, function(v) r.pos.power.h = v eng:ApplySizes() end, Px })
    end
    if bars.swing or bars.ranged then
        SliderPair(L,
            { "Swing bar width", 100, 500, r.pos.swing.w, function(v) r.pos.swing.w = v eng:ApplySizes() end, Px },
            { "Swing bar height", 1, 12, r.pos.swing.h, function(v) r.pos.swing.h = v eng:ApplySizes() end, Px })
    end
    if bars.wand then
        SliderPair(L,
            { "Wand bar width", 100, 500, r.pos.wand.w, function(v) r.pos.wand.w = v eng:ApplySizes() end, Px },
            { "Wand bar height", 2, 16, r.pos.wand.h, function(v) r.pos.wand.h = v eng:ApplySizes() end, Px })
    end
    if bars.combo then
        SliderPair(L,
            { "Combo point size", 6, 20, r.pos.combo.size, function(v) r.pos.combo.size = v eng:Refresh() end, Px },
            { "Combo point spacing", 0, 12, r.pos.combo.spacing, function(v) r.pos.combo.spacing = v eng:Refresh() end, Px })
    end
    L:EndCard()

    L:Card("Colours")
    local has = {
        texts = def.texts and #def.texts > 0, manaOrPower = bars.mana or bars.power,
        mana = bars.mana, fsr = bars.fsr, power = bars.power, tick = bars.tick,
        swing = bars.swing, ranged = bars.ranged, wand = bars.wand, combo = bars.combo,
    }
    local entries = {}
    for _, c in ipairs(COLOR_LABELS) do
        if not c.needs or has[c.needs] then
            local key = c[1]
            entries[#entries + 1] = { c[2],
                get = function() return HUD.Col(cfg.colors[key], COLOR_DEFAULTS[key]) end,
                set = function(rr, g, b, a)
                    cfg.colors[key] = { r = rr, g = g, b = b, a = a or 1 }
                    eng:ApplyColors()
                end }
        end
    end
    HUD.ColorGrid(L, entries)
    L:EndCard()

    HUD.SharedLookCards(L)
end

function Engine:Tab_Text(L, cfg)
    local eng = self
    local r = cfg.resources
    local alert
    if self.def.texts and #self.def.texts > 0 then
        alert = { label = "Reminder text", defaultSize = 20, sample = self.def.texts[1].text,
            getSize = function() return r.pos.texts.size or 20 end,
            setSize = function(v) r.pos.texts.size = v eng:ApplySizes() end }
    end
    HUD.SharedTextCards(L, alert)
end

function Engine:Tab_Position(L, cfg)
    local eng = self
    L:Card("Position")
    L:Desc("Every piece of the HUD is its own anchor: drag them to line up with your unit frames.")
    HUD.UnlockButton(L, self.def.prefix)
    L:Gap(4)
    HUD.ScaleSlider(L, "Cooldown grid scale", cfg.mainRow, "scale", function() eng:ApplyAnchorPositions() end)
    if self.def.buffRow and #self.def.buffRow > 0 then
        HUD.ScaleSlider(L, "Active buff row scale", cfg.auraRow, "scale", function() eng:ApplyAnchorPositions() end)
    end
    L:EndCard()
end

function Engine:Tab_Advanced(L, cfg)
    local eng = self
    L:Card("Reset")
    HUD.Button(L, "Reset colours", 150, function()
        cfg.colors = ns.CopySetting(COLOR_DEFAULTS)
        eng:ApplyColors()
        ns.SettingsChanged("reset")
        HUD.RefreshPage()
    end, "Puts this HUD's colours back to the defaults.")
    HUD.ResetLookButton(L)
    L:EndCard()
end

function Engine:BuildPage(L)
    local def = self.def
    L:Header(def.label, def.blurb or "Cooldown grid, active buffs, target debuffs, reminders and resource bars.")
    local cfg = self:Store()
    if not cfg then
        L:Notice("missing", "The HUD settings are not available yet.")
        return
    end
    local eng = self
    -- fitted after every update: in the dock's strata, inside the canvas
    L:Preview(HUD.FitSpec(self:PreviewSpec()))
    L:Tabs({
        { id = "general", label = "General",   build = function(L2) eng:Tab_General(L2, cfg) end },
        { id = "look",    label = "Look",      build = function(L2) eng:Tab_Look(L2, cfg) end },
        { id = "text",    label = "Text",      build = function(L2) eng:Tab_Text(L2, cfg) end },
        { id = "anim",    label = "Animation", build = function(L2) HUD.SharedAnimCards(L2) end },
        { id = "pos",     label = "Position",  build = function(L2) eng:Tab_Position(L2, cfg) end },
        { id = "adv",     label = "Advanced",  build = function(L2) eng:Tab_Advanced(L2, cfg) end },
    })
end

-- ============================================================
-- DEFINE
-- ============================================================
-- def = {
--   class = "MAGE", className = "Mage", label = "Mage HUD", store = "mage",
--   prefix = "mg", frameName = "Mage", blurb = "...",
--   spells = { key = spellId, ... },
--   grid = { { key, kind = "spell", spell = key, label, noRange, when = fn(S) }
--          | { key, kind = "itemPotion" | "itemRune", label }
--          | { key, kind = "item", items = { { id, icon } ... }, label } },
--   buffRow = { { key, id, label } ... },         -- own player buffs
--   debuffRow = { { key, id, label } ... },       -- own debuffs on target
--   reminders = { { key, label, spell, icon, default, check = fn(H, S) -> shown, tex, count, left } },
--   bars = { "mana", "fsr", "swing", "ranged", "power", "tick", "combo", "wand" },
--   texts = { { key, text, check = fn(H, S) -> bool, default } },
--   powerLabel = "Energy", potionChoice = 13, weaponEnchant = true, keywords = "...",
-- }
function HUD.DefineClass(def)
    local self = setmetatable({}, Engine)
    self.def = def
    self.defaults = DefaultsFor(def)
    self.bars = {}
    for _, b in ipairs(def.bars or {}) do self.bars[b] = true end
    self.wantsRanged = self.bars.ranged
    self.wantsWeaponEnchant = def.weaponEnchant
    self.S = {
        isClass = false, inCombat = false,
        spells = {}, cds = {}, usable = {}, inRange = {},
        buffs = {}, targetDebuffs = {}, auraNames = {}, auraIcons = {},
        targetAttackable = false, powerType = 0,
        swing = { start = 0, duration = 0 }, ranged = { start = 0, duration = 0 },
        fsr = { start = 0, duration = 0 }, tick = { start = 0, duration = 0 },
        wand = { start = 0, duration = 0, active = false },
        items = {}, trinkets = {}, racial = nil,
    }
    self.dirty = { auras = true, bags = true, spells = true, target = true }
    self.lastPower, self.fsrCastAt = 0, -10
    self.anchors, self.holders = {}, {}
    self.mainIcons, self.mainActive = {}, {}
    self.auraIcons, self.auraActive = {}, {}
    self.debuffIcons, self.debuffActive = {}, {}
    self.remindIcons, self.auxIcons = {}, {}
    -- what each row was last laid out with (HUD.LayoutGrid / LayoutRow)
    self.memo = { main = {}, aura = {}, debuff = {}, remind = {}, aux = {} }

    -- Frames exist only for the class they serve.
    local isClass = select(2, UnitClass("player")) == def.class
    if isClass then
        self:CreateAnchors()
        C_Timer.After(2, function()
            self:ApplyAnchorPositions()
            self:RegisterMovers()
        end)
    end

    self.ev = CreateFrame("Frame")
    self.ev:RegisterEvent("PLAYER_LOGIN")
    self.ev:SetScript("OnEvent", function(_, event, a1, a2, a3) self:OnEvent(event, a1, a2, a3) end)

    HUD.RegisterPage(def.store, def.label, (def.keywords or "") .. " " .. HUD.PAGE_KEYWORDS, { [def.class] = true },
        function(L) self:BuildPage(L) end)

    return self
end
