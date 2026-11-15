-- Win_Paperdoll - ZacUI's character sheet: your gear in two flat columns
-- and a weapon row, the 3D model between them with the five resistances
-- down its right edge, two stat cards you pick the contents of, and a
-- footer with average item level, durability and the helm / cloak toggles.
-- Part of ZacUI; load order is set by the TOC.
--
-- A Win_Kit cover over PaperDollFrame, laid over CharacterFrame's visible
-- rectangle (the same inset Win_Character's pages use), so it shows only
-- on the Character tab and the bottom tabs underneath stay live. C, the
-- micro button and Escape open and close it through Blizzard's own code.
--
-- RIGHT-CLICK NEEDS SECURE BUTTONS. Blizzard's slot uses the item on a
-- right-click, and UseInventoryItem is protected. So every slot is a
-- SecureActionButton whose right button runs "/use <slot>" - exactly the
-- call Blizzard's slot makes, and it works in combat. The price: those
-- buttons make CharacterFrame a protected frame, so this window is only
-- ever built, shown, hidden or moved out of combat, and its X is a secure
-- click on Blizzard's own close button (as in Win_Spellbook).
--
--   Left-click / drag     pick up, drop, swap, equip what the cursor holds
--                         (Blizzard's own slot, clicked securely: works in combat)
--   Right-click           use the item (trinkets, on-use gear)
--   Shift / Ctrl / Alt    handed to Blizzard's own slot, so linking,
--                         previewing and other addons' slot clicks
--                         (Readycheck's and ItemRack's Alt-click buttons) work
--   Model                 drag to rotate, wheel to zoom, drop an item to equip
--   Stat cards            the dropdown picks what each card shows

local ADDON_NAME = ...
-- Zacui_Windows is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end
-- Not on every game version (Core_Flavor's feature table: Retail's character sheet is its own; a Retail version comes later):
-- this window stands down here, before it makes a frame or a module.
if ns.FeatureOn and not ns.FeatureOn("win_character") then return end

-- shared state from earlier ZacUI files
local FLAT = ns.FLAT
local GetColor = ns.GetColor
local Kit = ns.Kit
local Modules = ns.Modules
local UI = ns.UI
local ZUI = ns.ZUI

local M, F = UI.M, UI.F

local floor, ceil, max, min, abs = math.floor, math.ceil, math.max, math.min, math.abs
local format = string.format

-- Layout. The cover is CharacterFrame's inset rectangle stopped above the
-- bottom tabs (341 x ~421 with Blizzard's tab art); everything below is
-- sized to fit inside it with room to spare above the footer.
local SLOT      = 36
local SLOT_GAP  = 4
local AMMO      = 28
local INFO_H    = 18
local COL_GAP   = 8     -- slot column -> middle column
local DD_H      = 20
local LINE_H    = 13
local CARD_ROWS = 6
local CARD_H    = 2 + DD_H + 3 + CARD_ROWS * LINE_H + 4

local LEFT_SLOTS  = { "HeadSlot", "NeckSlot", "ShoulderSlot", "BackSlot",
                      "ChestSlot", "ShirtSlot", "TabardSlot", "WristSlot" }
local RIGHT_SLOTS = { "HandsSlot", "WaistSlot", "LegsSlot", "FeetSlot",
                      "Finger0Slot", "Finger1Slot", "Trinket0Slot", "Trinket1Slot" }
local WEAPON_SLOTS = { "MainHandSlot", "SecondaryHandSlot", "RangedSlot" }

-- Shirt, tabard and ammo carry no item level worth a number.
local NO_ILVL = { [0] = true, [4] = true, [19] = true }
-- The average: every gear slot but shirt and tabard (17 on Era).
local AVG_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }
local MAINHAND, OFFHAND, RANGED = 16, 17, 18

-- Every modifier combination the secure clicks must ignore, so a shift /
-- ctrl / alt click goes to Blizzard's slot's modified branch instead of
-- using or picking up the item. Order matches SecureButton_GetModifierPrefix.
local MOD_PREFIXES = { "shift-", "ctrl-", "alt-", "ctrl-shift-", "alt-shift-",
                       "alt-ctrl-", "alt-ctrl-shift-" }

local win, mid, model, infoLevel, infoGuild
local ilvlText, durText, chipHelm, chipCloak
local slots = {}
local slotById = {}
local cards = {}
local pendingApply = false
local Leftovers   -- defined with Apply

local function Enabled()
    return ZacUIDB and ZacUIDB.modules and ZacUIDB.modules.paperdollwin ~= false
end

-- ============================================================
-- SMALL HELPERS
-- ============================================================
local GetInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo

local function G(name, fallback)
    local v = _G[name]
    if type(v) == "string" and v ~= "" then return v end
    return fallback
end

-- Blizzard's tooltip strings are format templates; a client whose copy
-- takes different arguments gets no line rather than a Lua error.
local function SafeFormat(fmt, ...)
    if type(fmt) ~= "string" then return nil end
    local ok, s = pcall(format, fmt, ...)
    if ok then return s end
    return nil
end

-- Palette colour as an inline escape, for the split "base +buff -debuff"
-- text inside tooltips.
local function Hex(key)
    local c = GetColor("text", key)
    return format("|cff%02x%02x%02x", floor(c.r * 255 + 0.5),
        floor(c.g * 255 + 0.5), floor(c.b * 255 + 0.5))
end

local function Pct(v) return format("%.2f%%", v or 0) end

-- Blizzard's rule for a stat's number: red if anything lowers it, green if
-- something raises it, plain otherwise.
local function BuffKey(pos, neg)
    if neg < 0 then return "red" end
    if pos > 0 then return "green" end
    return nil
end

-- PaperDollFormatStat's tooltip line, in palette colours:
-- "Strength 120 (100 +25 -5)".
local function SplitText(name, effective, base, pos, neg)
    local t = Hex("normal") .. (name or "") .. " " .. effective
    if pos == 0 and neg == 0 then return t .. "|r" end
    t = t .. " (" .. base .. "|r"
    if pos > 0 then t = t .. Hex("green") .. " +" .. pos .. "|r" end
    if neg < 0 then t = t .. Hex("red") .. " " .. neg .. "|r" end
    return t .. Hex("normal") .. ")|r"
end

local function ItemLevel(link)
    if not link then return nil end
    local detailed = (C_Item and C_Item.GetDetailedItemLevelInfo) or GetDetailedItemLevelInfo
    if detailed then
        local ok, lvl = pcall(detailed, link)
        if ok and type(lvl) == "number" and lvl > 0 then return lvl end
    end
    local lvl = select(4, GetInfo(link))
    if type(lvl) == "number" and lvl > 0 then return lvl end
    return nil
end

local function SlotQuality(id, link)
    if GetInventoryItemQuality then
        local q = GetInventoryItemQuality("player", id)
        if q then return q end
    end
    return link and select(3, GetInfo(link)) or nil
end

local function Durability(id)
    if not GetInventoryItemDurability then return nil end
    local cur, maxD = GetInventoryItemDurability(id)
    if cur and maxD and maxD > 0 then return cur, maxD end
    return nil
end

-- School names for the spell cards and resistances. Blizzard's own
-- DAMAGE_SCHOOLn strings (n = spell school index: 2 holy .. 7 arcane),
-- English if a client lacks them.
local SCHOOL_EN = { [2] = "Holy", [3] = "Fire", [4] = "Nature", [5] = "Frost",
                    [6] = "Shadow", [7] = "Arcane" }
local function SchoolName(i) return G("DAMAGE_SCHOOL" .. i, SCHOOL_EN[i]) end

local APM = ATTACK_POWER_MAGIC_NUMBER or 14

-- ============================================================
-- STAT LINES
-- ============================================================
-- Each category returns up to CARD_ROWS lines:
--   { label, value, key (value colour), title, body, lines = {...} }
-- The numbers and tooltip text follow Blizzard's PaperDollFrame_Set*
-- functions (Era's own file) wherever Era shows the stat at all; the
-- stats Era's sheet never showed get a short plain tooltip.
local NA = NOT_APPLICABLE or "N/A"

local function ArmorLine()
    local base, effectiveArmor, _, pos, neg = UnitArmor("player")
    base, pos, neg = base or 0, pos or 0, neg or 0
    local effective = max(0, base + pos + neg)
    local level = UnitLevel("player")
    local body
    if C_PaperDollInfo and C_PaperDollInfo.GetArmorEffectiveness then
        local ok, eff = pcall(C_PaperDollInfo.GetArmorEffectiveness, effectiveArmor or effective, level)
        if ok and eff then body = SafeFormat(ARMOR_TOOLTIP, level, eff * 100) end
    end
    local name = G("ARMOR", "Armor")
    return { label = name, value = tostring(effective), key = BuffKey(pos, neg),
             title = SplitText(name, effective, base, pos, neg), body = body }
end

local STAT_KEYS = { "STRENGTH", "AGILITY", "STAMINA", "INTELLECT", "SPIRIT" }
local STAT_EN = { "Strength", "Agility", "Stamina", "Intellect", "Spirit" }

local function BaseLines()
    local out = {}
    local _, classFile = UnitClass("player")
    for i = 1, 5 do
        local stat, effective, pos, neg = UnitStat("player", i)
        stat, effective, pos, neg = stat or 0, effective or 0, pos or 0, neg or 0
        local name = G("SPELL_STAT" .. i .. "_NAME", STAT_EN[i])
        -- Blizzard's own class line first ("Increases your Attack Power"),
        -- the generic one when the class has none.
        local body = _G[(classFile or "") .. "_" .. STAT_KEYS[i] .. "_TOOLTIP"]
            or _G["DEFAULT_" .. STAT_KEYS[i] .. "_TOOLTIP"]
        out[#out + 1] = {
            label = name, value = tostring(effective), key = BuffKey(pos, neg),
            title = SplitText(name, effective, stat - pos - neg, pos, neg),
            body = type(body) == "string" and body or nil,
        }
    end
    out[#out + 1] = ArmorLine()
    return out
end

local RESIST_ORDER = { 6, 2, 3, 4, 5 }   -- Blizzard's column: arcane, fire, nature, frost, shadow

-- One plain spell icon per resistance index, so the column takes the
-- same flat bordered square as a gear slot (Blizzard's own resistance
-- art carries a bevelled bronze frame that no crop removes). Read from
-- the spell where the client can, the icon file otherwise: Arcane
-- Explosion, Fire Ward, Nature Resistance Totem, Frost Ward, Shadow
-- Protection.
local SpellTexture = GetSpellTexture or (C_Spell and C_Spell.GetSpellTexture)
local RESIST_ICON = {
    [6] = { 1449,  "Interface\\Icons\\Spell_Nature_WispSplode" },
    [2] = { 543,   "Interface\\Icons\\Spell_Fire_FireArmor" },
    [3] = { 10595, "Interface\\Icons\\Spell_Nature_NatureResistanceTotem" },
    [4] = { 6143,  "Interface\\Icons\\Spell_Frost_FrostWard" },
    [5] = { 976,   "Interface\\Icons\\Spell_Shadow_AntiShadow" },
}
local function ResistIcon(id)
    local r = RESIST_ICON[id]
    return (SpellTexture and SpellTexture(r[1])) or r[2]
end

local function ResistLines()
    local out = {}
    local level = max(UnitLevel("player") or 1, 20)
    for _, id in ipairs(RESIST_ORDER) do
        local base, total, pos, neg = UnitResistance("player", id)
        base, total, pos, neg = base or 0, total or 0, pos or 0, neg or 0
        local key
        if abs(neg) > pos then key = "red" elseif abs(neg) < pos then key = "green" end
        local name = SchoolName(id + 1)
        local title = Hex("normal") .. G("RESISTANCE" .. id .. "_NAME", name) .. " " .. total .. "|r"
        if pos ~= 0 or neg ~= 0 then
            title = title .. Hex("normal") .. " ( " .. base .. "|r"
            if pos > 0 then title = title .. Hex("green") .. " +" .. pos .. "|r" end
            if neg < 0 then title = title .. Hex("red") .. " " .. neg .. "|r" end
            title = title .. Hex("normal") .. " )|r"
        end
        local ratio = total / level
        local grade
        if ratio > 5 then grade = RESISTANCE_EXCELLENT
        elseif ratio > 3.75 then grade = RESISTANCE_VERYGOOD
        elseif ratio > 2.5 then grade = RESISTANCE_GOOD
        elseif ratio > 1.25 then grade = RESISTANCE_FAIR
        elseif ratio > 0 then grade = RESISTANCE_POOR
        else grade = RESISTANCE_NONE end
        out[#out + 1] = {
            label = name, value = tostring(total), key = key, title = title,
            body = SafeFormat(RESISTANCE_TOOLTIP_SUBTEXT, _G["RESISTANCE_TYPE" .. id], level, grade),
        }
    end
    return out
end

-- Damage exactly as PaperDollFrame_SetDamage works it out: the displayed
-- range, and the base range plus buff annotations for the tooltip.
local function DamageRange(minD, maxD, pos, neg, percent)
    local displayMin, displayMax = max(floor(minD), 1), max(ceil(maxD), 1)
    if percent == 0 then
        minD, maxD = 0, 0
    else
        minD = (minD / percent) - pos - neg
        maxD = (maxD / percent) - pos - neg
    end
    local baseDamage = (minD + maxD) * 0.5
    local fullDamage = (baseDamage + pos + neg) * percent
    local bonus = fullDamage - baseDamage
    if bonus < 0.1 and bonus > -0.1 then bonus = 0 end
    local tip = max(floor(minD), 1) .. " - " .. max(ceil(maxD), 1)
    if bonus ~= 0 then
        if pos > 0 then tip = tip .. Hex("green") .. " +" .. pos .. "|r" end
        if neg < 0 then tip = tip .. Hex("red") .. " " .. neg .. "|r" end
        if percent > 1 then
            tip = tip .. Hex("green") .. " x" .. floor(percent * 100 + 0.5) .. "%|r"
        elseif percent < 1 then
            tip = tip .. Hex("red") .. " x" .. floor(percent * 100 + 0.5) .. "%|r"
        end
    end
    local sep = (displayMin < 100 and displayMax < 100) and " - " or "-"
    local key = (bonus > 0 and "green") or (bonus < 0 and "red") or nil
    return displayMin .. sep .. displayMax, key, tip, fullDamage
end

local function Dps(fullDamage, speed)
    if not speed or speed == 0 then return "--" end
    return format("%.1f", max(fullDamage, 1) / speed)
end

local function MeleeLines()
    local out = {}
    local skillBase, skillMod = UnitAttackBothHands("player")
    skillBase, skillMod = skillBase or 0, skillMod or 0
    out[#out + 1] = {
        label = "Weapon skill", value = tostring(skillBase + skillMod),
        key = (skillMod > 0 and "green") or (skillMod < 0 and "red") or nil,
        title = G("ATTACK_TOOLTIP", "Weapon skill"), body = G("ATTACK_TOOLTIP_SUBTEXT"),
    }

    local base, pos, neg = UnitAttackPower("player")
    base, pos, neg = base or 0, pos or 0, neg or 0
    local apName = G("MELEE_ATTACK_POWER", "Attack Power")
    out[#out + 1] = {
        label = "Attack power", value = tostring(max(0, base + pos + neg)), key = BuffKey(pos, neg),
        title = SplitText(apName, max(0, base + pos + neg), base, pos, neg),
        body = SafeFormat(MELEE_ATTACK_POWER_TOOLTIP, max(base + pos + neg, 0) / APM),
    }

    local speed, offSpeed = UnitAttackSpeed("player")
    local minD, maxD, minOff, maxOff, bPos, bNeg, percent = UnitDamage("player")
    minD, maxD, bPos, bNeg, percent = minD or 0, maxD or 0, bPos or 0, bNeg or 0, percent or 1
    local text, key, tip, full = DamageRange(minD, maxD, bPos, bNeg, percent)
    local lines = {
        { G("ATTACK_SPEED_COLON", "Speed:"), format("%.2f", speed or 0) },
        { G("DAMAGE_COLON", "Damage:"), tip },
        { G("DAMAGE_PER_SECOND", "Damage per second"), Dps(full, speed) },
    }
    if offSpeed then
        local _, _, offTip, offFull = DamageRange(minOff or 0, maxOff or 0, bPos, bNeg, percent)
        lines[#lines + 1] = { blank = true }
        lines[#lines + 1] = { header = G("INVTYPE_WEAPONOFFHAND", "Off Hand") }
        lines[#lines + 1] = { G("ATTACK_SPEED_COLON", "Speed:"), format("%.2f", offSpeed) }
        lines[#lines + 1] = { G("DAMAGE_COLON", "Damage:"), offTip }
        lines[#lines + 1] = { G("DAMAGE_PER_SECOND", "Damage per second"), Dps(offFull, offSpeed) }
    end
    out[#out + 1] = { label = G("DAMAGE", "Damage"), value = text, key = key,
                      title = G("INVTYPE_WEAPONMAINHAND", "Main Hand"), lines = lines }
    out[#out + 1] = {
        label = "Speed",
        value = offSpeed and format("%.2f / %.2f", speed or 0, offSpeed) or format("%.2f", speed or 0),
        title = "Attack speed", body = "Seconds between swings (main hand / off hand).",
    }
    if GetCritChance then
        out[#out + 1] = { label = "Crit chance", value = Pct(GetCritChance()),
                          title = "Melee critical strike chance",
                          body = "Chance for a melee attack to hit for double damage." }
    end
    if GetHitModifier then
        local hit = GetHitModifier() or 0
        out[#out + 1] = { label = "Hit bonus", value = "+" .. format("%.0f", hit) .. "%",
                          title = "Hit from gear and talents",
                          body = "Reduces your chance to miss with melee and ranged attacks." }
    end
    return out
end

local function RangedLines()
    local out = {}
    local hasRelic = UnitHasRelicSlot and UnitHasRelicSlot("player")
    local noRanged = hasRelic or not GetInventoryItemTexture("player", RANGED)
    local na = { value = NA, key = "gray" }
    local function Line(t) if noRanged then t.value, t.key, t.lines = na.value, na.key, nil end return t end

    local skillBase, skillMod = 0, 0
    if not noRanged then skillBase, skillMod = UnitRangedAttack("player") end
    skillBase, skillMod = skillBase or 0, skillMod or 0
    out[#out + 1] = Line({
        label = "Weapon skill", value = tostring(skillBase + skillMod),
        key = (skillMod > 0 and "green") or (skillMod < 0 and "red") or nil,
        title = G("RANGED_ATTACK_TOOLTIP", "Ranged weapon skill"), body = G("ATTACK_TOOLTIP_SUBTEXT"),
    })

    -- A wand's damage ignores attack power; Blizzard shows "--" for it.
    local ap
    if noRanged then
        ap = Line({ label = "Attack power", title = G("RANGED_ATTACK_POWER", "Ranged Attack Power") })
    elseif HasWandEquipped and HasWandEquipped() then
        ap = { label = "Attack power", value = "--", key = "gray", title = G("RANGED_ATTACK_POWER", "Ranged Attack Power"),
               body = "Wands are not affected by attack power." }
    else
        local base, pos, neg = UnitRangedAttackPower("player")
        base, pos, neg = base or 0, pos or 0, neg or 0
        ap = {
            label = "Attack power", value = tostring(max(0, base + pos + neg)), key = BuffKey(pos, neg),
            title = SplitText(G("RANGED_ATTACK_POWER", "Ranged Attack Power"), max(0, base + pos + neg), base, pos, neg),
            body = SafeFormat(RANGED_ATTACK_POWER_TOOLTIP, base / APM),
        }
    end
    out[#out + 1] = ap

    local speed, minD, maxD, pos, neg, percent = 0, 0, 0, 0, 0, 1
    if not noRanged then speed, minD, maxD, pos, neg, percent = UnitRangedDamage("player") end
    speed, minD, maxD, pos, neg, percent = speed or 0, minD or 0, maxD or 0, pos or 0, neg or 0, percent or 1
    local text, key, tip, full = DamageRange(minD, maxD, pos, neg, percent)
    out[#out + 1] = Line({
        label = G("DAMAGE", "Damage"), value = text, key = key, title = G("INVTYPE_RANGED", "Ranged"),
        lines = {
            { G("ATTACK_SPEED_COLON", "Speed:"), format("%.2f", speed) },
            { G("DAMAGE_COLON", "Damage:"), tip },
            { G("DAMAGE_PER_SECOND", "Damage per second"), Dps(full, speed) },
        },
    })
    out[#out + 1] = Line({ label = "Speed", value = format("%.2f", speed),
                           title = "Ranged attack speed", body = "Seconds between shots." })
    if GetRangedCritChance then
        out[#out + 1] = Line({ label = "Crit chance", value = Pct(GetRangedCritChance()),
                               title = "Ranged critical strike chance",
                               body = "Chance for a ranged attack to hit for double damage." })
    end
    return out
end

-- The lowest school's value, and every school for the tooltip (the TBC
-- sheet's own approach; Era's sheet has no spell section at all).
local function PerSchool(fn, fmt)
    local lowest, lines = nil, {}
    for i = 2, 7 do
        local v = fn(i) or 0
        if not lowest or v < lowest then lowest = v end
        lines[#lines + 1] = { SchoolName(i), fmt(v) }
    end
    return lowest or 0, lines
end

local function SpellLines()
    local out = {}
    if GetSpellBonusDamage then
        local low, lines = PerSchool(GetSpellBonusDamage, tostring)
        out[#out + 1] = { label = "Spell damage", value = tostring(low),
                          title = "Bonus spell damage", lines = lines }
    end
    if GetSpellBonusHealing then
        local heal = GetSpellBonusHealing() or 0
        out[#out + 1] = { label = "Healing", value = tostring(heal), title = "Bonus healing",
                          body = SafeFormat(BONUS_HEALING_TOOLTIP, heal)
                              or "Added to the healing done by your spells." }
    end
    if GetSpellCritChance then
        local low, lines = PerSchool(GetSpellCritChance, Pct)
        out[#out + 1] = { label = "Spell crit", value = Pct(low),
                          title = "Spell critical strike chance", lines = lines }
    end
    if GetManaRegen then
        -- Power type 0 is mana; a druid in a form still has the pool.
        if (UnitPowerMax("player", 0) or 0) > 0 then
            local base, casting = GetManaRegen()
            base, casting = floor((base or 0) * 5), floor((casting or 0) * 5)
            out[#out + 1] = {
                label = "Mana / 5 sec", value = base .. " / " .. casting, title = "Mana regeneration",
                body = format("%d mana every 5 seconds while not casting, %d while casting.", base, casting),
            }
        else
            out[#out + 1] = { label = "Mana / 5 sec", value = NA, key = "gray", title = "Mana regeneration" }
        end
    end
    if #out == 0 then
        out[1] = { label = "Not available", value = "", key = "gray", title = "Spell stats",
                   body = "This client does not report spell stats." }
    end
    return out
end

local function DefenseLines()
    local out = { ArmorLine() }
    if UnitDefense then
        local base, modifier = UnitDefense("player")
        base, modifier = base or 0, modifier or 0
        local pos, neg = max(modifier, 0), min(modifier, 0)
        local name = G("DEFENSE", "Defense")
        out[#out + 1] = {
            label = name, value = tostring(max(0, base + pos + neg)), key = BuffKey(pos, neg),
            title = SplitText(name, max(0, base + pos + neg), base, pos, neg),
            body = "Lowers the chance you are hit or critically hit, and raises your dodge, parry and block.",
        }
    end
    if GetDodgeChance then
        out[#out + 1] = { label = "Dodge", value = Pct(GetDodgeChance()), title = "Dodge chance",
                          body = "Chance to dodge a melee attack." }
    end
    if GetParryChance then
        out[#out + 1] = { label = "Parry", value = Pct(GetParryChance()), title = "Parry chance",
                          body = "Chance to parry a melee attack from the front." }
    end
    if GetBlockChance then
        local body = "Chance to block a melee attack with a shield."
        if GetShieldBlock then
            local amount = GetShieldBlock()
            if amount and amount > 0 then body = body .. " Your shield blocks " .. amount .. " damage." end
        end
        out[#out + 1] = { label = "Block", value = Pct(GetBlockChance()), title = "Block chance", body = body }
    end
    return out
end

local CATEGORIES = {
    { value = "base",    text = "Attributes",  fn = BaseLines },
    { value = "melee",   text = "Melee",       fn = MeleeLines },
    { value = "ranged",  text = "Ranged",      fn = RangedLines },
    { value = "spell",   text = "Spell",       fn = SpellLines },
    { value = "defense", text = "Defense",     fn = DefenseLines },
    { value = "resist",  text = "Resistances", fn = ResistLines },
}
local CATEGORY_BY = {}
for _, c in ipairs(CATEGORIES) do CATEGORY_BY[c.value] = c end

-- Remembered per character: a warrior and a mage on one account want
-- different cards. The default right card follows the class.
local CLASS_DEFAULT = {
    HUNTER = "ranged", MAGE = "spell", PRIEST = "spell", WARLOCK = "spell",
}
local function Category(side)
    local db = type(ZacUICharDB) == "table" and ZacUICharDB.paperdollStats
    local v = db and db[side]
    if v and CATEGORY_BY[v] then return v end
    if side == "left" then return "base" end
    local _, classFile = UnitClass("player")
    return CLASS_DEFAULT[classFile or ""] or "melee"
end

local function SetCategory(side, value)
    if not CATEGORY_BY[value] then return end
    if type(ZacUICharDB) == "table" then
        ZacUICharDB.paperdollStats = ZacUICharDB.paperdollStats or {}
        ZacUICharDB.paperdollStats[side] = value
    end
end

-- ============================================================
-- STAT CARDS
-- ============================================================
local function ShowStatTip(row)
    local spec = row.spec
    if not spec then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    local t = GetColor("tooltip", "title")
    local b = GetColor("tooltip", "body")
    local n = GetColor("text", "normal")
    GameTooltip:SetText(spec.title or spec.label or "", t.r, t.g, t.b)
    if spec.body then GameTooltip:AddLine(spec.body, b.r, b.g, b.b, true) end
    if spec.lines then
        for _, l in ipairs(spec.lines) do
            if l.blank then
                GameTooltip:AddLine(" ")
            elseif l.header then
                GameTooltip:AddLine(l.header, t.r, t.g, t.b)
            else
                GameTooltip:AddDoubleLine(l[1], l[2], b.r, b.g, b.b, n.r, n.g, n.b)
            end
        end
    end
    GameTooltip:Show()
end

local function FillCard(card)
    local cat = CATEGORY_BY[Category(card.side)]
    card.dd:SetText(cat.text)
    local lines
    if _G.ZACUI_MODERN then
        -- (WoW Forever and Retail can hand your stats back hidden - secret values, no
        -- maths on them: the card keeps what it last showed)
        local ok, r = pcall(cat.fn)
        if not ok then return end
        lines = r
    else
        lines = cat.fn()
    end
    for i, row in ipairs(card.rows) do
        local spec = lines[i]
        row.spec = spec
        if spec then
            row.label:SetText(spec.label or "")
            row.value:SetText(spec.value or "")
            -- Through the paint key, so a colour-editor repaint keeps it.
            row.value._zPaintKey = spec.key or "normal"
            row.value:_zPaint()
            row:Show()
            if GameTooltip:IsOwned(row) then ShowStatTip(row) end
        else
            row:Hide()
        end
    end
end

-- RESISTANCES, ALWAYS ON SHOW. Blizzard's sheet keeps the five schools
-- in a column down the model's right edge; here they could only be seen
-- by switching a stat card to "Resistances". Same place, in the house
-- style: Kit.Icon squares like the gear slots, the total where an icon
-- carries its count, the slot's hover wash, and the stat card's own
-- tooltip (ResistLines). A school you have none of is greyed out, so the
-- ones you do have are what the eye lands on. The cells are children of
-- the model so they draw above it.
local RESIST_SIZE, RESIST_GAP = 24, 3
local resistCells = {}

local function UpdateResists()
    if not resistCells[1] then return end
    local lines
    if _G.ZACUI_MODERN then
        -- (hidden resistances on the modern client: the cells keep what they showed)
        local ok, r = pcall(ResistLines)
        if not ok then return end
        for _, spec in ipairs(r) do if ns.IsSecret(spec.value) then return end end
        lines = r
    else
        lines = ResistLines()
    end
    for i, cell in ipairs(resistCells) do
        local spec = lines[i]
        cell.spec = spec
        local none = not spec or spec.value == "0"
        cell.count:SetText(spec and spec.value or "")
        cell.count._zPaintKey = (spec and spec.key) or (none and "gray") or "normal"
        cell.count:_zPaint()
        cell:SetDesaturated(none)
        if GameTooltip:IsOwned(cell) then ShowStatTip(cell) end
    end
end

local function ResistEnter(self)
    self.hover:Show()
    ShowStatTip(self)
end

local function ResistLeave(self)
    self.hover:Hide()
    GameTooltip:Hide()
end

local function BuildResists(parent)
    local n = #RESIST_ORDER
    local span = n * RESIST_SIZE + (n - 1) * RESIST_GAP
    for i, id in ipairs(RESIST_ORDER) do
        local cell = Kit.Icon(parent, RESIST_SIZE)
        -- centred on the model's height, 4px in from its right edge
        cell:SetPoint("TOPRIGHT", parent, "RIGHT", -4,
            span / 2 - (i - 1) * (RESIST_SIZE + RESIST_GAP))
        cell:SetIcon(ResistIcon(id))
        cell:EnableMouse(true)
        local hover = cell:CreateTexture(nil, "ARTWORK", nil, 6)
        hover._zui_own = true
        hover:SetPoint("TOPLEFT", 1, -1)
        hover:SetPoint("BOTTOMRIGHT", -1, 1)
        hover:SetColorTexture(1, 1, 1, 0.10)
        hover:SetBlendMode("ADD")
        hover:Hide()
        cell.hover = hover
        cell:SetScript("OnEnter", ResistEnter)
        cell:SetScript("OnLeave", ResistLeave)
        resistCells[i] = cell
    end
end

local function UpdateStats()
    for _, card in ipairs(cards) do FillCard(card) end
    UpdateResists()
end

local function BuildCard(side)
    local card = UI.Box(mid, "ui", "cardBg")
    card:SetHeight(CARD_H)
    card.side = side
    card.dd = UI.Dropdown(card, {
        width = 112,
        items = function() return CATEGORIES end,
        selectedValue = function() return Category(side) end,
        selected = function() return CATEGORY_BY[Category(side)].text end,
        onSelect = function(value)
            SetCategory(side, value)
            FillCard(card)
        end,
    })
    card.dd:SetHeight(DD_H)
    card.dd:SetPoint("TOPLEFT", card, "TOPLEFT", 2, -2)
    card.dd:SetPoint("TOPRIGHT", card, "TOPRIGHT", -2, -2)

    card.rows = {}
    for i = 1, CARD_ROWS do
        local row = CreateFrame("Frame", nil, card)
        local y = -(2 + DD_H + 3) - (i - 1) * LINE_H
        row:SetHeight(LINE_H)
        row:SetPoint("TOPLEFT", card, "TOPLEFT", 6, y)
        row:SetPoint("TOPRIGHT", card, "TOPRIGHT", -6, y)
        row:EnableMouse(true)
        -- Value sizes to its text on the right; the label takes what is
        -- left and truncates rather than running under the number.
        row.value = UI.Font(row, F.SMALL, { justify = "RIGHT" })
        row.value:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        row.value:SetWordWrap(false)
        row.label = UI.Font(row, F.SMALL, { justify = "LEFT", cat = "text", key = "gray" })
        row.label:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.label:SetPoint("RIGHT", row.value, "LEFT", -4, 0)
        row.label:SetWordWrap(false)
        row:SetScript("OnEnter", ShowStatTip)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        card.rows[i] = row
    end
    cards[#cards + 1] = card
    return card
end

-- ============================================================
-- GEAR SLOTS
-- ============================================================
local function UpdateCooldown(b)
    local cd = b.icon.cooldown
    if not cd then return end
    if not b.hasItem then cd:Hide() return end
    local start, duration, enable = GetInventoryItemCooldown("player", b.slotId)
    if ns.Hidden(start, duration, enable) then start, duration, enable = 0, 0, 0 end   -- (WoW Forever)
    if CooldownFrame_Set then
        CooldownFrame_Set(cd, start or 0, duration or 0, enable or 0)
    elseif start and duration and duration > 0 then
        cd:SetCooldown(start, duration)
    else
        cd:Hide()
    end
end

local function UpdateCursorTarget(b)
    local can = CursorCanGoInSlot(b.slotId) and true or false
    if can then
        local a = GetColor("ui", "accent")
        b.canGo:SetVertexColor(a.r, a.g, a.b, 0.30)
    end
    b.canGo:SetShown(can)
end

local function CountText(n)
    if not n or n <= 1 then return "" end
    if n >= 1000 then return format("%.1fk", n / 1000) end
    return tostring(n)
end

-- PaperDollItemSlotButton_Update, drawn our way: the item or the slot's
-- empty art, Blizzard's red tint when it is broken or unusable, the lock
-- desaturation while it is on the cursor, plus quality border, item level
-- and a wear strip Blizzard does not have.
local function UpdateSlot(b)
    local id = b.slotId
    local icon = b.icon
    local tex = GetInventoryItemTexture("player", id)
    if tex then
        local link = GetInventoryItemLink("player", id)
        b.hasItem = 1
        icon:SetIcon(tex)
        icon.count:SetText(CountText(GetInventoryItemCount("player", id)))
        local bad = GetInventoryItemBroken("player", id)
            or GetInventoryItemEquippedUnusable("player", id)
        icon:SetUsable(not bad)
        local q = SlotQuality(id, link)
        icon:SetQuality(q)
        if NO_ILVL[id] then
            b.ilvl:SetText("")
        else
            local lvl = ItemLevel(link)
            b.ilvl:SetText(lvl and tostring(lvl) or "")
            if q then b.ilvl:SetTextColor(ns.QualityRGB(q)) else b.ilvl:_zPaint() end
        end
        local cur, maxD = Durability(id)
        if cur and cur == 0 then
            b.wear:SetVertexColor(Kit.TextRGB("red"))
            b.wear:Show()
        elseif cur and cur / maxD <= 0.25 then
            b.wear:SetVertexColor(Kit.TextRGB("orange"))
            b.wear:Show()
        else
            b.wear:Hide()
        end
    else
        b.hasItem = nil
        local empty = b.emptyTex
        if b.checkRelic and UnitHasRelicSlot and UnitHasRelicSlot("player") then
            empty = "Interface\\Paperdoll\\UI-PaperDoll-Slot-Relic.blp"
        end
        icon:SetIcon(empty)
        icon.count:SetText("")
        icon:SetUsable(true)
        icon:SetQuality(nil)
        b.ilvl:SetText("")
        b.wear:Hide()
    end
    icon:SetDesaturated(IsInventoryItemLocked(id))
    UpdateCooldown(b)
    UpdateCursorTarget(b)
end

-- READYCHECK'S QUEUE, ON OUR SLOTS. A gear swap asked for in combat waits
-- for the fight to end, and Readycheck marks the slot it is headed for
-- with the incoming item's icon. It puts that marker on Blizzard's slot
-- buttons - which sit covered under this window, and whose markers are in
-- a higher strata, so they would show through at Blizzard's slot
-- positions instead of ours. So the same marker is drawn here, from the
-- slot -> icon map Readycheck keeps (GearManager.charSheetQueued), and
-- Readycheck's own are hidden while this sheet is up. Without Readycheck
-- there is no map and nothing is drawn.
local function QueueSource()
    local RC = _G.Readycheck
    local GM = RC and RC.GearManager
    if type(GM) ~= "table" then return nil, nil end
    return GM, type(GM.charSheetQueued) == "table" and GM.charSheetQueued or nil
end

local function UpdateQueueBadges()
    local _, map = QueueSource()
    for _, b in ipairs(slots) do
        local tex = map and map[b.slotId]
        if tex then
            b.queue:SetIcon(tex)
            b.queue:Show()
        else
            b.queue:Hide()
        end
        local blizz = _G["Character" .. b.slotName]
        local theirs = blizz and blizz.queueIndicator
        if type(theirs) == "table" and theirs.Hide then theirs:Hide() end
    end
end

-- Readycheck repaints its markers whenever its queue changes; follow it.
-- Hooked on first show rather than at load, so it does not matter which
-- addon loaded first.
local queueHooked = false
local function HookQueue()
    if queueHooked or not hooksecurefunc then return end
    local GM = QueueSource()
    if not GM or type(GM.UpdateCharacterSheetQueueIndicators) ~= "function" then return end
    queueHooked = true
    hooksecurefunc(GM, "UpdateCharacterSheetQueueIndicators", function()
        if win and win:IsVisible() then UpdateQueueBadges() end
    end)
end

local function UpdateAllSlots()
    for _, b in ipairs(slots) do UpdateSlot(b) end
end

-- PaperDollItemSlotButton_OnEnter: the item (or the slot's name), the
-- repair cost while the repair cursor is up, and the dress-up cursor.
local function SlotTooltip(self)
    self.hover:Show()
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local hasItem, _, repairCost = GameTooltip:SetInventoryItem("player", self.slotId, nil, true)
    if not hasItem then
        local text = _G[string.upper(self.slotName)]
        if self.checkRelic and UnitHasRelicSlot and UnitHasRelicSlot("player") then
            text = RELICSLOT
        end
        GameTooltip:SetText(text or self.slotName)
    end
    if InRepairMode() and repairCost and repairCost > 0 then
        GameTooltip:AddLine(REPAIR_COST, nil, nil, nil, true)
        GameTooltip_AddMoneyLine(GameTooltip, repairCost)
        GameTooltip:Show()
    else
        CursorUpdate(self)
    end
end

-- Readycheck's gear flyout (every item that fits this slot, click to swap)
-- hooks the OnEnter of Blizzard's own slot buttons - which sit faded under
-- this window and never see the mouse. So the slot here asks for it
-- itself, through the call Readycheck provides for exactly this. Readycheck
-- decides whether its menus are on; nothing happens if it is not loaded.
local function ReadycheckMenu(self)
    local RC = _G.Readycheck
    local GM = RC and RC.GearManager
    if type(GM) == "table" and type(GM.ShowCharSheetMenu) == "function" then
        pcall(GM.ShowCharSheetMenu, GM, self.slotId, self)
    end
end

local function SlotEnter(self)
    SlotTooltip(self)
    ReadycheckMenu(self)
end

local function SlotLeave(self)
    self.hover:Hide()
    GameTooltip:Hide()
    ResetCursor()
end

-- PaperDollItemSlotButton_OnClick's left button. Right-click is not here:
-- the secure "/use" attribute already ran for it.
local function SlotLeft(self)
    if MerchantFrame_ResetRefundItem then MerchantFrame_ResetRefundItem() end
    if GetCursorInfo() == "merchant" and MerchantFrame and MerchantFrame.extendedCost
        and MerchantFrame_ConfirmExtendedItemCost then
        MerchantFrame_ConfirmExtendedItemCost(MerchantFrame.extendedCost)
    else
        PickupInventoryItem(self.slotId)
        -- Blizzard's refund prompt reads :GetID() (the slot) and the
        -- parent's :GetID() (0, "equipped") off this button.
        if CursorHasItem() and MerchantFrame_SetRefundItem then
            MerchantFrame_SetRefundItem(self, 1)
        end
    end
end

-- A modified click goes to Blizzard's own slot, as a plain (insecure)
-- Click: its OnClick sees the modifier and takes the modified branch -
-- link, preview, and whatever other addons hook there (Readycheck's and
-- ItemRack's Alt-click buttons hook PaperDollItemSlotButton_OnModifiedClick
-- or the slot's OnClick). That branch picks nothing up, so it is fine in
-- combat. The secure actions are no-ops for every modifier (BuildSlot).
local function ModifiedClick(self, button)
    local blizz = self._zBlizz
    if blizz and blizz.Click then
        blizz:Click(button)
    else
        HandleModifiedItemClick(GetInventoryItemLink("player", self.slotId))
    end
end

-- Runs AFTER the secure action. The left button is normally Blizzard's
-- own slot, clicked securely (see BuildSlot), so there is nothing to do
-- here for it; this only covers a build without that slot, and there
-- PickupInventoryItem is refused in combat, so it waits for the fight to
-- end rather than throwing ADDON_ACTION_BLOCKED.
local function SlotClick(self, button)
    if IsModifiedClick() then
        ModifiedClick(self, button)
        return
    end
    if button == "LeftButton" then
        if self._zInsecureLeft and not InCombatLockdown() then
            SlotLeft(self)
        end
        return
    end
    -- Right button: the secure "/use" already ran.
    if MerchantFrame_ResetRefundItem then MerchantFrame_ResetRefundItem() end
end

-- One secure header for every slot's drag wrappers (see BuildSlot).
local dragHeader
local function DragHeader()
    if not dragHeader and SecureHandlerWrapScript then
        dragHeader = CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate")
    end
    return dragHeader
end

local function BuildSlot(slotName, size)
    local id, emptyTex, checkRelic = GetInventorySlotInfo(slotName)
    local b = CreateFrame("Button", nil, win, "SecureActionButtonTemplate")
    b:SetSize(size, size)
    b:SetID(id)
    b.slotId, b.slotName, b.emptyTex, b.checkRelic = id, slotName, emptyTex, checkRelic
    -- Released-click only, like Blizzard's slot, and on release whatever
    -- ActionButtonUseKeyDown says - a use on press would fire every time
    -- you start dragging the item off.
    b:SetAttribute("useOnKeyDown", false)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    -- The ammo slot has nothing to use; everything else right-clicks into
    -- the same UseInventoryItem Blizzard's slot calls ("/use 13").
    -- LEFT-CLICK IS BLIZZARD'S SLOT, CLICKED SECURELY. Picking up,
    -- dropping and swapping gear is PickupInventoryItem, which an addon
    -- may not call in combat - and weapon swaps mid-fight are exactly when
    -- it matters. A secure "click" runs Blizzard's own slot handler
    -- (CharacterMainHandSlot and friends: pick up / drop / swap, the
    -- merchant refund prompt, and shift / ctrl-click links and preview)
    -- with Blizzard's credentials. The slot is faded under the cover but
    -- still exists, and Click() does not care that it is invisible.
    local blizz = _G["Character" .. slotName]
    if blizz then
        b:SetAttribute("type1", "click")
        b:SetAttribute("clickbutton1", blizz)
        -- modified left-clicks are SlotClick's (ModifiedClick)
        for _, prefix in ipairs(MOD_PREFIXES) do
            b:SetAttribute(prefix .. "type1", ATTRIBUTE_NOOP or "")
        end
        b._zBlizz = blizz
    else
        b._zInsecureLeft = true
    end
    if id ~= 0 then
        b:SetAttribute("type2", "macro")
        b:SetAttribute("macrotext2", "/use " .. id)
        for _, prefix in ipairs(MOD_PREFIXES) do
            b:SetAttribute(prefix .. "type2", ATTRIBUTE_NOOP or "")
        end
    end
    -- The classifier never needs to look at a secure button of ours.
    if ZUI and ZUI.skinned then ZUI.skinned[b] = true end

    local icon = Kit.Icon(b, size, { cooldown = true })
    icon:SetAllPoints()
    b.icon = icon

    -- Everything below sits on the icon frame, which draws above the
    -- button's own layers.
    b.ilvl = UI.Font(icon, F.SMALL, { justify = "LEFT" })
    b.ilvl:SetPoint("TOPLEFT", icon, "TOPLEFT", 2, -2)

    -- Readycheck's "queued for this slot" marker (UpdateQueueBadges): the
    -- incoming item, small, in the corner the item level does not use.
    b.queue = Kit.Icon(icon, 14)
    b.queue:SetPoint("TOPRIGHT", icon, "TOPRIGHT", -1, -1)
    -- above the cooldown swipe, which is a sibling frame on the icon
    b.queue:SetFrameLevel(icon:GetFrameLevel() + 3)
    b.queue:Hide()

    local wear = icon:CreateTexture(nil, "OVERLAY", nil, 6)
    wear._zui_own = true
    wear:SetTexture(FLAT)
    wear:SetHeight(2)
    wear:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", 1, 1)
    wear:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -1, 1)
    wear:Hide()
    b.wear = wear

    -- "This item fits here": Blizzard lights the slot while the cursor
    -- holds something it can take.
    local canGo = icon:CreateTexture(nil, "ARTWORK", nil, 5)
    canGo._zui_own = true
    canGo:SetTexture(FLAT)
    canGo:SetPoint("TOPLEFT", 1, -1)
    canGo:SetPoint("BOTTOMRIGHT", -1, 1)
    canGo:Hide()
    b.canGo = canGo

    local hover = icon:CreateTexture(nil, "ARTWORK", nil, 6)
    hover._zui_own = true
    hover:SetPoint("TOPLEFT", 1, -1)
    hover:SetPoint("BOTTOMRIGHT", -1, 1)
    hover:SetColorTexture(1, 1, 1, 0.10)
    hover:SetBlendMode("ADD")
    hover:Hide()
    b.hover = hover

    b:SetScript("OnEnter", SlotEnter)
    b:SetScript("OnLeave", SlotLeave)
    -- The tooltip refresher runs several times a second; it redraws the
    -- tooltip only, it must not keep re-opening the flyout.
    b.UpdateTooltip = SlotTooltip
    b:HookScript("OnClick", SlotClick)
    -- Drags, securely: a secure-handler wrapper whose answer is "pick up
    -- inventory slot <id>" makes Blizzard's secure code do the
    -- PickupInventoryItem - the same call Blizzard's slot makes on a drag
    -- or a drop, and it works in combat.
    local header = DragHeader()
    if header then
        local body = [[ return "inventory", self:GetID() ]]
        SecureHandlerWrapScript(b, "OnDragStart", header, body)
        SecureHandlerWrapScript(b, "OnReceiveDrag", header, body)
    else
        local function Drag(self)
            if not InCombatLockdown() then SlotLeft(self) end
        end
        b:SetScript("OnDragStart", Drag)
        b:SetScript("OnReceiveDrag", Drag)
    end
    slots[#slots + 1] = b
    slotById[id] = b
    return b
end

-- ============================================================
-- MODEL
-- ============================================================
-- Rotation by dragging, like Model_OnUpdate, but the OnUpdate only lives
-- while the button is held.
local ROTATE = MODELFRAME_DRAG_ROTATION_CONSTANT or 0.010
local TWO_PI = 2 * math.pi

local function DragUpdate(self)
    local x = GetCursorPosition()
    local diff = (x - (self.dragX or x)) * ROTATE
    self.dragX = x
    self.rotation = self.rotation + diff
    if self.rotation < 0 then self.rotation = self.rotation + TWO_PI end
    if self.rotation > TWO_PI then self.rotation = self.rotation - TWO_PI end
    self:SetRotation(self.rotation)
end

local function StopDrag(self)
    self:SetScript("OnUpdate", nil)
    self.dragX = nil
end

-- FRAMING. Blizzard's character model is 233 x 300 - taller than wide -
-- and the unit camera is tuned for that shape. Ours sits between the gear
-- columns above the stat cards, so it is wider than it is tall, and at
-- Blizzard's camera distance the head or feet crop at the edges. The
-- camera is pulled back in proportion to how much squatter the frame is
-- (damped, so the character does not shrink to a figurine), and the wheel
-- can take it further out or in from there.
local BLIZZ_ASPECT = 300 / 233
local MAX_EXTRA = 0.8

local function FitCamera(m)
    if not m or not m.SetCamDistanceScale then return end
    local w, h = m:GetWidth(), m:GetHeight()
    local base = 1
    if w and h and w > 1 and h > 1 then
        local want = BLIZZ_ASPECT / (h / w)
        base = 1 + (want - 1) * 0.5
        if base < 1 then base = 1 elseif base > 1.8 then base = 1.8 end
    end
    m.camBase = base
    m:SetCamDistanceScale(base + (m.camExtra or 0))
end

local function UpdateModel()
    if not model then return end
    -- WoW Forever / Retail: Blizzard's own character-sheet scene and orbit
    -- camera (the one their paper doll uses) frames the whole character
    if model._zScene then
        pcall(ModelSceneUtil.SetUpCharacterSheetScene, model)
        return
    end
    model:SetUnit("player", false)
    model:SetRotation(model.rotation)
    if model.SetPortraitZoom then model:SetPortraitZoom(model.zoom) end
    -- SetUnit resets the camera, so the framing goes back on after it.
    FitCamera(model)
end

-- WoW Forever / Retail (2026-11-07, the head cut off): the modern client's
-- PlayerModel has no camera distance, so a wide, short stage crops the
-- head. Blizzard's paper doll there is a ModelScene on the character-sheet
-- scene; ours is the same: their template (drag to turn, wheel to zoom)
-- and their set-up call, on our own frame.
local function BuildScene(parent)
    if not (_G.ZACUI_MODERN and ModelSceneUtil and ModelSceneUtil.SetUpCharacterSheetScene) then return nil end
    local ok, m = pcall(CreateFrame, "ModelScene", nil, parent, "ModelSceneMixinTemplate")
    if not ok or not m then return nil end
    m:SetPoint("TOPLEFT", 1, -1)
    m:SetPoint("BOTTOMRIGHT", -1, 1)
    m._zScene = true
    -- an item on the cursor dropped on the model is put on, as on Blizzard's
    local function Equip()
        if CursorHasItem() and not InCombatLockdown() then AutoEquipCursorItem() end
    end
    m:HookScript("OnMouseUp", function(_, button) if button == "LeftButton" then Equip() end end)
    m:SetScript("OnReceiveDrag", Equip)
    return m
end

local function BuildModel(parent)
    local scene = BuildScene(parent)
    if scene then return scene end
    local m = CreateFrame("PlayerModel", nil, parent)
    m:SetPoint("TOPLEFT", 1, -1)
    m:SetPoint("BOTTOMRIGHT", -1, 1)
    m.rotation = MODELFRAME_DEFAULT_ROTATION or 0.61
    m.zoom = 0
    m.maxZoom = MODELFRAME_MAX_PLAYER_ZOOM or 0.8
    m:EnableMouse(true)
    m:EnableMouseWheel(true)
    m:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            self.dragX = GetCursorPosition()
            self:SetScript("OnUpdate", DragUpdate)
        end
    end)
    -- Blizzard's model equips whatever the cursor holds on any release
    -- over it, and on a drop.
    m:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then StopDrag(self) end
        -- AutoEquipCursorItem is refused to addons in combat; in a fight,
        -- drop the item on its slot instead (that path is secure).
        if CursorHasItem() and not InCombatLockdown() then AutoEquipCursorItem() end
    end)
    m:SetScript("OnReceiveDrag", function()
        if CursorHasItem() and not InCombatLockdown() then AutoEquipCursorItem() end
    end)
    -- Wheel up: first undo any zoom-out, then zoom in (Blizzard's portrait
    -- zoom). Wheel down: the reverse, then pull the camera further back.
    m.camExtra = 0
    m:SetScript("OnMouseWheel", function(self, delta)
        local step = MODELFRAME_ZOOM_STEP or 0.15
        if delta > 0 then
            if (self.camExtra or 0) > 0 then
                self.camExtra = max(0, self.camExtra - step)
            else
                self.zoom = min(self.maxZoom, self.zoom + step)
            end
        else
            if self.zoom > 0 then
                self.zoom = max(0, self.zoom - step)
            else
                self.camExtra = min(MAX_EXTRA, (self.camExtra or 0) + step)
            end
        end
        if self.SetPortraitZoom then self:SetPortraitZoom(self.zoom) end
        if self.SetCamDistanceScale then
            self:SetCamDistanceScale((self.camBase or 1) + self.camExtra)
        end
    end)
    m:SetScript("OnSizeChanged", FitCamera)
    -- WoW Forever (2026-11-07, the head cut off): the modern client loads
    -- the model after SetUnit returns and resets the camera when it lands,
    -- throwing away the framing set a moment before. It is put back once
    -- the model is in. Classic sets the model up at once, so nothing there.
    if _G.ZACUI_MODERN and m.HasScript and m:HasScript("OnModelLoaded") then
        m:SetScript("OnModelLoaded", function(self)
            self:SetRotation(self.rotation)
            if self.SetPortraitZoom then self:SetPortraitZoom(self.zoom) end
            FitCamera(self)
        end)
    end
    m:SetScript("OnHide", StopDrag)
    m:RegisterEvent("UI_SCALE_CHANGED")
    m:RegisterEvent("DISPLAY_SIZE_CHANGED")
    m:SetScript("OnEvent", function(self)
        if self.RefreshCamera then self:RefreshCamera() end
    end)
    return m
end

-- ============================================================
-- TITLE + FOOTER
-- ============================================================
local function UpdateTitle()
    win:SetTitle(UnitPVPName("player") or UnitName("player") or "")
    local className, classFile = UnitClass("player")
    local classText = Kit.ClassText(className, classFile)
    local level, race = UnitLevel("player"), UnitRace("player") or ""
    infoLevel:SetText(SafeFormat(PLAYER_LEVEL, level, race, classText)
        or ("Level " .. level .. " " .. race .. " " .. classText))
    local guildName, rankTitle = GetGuildInfo("player")
    if guildName then
        infoGuild:SetText(SafeFormat(GUILD_TITLE_TEMPLATE, rankTitle or "", guildName)
            or ((rankTitle or "") .. " of " .. guildName))
    else
        infoGuild:SetText("")
    end
end

local ilvlPending = false

local function AverageItemLevel()
    local total, pending = 0, false
    for _, id in ipairs(AVG_SLOTS) do
        local link = GetInventoryItemLink("player", id)
        if link then
            local lvl = ItemLevel(link)
            if lvl then total = total + lvl else pending = true end
        end
    end
    -- A two-hander leaves the off hand empty by design: count it twice,
    -- the way the modern client's own average does.
    local mh = GetInventoryItemLink("player", MAINHAND)
    if mh and not GetInventoryItemLink("player", OFFHAND)
        and select(9, GetInfo(mh)) == "INVTYPE_2HWEAPON" then
        total = total + (ItemLevel(mh) or 0)
    end
    return total / #AVG_SLOTS, pending
end

local function UpdateFooter()
    local avg, pending = AverageItemLevel()
    ilvlPending = pending
    ilvlText:SetText("Item level " .. format("%.1f", avg) .. (pending and "*" or ""))

    local sumCur, sumMax, lowest, broken = 0, 0, 1, false
    for id = 1, 18 do
        local cur, maxD = Durability(id)
        if cur then
            sumCur, sumMax = sumCur + cur, sumMax + maxD
            if cur / maxD < lowest then lowest = cur / maxD end
            if cur == 0 then broken = true end
        end
    end
    if sumMax > 0 then
        durText:SetText("Durability " .. floor(sumCur / sumMax * 100 + 0.5) .. "%")
        durText._zPaintKey = broken and "red" or (lowest <= 0.25 and "orange") or "normal"
    else
        durText:SetText("Durability --")
        durText._zPaintKey = "gray"
    end
    durText:_zPaint()

    if chipHelm and ShowingHelm then chipHelm:SetOn(ShowingHelm()) end
    if chipCloak and ShowingCloak then chipCloak:SetOn(ShowingCloak()) end
end

local function IlvlTooltip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    local t = GetColor("tooltip", "title")
    local b = GetColor("tooltip", "body")
    GameTooltip:AddLine("Average item level", t.r, t.g, t.b)
    GameTooltip:AddLine("Every gear slot except shirt and tabard. An empty slot counts as 0; "
        .. "a two-hander counts for both hands.", b.r, b.g, b.b, true)
    if ilvlPending then
        GameTooltip:AddLine("* Some item details are still loading.", b.r, b.g, b.b, true)
    end
    GameTooltip:Show()
end

local function DurabilityTooltip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    local t = GetColor("tooltip", "title")
    local body = GetColor("tooltip", "body")
    GameTooltip:AddLine("Durability", t.r, t.g, t.b)
    local any = false
    for id = 1, 18 do
        local cur, maxD = Durability(id)
        if cur and cur < maxD then
            any = true
            local link = GetInventoryItemLink("player", id)
            local b = slotById[id]
            local name = (link and GetInfo(link)) or (b and _G[string.upper(b.slotName)])
            local pct = cur / maxD
            local r, g, bl = Kit.TextRGB(cur == 0 and "red" or (pct <= 0.25 and "orange") or "normal")
            GameTooltip:AddDoubleLine(name or ("Slot " .. id), floor(pct * 100 + 0.5) .. "%",
                body.r, body.g, body.b, r, g, bl)
        end
    end
    if not any then GameTooltip:AddLine("Everything is fully repaired.", body.r, body.g, body.b, true) end
    GameTooltip:Show()
end

-- A mouse target over a footer text, for its tooltip.
local function HotSpot(parent, region, fn)
    local hot = CreateFrame("Frame", nil, parent)
    hot:SetAllPoints(region)
    hot:EnableMouse(true)
    hot:SetScript("OnEnter", fn)
    hot:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return hot
end

-- ============================================================
-- PLACEMENT + SILENCING (shared rules with Win_Character)
-- ============================================================
-- CharacterFrame's inset rectangle, stopped above the highest bottom tab
-- (Blizzard's art tabs are 32px and poke above the stock inset; the skin
-- flattens them to 22px). The same rule Win_Character's pages use, so the
-- tabs stay clickable on every page and the covers line up. The cover is
-- protected: out of combat only.
local function PlaceOverCharacter(f)
    local host = CharacterFrame
    local ins = ns.GetPanelInset("CharacterFrame", host)
    -- WoW Forever / Retail: their character frame is much taller than this
    -- page's slots, model and stats (an empty band under them), and its
    -- tabs are on the side: the page is exactly as tall as its content
    if f._zContentH then
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", host, "TOPLEFT", ins.l or 0, -(ins.t or 0))
        f:SetPoint("TOPRIGHT", host, "TOPRIGHT", -(ins.r or 0), -(ins.t or 0))
        f:SetHeight(f._zContentH)
        return
    end
    local bottom = ins.b or 0
    -- With ZacUI's tab strip on, Blizzard's tabs are faded out and the
    -- strip hangs below the panel line, so the page runs down to it.
    local tabsOn = ns.CharTabs and ns.CharTabs.Enabled and ns.CharTabs.Enabled()
    local base = (not tabsOn) and host:GetBottom()
    if base then
        for i = 1, 5 do
            local tab = _G["CharacterFrameTab" .. i]
            local top = tab and tab:IsShown() and tab:GetTop()
            if top then bottom = max(bottom, ceil(top - base) + 1) end
        end
    end
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", host, "TOPLEFT", ins.l or 0, -(ins.t or 0))
    f:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -(ins.r or 0), bottom)
end

-- Kit.Silence is written for frames: it also turns their mouse off, and
-- Unsilence turns it back ON - which on a plain texture (the portrait,
-- the page art) would make it start catching the mouse. Textures only
-- fade; frames go through the kit. Same field as the kit (and as
-- Win_Character), so either path can undo the other.
-- Kit.Silence fades textures and frames alike (a texture has no mouse
-- to take away), remembering each piece's own alpha and mouse state.
local Quiet, Unquiet = Kit.Silence, Kit.Unsilence


-- ============================================================
-- REFRESH (coalesced)
-- ============================================================
local dirty = {}
local queued = false

local function Flush()
    queued = false
    -- IsVisible, not IsShown: the cover is a shown child all session, and
    -- a sheet nobody is looking at is rebuilt in full by its OnShow.
    if not win or not win:IsVisible() then
        for k in pairs(dirty) do dirty[k] = nil end
        return
    end
    if dirty.title then UpdateTitle() end
    if dirty.slots then
        UpdateAllSlots()
    elseif dirty.cd then
        for _, b in ipairs(slots) do UpdateCooldown(b) end
    end
    if dirty.stats then UpdateStats() end
    if dirty.footer then UpdateFooter() end
    if dirty.model then UpdateModel() end
    for k in pairs(dirty) do dirty[k] = nil end
end

local function Mark(...)
    for i = 1, select("#", ...) do dirty[select(i, ...)] = true end
    if queued then return end
    queued = true
    C_Timer.After(0, Flush)
end

local function FullRefresh()
    if not win or not win:IsVisible() then return end
    UpdateTitle()
    UpdateAllSlots()
    HookQueue()
    UpdateQueueBadges()
    UpdateStats()
    UpdateFooter()
    UpdateModel()
end

local STAT_EVENTS = {
    UNIT_STATS = true, UNIT_RESISTANCES = true, UNIT_DAMAGE = true, UNIT_RANGEDDAMAGE = true,
    UNIT_ATTACK_SPEED = true, UNIT_ATTACK_POWER = true, UNIT_RANGED_ATTACK_POWER = true,
    UNIT_ATTACK = true, UNIT_DEFENSE = true, UNIT_AURA = true, UNIT_MAXPOWER = true,
    PLAYER_DAMAGE_DONE_MODS = true, SKILL_LINES_CHANGED = true,
}

local function OnEvent(_, event, _, arg2)
    if not win:IsVisible() then return end
    if event == "CURSOR_CHANGED" then
        for _, b in ipairs(slots) do UpdateCursorTarget(b) end
    elseif event == "BAG_UPDATE_COOLDOWN" then
        Mark("cd")
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        Mark("slots", "stats", "footer")
    elseif event == "UNIT_INVENTORY_CHANGED" or event == "UPDATE_INVENTORY_DURABILITY" then
        Mark("slots", "footer")
    elseif event == "UPDATE_INVENTORY_ALERTS" or event == "BAG_UPDATE_DELAYED" then
        Mark("slots")
    elseif event == "ITEM_LOCK_CHANGED" then
        -- Equipment locks come with no bag argument; bag locks are not ours.
        if arg2 == nil then Mark("slots") end
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        if ilvlPending then Mark("slots", "footer") end
    elseif event == "UNIT_MODEL_CHANGED" then
        Mark("model")
    elseif event == "UNIT_LEVEL" then
        Mark("title", "stats")
    elseif event == "PLAYER_GUILD_UPDATE" or event == "UNIT_NAME_UPDATE"
        or event == "PLAYER_PVP_RANK_CHANGED" then
        Mark("title")
    elseif STAT_EVENTS[event] then
        Mark("stats")
    end
end

local function RegisterEvents(ev)
    local function Reg(e) pcall(ev.RegisterEvent, ev, e) end
    local function RegUnit(e)
        if not pcall(ev.RegisterUnitEvent, ev, e, "player") then Reg(e) end
    end
    for _, e in ipairs({ "CURSOR_CHANGED", "BAG_UPDATE_COOLDOWN",
        "PLAYER_EQUIPMENT_CHANGED", "UPDATE_INVENTORY_DURABILITY", "UPDATE_INVENTORY_ALERTS",
        "BAG_UPDATE_DELAYED", "ITEM_LOCK_CHANGED", "GET_ITEM_INFO_RECEIVED",
        "PLAYER_GUILD_UPDATE", "PLAYER_PVP_RANK_CHANGED", "PLAYER_DAMAGE_DONE_MODS",
        "SKILL_LINES_CHANGED" }) do
        Reg(e)
    end
    for _, e in ipairs({ "UNIT_INVENTORY_CHANGED", "UNIT_MODEL_CHANGED", "UNIT_LEVEL",
        "UNIT_NAME_UPDATE", "UNIT_STATS", "UNIT_RESISTANCES", "UNIT_DAMAGE",
        "UNIT_RANGEDDAMAGE", "UNIT_ATTACK_SPEED", "UNIT_ATTACK_POWER",
        "UNIT_RANGED_ATTACK_POWER", "UNIT_ATTACK", "UNIT_DEFENSE", "UNIT_AURA",
        "UNIT_MAXPOWER" }) do
        RegUnit(e)
    end
end

-- ============================================================
-- BUILD
-- ============================================================
-- Only ever called out of combat (Apply checks): it creates and places
-- secure buttons.
local function Build()
    if win then return win end
    win = Kit.Cover(PaperDollFrame, {
        name = "ZacUIPaperdollWindow",
        title = UnitName("player") or (CHARACTER or "Character"),
        insetName = "CharacterFrame",
        onClose = function()
            if not InCombatLockdown() then HideUIPanel(CharacterFrame) end
        end,
    })
    if _G.ZACUI_MODERN then
        -- title, info line, the slot columns, a pad, the footer
        win._zContentH = M.TITLEBAR + 2 + INFO_H + 4 + 8 * SLOT + 7 * SLOT_GAP
            + Kit.PAD + Kit.FOOTER_H + 1
    end
    win.Reanchor = function() PlaceOverCharacter(win) end
    win.Reanchor()

    -- Level / race / class on the left, guild on the right, one line.
    local info = CreateFrame("Frame", nil, win)
    info:SetHeight(INFO_H)
    info:SetPoint("TOPLEFT", win, "TOPLEFT", Kit.PAD, -(M.TITLEBAR + 2))
    info:SetPoint("TOPRIGHT", win, "TOPRIGHT", -Kit.PAD, -(M.TITLEBAR + 2))
    infoLevel = UI.Font(info, F.LABEL, { justify = "LEFT" })
    infoLevel:SetPoint("LEFT", info, "LEFT", 0, 0)
    infoLevel:SetWordWrap(false)
    infoGuild = UI.Font(info, F.SMALL, { justify = "RIGHT", cat = "text", key = "gray" })
    infoGuild:SetPoint("RIGHT", info, "RIGHT", 0, 0)
    infoGuild:SetPoint("LEFT", infoLevel, "RIGHT", 10, 0)
    infoGuild:SetWordWrap(false)

    -- Two columns of eight, Blizzard's order, anchored straight to the
    -- cover (secure buttons are never re-anchored after this).
    local top = -(M.TITLEBAR + 2 + INFO_H + 4)
    local step = SLOT + SLOT_GAP
    for i, name in ipairs(LEFT_SLOTS) do
        local b = BuildSlot(name, SLOT)
        b:SetPoint("TOPLEFT", win, "TOPLEFT", Kit.PAD, top - (i - 1) * step)
    end
    for i, name in ipairs(RIGHT_SLOTS) do
        local b = BuildSlot(name, SLOT)
        b:SetPoint("TOPRIGHT", win, "TOPRIGHT", -Kit.PAD, top - (i - 1) * step)
    end

    -- Weapons + ammo, level with the last row and centred on the cover
    -- (the columns are symmetric, so that is the middle column's centre).
    local rowTop = top - 7 * step
    local rowW = 3 * SLOT + 2 * SLOT_GAP + 8 + AMMO
    local x = -rowW / 2
    for _, name in ipairs(WEAPON_SLOTS) do
        local b = BuildSlot(name, SLOT)
        b:SetPoint("TOP", win, "TOP", x + SLOT / 2, rowTop)
        x = x + SLOT + SLOT_GAP
    end
    local ammo = BuildSlot("AmmoSlot", AMMO)
    ammo:SetPoint("TOP", win, "TOP", x - SLOT_GAP + 8 + AMMO / 2, rowTop - (SLOT - AMMO) / 2)
    -- Relic classes have no ammo slot (not on Era, but Blizzard checks).
    if UnitHasRelicSlot and UnitHasRelicSlot("player") then ammo:Hide() end

    -- The middle column: model on top, the two stat cards above the
    -- weapon row.
    local side = Kit.PAD + SLOT + COL_GAP
    local zoneH = 8 * SLOT + 7 * SLOT_GAP
    mid = CreateFrame("Frame", nil, win)
    mid:SetPoint("TOPLEFT", win, "TOPLEFT", side, top)
    mid:SetPoint("TOPRIGHT", win, "TOPRIGHT", -side, top)
    mid:SetHeight(zoneH)

    local cardL = BuildCard("left")
    cardL:SetPoint("BOTTOMLEFT", mid, "BOTTOMLEFT", 0, SLOT + 6)
    cardL:SetPoint("BOTTOMRIGHT", mid, "BOTTOM", -2, SLOT + 6)
    local cardR = BuildCard("right")
    cardR:SetPoint("BOTTOMLEFT", mid, "BOTTOM", 2, SLOT + 6)
    cardR:SetPoint("BOTTOMRIGHT", mid, "BOTTOMRIGHT", 0, SLOT + 6)

    -- Four corners, not TOPLEFT+TOPRIGHT+BOTTOM: a BOTTOM anchor also pins
    -- the horizontal centre - onto the LEFT card's centre - and fights the
    -- two top corners.
    local stage = UI.Box(mid, "ui", "cardBg")
    stage:SetPoint("TOPLEFT", mid, "TOPLEFT", 0, 0)
    stage:SetPoint("TOPRIGHT", mid, "TOPRIGHT", 0, 0)
    stage:SetPoint("BOTTOMLEFT", cardL, "TOPLEFT", 0, 6)
    stage:SetPoint("BOTTOMRIGHT", cardR, "TOPRIGHT", 0, 6)
    model = BuildModel(stage)
    BuildResists(model)

    -- Footer: item level and durability on the left, toggles on the right.
    win.footer = Kit.Footer(win)
    ilvlText = UI.Font(win.footer, F.LABEL, { justify = "LEFT" })
    ilvlText:SetPoint("LEFT", win.footer, "LEFT", 8, 0)
    ilvlText:SetWordWrap(false)
    HotSpot(win.footer, ilvlText, IlvlTooltip)

    if ShowCloak and ShowingCloak then
        chipCloak = Kit.Chip(win.footer, "Cloak", ShowingCloak(), function(on)
            ShowCloak(on and true or false)
        end, "Show your cloak on your character.")
        chipCloak:SetPoint("RIGHT", win.footer, "RIGHT", -6, 0)
    end
    if ShowHelm and ShowingHelm then
        chipHelm = Kit.Chip(win.footer, "Helm", ShowingHelm(), function(on)
            ShowHelm(on and true or false)
        end, "Show your helm on your character.")
        if chipCloak then
            chipHelm:SetPoint("RIGHT", chipCloak, "LEFT", -4, 0)
        else
            chipHelm:SetPoint("RIGHT", win.footer, "RIGHT", -6, 0)
        end
    end

    durText = UI.Font(win.footer, F.LABEL, { justify = "LEFT" })
    durText:SetPoint("LEFT", ilvlText, "RIGHT", 14, 0)
    local leftmost = chipHelm or chipCloak
    if leftmost then durText:SetPoint("RIGHT", leftmost, "LEFT", -6, 0) end
    durText:SetWordWrap(false)
    HotSpot(win.footer, durText, DurabilityTooltip)

    -- THE X, SECURELY. The slot buttons make CharacterFrame protected, so
    -- an addon's HideUIPanel on it is refused in combat. A secure "click"
    -- on Blizzard's own close button runs their handler instead.
    local blizzClose = _G.CharacterFrameCloseButton
    if blizzClose then
        local sx = CreateFrame("Button", nil, win.titleBar, "SecureActionButtonTemplate")
        sx:SetAllPoints(win.closeButton)
        sx:SetFrameLevel(win.closeButton:GetFrameLevel() + 2)
        sx:SetAttribute("useOnKeyDown", false)
        sx:RegisterForClicks("AnyUp")
        sx:SetAttribute("type", "click")
        sx:SetAttribute("clickbutton", blizzClose)
        local xb = win.closeButton
        sx:SetScript("OnEnter", function() xb._zHot = true; xb:_zPaint() end)
        sx:SetScript("OnLeave", function() xb._zHot = nil; xb:_zPaint() end)
        xb:EnableMouse(false)
        if ZUI and ZUI.skinned then ZUI.skinned[sx] = true end
    end

    local ev = CreateFrame("Frame", nil, win)
    RegisterEvents(ev)
    ev:SetScript("OnEvent", OnEvent)

    -- Forever's modern page parts (slots, level line, pane chrome): hushed
    -- by name with the cover, hushed again when Blizzard rebuilds the page
    Kit.CharacterCover(win, "paperdoll")

    -- Blizzard pieces around the cover are silenced only while this page
    -- is up, so the other Character tabs (their own covers, or Blizzard's
    -- skinned pages) get them back.
    win:HookScript("OnShow", function()
        Quiet(Leftovers())
        FullRefresh()
        -- The skin flattens the tabs in a timer of its own; stop right
        -- above the new row a frame later (never in combat: protected).
        C_Timer.After(0, function()
            if win:IsVisible() and not InCombatLockdown() then win.Reanchor() end
        end)
    end)
    win:HookScript("OnHide", function()
        Unquiet(Leftovers())
        for _, card in ipairs(cards) do card.dd.Close() end
        ResetCursor()
    end)
    return win
end

-- What of Blizzard's hangs outside the cover or would show around it:
-- the portrait (top-left, past the inset), the close button's corner,
-- PaperDollFrame's own art (its frame edges ring the cover when the
-- character skin is off) and CharacterModelFrame (under the cover, but a
-- second model rendering for nobody). Never the bottom tabs. The shared
-- CharacterFrame pieces are the same list Win_Character's pages silence,
-- so a tab switch hands them from one cover to the next.
function Leftovers()
    local t = {}
    local function Add(f) if f then t[#t + 1] = f end end
    -- (on the modern client the window's own chrome - close button,
    -- portrait, frame art, title bar - is Kit.CharacterCover's, quietened
    -- in a side table with the other parts, never with fields on them)
    if not _G.ZACUI_MODERN then
        Add(_G.CharacterFrameCloseButton)
        Add(_G.CharacterFramePortrait)
        if CharacterFrame then
            Add(CharacterFrame.PortraitContainer)
            Add(CharacterFrame.NineSlice)
            -- Forever's (modern) CharacterFrame has a title bar at frame level
            -- 510 that draws over the cover ("Zac Warrior" twice); Classic's has none
            Add(CharacterFrame.TitleContainer)
        end
    end
    Add(_G.CharacterModelFrame)
    if PaperDollFrame then
        for _, r in ipairs({ PaperDollFrame:GetRegions() }) do
            if r.IsObjectType and r:IsObjectType("Texture") and not r._zui_own then Add(r) end
        end
    end
    -- (Forever's modern paperdoll - the item slots at frame level 100, the
    -- level line, the pane divider and toggle - is Kit.CharacterCover's:
    -- quietened by name, never hidden, hushed again whenever Blizzard
    -- rebuilds the page under the cover)
    return t
end

local function Apply()
    if not PaperDollFrame or not CharacterFrame then return end
    -- The cover holds secure buttons: build, show and hide wait for the
    -- fight to end.
    if InCombatLockdown() then
        pendingApply = true
        return
    end
    pendingApply = false
    if Enabled() then
        Build()
        win.Reanchor()
        win:Show()
        if win:IsVisible() then
            Quiet(Leftovers())
            FullRefresh()
        end
    elseif win then
        win:Hide()
        Unquiet(Leftovers())
    end
end

-- ============================================================
-- MODULE
-- ============================================================
Modules.paperdollwin = function()
    if not PaperDollFrame or not CharacterFrame or ns._zPaperdollWin then return end
    ns._zPaperdollWin = true
    -- A later /zui toggle only flips the saved flag; the page checks it on
    -- every open (out of combat) so turning it off never needs a reload.
    PaperDollFrame:HookScript("OnShow", function()
        if not InCombatLockdown() then Apply() end
    end)
    -- Built at login rather than on first open, so a first C press in
    -- combat still finds the sheet. A login in combat builds on the way out.
    local watch = CreateFrame("Frame")
    watch:RegisterEvent("PLAYER_REGEN_ENABLED")
    watch:SetScript("OnEvent", function()
        if pendingApply then Apply() end
    end)
    Apply()
end
