-- Config_PagesClassicBook - the "Talents & spellbook" page on WoW Forever:
-- ZacUI's Classic talent trees and every-rank spellbook over Forever's
-- combined spells window (Win_TalentsForever, Win_SpellbookForever).
-- Part of ZacUI; load order is set by the TOC (after Config_PagesWindows,
-- under whose menu row it sits).
--
-- The two switches are the windows' own module switches (the same as
-- Modules > Windows > Talents / Spellbook), so nothing new is saved and
-- nobody's default moves: on, as everywhere ZacUI's windows are on. The
-- preview is three trees drawn by the window's own code from a sample
-- warrior, in ZacUI's look or the Classic look.

local ADDON_NAME = ...
local ns = _G.ZacUI
if not ns then return end
if not _G.ZACUI_IS_FOREVER then return end
if ns.FeatureOn and not ns.FeatureOn("classic_book") then return end

local CT = ns.ClassicTalents
local RegisterPage = ns.RegisterPage
local UI = ns.UI
if not (CT and RegisterPage and UI) then return end

local M = UI.M
local PAGE_ID, MENU_ID = "ClassicBook", "classicbook"

-- ============================================================
-- THE MENU ROW (under Game windows)
-- ============================================================
do
    for _, group in ipairs(ns.ConfigMenu or {}) do
        if group.id == "windows" and group.children then
            local have, after = false, nil
            for i, child in ipairs(group.children) do
                if child.id == MENU_ID then have = true end
                if child.id == "gamewindows" then after = i end
            end
            if not have then
                table.insert(group.children, (after or #group.children) + 1, {
                    id = MENU_ID, label = "Talents & spellbook", page = PAGE_ID, addon = "Zacui_Windows",
                    keywords = "talents talent tree trees classic vanilla spellbook spell book ranks rank "
                        .. "all ranks learn points arms fury protection spec",
                })
            end
        end
    end
end

-- ============================================================
-- THE PREVIEW: A SAMPLE WARRIOR, DRAWN BY THE WINDOW'S OWN CODE
-- ============================================================
local I = "Interface\\Icons\\"
-- tree, tier, column, rank, max, name, icon, requirement (node id)
local SAMPLE = {
    { 1, 1, 1, 3, 3, "Improved Heroic Strike", "Ability_Rogue_Ambush" },
    { 1, 1, 2, 5, 5, "Deflection", "Ability_Parry" },
    { 1, 1, 3, 2, 3, "Improved Rend", "Ability_Gouge" },
    { 1, 2, 1, 2, 2, "Improved Charge", "Ability_Warrior_Charge" },
    { 1, 2, 4, 5, 5, "Tactical Mastery", "Spell_Nature_EnchantArmor" },
    { 1, 3, 2, 2, 2, "Improved Overpower", "INV_Sword_05", 2 },
    { 1, 3, 3, 1, 1, "Anger Management", "Spell_Holy_BlessingOfStamina", 3 },
    { 1, 4, 2, 2, 2, "Deep Wounds", "Ability_BackStab", 6 },
    { 1, 5, 2, 0, 5, "Impale", "Ability_SearingArrow", 8 },
    { 1, 7, 2, 0, 1, "Mortal Strike", "Ability_Warrior_SavageBlow" },
    { 2, 1, 2, 5, 5, "Cruelty", "Ability_Rogue_Eviscerate" },
    { 2, 1, 3, 0, 5, "Booming Voice", "Spell_Nature_Purge" },
    { 2, 2, 3, 0, 5, "Unbridled Wrath", "Spell_Nature_StoneClawTotem" },
    { 2, 2, 2, 0, 5, "Improved Demoralizing Shout", "Ability_Warrior_WarCry" },
    { 3, 1, 2, 0, 5, "Shield Specialization", "INV_Shield_06" },
    { 3, 1, 3, 0, 5, "Anticipation", "Spell_Nature_MirrorImage" },
    { 3, 2, 2, 0, 3, "Improved Bloodrage", "Ability_Racial_BloodRage" },
    { 3, 2, 3, 0, 1, "Last Stand", "Spell_Holy_AshesToAshes", 17 },
}
local TREES = {
    { "Arms", "Ability_Rogue_Eviscerate", 26 },
    { "Fury", "Ability_Warrior_InnerRage", 256 },
    { "Protection", "INV_Shield_06", 257 },
}

local function SampleModel()
    local m = { trees = {}, nodes = {}, byID = {}, unspent = 5, stagedCount = 0, sample = true }
    for i, t in ipairs(TREES) do
        m.trees[i] = { index = i, name = t[1], icon = I .. t[2], skillLineID = t[3], nodes = {}, spent = 0, ranks = 0 }
    end
    for id, s in ipairs(SAMPLE) do
        local tree = m.trees[s[1]]
        local n = { id = id, tree = tree, x = (s[1] - 1) * 4000 + (s[3] - 1) * 630, y = (s[2] - 1) * 630,
            rank = s[4], max = s[5], name = s[6], icon = I .. s[7], edges = {}, from = {},
            canBuy = false, canRefund = false, available = true, staged = false }
        m.nodes[#m.nodes + 1] = n
        m.byID[id] = n
        tree.nodes[#tree.nodes + 1] = n
        tree.spent = tree.spent + n.rank
    end
    for id, s in ipairs(SAMPLE) do
        local req = s[8] and m.byID[s[8]]
        if req then
            local lit = req.rank >= req.max
            req.edges[#req.edges + 1] = { to = id, active = lit }
            m.byID[id].from[#m.byID[id].from + 1] = { node = req, active = lit }
        end
    end
    -- reachable with points left: the ones whose requirement is full and
    -- whose tier the tree's points have opened (five per tier)
    CT.Layout(m)
    for _, n in ipairs(m.nodes) do
        n.canBuy = n.rank < n.max
        for _, e in ipairs(n.from) do if not e.active then n.canBuy = false end end
    end
    for _, n in ipairs(m.nodes) do
        if (n.tier - 1) * 5 > n.tree.spent then n.canBuy = false end
    end
    -- one pick waiting for Learn
    local rend = m.byID[3]
    rend.staged, rend.tree.staged, m.stagedCount = true, true, 1
    return m
end
ns.ClassicTalents.SampleModel = SampleModel

local SCALE = 0.56

local function Paint(st, mode)
    local views = st.views[mode]
    if not views then
        views = {}
        for i = 1, 3 do views[i] = CT.NewTreeView(st.holder, CT.GEO) end
        st.views[mode] = views
    end
    for m, vs in pairs(st.views) do
        for _, v in ipairs(vs) do v:SetShown(m == mode) end
    end
    local model = st.model
    local tw = CT.TreeW(CT.GEO, model.cols)
    local ctx = { editable = true, unspent = model.unspent, classFile = "WARRIOR" }
    for i, v in ipairs(views) do
        v:ClearAllPoints()
        v:SetPoint("TOPLEFT", st.holder, "TOPLEFT", (i - 1) * (tw + CT.GEO.gap), 0)
        CT.PaintTree(v, model.trees[i], model, ctx)
    end
end

local function BuildPreview(canvas, P)
    local st = P.store
    st.model = SampleModel()
    st.views = {}
    st.holder = CreateFrame("Frame", nil, canvas)
    local tw, th = CT.TreeW(CT.GEO, st.model.cols), CT.TreeH(CT.GEO, st.model.tiers)
    st.w, st.h = 3 * tw + 2 * CT.GEO.gap, th
    st.holder:SetSize(st.w, st.h)
    st.holder:SetScale(SCALE)
    st.holder:SetPoint("CENTER", canvas, "CENTER", 0, 0)
end

local function UpdatePreview(canvas, P)
    local st = P.store
    local mode = P.mode or ((ns.Look and ns.Look.Active and ns.Look.Active() ~= "zacui") and "classic" or "zacui")
    if ns.Look and ns.Look.With then
        ns.Look.With(mode, Paint, st, mode)
    else
        Paint(st, mode)
    end
    if P.Resize then P.Resize(math.floor(st.w * SCALE) + 24, math.floor(st.h * SCALE) + 24) end
end

-- ============================================================
-- THE PAGE
-- ============================================================
local function ModuleOn(key)
    return ZacUIDB and ZacUIDB.modules and ZacUIDB.modules[key] ~= false
end

RegisterPage(PAGE_ID, function(L)
    L:Header("Talents & spellbook",
        "Forever's talents are the three Classic trees and its book keeps every rank. ZacUI shows "
        .. "them the Classic way, inside the game's own spells window: the talent key and P open them as always.")

    L:Preview({
        key = "windows.classicbook",
        title = "Talent trees",
        width = math.floor((3 * CT.TreeW(CT.GEO, 4) + 2 * CT.GEO.gap) * SCALE) + 24,
        height = math.floor(CT.TreeH(CT.GEO, 7) * SCALE) + 24,
        modes = { { id = "zacui", label = "ZacUI look" }, { id = "classic", label = "Classic look" } },
        modesLabel = "Look",
        build = BuildPreview,
        update = UpdatePreview,
    })

    L:Card("Talents")
    local talents = UI.Checkbox(L.current, "Use ZacUI's talent tree", ModuleOn("talentswin"), function(v)
        ZacUIDB.modules = ZacUIDB.modules or {}
        ZacUIDB.modules.talentswin = v and true or false
        if v and ns.Modules and ns.Modules.talentswin then pcall(ns.Modules.talentswin) end
        if CT.Apply then CT.Apply() end
    end, { tooltip = "On: the three trees side by side, with prerequisite arrows and ranks. Off: the game's own talent page." })
    L:Row(talents, 17)
    L:Desc("Click picks a rank, right-click takes a pick back, and Learn (it asks first) learns them all at once. "
        .. "Not in combat. Picks you never learned are dropped when the window closes. \"Game's view\" in the "
        .. "window's footer shows the game's own page until you next open it - switching spec lives there.")
    L:EndCard()

    L:Card("Spellbook")
    local book = UI.Checkbox(L.current, "Use ZacUI's spellbook", ModuleOn("spellbookwin"), function(v)
        ZacUIDB.modules = ZacUIDB.modules or {}
        ZacUIDB.modules.spellbookwin = v and true or false
        if v then
            if ns.EnableModuleLive then ns.EnableModuleLive("spellbookwin") end
        elseif ns.Print then
            ns.Print("Spellbook off - /reload to bring back the game's own book.")
        end
    end, { tooltip = "One searchable list of every spell, filtered by school, with every rank when you ask for it." })
    L:Row(book, 17)
    L:Desc("\"All ranks\" in the book is the game's Show all spell ranks switch (not offered to warriors and "
        .. "rogues, as in the game's own book); each row casts its own rank. Turning the book off takes a /reload.")
    L:EndCard()
end)
