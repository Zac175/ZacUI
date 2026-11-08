-- HUD_V2_Page - Class HUD v2: the cards it adds to every class HUD's
-- settings page, on the tabs the page already has (General: the utility
-- row, the role setup, when each row shows, buffs that are down; Look:
-- row layouts, icon states; Text: cooldown text thresholds and format,
-- keybind text; Position: the utility row's scale; Advanced: the press
-- mirror and tooltips). Each card is built only where it applies (no
-- utility card for a class without utility spells, no role card without
-- roles). Every control changes the live HUD and the preview sample at
-- once through the page's own widgets; nothing is written until changed.
-- Part of ZacUI; load order is set by the TOC (after HUD_V2_Icon).

local ns = _G.ZacUI
if not ns or not ns.HUD or not ns.HUD.V2 then return end
local HUD = ns.HUD
local V2 = HUD.V2
local Engine = HUD.ClassEngine
local UI = ns.UI

local Check = HUD.CheckIndent

local function Px(v) return v .. " px" end
local function Secs(v) return v == 0 and "off" or (v .. " s") end

-- the page's own memory (which row a card shows), kept with ZacUI's
-- other config-window state
local function PageMem()
    ZacUIDB.config = ZacUIDB.config or {}
    return ZacUIDB.config
end

-- the rows this HUD has, { { value = row, text = label } ... }
function Engine:V2RowItems(withUtility)
    local def = self.def
    local out = { { value = "main", text = V2.ROW_LABELS.main } }
    if withUtility and def.utility and #def.utility > 0 then out[#out + 1] = { value = "utility", text = V2.ROW_LABELS.utility } end
    if def.buffRow and #def.buffRow > 0 then out[#out + 1] = { value = "buffs", text = V2.ROW_LABELS.buffs } end
    if def.debuffRow and #def.debuffRow > 0 then out[#out + 1] = { value = "debuffs", text = V2.ROW_LABELS.debuffs } end
    if def.reminders and #def.reminders > 0 then out[#out + 1] = { value = "reminders", text = V2.ROW_LABELS.reminders } end
    out[#out + 1] = { value = "aux", text = V2.ROW_LABELS.aux }
    return out
end

local function RowPick(L, eng, memKey, items)
    local mem = PageMem()
    local cur = mem[memKey]
    local ok = false
    for _, it in ipairs(items) do if it.value == cur then ok = true end end
    if not ok then cur = items[1].value mem[memKey] = nil end
    local function Label() for _, it in ipairs(items) do if it.value == cur then return it.text end end return "" end
    HUD.Dropdown(L, 220, items, Label, function(v)
        mem[memKey] = v
        HUD.RefreshPage()
    end)
    return cur
end

-- after a v2 setting changed: the save tidied, the HUD redrawn
local function After(eng, cfg)
    return function()
        V2.Tidy(cfg)
        if eng.V2SyncWants then eng:V2SyncWants(cfg) end
        eng:Refresh()
    end
end

-- ------------------------------------------------------------
-- General
-- ------------------------------------------------------------
function Engine:V2Tab_General(L, cfg)
    local eng, def = self, self.def

    if def.utility and #def.utility > 0 then
        L:Card("Utility row")
        L:Desc("Lesser cooldowns on a second row of their own. Its spot is under Position once it is on.")
        Check(L, "Show the utility row", V2.UtilityOn(cfg), function(v)
            local u = V2.Sub(cfg, "utility", true)
            u.enabled = v or nil
            V2.Tidy(cfg)
            if v then eng:V2EnsureUtility() end
            eng:Refresh()
            HUD.RefreshPage()
        end)
        if V2.UtilityOn(cfg) then
            local hidden = V2.HiddenSet(cfg, "utility")
            HUD.CheckGrid(L, def.utility,
                function(g) return g.label or g.key end,
                function(g) return not eng:V2Off("utility", hidden, g) end,
                function(g, v)
                    -- a tick is yours for good: true = off, false = on
                    V2.HiddenSet(cfg, "utility", true)[g.key] = not v
                    eng:Refresh()
                end)
            HUD.SliderPair(L,
                { "Utility icon size", 14, 48, (V2.Util(cfg) and V2.Util(cfg).iconSize) or 25,
                  function(v) V2.Sub(cfg, "utility", true).iconSize = v eng:ApplySizes() end, Px },
                { "Utility spacing", 0, 12, (V2.Util(cfg) and V2.Util(cfg).spacing) or 4,
                  function(v) V2.Sub(cfg, "utility", true).spacing = v eng:ApplySizes() end, Px })
        end
        L:EndCard()
    end

    if def.roles and #def.roles > 0 then
        L:Card("Spec defaults")
        L:Desc("The HUD starts the way a strong player of your spec sets it up: the icons, buffs, debuffs, trinkets, glows and bar extras that spec watches. Anything you tick or untick stays yours.")
        local v = V2.Cfg(cfg)
        local pick = v and v.role
        local items = eng:V2SpecItems(true)
        local function Label()
            for _, it in ipairs(items) do if it.value == (pick or "auto") then return it.text end end
            return items[1].text
        end
        HUD.Dropdown(L, 240, items, Label, function(val)
            V2.Cfg(cfg, true).role = (val ~= "auto") and val or nil
            V2.Tidy(cfg)
            for _, m in pairs(eng.memo) do HUD.ForgetLayout(m) end
            eng:Refresh()
            HUD.RefreshPage()
        end, "Automatic follows your talents (and, for a feral druid, the form you fight in); Class baseline shows everything, as the HUD always did.")
        HUD.Button(L, "Reset to spec defaults", 200, function()
            eng:V2ResetToSpec()
            HUD.RefreshPage()
        end, "Clears your own ticks, glow rules, bar extras and the trinket row's switch, so the spec decides them again.")
        L:EndCard()
    end

    L:Card("When each row shows")
    L:Desc("A rule per row: always, only in combat, with a target... The row fades by it; nothing saved shows it as always.")
    local row = RowPick(L, eng, "hudV2VisRow", eng:V2RowItems(true))
    local vg, vs = ns.CustomAccess(cfg, "visibility", row, After(eng, cfg))
    L:Add(UI.VisibilityPicker(L.current, { width = UI.CardInnerWidth(L), get = vg, set = vs,
        shows = { "always", "combat", "nocombat", "group", "raid", "instance", "target", "resting", "never" },
        fields = { show = true, alpha = true, combatAlpha = true, fadeIn = true, fadeOut = true } }), 6)
    L:EndCard()

    if def.buffRow and #def.buffRow > 0 then
        L:Card("Buffs that are down")
        local v = V2.Cfg(cfg)
        local mode = v and v.buffsMissing or "hide"
        local modes = { { value = "hide", text = "Take no room (as always)" }, { value = "keep", text = "Keep their place" },
            { value = "grey", text = "Show greyed out" } }
        HUD.Dropdown(L, 240, modes, function()
            for _, m in ipairs(modes) do if m.value == mode then return m.text end end
            return modes[1].text
        end, function(val)
            V2.Cfg(cfg, true).buffsMissing = (val ~= "hide") and val or nil
            V2.Tidy(cfg)
            HUD.ForgetLayout(eng.memo.aura)
            eng:Refresh()
        end, "A buff that is not up can keep its slot in the row, empty or as a grey icon, so the others never shift.")
        L:EndCard()
    end
end

-- ------------------------------------------------------------
-- Look
-- ------------------------------------------------------------
function Engine:V2LayoutDefaultsFor(cfg, row)
    if row == "main" then return V2.LayoutDefaults("main", cfg.mainRow.rows, cfg.mainRow.spacing or 4) end
    local size, space = 25, 4
    if row == "utility" then local u = V2.Util(cfg) size, space = (u and u.iconSize) or 25, (u and u.spacing) or 4
    elseif row == "buffs" then size, space = cfg.auraRow.iconSize or 25, cfg.auraRow.spacing or 4
    elseif row == "debuffs" then size, space = cfg.debuffRow.iconSize or 26, cfg.debuffRow.spacing or 4
    elseif row == "reminders" then size, space = cfg.reminders.iconSize or 40, cfg.reminders.spacing or 6
    elseif row == "aux" then size, space = cfg.aux.iconSize or 30, cfg.aux.spacing or 4 end
    return V2.LayoutDefaults(row, size, size, space)
end

function Engine:V2Tab_Look(L, cfg)
    local eng = self

    L:Card("Row layout")
    L:Desc("How a row's icons line up when there are several. Nothing saved keeps the row's own layout.")
    local row = RowPick(L, eng, "hudV2LayoutRow", eng:V2RowItems(true))
    local lg, ls = ns.CustomAccess(cfg, "layouts", row, function()
        for _, m in pairs(eng.memo) do HUD.ForgetLayout(m) end
        eng:Refresh()
    end)
    L:Add(UI.LayoutPicker(L.current, { width = UI.CardInnerWidth(L), get = lg, set = ls,
        defaults = function() return eng:V2LayoutDefaultsFor(cfg, row) end,
        fields = { grow = true, wrap = true, perLine = true, spacingX = true, spacingY = true, padding = true, reverse = true, max = true },
        maxItems = 40 }), 6)
    L:EndCard()

    L:Card("Icon states")
    L:Desc("A look per state over the HUD's own: ready, on cooldown, out of range, a buff up or about to run out. Only what you set changes.")
    local sg, ss = ns.CustomAccess(cfg, "states", nil, After(eng, cfg))
    L:Add(UI.StateEditor(L.current, { width = UI.CardInnerWidth(L), get = sg, set = ss,
        states = V2.STATES, remember = PageMem(), fields = V2.STATE_FIELDS,
        defaults = function() return V2.STATE_DEFAULTS end }), 6)
    local v = V2.Cfg(cfg)
    HUD.Slider(L, "About to run out under", 1, 15, (v and v.expiring) or V2.EXPIRING_DEFAULT, function(val)
        V2.Cfg(cfg, true).expiring = (val ~= V2.EXPIRING_DEFAULT) and val or nil
        V2.Tidy(cfg)
        eng:Refresh()
    end, { width = 240, format = Secs, desc = "When a buff or debuff counts as about to run out." })
    L:EndCard()

    if self.V2GlowCard then self:V2GlowCard(L, cfg) end
end

-- every icon a glow rule can sit on, { { value = key, text = label } ... }
function Engine:V2IconItems()
    local def, S = self.def, self.S
    local out = {}
    local function Add(list, row, prefix)
        for _, e in ipairs(list or {}) do
            out[#out + 1] = { value = V2.GlowKey(row, e.key), text = prefix .. (e.label or S.auraNames[e.key] or e.key) }
        end
    end
    Add(def.grid, "main", "")
    Add(def.utility, "utility", "Utility: ")
    Add(def.buffRow, "buffs", "Buff: ")
    Add(def.debuffRow, "debuffs", "Debuff: ")
    out[#out + 1] = { value = "aux:trinket1", text = "Trinket 1" }
    out[#out + 1] = { value = "aux:trinket2", text = "Trinket 2" }
    out[#out + 1] = { value = "aux:racial", text = "Racial" }
    return out
end

local function Sel(items, cur)
    for _, it in ipairs(items) do if (it.value or it.id) == cur then return it.text or it.label end end
    return items[1] and (items[1].text or items[1].label) or ""
end
local function Items(list)
    local out = {}
    for _, e in ipairs(list) do out[#out + 1] = { value = e.id, text = e.label } end
    return out
end

function Engine:V2GlowCard(L, cfg)
    if not V2.GLOW_WHEN then return end
    local eng = self
    L:Card("Glow rules")
    L:Desc("A glow on an icon while a condition holds: ready, its buff up or down, a stack count, a DoT safe to recast without clipping... An icon can carry several rules.")
    local iconKey = RowPick(L, eng, "hudV2GlowIcon", eng:V2IconItems())
    -- the spec's rules for an icon (read only: a change copies them first)
    local function SpecRules(gk)
        local role = eng.V2SpecRole and eng:V2SpecRole()
        return role and role.glows and role.glows[gk] or nil
    end
    local rules, mine
    if eng.V2RulesFor then rules, mine = eng:V2RulesFor(cfg, iconKey)
    else rules = type(cfg.glows) == "table" and cfg.glows[iconKey] or nil mine = true end
    local function After()
        if type(cfg.glows) == "table" then
            for k, list in pairs(cfg.glows) do
                -- an emptied list stays where the spec has rules ("none of them")
                if type(list) ~= "table" or (#list == 0 and not SpecRules(k)) then cfg.glows[k] = nil end
            end
            if next(cfg.glows) == nil then cfg.glows = nil end
        end
        eng:Refresh()
    end
    local function Own()
        cfg.glows = type(cfg.glows) == "table" and cfg.glows or {}
        if type(cfg.glows[iconKey]) ~= "table" then
            local copy = {}
            for i, r in ipairs(SpecRules(iconKey) or {}) do
                local c = {}
                for k, v in pairs(r) do c[k] = (type(v) == "table") and { r = v.r, g = v.g, b = v.b, a = v.a } or v end
                copy[i] = c
            end
            cfg.glows[iconKey] = copy
        end
        return cfg.glows[iconKey]
    end
    if rules and not mine then
        local names = {}
        for _, w in ipairs(V2.GLOW_WHEN) do names[w.id] = w.label end
        for idx, rule in ipairs(rules) do
            HUD.Label(L, "Rule " .. idx .. " (your spec's): " .. (names[rule.when or "ready"] or tostring(rule.when)))
        end
        HUD.Button(L, "Change these rules", 170, function()
            Own()
            After()
            HUD.RefreshPage()
        end, "Makes the spec's rules for this icon your own to change.")
        rules = nil
    elseif mine and SpecRules(iconKey) then
        HUD.Button(L, "Back to the spec's rules", 190, function()
            cfg.glows[iconKey] = nil
            After()
            HUD.RefreshPage()
        end)
    end
    for idx, rule in ipairs(mine and rules or {}) do
        HUD.Label(L, "Rule " .. idx, "highlight")
        local whenItems = Items(eng:V2GlowWhenFor(iconKey, rule.when))
        HUD.Dropdown(L, 260, whenItems, function() return Sel(whenItems, rule.when or "ready") end,
            function(val) rule.when = val After() HUD.RefreshPage() end)
        if rule.when == "stacks" then
            local ops = Items(V2.STACK_OPS)
            HUD.Dropdown(L, 160, ops, function() return Sel(ops, rule.stacksOp or ">=") end, function(val) rule.stacksOp = val After() end)
            HUD.Slider(L, "Stacks", 1, 20, tonumber(rule.stacksN) or 1, function(val) rule.stacksN = val After() end, { width = 200 })
        end
        local styles = Items(V2.GLOW_STYLES)
        HUD.Dropdown(L, 220, styles, function() return Sel(styles, rule.style or "edge") end,
            function(val) rule.style = val After() HUD.RefreshPage() end)
        -- (the game's own glow is its art: no colour of ours)
        local modes = { { value = "default", text = "The style's colour" }, { value = "class", text = "Class colour" }, { value = "custom", text = "A colour of mine" } }
        if rule.style ~= "blizzard" then
            HUD.Dropdown(L, 220, modes, function() return Sel(modes, rule.colorMode or "default") end,
                function(val) rule.colorMode = (val ~= "default") and val or nil After() HUD.RefreshPage() end)
        end
        if rule.colorMode == "custom" and rule.style ~= "blizzard" then
            HUD.ColorGrid(L, { { "Glow colour",
                get = function() return HUD.Col(rule.color, { r = 1, g = 0.82, b = 0, a = 1 }) end,
                set = function(r, g, b, a) rule.color = { r = r, g = g, b = b, a = a or 1 } After() end } })
        end
        local andItems = { { value = "none", text = "No second condition" } }
        for _, e in ipairs(eng.def.buffRow or {}) do
            andItems[#andItems + 1] = { value = e.key, text = "And " .. (e.label or eng.S.auraNames[e.key] or e.key) .. " is..." }
        end
        HUD.Dropdown(L, 260, andItems, function() return Sel(andItems, rule.andKey or "none") end,
            function(val) rule.andKey = (val ~= "none") and val or nil After() HUD.RefreshPage() end)
        if rule.andKey then
            local st = { { value = "up", text = "...up" }, { value = "down", text = "...down" } }
            HUD.Dropdown(L, 160, st, function() return Sel(st, rule.andState or "up") end, function(val) rule.andState = val After() end)
        end
        Check(L, "Only in combat", rule.combatOnly or false, function(on) rule.combatOnly = on or nil After() end)
        L:Add(UI.SoundPicker(L.current, { label = "Sound when it lights", width = 260, defaultLabel = "None",
            get = function() return rule.sound end,
            set = function(name) rule.sound = (name and name ~= "__d" and name ~= "none") and name or nil After() end }), 6)
        HUD.Button(L, "Remove this rule", 150, function()
            table.remove(rules, idx)
            After()
            HUD.RefreshPage()
        end)
    end
    HUD.Button(L, "Add a rule", 150, function()
        local list = Own()
        local first = eng:V2GlowWhenFor(iconKey)[1]
        list[#list + 1] = { when = first and first.id or "ready", style = "edge" }
        eng:Refresh()
        HUD.RefreshPage()
    end, "Rules are evaluated five times a second for the icons that have one; nothing runs without rules.")
    L:EndCard()
end

-- ------------------------------------------------------------
-- Text
-- ------------------------------------------------------------
function Engine:V2Tab_Text(L, cfg)
    local eng = self
    local v = V2.Cfg(cfg)

    L:Card("Cooldown text")
    local thr = v and v.threshold
    HUD.Slider(L, "Turn colour under", 0, 30, (thr and thr.seconds) or 0, function(val)
        local t = V2.Sub(cfg, "threshold", true)
        t.seconds = (val > 0) and val or nil
        if not t.seconds and not t.color then V2.Cfg(cfg).threshold = nil end
        V2.Tidy(cfg)
        eng:Refresh()
    end, { width = 240, format = Secs, desc = "A cooldown timer changes colour below this many seconds (0 = never)." })
    HUD.ColorGrid(L, { { "Colour under the threshold",
        get = function()
            local t = V2.Sub(cfg, "threshold")
            local c = t and t.color
            return HUD.Col(c, { r = 1, g = 0.2, b = 0.2, a = 1 })
        end,
        set = function(r, g, b, a)
            V2.Sub(cfg, "threshold", true).color = { r = r, g = g, b = b, a = a or 1 }
            eng:Refresh()
        end } })
    local fg, fs = ns.CustomAccess(cfg, "formats", "cooldown", After(eng, cfg))
    L:Add(UI.TextFormatPicker(L.current, { width = UI.CardInnerWidth(L), get = fg, set = fs,
        kinds = { time = true }, defaults = V2.TIME_DEFAULTS,
        sample = function(spec) return ns.FormatTime(83, spec, V2.TIME_DEFAULTS) .. "  /  " .. ns.FormatTime(7.4, spec, V2.TIME_DEFAULTS) end }), 6)
    L:Desc("How the cooldown numbers read; nothing saved reads as the HUD always has.")
    L:EndCard()

    L:Card("Keybind text")
    L:Desc("The key that casts an icon's spell, in its corner. Its spot is \"Keybind\" under Where the icon texts sit.")
    local keys = v and v.keys
    local rows = { { "main", "On the cooldown grid" }, { "aux", "On the trinket and racial row" } }
    if V2.UtilityOn(cfg) then table.insert(rows, 2, { "utility", "On the utility row" }) end
    for _, r in ipairs(rows) do
        Check(L, r[2], keys and keys[r[1]] or false, function(on)
            local k = V2.Sub(cfg, "keys", true)
            k[r[1]] = on or nil
            V2.Tidy(cfg)
            eng:V2SyncWants(cfg)
            if V2.Keys and V2.Keys.MarkDirty then V2.Keys.MarkDirty() end
            eng:Refresh()
        end)
    end
    HUD.Slider(L, "Keybind text size", 6, 20, (keys and keys.size) or V2.KEY_SIZE_DEFAULT, function(val)
        local k = V2.Sub(cfg, "keys", true)
        k.size = (val ~= V2.KEY_SIZE_DEFAULT) and val or nil
        V2.Tidy(cfg)
        eng:Refresh()
    end, { width = 240, format = Px })
    L:EndCard()
end

-- ------------------------------------------------------------
-- Position (inside the page's Position card)
-- ------------------------------------------------------------
function Engine:V2Tab_PositionCard(L, cfg)
    local eng = self
    if V2.UtilityOn(cfg) then
        HUD.ScaleSlider(L, "Utility row scale", V2.Sub(cfg, "utility", true), "scale", function() eng:ApplyAnchorPositions() end)
    end
end

-- ------------------------------------------------------------
-- Advanced
-- ------------------------------------------------------------
function Engine:V2Tab_Advanced(L, cfg)
    local eng = self
    local v = V2.Cfg(cfg)
    L:Card("Mouse")
    Check(L, "Mirror key presses on the icons", v and v.pressMirror or false, function(on)
        V2.Cfg(cfg, true).pressMirror = on or nil
        V2.Tidy(cfg)
        eng:V2SyncWants(cfg)
    end, nil, "An icon darkens while the key that casts it is held, even on cooldown.")
    L:Desc("Tooltips on hover, per row. An icon with a tooltip takes the mouse; the rest stay click-through.")
    local tips = v and v.tooltips
    for _, it in ipairs(eng:V2RowItems(true)) do
        if it.value ~= "reminders" then
            Check(L, "Tooltips: " .. it.text:lower(), tips and tips[it.value] or false, function(on)
                local t = V2.Sub(cfg, "tooltips", true)
                t[it.value] = on or nil
                V2.Tidy(cfg)
                eng:Refresh()
            end, 16)
        end
    end
    L:EndCard()
end
