-- Tooltip_Stats - item tooltips' long Classic stat lines made short:
-- "Equip: Increases attack power by 24." becomes "+24 Attack Power",
-- "Equip: Improves your chance to hit by 1%." becomes "+1% Hit", each in
-- its own colour, the line replaced where it stands. Off by default
-- (Tooltips > General), with a before / after sample on the page.
-- Part of ZacUI; load order is set by the TOC (after Blz_Tooltip).
--
-- HOW A LINE IS READ. The "Equip:" word is the game's own
-- (ITEM_SPELL_TRIGGER_ONEQUIP), and each stat's short name is the game's
-- own too (ITEM_MOD_*_SHORT: "Attack Power", "Hit", "Spell Power",
-- "Defense"...), so the words written on the line are the client's
-- language. What is matched behind "Equip:" is Classic's English wording
-- of each effect ("Increases attack power by N", "Improves your chance
-- to hit by N%") - a client in another language leaves those lines as
-- they are, since the game ships no string for the wording of an equip
-- effect. Resistance lines ("+10 Fire Resistance", ITEM_RESIST_SINGLE)
-- are already short and only take a colour.
--
-- EVERY TOOLTIP that shows an item: the game tooltip, the chat link
-- tooltip and the two comparison tooltips. Through the tooltip data hook
-- where the client has one (TooltipDataProcessor), the OnTooltipSetItem
-- script otherwise. A line the game hides from addons (WoW Forever, in a
-- fight) is left alone.
--
-- COST: one pass over a tooltip's lines when an item is set; nothing else.

local ADDON_NAME, ns = ...

local GetColor = ns.GetColor
local TipCfg = ns.TipCfg

local TS = {}
ns.TooltipStats = TS

local OWN_ID = "tooltip_stats"

-- ============================================================
-- SETTINGS (tooltip.statLines, tooltip.statColors; nothing saved = off)
-- ============================================================
local function Cfg()
    if TipCfg then return TipCfg() end
    ZacUIDB.tooltip = ZacUIDB.tooltip or {}
    return ZacUIDB.tooltip
end
TS.Cfg = Cfg
function TS.On()
    if ns.FeatureOn and not ns.FeatureOn(OWN_ID) then return false end
    return Cfg().statLines == true
end
function TS.ColourResist() return Cfg().statResist ~= false end

-- ============================================================
-- THE STATS
-- ============================================================
-- Each: its key, the game's short name (global, English fallback), the
-- Classic wording behind "Equip:" (captures the number), whether it is a
-- percent, and the colour it wears by default (a palette key or r,g,b).
local function G(name, fallback)
    local v = _G[name]
    if type(v) == "string" and v ~= "" then return v end
    return fallback
end
TS.STATS = {
    { key = "ap", name = G("ITEM_MOD_ATTACK_POWER_SHORT", "Attack Power"),
      pats = { "^Increases attack power by (%d+)%.?$" }, color = { 1, 0.6, 0.2 } },
    { key = "rap", name = G("ITEM_MOD_RANGED_ATTACK_POWER_SHORT", "Ranged Attack Power"),
      pats = { "^Increases ranged attack power by (%d+)%.?$" }, color = { 1, 0.7, 0.3 } },
    { key = "crit", name = G("ITEM_MOD_CRIT_RATING_SHORT", "Critical Strike"), percent = true,
      pats = { "^Improves your chance to get a critical strike by (%d+)%%%.?$",
               "^Increases your chance to get a critical strike by (%d+)%%%.?$",
               "^Increases your critical strike chance by (%d+)%%%.?$" }, color = { 1, 0.85, 0.3 } },
    { key = "spellcrit", name = G("ITEM_MOD_CRIT_SPELL_RATING_SHORT", "Spell Critical Strike"), percent = true,
      pats = { "^Improves your chance to get a critical strike with spells by (%d+)%%%.?$",
               "^Increases your chance to get a critical strike with spells by (%d+)%%%.?$" }, color = { 0.8, 0.6, 1 } },
    { key = "hit", name = G("ITEM_MOD_HIT_RATING_SHORT", "Hit"), percent = true,
      pats = { "^Improves your chance to hit by (%d+)%%%.?$", "^Increases your chance to hit by (%d+)%%%.?$" },
      color = { 1, 1, 0.5 } },
    { key = "spellhit", name = G("ITEM_MOD_HIT_SPELL_RATING_SHORT", "Spell Hit"), percent = true,
      pats = { "^Improves your chance to hit with spells by (%d+)%%%.?$",
               "^Increases your chance to hit with spells by (%d+)%%%.?$" }, color = { 0.7, 0.7, 1 } },
    { key = "sp", name = G("ITEM_MOD_SPELL_POWER_SHORT", "Spell Power"),
      pats = { "^Increases damage and healing done by magical spells and effects by up to (%d+)%.?$" },
      color = { 0.5, 0.7, 1 } },
    { key = "heal", name = G("ITEM_MOD_SPELL_HEALING_DONE_SHORT", "Healing"),
      pats = { "^Increases healing done by spells and effects by up to (%d+)%.?$",
               "^Increases healing done by magical spells and effects by up to (%d+)%.?$" }, color = { 0.4, 0.9, 0.5 } },
    { key = "schooldmg", name = nil,   -- the school is in the line: "+20 Fire Damage"
      pats = { "^Increases damage done by (%a+) spells and effects by up to (%d+)%.?$" }, school = true,
      color = { 0.9, 0.5, 0.9 } },
    { key = "def", name = G("ITEM_MOD_DEFENSE_SKILL_RATING_SHORT", "Defense"),
      pats = { "^Increased Defense %+(%d+)%.?$", "^Increases your defense by (%d+)%.?$",
               "^Increases defense rating by (%d+)%.?$" }, color = { 0.6, 0.8, 1 } },
    { key = "mp5", name = G("ITEM_MOD_MANA_REGENERATION_SHORT", "Mana per 5 sec"),
      pats = { "^Restores (%d+) mana per 5 sec%.?$" }, color = { 0.4, 0.6, 1 } },
    { key = "hp5", name = G("ITEM_MOD_HEALTH_REGENERATION_SHORT", "Health per 5 sec"),
      pats = { "^Restores (%d+) health per 5 sec%.?$" }, color = { 0.4, 1, 0.5 } },
    { key = "dodge", name = G("ITEM_MOD_DODGE_RATING_SHORT", "Dodge"), percent = true,
      pats = { "^Increases your chance to dodge an attack by (%d+)%%%.?$" }, color = { 0.6, 0.9, 1 } },
    { key = "parry", name = G("ITEM_MOD_PARRY_RATING_SHORT", "Parry"), percent = true,
      pats = { "^Increases your chance to parry an attack by (%d+)%%%.?$" }, color = { 0.8, 0.8, 0.6 } },
    { key = "block", name = G("ITEM_MOD_BLOCK_RATING_SHORT", "Block"), percent = true,
      pats = { "^Increases your chance to block attacks with a shield by (%d+)%%%.?$" }, color = { 0.7, 0.7, 0.7 } },
    { key = "blockvalue", name = G("ITEM_MOD_BLOCK_VALUE_SHORT", "Block Value"),
      pats = { "^Increases the block value of your shield by (%d+)%.?$" }, color = { 0.75, 0.75, 0.8 } },
}
TS.RESIST = { key = "resist", name = "Resistance", color = { 0.6, 0.9, 0.6 } }
local BY_KEY = {}
for _, s in ipairs(TS.STATS) do BY_KEY[s.key] = s end
BY_KEY.resist = TS.RESIST

-- "Equip:" as this client writes it, and the pattern that strips it
local EQUIP = G("ITEM_SPELL_TRIGGER_ONEQUIP", "Equip:")
local function Escape(s) return (s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")) end
local EQUIP_PAT = "^" .. Escape(EQUIP) .. "%s*(.-)%s*$"
-- a resistance line, from the game's own format ("%c%d %s Resistance")
local RESIST_PAT
do
    local fmt = G("ITEM_RESIST_SINGLE", "%c%d %s Resistance")
    local p = Escape(fmt)
    -- the escaped placeholders back into captures: sign+number, school
    p = p:gsub("%%%%c%%%%d", "([%%+%%-]%%d+)"):gsub("%%%%d", "(%%d+)"):gsub("%%%%s", "(.-)")
    RESIST_PAT = "^" .. p .. "$"
end
TS.EQUIP_PAT, TS.RESIST_PAT = EQUIP_PAT, RESIST_PAT

-- the colour a stat wears: the saved one, else its default
function TS.Color(key)
    local c = Cfg().statColors
    c = type(c) == "table" and c[key] or nil
    if type(c) == "table" and ns.ColorOf then return ns.ColorOf(c) end
    local s = BY_KEY[key]
    local d = s and s.color or { 1, 1, 1 }
    return d[1], d[2], d[3], 1
end

-- one tooltip line -> the short line and its colour, or nil to leave it
-- (the text is never touched while the game hides it)
function TS.Rewrite(text)
    if type(text) ~= "string" or text == "" then return nil end
    if ns.IsSecret and ns.IsSecret(text) then return nil end
    local body = text:match(EQUIP_PAT)
    if body then
        for _, s in ipairs(TS.STATS) do
            for _, p in ipairs(s.pats) do
                local a, b = body:match(p)
                if a then
                    local n, name
                    if s.school then n, name = b, a .. " Damage" else n, name = a, s.name end
                    local r, g, bl = TS.Color(s.key)
                    return "+" .. n .. (s.percent and "%" or "") .. " " .. name, r, g, bl, s.key
                end
            end
        end
        return nil
    end
    if TS.ColourResist() then
        local n, school = text:match(RESIST_PAT)
        if n and school and not school:find(" ") then
            local r, g, b = TS.Color("resist")
            return text, r, g, b, "resist"
        end
    end
    return nil
end

-- ============================================================
-- THE TOOLTIPS
-- ============================================================
function TS.Process(tt)
    if not TS.On() then return 0 end
    local name = tt.GetName and tt:GetName()
    local n = tt.NumLines and tt:NumLines() or 0
    if not name or n < 2 then return 0 end
    local changed = 0
    for i = 2, n do
        local left = _G[name .. "TextLeft" .. i]
        if left and left.GetText then
            local text = left:GetText()
            local new, r, g, b = TS.Rewrite(text)
            if new then
                if new ~= text then left:SetText(new) end
                left:SetTextColor(r, g, b, 1)
                changed = changed + 1
            end
        end
    end
    return changed
end

local hooked = false
local function HookTooltips()
    if hooked then return end
    hooked = true
    local tips = {}
    for _, n in ipairs({ "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2" }) do
        if _G[n] then tips[_G[n]] = true end
    end
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
        and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt)
            if tips[tt] then pcall(TS.Process, tt) end
        end)
        return
    end
    for tt in pairs(tips) do
        if tt.HookScript and (not tt.HasScript or tt:HasScript("OnTooltipSetItem")) then
            pcall(tt.HookScript, tt, "OnTooltipSetItem", function(self) pcall(TS.Process, self) end)
        end
    end
end
TS.Hook = HookTooltips

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    HookTooltips()
end)

-- ============================================================
-- THE PAGE: a card on Tooltips > General, with a before / after sample
-- ============================================================
TS.SAMPLE = {
    "Equip: Increases attack power by 24.",
    "Equip: Improves your chance to get a critical strike by 1%.",
    "Equip: Improves your chance to hit by 1%.",
    "Equip: Increases damage and healing done by magical spells and effects by up to 29.",
    "Equip: Increases healing done by spells and effects by up to 55.",
    "Equip: Increased Defense +7.",
    "Equip: Restores 5 mana per 5 sec.",
    "+10 Fire Resistance",
}

local function AddTab(page, tab, label, build)
    if ns.AddPageTab then return ns.AddPageTab(page, tab, label, build) end
    ns.PageTabs = ns.PageTabs or {}
    local list = ns.PageTabs[page] or {}
    ns.PageTabs[page] = list
    list[#list + 1] = { tab = tab, label = label, build = build }
end

-- the sample: two columns of lines, the left as the game writes them,
-- the right as this file rewrites them (through TS.Rewrite itself)
function TS.BuildSample(parent, width)
    local UI = ns.UI
    local host = UI.Holder(parent)
    local colW = math.max(120, math.floor((width - 12) / 2))
    host.lines = {}
    local y = 0
    local hl = UI.Font(host, UI.F.SMALL, { cat = "text", key = "gray", text = "Before" })
    hl:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    local hr = UI.Font(host, UI.F.SMALL, { cat = "text", key = "gray", text = "After" })
    hr:SetPoint("TOPLEFT", host, "TOPLEFT", colW + 12, 0)
    -- (as tall as the heading's type: the settings window's is larger)
    y = y - math.max(16, math.ceil(hl:GetStringHeight() or 12) + 4)
    for i, text in ipairs(TS.SAMPLE) do
        local l = UI.Font(host, UI.F.SMALL, { width = colW, justify = "LEFT" })
        l:SetPoint("TOPLEFT", host, "TOPLEFT", 0, y)
        l:SetText(text)
        local r = UI.Font(host, UI.F.SMALL, { width = colW, justify = "LEFT" })
        r:SetPoint("TOPLEFT", host, "TOPLEFT", colW + 12, y)
        host.lines[i] = { l, r, text }
        local h = math.max(l:GetStringHeight() or 12, 12)
        y = y - h - 3
    end
    host:SetSize(width, -y + 2)
    function host.Refresh()
        for _, row in ipairs(host.lines) do
            local l, r, text = row[1], row[2], row[3]
            local isEquip = text:match(EQUIP_PAT) ~= nil
            if isEquip then l:SetTextColor(0, 1, 0, 1) else l:SetTextColor(1, 1, 1, 1) end
            local new, cr, cg, cb = TS.Rewrite(text)
            if new then
                r:SetText(new)
                r:SetTextColor(cr, cg, cb, 1)
            else
                r:SetText(text)
                if isEquip then r:SetTextColor(0, 1, 0, 1) else r:SetTextColor(1, 1, 1, 1) end
            end
        end
    end
    host.Refresh()
    return host
end

AddTab("tooltips", "general", "General", function(L)
    if ns.FeatureOn and not ns.FeatureOn(OWN_ID) then return end
    local UI = ns.UI
    local Kit = ns.CorePageKit
    local cfg = Cfg()
    L:Card("Stat lines on items")
    local on = UI.Checkbox(L.current, "Short stat lines", cfg.statLines == true, function(v)
        cfg.statLines = v or nil
        if ns.RefreshConfig then ns.RefreshConfig() end
    end, { tooltip = "\"Equip: Increases attack power by 24.\" reads \"+24 Attack Power\", in the stat's colour, on "
        .. "every item tooltip. Attack power, crit, hit, spell power and healing, defence, mana and health per 5, "
        .. "dodge, parry, block; resistance lines keep their words and take a colour." })
    L:Row(on, 17)
    local sample = TS.BuildSample(L.current, UI.CardInnerWidth and UI.CardInnerWidth(L) or 400)
    L:Add(sample, 8)
    local kids = {}
    kids[#kids + 1] = UI.Checkbox(L.current, "Colour resistance lines too", TS.ColourResist(), function(v)
        if v then cfg.statResist = nil else cfg.statResist = false end
        sample.Refresh()
    end)
    L:Dependent(kids, cfg.statLines == true, 1, nil, "Short stat lines")
    L:EndCard()

    L:Card("Stat colours")
    L:Desc("Each stat's line colour. Blank is ZacUI's colour for it.")
    local function Picker(s)
        return UI.ColorPicker(L.current, { label = s.name or "School damage",
            get = function()
                local c = cfg.statColors
                c = type(c) == "table" and c[s.key] or nil
                if type(c) == "table" then return ns.ColorOf(c) end
                return TS.Color(s.key)
            end,
            set = function(r, g, b)
                if type(cfg.statColors) ~= "table" then cfg.statColors = {} end
                cfg.statColors[s.key] = { r = r, g = g, b = b, a = 1 }
                sample.Refresh()
            end,
            default = function() local d = s.color return d[1], d[2], d[3], 1 end,
            reset = function()
                if type(cfg.statColors) == "table" then
                    cfg.statColors[s.key] = nil
                    if next(cfg.statColors) == nil then cfg.statColors = nil end
                end
                sample.Refresh()
                if ns.SettingsChanged then ns.SettingsChanged("reset") end
            end })
    end
    local pickers = {}
    for _, s in ipairs(TS.STATS) do pickers[#pickers + 1] = Picker(s) end
    pickers[#pickers + 1] = Picker(TS.RESIST)
    L:Grid(pickers, 2)
    L:EndCard()
end)

if ns.AddMenuKeywords then
    ns.AddMenuKeywords("tooltips", "stat stats short lines equip attack power crit hit spell power healing defense mp5 resistance colour color")
end
