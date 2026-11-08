-- CB_Core - the consumable bars' settings and what they read from the
-- game: the bags (counts, where each item sits for its cooldown), the
-- player's buffs, the weapons and their enchants. And the one function
-- that decides which buttons a bar shows, in what order (CB.Collect) -
-- the live bars and the settings preview both call it, the preview with
-- a made-up world.
-- Part of ZacUI; load order is set by the TOC.
--
-- COST. Nothing here runs from a hot event. The bags are scanned when
-- they changed (BAG_UPDATE_DELAYED marks them, the next read scans), the
-- buffs come from the shared aura read (ns.PlayerAuras), the weapon
-- enchants are held half a second, a bag weapon's tooltip two.

local ADDON_NAME = ...
local ns = _G.ZacUI
if not ns then return end
local D = ns.ConsData
if not D then return end

local CB = {}
ns.ConsBars = CB

local GetTime, pairs, ipairs, type, tonumber = GetTime, pairs, ipairs, type, tonumber
local math_floor, math_min = math.floor, math.min

CB.BARS = { "main", "potions", "weapons" }
CB.LABELS = { main = "Consumables bar", potions = "Potion bar", weapons = "Weapon bar" }
-- Readycheck's name for the same bar (the import, the "turn it off" note)
CB.RC_KEYS = { main = "consumablesHelper", potions = "potionsBar", weapons = "weaponsBar" }

-- ids for the buttons that are not one item: a hand's stone button, a
-- bag weapon (900000 + bag * 100 + slot)
CB.MH, CB.OH = 999901, 999902
local function IsBagWeaponId(id) return id >= 900000 and id < 999900 end
CB.IsBagWeaponId = IsBagWeaponId

-- ============================================================
-- SETTINGS - ZacUIDB.consbars (a profile section)
-- ============================================================
-- Every bar off until turned on. The rest are Readycheck's own defaults,
-- so a bar looks and behaves the same as its Readycheck twin.
local BAR_COMMON = {
    enabled = false, locked = true, hideInCombat = false,
    buttonSize = 32, buttonsPerRow = 10, iconSpacing = 4, growDirection = "DOWN", scale = 1,
    showBackground = false, showCount = true, showItemNames = false, showTooltips = false,
    showExpiryTimer = true, showBeforeExpiry = 60,
    visibilityMode = "always", mouseoverFade = false, mouseoverFadeAlpha = 0.15, tts = false,
}
local function Merge(base, extra)
    local t = {}
    for k, v in pairs(base) do t[k] = v end
    for k, v in pairs(extra or {}) do t[k] = v end
    return t
end
CB.DEFAULTS = {
    stone = D.DEFAULT_STONE or 18262,   -- the stone / oil the weapon buttons put on
    weaponIcons = true,         -- the hand buttons show the weapon, not the stone
    potionReadyTTS = false,     -- "Potion ready" when the potion cooldown ends
    ttsRepeat = false, ttsRepeatCount = 1, ttsRepeatInterval = 60,
    main = Merge(BAR_COMMON, {
        showOnlyAvailable = false, hideWhenActive = false, hideConflictingBuffs = false,
        groupConflictButtons = true, selfCastJujus = true, petrificationCampMode = false,
        hideUsedInCombat = true, showBagWeapons = false,
    }),
    potions = Merge(BAR_COMMON, {
        showOnlyAvailable = false, hideWhenActive = false, petrificationCampMode = false,
    }),
    weapons = Merge(BAR_COMMON, {
        buttonSize = 36, buttonsPerRow = 4, growDirection = "RIGHT", showBackground = true,
        showEquippedWeapons = true, showBagWeapons = true,
    }),
}
-- where each bar starts (the movers' default spot; Readycheck's)
CB.DEFAULT_SPOT = {
    main = { point = "TOPRIGHT", x = -10, y = -200 },
    potions = { point = "TOPRIGHT", x = -10, y = -400 },
    weapons = { point = "BOTTOMLEFT", x = 300, y = 100 },
}
-- Not in DEFAULTS on purpose (an empty table there would land in every
-- save): hiddenItems, hiddenWeapons, itemOrder, customItems,
-- conflictGroupPreferences, conflictGroupQuickUse, clickActions,
-- hordeByFaction, visibilityRaids, style, anchors, formats, visibility,
-- chrome, position, stoneBySlot, itemTTS. nil reads as "none".

function CB.Cfg()
    if type(ZacUIDB) ~= "table" then return CB.DEFAULTS end
    local c = ZacUIDB.consbars
    if type(c) ~= "table" then c = {} ZacUIDB.consbars = c end
    -- filled once per table (a profile worn hands over a new one, or
    -- clears a bar: filled again); the bars read this every tick
    if c ~= CB._filled or type(c.main) ~= "table" or type(c.potions) ~= "table" or type(c.weapons) ~= "table" then
        if ns.FillDefaults then ns.FillDefaults(c, CB.DEFAULTS) end
        CB._filled = c
    end
    return c
end
function CB.Bar(key)
    local c = CB.Cfg()
    return c[key] or CB.DEFAULTS[key]
end
local function T(cfg, k) local t = cfg and cfg[k] return type(t) == "table" and t or nil end
CB.T = T

-- a bar's item hidden? (the potion bar starts with its food hidden: a
-- saved table, once written, is the whole truth - false means shown)
function CB.Hidden(key, cfg, id)
    local h = T(cfg, "hiddenItems")
    if h then return h[id] == true end
    if key == "potions" then return D.POTION_BAR_HIDDEN[id] == true end
    return false
end
function CB.SetHidden(key, cfg, id, on)
    local h = T(cfg, "hiddenItems")
    if not h then
        h = {}
        if key == "potions" then for k in pairs(D.POTION_BAR_HIDDEN) do h[k] = true end end
        cfg.hiddenItems = h
    end
    h[id] = on and true or false
end

-- Horde mode (no main-hand stone button: Windfury Totem): per bar and
-- per faction - unset is on for Horde, off for Alliance
local function Faction()
    local f = UnitFactionGroup and UnitFactionGroup("player")
    if f == "Horde" or f == "Alliance" then return f end
end
function CB.HordeMode(cfg)
    local f = Faction()
    local set = T(cfg, "hordeByFaction")
    local v = set and f and set[f]
    if v == nil then return f == "Horde" end
    return v and true or false
end
function CB.SetHordeMode(cfg, on)
    local f = Faction()
    if not f then return end
    if type(cfg.hordeByFaction) ~= "table" then cfg.hordeByFaction = {} end
    cfg.hordeByFaction[f] = on and true or false
end

local function IsRogue() return UnitClass and select(2, UnitClass("player")) == "ROGUE" end
CB.IsRogue = IsRogue

-- ============================================================
-- THE GAME - the bags
-- ============================================================
local Bags = { dirty = true, version = 0, counts = {}, loc = {} }
CB.Bags = Bags
local CC = C_Container
local function NumSlots(bag)
    if CC and CC.GetContainerNumSlots then return CC.GetContainerNumSlots(bag) or 0 end
    return GetContainerNumSlots and GetContainerNumSlots(bag) or 0
end
local function SlotItem(bag, slot)
    if CC and CC.GetContainerItemInfo then
        local info = CC.GetContainerItemInfo(bag, slot)
        if type(info) == "table" then return info.itemID, info.stackCount or 1 end
        return nil
    end
    if GetContainerItemInfo then
        local _, count, _, _, _, _, link = GetContainerItemInfo(bag, slot)
        local id = link and tonumber(link:match("item:(%d+)"))
        return id, count or 1
    end
end
function Bags.Mark() Bags.dirty = true end
function Bags.Fresh()
    if not Bags.dirty then return end
    Bags.dirty = false
    local counts, loc = {}, {}
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        for slot = 1, NumSlots(bag) do
            local id, n = SlotItem(bag, slot)
            if id then
                counts[id] = (counts[id] or 0) + (n or 1)
                if not loc[id] then loc[id] = { bag, slot } end
            end
        end
    end
    Bags.counts, Bags.loc = counts, loc
    Bags.version = Bags.version + 1
end
function Bags.Count(id)
    Bags.Fresh()
    return Bags.counts[id] or 0
end
-- each bag slot: fn(bag, slot, itemId)
function Bags.Each(fn)
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        for slot = 1, NumSlots(bag) do
            local id = SlotItem(bag, slot)
            if id then fn(bag, slot, id) end
        end
    end
end

-- ============================================================
-- THE LIVE WORLD - what CB.Collect and the buttons read
-- ============================================================
local W = {}
CB.World = W
function W.Now() return GetTime() end
function W.Count(id) return Bags.Count(id) end

-- an item's cooldown from its bag slot (Classic has no cooldown by item id)
function W.Cooldown(id)
    if not id or id > 900000 then return 0, 0 end
    Bags.Fresh()
    local l = Bags.loc[id]
    if not (l and CC and CC.GetContainerItemCooldown) then return 0, 0 end
    local s, d = CC.GetContainerItemCooldown(l[1], l[2])
    s, d = tonumber(s) or 0, tonumber(d) or 0
    -- a start from before this session's clock reads as hours: brought back
    if s > GetTime() + 1 then s = s - 4294967.296 end
    return s, d
end

-- the player's buffs: spell id -> { name, expirationTime }, and by name
local buffVer, byId, byName = nil, {}, {}
local trackedIds
local function BuffMaps()
    local A = ns.PlayerAuras
    local v = A and A.Version and A.Version() or 0
    if v == buffVer and byId then return byId, byName end
    buffVer = v
    byId, byName = {}, {}
    for _, a in ipairs((A and A.Buffs and A.Buffs()) or {}) do
        if a.spellId then byId[a.spellId] = a end
        if a.name then byName[a.name:lower()] = a end
    end
    return byId, byName
end
CB.BuffMaps = BuffMaps
-- The same consumable buff comes with several spell ids, so fall back to
-- its name - unless that id is another consumable's (two items sharing a
-- buff name would claim each other's timers).
function W.Buff(buffId)
    if not buffId then return false, 0 end
    local ids, names = BuffMaps()
    local a = ids[buffId]
    if not a then
        local nm = GetSpellInfo and GetSpellInfo(buffId)
        local hit = nm and names[nm:lower()]
        if hit and not (hit.spellId and D.BY_BUFF[hit.spellId] and hit.spellId ~= buffId) then a = hit end
    end
    if not a then return false, 0 end
    local exp = tonumber(a.expirationTime) or 0
    return true, exp > 0 and (exp - GetTime()) or 0
end
function W.ItemBuff(id)
    local it = D.BY_ID[id] or (CB._custom and CB._custom[id])
    if it and it.buffId == nil and it.buffName then return W.NamedBuff(it.buffName, id) end
    return W.Buff(it and it.buffId)
end

-- TBC / Forever: a buff known only by its name (Forever's "Well Fed").
-- Never another consumable's buff that has an id (TBC's foods are "Well
-- Fed" too). Several items sharing the name: the one last used owns it;
-- none used yet, each of them reads it.
local namedLast = {}
function CB.NoteNamedUse(id)
    local it = id and D.BY_ID[id]
    if it and it.buffId == nil and it.buffName then namedLast[it.buffName:lower()] = id end
end
-- the item a name-only buff belongs to (nil: not known which)
function CB.NamedOwner(lname)
    local id = namedLast[lname]
    local list = D.BY_BUFF_NAME and D.BY_BUFF_NAME[lname]
    if not (id and list) then return nil end
    for _, x in ipairs(list) do if x == id then return id end end
    return nil
end
function W.NamedBuff(name, id)
    if not name then return false, 0 end
    local _, names = BuffMaps()
    local lname = name:lower()
    local a = names[lname]
    if not a or (a.spellId and D.BY_BUFF[a.spellId]) then return false, 0 end
    local owner = id and CB.NamedOwner(lname)
    if owner and owner ~= id then return false, 0 end
    local exp = tonumber(a.expirationTime) or 0
    return true, exp > 0 and (exp - GetTime()) or 0
end

-- a clash group's live member: a rival's buff, or the explosives' shared
-- cooldown (they give no buff); held half a second per group
local groupCache = {}
function CB.ClearGroupCache() for k in pairs(groupCache) do groupCache[k] = nil end end
function W.GroupBuff(g)
    local set = D.CONFLICT[g]
    if not set then return false, 0, nil end
    local now = GetTime()
    local c = groupCache[g]
    if c and now - c.t < 0.5 then return c.has, c.rem, c.id end
    local has, rem, who = false, 0, nil
    if g == "engineeringExplosives" then
        for id in pairs(set) do
            if not D.OWN_TIMER[id] and not has then
                local s, d = W.Cooldown(id)
                if s > 0 and d > 0 and s + d - now > 0 then has, rem, who = true, s + d - now, id end
            end
        end
    else
        for id in pairs(set) do
            if not has then
                local h, r = W.ItemBuff(id)
                if h then has, rem, who = true, r, id end
            end
        end
        -- TBC: a flask fills both elixir slots (and an elixir the flask's)
        local also = D.GROUP_BLOCKS and D.GROUP_BLOCKS[g]
        for _, og in ipairs(also or {}) do
            for id in pairs(D.CONFLICT[og] or {}) do
                if not has then
                    local h, r = W.ItemBuff(id)
                    if h then has, rem, who = true, r, id end
                end
            end
        end
    end
    groupCache[g] = { t = now, has = has, rem = rem, id = who }
    return has, rem, who
end

-- the weapon enchants (one call fills both hands; a poison low on
-- charges reads as a few seconds left, so it shows and warns)
local ench = { t = -1 }
local function Slot(has, exp, charges, id)
    local secs = has and ((tonumber(exp) or 0) / 1000) or 0
    local ch = has and tonumber(charges) or 0
    local low = has and ch > 0 and ch <= D.POISON_LOW_CHARGES or false
    return { has = has and true or false, rem = low and math_min(secs, 5) or secs, real = secs, charges = ch, low = low, id = id }
end
function CB.ClearEnchantCache() ench.t = -1 end
function W.Enchant(slot)
    local now = GetTime()
    if now - ench.t >= 0.5 then
        ench.t = now
        local mh, mhe, mhc, mhid, oh, ohe, ohc, ohid
        if GetWeaponEnchantInfo then mh, mhe, mhc, mhid, oh, ohe, ohc, ohid = GetWeaponEnchantInfo() end
        ench.mainhand, ench.offhand = Slot(mh, mhe, mhc, mhid), Slot(oh, ohe, ohc, ohid)
    end
    local e = ench[slot]
    if not (e and e.has) then return false, 0, nil, 0 end
    return true, e.rem, e.id, e.charges, e.low, e.real
end

-- A bag weapon's enchant: no API reads it, only its tooltip (a short
-- green line with a duration). Held two seconds; bag and weapon changes
-- drop it.
local bagEnch = {}
local scanTip
function CB.ClearBagEnchantCache() for k in pairs(bagEnch) do bagEnch[k] = nil end end
local function TipLines(bag, slot)
    if not scanTip then
        scanTip = CreateFrame("GameTooltip", "ZacUIConsScanTip", nil, "GameTooltipTemplate")
        if scanTip.SetOwner then scanTip:SetOwner(WorldFrame or UIParent, "ANCHOR_NONE") end
    end
    local out = {}
    if not scanTip.SetBagItem then return out end
    pcall(scanTip.ClearLines, scanTip)
    if not pcall(scanTip.SetBagItem, scanTip, bag, slot) then return out end
    local n = scanTip.NumLines and scanTip:NumLines() or 0
    for i = 1, n do
        local fs = _G["ZacUIConsScanTipTextLeft" .. i]
        local text = fs and fs.GetText and fs:GetText()
        if text then
            local r, g, b = 1, 1, 1
            if fs.GetTextColor then r, g, b = fs:GetTextColor() end
            out[#out + 1] = { text = text, r = r or 1, g = g or 1, b = b or 1 }
        end
    end
    return out
end
CB.TipLines = TipLines
local EFFECT_WORDS = { "over%s+%d+%s*sec", "for%s+%d+%s*sec", "damage", "wounds", "restore", "heal", "shadow",
    "fire", "frost", "nature", "arcane", "holy", "target", "chance", "proc", "struck", "when hit", "attacker" }
function CB.ReadTempEnchant(lines)
    for _, l in ipairs(lines) do
        local text = l.text
        local lower = text:lower()
        local mins, secs = text:match("(%d+)%s*min"), text:match("(%d+)%s*sec")
        if mins or secs then
            local effect = false
            for _, w in ipairs(EFFECT_WORDS) do if lower:find(w) then effect = true break end end
            local green = (l.g or 0) > 0.8 and (l.r or 1) < 0.5 and (l.b or 1) < 0.5
            local paren = text:match("%(%d+%s*min%)%s*$") or text:match("%(%d+%s*sec%)%s*$")
            local ok = (paren or lower:find("remaining") or (#text < 20 and green)) and not effect
                and not lower:find("cooldown")
            if ok then
                return true, (tonumber(mins) or 0) * 60 + (tonumber(secs) or 0)
            end
        end
    end
    return false, 0
end
function W.BagEnchant(bag, slot)
    local k = bag * 100 + slot
    local now = GetTime()
    local c = bagEnch[k]
    if c and now - c.t < 2 then return c.has, c.rem end
    local has, rem = CB.ReadTempEnchant(TipLines(bag, slot))
    bagEnch[k] = { t = now, has = has, rem = rem }
    return has, rem
end

-- an equipped weapon: its icon, id, link, name, and whether a stone goes on it
local function Takes(sub, list)
    sub = sub and sub:lower() or ""
    for _, w in ipairs(list) do if sub:find(w, 1, true) then return true end end
    return false
end
function W.Equipped(inv)
    local tex = GetInventoryItemTexture and GetInventoryItemTexture("player", inv)
    if not tex then return nil end
    local id = GetInventoryItemID and GetInventoryItemID("player", inv)
    local link = GetInventoryItemLink and GetInventoryItemLink("player", inv)
    local ok = false
    if link and GetItemInfo then
        local _, _, _, _, _, _, sub, _, loc, _, _, classId = GetItemInfo(link)
        if classId == 2 and (inv == 16 or loc ~= "INVTYPE_SHIELD") then
            ok = Takes(sub, inv == 16 and D.SHARPEN_MH or D.SHARPEN_OH)
        end
    end
    return { texture = tex, itemId = id, link = link, name = link and link:match("%[(.-)%]"), sharpenable = ok }
end

-- the weapons in the bags that take a stone (per bag change)
local bagWeapons, bagWeaponsVer
function W.BagWeapons()
    Bags.Fresh()
    if bagWeapons and bagWeaponsVer == Bags.version then return bagWeapons end
    local out = {}
    Bags.Each(function(bag, slot, id)
        local _, _, sub, loc, icon, classId
        if GetItemInfoInstant then _, _, sub, loc, icon, classId = GetItemInfoInstant(id) end
        if classId ~= 2 or not D.WEAPON_SLOTS[loc] or not sub or not Takes(sub, D.SHARPEN_BAG) then return end
        local link = CC and CC.GetContainerItemLink and CC.GetContainerItemLink(bag, slot)
        if not link then return end
        out[#out + 1] = { bag = bag, slot = slot, link = link, itemId = id,
            name = (GetItemInfo and GetItemInfo(link)) or "Weapon", texture = icon or (GetItemIcon and GetItemIcon(id)) }
    end)
    bagWeapons, bagWeaponsVer = out, Bags.version
    return out
end

-- the global cooldown, eating, casting
function W.GCD()
    if not GetSpellCooldown then return 0, 0 end
    local s, d = GetSpellCooldown(ns.GCDSpell and ns.GCDSpell() or 61304)
    if ns.Hidden(s, d) then return 0, 0 end   -- (hidden on WoW Forever)
    if s and d and s > 0 and d > 0 then
        local r = s + d - GetTime()
        if r > 0 then return r, d end
    end
    return 0, 0
end
function W.Eating()
    if InCombatLockdown() then return false, 0 end
    local ids, names = BuffMaps()
    local now = GetTime()
    for _, sid in ipairs(D.EATING_IDS or { 24800, 18124 }) do
        local a = ids[sid]
        local exp = a and tonumber(a.expirationTime) or 0
        if exp > now then return true, exp - now end
    end
    -- (TBC / Forever: the eating aura by its name too)
    for _, n in ipairs(D.EATING_NAMES or {}) do
        local a = names[n]
        local exp = a and tonumber(a.expirationTime) or 0
        if exp > now then return true, exp - now end
    end
    return false, 0
end
function W.Cast()
    local name, _, _, s, e
    if UnitCastingInfo then name, _, _, s, e = UnitCastingInfo("player") end
    if not name and UnitChannelInfo then name, _, _, s, e = UnitChannelInfo("player") end
    -- (WoW Forever may hide cast times in combat: then no cast reading)
    if ns.IsSecret and (ns.IsSecret(name) or ns.IsSecret(s) or ns.IsSecret(e)) then return nil end
    if name and s and e then return name, s / 1000, e / 1000 end
end
function W.InCombat() return InCombatLockdown() end
function W.ItemName(id) return GetItemInfo and GetItemInfo(id) or nil end
function W.ItemIcon(id) return id and GetItemIcon and GetItemIcon(id) or nil end

-- ============================================================
-- STONES - the one a weapon button puts on
-- ============================================================
local function FirstOfKind(kind, w)
    for _, s in ipairs(D.STONES) do
        if s.poison == kind and w.Count(s.id) > 0 then return s.id end
    end
end
-- the pick if carried, else the best carried, else Elemental; a rogue's
-- hands keep a pick each (a poison that ran out falls to another rank)
function CB.ValidStone(slot, w)
    w = w or W
    local c = CB.Cfg()
    if (slot == "mainhand" or slot == "offhand") and IsRogue() then
        local pick = T(c, "stoneBySlot") and c.stoneBySlot[slot]
        if pick then
            if w.Count(pick) > 0 then return pick end
            local kind = D.POISON_KIND[pick]
            local alt = kind and FirstOfKind(kind, w)
            if alt then return alt end
        end
        if not pick or D.POISON_KIND[pick] then
            for _, kind in ipairs(D.SLOT_POISON_ORDER[slot]) do
                local id = FirstOfKind(kind, w)
                if id then return id end
            end
        end
    end
    local cur = c.stone or D.DEFAULT_STONE or 18262
    if w.Count(cur) > 0 then return cur end
    for _, s in ipairs(D.STONES) do if w.Count(s.id) > 0 then return s.id end end
    return D.DEFAULT_STONE or 18262
end
function CB.StoneName(id)
    if D.STONE_NAMES[id] then return D.STONE_NAMES[id] end
    local s = D.STONE_BY_ID[id]
    if s and s.poison then return s.name:gsub("^(%S+)", "%1 Poison") end
    return "Sharpening Stone"
end
function CB.ShortStone(id)
    if D.STONE_SHORT[id] then return D.STONE_SHORT[id] end
    local s = D.STONE_BY_ID[id]
    return s and s.name or "Stone"
end

-- ============================================================
-- WHEN A BAR SHOWS ("Show in", Readycheck's modes; the raid filter
-- narrows the raid modes to the ticked raids)
-- ============================================================
CB.RAIDS = { { "Molten Core", 409 }, { "Onyxia's Lair", 249 }, { "Blackwing Lair", 469 }, { "Zul'Gurub", 309 },
    { "Ruins of Ahn'Qiraj", 509 }, { "Temple of Ahn'Qiraj", 531 }, { "Naxxramas", 533 } }
CB.MODES = { { "always", "Always" }, { "group", "In a group" }, { "city", "In cities" },
    { "raids", "In raids" }, { "raids_and_city", "In raids and cities" } }
local function RaidName()
    if not (IsInInstance and GetInstanceInfo) then return nil end
    local inside, kind = IsInInstance()
    if not (inside and kind == "raid") then return nil end
    local name, _, _, _, _, _, _, iid = GetInstanceInfo()
    for _, r in ipairs(CB.RAIDS) do
        if r[2] == iid or r[1] == name then return r[1] end
    end
    return name
end
local function InRaid(filter)
    local inside, kind = false, nil
    if IsInInstance then inside, kind = IsInInstance() end
    if not (inside and kind == "raid") then return false end
    if type(filter) == "table" and next(filter) ~= nil then
        local n = RaidName()
        return (n and filter[n]) and true or false
    end
    return true
end
function CB.ShowIn(cfg)
    local mode = cfg.visibilityMode or "always"
    local raids = T(cfg, "visibilityRaids")
    if mode == "raids" or mode == "raids_only" then return InRaid(raids) end
    if mode == "group" then return (IsInGroup and IsInGroup()) and true or false end
    if mode == "city" then return (IsResting and IsResting()) and true or false end
    if mode == "raids_and_city" then return InRaid(raids) or ((IsResting and IsResting()) and true or false) end
    return true
end

-- ============================================================
-- WHICH BUTTONS - one bar's buttons, in order
-- ============================================================
-- entry: { id, data, count, category, hasBuff, rem, group, grouped,
--          hasConflictBuff, conflictTime, conflictItemId }
-- returns entries (only those to show), next (the soonest time a buff
-- crosses into its warning window: the bar is rebuilt then)
local function Weapon(id, slot, eq, stone, count, has, rem)
    return { id = id, count = count, category = "utilities", hasBuff = has, rem = rem or 0,
        data = { name = slot == "mainhand" and "Mainhand Stone" or "Offhand Stone", slot = slot,
            baseItemId = stone, unified = true, weaponTexture = eq and eq.texture } }
end
local function HandButtons(out, cfg, w, horde, hiddenMain, checkHidden)
    local hw = T(cfg, "hiddenWeapons")
    local mh = w.Equipped(16)
    if mh and not horde and not (checkHidden and hiddenMain[CB.MH]) and not (hw and mh.itemId and hw[mh.itemId])
        and mh.sharpenable then
        local stone = CB.ValidStone("mainhand", w)
        local has, rem = w.Enchant("mainhand")
        local n = w.Count(stone)
        if cfg.showOnlyAvailable ~= true or n > 0 or has then
            out[#out + 1] = Weapon(CB.MH, "mainhand", mh, stone, n, has, rem)
        end
    end
    local oh = w.Equipped(17)
    if oh and not (checkHidden and hiddenMain[CB.OH]) and not (hw and oh.itemId and hw[oh.itemId]) and oh.sharpenable then
        local stone = CB.ValidStone("offhand", w)
        local has, rem = w.Enchant("offhand")
        local n = w.Count(stone)
        if cfg.showOnlyAvailable ~= true or n > 0 or has then
            out[#out + 1] = Weapon(CB.OH, "offhand", oh, stone, n, has, rem)
        end
    end
end
local function BagWeaponButtons(out, cfg, w)
    local hw = T(cfg, "hiddenWeapons")
    local stone = CB.ValidStone(nil, w)
    local n = w.Count(stone)
    for _, wp in ipairs(w.BagWeapons()) do
        if not (hw and wp.itemId and hw[wp.itemId]) then
            local has, rem = w.BagEnchant(wp.bag, wp.slot)
            out[#out + 1] = { id = 900000 + wp.bag * 100 + wp.slot, count = n, category = "utilities",
                hasBuff = has, rem = rem or 0,
                data = { name = wp.name, slot = "bag", bag = wp.bag, bagSlot = wp.slot, weaponItemId = wp.itemId,
                    weaponLink = wp.link, weaponTexture = wp.texture, baseItemId = stone, bagWeapon = true } }
        end
    end
end

-- not a button of its own: the raw stones and oils (the hand buttons put
-- them on) and the old per-hand stone variants
local function NotAButton(id, it)
    return D.ENHANCE_RAW[id] or D.OILS[id] or D.STONE_VARIANT[id] or (it and it.noBar)
end
CB.NotAButton = NotAButton

-- every item a bar can carry, before the state rules
function CB.Catalogue(key, cfg)
    local out = {}
    for _, cat in ipairs(D.CATEGORY_KEYS) do
        for id, it in pairs(D.ITEMS[cat]) do
            local ok
            if key == "potions" then ok = D.POTION_BAR[id]
            else ok = not NotAButton(id, it) and not (D.POTION_BAR[id] and not D.BOTH_BARS[id]) end
            if ok then out[#out + 1] = { id = id, data = it, category = cat } end
        end
    end
    for id, it in pairs(T(cfg, "customItems") or {}) do
        id = tonumber(id) or id
        if type(it) == "table" and type(id) == "number" and not (key ~= "potions" and NotAButton(id)) then
            out[#out + 1] = { id = id, data = it, category = it.category or "custom", custom = true }
        end
    end
    return out
end

local function OrderLookup(cfg)
    local o, n = {}, 0
    for i, id in ipairs(T(cfg, "itemOrder") or {}) do o[id] = i n = i end
    return o, n > 0
end
local function SortKey(e)
    if e.id == CB.MH or e.id == CB.OH then return e.id end
    if IsBagWeaponId(e.id) then return 999903 end
    return e.data.baseItemId or e.id
end
CB.SortKey = SortKey

-- the grouped button's item: the pick when carried, else the first carried
local function Representative(g, cfg, w)
    local prio = D.PRIORITY[g]
    if not prio then return nil end
    local pref = T(cfg, "conflictGroupPreferences") and cfg.conflictGroupPreferences[g]
    if pref and w.Count(pref) > 0 then return pref end
    for _, id in ipairs(prio) do if w.Count(id) > 0 then return id end end
    return pref or prio[1]
end
CB.Representative = Representative

function CB.Collect(key, cfg, w)
    w = w or W
    cfg = cfg or CB.Bar(key)
    local out = {}
    local thr = tonumber(cfg.showBeforeExpiry) or 60
    local now = w.Now()
    if key == "weapons" then
        if cfg.showEquippedWeapons ~= false then HandButtons(out, cfg, w, CB.HordeMode(cfg), nil, false) end
        if cfg.showBagWeapons then BagWeaponButtons(out, cfg, w) end
        return out, nil
    end
    -- custom items' buffs are readable by id
    CB._custom = T(cfg, "customItems")
    local hidden = {}
    for _, e in ipairs(CB.Catalogue(key, cfg)) do
        if CB.Hidden(key, cfg, e.id) then hidden[e.id] = true end
    end
    if key == "main" then
        local hm = T(cfg, "hiddenItems") or {}
        HandButtons(out, cfg, w, CB.HordeMode(cfg), hm, true)
    end
    local groups, reps = {}, {}
    local onlyAvail = cfg.showOnlyAvailable == true
    for _, e in ipairs(CB.Catalogue(key, cfg)) do
        if not hidden[e.id] then
            local it = e.data
            local cid = it.baseItemId or e.id
            local n = w.Count(cid)
            local has, rem = w.Buff(it.buffId)
            if it.buffId == nil then
                has, rem = false, 0
                -- (TBC / Forever: a buff known only by its name)
                if it.buffName and w.NamedBuff then has, rem = w.NamedBuff(it.buffName, cid) end
            end
            local skip = (not has) and onlyAvail and n == 0
            if not skip then
                local show, skipGroup = false, false
                local g = (key == "main") and (not D.OWN_TIMER[cid]) and D.GROUP_OF[cid] or nil
                local mine = has and rem > 0 and rem <= thr
                if g then
                    local gs = groups[g]
                    if not gs then
                        local gh, gt, gi = w.GroupBuff(g)
                        gs = { has = gh, time = gt, id = gi, expiring = gh and gt > 0 and gt <= thr }
                        groups[g] = gs
                    end
                    if mine then
                        show = true
                    elseif gs.has and not gs.expiring then
                        if cfg.hideWhenActive and has then
                            show = false
                        else
                            show = not onlyAvail or n > 0 or has
                            if show and cfg.groupConflictButtons ~= false then
                                if reps[g] == nil then reps[g] = Representative(g, cfg, w) or false end
                                if cid ~= reps[g] then skipGroup = true end
                            end
                        end
                    else
                        show = not onlyAvail or n > 0 or has
                    end
                else
                    if cfg.hideWhenActive and has and rem > thr then show = false
                    else show = not onlyAvail or n > 0 or has end
                end
                if show and not skipGroup then
                    local gs = g and groups[g]
                    out[#out + 1] = { id = e.id, data = it, count = n, category = e.category, hasBuff = has, rem = rem,
                        group = g, grouped = (cfg.groupConflictButtons ~= false and g ~= nil) or nil,
                        hasConflictBuff = gs and gs.has or false, conflictTime = gs and gs.time or 0,
                        conflictItemId = gs and gs.id or nil, custom = e.custom }
                end
            end
        end
    end
    if key == "main" and cfg.showBagWeapons then BagWeaponButtons(out, cfg, w) end

    -- order: yours, then category, the clash groups ahead of loose items, name
    local order, hasOrder = OrderLookup(cfg)
    table.sort(out, function(a, b)
        local ak, bk = SortKey(a), SortKey(b)
        if hasOrder then
            local ao, bo = order[ak], order[bk]
            if ao and not bo then return true elseif bo and not ao then return false
            elseif ao and bo and ao ~= bo then return ao < bo end
        end
        if key == "potions" then
            if (a.data.name or "") ~= (b.data.name or "") then return (a.data.name or "") < (b.data.name or "") end
            return a.id < b.id
        end
        local ac, bc = D.CATEGORY_ORDER[a.category] or 99, D.CATEGORY_ORDER[b.category] or 99
        if ac ~= bc then return ac < bc end
        if a.group and not b.group then return true elseif b.group and not a.group then return false end
        if a.group and b.group then
            local ag, bg = D.GROUP_ORDER[a.group] or 99, D.GROUP_ORDER[b.group] or 99
            if ag ~= bg then return ag < bg end
        end
        local as, bs = a.data.slot or "none", b.data.slot or "none"
        if ak == bk then
            if as == "mainhand" and bs == "offhand" then return true end
            if as == "offhand" and bs == "mainhand" then return false end
        end
        if (a.data.name or "") ~= (b.data.name or "") then return (a.data.name or "") < (b.data.name or "") end
        return a.id < b.id
    end)

    -- the state rules: a buff with plenty left hides its button (and a
    -- rival's, when clashing buffs hide); the soonest crossing is kept
    local shown, nextCross = {}, nil
    for _, e in ipairs(out) do
        local vis = true
        if cfg.hideWhenActive and e.hasBuff and e.rem > thr then vis = false
        elseif key == "main" and cfg.hideConflictingBuffs and e.hasConflictBuff and e.conflictItemId ~= e.id
            and e.conflictTime > thr then vis = false end
        if vis then shown[#shown + 1] = e end
        if e.hasBuff and e.rem > thr then
            local t = now + e.rem - thr
            if not nextCross or t < nextCross then nextCross = t end
        end
        if e.hasConflictBuff and e.conflictTime > thr then
            local t = now + e.conflictTime - thr
            if not nextCross or t < nextCross then nextCross = t end
        end
    end
    CB._custom = nil
    return shown, nextCross
end

-- ============================================================
-- GRID - the index-th button's spot (x from the bar's left, y from its
-- top) and the bar's size for n buttons. DOWN fills rows of perRow,
-- RIGHT fills columns of perRow.
-- ============================================================
CB.PAD = 5
function CB.GridOffset(i, perRow, size, gap, grow)
    local row, col
    if grow == "DOWN" then row, col = math_floor((i - 1) / perRow), (i - 1) % perRow
    else col, row = math_floor((i - 1) / perRow), (i - 1) % perRow end
    return CB.PAD + col * (size + gap), -CB.PAD - row * (size + gap), row, col
end
function CB.BarSize(n, perRow, size, gap, grow)
    if n <= 0 then return 2 * CB.PAD + size, 2 * CB.PAD + size end
    local cols, rows
    if grow == "DOWN" then cols, rows = math_min(n, perRow), math.ceil(n / perRow)
    else cols, rows = math.ceil(n / perRow), math_min(n, perRow) end
    return 2 * CB.PAD + cols * size + (cols - 1) * gap, 2 * CB.PAD + rows * size + (rows - 1) * gap
end
function CB.Geo(cfg)
    local size = math_floor(tonumber(cfg.buttonSize) or 32)
    local per = math.max(1, math_floor(tonumber(cfg.buttonsPerRow) or 10))
    local gap = tonumber(cfg.iconSpacing) or 4
    local grow = (cfg.growDirection == "RIGHT") and "RIGHT" or "DOWN"
    return size, per, gap, grow
end

-- ============================================================
-- READYCHECK - is its twin of this bar on?
-- ============================================================
function CB.RC()
    local RC = _G.Readycheck
    if type(RC) == "table" and type(RC.db) == "table" then return RC end
end
local function Loaded(name)
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        local ok, r = pcall(C_AddOns.IsAddOnLoaded, name)
        if ok and r then return true end
    end
    if IsAddOnLoaded then
        local ok, r = pcall(IsAddOnLoaded, name)
        if ok and r then return true end
    end
    return false
end
-- true when Readycheck is running its own copy of this bar
function CB.ReadycheckBarOn(key)
    local RC = CB.RC()
    if not RC then return false end
    local ok, on = pcall(function()
        local d = RC.db[CB.RC_KEYS[key]]
        if not (type(d) == "table" and d.enabled) then return false end
        -- the bars live in Readycheck's consumables module
        return Loaded("Readycheck_Consumables") or (RC[CB.RC_KEYS[key]] and RC[CB.RC_KEYS[key]].frame ~= nil) or false
    end)
    return ok and on or false
end
