-- Win_PetPaperdoll - ZacUI's Pet tab: your beast or demon's name, level
-- and family, a model you can turn and zoom, and for a hunter's pet its
-- happiness, loyalty, experience and training points, then the same
-- stats and resistances Blizzard's pet sheet shows.
-- Part of ZacUI; load order is set by the TOC.
--
-- A Win_Kit cover over PetPaperDollFrame, laid over CharacterFrame's
-- visible rectangle stopped above the bottom tabs (the rule Win_Paperdoll
-- and Win_Character use), so it shows only while the Pet tab is the
-- active page and the tabs underneath stay live. The Pet tab, its key
-- binding, the micro button and Escape all open and close it through
-- Blizzard's own code, and Blizzard's own PetPaperDollFrame_OnEvent still
-- sends you back to the Character tab when the pet goes away for good.
--
-- THE NUMBERS ARE BLIZZARD'S. Every value and tooltip follows Era's
-- PetPaperDollFrame_Update and the PaperDollFrame_Set* calls it makes for
-- "pet" - including the 1.12 rule that a pet's attributes and armor show
-- no buff split (Blizzard's own comment: UnitStat / UnitArmor never
-- reported one for a unit that is not you). Happiness mirrors the pet
-- unit frame's icon and tooltip; the diet line is the pet sheet's own.
--
-- THE X IS SECURE, SO THE COVER IS PROTECTED. CharacterFrame is a
-- protected frame (Win_Paperdoll's secure slots), so an addon's
-- HideUIPanel on it is refused in combat. The X is a secure "click" on
-- Blizzard's CharacterFrameCloseButton, which makes this cover protected
-- too: it is built, shown, hidden and re-anchored only out of combat.
-- Everything inside is a plain frame and updates live in a fight.
--
--   Model        drag to rotate, wheel to zoom
--   Happiness    hover for the damage modifier, loyalty trend and diet
--   Stats        hover any line for Blizzard's tooltip

local ADDON_NAME = ...
-- Zacui_Windows is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end
-- Not on every game version (Core_Flavor's feature table: Retail's pet page is the stable; a Retail version comes later):
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

local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min
local format = string.format

-- Layout. The cover is CharacterFrame's inset rectangle stopped above the
-- bottom tabs (341 x ~421 with Blizzard's tab art). Built bottom-up:
-- resistances, the two stat cards, the hunter status card, and the model
-- takes whatever height is left.
local INFO_H    = 18
local GAP       = 6
local LINE_H    = 13
local CARD_ROWS = 5
local CARD_HEAD = 18
local CARD_H    = CARD_HEAD + CARD_ROWS * LINE_H + 6
local STATUS_H  = 44
local RESIST_H  = 28

local win, body, stage, model, status, resist, emptyText
local infoLevel, infoLoyal
local happyIcon, happyText, dmgText, happyHot, tpLabel, tpValue, xpBar
local cards = {}
local resistCells = {}
local pendingApply = false
local lastHas, lastHunter
local Leftovers   -- defined with Apply

local function Enabled()
    return ZacUIDB and ZacUIDB.modules and ZacUIDB.modules.petpaperdollwin ~= false
end

-- ============================================================
-- SMALL HELPERS
-- ============================================================
local function G(name, fallback)
    local v = _G[name]
    if type(v) == "string" and v ~= "" then return v end
    return fallback
end

-- Blizzard's labels carry a colon ("Attack:"); our rows do not. Handles
-- the full-width colon of the Asian clients too.
local function Label(name, fallback)
    local s = G(name, fallback) or ""
    s = (s:gsub("%s*:%s*$", ""))
    s = (s:gsub("\239\188\154%s*$", ""))
    return s
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

-- PaperDollFormatStat's colour rule: red if anything lowers it, green if
-- something raises it, plain otherwise.
local function BuffKey(pos, neg)
    if neg < 0 then return "red" end
    if pos > 0 then return "green" end
    return nil
end

-- PaperDollFormatStat's tooltip line, in palette colours:
-- "Attack Power 120 (100 +25 -5)".
local function SplitText(name, effective, base, pos, neg)
    local t = Hex("normal") .. (name or "") .. " " .. effective
    if pos == 0 and neg == 0 then return t .. "|r" end
    t = t .. " (" .. base .. "|r"
    if pos > 0 then t = t .. Hex("green") .. " +" .. pos .. "|r" end
    if neg < 0 then t = t .. Hex("red") .. " " .. neg .. "|r" end
    return t .. Hex("normal") .. ")|r"
end

local APM = ATTACK_POWER_MAGIC_NUMBER or 14

-- A pet to show: Blizzard's own test (HasPetUI) plus a live unit, so a
-- dead or dismissed pet reads "No pet summoned" instead of stale numbers.
-- The second value is HasPetUI's "hunter pet" flag (the pet sheet calls
-- it canGainXP): happiness, loyalty, XP and training points are hunter-only.
local function PetState()
    local hasUI, isHunter
    if HasPetUI then hasUI, isHunter = HasPetUI() end
    local has = (hasUI and UnitExists("pet")) and true or false
    return has, (has and isHunter) and true or false
end

-- ============================================================
-- STAT LINES
-- ============================================================
-- Each returns { label, value, key (value colour), title, body, lines }.
-- Straight from Era's PetPaperDollFrame_SetStats and the PaperDollFrame_Set*
-- functions it calls with "pet".
local STAT_KEYS = { "STRENGTH", "AGILITY", "STAMINA", "INTELLECT", "SPIRIT" }
local STAT_EN = { "Strength", "Agility", "Stamina", "Intellect", "Spirit" }

local function AttributeLines()
    local out = {}
    local _, classFile = UnitClass("pet")
    for i = 1, 5 do
        local _, effective = UnitStat("pet", i)
        effective = effective or 0
        local name = G("SPELL_STAT" .. i .. "_NAME", STAT_EN[i])
        -- The pet's class line first, the generic one when it has none.
        local body = classFile and _G[string.upper(classFile) .. "_" .. STAT_KEYS[i] .. "_TOOLTIP"]
        if type(body) ~= "string" then body = _G["DEFAULT_" .. STAT_KEYS[i] .. "_TOOLTIP"] end
        -- 1.12 rule: no buff split for a pet, so no colour either.
        out[i] = {
            label = name, value = tostring(effective),
            title = Hex("normal") .. name .. " " .. effective .. "|r",
            body = type(body) == "string" and body or nil,
        }
    end
    return out
end

-- PaperDollFrame_SetDamage's numbers: the displayed range, and the base
-- range plus buff annotations for the tooltip.
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
    if not speed or speed == 0 then return format("%.1f", 0) end
    return format("%.1f", max(fullDamage, 1) / speed)
end

local function CombatLines()
    local out = {}

    -- Attack (PaperDollFrame_SetAttackBothHands); the pet sheet's own
    -- tooltip is just ATTACK_TOOLTIP, no sub-text.
    local base, mod = UnitAttackBothHands("pet")
    base, mod = base or 0, mod or 0
    out[#out + 1] = {
        label = Label("ATTACK_COLON", "Attack"), value = tostring(base + mod),
        key = (mod > 0 and "green") or (mod < 0 and "red") or nil,
        title = G("ATTACK_TOOLTIP", "Attack"),
    }

    local apBase, apPos, apNeg = UnitAttackPower("pet")
    apBase, apPos, apNeg = apBase or 0, apPos or 0, apNeg or 0
    local ap = max(0, apBase + apPos + apNeg)
    out[#out + 1] = {
        label = Label("ATTACK_POWER_COLON", "Attack Power"), value = tostring(ap),
        key = BuffKey(apPos, apNeg),
        title = SplitText(G("MELEE_ATTACK_POWER", "Attack Power"), ap, apBase, apPos, apNeg),
        body = SafeFormat(MELEE_ATTACK_POWER_TOOLTIP, max(apBase + apPos + apNeg, 0) / APM),
    }

    -- Damage, with CharacterDamageFrame_OnEnter's tooltip.
    local speed, offSpeed = UnitAttackSpeed("pet")
    local minD, maxD, minOff, maxOff, bPos, bNeg, percent = UnitDamage("pet")
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
    out[#out + 1] = { label = Label("DAMAGE_COLON", "Damage"), value = text, key = key,
                      title = G("INVTYPE_WEAPONMAINHAND", "Main Hand"), lines = lines }

    -- Defense (PaperDollFrame_SetDefense); the pet sheet's tooltip is
    -- DEFENSE_TOOLTIP alone.
    if UnitDefense then
        local dBase, modifier = UnitDefense("pet")
        dBase, modifier = dBase or 0, modifier or 0
        local pos, neg = max(modifier, 0), min(modifier, 0)
        out[#out + 1] = {
            label = Label("DEFENSE_COLON", "Defense"), value = tostring(max(0, dBase + pos + neg)),
            key = BuffKey(pos, neg), title = G("DEFENSE_TOOLTIP", "Defense"),
        }
    end

    -- Armor (PaperDollFrame_SetArmor): for a pet the effective value is
    -- shown as the base with no buffs, and the tooltip gives the damage
    -- reduction at the pet's level.
    local _, effectiveArmor = UnitArmor("pet")
    effectiveArmor = effectiveArmor or 0
    local armor = max(0, effectiveArmor)
    local level = UnitLevel("pet") or 1
    local armorBody
    if C_PaperDollInfo and C_PaperDollInfo.GetArmorEffectiveness then
        local ok, eff = pcall(C_PaperDollInfo.GetArmorEffectiveness, effectiveArmor, level)
        if ok and eff then armorBody = SafeFormat(ARMOR_TOOLTIP, level, eff * 100) end
    end
    local armorName = G("ARMOR", "Armor")
    out[#out + 1] = {
        label = Label("ARMOR_COLON", armorName), value = tostring(armor),
        title = Hex("normal") .. armorName .. " " .. armor .. "|r", body = armorBody,
    }
    return out
end

-- Blizzard's pet resistance column: resistance index (the frame IDs) and
-- the row of Blizzard's resistance icon strip each one uses.
local RESISTS = {
    { id = 6, t = 0.2265625,  b = 0.33984375, en = "Arcane Resistance" },
    { id = 2, t = 0,          b = 0.11328125, en = "Fire Resistance" },
    { id = 3, t = 0.11328125, b = 0.2265625,  en = "Nature Resistance" },
    { id = 4, t = 0.33984375, b = 0.453125,   en = "Frost Resistance" },
    { id = 5, t = 0.453125,   b = 0.56640625, en = "Shadow Resistance" },
}
local RESIST_TEX = "Interface\\PaperDollInfoFrame\\UI-Character-ResistanceIcons"

-- PetPaperDollFrame_SetResistances: red below zero, green above, the
-- name plus the base / buff formula as the tooltip.
local function ResistSpec(r)
    local base, total, pos, neg = UnitResistance("pet", r.id)
    base, total, pos, neg = base or 0, total or 0, pos or 0, neg or 0
    local key
    if total < 0 then key = "red" elseif total > 0 then key = "green" end
    local title = Hex("normal") .. G("RESISTANCE" .. r.id .. "_NAME", r.en) .. "|r"
    if pos ~= 0 or neg ~= 0 then
        title = title .. Hex("normal") .. " ( " .. base .. "|r"
        if pos > 0 then title = title .. Hex("green") .. " +" .. pos .. "|r" end
        if neg < 0 then title = title .. Hex("red") .. " " .. neg .. "|r" end
        title = title .. Hex("normal") .. " )|r"
    end
    return { value = tostring(total), key = key, title = title }
end

-- ============================================================
-- STAT CARDS + RESISTANCES
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

local function SetValue(fs, text, key)
    fs:SetText(text or "")
    -- Through the paint key, so a colour-editor repaint keeps it.
    fs._zPaintKey = key or "normal"
    fs:_zPaint()
end

local function FillCard(card)
    local lines
    if _G.ZACUI_MODERN then
        -- (WoW Forever and Retail can hand the pet's stats back hidden: the card keeps
        -- what it last showed)
        local ok, r = pcall(card.fn)
        if not ok then return end
        lines = r
    else
        lines = card.fn()
    end
    for i, row in ipairs(card.rows) do
        local spec = lines[i]
        row.spec = spec
        if spec then
            row.label:SetText(spec.label or "")
            SetValue(row.value, spec.value, spec.key)
            row:Show()
            if GameTooltip:IsOwned(row) then ShowStatTip(row) end
        else
            row:Hide()
        end
    end
end

local function UpdateStats()
    for _, card in ipairs(cards) do FillCard(card) end
    for i, cell in ipairs(resistCells) do
        local spec = ResistSpec(RESISTS[i])
        cell.spec = spec
        SetValue(cell.value, spec.value, spec.key)
        if GameTooltip:IsOwned(cell) then ShowStatTip(cell) end
    end
end

local function BuildCard(parent, title, fn)
    local card = UI.Box(parent, "ui", "cardBg")
    card:SetHeight(CARD_H)
    card.fn = fn
    local head = UI.Font(card, F.LABEL, { text = title, cat = "text", key = "gold", justify = "LEFT" })
    head:SetPoint("TOPLEFT", card, "TOPLEFT", 6, -4)
    head:SetPoint("TOPRIGHT", card, "TOPRIGHT", -6, -4)
    head:SetWordWrap(false)
    card.rows = {}
    for i = 1, CARD_ROWS do
        local row = CreateFrame("Frame", nil, card)
        local y = -CARD_HEAD - (i - 1) * LINE_H
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

-- Five equal cells across the strip, icon then number, laid out from the
-- strip's measured width.
local function BuildResist(parent)
    local strip = UI.Box(parent, "ui", "cardBg")
    strip:SetHeight(RESIST_H)
    for i, r in ipairs(RESISTS) do
        local cell = CreateFrame("Frame", nil, strip)
        cell:SetHeight(RESIST_H - 2)
        cell:EnableMouse(true)
        local icon = cell:CreateTexture(nil, "ARTWORK")
        icon._zui_own = true
        icon:SetSize(22, 20)
        icon:SetPoint("LEFT", cell, "LEFT", 6, 0)
        icon:SetTexture(RESIST_TEX)
        icon:SetTexCoord(0, 1, r.t, r.b)
        cell.value = UI.Font(cell, F.LABEL, { justify = "LEFT" })
        cell.value:SetPoint("LEFT", icon, "RIGHT", 4, 0)
        cell.value:SetPoint("RIGHT", cell, "RIGHT", -2, 0)
        cell.value:SetWordWrap(false)
        cell:SetScript("OnEnter", ShowStatTip)
        cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
        resistCells[i] = cell
    end
    local function Layout()
        local w = (strip:GetWidth() or 0) - 2
        if w <= 0 then return end
        local cw = floor(w / #resistCells)
        for i, cell in ipairs(resistCells) do
            cell:ClearAllPoints()
            cell:SetPoint("LEFT", strip, "LEFT", 1 + (i - 1) * cw, 0)
            cell:SetWidth(cw)
        end
    end
    strip:SetScript("OnSizeChanged", Layout)
    Layout()
    return strip
end

-- ============================================================
-- HUNTER STATUS: happiness, training points, experience
-- ============================================================
-- The pet unit frame's happiness art: Blizzard's icon sheet and the
-- coordinates PetFrameMixin:SetHappiness uses (1 unhappy .. 3 happy).
local HAPPY_TEX = "Interface\\PetPaperDollFrame\\UI-PetHappiness"
local HAPPY = {
    [1] = { l = 0.375,  r = 0.5625, key = "red",    en = "Unhappy" },
    [2] = { l = 0.1875, r = 0.375,  key = "orange", en = "Content" },
    [3] = { l = 0,      r = 0.1875, key = "green",  en = "Happy" },
}

-- A flat bar: our own fill over our own box. No StatusBar art.
local function FlatBar(parent, height)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(height)
    UI.Fill(f, "ui", "elementBg")
    UI.Border(f, "ui", "border")
    f._zPaint = UI.PaintBox
    f:_zPaint()
    local b = CreateFrame("StatusBar", nil, f)
    b:SetPoint("TOPLEFT", 1, -1)
    b:SetPoint("BOTTOMRIGHT", -1, 1)
    b:SetStatusBarTexture(FLAT)
    local t = b:GetStatusBarTexture()
    if t then t._zui_own = true end
    b:SetMinMaxValues(0, 1)
    b:SetValue(0)
    b:SetFrameLevel(f:GetFrameLevel() + 1)
    f.bar = b
    -- The text sits on its own frame above the fill.
    local over = CreateFrame("Frame", nil, f)
    over:SetAllPoints()
    over:SetFrameLevel(f:GetFrameLevel() + 3)
    f.text = UI.Font(over, F.SMALL, { justify = "CENTER" })
    f.text:SetPoint("CENTER", over, "CENTER", 0, 0)
    f.text:SetWordWrap(false)
    function f:Set(value, maxV)
        if not maxV or maxV <= 0 then maxV = 1 end
        self.bar:SetMinMaxValues(0, maxV)
        self.bar:SetValue(max(0, min(value or 0, maxV)))
        local c = GetColor("text", "blue")
        self.bar:SetStatusBarColor(c.r, c.g, c.b, 1)
    end
    return f
end

-- PetFrameHappiness's tooltip (happiness, damage modifier, loyalty trend)
-- with the pet sheet's diet line (PetPaperDollPetInfo) below it. Read
-- live on every hover, so it is never stale.
local function HappyEnter(self)
    local happiness, damagePercentage, loyaltyRate
    if GetPetHappiness then happiness, damagePercentage, loyaltyRate = GetPetHappiness() end
    local spec = happiness and HAPPY[happiness]
    if not spec then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local t = GetColor("tooltip", "title")
    local b = GetColor("tooltip", "body")
    GameTooltip:SetText(G("PET_HAPPINESS" .. happiness, spec.en), t.r, t.g, t.b)
    local dmg = damagePercentage and SafeFormat(PET_DAMAGE_PERCENTAGE, damagePercentage)
    if dmg then GameTooltip:AddLine(dmg, b.r, b.g, b.b, true) end
    loyaltyRate = loyaltyRate or 0
    if loyaltyRate < 0 then
        GameTooltip:AddLine(G("LOSING_LOYALTY", "Losing loyalty"), b.r, b.g, b.b, true)
    elseif loyaltyRate > 0 then
        GameTooltip:AddLine(G("GAINING_LOYALTY", "Gaining loyalty"), b.r, b.g, b.b, true)
    end
    if GetPetFoodTypes and BuildListString then
        local foods = BuildListString(GetPetFoodTypes())
        local diet = foods and SafeFormat(PET_DIET_TEMPLATE, foods)
        if diet then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(diet, b.r, b.g, b.b, true)
        end
    end
    GameTooltip:Show()
end

local function UpdateStatus()
    local happiness, damagePercentage
    if GetPetHappiness then happiness, damagePercentage = GetPetHappiness() end
    local spec = happiness and HAPPY[happiness]
    if spec then
        happyIcon:SetTexCoord(spec.l, spec.r, 0, 0.359375)
        happyIcon:Show()
        SetValue(happyText, G("PET_HAPPINESS" .. happiness, spec.en), spec.key)
        dmgText:SetText(damagePercentage and (G("DAMAGE", "Damage") .. " " .. damagePercentage .. "%") or "")
    else
        happyIcon:Hide()
        happyText:SetText("")
        dmgText:SetText("")
    end
    if GameTooltip:IsOwned(happyHot) then
        if spec then HappyEnter(happyHot) else GameTooltip:Hide() end
    end

    -- PetPaperDollFrame_Update: unspent = total - spent.
    if GetPetTrainingPoints then
        local totalPoints, spent = GetPetTrainingPoints()
        tpValue:SetText(tostring((totalPoints or 0) - (spent or 0)))
        tpLabel:SetText(Label("TRAINING_POINTS", "Training Points"))
    else
        tpValue:SetText("")
        tpLabel:SetText("")
    end

    -- PetExpBar_Update: no bar when there is nothing to the next level.
    local currXP, nextXP = 0, 0
    if GetPetExperience then currXP, nextXP = GetPetExperience() end
    currXP, nextXP = currXP or 0, nextXP or 0
    if nextXP == 0 then
        xpBar:Hide()
    else
        xpBar:Set(currXP, nextXP)
        xpBar.text:SetText(G("XP", "XP") .. " " .. currXP .. " / " .. nextXP)
        xpBar:Show()
    end
end

-- ============================================================
-- MODEL
-- ============================================================
-- Rotation by dragging, like Model_OnUpdate, but the OnUpdate only lives
-- while the button is held. Zoom by wheel, like Model_OnMouseWheel.
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

local function UpdateModel()
    if not model then return end
    if UnitExists("pet") then
        model:SetUnit("pet")
        model:SetRotation(model.rotation)
        if model.SetPortraitZoom then model:SetPortraitZoom(model.zoom) end
    elseif model.ClearModel then
        model:ClearModel()
    end
end

local function BuildModel(parent)
    local m = CreateFrame("PlayerModel", nil, parent)
    m:SetPoint("TOPLEFT", 1, -1)
    m:SetPoint("BOTTOMRIGHT", -1, 1)
    m.rotation = MODELFRAME_DEFAULT_ROTATION or 0.61
    m.zoom = 0
    -- The pet sheet's model uses the player zoom limit (Model_OnLoad).
    m.maxZoom = MODELFRAME_MAX_PLAYER_ZOOM or 0.8
    m:EnableMouse(true)
    m:EnableMouseWheel(true)
    m:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            self.dragX = GetCursorPosition()
            self:SetScript("OnUpdate", DragUpdate)
        end
    end)
    m:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then StopDrag(self) end
    end)
    m:SetScript("OnMouseWheel", function(self, delta)
        self.zoom = max(0, min(self.maxZoom, self.zoom + delta * (MODELFRAME_ZOOM_STEP or 0.15)))
        if self.SetPortraitZoom then self:SetPortraitZoom(self.zoom) end
    end)
    -- WoW Forever: the modern client loads the model after SetUnit and
    -- resets the camera then; the framing goes back on once it is in
    if _G.ZACUI_MODERN and m.HasScript and m:HasScript("OnModelLoaded") then
        m:SetScript("OnModelLoaded", function(self)
            self:SetRotation(self.rotation)
            if self.SetPortraitZoom then self:SetPortraitZoom(self.zoom) end
        end)
    end
    m:SetScript("OnHide", StopDrag)
    -- What PetModelFrame does on a UI scale / resolution change.
    m:RegisterEvent("UI_SCALE_CHANGED")
    m:RegisterEvent("DISPLAY_SIZE_CHANGED")
    m:SetScript("OnEvent", function(self)
        if not UnitExists("pet") then return end
        if self.RefreshUnit then self:RefreshUnit()
        elseif self.RefreshCamera then self:RefreshCamera() end
    end)
    return m
end

-- ============================================================
-- TITLE + STATE
-- ============================================================
local function UpdateTitle(has, hunter)
    if not has then
        win:SetTitle(G("PET", "Pet"))
        infoLevel:SetText("")
        infoLoyal:SetText("")
        return
    end
    win:SetTitle(UnitName("pet") or G("PET", "Pet"))
    -- PetLevelText: "Level 60" plus the family ("Cat", "Imp").
    local level = UnitLevel("pet") or 0
    local text = SafeFormat(UNIT_LEVEL_TEMPLATE, level) or ("Level " .. level)
    local family = UnitCreatureFamily("pet")
    if family then text = text .. " " .. family end
    infoLevel:SetText(text)
    local loyalty = hunter and GetPetLoyalty and GetPetLoyalty()
    infoLoyal:SetText(type(loyalty) == "string" and loyalty or "")
end

-- Pet / no pet, hunter / not: which parts show, and where the model's
-- bottom edge sits. Plain frames only, so this is safe in combat.
local function ApplyState(has, hunter)
    if has == lastHas and hunter == lastHunter then return end
    lastHas, lastHunter = has, hunter
    body:SetShown(has)
    emptyText:SetShown(not has)
    status:SetShown(hunter)
    -- Four corners, not TOPLEFT/TOPRIGHT + BOTTOM: without the status card
    -- the edge below is two half-width cards, and a BOTTOM point on the
    -- left card's centre would fight the left/right edges.
    stage:ClearAllPoints()
    stage:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
    stage:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, 0)
    stage:SetPoint("BOTTOMLEFT", hunter and status or cards[1], "TOPLEFT", 0, GAP)
    stage:SetPoint("BOTTOMRIGHT", hunter and status or cards[2], "TOPRIGHT", 0, GAP)
end

-- ============================================================
-- PLACEMENT + SILENCING (shared rules with Win_Paperdoll / Win_Character)
-- ============================================================
-- CharacterFrame's inset rectangle, stopped above the highest bottom tab
-- (Blizzard's art tabs are 32px and poke above the stock inset; the skin
-- flattens them to 22px). The cover is protected: out of combat only.
local function PlaceOverCharacter(f)
    local host = CharacterFrame
    local ins = ns.GetPanelInset("CharacterFrame", host)
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
-- Win_Paperdoll / Win_Character), so either path can undo the other.
-- Kit.Silence fades textures and frames alike (a texture has no mouse
-- to take away), remembering each piece's own alpha and mouse state.
local Quiet, Unquiet = Kit.Silence, Kit.Unsilence


-- ============================================================
-- REFRESH (coalesced)
-- ============================================================
local dirty = {}
local queued = false

local function FullRefresh()
    if not win or not win:IsVisible() then return end
    local has, hunter = PetState()
    ApplyState(has, hunter)
    UpdateTitle(has, hunter)
    if has then
        if hunter then UpdateStatus() end
        UpdateStats()
    end
    UpdateModel()
end

local function Flush()
    queued = false
    -- IsVisible, not IsShown: the cover is a shown child all session, and
    -- a page nobody is looking at is redrawn in full by its OnShow.
    if not win or not win:IsVisible() then
        for k in pairs(dirty) do dirty[k] = nil end
        return
    end
    local has, hunter = PetState()
    if dirty.all or has ~= lastHas or hunter ~= lastHunter then
        FullRefresh()
    elseif has then
        if dirty.title then UpdateTitle(has, hunter) end
        if dirty.status and hunter then UpdateStatus() end
        if dirty.stats then UpdateStats() end
        if dirty.model then UpdateModel() end
    end
    for k in pairs(dirty) do dirty[k] = nil end
end

local function Mark(...)
    for i = 1, select("#", ...) do dirty[select(i, ...)] = true end
    if queued then return end
    queued = true
    C_Timer.After(0, Flush)
end

-- The pet sheet's own event list (PetPaperDollFrame_OnLoad) plus
-- UNIT_HAPPINESS (the pet frame's) and UNIT_AURA / UNIT_NAME_UPDATE.
local STAT_EVENTS = {
    UNIT_STATS = true, UNIT_RESISTANCES = true, UNIT_DAMAGE = true, UNIT_RANGEDDAMAGE = true,
    UNIT_ATTACK_SPEED = true, UNIT_ATTACK_POWER = true, UNIT_RANGED_ATTACK_POWER = true,
    UNIT_ATTACK = true, UNIT_DEFENSE = true, UNIT_AURA = true,
}
local PET_UNIT_EVENTS = {
    "UNIT_MODEL_CHANGED", "UNIT_LEVEL", "UNIT_NAME_UPDATE", "UNIT_STATS",
    "UNIT_RESISTANCES", "UNIT_DAMAGE", "UNIT_RANGEDDAMAGE", "UNIT_ATTACK_SPEED",
    "UNIT_ATTACK_POWER", "UNIT_RANGED_ATTACK_POWER", "UNIT_DEFENSE", "UNIT_ATTACK",
    "UNIT_AURA",
}

local function OnEvent(_, event, arg1)
    if not win:IsVisible() then return end
    if event == "UNIT_PET" then
        if arg1 == "player" then Mark("all") end
    elseif event == "PET_UI_UPDATE" or event == "PET_BAR_UPDATE" or event == "PET_UI_CLOSE" then
        Mark("all")
    elseif event == "UNIT_HAPPINESS" or event == "UNIT_PET_EXPERIENCE"
        or event == "UNIT_PET_TRAINING_POINTS" then
        Mark("status")
    -- Everything below is a pet unit event: filtered to "pet" by
    -- RegisterUnitEvent, and checked again in case that fell back.
    elseif arg1 ~= "pet" then
        return
    elseif event == "UNIT_MODEL_CHANGED" then
        Mark("model")
    elseif event == "UNIT_LEVEL" then
        Mark("title", "stats", "status")
    elseif event == "UNIT_NAME_UPDATE" then
        Mark("title")
    elseif STAT_EVENTS[event] then
        Mark("stats")
    end
end

local function RegisterEvents(ev)
    local function Reg(e) pcall(ev.RegisterEvent, ev, e) end
    -- UNIT_PET is the player's; the pet ones filter to the pet unit.
    local function RegUnit(e, unit)
        if not pcall(ev.RegisterUnitEvent, ev, e, unit) then Reg(e) end
    end
    RegUnit("UNIT_PET", "player")
    -- Rare, and their unit argument is not documented: registered plain.
    for _, e in ipairs({ "PET_UI_UPDATE", "PET_BAR_UPDATE", "PET_UI_CLOSE",
        "UNIT_HAPPINESS", "UNIT_PET_EXPERIENCE", "UNIT_PET_TRAINING_POINTS" }) do
        Reg(e)
    end
    for _, e in ipairs(PET_UNIT_EVENTS) do RegUnit(e, "pet") end
end

-- ============================================================
-- BUILD
-- ============================================================
-- Only ever called out of combat (Apply checks): it creates a secure
-- button.
local function Build()
    if win then return win end
    win = Kit.Cover(PetPaperDollFrame, {
        name = "ZacUIPetPaperdollWindow",
        title = G("PET", "Pet"),
        insetName = "CharacterFrame",
        onClose = function()
            if not InCombatLockdown() then HideUIPanel(CharacterFrame) end
        end,
    })
    win.Reanchor = function() PlaceOverCharacter(win) end
    win.Reanchor()

    -- Level and family on the left, loyalty (hunters) on the right.
    local info = CreateFrame("Frame", nil, win)
    info:SetHeight(INFO_H)
    info:SetPoint("TOPLEFT", win, "TOPLEFT", Kit.PAD, -(M.TITLEBAR + 2))
    info:SetPoint("TOPRIGHT", win, "TOPRIGHT", -Kit.PAD, -(M.TITLEBAR + 2))
    infoLevel = UI.Font(info, F.LABEL, { justify = "LEFT" })
    infoLevel:SetPoint("LEFT", info, "LEFT", 0, 0)
    infoLevel:SetWordWrap(false)
    infoLoyal = UI.Font(info, F.SMALL, { justify = "RIGHT", cat = "text", key = "gray" })
    infoLoyal:SetPoint("RIGHT", info, "RIGHT", 0, 0)
    infoLoyal:SetPoint("LEFT", infoLevel, "RIGHT", 10, 0)
    infoLoyal:SetWordWrap(false)

    emptyText = UI.Font(win, F.CARD, { cat = "text", key = "gray", justify = "CENTER",
                                       text = "No pet summoned" })
    emptyText:SetPoint("CENTER", win, "CENTER", 0, 0)
    emptyText:Hide()

    -- Everything that needs a pet lives on one frame, hidden without one.
    body = CreateFrame("Frame", nil, win)
    body:SetPoint("TOPLEFT", win, "TOPLEFT", Kit.PAD, -(M.TITLEBAR + 2 + INFO_H + 4))
    body:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -Kit.PAD, Kit.PAD)

    resist = BuildResist(body)
    resist:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 0, 0)
    resist:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 0)

    local cardL = BuildCard(body, "Attributes", AttributeLines)
    cardL:SetPoint("BOTTOMLEFT", resist, "TOPLEFT", 0, GAP)
    cardL:SetPoint("BOTTOMRIGHT", resist, "TOP", -2, GAP)
    local cardR = BuildCard(body, "Combat", CombatLines)
    cardR:SetPoint("BOTTOMLEFT", resist, "TOP", 2, GAP)
    cardR:SetPoint("BOTTOMRIGHT", resist, "TOPRIGHT", 0, GAP)

    -- Hunter status card: happiness and training points on one line
    -- (explicit left / right halves so they cannot overlap), XP below.
    status = UI.Box(body, "ui", "cardBg")
    status:SetHeight(STATUS_H)
    status:SetPoint("BOTTOMLEFT", cardL, "TOPLEFT", 0, GAP)
    status:SetPoint("BOTTOMRIGHT", cardR, "TOPRIGHT", 0, GAP)

    happyIcon = status:CreateTexture(nil, "ARTWORK")
    happyIcon._zui_own = true
    happyIcon:SetSize(20, 20)
    happyIcon:SetPoint("TOPLEFT", status, "TOPLEFT", 6, -4)
    happyIcon:SetTexture(HAPPY_TEX)
    happyText = UI.Font(status, F.LABEL, { justify = "LEFT" })
    happyText:SetPoint("LEFT", happyIcon, "RIGHT", 6, 0)
    happyText:SetWordWrap(false)

    tpValue = UI.Font(status, F.LABEL, { justify = "RIGHT" })
    tpValue:SetPoint("RIGHT", status, "TOPRIGHT", -6, -14)
    tpValue:SetWordWrap(false)
    tpLabel = UI.Font(status, F.SMALL, { justify = "RIGHT", cat = "text", key = "gray" })
    tpLabel:SetPoint("RIGHT", tpValue, "LEFT", -4, 0)
    tpLabel:SetWordWrap(false)

    dmgText = UI.Font(status, F.SMALL, { justify = "LEFT", cat = "text", key = "gray" })
    dmgText:SetPoint("LEFT", happyText, "RIGHT", 8, 0)
    dmgText:SetPoint("RIGHT", tpLabel, "LEFT", -8, 0)
    dmgText:SetWordWrap(false)

    happyHot = CreateFrame("Frame", nil, status)
    happyHot:SetPoint("TOPLEFT", happyIcon, "TOPLEFT", 0, 0)
    happyHot:SetPoint("BOTTOMRIGHT", dmgText, "BOTTOMRIGHT", 0, -3)
    happyHot:EnableMouse(true)
    happyHot:SetScript("OnEnter", HappyEnter)
    happyHot:SetScript("OnLeave", function() GameTooltip:Hide() end)

    xpBar = FlatBar(status, 12)
    xpBar:SetPoint("TOPLEFT", status, "TOPLEFT", 6, -28)
    xpBar:SetPoint("TOPRIGHT", status, "TOPRIGHT", -6, -28)
    xpBar:Hide()

    -- The model takes the rest (its bottom edge follows ApplyState).
    stage = UI.Box(body, "ui", "cardBg")
    model = BuildModel(stage)
    lastHas, lastHunter = nil, nil
    ApplyState(false, false)

    -- THE X, SECURELY. CharacterFrame is protected, so an addon's
    -- HideUIPanel on it is refused in combat. A secure "click" on
    -- Blizzard's own close button runs their handler instead.
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

    -- Forever's modern window chrome (pane divider, toggle): hushed by name
    Kit.CharacterCover(win, "pet")

    -- Blizzard pieces around the cover are silenced only while this page
    -- is up, so the other Character tabs get them back.
    win:HookScript("OnShow", function()
        Quiet(Leftovers())
        -- The pet may have changed while the page was closed.
        lastHas, lastHunter = nil, nil
        FullRefresh()
        -- The skin flattens the tabs in a timer of its own; stop right
        -- above the new row a frame later (never in combat: protected).
        C_Timer.After(0, function()
            if win:IsVisible() and not InCombatLockdown() then win.Reanchor() end
        end)
    end)
    win:HookScript("OnHide", function()
        Unquiet(Leftovers())
    end)
    return win
end

-- What of Blizzard's hangs outside the cover or would show around it:
-- the portrait and close button past the top corners, the page's own
-- art (it rings the cover when the character skin is off), PetModelFrame
-- (under the cover, but a second model rendering for nobody) and the
-- page's Close button, which sits right on the cover's bottom edge. Never
-- the bottom tabs. The shared CharacterFrame pieces are the same list
-- Win_Paperdoll and Win_Character silence, so a tab switch hands them
-- from one cover to the next (Blizzard hides the old page before it
-- shows the new one).
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
    Add(_G.PetModelFrame)
    Add(_G.PetPaperDollCloseButton)
    if PetPaperDollFrame then
        for _, r in ipairs({ PetPaperDollFrame:GetRegions() }) do
            if r.IsObjectType and r:IsObjectType("Texture") and not r._zui_own then Add(r) end
        end
    end
    -- (Forever's pane divider and toggle are Kit.CharacterCover's:
    -- quietened by name, never hidden; Forever's own pet page is a
    -- sidebar of the paperdoll, with no PetPaperDollFrame to cover)
    return t
end

local function Apply()
    if not PetPaperDollFrame or not CharacterFrame then return end
    -- The cover is protected (its secure X): build, show and hide wait
    -- for the fight to end.
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
        -- Only hand the pieces back if this page is the one up: another
        -- tab's cover may be silencing the same shared chrome.
        local up = win:IsVisible()
        win:Hide()
        if up then Unquiet(Leftovers()) end
    end
end

-- ============================================================
-- MODULE
-- ============================================================
Modules.petpaperdollwin = function()
    if not PetPaperDollFrame or not CharacterFrame or ns._zPetPaperdollWin then return end
    ns._zPetPaperdollWin = true
    -- A later /zui toggle only flips the saved flag; the page checks it on
    -- every open (out of combat) so turning it off never needs a reload.
    -- Apply itself defers to the end of a fight (pendingApply).
    PetPaperDollFrame:HookScript("OnShow", function() Apply() end)
    -- Built at login rather than on first open, so a first Pet-tab click
    -- in combat still finds the page. A login in combat builds on the way out.
    local watch = CreateFrame("Frame")
    watch:RegisterEvent("PLAYER_REGEN_ENABLED")
    watch:SetScript("OnEvent", function()
        if pendingApply then Apply() end
    end)
    Apply()
end
