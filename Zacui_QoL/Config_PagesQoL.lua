-- Config_PagesQoL - the Quality of life page. Everything the QoL
-- module reads is editable here; the defaults ARE the audited Leatrix
-- Plus setup (the 11 features that were actually running).
-- Part of ZacUI; load order is set by the TOC.

local ADDON_NAME = ...
-- Zacui_QoL is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

-- shared state from earlier ZacUI files
local Print = ns.Print
local RegisterPage = ns.RegisterPage
local UI = ns.UI

local M, F = UI.M, UI.F

local function Refresh()
    local QoL = ns.QoL
    if QoL and QoL.Refresh then QoL.Refresh() end
end

local function BindCheck(L, tbl, key, label, desc)
    local w = UI.Checkbox(L.current, label, tbl[key] and true or false,
        function(v)
            tbl[key] = v and true or false
            Refresh()
        end)
    L:Row(w, 17)
    if desc then L:Desc(desc) end
    return w
end

local function BindSlider(L, tbl, key, label, opts)
    opts = opts or {}
    local w = UI.Slider(L.current, {
        width = 200, min = opts.min, max = opts.max, step = opts.step or 1,
        value = tbl[key], label = label, format = opts.format,
        onChange = function(v)
            tbl[key] = v
            Refresh()
        end,
    })
    L:Row(w, 40)
    if opts.desc then L:Desc(opts.desc) end
    return w
end

-- ============================================================
-- BOSS PARTICLES - the per-boss particle density card. One raid shows
-- at a time (a dropdown picks it; the choice lives in the config state
-- so the page rebuild lands on the same raid), with one row per boss:
-- the tick, and a seconds box for how long particles stay up after the
-- kill. Naxx bosses wear their wing colour, as the WA's list did.
-- ============================================================
local WING_COLORS = {
    spider    = "33ccff",
    plague    = "ff9933",
    military  = "33cc66",
    construct = "ff66cc",
    frostwyrm = "ffcc33",
}

local DENSITY_NAMES = { [0] = "0 off", "1 low", "2 fair", "3 good", "4 high", "5 ultra" }
local function DensityLabel(v)
    return DENSITY_NAMES[v] or tostring(v)
end

local function BossParticlesCard(L, QoL)
    L:Card("Boss particles")
    if not QoL.BossFXState then
        L:Desc("The boss particles module did not load.")
        L:EndCard()
        return
    end
    local st = QoL.BossFXState()
    local raids = QoL.BossFXRaids

    BindCheck(L, st, "enabled", "Per-boss particle density",
        "Your particle WeakAura, native. In a raid the particle density "
        .. "sits at the raid level below (0 = off, for FPS on trash); "
        .. "when a ticked boss starts it jumps to the encounter level so "
        .. "particle mechanics stay visible, and drops back at the end - "
        .. "after the linger, for fights whose ground effects outlive "
        .. "the boss. Outside raids the world level below is set, or your "
        .. "own setting is put back exactly when that is off.")
    L:Desc(st.active
        and ("Currently HOLDING - the raid level is in; "
            .. (st.worldEnabled and ("the world level (" .. DensityLabel(st.worldDensity) .. ")")
                or ("your normal particle density (" .. tostring(st.saved) .. ")"))
            .. " comes back when you leave.")
        or "Currently idle - it arms itself when you zone into a raid.")
    BindSlider(L, st, "raidDensity", "Raid level (between bosses)",
        { min = 0, max = 5, format = DensityLabel })
    BindSlider(L, st, "encounterDensity", "Encounter level (ticked bosses)",
        { min = 0, max = 5, format = DensityLabel })
    BindCheck(L, st, "worldEnabled", "Set a level outside raids too",
        "Open world, dungeons and battlegrounds get the level below the moment you "
        .. "zone out of a raid, instead of whatever the raid happened to capture as "
        .. "your \"original\" - which is how particles got stuck on the lowest setting.")
    BindSlider(L, st, "worldDensity", "World level (open world, dungeons)",
        { min = 0, max = 5, format = DensityLabel })

    -- which raid the rows below belong to
    local cfg = ns.ConfigState and ns.ConfigState() or {}
    local shown
    for _, raid in ipairs(raids) do
        if raid.key == cfg.bossFXRaid then shown = raid end
    end
    shown = shown or raids[1]

    L:Gap(4)
    local dd = UI.Dropdown(L.current, { width = 200,
        items = function()
            local items = {}
            for _, raid in ipairs(raids) do
                items[#items + 1] = { text = raid.label, value = raid.key }
            end
            return items
        end,
        selected = function() return shown.label end,
        selectedValue = function() return shown.key end,
        onSelect = function(v)
            cfg.bossFXRaid = v
            if ns.RefreshConfig then ns.RefreshConfig() end
        end,
    })
    L:Row(dd, 30)

    local r = QoL.BossFXRaidState(shown)
    BindCheck(L, r, "enabled", "Manage " .. shown.label,
        shown.test
            and ("Testing only: while this is on, 5-man dungeons count as "
                .. "raids, so the Stockades bosses run the whole cycle - "
                .. "raid level on entry, encounter level on the pull, "
                .. "linger, back down. Turn it off when you are done.")
            or nil)

    L:Desc("Ticked bosses get the encounter level. The box on the right "
        .. "is the linger: seconds particles stay up after the kill "
        .. "(Viscidus slime, Ouro residue). Blank or 0 means none.")

    local card = L.current
    -- the linger column: right of the longest boss name at this type size
    local LINGER_X = 270
    do
        local probe = UI.Font(card, F.LABEL, { text = "" })
        local widest = 0
        for _, boss in ipairs(shown.bosses) do
            probe:SetText(boss.name)
            widest = math.max(widest, math.ceil(probe:GetStringWidth() or 0))
        end
        probe:SetText("")
        probe:Hide()
        LINGER_X = math.max(LINGER_X, widest + 70)
    end
    local hdr = UI.Font(card, F.SMALL, { text = "linger (s)", cat = "text", key = "gray" })
    hdr:SetPoint("TOPLEFT", card, "TOPLEFT", LINGER_X, card._y)
    card._y = card._y - math.max(16, math.ceil(hdr:GetStringHeight() or 12) + 4)

    for _, boss in ipairs(shown.bosses) do
        local hex = boss.wing and WING_COLORS[boss.wing]
        local label = hex and ("|cff" .. hex .. boss.name .. "|r") or boss.name
        local id = boss.id
        local y = card._y
        local cb = UI.Checkbox(card, label, r.bosses[id] == true,
            function(v)
                r.bosses[id] = v and true or nil
                Refresh()
            end)
        L:Row(cb, 24)
        local secs = tonumber(r.linger[id])
        local eb = UI.EditBox(card, { width = 44,
            text = (secs and secs > 0) and tostring(secs) or "",
            onChange = function(v)
                local n = tonumber(v)
                if n and n > 0 then
                    r.linger[id] = math.min(120, math.floor(n))
                else
                    r.linger[id] = nil
                end
            end })
        eb:SetPoint("TOPLEFT", card, "TOPLEFT", LINGER_X, y + 4)
    end

    L:Gap(6)
    BindCheck(L, st, "chat", "Print encounter IDs to chat",
        "Every ENCOUNTER_START and END with its id, plus each density "
        .. "change. If a boss never triggers, this shows the id to fix "
        .. "in QoL_BossFX.lua.")
    L:EndCard()
end

-- where there is no buff limit (Core_Flavor, buff_remover) the page has
-- no Buffs tab, so its words do not find the page either; the same for
-- the Snowball button's words where it is not needed (snowball)
if ns.FeatureOn and not ns.FeatureOn("buff_remover") and ns.FindMenuItem then
    local item = ns.FindMenuItem("qol")
    if item and type(item.keywords) == "string" then
        item.keywords = item.keywords:gsub("%s*buff remover cancelaura", "")
    end
end
if ns.FeatureOn and not ns.FeatureOn("snowball") and ns.FindMenuItem then
    local item = ns.FindMenuItem("qol")
    if item and type(item.keywords) == "string" then
        item.keywords = item.keywords:gsub("%s*snowball snow airborne jump", "")
    end
end

-- ============================================================
-- BUFFS - the buff remover (QoL_BuffRemover.lua). The counting is
-- Readycheck's; this tab is only the ticks, the switches and the macros.
-- ============================================================
local function RefreshPage()
    if ns.RefreshConfig then ns.RefreshConfig() end
end

local function MacroNames()
    local out = {}
    local total = (MAX_ACCOUNT_MACROS or 120) + (MAX_CHARACTER_MACROS or 18)
    for i = 1, total do
        local name = GetMacroInfo(i)
        if name and name ~= "" then out[#out + 1] = name end
    end
    table.sort(out)
    return out
end

local function BuffsTab(L, QoL)
    local BR = QoL.BuffRemover
    local rc = _G.Readycheck
    local D = rc and rc.BuffCapData
    L:Card("Buff remover")
    if not BR then
        L:Desc("The buff remover did not load.")
        L:EndCard()
        return
    end
    if not (BR.HasCounter() and D) then
        L:Desc("Needs Readycheck: the buff counting, hidden slots included, "
            .. "lives in its stats bar. Turn Readycheck on and reload.")
        L:EndCard()
        return
    end
    if BR.CounterHere and not BR.CounterHere() then
        L:Desc("Waits for Readycheck: its buff counter does not run on "
            .. (ns.FlavorName and ns.FlavorName() or "this game") .. " yet.")
    end
    local b = BR.Cfg()
    local c = BR.ClassCfg()
    local cls = select(2, UnitClass("player"))
    local cfg = ns.ConfigState and ns.ConfigState() or {}

    BindCheck(L, b, "enabled", "Remove the buffs ticked below",
        "So the 32-buff cap never pushes off a flask or a world buff to make "
        .. "room for one you never wanted. Readycheck's stats bar shows Keep or "
        .. "Remove beside every buff (click its Buffs cell); a click there "
        .. "switches it too.")
    BindCheck(L, b, "auto", "Out of combat, take them off as soon as they land", nil)
    if cls == "WARRIOR" or cls == "DRUID" or cls == "PALADIN" then
        BindCheck(L, c, "salv", "Drop Blessing of Salvation while tanking",
            "Defensive Stance, bear form or Righteous Fury. Pausing does not stop this.")
    end
    local paused = BR.Paused()
    local pb = UI.Button(L.current, paused and "Resume removal" or "Pause removal", { width = 140,
        onClick = function()
            BR.SetPaused(not BR.Paused())
            RefreshPage()
        end })
    L:Row(pb, 30)
    local n = 0
    for _ in pairs(c.remove) do n = n + 1 end
    for _ in pairs(c.names) do n = n + 1 end
    if not BR.Running() then
        L:Desc("Off right now.")
    elseif paused then
        L:Desc("Paused on this character: nothing is removed except Salvation while tanking. "
            .. "Shift-clicking Readycheck's Buffs cell pauses and resumes as well.")
    else
        L:Desc(n .. " buff(s) ticked for your class. Ticks are per class, so each class keeps its own list.")
    end
    L:EndCard()

    -- ============================================================
    L:Card("In combat")
    BindCheck(L, b, "combat", "Load the ticked buffs into linked macros",
        "Addons cannot cancel a buff in a fight; a key press can. Link the "
        .. "macros you press all fight (your main attack) and each gets "
        .. "/click lines under a #ZB line: every press then cancels "
        .. "the ticked buffs you have. The lines are written before each "
        .. "fight and taken back out when you unlink a macro or switch this off.")
    local ch = BR.Char()
    local st = BR.Status()
    for _, name in ipairs(ch.macros) do
        local label = name
        if st.missing and st.missing[name] then label = label .. "  |cffe04d4d(no macro by that name)|r" end
        local bks = BR.Backups()
        if bks[name] or bks[name .. (BR.CHAR_COPY or "")] then label = label .. "  |cff8a90a0(its /cancelaura lines moved in)|r" end
        local fs = UI.Font(L.current, F.LABEL, { text = label })
        local un = UI.Button(L.current, "Unlink", { width = 70,
            onClick = function()
                if BR.Unlink(name) == "combat" then Print("buffs: not in combat.") end
                RefreshPage()
            end })
        L:Row(un, 28)
        fs:SetPoint("LEFT", un, "RIGHT", 10, 0)
    end
    if #ch.macros < BR.MAX_LINKED then
        local dd = UI.Dropdown(L.current, { width = 220,
            items = function()
                local items = {}
                for _, name in ipairs(MacroNames()) do
                    if not BR.IsLinked(name) then items[#items + 1] = { text = name, value = name } end
                end
                return items
            end,
            selected = function() return "Link a macro..." end,
            selectedValue = function() return nil end,
            onSelect = function(v)
                local r = BR.Link(v)
                if r == "combat" then Print("buffs: not in combat.") end
                RefreshPage()
            end,
        })
        L:Row(dd, 30)
    end
    if BR.ATTACKS and BR.ATTACKS[cls] and BR.AutoLink then
        local auto = UI.Button(L.current, "Link the attack macros on my bars", { width = 240,
            tooltip = "Finds the macros on your action bars that cast Bloodthirst, Whirlwind, "
                .. "Sunder Armor, Heroic Strike, Cleave, Execute and the like, and links them "
                .. "(up to " .. BR.MAX_LINKED .. ", the ones already linked stay).",
            onClick = function()
                local added = BR.AutoLink(false)
                if added == nil then
                    Print("buffs: not in combat.")
                elseif #added == 0 then
                    Print("buffs: no more attack macros on your bars to link.")
                else
                    Print("buffs: linked " .. table.concat(added, ", ") .. ".")
                end
                RefreshPage()
            end })
        L:Row(auto, 30)
    end
    if #ch.macros > 0 then
        local line = (st.names or 0) .. " name(s) loaded on " .. (st.lines or 0) .. " line(s)."
        if st.ownButton then
            line = line .. " " .. st.ownButton .. " has a line to itself, so it goes on every press."
        end
        if st.limit then
            line = line .. " The macro " .. st.limit .. " only had room for " .. (st.lines or 0)
                .. " line(s): its own /cancelaura lines take the space. Take them over below."
        end
        L:Desc(line)
        local row = UI.Holder(L.current)
        row:SetSize(460, 24)
        local take = UI.Button(row, "Take over their /cancelaura lines", { width = 220,
            tooltip = "Every plain /cancelaura line in the linked macros becomes a name tick "
                .. "here (names set to always keep are skipped) and comes out of the macro, "
                .. "which leaves room for the remover's lines. The macros as they were are "
                .. "kept, and Put my macros back restores them.",
            onClick = function()
                local took, changed = BR.TakeOver()
                if took == nil then
                    Print("buffs: not in combat.")
                elseif #changed == 0 then
                    Print("buffs: the linked macros have no /cancelaura lines to take.")
                else
                    Print("buffs: took " .. #took .. " new name(s) from " .. table.concat(changed, ", ") .. ".")
                end
                RefreshPage()
            end })
        take:SetPoint("LEFT", row, "LEFT", 0, 0)
        if BR.HasBackups() then
            local back = UI.Button(row, "Put my macros back", { width = 150,
                tooltip = "Restores every macro whose /cancelaura lines were taken over, exactly "
                    .. "as it was, and unlinks it. Your ticks stay.",
                onClick = function()
                    local done = BR.RestoreMacros()
                    if done == nil then Print("buffs: not in combat.")
                    else Print("buffs: put back " .. (#done > 0 and table.concat(done, ", ") or "nothing") .. ".") end
                    RefreshPage()
                end })
            back:SetPoint("LEFT", take, "RIGHT", 6, 0)
        end
        L:Row(row, 30)
    end
    L:EndCard()

    -- ============================================================
    L:Card("Buffs to remove")
    local search = cfg.buffSearch or ""
    local sb
    sb = UI.EditBox(L.current, { width = 220, text = search, hint = "Search buffs",
        onChange = function(text)
            cfg.buffSearch = text or ""
            cfg._buffSearchGen = (cfg._buffSearchGen or 0) + 1
            local mine = cfg._buffSearchGen
            C_Timer.After(0.3, function()
                if mine ~= cfg._buffSearchGen then return end
                cfg._buffSearchFocus = true
                RefreshPage()
            end)
        end })
    L:Row(sb, 30)
    -- the page rebuilds as you type; the new box takes the typing back
    if cfg._buffSearchFocus then
        cfg._buffSearchFocus = nil
        local eb = sb.editBox
        if eb then
            eb:SetFocus()
            if eb.SetCursorPosition then eb:SetCursorPosition(#search) end
        end
    end

    -- every row wears the buff's icon: the list entry's spell, the icon
    -- seen on you before, or the spell by that name; a question mark when
    -- none is known
    local GetTex = (C_Spell and C_Spell.GetSpellTexture) or GetSpellTexture
    local QUESTION = 134400
    local function Tex(spell)
        if not (spell and GetTex) then return nil end
        return GetTex(spell)
    end
    local function EntryIcon(e)
        for _, id in ipairs(e.ids or {}) do
            local t = Tex(id)
            if t then return t end
        end
        return nil
    end
    local byEntryName
    local function NameIcon(name)
        for _, sn in pairs(b.seen) do
            if sn.n == name and sn.i then return sn.i end
        end
        if not byEntryName then
            byEntryName = {}
            for _, e in ipairs(D.ALL) do
                if not byEntryName[e.name] then byEntryName[e.name] = e end
                for _, nm in ipairs(BR.NamesOf(e)) do
                    if not byEntryName[nm] then byEntryName[nm] = e end
                end
            end
        end
        local e = byEntryName[name]
        return (e and EntryIcon(e)) or Tex(name)
    end
    local function KeyIcon(key)
        local e = D.BY_KEY and D.BY_KEY[key]
        if e then return EntryIcon(e) end
        local sn = b.seen[key]
        return (sn and sn.i) or Tex(key)
    end
    local function WithIcon(tex, label)
        return "|T" .. tostring(tex or QUESTION) .. ":16:16:0:0:64:64:5:59:5:59|t " .. label
    end

    -- When each ticked buff goes: out of combat, in combat or both, and a
    -- separate tick for "only while a world buff is on you". Shown beside
    -- the tick while it is ticked; a fresh tick starts at Both, not held.
    -- (2026-10-31, Zac: the six-way list "is kinda confusing to use")
    local WHEN = {
        { text = "Both", value = "both" },
        { text = "Out of combat", value = "ooc" },
        { text = "In combat", value = "combat" },
    }
    local function WhenText(v)
        for _, w in ipairs(WHEN) do if w.value == v then return w.text end end
        return WHEN[1].text
    end
    local function WhenPicker(cb, get, set, ticked)
        local dd = UI.Dropdown(L.current, { width = 120,
            items = function()
                local items = {}
                for _, w in ipairs(WHEN) do items[#items + 1] = { text = w.text, value = w.value } end
                return items
            end,
            selected = function() return WhenText(get()) end,
            selectedValue = function() return get() end,
            onSelect = function(v) set(v) end,
        })
        dd:SetPoint("LEFT", cb, "RIGHT", 10, 0)
        dd:SetShown(ticked)
        return dd
    end
    local function WbTick(dd, get, set, ticked)
        local wb = UI.Checkbox(L.current, "while WBs out", get(), function(v) set(v) end,
            { tooltip = "Only while a world buff is on you (Ony, Rend, Zandalar, Songflower, DMF, Darkmoon Faire...). "
                .. "Untick it and the buff goes whether or not you have world buffs." })
        wb:SetPoint("LEFT", dd, "RIGHT", 8, 0)
        wb:SetShown(ticked)
        return wb
    end
    local function Tick(key, label)
        local dd, wb
        local cb = UI.Checkbox(L.current, WithIcon(KeyIcon(key), label), c.remove[key] == true,
            function(v)
                BR.SetRemove(key, v)
                if dd then dd:SetShown(v and true or false) if v then dd:SetText(WhenText("both")) end end
                if wb then wb:SetShown(v and true or false) if v then wb:SetChecked(false) end end
            end)
        L:Row(cb, 24)
        dd = WhenPicker(cb, function() return BR.Phase(key) end,
            function(v) BR.SetPhase(key, v) end, c.remove[key] == true)
        wb = WbTick(dd, function() return BR.Wb(key) end,
            function(v) BR.SetWb(key, v) end, c.remove[key] == true)
    end
    local function NameTick(name, label)
        local dd, wb
        local cb = UI.Checkbox(L.current, WithIcon(NameIcon(name), label or name), c.names[name] == true,
            function(v)
                BR.SetName(name, v)
                if dd then dd:SetShown(v and true or false) if v then dd:SetText(WhenText("both")) end end
                if wb then wb:SetShown(v and true or false) if v then wb:SetChecked(false) end end
            end)
        L:Row(cb, 24)
        dd = WhenPicker(cb, function() return BR.PhaseName(name) end,
            function(v) BR.SetPhaseName(name, v) end, c.names[name] == true)
        wb = WbTick(dd, function() return BR.WbName(name) end,
            function(v) BR.SetWbName(name, v) end, c.names[name] == true)
    end
    local function EntryLabel(e)
        local label = e.name
        if e.note then label = label .. "  |cff8a90a0" .. e.note .. "|r" end
        if e.group and D.GROUP_LABEL[e.group] then
            label = label .. "  |cff8a90a0" .. D.GROUP_LABEL[e.group] .. "|r"
        end
        local kept = c.keep[e.name]
        if not kept then
            for _, nm in ipairs(BR.NamesOf(e)) do
                if c.keep[nm] then kept = true break end
            end
        end
        if kept then label = label .. "  |cff4dcc66(always kept)|r" end
        return label
    end

    local q = search:lower():gsub("^%s+", ""):gsub("%s+$", "")
    if q ~= "" then
        local shown, MAXROWS = 0, 60
        local exact = false
        for _, e in ipairs(D.ALL) do
            if shown < MAXROWS and BR.Visible(e) and not BR.Fixed(e) and e.name:lower():find(q, 1, true) then
                shown = shown + 1
                if e.byName then NameTick(e.name, EntryLabel(e)) else Tick(e.key, EntryLabel(e)) end
            end
            if e.name:lower() == q then exact = true end
        end
        local seen = {}
        for id, sn in pairs(b.seen) do
            if sn.n and not D.BY_ID[id] and sn.n:lower():find(q, 1, true) then seen[#seen + 1] = { id = id, n = sn.n } end
        end
        table.sort(seen, function(x, y) return x.n < y.n end)
        for _, it in ipairs(seen) do
            if shown < MAXROWS then
                shown = shown + 1
                Tick(it.id, it.n .. "  |cff8a90a0had it before|r")
            end
            if it.n:lower() == q then exact = true end
        end
        for name in pairs(c.names) do
            if name:lower():find(q, 1, true) and shown < MAXROWS and not D.BY_NAME[name] then
                shown = shown + 1
                NameTick(name, name .. "  |cff8a90a0by name|r")
            end
            if name:lower() == q then exact = true end
        end
        if shown == 0 then L:Desc("Nothing in the list matches.") end
        if shown >= MAXROWS then L:Desc("More match - type a little more.") end
        if not exact then
            local typed = search:gsub("^%s+", ""):gsub("%s+$", "")
            local add = UI.Button(L.current, "Remove any buff called \"" .. typed .. "\"", { width = 300,
                tooltip = "For a buff the list does not have. It matches the buff's name exactly, "
                    .. "the way a /cancelaura line does.",
                onClick = function()
                    BR.SetName(typed, true)
                    RefreshPage()
                end })
            L:Row(add, 30)
        end
    else
        local shownCat
        for _, cat in ipairs(D.CATEGORIES) do
            if cat.id == cfg.buffCat then shownCat = cat end
        end
        shownCat = shownCat or D.CATEGORIES[1]
        local dd = UI.Dropdown(L.current, { width = 220,
            items = function()
                local items = {}
                for _, cat in ipairs(D.CATEGORIES) do items[#items + 1] = { text = cat.label, value = cat.id } end
                return items
            end,
            selected = function() return shownCat.label end,
            selectedValue = function() return shownCat.id end,
            onSelect = function(v)
                cfg.buffCat = v
                RefreshPage()
            end,
        })
        L:Row(dd, 30)
        L:Desc("Ticked buffs are removed. Not listed: auras and totems another player "
            .. "keeps up, buffs the game will not cancel, and other classes' own buffs.")
        local any = false
        if shownCat.id == "seen" then
            local list = {}
            for id, sn in pairs(b.seen) do
                if sn.n and not D.BY_ID[id] then list[#list + 1] = { id = id, n = sn.n } end
            end
            table.sort(list, function(x, y) return x.n < y.n end)
            for _, it in ipairs(list) do
                any = true
                Tick(it.id, it.n)
            end
            if not any then L:Desc("Buffs you have had that are not in the list above show up here.") end
        else
            for _, e in ipairs(D.ALL) do
                if e.cat == shownCat.id and BR.Visible(e) and not BR.Fixed(e) then
                    any = true
                    if e.byName then NameTick(e.name, EntryLabel(e)) else Tick(e.key, EntryLabel(e)) end
                end
            end
            if not any then L:Desc("Nothing here for your class.") end
        end
    end
    L:EndCard()

    -- ============================================================
    L:Card("By name")
    L:Desc("Names match a buff exactly, the way a /cancelaura line does. Always keep "
        .. "beats every tick: a kept name is never removed, in or out of combat.")
    local names, keeps = {}, {}
    -- a buff the list matches by name (the healers' tier-set procs) is
    -- ticked in its own list above; showing it here too doubled it
    for nm in pairs(c.names) do
        if not (D.BY_NAME and D.BY_NAME[nm]) then names[#names + 1] = nm end
    end
    for nm in pairs(c.keep) do keeps[#keeps + 1] = nm end
    table.sort(names)
    table.sort(keeps)
    for _, nm in ipairs(names) do NameTick(nm) end
    for _, nm in ipairs(keeps) do
        local cb = UI.Checkbox(L.current, WithIcon(NameIcon(nm), "Always keep: " .. nm), true,
            function(v) BR.SetKeep(nm, v) RefreshPage() end)
        L:Row(cb, 22)
    end
    if #names == 0 and #keeps == 0 then L:Desc("None yet.") end
    local row = UI.Holder(L.current)
    row:SetSize(460, 24)
    local nb = UI.EditBox(row, { width = 200, text = cfg.buffNameDraft or "", hint = "A buff's name",
        onChange = function(t) cfg.buffNameDraft = t end })
    nb:SetPoint("LEFT", row, "LEFT", 0, 0)
    local function Draft()
        local t = (cfg.buffNameDraft or ""):gsub("^%s+", ""):gsub("%s+$", "")
        return t
    end
    local goB = UI.Button(row, "Remove it", { width = 90, onClick = function()
        local t = Draft()
        if t ~= "" then BR.SetName(t, true) cfg.buffNameDraft = nil RefreshPage() end
    end })
    goB:SetPoint("LEFT", nb, "RIGHT", 6, 0)
    local keepB = UI.Button(row, "Always keep", { width = 100, onClick = function()
        local t = Draft()
        if t ~= "" then BR.SetKeep(t, true) cfg.buffNameDraft = nil RefreshPage() end
    end })
    keepB:SetPoint("LEFT", goB, "RIGHT", 6, 0)
    L:Row(row, 30)
    L:EndCard()

    -- ============================================================
    L:Card("Import / export")
    L:Desc("The whole setup as one line of text: the ticks, the names, the always-keep "
        .. "names and the linked macros. Export, then paste it on another character "
        .. "(or into any ZacUI or Readycheck import box).")
    local box = UI.TextBox(L.current, { width = 440, height = 60, text = cfg.buffImportDraft or "",
        selectOnFocus = true, onChange = function(t) cfg.buffImportDraft = t end })
    L:Row(box, 66)
    local Import = ns.Import
    if Import and Import.StatusRow then Import.StatusRow(L, box, "buffs") end
    local ie = UI.Holder(L.current)
    ie:SetSize(460, 24)
    local impB = UI.Button(ie, "Import", { width = 90, onClick = function()
        local text = box:GetText() or ""
        if Import and Import.Offer then
            Import.Offer(text, { onDone = function() cfg.buffImportDraft = nil RefreshPage() end })
        end
    end })
    impB:SetPoint("LEFT", ie, "LEFT", 0, 0)
    local expB = UI.Button(ie, "Export", { width = 90, onClick = function()
        local text = BR.Export()
        cfg.buffImportDraft = text
        box:SetText(text)
        if box.editBox then
            box.editBox:SetFocus()
            box.editBox:HighlightText()
        end
    end })
    expB:SetPoint("LEFT", impB, "RIGHT", 6, 0)
    L:Row(ie, 30)
    L:EndCard()
end

-- ============================================================
-- MACROS - the unused-macro list (QoL_MacroCleanup.lua). Nothing goes
-- unless a button here is pressed, and everything that goes is binned.
-- ============================================================
local function MacrosTab(L, QoL)
    local MC = QoL.MacroCleanup
    L:Card("Unused macros")
    if not MC then
        L:Desc("The macro cleanup did not load.")
        L:EndCard()
        return
    end
    local account, mine, seen = MC.Unused()
    L:Desc("A macro counts as used when it is on one of your action bars or a key is "
        .. "bound to it. Account macros are shared, so one is listed only when no "
        .. "character seen so far uses it. Characters seen on this account: "
        .. (#seen > 0 and table.concat(seen, ", ") or "none yet")
        .. ". Log into every character on this account once before trusting the account list.")
    L:Desc("Deleting puts the macro in the bin below first; Restore makes it again.")

    local function Row(m)
        local row = UI.Holder(L.current)
        row:SetSize(460, 22)
        local del = UI.Button(row, "Delete", { width = 64, onClick = function()
            local ok, why = MC.Delete(m)
            if not ok then Print("macros: " .. tostring(why)) end
            RefreshPage()
        end })
        del:SetPoint("LEFT", row, "LEFT", 0, 0)
        local fs = UI.Font(row, F.LABEL, { text = m.name .. "  |cff8a90a0" .. MC.Preview(m.body) .. "|r" })
        fs:SetPoint("LEFT", del, "RIGHT", 8, 0)
        L:Row(row, 26)
    end
    local function DeleteAll(list, what)
        local n = #list
        if n == 0 then return end
        local btn = UI.Button(L.current, "Delete all " .. n .. " " .. what, { width = 220, onClick = function()
            UI.Confirm({
                title = "Delete macros",
                text = "Delete these " .. n .. " " .. what .. "? Each goes into the bin first, "
                    .. "and Restore there makes it again.",
                acceptText = "Delete",
                onAccept = function()
                    local done = MC.DeleteAll(list)
                    Print("macros: deleted " .. done .. " (they are in the bin on the Macros tab).")
                    RefreshPage()
                end,
            })
        end })
        L:Row(btn, 30)
    end

    L:Gap(4)
    L:Desc("|cffffd100Account macros on no seen character's bars or keys (" .. #account .. ")|r")
    if #account == 0 then L:Desc("None.") end
    for _, m in ipairs(account) do Row(m) end
    DeleteAll(account, "account macros")
    L:Gap(4)
    L:Desc("|cffffd100This character's own macros it does not use (" .. #mine .. ")|r")
    if #mine == 0 then L:Desc("None.") end
    for _, m in ipairs(mine) do Row(m) end
    DeleteAll(mine, "character macros")
    local retired, keptMount = {}, {}
    if MC.Retired then retired, keptMount = MC.Retired() end
    keptMount = keptMount or {}
    if #retired > 0 or #keptMount > 0 then
        L:Gap(4)
        L:Desc("|cffffd100Old mount macros the smart mount macro replaces (" .. #retired .. ")|r")
        L:Desc("Other macros with its name, and macros that are nothing but mount lines, "
            .. "on no character's bars. Deleting a macro empties every bar slot it sat in, so one "
            .. "still on a bar is not offered: this character's bar slots are given the smart macro "
            .. "automatically (/zui mount does it now), another character's when that character logs in.")
        for _, m in ipairs(retired) do Row(m) end
        DeleteAll(retired, "old mount macros")
        for _, m in ipairs(keptMount) do
            local who = m.usedBy == "you" and "on your bars" or ("on the bars of " .. tostring(m.usedBy))
            L:Desc("|cff8a90a0kept:|r " .. m.name .. "  |cff8a90a0" .. who .. "|r")
        end
    end
    L:EndCard()

    L:Card("Bin")
    local bin = MC.Bin()
    if #bin == 0 then L:Desc("Empty.") end
    for i = #bin, 1, -1 do
        local m = bin[i]
        local row = UI.Holder(L.current)
        row:SetSize(460, 22)
        local rb = UI.Button(row, "Restore", { width = 70, onClick = function()
            local ok, why = MC.Restore(i)
            if not ok then Print("macros: " .. tostring(why)) end
            RefreshPage()
        end })
        rb:SetPoint("LEFT", row, "LEFT", 0, 0)
        local fs = UI.Font(row, F.LABEL, { text = m.name .. "  |cff8a90a0"
            .. (m.account and "account" or "character") .. " macro, from " .. tostring(m.who) .. "|r" })
        fs:SetPoint("LEFT", rb, "RIGHT", 8, 0)
        L:Row(row, 26)
    end
    L:EndCard()
end

-- ============================================================
-- LOOT - the auto-roll tab (QoL_AutoRoll.lua).
-- ============================================================
local function LootTab(L, QoL)
    local AR = QoL.AutoRoll
    L:Card("Auto roll")
    if not AR then
        L:Desc("The auto-roll module did not load.")
        L:EndCard()
        return
    end
    local a = AR.DB()
    BindCheck(L, a, "enabled", "Roll on group loot for me",
        "Answers the roll box the moment it appears, by the rules below. "
        .. "Replaces the two auto-roll auras.")
    BindCheck(L, a, "raidsOnly", "  ... only inside raid instances",
        "Off, and it rolls in dungeons and the open world too.")
    BindCheck(L, a, "announce", "  ... say what it rolled in chat", nil)
    BindCheck(L, a, "filterChat", "  ... hide the roll chatter for those items",
        "Hides 'X has selected Need for: [item]' for items it rolled on. "
        .. "Who received the item still shows.")
    L:EndCard()

    -- a dropdown of the four choices, bound to tbl[key]
    -- (the dropdown goes under its label when the card is too narrow)
    local function ChoiceRow(tbl, key, label)
        local dd = UI.Dropdown(L.current, { width = 190,
            items = function()
                local items = {}
                for _, c in ipairs(AR.CHOICES) do
                    items[#items + 1] = { text = c.label, value = c.value }
                end
                return items
            end,
            selected = function() return AR.CHOICE_LABEL[tbl[key] or "ask"] end,
            selectedValue = function() return tbl[key] or "ask" end,
            onSelect = function(v) tbl[key] = v end,
        })
        L:Labeled(label, dd, 200, { gap = 6 })
    end

    L:Card("By quality")
    L:Desc("Used when no item rule below matches. 'Ask' leaves the roll "
        .. "box for you.")
    for _, q in ipairs(AR.QUALITIES) do
        ChoiceRow(a.quality, q.key, q.label)
    end
    L:EndCard()

    -- (options audit 2026-11-09) the known sets are Classic raid drops
    -- (Zul'Gurub coins and bijous, Naxxramas scraps): none of them drops on
    -- Retail, so the card is not shown there (saved choices stay)
    -- (2026-11-09, Zac: "forever has no raids yet": not there either)
    if not (ns.Flavor and (ns.Flavor() == "retail" or ns.Flavor() == "forever")) then
        L:Card("Known items")
        L:Desc("One choice for the whole set. These win over the quality rule.")
        for _, g in ipairs(AR.GROUPS) do
            ChoiceRow(a.groups, g.key, g.label)
        end
        L:EndCard()
    end

    L:Card("Your items")
    L:Desc("Specific items, by id or by shift-clicking a link into the "
        .. "box. These win over everything.")
    local cfg = ns.ConfigState and ns.ConfigState() or {}
    local box = UI.EditBox(L.current, { width = 200, text = cfg.autoRollDraft or "",
        hint = "item id or link",
        onChange = function(t) cfg.autoRollDraft = t end })
    local add = UI.Button(L.current, "Add", { width = 60, onClick = function()
        local t = box:GetText() or ""
        if t == "" then return end
        local ok, why = AR.AddCustom(t, "pass")
        if not ok then Print("auto-roll: " .. tostring(why)) return end
        cfg.autoRollDraft = nil
        RefreshPage()
    end })
    L:Flow({ box, add }, 8, 8)
    if #a.custom == 0 then L:Desc("None yet.") end
    -- name | choice | Remove: Remove holds the right edge, the choice sits
    -- before it, and the name (cut short, whole on hover) takes the rest
    local rowW = math.min(460, L:Room())
    local ddW = math.min(170, math.max(90, rowW - 70 - 8 - 8 - 120))
    local nameW = math.max(40, rowW - 70 - 8 - ddW - 8)
    for _, c in ipairs(a.custom) do
        local r = UI.Holder(L.current)
        r:SetSize(rowW, 26)
        r:EnableMouse(true)
        local fs = UI.Font(r, F.LABEL, { text = AR.CustomName(c)
            .. "  |cff8a90a0" .. tostring(c.id) .. "|r" })
        fs:SetPoint("LEFT", r, "LEFT", 0, 0)
        fs:SetWidth(nameW)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        UI.TruncTip(fs, r)
        local dd = UI.Dropdown(r, { width = ddW,
            items = function()
                local items = {}
                for _, ch in ipairs(AR.CHOICES) do
                    items[#items + 1] = { text = ch.label, value = ch.value }
                end
                return items
            end,
            selected = function() return AR.CHOICE_LABEL[c.roll or "ask"] end,
            selectedValue = function() return c.roll or "ask" end,
            onSelect = function(v) c.roll = v end,
        })
        local rm = UI.Button(r, "Remove", { width = 70, onClick = function()
            AR.RemoveCustom(c.id)
            RefreshPage()
        end })
        rm:SetPoint("RIGHT", r, "RIGHT", 0, 0)
        dd:SetPoint("RIGHT", rm, "LEFT", -8, 0)
        L:Row(r, 30)
    end
    L:EndCard()
end

-- ============================================================
-- THE THINGS ON SCREEN - the GCD tracker, the pull and break timers and
-- the Snowball button. Each tab: a live preview in the dock, built with
-- the module's own constructors and fake data, then its settings as
-- cards in ZacUI's usual order - General, Look, Text, Animation,
-- Position, Advanced.
-- ============================================================
local function Changed(source)
    if ns.SettingsChanged then ns.SettingsChanged(source or "qol") end
end

-- what is on screen follows every change, once per frame
local Restyle = ns.Coalesce and ns.Coalesce(function()
    local QoL = ns.QoL
    if not QoL then return end
    if QoL.GCDTracker and QoL.GCDTracker.Restyle then QoL.GCDTracker.Restyle() end
    if QoL.RaidTimers and QoL.RaidTimers.Restyle then QoL.RaidTimers.Restyle() end
    if QoL.Snowball and QoL.Snowball.Restyle then QoL.Snowball.Restyle() end
end)
if Restyle and ns.OnSettingsChanged then ns.OnSettingsChanged(function() Restyle() end) end

local function Px(v) return v .. " px" end
local function Secs(v) return string.format("%.2fs", v) end
local function Pct(v) return v .. "%" end
local function R2(v) return math.floor(v * 100 + 0.5) / 100 end

-- a slider bound to tbl[key], a row of its own
local function Slide(L, tbl, key, label, o)
    local w = UI.Slider(L.current, { width = o.width or 200, min = o.min, max = o.max, step = o.step or 1,
        value = tonumber(tbl[key]) or o.default or o.min, label = label, format = o.format,
        onChange = function(v)
            tbl[key] = (o.step and o.step < 1) and R2(v) or v
            if o.after then o.after(v) end
        end })
    L:Row(w, 40)
    if o.desc then L:Desc(o.desc) end
    return w
end

-- a colour bound to tbl[key] ({ r, g, b, a }); nil reads as `fallback()`
local function Colour(L, tbl, key, label, fallback, alpha, desc)
    local cp = UI.ColorPicker(L.current, { label = label, alpha = alpha,
        get = function()
            if type(tbl[key]) == "table" then return tbl[key] end
            return fallback()
        end,
        set = function(r, g, b, a) tbl[key] = { r = r, g = g, b = b, a = alpha and a or nil } end })
    L:Row(cp, 22)
    if desc then L:Desc(desc) end
    return cp
end

local function Pal(cat, key, a)
    return function()
        local c = ns.GetColor(cat, key)
        return { r = c.r, g = c.g, b = c.b, a = a or 1 }
    end
end
local function Fixed(r, g, b, a) return function() return { r = r, g = g, b = b, a = a or 1 } end end

-- a dropdown with a small label over it, bound to tbl[key]
local function Choice(L, tbl, key, label, items, width)
    local f = UI.Field(L.current, label, function(host)
        return UI.Dropdown(host, { width = width or 200,
            items = function() return items end,
            selected = function()
                for _, it in ipairs(items) do if it.value == tbl[key] then return it.text end end
                return items[1].text
            end,
            selectedValue = function() return tbl[key] end,
            onSelect = function(v) tbl[key] = v end })
    end, { width = width or 200 })
    L:Add(f, 6)
    return f
end

local function Check(L, tbl, key, label, desc, after)
    local w = UI.Checkbox(L.current, label, tbl[key] ~= false and tbl[key] ~= nil and true or false,
        function(v)
            tbl[key] = v and true or false
            if after then after(v) end
        end)
    L:Row(w, 17)
    if desc then L:Desc(desc) end
    return w
end

local function Reset(L, label, tbl, keys, defaults)
    local b = UI.Button(L.current, label, { width = 200, onClick = function()
        for _, k in ipairs(keys) do
            local v = defaults[k]
            tbl[k] = (type(v) == "table" and ns.CopySetting) and ns.CopySetting(v) or v
        end
        Changed("qol.reset")
        if ns.RefreshConfig then ns.RefreshConfig() end
    end })
    L:Row(b, M.BUTTON_H + 6)
    return b
end

local function EasingItems()
    local out = {}
    for _, e in ipairs(ns.Motion and ns.Motion.EASINGS or { { id = "linear", label = "Steady" } }) do
        out[#out + 1] = { text = e.label, value = e.id }
    end
    return out
end

-- Where one text sits: ZacUI's anchor picker over <tbl>.anchors.<key>
-- (nil = its built-in spot), with a time format when it has one; and the
-- preview's pick hook (a sample's text -> this tab, its group flashes).
local function Spot(L, owner, key, pickKey, label, def, targets, fmt)
    local ag, as = ns.CustomAccess(owner, "anchors", key)
    local o = { key = pickKey, label = label, anchorGet = ag, anchorSet = as, targets = targets,
        defaultTargetLabel = "Where it sits now", anchorMin = -40, anchorMax = 40,
        anchorDefaults = function() return def end }
    if fmt then
        local fg, fs = ns.CustomAccess(owner, "formats", fmt.key)
        o.formatGet, o.formatSet, o.formatKinds, o.formatDefaults = fg, fs, { time = true }, fmt.defaults
        o.formatSample = fmt.sample
    end
    return UI.TextElement(L, o)
end
local function PickTo(previewKey, prefix, tab)
    if not ns.CustomPick then return end
    ns.CustomPick.SetHandler(previewKey, function(el)
        if type(el) ~= "string" or el:sub(1, #prefix) ~= prefix then return end
        ZacUIDB.config = ZacUIDB.config or {}
        ZacUIDB.config.tabs = ZacUIDB.config.tabs or {}
        ZacUIDB.config.tabs.qol = tab
        ns.RefreshConfig()
    end)
end

-- ------------------------------------------------------------ GCD tracker
-- made-up casts for the preview: Bloodthirst, Whirlwind, Heroic Strike,
-- Sunder Armor, Execute, Hamstring
local GCD_ICONS = { 136012, 132369, 132282, 132363, 135358, 132316 }

local function GCDPreviewAdd(st, GT, d, state)
    st.k = (st.k or 0) % #GCD_ICONS + 1
    local now = GetTime()
    local last = st.list[#st.list]
    if state == "pressed" and last and last.state ~= "ok" and last.tex == GCD_ICONS[st.k] then
        last.n = last.n + 1
        last.at = now
        return false
    end
    st.list[#st.list + 1] = { tex = GCD_ICONS[st.k], state = state, at = now, n = 1 }
    while #st.list > d.count do table.remove(st.list, 1) end
    st.gcdAt = now
    return true
end

local function GCDSeed(st, GT, d, mode)
    wipe(st.list)
    local now = GetTime()
    local states = (mode == "presses") and { "ok", "fail", "ok", "pressed" } or { "ok", "ok", "ok", "ok" }
    for i, state in ipairs(states) do
        st.k = i
        st.list[#st.list + 1] = { tex = GCD_ICONS[i], state = state, at = now - (#states - i) * 1.1,
            n = (state == "fail") and 3 or 1 }
    end
    st.gcdAt = now - 0.6
    st.seeded = mode
end

local function GCDPreview(L, GT)
    local d = GT.DB()
    L:Preview({
        key = "qol.gcd",
        title = "GCD tracker",
        width = math.max(240, math.min(600, d.count * (d.size + (tonumber(d.gap) or 2)) + 40)),
        height = math.max(50, d.size + 34),
        modes = { { id = "casts", label = "What went off" }, { id = "presses", label = "With presses" } },
        build = function(canvas, P)
            local st = P.store
            st.list = {}
            st.row = GT.NewRow(canvas)
            st.row.holder:SetPoint("CENTER", canvas, "CENTER", 0, 0)
            st.note = UI.Font(canvas, F.SMALL, { cat = "text", key = "orange", justify = "CENTER" })
            st.note:SetPoint("BOTTOM", canvas, "BOTTOM", 0, 2)
            -- a cast every so often, the presses settling, the GCD bar
            -- sweeping - only while the canvas is on screen
            local feed = CreateFrame("Frame", nil, canvas)
            feed.t, feed.f = 0, 0
            feed:SetScript("OnUpdate", function(self, elapsed)
                local dd = GT.DB()
                local now = GetTime()
                self.t, self.f = self.t + elapsed, self.f + elapsed
                local arrived = false
                if self.t >= 1.2 then
                    self.t = 0
                    local presses = (P.mode == "presses")
                    arrived = GCDPreviewAdd(st, GT, dd, presses and "pressed" or "ok")
                end
                for _, e in ipairs(st.list) do
                    if e.state == "pressed" and now - e.at > 0.5 then
                        e.state = (e.tex == GCD_ICONS[2]) and "fail" or "ok"
                    end
                end
                while st.list[1] and now - st.list[1].at > dd.fade do table.remove(st.list, 1) end
                if arrived or self.f >= 0.1 then
                    self.f = 0
                    GT.LayoutRow(st.row, st.list, dd, now, arrived)
                end
                local g = (now - (st.gcdAt or 0)) / 1.5
                GT.SetGCD(st.row, dd, (g >= 0 and g < 1) and g or nil)
            end)
            st.feed = feed
        end,
        update = function(canvas, P)
            local st = P.store
            local dd = GT.DB()
            if st.seeded ~= (P.mode or "casts") or #st.list == 0 then GCDSeed(st, GT, dd, P.mode or "casts") end
            local now = GetTime()
            GT.LayoutRow(st.row, st.list, dd, now, false)
            local g = (now - (st.gcdAt or 0)) / 1.5
            GT.SetGCD(st.row, dd, (g >= 0 and g < 1) and g or 0.6)
            local note
            if not dd.enabled then note = "The tracker is off (General)."
            elseif ns.Motion and not ns.Motion.Enabled() then note = "Animations are off (Appearance > Motion)." end
            st.note:SetText(note or "")
            st.note:SetShown(note ~= nil)
            -- the canvas is the row at its real size
            if P.Resize then
                P.Resize(math.max(240, dd.count * (dd.size + (tonumber(dd.gap) or 2)) + 40),
                    math.max(50, dd.size + 34))
            end
        end,
        replay = function(canvas, P)
            local st = P.store
            local dd = GT.DB()
            st.feed.t = 0
            if GCDPreviewAdd(st, GT, dd, "ok") then GT.LayoutRow(st.row, st.list, dd, GetTime(), true) end
        end,
    })
end

local function GCDTab(L, QoL)
    local GT = QoL.GCDTracker
    if not GT then
        L:Card("GCD tracker")
        L:Desc("The GCD tracker did not load.")
        L:EndCard()
        return
    end
    local gc = GT.DB()
    local D = GT.DEFAULTS
    PickTo("qol.gcd", "gcd.", "gcd")
    GCDPreview(L, GT)

    L:Card("General")
    BindCheck(L, gc, "enabled", "Show what goes off",
        "A small row of icons: every cast that went off adds its icon at the newest end, older "
        .. "ones move along. Under it a thin bar fills while the global cooldown runs. "
        .. "Nothing is on screen while the row is empty.")
    BindCheck(L, gc, "showFails", "  ... show the presses too",
        "Every bar press adds an icon as well: dim while the game thinks about it, lit when "
        .. "the cast went off, red with a cross when it was refused (no rage, on cooldown). A "
        .. "refused press repeated is counted on its icon (x3) rather than filling the row.")
    BindCheck(L, gc, "showGCD", "  ... the global cooldown bar", nil)
    BindSlider(L, gc, "count", "Icons kept", { min = 4, max = 20 })
    BindSlider(L, gc, "fade", "Gone after", { min = 2, max = 15, format = function(v) return v .. "s" end,
        desc = "Seconds after a press until its icon has gone." })
    L:EndCard()

    L:Card("Look")
    BindSlider(L, gc, "size", "Icon size", { min = 16, max = 48, format = Px })
    Slide(L, gc, "gap", "Space between icons", { min = 0, max = 12, format = Px })
    Check(L, gc, "border", "A border round each icon")
    Check(L, gc, "cross", "A cross over a refused press")
    Colour(L, gc, "pendingColor", "A press waiting for the game", Fixed(0.55, 0.55, 0.55))
    Colour(L, gc, "failColor", "A refused press", Pal("text", "red"))
    L:Gap(6)
    Slide(L, gc, "barHeight", "Cooldown bar height", { min = 1, max = 12, format = Px })
    Choice(L, gc, "barPos", "Cooldown bar sits", {
        { text = "Under the icons", value = "below" }, { text = "Over the icons", value = "above" } })
    local tp = UI.TexturePicker(L.current, { label = "Cooldown bar texture", width = 240,
        defaultLabel = "Flat", defaultPath = function() return ns.FLAT end,
        get = function() return gc.barTexture end,
        set = function(name) gc.barTexture = name end,
        color = function() local r, g, b = ns.ColorOf(gc.barColor, ns.GetColor("ui", "accent")) return r, g, b end })
    L:Add(tp, 6)
    Colour(L, gc, "barColor", "Cooldown bar colour", Pal("ui", "accent"), true)
    Colour(L, gc, "barBg", "Behind the bar", function()
        local w = ns.GetColor("ui", "windowBg")
        return { r = w.r, g = w.g, b = w.b, a = 0.5 }
    end, true)
    Reset(L, "Back to the usual look", gc,
        { "gap", "border", "cross", "pendingColor", "failColor", "barHeight", "barPos", "barTexture", "barColor", "barBg" }, D)
    L:EndCard()

    L:Card("Text")
    local fp = UI.FontPicker(L.current, { label = "The count on an icon (x3)",
        defaults = { size = 10, outline = "outline" }, minSize = 6, maxSize = 24, sample = "x3  x12",
        get = function() return gc.countFont end,
        set = function(spec) gc.countFont = spec end })
    L:Add(fp, 4)
    Colour(L, gc, "countColor", "Count colour", Fixed(1, 1, 1))
    Spot(L, GT.DB, "count", "gcd.count", "Where the count sits", GT.COUNT_DEFAULTS, { { value = "icon", text = "The icon" } })
    L:EndCard()

    L:Card("Animation")
    local ap = UI.AnimationPicker(L.current, { label = "When an icon arrives",
        styles = { "none", "fade", "slide", "pop", "bounce" },
        get = function() return gc.showAnim end,
        set = function(spec) gc.showAnim = spec end })
    L:Add(ap, 6)
    Slide(L, gc, "slide", "Slide along", { min = 0, max = 0.6, step = 0.05,
        format = function(v) return v > 0 and Secs(v) or "At once" end,
        desc = "How long the row takes to move along when an icon arrives. At once is how it has always been." })
    Choice(L, gc, "slideEase", "How it slides", EasingItems())
    Slide(L, gc, "fadeOut", "Fade out", { min = 0, max = 3, step = 0.1, format = Secs,
        desc = "Icons fade over this long at the end." })
    L:EndCard()

    L:Card("Position")
    Choice(L, gc, "grow", "New icons arrive at", {
        { text = "The right (older ones move left)", value = "left" },
        { text = "The left (older ones move right)", value = "right" } }, 260)
    local mv = UI.Button(L.current, "Move it", { width = 100,
        onClick = function()
            if GT.Demo then GT.Demo() end
            if ns.ToggleMover then ns.ToggleMover("gcdtracker") end
        end })
    L:Row(mv, 26)
    L:Desc("Puts three sample icons in the row so you can see where it sits.")
    L:EndCard()
end

-- ------------------------------------------------------------ pull timers
-- The preview's timers: a break that runs out first (so the pull bar
-- glides up into its place) and a pull that reaches its last seconds.
local DEMO_DUR = { brk = 7, pull = 11 }
local DEMO_GAP = 0.8                  -- between one run ending and the next

local function TimerPreview(L, RT)
    local d = RT.DB()
    L:Preview({
        key = "qol.timers",
        title = "Pull and break timers",
        width = math.max(220, math.min(480, d.width + 40)),
        height = math.max(44, 2 * d.height + (tonumber(d.gap) or 4) + 16),
        modes = { { id = "both", label = "Both" }, { id = "pull", label = "Pull" }, { id = "brk", label = "Break" } },
        build = function(canvas, P)
            local st = P.store
            st.holder = CreateFrame("Frame", nil, canvas)
            st.holder:SetPoint("CENTER", canvas, "CENTER", 0, 0)
            st.bars = { brk = RT.NewBar("brk", st.holder), pull = RT.NewBar("pull", st.holder) }
            st.t0 = { brk = GetTime(), pull = GetTime() }
            st.y = {}
            local tick = CreateFrame("Frame", nil, canvas)
            tick:SetScript("OnUpdate", function()
                local dd = RT.DB()
                local now = GetTime()
                local mode = P.mode or "both"
                local relayout = false
                for kind, b in pairs(st.bars) do
                    local want = (mode == "both" or mode == kind) and dd[kind] ~= false
                    local left = DEMO_DUR[kind] - (now - st.t0[kind])
                    if not want then
                        -- nothing
                    elseif left > 0 then
                        if b:IsShown() and not b._zOut then RT.FillBar(b, kind, left, DEMO_DUR[kind], dd, now) end
                    elseif not b._zOut and b:IsShown() then
                        b._zOut = true
                        relayout = true
                        ns.Motion.Hide(b, dd.hideAnim, function() b._zOut = nil end)
                    elseif left < -DEMO_GAP then
                        st.t0[kind] = now
                        relayout = true
                        b._zArrive = true
                    end
                end
                if relayout then st.Layout(false) end
                -- the glide (the same rule as the real bars)
                local k = math.max(0.02, math.min(1, (tonumber(dd.glide) or 25) / 100))
                if not ns.Motion.Enabled() then k = 1 end
                for _, b in pairs(st.bars) do
                    if b:IsShown() and not b._zOut and not ns.Motion.IsPlaying(b) and b._zY and b._zTY and b._zY ~= b._zTY then
                        local ny = b._zY + (b._zTY - b._zY) * k
                        if math.abs(ny - b._zTY) < 0.3 then ny = b._zTY end
                        b._zY = ny
                        st.Put(b, dd, ny)
                    end
                end
            end)
            st.tick = tick
            st.Put = function(b, dd, y)
                b:ClearAllPoints()
                if dd.grow == "up" then b:SetPoint("BOTTOM", st.holder, "BOTTOM", 0, -y)
                else b:SetPoint("TOP", st.holder, "TOP", 0, y) end
            end
            -- the real Layout's rule: running bars stacked in order; a new
            -- one plays its entrance where it belongs
            st.Layout = function(arriveAll)
                local dd = RT.DB()
                local mode = P.mode or "both"
                local y, gap = 0, tonumber(dd.gap) or 4
                for _, kind in ipairs({ "brk", "pull" }) do
                    local b = st.bars[kind]
                    local want = (mode == "both" or mode == kind) and dd[kind] ~= false
                    local left = DEMO_DUR[kind] - (GetTime() - st.t0[kind])
                    if want and left > 0 then
                        RT.StyleBar(b, kind, dd)
                        b.label:SetText((kind == "pull" and "Pull" or "Break")
                            .. RT.Who({ sender = UnitName("player") or "Zaccw" }))
                        b._zTY = -y
                        if arriveAll or b._zArrive or not b:IsShown() then
                            b._zArrive = nil
                            ns.Motion.Stop(b)
                            b:Hide()
                            b._zY = -y
                            st.Put(b, dd, b._zY)
                            RT.FillBar(b, kind, left, DEMO_DUR[kind], dd, GetTime())
                            ns.Motion.Show(b, dd.showAnim)
                        elseif not ns.Motion.IsPlaying(b) then
                            if b._zY == nil then b._zY = -y end
                            st.Put(b, dd, b._zY)
                        end
                        y = y + dd.height + gap
                    elseif not want then
                        ns.Motion.Stop(b)
                        b._zOut = nil
                        b:Hide()
                    end
                end
                st.holder:SetSize(dd.width, math.max(dd.height, 2 * dd.height + gap))
            end
        end,
        update = function(canvas, P)
            local st = P.store
            local dd = RT.DB()
            for kind, b in pairs(st.bars) do RT.StyleBar(b, kind, dd) end
            st.Layout(false)
            -- the canvas is the two bars at their real size
            if P.Resize then
                P.Resize(math.max(220, dd.width + 40),
                    math.max(44, 2 * dd.height + (tonumber(dd.gap) or 4) + 16))
            end
        end,
        replay = function(canvas, P)
            local st = P.store
            local now = GetTime()
            st.t0.brk, st.t0.pull = now, now
            for _, b in pairs(st.bars) do b._zOut = nil end
            st.Layout(true)
        end,
    })
end

local function TimersTab(L, QoL)
    local RT = QoL.RaidTimers
    if not RT then
        L:Card("Pull and break timers")
        L:Desc("The pull timers did not load.")
        L:EndCard()
        return
    end
    local t = RT.DB()
    local D = RT.DEFAULTS
    local function TRefresh() RT.Apply() end
    PickTo("qol.timers", "timers.", "timers")
    local function TCheck(key, label, desc)
        local w = UI.Checkbox(L.current, label, t[key] and true or false, function(v)
            t[key] = v and true or false
            TRefresh()
        end)
        L:Row(w, 17)
        if desc then L:Desc(desc) end
    end
    local function TSlider(key, label, mn, mx, fmt)
        local w = UI.Slider(L.current, { width = 200, min = mn, max = mx, step = 1,
            value = t[key], label = label, format = fmt,
            onChange = function(v) t[key] = v; RT.Layout() end })
        L:Row(w, 40)
    end
    TimerPreview(L, RT)

    L:Card("General")
    TCheck("enabled", "Show pull and break timers as bars",
        "From DBM, BigWigs and /countdown. They keep running through a "
        .. "reload, a relog or a character swap.")
    TCheck("brk", "  Break timers")
    TCheck("pull", "  Pull timers")
    TCheck("hideBlizz", "  Hide Blizzard's own countdown",
        "One pull timer instead of two: Blizzard's ornate bar and its big numbers are hidden.")
    TCheck("sync", "Ask the group when you log in",
        "Your other characters running ZacUI answer with any timer they "
        .. "have, so a break that started while you were logged out still "
        .. "shows up.")
    Check(L, t, "sender", "Show who started it", "The caller's name, in their class colour, after the label.")
    L:Desc("Raid mods has its own pull-timer text too (Combat > Raid mods > Pull timers); "
        .. "keep one of the two on so a pull is not counted twice.")
    L:EndCard()

    L:Card("Look")
    TSlider("width", "Bar width", 120, 400, Px)
    TSlider("height", "Bar height", 12, 36, Px)
    Slide(L, t, "gap", "Space between the bars", { min = 0, max = 20, format = Px })
    local tp = UI.TexturePicker(L.current, { label = "Bar texture", width = 240,
        get = function() return t.texture end,
        set = function(name) t.texture = name end,
        color = function() local c = ns.GetColor("text", "red") return c.r, c.g, c.b end })
    L:Add(tp, 6)
    Colour(L, t, "pullColor", "Pull bar", Pal("text", "red"))
    Colour(L, t, "breakColor", "Break bar", Pal("text", "blue"))
    Colour(L, t, "bgColor", "Behind the bar", function()
        local w, c = ns.GetColor("ui", "windowBg"), ns.GetColor("text", "red")
        return { r = w.r * 0.45 + c.r * 0.12, g = w.g * 0.45 + c.g * 0.12, b = w.b * 0.45 + c.b * 0.12, a = 0.9 }
    end, true, "Until you pick one, a dark shade of each bar's own colour.")
    Check(L, t, "icon", "The icon at the left")
    Check(L, t, "spark", "A glow at the end of the fill")
    Check(L, t, "sheen", "A sheen on the fill")
    Slide(L, t, "warnAt", "Warn in the last", { min = 0, max = 10, format = function(v)
        return v > 0 and (v .. "s of a pull") or "Never" end,
        desc = "The time turns this colour for the last seconds of a pull." })
    Colour(L, t, "warnColor", "Warning colour", Pal("text", "gold"))
    Reset(L, "Back to the usual look", t,
        { "gap", "texture", "pullColor", "breakColor", "bgColor", "icon", "spark", "sheen", "warnAt", "warnColor" }, D)
    L:EndCard()

    L:Card("Text")
    local lf = UI.FontPicker(L.current, { label = "Label (Pull, Break and who)",
        defaults = { size = RT.LabelSize(t), outline = "outline" }, minSize = 6, maxSize = 24, sample = "Pull  Zaccw",
        get = function() return t.labelFont end,
        set = function(spec) t.labelFont = spec end })
    L:Add(lf, 4)
    local tf = UI.FontPicker(L.current, { label = "Time",
        defaults = { size = RT.TimeSize(t), outline = "outline" }, minSize = 6, maxSize = 28, sample = "9.4  1:30",
        get = function() return t.timeFont end,
        set = function(spec) t.timeFont = spec end })
    L:Add(tf, 4)
    L:Desc("Until a font is picked, both follow the bar's height.")
    Colour(L, t, "textColor", "Text colour", Pal("text", "normal"))
    local targets = {}
    for _, k in ipairs({ "bar", "fill", "icon", "label", "time" }) do targets[#targets + 1] = { value = k, text = RT.ANCHOR_LABELS[k] } end
    local function Others(key)
        local out = {}
        for _, e in ipairs(targets) do if e.value ~= key then out[#out + 1] = e end end
        return out
    end
    Spot(L, RT.DB, "label", "timers.label", "Where the label sits", RT.AnchorDefaults("label"), Others("label"))
    Spot(L, RT.DB, "time", "timers.time", "Where the time sits", RT.AnchorDefaults("time"), Others("time"),
        { key = "time", defaults = RT.TIME_DEFAULTS,
          sample = function(f) return ns.FormatTime(90, f, RT.TIME_DEFAULTS) .. "  " .. ns.FormatTime(9.4, f, RT.TIME_DEFAULTS) end })
    L:EndCard()

    L:Card("Animation")
    local sa = UI.AnimationPicker(L.current, { label = "When a bar starts",
        styles = { "none", "fade", "slide", "pop", "bounce" },
        get = function() return t.showAnim end, set = function(spec) t.showAnim = spec end })
    L:Add(sa, 6)
    local ha = UI.AnimationPicker(L.current, { label = "When a bar ends",
        styles = { "none", "fade", "slide", "pop" },
        get = function() return t.hideAnim end, set = function(spec) t.hideAnim = spec end })
    L:Add(ha, 6)
    Slide(L, t, "glide", "Glide speed", { min = 5, max = 100, step = 5, format = Pct,
        desc = "How quickly a bar moves up into a place that came free. 100% is at once." })
    Check(L, t, "warnPulse", "The pull bar breathes in its last seconds")
    L:EndCard()

    L:Card("Position")
    Choice(L, t, "grow", "Bars stack", {
        { text = "Downward (break on top)", value = "down" }, { text = "Upward (break at the bottom)", value = "up" } })
    local row = UI.Holder(L.current)
    row:SetSize(300, M.BUTTON_H)
    local test = UI.Button(row, "Test", { width = 80,
        tooltip = "A 15 second break and a 10 second pull, to see them.",
        onClick = function() RT.Test() end })
    test:SetPoint("LEFT")
    local move = UI.Button(row, "Move", { width = 80,
        tooltip = "Shows a box to drag; press again to lock. Edit Mode moves it too.",
        onClick = function() if ns.ToggleMover then ns.ToggleMover("raidtimers") end end })
    move:SetPoint("LEFT", test, "RIGHT", 8, 0)
    L:Row(row, M.BUTTON_H + 4)
    L:EndCard()
end

-- ------------------------------------------------------------ snowball
local SNOW_MODES = { { id = "ground", label = "Ground" }, { id = "air", label = "In the air" },
                     { id = "none", label = "None left" } }

local function SnowballPreview(L, SB)
    local sc = SB.Cfg()
    local size = tonumber(sc.size) or 45
    L:Preview({
        key = "qol.snowball",
        title = "Snowball button",
        width = size + 226, height = math.max(50, size + 12),
        modes = SNOW_MODES,
        build = function(canvas, P)
            local st = P.store
            st.holder = CreateFrame("Frame", nil, canvas)
            st.holder:SetPoint("CENTER", canvas, "CENTER", 0, 4)
            st.btn = SB.Face(CreateFrame("Frame", nil, st.holder))
            st.btn:SetAllPoints(st.holder)
            st.lock = SB.Face(CreateFrame("Frame", nil, st.holder))
            st.lock:SetAllPoints(st.holder)
            st.lock:SetFrameLevel(st.btn:GetFrameLevel() + 3)
            st.note = UI.Font(canvas, F.SMALL, { cat = "text", key = "gray", justify = "CENTER" })
            st.note:SetPoint("BOTTOM", canvas, "BOTTOM", 0, 2)
            st.note:SetWidth(190)
        end,
        update = function(canvas, P)
            local st = P.store
            local c = SB.Cfg()
            local s = tonumber(c.size) or 45
            local mode = P.mode or "ground"
            local n = (mode == "none") and 0 or 12
            if ns.Motion then ns.Motion.Stop(st.lock) end
            st.holder:SetSize(s, s)
            SB.StyleFace(st.btn, c, false, n)
            SB.StyleFace(st.lock, c, true, n)
            -- at rest for the mode: the lock over it on the ground, gone in the air
            st.lock:SetAlpha(1)
            st.lock:SetShown(mode ~= "air")
            st.holder:SetAlpha(c.showIcon ~= false and 1 or 0.25)
            local note
            if c.showIcon == false then note = "The icon is hidden: only the mouse button throws."
            elseif mode == "air" then note = "In the air the lock steps aside: a click throws."
            else note = "On the ground a click is swallowed: jump first." end
            -- the button and the note beside it, at their real size; the
            -- canvas is their box and the strip scales it
            st.note:SetWidth(190)
            st.note:SetJustifyH("LEFT")
            st.note:SetText(note)
            local noteH = (st.note:GetStringHeight() or 12) + 4
            st.holder:SetScale(1)
            st.holder:ClearAllPoints()
            st.holder:SetPoint("LEFT", canvas, "LEFT", 8, 0)
            st.note:ClearAllPoints()
            st.note:SetPoint("LEFT", st.holder, "RIGHT", 12, 0)
            if P.Resize then P.Resize(8 + s + 12 + 190 + 8, math.max(s, noteH) + 12) end
        end,
        replay = function(canvas, P)
            local st = P.store
            local spec = SB.Cfg().lockAnim
            if (P.mode or "ground") == "air" then
                st.lock:SetAlpha(1)
                st.lock:Show()
                SB.SetLock(st.lock, false, spec)
            else
                st.lock:Hide()
                SB.SetLock(st.lock, true, spec)
            end
        end,
    })
end

local function SnowballTab(L, QoL)
    local SBm = QoL.Snowball
    if not SBm then
        L:Card("Snowball button")
        L:Desc("The Snowball button did not load.")
        L:EndCard()
        return
    end
    local sc = SBm.Cfg()
    PickTo("qol.snowball", "snowball.", "snowball")
    SnowballPreview(L, SBm)

    L:Card("General")
    BindCheck(L, sc, "enabled", "Show a Snowball button that only throws in the air",
        "Click it as often as you like: on the ground it is locked and nothing happens; "
        .. "the moment you are in the air the same click throws a Snowball at yourself. "
        .. "Right-click takes the snow off you. In a macro: /click ZacUISnowball throws, "
        .. "/click ZacUISnowball RightButton clears - wherever you are, since only the "
        .. "mouse is held back by the lock (the game gives macros no way to know you are "
        .. "falling).")
    BindCheck(L, sc, "raidsOnly", "  ... only in raids", nil)
    BindCheck(L, sc, "chatty", "  ... explain in chat",
        "Chat lines on why a throw did not happen (locked on the ground, no Snowballs, the game's own error), "
        .. "and what a press of the mouse button did. Off by default.")
    BindCheck(L, sc, "showIcon", "  ... show the icon",
        "Off, and there is nothing on screen to click: only the mouse button (Advanced) throws.")
    local tg = UI.EditBox(L.current, { width = 240,
        text = sc.targets or "",
        hint = "Maexxna, Loatheb ...",
        onEnter = function(v)
            sc.targets = (v or ""):gsub("^%s+", ""):gsub("%s+$", "")
            Refresh()
        end })
    L:Row(tg, 26)
    local pick = UI.Dropdown(L.current, { width = 240,
        items = function()
            local items = {}
            for _, entry in ipairs(SBm.BossLists()) do
                for _, boss in ipairs(entry[2]) do
                    items[#items + 1] = { text = boss .. "  |cff808080" .. entry[1] .. "|r", value = boss }
                end
                -- the trash, by section, after that raid's bosses
                for _, sec in ipairs(entry.trash or {}) do
                    for _, mob in ipairs(sec[2]) do
                        items[#items + 1] = { text = mob .. "  |cff808080" .. entry[1] .. " - " .. sec[1] .. "|r", value = mob }
                    end
                end
            end
            return items
        end,
        selected = function() return "Add a boss or trash mob..." end,
        selectedValue = function() return nil end,
        onSelect = function(v)
            sc.targets = SBm.AddTarget(sc.targets, v)
            tg:SetText(sc.targets)
            Refresh()
        end })
    L:Row(pick, 26)
    L:Desc("Only while targeting one of these (names, comma-separated; empty = always). Type names and press "
        .. "Enter, or pick bosses from the list (Readycheck's). Decided out of combat: target Maexxna before "
        .. "the pull and the button is up for the fight; the next change of target after the fight takes it down.")
    L:EndCard()

    L:Card("Look")
    BindSlider(L, sc, "size", "Size", { min = 24, max = 200, format = Px,
        desc = "Changes wait for the end of a fight: the button is a secure one." })
    Check(L, sc, "showCooldown", "The cooldown sweep over the icon")
    Check(L, sc, "lockDesat", "The locked icon in grey")
    Colour(L, sc, "lockColor", "Locked tint", Fixed(0.55, 0.55, 0.6))
    Reset(L, "Back to the usual look", sc, { "showCooldown", "lockDesat", "lockColor" }, SBm.DEFAULTS)
    L:EndCard()

    L:Card("Text")
    Check(L, sc, "showCount", "How many you carry, in the corner")
    local fp = UI.FontPicker(L.current, { label = "The count",
        defaults = { size = 12, outline = "outline" }, minSize = 6, maxSize = 28, sample = "12  3  0",
        get = function() return sc.countFont end,
        set = function(spec) sc.countFont = spec end })
    L:Add(fp, 4)
    Colour(L, sc, "countColor", "Count colour", Fixed(1, 1, 1))
    Colour(L, sc, "emptyColor", "Count when you have none", Fixed(1, 0.3, 0.3))
    Spot(L, SBm.Cfg, "count", "snowball.count", "Where the count sits", SBm.COUNT_DEFAULTS, { { value = "button", text = "The button" } })
    L:EndCard()

    L:Card("Animation")
    local ap = UI.AnimationPicker(L.current, { label = "When the lock opens and closes",
        styles = { "none", "fade", "pop", "slide" },
        get = function() return sc.lockAnim end,
        set = function(spec) sc.lockAnim = spec end })
    L:Add(ap, 6)
    L:Desc("Only what you see: the lock steps aside the moment you leave the ground either way. "
        .. "None is how it has always been.")
    L:EndCard()

    L:Card("Position")
    local mv = UI.Button(L.current, "Move it", { width = 100,
        onClick = function() if ns.ToggleMover then ns.ToggleMover("snowball") end end })
    L:Row(mv, 26)
    L:EndCard()

    L:Card("Advanced")
    local ab = UI.EditBox(L.current, { width = 160,
        text = sc.airButton or "",
        hint = "BUTTON4, ALT-BUTTON4, BUTTON5 ...",
        onEnter = function(v)
            v = (v or ""):upper():gsub("%s+", "")
            if v ~= "" and not (SBm.PhysOf and SBm.PhysOf(v)) then
                Print("Snowball: that has to be BUTTON3, BUTTON4 or BUTTON5 (the middle and side buttons), with any modifiers in front (ALT-BUTTON4). A keyboard key cannot be gated, and the game cannot gate buttons beyond BUTTON5.")
                return
            end
            sc.airButton = v
            Refresh()
        end })
    L:Row(ab, 26)
    L:Desc("A mouse button that throws only while you are in the air, wherever the cursor is "
        .. "over the world. Press Enter. A keyboard key cannot do this: the game runs a key "
        .. "without looking at what is under the cursor, but offers a mouse button to the "
        .. "frame under it first, which is what the lock uses. Only that exact combination is "
        .. "the snowball: with BUTTON4 here, Shift-BUTTON4 and the rest still do what your Key "
        .. "Bindings say (if one of them is bound to something that is not a bar button, the "
        .. "mouse button switches itself off and chat says which). Two limits, both the "
        .. "game's: over a window the window eats the press, and while you hold the right "
        .. "button to steer the UI gets no mouse at all, so a press then throws on the ground too.")
    L:EndCard()
end

-- search words for what the page does not say in so many words
if ns.AddMenuKeywords then
    ns.AddMenuKeywords("qol", "gcd global cooldown tracker icons casts presses "
        .. "pull break timer timers countdown dbm bigwigs snowball snow airborne jump "
        .. "animation slide fade preview font colour color texture bar")
end

RegisterPage("QoL", function(L)
    local QoL = ns.QoL
    L:Header("Quality of life",
        "Vendor and loot automation, the GCD tracker, pull timers and the Snowball button, "
        .. "screen and raid tweaks, muted sounds, the buff remover, macro cleanup and auto-roll.")
    -- "Combat helpers" became three tabs (2026-11-01): land where it was
    local cs = ns.ConfigState and ns.ConfigState()
    if cs and cs.tabs and cs.tabs.qol == "combat" then cs.tabs.qol = "gcd" end

    if not QoL or not QoL.DB then
        L:Notice("missing", "The quality-of-life module did not load.")
        return
    end
    local d = QoL.DB()

    if not (ZacUIDB.modules and ZacUIDB.modules.qol) then
        L:Notice("off", "The Quality of life module is off; these settings wait for it.", "Modules > HUD", "qol")
    end

    local function Tab_auto(L)
        -- ============================================================
        L:Card("Merchant")
        BindCheck(L, d, "sellJunk", "Sell junk automatically",
            "Greys sell when a vendor opens. Hold Shift while opening to skip.")
        BindCheck(L, d, "sellSummary", "  ... print what it earned", nil)
        local ex = UI.EditBox(L.current, { width = 220,
            text = d.sellExclude or "",
            hint = "item IDs, comma separated",
            onChange = function(v)
                d.sellExclude = v or ""
                if QoL.UpdateWhiteList then QoL.UpdateWhiteList() end
            end })
        L:Row(ex, 26)
        L:Desc("Exception list, both directions: a grey item listed here is "
            .. "KEPT, a white item listed here is SOLD.")
        BindCheck(L, d, "repair", "Repair automatically",
            "From your own gold, silently skipped when you can't afford it. "
            .. "Shift skips.")
        BindCheck(L, d, "repairSummary", "  ... print the cost", nil)
        if type(CanGuildBankRepair) == "function" then
            BindCheck(L, d, "repairGuild", "  ... from the guild bank's funds first",
                "When your guild lets you repair from its bank and today's allowance covers it. Off by default.")
        end
        L:EndCard()

        -- ============================================================
        local SMo = QoL.SmartMount
        if SMo then
            local sm = SMo.Cfg()
            L:Card("Mount macro")
            BindCheck(L, sm, "enabled", "Keep one mount macro right on every character",
                "The macro named below is rewritten (out of combat) to use what this "
                .. "character has: inside the Temple of Ahn'Qiraj a Qiraji crystal from "
                .. "the bags, elsewhere the best mount item carried - epic before rare - "
                .. "or a paladin's or warlock's summon spell. Same key, every character.")
            local nameBox = UI.EditBox(L.current, { width = 160,
                text = sm.macro or "Mount",
                hint = "macro name",
                onEnter = function(v)
                    v = (v or ""):gsub("^%s+", ""):gsub("%s+$", "")
                    if v ~= "" then sm.macro = v SMo.Refresh() end
                end })
            L:Row(nameBox, 26)
            L:Desc("The macro's name, exactly as in the Macros window. Press Enter.")
            BindCheck(L, sm, "create", "  ... make it (account-wide) when a character does not have it", nil)
            local row = UI.Holder(L.current)
            row:SetSize(300, M.BUTTON_H)
            local st = UI.Button(row, "Check now", { width = 100,
                tooltip = "Prints what it picks on this character and writes the macro.",
                onClick = function() SMo.Status() end })
            st:SetPoint("LEFT")
            L:Row(row, M.BUTTON_H + 8)
            L:EndCard()
        end

        -- ============================================================
        local SWo = QoL.SmartWeapons
        if SWo then
            local sw = SWo.Cfg()
            L:Card("Weapon macros")
            BindCheck(L, sw, "enabled", "Keep weapon swap macros on this character's weapons",
                "Every macro with /equipslot or /equip lines, on every character and class: a weapon "
                .. "the character does not have is swapped for its own in the same role (main hand, "
                .. "off hand, fast weapon, shield, off-hand item, two-hander, ranged), and a macro "
                .. "follows an upgrade of the weapon it used. Weapons you carry are never changed "
                .. "otherwise, so a set named on purpose stays. A macro with a #keep line is left alone.")
            L:Desc("Main and off hand: the pair you dual wield in boss fights, learned a few seconds "
                .. "into each pull - trash weapons worn on the way never count.")
            local skipBox = UI.EditBox(L.current, { width = 300, text = sw.skip or "",
                hint = "never in swap macros: Kingsfall",
                onChange = function(v) sw.skip = v or "" end,
                onEnter = function(v) sw.skip = v or "" SWo.Refresh() end })
            L:Row(skipBox, 26)
            L:Desc("Weapons never picked for a swap macro (comma between each) - trash weapons, say. "
                .. "A macro that names one on purpose keeps it.")
            local row = UI.Holder(L.current)
            row:SetSize(300, M.BUTTON_H)
            local st = UI.Button(row, "Check now", { width = 100,
                tooltip = "Goes over this character's macros now.",
                onClick = function() SWo.Refresh() end })
            st:SetPoint("LEFT")
            L:Row(row, M.BUTTON_H + 8)
            L:EndCard()
        end

        -- ============================================================
        L:Card("World")
        BindCheck(L, d, "gossip", "Skip gossip pages",
            "Single-option gossip skips at stables, bankers, flight masters, "
            .. "trainers, vendors and battlemasters; elsewhere hold Alt. Shift "
            .. "suppresses.")
        BindCheck(L, d, "fasterLoot", "Faster auto-loot",
            "Grabs every loot slot the moment the window opens, honoring "
            .. "master loot thresholds.")
        BindCheck(L, d, "dismount", "Dismount on error",
            "Casting while mounted dismounts you instead of erroring.")
        BindCheck(L, d, "dismountNoResource", "  ... on no rage/mana/energy", nil)
        BindCheck(L, d, "dismountNoMoving", "  ... on 'can't do that while moving'", nil)
        BindCheck(L, d, "dismountNoTaxi", "  ... when opening a flight map", nil)
        L:EndCard()

        -- ============================================================
        local DK = QoL.DialogKeys
        if DK then
            local dk = DK.Cfg()
            local function DkCheck(key, label, desc)
                local w = UI.Checkbox(L.current, label, dk[key] ~= false, function(v)
                    dk[key] = v and true or false
                    DK.SettingsChanged()
                    Refresh()
                end)
                L:Row(w, 17)
                if desc then L:Desc(desc) end
            end
            L:Card("Talking to NPCs by keyboard")
            DkCheck("enabled", "Keys for gossip and quest windows",
                "1-9 pick a line: a gossip option, a quest on offer or in progress, a reward "
                .. "to choose. Enter accepts a quest, continues, completes it, or takes the first "
                .. "line of a list. Escape and typing are never touched; keys that mean nothing "
                .. "here go through to the game.")
            DkCheck("numbers", "  ... number the lines", nil)
            DkCheck("space", "  ... Space does what Enter does", nil)
            DkCheck("popups", "  ... Space also presses a popup's first button",
                "Release spirit, take the summon, enter the instance - popups that take no typing.")
            L:EndCard()
        end

        -- ============================================================
        L:Card("Group")
        BindCheck(L, d, "invite", "Invite on whisper",
            "A whisper that is exactly the keyword invites the sender, when you "
            .. "can invite and are not queued for a battleground.")
        local kb = UI.EditBox(L.current, { width = 120,
            text = d.inviteKey or "inv",
            onChange = function(v)
                if not v or v == "" then v = "inv" end
                d.inviteKey = v
            end })
        L:Row(kb, 26)
        L:Desc("The keyword.")
        BindCheck(L, d, "inviteFriendsOnly", "  ... friends only",
            "Off, and anyone who whispers it gets invited.")
        BindCheck(L, d, "friendlyGuild", "  ... guild counts as friends", nil)
        L:EndCard()

    end

    local function Tab_screen(L)
        -- ============================================================
        L:Card("Screen")
        BindCheck(L, d, "noScreenGlow", "Remove screen glow",
            "The ffxGlow cvar. Toggling off restores it.")
        BindCheck(L, d, "noScreenEffects", "Remove death and netherworld effects",
            "The ffxDeath and ffxNether cvars. Toggling off restores them.")
        BindCheck(L, d, "noErrorText", "Hide red error text",
            "\"You are too far away!\", \"Not enough rage\" and the like in the middle "
            .. "of the screen. Quest progress and other yellow lines still show.")
        L:EndCard()

        -- ============================================================
        L:Card("Raid performance")
        if QoL.RaidPerfState then
            local rp = QoL.RaidPerfState()
            BindCheck(L, rp, "enabled", "Lower cosmetic graphics in raids",
                "Zoning into a raid drops shadows, SSAO, water, reflections, "
                .. "ground clutter and weather; zoning out restores exactly "
                .. "what you had. Ground markers are forced ON while active - "
                .. "spell effects, view distance and nameplates are never "
                .. "touched. Toggling this mid-raid applies immediately.")
            L:Desc(rp.active
                and "Currently ACTIVE - your normal settings are held and "
                    .. "will restore when you leave (or untick above)."
                or "Currently idle - it arms itself when you zone in.")
        else
            L:Desc("The raid performance module did not load.")
        end
        L:EndCard()

        -- ============================================================
        BossParticlesCard(L, QoL)
        -- ============================================================
        L:Card("Muted sounds")
        local mg = d.muteGame
        -- each group: the switch, then what it mutes, indented under it
        -- and dimmed while the switch is off
        local function Kid(tbl, key, label, tip)
            return UI.Checkbox(L.current, label, tbl[key] and true or false, function(v)
                tbl[key] = v and true or false
                Refresh()
            end, tip and { tooltip = tip } or nil)
        end
        BindCheck(L, mg, "enabled", "Mute game sounds", nil)
        L:Dependent({
            Kid(mg, "MuteChimes", "City bell chimes"),
            Kid(mg, "MuteFizzle", "Spell fizzles"),
            Kid(mg, "MuteInterface", "Interface clicks"),
            Kid(mg, "MuteLogin", "Login screen music", "Muted at logout, so it takes effect from your next login screen."),
            Kid(mg, "MuteTrains", "Train emotes"),
            Kid(mg, "MuteScreech", "Screech"),
            Kid(mg, "MuteYawns", "Tiger yawns"),
            Kid(mg, "MuteReady", "Ready check and level-up"),
            Kid(mg, "MutePiccolo", "Piccolo of the Flaming Fire", "Also mutes warlock Seduction."),
        }, mg.enabled, 2, nil, "Mute game sounds")
        local mm = d.muteMount
        L:Gap(4)
        BindCheck(L, mm, "enabled", "Mute mount sounds", nil)
        L:Dependent({
            Kid(mm, "MuteMechSteps", "Mechanical steps"),
            Kid(mm, "MuteStriders", "Mechanostriders"),
            Kid(mm, "MuteHorsesteps", "Horse hooves"),
        }, mm.enabled, 2, nil, "Mute mount sounds")
        L:EndCard()

    end

    -- the GCD tracker, the pull timers and the Snowball button each have
    -- a tab of their own (they shared "Combat helpers" until the
    -- 2026-11-01 look pass): each draws something on screen, so each
    -- has a live preview and the full set of look and motion settings
    local tabs = {
        { id = "auto", label = "Automation", build = Tab_auto },
        { id = "gcd", label = "GCD tracker", build = function(TL) GCDTab(TL, QoL) end },
        { id = "timers", label = "Pull timers", build = function(TL) TimersTab(TL, QoL) end },
        { id = "snowball", label = "Snowball", build = function(TL) SnowballTab(TL, QoL) end },
        { id = "screen", label = "Screen & sounds", build = Tab_screen },
        { id = "buffs", label = "Buffs", build = function(TL) BuffsTab(TL, QoL) end },
        { id = "macros", label = "Macros", build = function(TL) MacrosTab(TL, QoL) end },
        { id = "loot", label = "Loot", build = function(TL) LootTab(TL, QoL) end },
    }
    -- no Buffs tab where there is no buff limit, no Snowball tab where the
    -- button is not needed (Core_Flavor: buff_remover, snowball)
    for i = #tabs, 1, -1 do
        local t = tabs[i]
        if (t.id == "buffs" and ns.FeatureOn and not ns.FeatureOn("buff_remover"))
            or (t.id == "snowball" and ns.FeatureOn and not ns.FeatureOn("snowball")) then
            table.remove(tabs, i)
        end
    end
    L:Tabs(tabs)
end)
