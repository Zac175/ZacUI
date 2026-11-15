-- QoL_GatherSkill - the skill a herb or ore node needs, on its tooltip:
-- the game's "Requires Herbalism" line reads "Requires Herbalism (150)",
-- coloured by your chance of a skill-up there (orange, yellow, green, grey,
-- the way recipes show it); the game's own red stays while you cannot
-- gather it. Off by default (Tooltips > General, "Gathering nodes").
-- Part of ZacUI (the QoL part); load order is set by the TOC.
--
-- HOW A NODE IS KNOWN. A world object's tooltip carries no id, only its
-- name. A herb node bears its herb's name, so herbs are listed by the herb
-- ITEM and named from the client (any language); ore nodes are listed by
-- their English names (other languages: the ore lines stay as the game
-- shows them). The skill each node needs is the game's own: Classic's
-- nodes, and TBC's Outland nodes (Felweed to Mana Thistle, Fel Iron to
-- Khorium) on every client that has them.
--
-- COLOURS: under 25 points over the need orange, under 50 yellow, under
-- 100 green, then grey (gathering's skill-up odds).
--
-- THE HOOK. Where the client has TooltipDataProcessor, a post call on
-- world-object tooltips; on the older clients the tooltip's OnShow, which
-- returns at once for a unit or an item tooltip. Off, it returns at once.
-- A hidden line (Forever) is left untouched.

local ADDON_NAME = ...
local ns = _G.ZacUI
if not ns then return end

local QoL = ns.QoL
if not QoL then return end

local G = {}
QoL.GatherSkill = G

local OWN_ID = "gather_skill"
local HERB, MINE = "herb", "mine"

-- herb ITEM id -> the skill its node needs
G.HERBS = {
    -- Classic
    [765] = 1, [2447] = 1, [2449] = 15, [785] = 50, [2450] = 70, [3820] = 85, [2453] = 100,
    [3355] = 115, [3369] = 120, [3356] = 125, [3357] = 150, [3818] = 160, [3821] = 170,
    [3358] = 185, [3819] = 195, [4625] = 205, [8831] = 210, [8836] = 220, [8838] = 230,
    [8839] = 235, [8845] = 245, [8846] = 250, [13464] = 260, [13463] = 270, [13465] = 280,
    [13466] = 285, [13467] = 290, [13468] = 300,
    -- The Burning Crusade (Outland)
    [22785] = 300, [22786] = 315, [22787] = 325, [22789] = 325, [22788] = 335,
    [22790] = 340, [22791] = 350, [22792] = 365, [22793] = 375,
}
-- ore NODE name (English) -> the skill it needs
G.ORES = {
    ["Copper Vein"] = 1, ["Tin Vein"] = 65, ["Incendicite Mineral Vein"] = 65,
    ["Silver Vein"] = 75, ["Ooze Covered Silver Vein"] = 75, ["Lesser Bloodstone Deposit"] = 75,
    ["Iron Deposit"] = 125, ["Indurium Mineral Vein"] = 150, ["Gold Vein"] = 155,
    ["Ooze Covered Gold Vein"] = 155, ["Mithril Deposit"] = 175, ["Ooze Covered Mithril Deposit"] = 175,
    ["Truesilver Deposit"] = 230, ["Ooze Covered Truesilver Deposit"] = 230, ["Dark Iron Deposit"] = 230,
    ["Small Thorium Vein"] = 245, ["Ooze Covered Thorium Vein"] = 245, ["Rich Thorium Vein"] = 275,
    ["Ooze Covered Rich Thorium Vein"] = 275, ["Hakkari Thorium Vein"] = 275,
    -- The Burning Crusade (Outland)
    ["Fel Iron Deposit"] = 300, ["Nethercite Deposit"] = 275, ["Adamantite Deposit"] = 325,
    ["Rich Adamantite Deposit"] = 350, ["Khorium Vein"] = 375, ["Ancient Gem Vein"] = 375,
}
-- the profession each kind is: skill line id, the spells that may carry its name
local KIND = {
    [HERB] = { line = 182, spells = { 2366, 2368, 3570, 11993 }, english = "Herbalism" },
    [MINE] = { line = 186, spells = { 2575, 2576, 3564, 10248 }, english = "Mining" },
}

local function Hidden(v) return ns.IsSecret and ns.IsSecret(v) or false end

-- ============================================================
-- SETTINGS (tooltip.gatherSkill under qol; nothing saved = off)
-- ============================================================
local function DB()
    local q = QoL.DB()
    if type(q.gatherSkill) ~= "table" then q.gatherSkill = {} end
    return q.gatherSkill
end
G.DB = DB
local function Allowed() return not (ns.FeatureOn and not ns.FeatureOn(OWN_ID)) end
function G.On() return Allowed() and QoL.enabled == true and DB().enabled == true end

-- ============================================================
-- THE NODES
-- ============================================================
local nodes          -- name -> { kind, need }
local waiting = {}   -- herb item id -> true while its name has not loaded

local function ItemName(id)
    if C_Item and type(C_Item.GetItemNameByID) == "function" then
        local n = C_Item.GetItemNameByID(id)
        if n then return n end
    end
    if GetItemInfo then return (GetItemInfo(id)) end
    return nil
end

local loader
local function AddHerb(id)
    local name = ItemName(id)
    if type(name) ~= "string" or Hidden(name) then return false end
    nodes[name] = { HERB, G.HERBS[id] }
    return true
end

function G.Build()
    nodes = {}
    for name, need in pairs(G.ORES) do nodes[name] = { MINE, need } end
    for id in pairs(G.HERBS) do
        if not AddHerb(id) then
            waiting[id] = true
            if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
        end
    end
    if next(waiting) then
        if not loader then
            loader = CreateFrame("Frame")
            loader:SetScript("OnEvent", function(self, _, id, success)
                if not waiting[id] then return end
                waiting[id] = nil
                if success ~= false and nodes then AddHerb(id) end
                if not next(waiting) then self:UnregisterAllEvents() end
            end)
        end
        pcall(loader.RegisterEvent, loader, "ITEM_DATA_LOAD_RESULT")
        pcall(loader.RegisterEvent, loader, "GET_ITEM_INFO_RECEIVED")
    end
    return nodes
end
function G.Node(name)
    if not nodes then G.Build() end
    return nodes[name]
end

-- the names a profession's line may carry on this client
local function SkillNames(kind)
    local k = KIND[kind]
    local out = { k.english }
    for _, id in ipairs(k.spells) do
        local n
        if C_Spell and type(C_Spell.GetSpellName) == "function" then n = C_Spell.GetSpellName(id) end
        if not n and GetSpellInfo then n = (GetSpellInfo(id)) end
        if type(n) == "string" and n ~= "" then out[#out + 1] = n end
    end
    return out
end
G.SkillNames = SkillNames

-- your skill in that profession, nil without it
function G.Skill(kind)
    local k = KIND[kind]
    if type(GetProfessions) == "function" and type(GetProfessionInfo) == "function" then
        for _, index in ipairs({ GetProfessions() }) do
            if index then
                local _, _, rank, _, _, _, line = GetProfessionInfo(index)
                if line == k.line and not Hidden(rank) then return rank end
            end
        end
    end
    if type(GetNumSkillLines) == "function" and type(GetSkillLineInfo) == "function" then
        local names = {}
        for _, n in ipairs(SkillNames(kind)) do names[n] = true end
        for i = 1, GetNumSkillLines() do
            local name, header, _, rank = GetSkillLineInfo(i)
            if not header and name and names[name] and not Hidden(rank) then return rank end
        end
    end
    return nil
end

-- the skill-up colour for skill over need
function G.Odds(skill, need)
    local over = skill - need
    if over < 25 then return 1, 0.5, 0.25 end
    if over < 50 then return 1, 1, 0 end
    if over < 100 then return 0.25, 0.75, 0.25 end
    return 0.5, 0.5, 0.5
end

-- ============================================================
-- THE TOOLTIP
-- ============================================================
local function Line(tt, i)
    local n = tt.GetName and tt:GetName()
    return n and _G[n .. "TextLeft" .. i] or nil
end

-- rewrites the requirement line of a node's tooltip; true when it did
function G.Decorate(tt)
    if not G.On() or not tt or not tt.NumLines then return false end
    local first = Line(tt, 1)
    local title = first and first:GetText()
    if type(title) ~= "string" or Hidden(title) then return false end
    local node = G.Node(title)
    if not node then return false end
    local kind, need = node[1], node[2]
    local names = SkillNames(kind)
    for i = 2, tt:NumLines() do
        local fs = Line(tt, i)
        local text = fs and fs:GetText()
        if type(text) == "string" and not Hidden(text) and not text:find("%(%d+%)%s*$") then
            for _, n in ipairs(names) do
                if text:find(n, 1, true) then
                    fs:SetText(string.format("%s (%d)", text, need))
                    local skill = G.Skill(kind)
                    if skill and skill >= need then fs:SetTextColor(G.Odds(skill, need)) end
                    if tt.Show then tt:Show() end
                    return true
                end
            end
        end
    end
    return false
end

local hooked = false
local function Hook()
    if hooked or not GameTooltip then return end
    hooked = true
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType
        and Enum.TooltipDataType.Object then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Object, function(tt)
            if tt == GameTooltip then pcall(G.Decorate, tt) end
        end)
    else
        GameTooltip:HookScript("OnShow", function(tt)
            if not G.On() then return end
            -- a unit's or an item's tooltip is never a node's
            if tt.GetUnit and tt:GetUnit() then return end
            if tt.GetItem and tt:GetItem() then return end
            pcall(G.Decorate, tt)
        end)
    end
end
G.Hooked = function() return hooked end

function G.Apply()
    if not G.On() then return end
    if not nodes then G.Build() end
    Hook()
end
if Allowed() then
    local base = QoL.EnableAutomation
    function QoL.EnableAutomation(...)
        if base then base(...) end
        pcall(G.Apply)
    end
end

-- ============================================================
-- THE CARD: Tooltips > General
-- ============================================================
local function AddTab(page, tab, label, build)
    if ns.AddPageTab then return ns.AddPageTab(page, tab, label, build) end
    ns.PageTabs = ns.PageTabs or {}
    local list = ns.PageTabs[page] or {}
    ns.PageTabs[page] = list
    list[#list + 1] = { tab = tab, label = label, build = build }
end

AddTab("tooltips", "general", "General", function(L)
    if not Allowed() then return end
    local UI = ns.UI
    local d = DB()
    L:Card("Gathering nodes")
    local w = UI.Checkbox(L.current, "Show the skill a herb or ore node needs", d.enabled == true, function(v)
        d.enabled = v and true or nil
        if QoL.enabled then G.Apply() end
        if ns.RefreshConfig then ns.RefreshConfig() end
    end, { tooltip = "On a herb or ore node's tooltip, the game's \"Requires Herbalism\" / \"Requires Mining\" "
        .. "line gets the skill the node needs, coloured by your chance of a skill-up there: orange, yellow, green, grey." })
    L:Row(w, 17)
    -- what it looks like, in the four colours
    local sample = UI.Font(L.current, UI.F.LABEL, { text = "" })
    local function C(r, g, b) return string.format("|cff%02x%02x%02x", r * 255, g * 255, b * 255) end
    sample:SetText("Requires Herbalism " .. C(1, 0.5, 0.25) .. "(150)|r   "
        .. C(1, 1, 0) .. "(150)|r   " .. C(0.25, 0.75, 0.25) .. "(150)|r   " .. C(0.5, 0.5, 0.5) .. "(150)|r")
    L:Row(sample, 18)
    L:Desc("Herbs read their names from the game in your language; ore nodes are matched by their English names. "
        .. "Classic and Outland nodes.")
    if not QoL.enabled then L:Desc("The Quality of life part is not running, so this is not either.") end
    L:EndCard()
end)

if ns.AddMenuKeywords then
    ns.AddMenuKeywords("tooltips", "gathering herb herbalism ore mining node skill required level tooltip")
end
