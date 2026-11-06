-- CC_Config - the Click casting page (Combat > Click casting): the
-- switches, this character's bindings with an editor, copying another
-- character's set, and the Clique hand-over.
-- Part of ZacUI; load order is set by the TOC.

local ADDON_NAME = ...
local ns = _G.ZacUI
if not ns then return end

local CC = ns.ClickCast
if not CC then return end

local Print = ns.Print
local UI = ns.UI
local M, F = UI.M, UI.F

local function Refresh()
    if ns.RefreshConfig then ns.RefreshConfig() end
end

-- ============================================================
-- THE SPELLBOOK - spell names, and the ranks known of each
-- ============================================================
local function Spellbook()
    local names, ranks, icons = {}, {}, {}
    local BOOK = BOOKTYPE_SPELL or "spell"
    if not GetNumSpellTabs then return names, ranks, icons end
    for tab = 1, GetNumSpellTabs() do
        local _, _, offset, count = GetSpellTabInfo(tab)
        for slot = (offset or 0) + 1, (offset or 0) + (count or 0) do
            local name, sub = GetSpellBookItemName(slot, BOOK)
            local passive = IsPassiveSpell and IsPassiveSpell(slot, BOOK)
            if name and not passive then
                if not ranks[name] then
                    ranks[name] = {}
                    names[#names + 1] = name
                    icons[name] = GetSpellBookItemTexture and GetSpellBookItemTexture(slot, BOOK) or nil
                end
                if sub and sub ~= "" then table.insert(ranks[name], sub) end
            end
        end
    end
    table.sort(names)
    return names, ranks, icons
end

local function SpellIcon(name)
    if not name or name == "" then return nil end
    local tex = GetSpellTexture and GetSpellTexture(name)
    return tex
end

local function WithIcon(tex, label)
    if not tex then return label end
    return "|T" .. tostring(tex) .. ":14:14:0:0:64:64:5:59:5:59|t " .. label
end

-- ============================================================
-- KEY CAPTURE - a button that takes the next click, wheel or key
-- ============================================================
local MOUSE_NAMES = { LeftButton = "BUTTON1", RightButton = "BUTTON2", MiddleButton = "BUTTON3",
    Button4 = "BUTTON4", Button5 = "BUTTON5" }
local MODIFIER_KEYS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
    SHIFT = true, CTRL = true, ALT = true, UNKNOWN = true }

local function Mods()
    return (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "") .. (IsShiftKeyDown() and "SHIFT-" or "")
end

local function KeyCapture(parent, current, onSet)
    local b = UI.Button(parent, current and current ~= "" and CC.KeyLabel(current) or "Click here, then press the key",
        { width = 240, tooltip = "Click this, then do the click, wheel or key press you want - with Shift, Ctrl or "
            .. "Alt held if you want them. Escape cancels." })
    b:RegisterForClicks("AnyUp")
    local capturing = false
    local function Stop()
        capturing = false
        b:EnableKeyboard(false)
        b:EnableMouseWheel(false)
        b:SetScript("OnKeyDown", nil)
        b:SetScript("OnMouseWheel", nil)
    end
    local function Take(key)
        Stop()
        onSet(key)
    end
    b:SetScript("OnClick", function(self, button)
        if not capturing then
            capturing = true
            self:SetLabel("Now press it...")
            self:EnableKeyboard(true)
            if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(false) end
            self:EnableMouseWheel(true)
            self:SetScript("OnKeyDown", function(_, key)
                if key == "ESCAPE" then Stop(); Refresh() return end
                if MODIFIER_KEYS[key] then return end
                Take(Mods() .. key)
            end)
            self:SetScript("OnMouseWheel", function(_, delta)
                Take(Mods() .. (delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN"))
            end)
            return
        end
        local mb = MOUSE_NAMES[button]
        if mb then Take(Mods() .. mb) end
    end)
    b:HookScript("OnHide", Stop)
    return b
end

-- ============================================================
-- THE PAGE
-- ============================================================
local function Draft()
    local cfg = ns.ConfigState and ns.ConfigState() or {}
    return cfg
end

local function StatusCard(L)
    L:Card("Click casting")
    if CC.standDown then
        L:Notice("warn", "Clique is turned on, so ZacUI's click casting is standing down. Your Clique bindings "
            .. "have been brought over; turn Clique off to use them here.")
        local b = UI.Button(L.current, "Turn Clique off + reload", { width = 200, onClick = CC.DisableClique })
        L:Row(b, M.BUTTON_H + 8)
        if rawget(_G, "CliqueDB3") then
            local r = UI.Button(L.current, "Bring Clique's bindings over again", { width = 240,
                tooltip = "Replaces every character's ZacUI bindings with what Clique has now.",
                onClick = function()
                    local n = CC.ImportClique(true)
                    Print("click casting: brought " .. n .. " binding set(s) over from Clique.")
                    Refresh()
                end })
            L:Row(r, M.BUTTON_H + 8)
        end
        L:EndCard()
        return false
    end
    local c = CC.Cfg()
    local cb = UI.Checkbox(L.current, "Click casting on", c.enabled, function(v) CC.SetEnabled(v) Refresh() end)
    L:Row(cb, 17)
    L:Desc("Spells, macros, target and menu on any mouse button or key, with Shift, Ctrl or Alt, on ZacUI's "
        .. "unit frames - player, target, party, raid. Keys work while the mouse is over a frame.")
    local bz = UI.Checkbox(L.current, "The game's own unit frames too", c.blizzard,
        function(v) c.blizzard = v and true or false; Print("click casting: takes effect after a reload.") end)
    L:Row(bz, 17)
    L:Desc("For the Blizzard player, target, party and raid frames wherever ZacUI's are switched off "
        .. "(nameless ones - the game's party frames - get clicks, not hover keys).")
    if CC.skipped and #CC.skipped > 0 then
        L:Notice("warn", "A plain left or right click is never bound outside unit frames (it moves the camera); "
            .. #CC.skipped .. " hover binding(s) of that kind only work on frames.")
    end
    L:EndCard()
    return true
end

local function Editor(L, edit, index)
    local d = Draft()
    L:Card(index and "Edit binding" or "New binding")
    local key = KeyCapture(L.current, edit.key, function(k)
        edit.key = k
        Refresh()
    end)
    L:Row(key, M.BUTTON_H + 8)
    local typeDD = UI.Dropdown(L.current, { width = 220,
        items = function()
            local t = {}
            for _, ty in ipairs(CC.TYPES) do t[#t + 1] = { text = CC.TYPE_LABEL[ty], value = ty } end
            return t
        end,
        selected = function() return CC.TYPE_LABEL[edit.type or "spell"] end,
        selectedValue = function() return edit.type or "spell" end,
        onSelect = function(v) edit.type = v Refresh() end,
    })
    L:Row(typeDD, M.DROPDOWN_H + 8)
    local ty = edit.type or "spell"
    if ty == "spell" then
        local names, ranks, icons = Spellbook()
        local sp = UI.Dropdown(L.current, { width = 260,
            items = function()
                local t = {}
                for _, n in ipairs(names) do t[#t + 1] = { text = WithIcon(icons[n], n), value = n } end
                return t
            end,
            selected = function() return edit.spell and edit.spell ~= "" and WithIcon(SpellIcon(edit.spell), edit.spell) or "Pick a spell..." end,
            selectedValue = function() return edit.spell end,
            onSelect = function(v) edit.spell = v; edit.rank = nil; Refresh() end,
        })
        L:Row(sp, M.DROPDOWN_H + 8)
        local typed = UI.EditBox(L.current, { width = 260, text = edit.spell or "", hint = "...or type the spell's name",
            onChange = function(t) edit.spell = (t or ""):gsub("^%s+", ""):gsub("%s+$", "") end })
        L:Row(typed, 26)
        local rlist = edit.spell and ranks[edit.spell] or nil
        local rd = UI.Dropdown(L.current, { width = 220,
            items = function()
                local t = { { text = "Highest rank", value = "" } }
                for i = #(rlist or {}), 1, -1 do t[#t + 1] = { text = rlist[i], value = rlist[i] } end
                return t
            end,
            selected = function() return (edit.rank and edit.rank ~= "") and edit.rank or "Highest rank" end,
            selectedValue = function() return edit.rank or "" end,
            onSelect = function(v) edit.rank = (v ~= "") and v or nil Refresh() end,
        })
        L:Row(rd, M.DROPDOWN_H + 8)
    elseif ty == "macro" then
        local box = UI.TextBox(L.current, { width = 420, height = 70, text = edit.macrotext or "",
            onChange = function(t) edit.macrotext = t end })
        L:Row(box, 76)
        L:Desc("The macro runs with the clicked unit as \"mouseover\" ([@mouseover]) - write it that way.")
    end
    L:Gap(4)
    edit.sets = edit.sets or { default = true }
    for _, s in ipairs(CC.SETS) do
        local cb = UI.Checkbox(L.current, CC.SET_LABEL[s], edit.sets[s] == true,
            function(v) edit.sets[s] = v and true or nil end)
        L:Row(cb, 19)
    end
    L:Desc("Unit frames: click or key on a frame. Hover anywhere: on whatever unit is under the mouse, frames "
        .. "and the world. Anywhere: on your target, no unit under the mouse needed.")
    local row = UI.Holder(L.current)
    row:SetSize(460, 24)
    local save = UI.Button(row, index and "Save" or "Add", { width = 100, onClick = function()
        if not edit.key or edit.key == "" then Print("click casting: set a key first.") return end
        if (edit.type or "spell") == "spell" and (not edit.spell or edit.spell == "") then
            Print("click casting: pick a spell first.") return
        end
        local b = CC.Copy(edit)
        b.type = b.type or "spell"
        if b.type ~= "spell" then b.spell, b.rank = nil, nil end
        if b.type ~= "macro" then b.macrotext = nil end
        local list = CC.Bindings()
        if index and list[index] then list[index] = b else list[#list + 1] = b end
        d.ccEdit, d.ccEditIndex = nil, nil
        CC.Changed()
        Refresh()
    end })
    save:SetPoint("LEFT", row, "LEFT", 0, 0)
    local cancel = UI.Button(row, "Cancel", { width = 100, onClick = function()
        d.ccEdit, d.ccEditIndex = nil, nil
        Refresh()
    end })
    cancel:SetPoint("LEFT", save, "RIGHT", 6, 0)
    L:Row(row, 30)
    L:EndCard()
end

local function BindingsCard(L)
    local d = Draft()
    local list = CC.Bindings()
    L:Card("Bindings - " .. CC.CharKey())
    if #list == 0 then L:Desc("None yet.") end
    -- sorted for reading: mouse buttons first, then keys
    local order = {}
    for i in ipairs(list) do order[#order + 1] = i end
    table.sort(order, function(a, b)
        local ka, kb = list[a].key or "", list[b].key or ""
        local _, ba = CC.SplitKey(ka)
        local _, bb = CC.SplitKey(kb)
        local ma, mb = CC.MOUSE[ba] and 0 or 1, CC.MOUSE[bb] and 0 or 1
        if ma ~= mb then return ma < mb end
        if ba ~= bb then return ba < bb end
        return ka < kb
    end)
    for _, i in ipairs(order) do
        local b = list[i]
        local rowW = math.min(460, L:Room())
        local row = UI.Holder(L.current)
        row:SetSize(rowW, 22)
        local ed = UI.Button(row, "Edit", { width = 50, onClick = function()
            d.ccEdit = CC.Copy(b); d.ccEditIndex = i; d.ccEditChar = CC.CharKey()
            Refresh()
        end })
        ed:SetPoint("LEFT", row, "LEFT", 0, 0)
        local del = UI.Button(row, "Delete", { width = 60, onClick = function()
            table.remove(list, i)
            -- the rows below move up: an open editor would point at the wrong one
            d.ccEdit, d.ccEditIndex, d.ccEditChar = nil, nil, nil
            CC.Changed()
            Refresh()
        end })
        del:SetPoint("LEFT", ed, "RIGHT", 4, 0)
        local icon = b.type == "spell" and SpellIcon(b.spell) or nil
        -- (the description wraps in what the two buttons leave)
        local textW = rowW - (ed:GetWidth() or 50) - 4 - (del:GetWidth() or 60) - 8
        local fs = UI.Font(row, F.LABEL, { text = "|cffffd100" .. CC.KeyLabel(b.key) .. "|r  "
            .. WithIcon(icon, CC.ActionLabel(b)) .. "  |cff8a90a0" .. CC.SetsLabel(b) .. "|r", width = textW })
        fs:SetPoint("LEFT", del, "RIGHT", 8, 0)
        local th = math.ceil(fs:GetStringHeight() or 12)
        if th > 18 then row:SetHeight(th + 4) end
        L:Row(row, math.max(26, th + 8))
    end
    local add = UI.Button(L.current, "New binding", { width = 140, onClick = function()
        d.ccEdit = { type = "spell", sets = { default = true } }; d.ccEditIndex = nil; d.ccEditChar = CC.CharKey()
        Refresh()
    end })
    L:Row(add, M.BUTTON_H + 8)
    L:EndCard()
    -- the config state is account-wide: a draft from another character is dropped
    if d.ccEdit and d.ccEditChar ~= CC.CharKey() then d.ccEdit, d.ccEditIndex, d.ccEditChar = nil, nil, nil end
    if d.ccEdit then Editor(L, d.ccEdit, d.ccEditIndex) end
end

local function CopyCard(L)
    local c = CC.Cfg()
    local mine = CC.CharKey()
    local others = {}
    for k, p in pairs(c.profiles) do
        if k ~= mine and type(p) == "table" and type(p.bindings) == "table" and #p.bindings > 0 then others[#others + 1] = k end
    end
    if #others == 0 then return end
    table.sort(others)
    L:Card("Copy from another character")
    L:Desc("Replaces this character's bindings with a copy of theirs (this account's characters; Clique's sets "
        .. "came over for every character it knew).")
    local dd = UI.Dropdown(L.current, { width = 260,
        items = function()
            local t = {}
            for _, k in ipairs(others) do t[#t + 1] = { text = k .. " (" .. #c.profiles[k].bindings .. ")", value = k } end
            return t
        end,
        selected = function() return "Copy from..." end,
        selectedValue = function() return nil end,
        onSelect = function(v)
            UI.Confirm({ title = "Click casting", text = "Replace this character's bindings with " .. v .. "'s?",
                acceptText = "Replace", onAccept = function()
                    c.profiles[mine] = { bindings = CC.Copy(c.profiles[v].bindings) }
                    CC.Changed()
                    Refresh()
                end })
        end,
    })
    L:Row(dd, M.DROPDOWN_H + 8)
    L:EndCard()
end

ns.RegisterPage("ClickCast", function(L)
    L:Header("Click casting", "Cast on unit frames with any button or key")
    if not StatusCard(L) then return end
    BindingsCard(L)
    CopyCard(L)
end)
