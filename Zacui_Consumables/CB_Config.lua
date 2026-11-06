-- CB_Config - the Consumable bars page (Combat > Consumable bars): the
-- consumables, potion and weapon bars - one chosen at the top, its
-- settings in the house tabs - with the bar itself in the preview, on a
-- made-up set of bags and buffs. Readycheck's settings come over from
-- Advanced; while Readycheck runs its own copy of a bar that is on here,
-- a note offers to switch Readycheck's off.
-- Part of ZacUI; load order is set by the TOC.

local ADDON_NAME = ...
local ns = _G.ZacUI
if not ns then return end
local D, CB = ns.ConsData, ns.ConsBars
if not (D and CB and CB.Button and CB.Live) then return end

local UI = ns.UI
local M = UI.M
local B, Live = CB.Button, CB.Live
local format = string.format
local PAGE = "consbars"
local PREVIEW = "consbars.bar"

-- the menu row (with the other things that draw in a fight) and the
-- words people type that are not on the page
do
    local menu = ns.ConfigMenu
    local group
    for _, item in ipairs(menu or {}) do if item.id == "combat" and item.children then group = item end end
    if group then
        local have = false
        for _, c in ipairs(group.children) do if c.id == PAGE then have = true end end
        if not have then
            group.children[#group.children + 1] = { id = PAGE, label = "Consumable bars", page = "ConsBars",
                addon = "Zacui_Consumables", keywords = "consumables consumable bar bars potion potions flask flasks "
                    .. "elixir elixirs juju jujus food buff buffs weapon stone stones sharpening oil oils poison "
                    .. "poisons readycheck helper" }
        end
    end
    if ns.AddMenuKeywords then
        ns.AddMenuKeywords(PAGE, "sharpening weightstone wizard mana oil zanza mongoose titans rage "
            .. "petrification camp self cast hide combat expiry timer glow tts voice speak order hidden "
            .. "custom item id quick use shift alt ctrl modifier horde windfury mainhand offhand bag "
            .. "font colour color anchor corner format animation fade mouseover opacity scale layer import")
    end
end

local function Cfg() ZacUIDB.config = ZacUIDB.config or {} return ZacUIDB.config end
local function Which()
    local v = Cfg().consBar
    if v == "potions" or v == "weapons" then return v end
    return "main"
end
local function Bc() return CB.Bar(Which()) end
local function Px(v) return format("%d px", v) end
local function Changed(src) if ns.SettingsChanged then ns.SettingsChanged(src or "consbars") end end
local function Rebuild() if ns.RefreshConfig then ns.RefreshConfig() end end

local function Check(L, label, value, fn, desc, tip)
    local w = UI.Checkbox(L.current, label, value and true or false, fn, tip and { tooltip = tip } or nil)
    L:Row(w, M.ROW)
    if desc then L:Desc(desc) end
    return w
end
local function Opt(L, key, label, desc, default, after)
    local c = Bc()
    local v = c[key]
    if v == nil then v = default end
    return Check(L, label, v, function(on) c[key] = on and true or false if after then after() end end, desc)
end
local function Slider(L, key, label, min, max, step, fmt, desc, onSet)
    local c = Bc()
    local w = UI.Slider(L.current, { width = 240, min = min, max = max, step = step or 1,
        value = tonumber(c[key]) or min, label = label, format = fmt or Px,
        onChange = function(v) if onSet then onSet(v) else c[key] = v end end })
    L:Row(w, 40)
    if desc then L:Desc(desc) end
    return w
end
local function Drop(L, label, items, get, set, width)
    local w = UI.Field(L.current, label, function(h)
        return UI.Dropdown(h, { width = width or 240,
            items = function() return items end,
            selected = function()
                local v = get()
                for _, it in ipairs(items) do if it.value == v then return it.text end end
                return items[1] and items[1].text or ""
            end,
            selectedValue = get,
            onSelect = function(v) set(v) end })
    end, { width = width or 240 })
    L:Add(w, 8)
    return w
end
local function Pairs(list)
    local out = {}
    for _, p in ipairs(list) do out[#out + 1] = { value = p[1], text = p[2] } end
    return out
end
local function ItemName(id)
    local it = D.BY_ID[id]
    return (GetItemInfo and GetItemInfo(id)) or (it and (it.displayName or it.name))
        or (CB.T(Bc(), "customItems") and Bc().customItems[id] and Bc().customItems[id].name) or ("Item #" .. id)
end

-- ============================================================
-- THE PREVIEW - the bar itself on a made-up world
-- ============================================================
local ICONS = {
    [13510] = "INV_Potion_62", [13452] = "INV_Potion_32", [12451] = "INV_Misc_MonsterScales_11",
    [12460] = "INV_Misc_MonsterScales_07", [20079] = "INV_Potion_30", [21023] = "INV_Misc_Food_65",
    [20452] = "INV_Misc_Food_64", [13442] = "INV_Potion_41", [13446] = "INV_Potion_54", [3387] = "INV_Potion_62",
    [5634] = "INV_Potion_04", [13457] = "INV_Potion_24", [18262] = "INV_Stone_02", [10646] = "Spell_Fire_SelfDestruct",
    [18641] = "INV_Misc_Bomb_06", [14530] = "INV_Misc_Bandage_12", [12820] = "INV_Potion_92",
}
local Fake = {}
local FAKE_COUNTS = {
    [13510] = 3, [13452] = 8, [12451] = 12, [12460] = 14, [20079] = 1, [21023] = 6, [20452] = 12, [13442] = 11,
    [13446] = 6, [3387] = 4, [5634] = 5, [13457] = 3, [13456] = 2, [9030] = 2, [18262] = 7, [10646] = 9,
    [18641] = 15, [13180] = 6, [14530] = 20, [12820] = 4, [20004] = 3, [13454] = 0,
}
-- "running": a few buffs on, one about to go, a potion on its cooldown,
-- the weapons enchanted
-- "low": a buff in its last seconds, the main hand's stone under five
-- minutes, the off hand's poison down to its last charges
local FAKE_BUFFS = { running = { [17538] = 40, [16323] = 1500, [25661] = 600, [24383] = 2400 },
    low = { [17538] = 12, [16323] = 1500 } }
-- TBC / Forever (the client, or the game-version override): that game's
-- items in the same states (CB_Data_TBC / CB_Data_Forever)
local FAKE_ENCHANT = 2506
if D.PREVIEW then
    FAKE_COUNTS, FAKE_BUFFS, FAKE_ENCHANT = D.PREVIEW.counts, D.PREVIEW.buffs, D.PREVIEW.enchant or 2506
    for id, icon in pairs(D.PREVIEW.icons or {}) do ICONS[id] = icon end
end
local fakeMode = "ready"
function Fake.Now() return GetTime() end
function Fake.Count(id) return FAKE_COUNTS[id] or 0 end
function Fake.Buff(buffId)
    local t = FAKE_BUFFS[fakeMode]
    local r = t and buffId and t[buffId]
    if r then return true, r end
    return false, 0
end
-- (a buff known only by its name: by its lower-case name)
function Fake.NamedBuff(name)
    return Fake.Buff(name and name:lower())
end
function Fake.ItemBuff(id)
    local it = D.BY_ID[id]
    if it and it.buffId == nil and it.buffName then return Fake.NamedBuff(it.buffName) end
    return Fake.Buff(it and it.buffId)
end
function Fake.GroupBuff(g)
    for id in pairs(D.CONFLICT[g] or {}) do
        local h, r = Fake.ItemBuff(id)
        if h then return true, r, id end
    end
    -- (TBC: a flask fills both elixir slots, as the live bar reads it)
    for _, og in ipairs(D.GROUP_BLOCKS and D.GROUP_BLOCKS[g] or {}) do
        for id in pairs(D.CONFLICT[og] or {}) do
            local h, r = Fake.ItemBuff(id)
            if h then return true, r, id end
        end
    end
    return false, 0, nil
end
function Fake.Cooldown(id)
    if fakeMode == "running" and id == 13442 then return GetTime() - 73, 120 end
    return 0, 0
end
function Fake.Enchant(slot)
    if fakeMode == "low" then
        -- (as the live reader says it: a poison at its last charges reads 5 s)
        if slot == "mainhand" then return true, 240, FAKE_ENCHANT, 0, false, 240 end
        -- (TBC's poisons have no charges: no last charges to show)
        if (D.POISON_LOW_CHARGES or 10) <= 0 then return true, 1500, nil, 0, false, 1500 end
        return true, 5, nil, (D.POISON_LOW_CHARGES or 10) - 2, true, 1500
    end
    if fakeMode ~= "running" then return false, 0, nil, 0 end
    if slot == "mainhand" then return true, 1200, FAKE_ENCHANT, 0 end
    return true, 35, FAKE_ENCHANT, 0
end
function Fake.BagEnchant() return false, 0 end
local SWORD, DAGGER = "Interface\\Icons\\INV_Sword_39", "Interface\\Icons\\INV_Weapon_ShortBlade_16"
function Fake.Equipped(inv)
    if inv == 16 then return { texture = SWORD, itemId = 1, name = "Main hand sword", sharpenable = true } end
    return { texture = DAGGER, itemId = 2, name = "Off hand dagger", sharpenable = true }
end
function Fake.BagWeapons()
    return { { bag = 0, slot = 5, link = nil, itemId = 3, name = "Spare Sword", texture = "Interface\\Icons\\INV_Sword_27" } }
end
function Fake.GCD() return 0, 0 end
function Fake.Eating() return false, 0 end
function Fake.Cast() return nil end
function Fake.InCombat() return false end
function Fake.ItemName(id) local it = D.BY_ID[id] return it and it.name end
function Fake.ItemIcon(id)
    local live = GetItemIcon and id and GetItemIcon(id)
    if live then return live end
    local cat = D.PREVIEW and D.PREVIEW.catIcons and D.CATEGORY_OF[id]
    return "Interface\\Icons\\" .. (ICONS[id] or (cat and D.PREVIEW.catIcons[cat]) or "INV_Misc_QuestionMark")
end
CB.FakeWorld = Fake

local function SampleButton(P, i)
    local st = P.store
    local b = st.buttons[i]
    if not b then
        b = CreateFrame("Button", nil, st.box)
        B.Dress(b, true)
        b:SetScript("OnClick", function()
            if ns.CustomPick then ns.CustomPick.Pick(PREVIEW, "consbars.button") end
        end)
        st.buttons[i] = b
    end
    return b
end

local function BuildPreview(canvas, P)
    P.store.box = Live.NewBox(canvas)
    P.store.box:SetPoint("TOPLEFT", canvas, "TOPLEFT", 4, -4)
    P.store.buttons = {}
    if ns.TagElement then ns.TagElement(P.store.box.bg, "consbars.bar") end
    -- the clash group's menu, as a right click on a clashing item opens it
    if UI.ContextMenuSample then
        P.store.menu = UI.ContextMenuSample(canvas)
        P.store.menu:Hide()
    end
end

local function UpdatePreview(canvas, P)
    local key = Which()
    local cfg = CB.Bar(key)
    fakeMode = (P.mode == "picker") and "ready" or (P.mode or "ready")
    local st = P.store
    local entries = CB.Collect(key, cfg, Fake)
    local size, per, gap, grow = CB.Geo(cfg)
    -- (the live bar redraws its buttons on a change; so does the sample)
    B.Restyle()
    for i, e in ipairs(entries) do
        local b = SampleButton(P, i)
        b:SetSize(size, size)
        b._zSig = nil
        B.Fill(b, e, key, cfg, Fake)
        local x, y = CB.GridOffset(i, per, size, gap, grow)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", st.box, "TOPLEFT", x, y)
        b:Show()
        B.Tick(b, key, cfg, Fake, { now = GetTime(), cast = {} }, true)
    end
    for i = #entries + 1, #st.buttons do st.buttons[i]:Hide() end
    local w, h = CB.BarSize(#entries, per, size, gap, grow)
    local sc = tonumber(cfg.scale) or 1
    if sc <= 0 then sc = 1 end
    st.box:SetScale(sc)
    st.box:SetSize(w, h)
    Live.PaintChrome(st.box, cfg, cfg.locked == false)
    local cw, ch = w * sc + 8, h * sc + 8
    -- "Clash picker": the menu hanging under the first clashing item,
    -- filled by the live bar's own Live.GroupPickerItems (nothing on it clicks)
    local menu = st.menu
    if menu then
        local at, group
        if P.mode == "picker" then
            for i, e in ipairs(entries) do
                if e.grouped and e.group and D.PRIORITY[e.group] then at, group = i, e.group break end
            end
        end
        local items = at and Live.GroupPickerItems(key, group, Fake)
        if items then
            local shown = {}
            for i, it in ipairs(items) do
                shown[i] = { text = it.text, checked = it.checked, separator = it.separator }
            end
            menu:Fill(shown)
            local bx, by = CB.GridOffset(at, per, size, gap, grow)
            local mx, my = 4 + bx * sc, 4 + (-by + size) * sc + 2
            menu:ClearAllPoints()
            menu:SetPoint("TOPLEFT", canvas, "TOPLEFT", mx, -my)
            menu:Show()
            st.menuAt = st.buttons[at]
            cw = math.max(cw, mx + (menu:GetWidth() or 120) + 4)
            ch = math.max(ch, my + (menu:GetHeight() or 60) + 4)
        else
            menu:Hide()
            st.menuAt = nil
        end
    end
    if P.Resize then P.Resize(cw, ch) end
end

-- the strip's modes; the weapon bar has no clash groups
local function PreviewModes()
    local m = { { id = "ready", label = "Ready" }, { id = "running", label = "Buffs up" },
        { id = "low", label = "Running low" } }
    if Which() ~= "weapons" then m[#m + 1] = { id = "picker", label = "Clash picker" } end
    return m
end

local function ReplayPreview(canvas, P)
    local box = P.store.box
    local cfg = Bc()
    if ns.Motion then
        ns.Motion.StopTree(box)
        box:Hide()
        ns.Motion.Show(box, B.Spec(cfg, "showAnim"))
    end
end

-- ============================================================
-- THE TOP OF EVERY TAB: which bar, and Readycheck's twin
-- ============================================================
local function BarChooser(L)
    L:Card("Which bar")
    Drop(L, "Bar", { { value = "main", text = CB.LABELS.main }, { value = "potions", text = CB.LABELS.potions },
        { value = "weapons", text = CB.LABELS.weapons } }, Which, function(v) Cfg().consBar = v Rebuild() end)
    L:Desc("Every setting below is this bar's. The bar's own switch is on the General tab.")
    L:EndCard()
end

local function RCNote(L)
    local key = Which()
    if not (Bc().enabled and CB.ReadycheckBarOn(key)) then return end
    L:Notice("warn", "Readycheck's " .. CB.LABELS[key]:lower() .. " is on too, so you have two of them on screen.")
    L:Card("Readycheck's " .. CB.LABELS[key]:lower())
    local b = UI.Button(L.current, "Turn Readycheck's off", { width = 200, onClick = function()
        if InCombatLockdown() then return end
        local ok, why = CB.TurnOffReadycheck(key)
        if ns.Print then ns.Print(why) end
        Rebuild()
    end })
    L:Row(b, M.BUTTON_H + 6)
    L:Desc("Only its on switch changes; turn it back on in Readycheck any time.")
    L:EndCard()
end

-- ============================================================
-- GENERAL
-- ============================================================
local function Tab_general(L)
    local key, c = Which(), Bc()
    L:Card(CB.LABELS[key])
    Check(L, "Show the " .. CB.LABELS[key]:lower(), c.enabled, function(v) c.enabled = v and true or false end,
        "Off until you turn it on. Clicks use the item; the bar changes out of combat only.")
    Opt(L, "hideInCombat", "Hide in combat", "It goes see-through in a fight; its buttons still take a click.")
    L:EndCard()

    L:Card("What it shows")
    if key ~= "weapons" then
        Opt(L, "showOnlyAvailable", "Only items in your bags")
        Opt(L, "hideWhenActive", "Hide while the buff is up", "It comes back when the buff is about to run out.")
    end
    if key == "main" then
        Opt(L, "hideConflictingBuffs", "Hide items whose buff clashes with one that is up")
        Opt(L, "groupConflictButtons", "One button for items that clash", "Right click it to pick which one it uses.", true)
        Opt(L, "hideUsedInCombat", "Hide an item once used in combat", "Back when the fight ends.", true)
        Opt(L, "selfCastJujus", "Jujus on yourself", "A click never throws a juju at your target.", true)
        Opt(L, "showBagWeapons", "Buttons for weapons in your bags")
    end
    if key == "weapons" then
        Opt(L, "showEquippedWeapons", "Your main and off hand", nil, true)
        Opt(L, "showBagWeapons", "Weapons in your bags", nil, true)
    end
    if key ~= "potions" then
        Check(L, "Horde mode: no main hand button", CB.HordeMode(c), function(v) CB.SetHordeMode(c, v) end,
            "For Windfury Totem on the main hand. Kept for this faction only.")
    end
    if key ~= "weapons" then
        Opt(L, "petrificationCampMode", "Flask of Petrification also logs out (/camp)")
    end
    L:EndCard()

    L:Card("Running out")
    Slider(L, "showBeforeExpiry", "Warning time", key == "weapons" and 0 or 10, 300, key == "weapons" and 10 or 5,
        function(v) return format("%d s", v) end, "A buff under this comes back, glows and counts down.")
    Opt(L, "showExpiryTimer", "Count it down on the button", nil, true)
    L:EndCard()

    L:Card("Show in")
    local modes = Pairs(CB.MODES)
    Drop(L, "Show the bar", modes, function() return c.visibilityMode or "always" end,
        function(v) c.visibilityMode = v Rebuild() end)
    local mode = c.visibilityMode or "always"
    if mode == "raids" or mode == "raids_and_city" then
        local boxes = {}
        for _, r in ipairs(CB.RAIDS) do
            local name = r[1]
            boxes[#boxes + 1] = UI.Checkbox(L.current, name, CB.T(c, "visibilityRaids") and c.visibilityRaids[name] or false,
                function(v)
                    if type(c.visibilityRaids) ~= "table" then c.visibilityRaids = {} end
                    c.visibilityRaids[name] = v and true or nil
                    if next(c.visibilityRaids) == nil then c.visibilityRaids = nil end
                end)
        end
        L:Grid(boxes, 2, M.ROW)
        L:Desc("No raid ticked: every raid.")
    end
    L:EndCard()

    L:Card("When the bar shows")
    local vg, vs = ns.CustomAccess(Bc, "visibility", nil)
    L:Add(UI.VisibilityPicker(L.current, { width = UI.CardInnerWidth(L), get = vg, set = vs,
        shows = { "always", "combat", "nocombat", "group", "raid", "instance", "resting", "mouseover" } }), 6)
    L:Desc("On top of Show in. A hidden bar only fades out: its buttons still take clicks.")
    L:EndCard()

    L:Card("Fade when not hovered")
    Opt(L, "mouseoverFade", "Fade the bar while the mouse is away")
    local fa = UI.Slider(L.current, { width = 240, min = 0, max = 100, step = 5,
        value = math.floor((tonumber(c.mouseoverFadeAlpha) or 0.15) * 100 + 0.5), label = "Faded opacity",
        format = function(v) return format("%d%%", v) end, onChange = function(v) c.mouseoverFadeAlpha = v / 100 end })
    L:Row(fa, 40)
    L:EndCard()

    L:Card("Voice")
    Opt(L, "tts", "Say the name when it is running out", "ZacUI's voice (General page).")
    if key == "main" then
        local g = CB.Cfg()
        Check(L, "Say when the potion cooldown ends", g.potionReadyTTS, function(v) g.potionReadyTTS = v and true or false end)
        Check(L, "Say it again after the buff is gone", g.ttsRepeat, function(v) g.ttsRepeat = v and true or false Rebuild() end)
        local r1 = UI.Slider(L.current, { width = 240, min = 1, max = 10, step = 1, value = g.ttsRepeatCount or 1,
            label = "Times", format = function(v) return tostring(v) end, onChange = function(v) g.ttsRepeatCount = v end })
        local r2 = UI.Slider(L.current, { width = 240, min = 10, max = 300, step = 5, value = g.ttsRepeatInterval or 60,
            label = "Every", format = function(v) return format("%d s", v) end, onChange = function(v) g.ttsRepeatInterval = v end })
        L:Dependent({ r1, r2 }, g.ttsRepeat, 2, M.CHECK + 6)
    end
    L:EndCard()
end

-- ============================================================
-- ITEMS (the consumables and potion bars)
-- ============================================================
local function Catalogue(key, cfg)
    local list = CB.Catalogue(key, cfg)
    table.sort(list, function(a, b)
        local ac, bc = D.CATEGORY_ORDER[a.category] or 99, D.CATEGORY_ORDER[b.category] or 99
        if ac ~= bc then return ac < bc end
        return (a.data.name or "") < (b.data.name or "")
    end)
    return list
end

local function Tab_items(L)
    local key, c = Which(), Bc()
    if key == "weapons" then
        L:Card("Items")
        L:Desc("The weapon bar's buttons are your weapons: the Weapons tab picks them.")
        L:EndCard()
        return
    end
    local list = Catalogue(key, c)
    L:Card("Shown items")
    local all = UI.Button(L.current, "Show all", { width = 110, onClick = function()
        for _, e in ipairs(list) do CB.SetHidden(key, c, e.id, false) end
        if key == "main" then CB.SetHidden(key, c, CB.MH, false) CB.SetHidden(key, c, CB.OH, false) end
        Changed() Rebuild()
    end })
    local none = UI.Button(L.current, "Hide all", { width = 110, onClick = function()
        for _, e in ipairs(list) do CB.SetHidden(key, c, e.id, true) end
        Changed() Rebuild()
    end })
    L:Flow({ all, none }, 8, 6)
    local cat
    local boxes = {}
    local function Flush()
        if #boxes > 0 then L:Grid(boxes, 2, M.ROW) boxes = {} end
    end
    if key == "main" then
        boxes[#boxes + 1] = UI.Checkbox(L.current, "Main hand stone", not CB.Hidden(key, c, CB.MH),
            function(v) CB.SetHidden(key, c, CB.MH, not v) end)
        boxes[#boxes + 1] = UI.Checkbox(L.current, "Off hand stone", not CB.Hidden(key, c, CB.OH),
            function(v) CB.SetHidden(key, c, CB.OH, not v) end)
    end
    for _, e in ipairs(list) do
        if e.category ~= cat then
            Flush()
            cat = e.category
            L:Desc(D.CATEGORY_NAMES[cat] or cat)
        end
        local id = e.id
        boxes[#boxes + 1] = UI.Checkbox(L.current, e.data.displayName or e.data.name or ("Item #" .. id),
            not CB.Hidden(key, c, id), function(v) CB.SetHidden(key, c, id, not v) end)
    end
    Flush()
    L:EndCard()

    -- the order: an item moved earlier or later (the rest keep theirs)
    L:Card("Order")
    local order = {}
    local seen = {}
    for _, id in ipairs(CB.T(c, "itemOrder") or {}) do order[#order + 1] = id seen[id] = true end
    local entries = CB.Collect(key, c, CB.World)
    for _, e in ipairs(entries) do
        local k = CB.SortKey(e)
        if not seen[k] then order[#order + 1] = k seen[k] = true end
    end
    local items = {}
    -- (TBC / Forever: a saved place of an item this game does not have
    -- stays in the saved order, unlisted)
    local custom = CB.T(c, "customItems")
    local function Here(id)
        return not D.FLAVOR or id == CB.MH or id == CB.OH or id == 999903 or D.BY_ID[id] ~= nil
            or (custom and (custom[id] or custom[tostring(id)])) and true or false
    end
    for _, id in ipairs(order) do
        local label = (id == CB.MH and "Main hand stone") or (id == CB.OH and "Off hand stone")
            or (id == 999903 and "Bag weapons") or ItemName(id)
        if Here(id) then items[#items + 1] = { value = id, text = label } end
    end
    if #items == 0 then
        L:Desc("Nothing on the bar yet: the order follows the items you carry.")
    else
        local pick = Cfg().consOrderPick
        if not seen[pick] or not Here(pick) then pick = items[1].value end
        Drop(L, "Item", items, function() return pick end, function(v) Cfg().consOrderPick = v Rebuild() end)
        local function Move(d)
            local at
            for i, id in ipairs(order) do if id == pick then at = i end end
            if not at then return end
            local to = math.max(1, math.min(#order, at + d))
            if d == -999 then to = 1 end
            table.remove(order, at)
            table.insert(order, to, pick)
            c.itemOrder = order
            Changed() Rebuild()
        end
        local first = UI.Button(L.current, "First", { width = 80, onClick = function() Move(-999) end })
        local up = UI.Button(L.current, "Earlier", { width = 80, onClick = function() Move(-1) end })
        local down = UI.Button(L.current, "Later", { width = 80, onClick = function() Move(1) end })
        local reset = UI.Button(L.current, "Back to the usual order", { width = 180, onClick = function()
            c.itemOrder = nil Changed() Rebuild()
        end })
        L:Flow({ first, up, down, reset }, 8, 6)
        L:Desc("The usual order: by category, items that clash together, then by name.")
    end
    L:EndCard()

    L:Card("Your own items")
    local addId, addCat = nil, "custom"
    local eb = UI.EditBox(L.current, { width = 140, hint = "Item ID", onChange = function(t) addId = tonumber(t) end,
        onEnter = function(t) addId = tonumber(t) end })
    L:Row(eb, 30)
    local cats = { { value = "custom", text = "Custom" } }
    for _, k in ipairs(D.CATEGORY_KEYS) do cats[#cats + 1] = { value = k, text = D.CATEGORY_NAMES[k] } end
    Drop(L, "Category", cats, function() return addCat end, function(v) addCat = v end)
    local add = UI.Button(L.current, "Add item", { width = 120, onClick = function()
        if not addId or addId <= 0 then if ns.Print then ns.Print("Enter an item ID first.") end return end
        if type(c.customItems) ~= "table" then c.customItems = {} end
        c.customItems[addId] = { name = (GetItemInfo and GetItemInfo(addId)) or ("Item #" .. addId), category = addCat }
        Changed() Rebuild()
    end })
    L:Row(add, M.BUTTON_H + 6)
    local mine = {}
    for id, it in pairs(CB.T(c, "customItems") or {}) do mine[#mine + 1] = { id = id, it = it } end
    table.sort(mine, function(a, b) return tostring(a.it.name) < tostring(b.it.name) end)
    for _, m in ipairs(mine) do
        local id = m.id
        local rm = UI.Button(L.current, "Remove " .. tostring(m.it.name), { width = 220, onClick = function()
            c.customItems[id] = nil
            if next(c.customItems) == nil then c.customItems = nil end
            Changed() Rebuild()
        end })
        L:Row(rm, M.BUTTON_H + 4)
    end
    if #mine == 0 then L:Desc("None yet. An item added here gets a button like the rest.") end
    L:EndCard()

    if key == "main" then
        -- a clash group: which item its button uses, and shift / alt / ctrl + click
        L:Card("Items that clash")
        local groups = {}
        for _, g in ipairs(D.GROUP_LABELS) do
            if D.PRIORITY[g.key] and #D.PRIORITY[g.key] > 1 then groups[#groups + 1] = { value = g.key, text = g.label } end
        end
        local g = Cfg().consGroup
        local okG = false
        for _, x in ipairs(groups) do if x.value == g then okG = true end end
        if not okG then g = groups[1].value end
        Drop(L, "Group", groups, function() return g end, function(v) Cfg().consGroup = v Rebuild() end)
        local AUTO = 0
        local choices = { { value = AUTO, text = "Auto (first in your bags)" } }
        local qchoices = { { value = AUTO, text = "Not set" } }
        for _, id in ipairs(D.PRIORITY[g]) do
            choices[#choices + 1] = { value = id, text = ItemName(id) }
            qchoices[#qchoices + 1] = { value = id, text = ItemName(id) }
        end
        Drop(L, "The button uses", choices, function()
            return (CB.T(c, "conflictGroupPreferences") and c.conflictGroupPreferences[g]) or AUTO
        end, function(v)
            if type(c.conflictGroupPreferences) ~= "table" then c.conflictGroupPreferences = {} end
            c.conflictGroupPreferences[g] = (v ~= AUTO) and v or nil
            if next(c.conflictGroupPreferences) == nil then c.conflictGroupPreferences = nil end
        end)
        for _, m in ipairs(CB.QUICK_MODS) do
            local mk = m[1]
            Drop(L, m[2] .. (mk == "click" and "" or " + click") .. " uses", qchoices, function()
                local q = CB.T(c, "conflictGroupQuickUse") and c.conflictGroupQuickUse[g]
                return (q and q[mk]) or AUTO
            end, function(v)
                if type(c.conflictGroupQuickUse) ~= "table" then c.conflictGroupQuickUse = {} end
                local q = c.conflictGroupQuickUse[g] or {}
                q[mk] = (v ~= AUTO) and v or nil
                c.conflictGroupQuickUse[g] = next(q) and q or nil
                if next(c.conflictGroupQuickUse) == nil then c.conflictGroupQuickUse = nil end
            end)
        end
        L:Desc("Works in combat too. Grouping is on the General tab.")
        L:EndCard()
    end

    -- what the voice says for one item
    L:Card("What the voice says")
    local vitems = {}
    for _, e in ipairs(list) do
        if e.data.buffId or e.data.buffName then vitems[#vitems + 1] = { value = e.id, text = e.data.name } end
    end
    if #vitems > 0 then
        local vid = Cfg().consVoiceItem
        local okV = false
        for _, x in ipairs(vitems) do if x.value == vid then okV = true end end
        if not okV then vid = vitems[1].value end
        Drop(L, "Item", vitems, function() return vid end, function(v) Cfg().consVoiceItem = v Rebuild() end)
        local g = CB.Cfg()
        local function Item(make)
            if type(g.itemTTS) ~= "table" then if not make then return nil end g.itemTTS = {} end
            local t = g.itemTTS[tostring(vid)]
            if not t and make then t = {} g.itemTTS[tostring(vid)] = t end
            return t
        end
        local function Tidy()
            local t = Item(false)
            if t and next(t) == nil then g.itemTTS[tostring(vid)] = nil end
            if type(g.itemTTS) == "table" and next(g.itemTTS) == nil then g.itemTTS = nil end
        end
        Check(L, "Say this one", CB.Voice.ItemOn(vid), function(v) Item(true).ttsEnabled = v and true or false Tidy() end)
        Check(L, "Say it again after it is gone", CB.Voice.RepeatOn(vid), function(v)
            Item(true).repeatEnabled = (not v) and false or nil Tidy() end)
        local t = Item(false)
        local eb2 = UI.EditBox(L.current, { width = 220, text = (t and t.ttsText) or "", hint = D.SpokenName(ItemName(vid)),
            onEnter = function(s) Item(true).ttsText = (s ~= "") and s or nil Tidy() end })
        L:Row(eb2, 30)
        L:Desc("Empty: the short name (" .. tostring(D.SpokenName(D.BY_ID[vid] and D.BY_ID[vid].name)) .. ").")
    end
    L:EndCard()
end

-- ============================================================
-- WEAPONS (stones and oils; the weapon bar's clicks)
-- ============================================================
local function Tab_weapons(L)
    local key, c, g = Which(), Bc(), CB.Cfg()
    if key == "potions" then
        L:Card("Weapons")
        L:Desc("The potion bar has no weapon buttons.")
        L:EndCard()
        return
    end
    L:Card("The stone or oil")
    local stones = {}
    for _, s in ipairs(D.STONES) do stones[#stones + 1] = { value = s.id, text = CB.StoneName(s.id) } end
    Drop(L, "Put on", stones, function() return g.stone or D.DEFAULT_STONE or 18262 end, function(v) g.stone = v end, 260)
    L:Desc("Right click a weapon button to change it there. Not in your bags: the best one you carry.")
    Check(L, "Weapon icons on the hand buttons", g.weaponIcons ~= false, function(v) g.weaponIcons = v and true or false end,
        "Off: the stone's icon. Both bars.")
    L:EndCard()

    L:Card("Weapons shown")
    local list = {}
    for _, inv in ipairs({ 16, 17 }) do
        local eq = CB.World.Equipped(inv)
        if eq and eq.itemId and eq.sharpenable then list[#list + 1] = { id = eq.itemId, name = eq.name or ("Item #" .. eq.itemId) } end
    end
    for _, wp in ipairs(CB.World.BagWeapons()) do list[#list + 1] = { id = wp.itemId, name = wp.name } end
    local boxes = {}
    for _, w in ipairs(list) do
        local id = w.id
        boxes[#boxes + 1] = UI.Checkbox(L.current, w.name, not (CB.T(c, "hiddenWeapons") and c.hiddenWeapons[id]),
            function(v)
                if type(c.hiddenWeapons) ~= "table" then c.hiddenWeapons = {} end
                c.hiddenWeapons[id] = (not v) and true or nil
                if next(c.hiddenWeapons) == nil then c.hiddenWeapons = nil end
            end)
    end
    if #boxes > 0 then L:Grid(boxes, 2, M.ROW) else L:Desc("No weapon that takes a stone is equipped or in your bags.") end
    L:EndCard()

    if key == "weapons" then
        L:Card("What each click does")
        local acts = Pairs(CB.CLICK_ACTIONS)
        for _, s in ipairs(CB.CLICK_SLOTS) do
            local slot = s[1]
            Drop(L, s[2], acts, function() return Live.WeaponClickAction(slot) end, function(v)
                if type(c.clickActions) ~= "table" then c.clickActions = {} end
                c.clickActions[slot] = (v ~= CB.WEAPON_CLICK_DEFAULTS[slot]) and v or nil
                if next(c.clickActions) == nil then c.clickActions = nil end
            end, 220)
        end
        L:Desc("Equipping is a secure weapon swap, so it works in combat.")
        L:EndCard()
    end
end

-- ============================================================
-- LOOK
-- ============================================================
local function Colour(L, key, label)
    local c = Bc()
    local w = UI.ColorPicker(L.current, { label = label, alpha = true,
        get = function() return CB.T(c, "colors") and c.colors[key] or nil end,
        set = function(r, g, b, a)
            if r then
                if type(c.colors) ~= "table" then c.colors = {} end
                c.colors[key] = { r = r, g = g, b = b, a = a or 1 }
            elseif CB.T(c, "colors") then
                c.colors[key] = nil
                if next(c.colors) == nil then c.colors = nil end
            end
        end,
        default = function() return B.BarColor({}, key) end, reset = true })
    L:Row(w, 22)
    return w
end

local function Tab_look(L)
    local key, c = Which(), Bc()
    L:Card("Buttons")
    Slider(L, "buttonSize", "Button size", 24, 64, 2)
    Slider(L, "buttonsPerRow", "Per row", 1, 20, 1, function(v) return tostring(v) end)
    Slider(L, "iconSpacing", "Space between", 0, 12, 1)
    Drop(L, "New buttons go", { { value = "DOWN", text = "Along the row, then down" },
        { value = "RIGHT", text = "Down the column, then right" } }, function() return c.growDirection or "DOWN" end,
        function(v) c.growDirection = v end)
    Opt(L, "showBackground", "Background and border", nil, key == "weapons")
    Opt(L, "showCount", "Stack count", nil, true)
    Opt(L, "showItemNames", "Item names on the buttons")
    Opt(L, "showTooltips", "Item tooltips on hover")
    L:EndCard()

    L:Card("Bar colours")
    Colour(L, "frameBackground", "Background")
    Colour(L, "frameBorder", "Edge")
    Colour(L, "accentLine", "Accent line")
    Colour(L, "buttonBorder", "Button edge")
    Colour(L, "activeBorder", "Button edge while the buff is up")
    if key == "main" then
        Colour(L, "conflictBackground", "Clashing buff fill")
        Colour(L, "conflictBorder", "Clashing buff edge")
    end
    if key ~= "potions" then
        Colour(L, "elementalStone", "Elemental stone on")
        Colour(L, "consecratedStone", "Consecrated stone on")
        Colour(L, "denseStone", "Dense stone on")
        Colour(L, "frostOil", "Frost oil on")
        Colour(L, "enchanted", "Something else on")
    end
    L:EndCard()

    L:Card("Each state")
    local mem = Cfg()
    mem.consState = mem.consState or {}
    L:Add(UI.StateEditor(L.current, { width = UI.CardInnerWidth(L), states = B.STATES,
        get = function() return CB.T(c, "states") end, set = function(t) c.states = t end,
        defaults = function() return B.StateDefaults(c) end,
        fields = { color = true, desat = true, alpha = true, border = true, anim = true }, remember = mem.consState }), 6)
    L:Desc("Fill: the button behind its icon. Opacity: the icon's.")
    L:EndCard()

    L:Card("Expiry glow")
    local st = function() if type(c.style) ~= "table" then c.style = {} end return c.style end
    Check(L, "Glow when a buff is running out", B.GlowOn(key, c), function(v) st().glowEnabled = v and true or false end)
    local gs = UI.Slider(L.current, { width = 240, min = 1, max = 2.5, step = 0.05,
        value = tonumber(B.Style(c).glowScale) or B.GLOW_SCALE, label = "Glow size",
        format = function(v) return format("%d%%", v * 100 + 0.5) end, onChange = function(v) st().glowScale = v end })
    L:Row(gs, 40)
    local gc = UI.ColorPicker(L.current, { label = "Glow colour", alpha = true,
        get = function() return B.Style(c).glowColor end,
        set = function(r, g, b, a) st().glowColor = r and { r = r, g = g, b = b, a = a or 1 } or nil end,
        default = function() return ns.ColorOf(B.COLOR_DEFAULTS.glowColor) end, reset = true })
    L:Row(gc, 22)
    L:EndCard()

    L:Card("Shadow and glow")
    local cg, cs = ns.CustomAccess(Bc, "chrome", nil)
    L:Add(UI.ChromePicker(L.current, { width = UI.CardInnerWidth(L), get = cg, set = cs,
        fields = { shadowSize = true, shadowColor = true, glowSize = true, glowColor = true } }), 6)
    L:EndCard()
end

-- ============================================================
-- TEXT - one text at a time, all of its look
-- ============================================================
local function Tab_text(L)
    local key, c = Which(), Bc()
    L:Card("Button text")
    local items = {}
    for _, e in ipairs(B.ELEMS) do items[#items + 1] = { value = e, text = B.TEXT[e].label } end
    local elem = Cfg().consText
    if not B.TEXT[elem] then elem = "count" end
    Drop(L, "Text", items, function() return elem end, function(v) Cfg().consText = v Rebuild() end)
    L:Desc(B.DESC[elem])
    local function St() if type(c.style) ~= "table" then c.style = {} end return c.style end
    local size = CB.Geo(c)
    local colors = {}
    for _, ck in ipairs(B.TEXT_COLORS[elem] or {}) do
        local k = ck[1]
        colors[#colors + 1] = { label = ck[2],
            get = function() return B.Style(c)[k] end,
            set = function(r, g, b, a) St()[k] = r and { r = r, g = g, b = b, a = a or 1 } or nil end,
            default = function() return ns.ColorOf(B.COLOR_DEFAULTS[k]) end, reset = true }
    end
    local ag, as = ns.CustomAccess(Bc, "anchors", elem)
    local spec = { key = "consbars.text." .. elem,
        fontGet = function() return B.Style(c)[elem .. "Font"] end,
        fontSet = function(s) St()[elem .. "Font"] = s end,
        fontDefaults = B.FontDefaults(elem, size), sample = B.TEXT[elem].sample, minSize = 6, maxSize = 32,
        colors = (#colors > 0) and colors or nil,
        anchorGet = ag, anchorSet = as, anchorDefaults = function() return B.AnchorDefault(elem, nil) end,
        targets = (function()
            local t = {}
            for _, x in ipairs(B.ANCHOR_TARGETS) do if x.value ~= elem then t[#t + 1] = x end end
            return t
        end)(), defaultTargetLabel = "Where it always sits", anchorMin = -40, anchorMax = 40 }
    if elem == "cooldown" or elem == "expiry" or elem == "timer" then
        local fg, fs = ns.CustomAccess(Bc, "formats", elem)
        spec.formatGet, spec.formatSet, spec.formatKinds = fg, fs, { time = true }
        spec.formatDefaults = B.FORMAT_DEFAULTS[elem]
        spec.formatSample = function(f) return ns.FormatTime(47, f, B.FORMAT_DEFAULTS[elem]) .. "  "
            .. ns.FormatTime(1500, f, B.FORMAT_DEFAULTS[elem]) end
    elseif elem == "name" then
        local fg, fs = ns.CustomAccess(Bc, "formats", "name")
        spec.formatGet, spec.formatSet, spec.formatKinds = fg, fs, { name = true }
        spec.formatSample = function(f) return ns.FormatName("Elixir of the Mongoose", f) end
    end
    UI.TextElement(L, spec)
    local back = UI.Button(L.current, "Put back the default text", { width = 200, onClick = function()
        local s = CB.T(c, "style")
        if s then
            for _, e in ipairs(B.ELEMS) do s[e .. "Font"] = nil end
            for k in pairs(B.COLOR_DEFAULTS) do if k ~= "glowColor" then s[k] = nil end end
            if next(s) == nil then c.style = nil end
        end
        c.anchors, c.formats = nil, nil
        Changed("reset") Rebuild()
    end })
    L:Row(back, M.BUTTON_H + 6)
    L:Desc("Until you move its size, a text grows with the buttons.")
    L:EndCard()
end

-- ============================================================
-- ANIMATION
-- ============================================================
local function Tab_anim(L)
    local c = Bc()
    local function St() if type(c.style) ~= "table" then c.style = {} end return c.style end
    L:Card("The bar")
    L:Add(UI.AnimationPicker(L.current, { label = "When it appears", styles = { "none", "fade", "slide", "pop", "bounce" },
        get = function() return B.Style(c).showAnim end, set = function(s) St().showAnim = s end }), 6)
    L:Add(UI.AnimationPicker(L.current, { label = "When it goes", styles = { "none", "fade", "slide", "pop" },
        get = function() return B.Style(c).hideAnim end, set = function(s) St().hideAnim = s end }), 6)
    L:Desc("Zone rules and turning it on or off. In combat it always appears at once.")
    L:EndCard()
    L:Card("The expiry glow")
    L:Add(UI.AnimationPicker(L.current, { label = "Glow", styles = { "none", "pulse", "flash" },
        get = function() return B.Style(c).glowAnim end, set = function(s) St().glowAnim = s end }), 6)
    L:EndCard()
    L:Card("Fade when not hovered")
    local fi, fo = B.FadeTimes(c)
    local a = UI.Slider(L.current, { width = 240, min = 0, max = 2, step = 0.05, value = fi, label = "Fade in",
        format = function(v) return format("%.2f s", v) end, onChange = function(v) St().fadeIn = v end })
    L:Row(a, 40)
    local b = UI.Slider(L.current, { width = 240, min = 0, max = 2, step = 0.05, value = fo, label = "Fade out",
        format = function(v) return format("%.2f s", v) end, onChange = function(v) St().fadeOut = v end })
    L:Row(b, 40)
    L:Desc("The fade itself is on the General tab.")
    L:EndCard()
end

-- ============================================================
-- POSITION
-- ============================================================
local function Tab_pos(L)
    local key, c = Which(), Bc()
    L:Card("Size and place")
    Slider(L, "scale", "Scale", 0.5, 2, 0.05, function(v) return format("%d%%", v * 100 + 0.5) end)
    Check(L, "Lock the bar", c.locked ~= false, function(v) c.locked = v and true or false end,
        "Unlocked, drag the bar itself; right click it to lock or unlock.")
    local mv = UI.Button(L.current, "Move it", { width = 120, onClick = function()
        Live.Build(key)
        if ns.ToggleMover then ns.ToggleMover(CB.MoverKey(key)) end
    end })
    local back = UI.Button(L.current, "Put it back where it started", { width = 220, onClick = function()
        if ZacUIDB.movers then ZacUIDB.movers[CB.MoverKey(key)] = nil end
        Live.Place(key)
    end })
    L:Flow({ mv, back }, 8, 6)
    L:Desc("Also on Appearance > Movers. Out of combat only: the bar holds secure buttons.")
    L:EndCard()
    L:Card("Layer")
    local pg, ps = ns.CustomAccess(Bc, "position", nil)
    L:Add(UI.FrameLayerPicker(L.current, { width = UI.CardInnerWidth(L), get = pg, set = ps,
        fields = { strata = true, level = true, clamp = true } }), 6)
    L:EndCard()
    L:Card("Parts of a button")
    local function Part(pkey, label, dflt)
        local g2, s2 = ns.CustomAccess(Bc, "anchors", pkey)
        UI.FrameElement(L, { key = "consbars.part." .. pkey, label = label, anchorGet = g2, anchorSet = s2,
            anchorDefaults = function() return B.ANCHOR_DEFAULTS[pkey] end, targets = { { value = "button", text = "The button" } },
            defaultTargetLabel = dflt, anchorMin = -40, anchorMax = 40 })
    end
    if key ~= "potions" then Part("badge", "Stone badge", "Bottom left corner") end
    Part("glow", "Expiry glow", "Around the button")
    L:Desc("Each text's place is on the Text tab.")
    L:EndCard()
end

-- ============================================================
-- ADVANCED - Readycheck
-- ============================================================
local lastImport
local function Tab_adv(L)
    local key = Which()
    L:Card("From Readycheck")
    L:Desc("Copies this character's Readycheck consumables, potion and weapon bars here: on or off, the items, "
        .. "their order, where each bar sits, the look and every option.")
    local b = UI.Button(L.current, "Copy my Readycheck bars", { width = 220, onClick = function()
        local ok, why = CB.ImportFromReadycheck()
        lastImport = (ok and "Done: " or "Not copied: ") .. tostring(why)
        if ns.Print then ns.Print("Consumable bars: " .. lastImport) end
        Rebuild()
    end })
    L:Row(b, M.BUTTON_H + 6)
    if lastImport then L:Desc(lastImport) end
    if not CB.RC() then L:Desc("Readycheck is not loaded.") end
    L:EndCard()
    if CB.RC() then
        L:Card("Readycheck's own bars")
        for _, k in ipairs(CB.BARS) do
            local on = CB.ReadycheckBarOn(k)
            L:Pair(CB.LABELS[k], on and "on in Readycheck" or "off in Readycheck", 160)
            if on then
                local kk = k
                local off = UI.Button(L.current, "Turn Readycheck's " .. CB.LABELS[k]:lower() .. " off",
                    { width = 260, onClick = function()
                        if InCombatLockdown() then return end
                        local _, why = CB.TurnOffReadycheck(kk)
                        if ns.Print then ns.Print(why) end
                        Rebuild()
                    end })
                L:Row(off, M.BUTTON_H + 6)
            end
        end
        L:EndCard()
    end
    L:Card("Start again")
    local reset = UI.Button(L.current, "Reset the " .. CB.LABELS[key]:lower(), { width = 220, onClick = function()
        local c = CB.Cfg()
        c[key] = nil
        CB.Cfg()
        if ZacUIDB.movers then ZacUIDB.movers[CB.MoverKey(key)] = nil end
        Live.Place(key)
        Changed("reset") Rebuild()
    end })
    L:Row(reset, M.BUTTON_H + 6)
    L:Desc("Every setting of this bar back to the start (it turns off).")
    L:EndCard()
end

ns.RegisterPage("ConsBars", function(L)
    L:Header("Consumable bars", "Flasks, potions and weapon stones a click away")
    if ns.CustomPick then
        ns.CustomPick.SetHandler(PREVIEW, function(el)
            if type(el) ~= "string" then return end
            local cfg = Cfg()
            cfg.tabs = cfg.tabs or {}
            local t = el:match("^consbars%.text%.(.+)$")
            if t then cfg.consText = t cfg.tabs[PAGE] = "text"
            elseif el:find("^consbars%.part%.") then cfg.tabs[PAGE] = "pos"
            else cfg.tabs[PAGE] = "look" end
            Rebuild()
        end)
    end
    L:Preview({
        key = PREVIEW, title = "Bar", width = 200, height = 80,
        modes = PreviewModes(),
        modesLabel = "Show as",
        build = BuildPreview, update = UpdatePreview, replay = ReplayPreview,
    })
    BarChooser(L)
    RCNote(L)
    L:Tabs({
        { id = "general", label = "General", build = Tab_general },
        { id = "items", label = "Items", build = Tab_items },
        { id = "weapons", label = "Weapons", build = Tab_weapons },
        { id = "look", label = "Look", build = Tab_look },
        { id = "text", label = "Text", build = Tab_text },
        { id = "anim", label = "Animation", build = Tab_anim },
        { id = "pos", label = "Position", build = Tab_pos },
        { id = "adv", label = "Advanced", build = Tab_adv },
    })
end)
