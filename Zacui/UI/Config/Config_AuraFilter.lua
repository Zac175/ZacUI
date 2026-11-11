-- Config_AuraFilter - the one filter panel (Core_AuraFilter's face).
-- Part of ZacUI; load order is set by the TOC (after Config_Base).
--
-- ns.AuraFilter.Panel(L, place) adds the filter's cards to a settings
-- tab: Show (the preset), Your lists (Always show / Never show, added by
-- name or spell id, each with its own remove), Advanced, Sharing. Every
-- place that lists auras calls it with its own place key, so the filter
-- reads and works the same wherever it is.
-- (2026-11-10, Zac's approved mock. Not in this first build: pinning or
-- hiding by right-clicking an icon in the preview, and a filter's own
-- export / import - a profile export carries the filters.)

local ADDON_NAME, ns = ...
local AF = ns.AuraFilter
local UI = ns.UI
if not (AF and UI) then return end

local function Refresh() if ns.RefreshConfig then ns.RefreshConfig() end end

local function Text(list, value)
    for _, e in ipairs(list) do if e.value == value then return e.text, e.desc end end
    return tostring(value)
end

-- one list: its entries as rows with a remove button, then the add box
local function ListCard(L, place, which, title, lead, hint)
    L:Card(title)
    L:Desc(lead)
    local entries = AF.List(place, which)
    if #entries == 0 then
        L:Desc("Nothing yet.")
    else
        local F = UI.F
        for _, e in ipairs(entries) do
            local row = CreateFrame("Frame", nil, L.current)
            row:SetSize(300, 20)
            local x = UI.Button(row, "Remove", { width = 64, height = 18, size = F.SMALL,
                tooltip = "Take it off this list.",
                onClick = function() AF.Remove(place, which, e.key) Refresh() end })
            x:SetPoint("LEFT", row, "LEFT", 0, 0)
            local shown = tostring(e.label)
            if e.key:sub(1, 1) == "#" then shown = shown .. "  |cff888888(spell " .. e.key:sub(2) .. ")|r" end
            local fs = UI.Font(row, F.LABEL, { text = shown, cat = "text", key = "normal" })
            fs:SetPoint("LEFT", x, "RIGHT", 8, 0)
            L:Row(row, 22)
        end
    end
    local box
    local function Add()
        local t = box and box.editBox and box.editBox:GetText() or ""
        if AF.Add(place, which, t) then Refresh() end
    end
    local host = CreateFrame("Frame", nil, L.current)
    host:SetSize(300, (UI.M.EDIT_H or 20) + 2)
    box = UI.EditBox(host, { width = 220, hint = hint or "Spell name or ID", onEnter = Add })
    box:SetPoint("LEFT", host, "LEFT", 0, 0)
    local add = UI.Button(host, "Add", { width = 60, height = UI.M.EDIT_H or 20, onClick = Add })
    add:SetPoint("LEFT", box, "RIGHT", 6, 0)
    L:Row(host, (UI.M.EDIT_H or 20) + 8)
    L:EndCard()
end

-- opts.title: the first card's title (default "What shows")
function AF.Panel(L, place, opts)
    opts = opts or {}
    local def = AF.Def(place)
    if not def then return end
    local c = AF.Get(place)
    local adv = c.adv
    local function Changed() AF.Changed(place) end

    -- SHOW
    L:Card(opts.title or "What shows")
    -- the five choices as one row of buttons, the one in force lit
    do
        -- (each as wide as its own label at the font in use; a row that
        -- runs out of card carries on underneath)
        local row = CreateFrame("Frame", nil, L.current)
        local h = (UI.M.BUTTON_H or 22)
        local room = (L.Room and L:Room()) or 480
        local x, y, wide = 0, 0, 0
        for _, p in ipairs(AF.PRESETS) do
            local b = UI.Button(row, p.text, { width = 64, height = h, tooltip = p.desc,
                onClick = function() c.preset = p.value Changed() Refresh() end })
            local fs = b._zText
            local tw = fs and fs.GetStringWidth and fs:GetStringWidth() or (#p.text * 7)
            local w = math.max(64, math.ceil(tw) + 22)
            b:SetWidth(w)
            if x > 0 and x + w > room then x, y = 0, y + h + 4 end
            b:SetPoint("TOPLEFT", row, "TOPLEFT", x, -y)
            b:SetActive(c.preset == p.value)
            x = x + w + 4
            if x > wide then wide = x end
        end
        row:SetSize(wide, y + h)
        L:Row(row, y + h + 8)
    end
    local _, why = Text(AF.PRESETS, c.preset)
    if why then L:Desc(why) end
    if AF.HidesNames() then
        L:Desc("On this game version the game hides the names of auras in a fight. One it hides cannot be told "
            .. "apart, so it shows under every choice but Nothing, and your two lists only act out of combat.")
    end
    L:EndCard()

    -- SEEN LATELY: what this place has come across since you logged in,
    -- one click onto either list
    do
        local F = UI.F
        local list = AF.Seen(place)
        L:Card("Seen lately")
        if #list == 0 then
            L:Desc("Nothing yet. What this place comes across in game is listed here, "
                .. "to put on either list with one click.")
        else
            L:Desc("What this place has come across since you logged in.")
            local SHOWN = 10
            for i = 1, math.min(SHOWN, #list) do
                local e = list[i]
                local row = CreateFrame("Frame", nil, L.current)
                row:SetSize(300, 20)
                local al = UI.Button(row, "Always", { width = 58, height = 18, size = F.SMALL,
                    tooltip = "Always show " .. e.name .. " here.",
                    onClick = function() if AF.Add(place, "always", e.name) then Refresh() end end })
                al:SetPoint("LEFT", row, "LEFT", 0, 0)
                local nv = UI.Button(row, "Never", { width = 52, height = 18, size = F.SMALL,
                    tooltip = "Never show " .. e.name .. " here.",
                    onClick = function() if AF.Add(place, "never", e.name) then Refresh() end end })
                nv:SetPoint("LEFT", al, "RIGHT", 4, 0)
                local fs = UI.Font(row, F.LABEL, { text = e.name, cat = "text", key = "normal" })
                fs:SetPoint("LEFT", nv, "RIGHT", 8, 0)
                L:Row(row, 22)
            end
            if #list > SHOWN then L:Desc((#list - SHOWN) .. " more: add them by name below.") end
        end
        L:EndCard()
    end

    -- YOUR LISTS
    ListCard(L, place, "always", "Always show",
        "These show whatever \"Show\" says, in front of the rest.")
    ListCard(L, place, "never", "Never show",
        "These never show. This list wins over everything else.")

    -- ADVANCED (closed until asked for; not saved)
    local openKey = "adv:" .. tostring(place)
    if not AF._open then AF._open = {} end
    if not AF._open[openKey] then
        L:Card("Advanced")
        local n = 0
        for k, v in pairs(adv) do if AF.ADV_DEF[k] ~= nil and k ~= "max" and v ~= AF.ADV_DEF[k] then n = n + 1 end end
        local open = UI.Button(L.current, "Show the advanced settings", { width = 200,
            tooltip = "Duration, stacks, combat and boss limits, sorting, how many icons.",
            onClick = function() AF._open[openKey] = true Refresh() end })
        L:Row(open, (UI.M.BUTTON_H or 22) + 6)
        L:Desc("Duration, stacks, sorting, how many icons." .. (n > 0 and ("  " .. n .. (n == 1 and " is" or " are") .. " changed from the default.") or ""))
        L:EndCard()
    else
    L:Card("Advanced")
    local close = UI.Button(L.current, "Hide the advanced settings", { width = 200,
        onClick = function() AF._open[openKey] = nil Refresh() end })
    L:Row(close, (UI.M.BUTTON_H or 22) + 6)
    local function Check(label, key, tip)
        local cb = UI.Checkbox(L.current, label, adv[key] and true or false, function(v)
            adv[key] = v and true or false
            Changed()
        end)
        if tip then UI.Tooltip(cb, label, tip) end
        L:Row(cb, 17)
    end
    local function Slide(label, key, lo, hi, step, fmt)
        local s = UI.Slider(L.current, { width = 220, min = lo, max = hi, step = step or 1,
            value = tonumber(adv[key]) or lo, label = label, format = fmt,
            onChange = function(v) adv[key] = v Changed() end })
        L:Row(s, 40)
    end
    local function Secs(v)
        if v <= 0 then return "Any" end
        if v >= 60 then return string.format("%d min %02d s", math.floor(v / 60), v % 60) end
        return v .. " s"
    end
    Check("Only mine", "onlyMine", "Leave out other players' copies, whatever \"Show\" lets through.")
    Slide("Shortest duration to show", "minDur", 0, 60, 1, Secs)
    Slide("Longest duration to show", "maxDur", 0, 600, 5, Secs)
    L:Desc("A longest duration hides long ones and those that never run out (Fortitude, a paladin's aura).")
    if not def.noCombat then Check("Only in combat", "combatOnly") end
    if not def.noBoss then Check("Only on bosses and elites", "bossOnly") end
    Slide("Show at this many stacks", "minStacks", 0, 10, 1, function(v) return v <= 1 and "Any" or (v .. "+") end)
    if not def.noSort then
        local sd = UI.Field(L.current, "Sort by", function(h)
            return UI.Dropdown(h, { width = 180,
                items = function() return AF.SORTS end,
                selected = function() return (Text(AF.SORTS, adv.sort)) end,
                onSelect = function(v) adv.sort = v Changed() end })
        end, { width = 180 })
        L:Add(sd, 6)
    end
    if not def.noMax then Slide("Most icons", "max", 1, 40, 1) end
    if not def.noSort then Check("Always-show ones first", "pinnedFirst") end
    L:EndCard()
    end

    -- SHARING
    L:Card("Sharing")
    local others = {}
    for _, p in ipairs(AF.Places()) do if p.value ~= place then others[#others + 1] = p end end
    if #others > 0 then
        local cp = UI.Field(L.current, "Copy this filter to", function(h)
            return UI.Dropdown(h, { width = 200,
                items = function() return others end,
                selected = function() return "Pick a place..." end,
                onSelect = function(v)
                    if AF.Copy(place, v) and ns.Print then
                        ns.Print("filter copied to " .. (Text(others, v)) .. ".")
                    end
                end })
        end, { width = 200 })
        L:Add(cp, 6)
        L:Desc("One filter per place. Copying puts this one - its lists and all - on the place you pick.")
    end
    local reset = UI.Button(L.current, "Reset this filter", { width = 150,
        tooltip = "Back to how a new install has it: the preset, empty lists, the advanced settings.",
        onClick = function() AF.Reset(place) Refresh() end })
    L:Row(reset, (UI.M.BUTTON_H or 22) + 6)
    L:EndCard()
end


-- SEVERAL PLACES ON ONE TAB: a "Filtering" picker, then the picked place's
-- cards (the mock's top row). `pick` is a table the page keeps between
-- builds ({ place = ... }); the first place is shown until one is picked.
function AF.PanelFor(L, placeList, pick)
    local items = {}
    for _, p in ipairs(placeList) do
        local d = AF.Def(p)
        if d then items[#items + 1] = { value = p, text = d.label or p } end
    end
    if #items == 0 then return end
    local cur = pick.place
    local okCur = false
    for _, it in ipairs(items) do if it.value == cur then okCur = true end end
    if not okCur then cur = items[1].value pick.place = cur end
    L:Card("Filter")
    local dd = UI.Field(L.current, "Filtering", function(h)
        return UI.Dropdown(h, { width = 240,
            items = function() return items end,
            selected = function() return (Text(items, cur)) end,
            onSelect = function(v) pick.place = v Refresh() end })
    end, { width = 240 })
    L:Add(dd, 6)
    L:Desc("One filter for each list of buffs or debuffs, all with the same settings. Pick which one to set up.")
    L:EndCard()
    AF.Panel(L, cur)
end
