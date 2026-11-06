-- Config_PagesFlavor - General > Game versions: what ZacUI runs on
-- Classic Era, TBC and Forever (the feature table in Core_Flavor, as a
-- grid: on / off / changed, the reason on hover, this client marked),
-- and "Test as", which runs ZacUI as another game on this client after a
-- /reload, so Zac can play on Era and see ZacUI behave as it would on
-- Forever or TBC. /zacui flavor prints the same.
-- Part of ZacUI; load order is set by the TOC.
--
-- Test as writes ZacUIDB.dev.flavor (account-wide, outside every profile
-- and every string). Only which features ZacUI switches off changes; the
-- game's own API stays what it is.

local ADDON_NAME, ns = ...

local UI = ns.UI
local RegisterPage = ns.RegisterPage

local CHOICES = {
    { text = "Auto (this client)", value = "auto" },
    { text = "Classic Era", value = "era" },
    { text = "TBC", value = "tbc" },
    { text = "Forever", value = "forever" },
}
local function ChoiceText(v)
    for _, c in ipairs(CHOICES) do if c.value == v then return c.text end end
    return CHOICES[1].text
end

-- the grid's words and colours, per state
local STATE = {
    on      = { text = "on",      key = "green" },
    off     = { text = "off",     key = "red" },
    changed = { text = "changed", key = "orange" },
}

-- part folder -> what the grid calls it
local PART_LABEL = {
    Zacui = "ZacUI", Zacui_Bars = "Action bars", Zacui_UnitFrames = "Unit frames",
    Zacui_Nameplates = "Nameplates", Zacui_RaidMods = "Raid mods", Zacui_RaidTools = "Raid tools",
    Zacui_Auras = "Aura engine", Zacui_SBT = "Scrolling text", Zacui_Meter = "Damage meter",
    Zacui_Clicks = "Click casting", Zacui_Blessings = "Blessings", Zacui_BuffReminders = "Buff reminders",
    Zacui_Consumables = "Consumable bars", Zacui_HUD = "Class HUDs", Zacui_Bags = "Bags",
    Zacui_Maps = "Maps", Zacui_WorldMap = "World map", Zacui_QoL = "Quality of life",
    Zacui_Windows = "Windows",
}

-- shown for this session only: everything, or just the rows that differ
local onlyDiffers = false

local function Differs(f)
    for _, fl in ipairs(ns.FLAVORS) do
        if ns.FeatureState(f.id, fl) ~= "on" then return true end
    end
    return false
end

-- the preview: the note that sits on screen while testing, drawn by its
-- own constructor, saying the game the picker is set to
local function PreviewFlavor()
    local p = ns.PendingFlavor()
    if p == ns.RealFlavor() then
        -- Auto: show what it says on the other game this client is not
        p = (p == "forever") and "tbc" or "forever"
    end
    return p
end

local CELL_W, CELL_GAP = 80, 4

local function ColumnHead(parent, flavor)
    local real, cur = ns.RealFlavor(), ns.Flavor()
    local label = ns.FlavorName(flavor)
    local key = "gray"
    if flavor == cur and ns.FlavorSimulated() then
        label, key = label .. "\n(testing)", "orange"
    elseif flavor == real then
        label, key = label .. "\n(this client)", "gold"
    end
    local fs = UI.Font(parent, UI.F.SMALL, { cat = "text", key = key, justify = "CENTER" })
    fs:SetWidth(CELL_W)
    fs:SetText(label)
    return fs
end

local function Cell(parent, f, flavor)
    local st, why = ns.FeatureState(f.id, flavor)
    local look = STATE[st] or STATE.on
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(CELL_W, 16)
    local fs = UI.Font(b, UI.F.SMALL, { cat = "text", key = look.key, justify = "CENTER" })
    fs:SetPoint("CENTER", 0, 0)
    fs:SetText(look.text)
    b._zText, b._zState = fs, st
    if flavor == ns.Flavor() then
        UI.Fill(b, "ui", "accent", 0.10)
        b._zPaint = function(self) UI.PaintBox(self) fs:_zPaint() end
        b:_zPaint()
    end
    local body
    if st == "off" then
        body = "Off: " .. why .. "."
    elseif st == "changed" then
        body = "Runs, changed: " .. why .. "."
    else
        body = why and ("Runs: " .. why) or "Runs as it does on Classic Era."
    end
    UI.Tooltip(b, f.name .. " - " .. ns.FlavorName(flavor), body)
    return b
end

RegisterPage("Flavors", function(L)
    L:Header("Game versions",
        "What ZacUI runs on Classic Era, TBC and Forever, and a way to test another one on this client.")

    -- the note, as it reads on screen while testing
    L:Preview({
        key = "flavor.note",
        title = "Testing note",
        width = 220, height = 34,
        build = function(canvas, P)
            P.store.note = ns.BuildFlavorNote(canvas, PreviewFlavor())
            P.store.note:SetPoint("CENTER", canvas, "CENTER", 0, 0)
            P.store.note:EnableMouse(false)
        end,
        update = function(canvas, P)
            if P.store.note then
                P.store.note:SetFlavor(PreviewFlavor())
                P.store.note:_zPaint()
            end
        end,
    })

    -- TEST AS
    L:Card("Test as")
    local cur, pending, real = ns.Flavor(), ns.PendingFlavor(), ns.RealFlavor()
    local pick = UI.Field(L.current, "Run ZacUI as", function(h)
        return UI.Dropdown(h, { width = 200,
            items = function() return CHOICES end,
            selectedValue = function() return ns.FlavorOverride() end,
            selected = function() return ChoiceText(ns.FlavorOverride()) end,
            onSelect = function(v)
                ns.SetFlavorOverride(v)
                if ns.RefreshConfig then ns.RefreshConfig() end
            end })
    end, { width = 200 })
    UI.Tooltip(pick.control or pick, "Run ZacUI as",
        "ZacUI switches features off exactly as it would on that game, after a /reload. "
        .. "The game itself does not change: this client keeps every API it has. "
        .. "While it is on, a note on screen says so. The same as /zacui flavor era, tbc, forever or auto.")
    L:Add(pick, 6)
    pick._zFlavorPicker = true

    local now = string.format("Running as %s.", ns.FlavorName(cur))
    if ns.FlavorSimulated() then
        now = string.format("Running as %s (simulated - this client is %s).", ns.FlavorName(cur), ns.FlavorName(real))
    end
    if pending ~= cur then
        now = now .. " " .. string.format("After /reload: %s.", ns.FlavorName(pending))
    end
    local status = UI.Font(L.current, UI.F.DESC, { cat = "text", key = (pending ~= cur) and "orange" or "gray" })
    status:SetText(now)
    L:Row(status, 18)
    local reload = UI.Button(L.current, "Reload now", { width = 110,
        tooltip = "Reloads the interface so the choice takes effect.",
        onClick = function() ReloadUI() end })
    if pending == cur and reload.SetDisabled then reload:SetDisabled(true) end
    L:Row(reload, (UI.M.BUTTON_H or 20) + 6)
    L:EndCard()

    -- THE GRID
    L:Card("What runs where")
    local only = UI.Checkbox(L.current, "Only what differs between the games", onlyDiffers, function(v)
        onlyDiffers = v and true or false
        if ns.RefreshConfig then ns.RefreshConfig() end
    end, { tooltip = "Hide the rows that run the same everywhere." })
    L:Row(only, 22)

    local room = L:Room()
    local nameW = math.max(120, room - 3 * (CELL_W + CELL_GAP))

    -- the column heads: the client this is, and the one being tested
    local head = UI.Holder(L.current)
    local x, headH = nameW, 14
    for _, fl in ipairs(ns.FLAVORS) do
        local fs = ColumnHead(head, fl)
        fs:SetPoint("TOPLEFT", head, "TOPLEFT", x + CELL_GAP, 0)
        headH = math.max(headH, math.ceil(fs:GetStringHeight() or 14))
        x = x + CELL_W + CELL_GAP
    end
    local hName = UI.Font(head, UI.F.SMALL, { cat = "text", key = "gray", text = "Part / feature" })
    hName:SetPoint("TOPLEFT", head, "TOPLEFT", 0, 0)
    head:SetSize(room, headH)
    L:Row(head, headH + 4)

    local lastPart
    for _, f in ipairs(ns.FEATURE_FLAVORS) do
        if not onlyDiffers or Differs(f) then
            if f.part ~= lastPart then
                lastPart = f.part
                local ph = UI.Font(L.current, UI.F.LABEL, { cat = "text", key = "gold",
                    text = PART_LABEL[f.part] or f.part })
                L:Row(ph, 18)
            end
            local row = UI.Holder(L.current)
            local name = UI.Font(row, UI.F.SMALL, { cat = "text", key = "normal", width = nameW - 10, justify = "LEFT" })
            name:SetText(f.name)
            name:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -1)
            local h = math.max(16, math.ceil(name:GetStringHeight() or 12) + 2)
            row:SetSize(room, h)
            local cx = nameW
            for _, fl in ipairs(ns.FLAVORS) do
                local c = Cell(row, f, fl)
                c:SetPoint("TOPLEFT", row, "TOPLEFT", cx + CELL_GAP, 0)
                cx = cx + CELL_W + CELL_GAP
            end
            L:Row(row, h + 3)
        end
    end
    L:Gap(4)
    L:Desc("Hover a cell for the reason. A part that is off on a game registers nothing there, and its page says why.")
    L:EndCard()
end)
