-- Config_Profiles - the Profiles page: the one place every ZacUI setting
-- is managed as a whole. Which profile this character wears, every
-- profile on the account and who wears it, copying sections between
-- profiles, resetting sections, and the export / import strings.
-- Part of ZacUI; load order is set by the TOC.
--
-- THE MODEL is Readycheck's: a character wears a named profile; its
-- settings are live while the character is logged in and written back
-- at logout, reload and whenever this window closes. Sections (the list
-- in Core_Profiles) are the unit everything here works in, so a string
-- can carry just the nameplates, or a copy can bring over only the bars.

local ADDON_NAME, ns = ...

-- shared state from earlier ZacUI files
local Print = ns.Print
local Profiles = ns.Profiles
local RefreshConfig = ns.RefreshConfig
local RegisterPage = ns.RegisterPage
local UI = ns.UI
local ZUI = ns.ZUI

local M, F = UI.M, UI.F

local function Trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

local function Reload()
    if ns.RequestReload then ns.RequestReload()
    elseif type(ReloadUI) == "function" then ReloadUI()
    elseif C_UI and C_UI.Reload then C_UI.Reload() end
end

-- Loading settings rewrites module states and colours wholesale. Skins
-- that are already applied cannot be un-applied, so this is one of the few
-- places in the addon where a reload is genuinely required rather than
-- merely tidier - and it says so instead of pretending.
--
-- THE RELOAD IS ASKED FOR FIRST, then the load writes (WoW Forever honours
-- a reload only when it is asked for at the start of the click, build
-- 70425; UIF_Dialogs' ns.AskReload). The writes still run inside the same
-- click, so they are what the reload saves.
local function LoadThenReload(what, work)
    Reload()
    local ok, res, err = pcall(work)
    if not ok then Print(what .. " failed: " .. tostring(res)) return end
    if res then Print(what .. " - reloading to apply.") else Print(tostring(err)) end
end

-- Which sections the section-wise actions work on. Remembered in the
-- config state so it survives the rebuild every click causes.
local function Selected()
    ZacUIDB.config = ZacUIDB.config or {}
    local s = ZacUIDB.config
    if not s.profileSections then
        s.profileSections = {}
        for _, sec in ipairs(Profiles.SECTIONS) do s.profileSections[sec.key] = true end
    end
    return s.profileSections
end

local function SelectedList()
    local sel, out = Selected(), {}
    for _, sec in ipairs(Profiles.SECTIONS) do
        if sel[sec.key] then out[#out + 1] = sec.key end
    end
    return out
end

local function SectionLabels(keys)
    local names = {}
    for _, k in ipairs(keys) do
        for _, sec in ipairs(Profiles.SECTIONS) do
            if sec.key == k then names[#names + 1] = sec.label end
        end
    end
    return table.concat(names, ", ")
end

-- ============================================================
-- ANY STRING, ANY BOX - the parts every import box shares
-- ============================================================
-- Core_Profiles' Import.Identify says what a pasted string is and
-- Import.Run imports it. These three put that on screen, the same way
-- on every page that has an import box:
--
--   Import.Watch     a line under the box that names the paste as it
--                    lands ("ZacUI bar loadout - Warrior, 62 slots...")
--   Import.Redirect  for a page's own Import button: if the box holds
--                    something that belongs to another page, offer it
--                    instead of refusing it
--   Import.Offer     the window that does the offering: what it is,
--                    what each choice does, and the buttons
local Import = ns.Import

-- One line for the status text under a box: wording and colour key.
local function StatusOf(info, expected)
    if not info or info.kind == "empty" then return "", "gray" end
    if info.kind == "unknown" then
        -- The aura engine reads older forms that nothing here can tell
        -- by sight; its tab leaves the verdict to the engine.
        if expected == "weakauras" then
            return "Not a string ZacUI knows by sight - Import lets the aura engine try it.", "gray"
        end
        return info.title .. ". " .. tostring(info.problem or ""), "red"
    end
    local text = tostring(info.title or "")
    if info.lines and info.lines[1] then text = text .. "  -  " .. info.lines[1] end
    if not info.ready then
        return text .. ". " .. tostring(info.problem or ""), "red"
    end
    local own = (info.kind == expected) or (expected == "loadout" and info.kind == "myslot")
    if expected and not own then
        text = text .. ". It belongs elsewhere, and can still be imported from here."
    end
    return text, "gold"
end

-- Names whatever is in `box` (a UI.TextBox, or anything with .editBox)
-- on `font`, a moment after the text stops changing - describing a
-- paste decodes it, which is not per-keystroke work.
function Import.Watch(box, font, expected)
    local eb = box and (box.editBox or box)
    if not (eb and eb.HookScript and font) then return end
    local gen = 0
    local function Update()
        local text, key = StatusOf(Import.Identify(eb:GetText() or ""), expected)
        font:SetText(text)
        if font._zPaint then
            font._zPaintCat, font._zPaintKey = "text", key
            font:_zPaint()
        end
    end
    eb:HookScript("OnTextChanged", function()
        gen = gen + 1
        local mine = gen
        C_Timer.After(0.2, function()
            if mine == gen and eb:IsVisible() then Update() end
        end)
    end)
    Update()
end

local offer
local function BuildOffer()
    local f = UI.Window("ZacUIImportOffer", 400, 240, "Import")
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(110)
    f.what = UI.Font(f, F.LABEL, { cat = "text", key = "gold", width = 368 })
    f.what:SetPoint("TOPLEFT", 16, -(M.TITLEBAR + 12))
    f.detail = UI.Font(f, F.SMALL, { cat = "text", key = "gray", width = 368 })
    f.effect = UI.Font(f, F.SMALL, { width = 368 })
    f.name = UI.EditBox(f, { width = 240, height = 20, hint = "Name", clear = false })
    f.buttons = {}
    for i = 1, 2 do
        f.buttons[i] = UI.Button(f, "", { width = 182, height = 22 })
    end
    f.cancel = UI.Button(f, CANCEL or "Cancel", { width = 100, height = 22,
        onClick = function() UI.CloseWindow(f) end })
    f.cancel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 12)
    return f
end

-- Offers a recognised string: one button per thing that can be done
-- with it. opts.info: Identify's result for this text. opts.note: a
-- first line saying why the offer appeared. opts.onDone(result): after
-- an import that does not reload.
function Import.Offer(text, opts)
    opts = opts or {}
    local info = opts.info or Import.Identify(text)
    if info.kind == "empty" then return false end
    offer = offer or BuildOffer()
    local f = offer

    f.what:SetText(tostring(info.title or ""))
    local lines = {}
    if opts.note then lines[#lines + 1] = opts.note end
    for _, l in ipairs(info.lines or {}) do lines[#lines + 1] = l end
    f.detail:SetText(table.concat(lines, "\n"))

    local actions = info.ready and info.actions or {}
    local effects = {}
    if not info.ready then
        effects[1] = tostring(info.problem or "It cannot be imported.")
        f.effect._zPaintKey = "red"
    else
        for _, a in ipairs(actions) do
            effects[#effects + 1] = a.label .. ": " .. tostring(a.effect or "")
        end
        f.effect._zPaintKey = "normal"
    end
    f.effect:_zPaint()
    f.effect:SetText(table.concat(effects, "\n"))

    local wantsName = false
    for _, a in ipairs(actions) do if a.needsName then wantsName = true end end
    f.name:SetText(info.defaultName or "")
    f.name:SetShown(wantsName)
    f._busy = nil

    -- stacked top to bottom from measured heights
    local y = -(M.TITLEBAR + 12) - math.max(14, f.what:GetStringHeight()) - 6
    f.detail:ClearAllPoints()
    f.detail:SetPoint("TOPLEFT", 16, y)
    if f.detail:GetText() and f.detail:GetText() ~= "" then
        y = y - math.max(12, f.detail:GetStringHeight()) - 8
    end
    f.effect:ClearAllPoints()
    f.effect:SetPoint("TOPLEFT", 16, y)
    y = y - math.max(12, f.effect:GetStringHeight()) - 10
    f.name:ClearAllPoints()
    if wantsName then
        f.name:SetPoint("TOPLEFT", 16, y)
        y = y - 28
    end

    for i, b in ipairs(f.buttons) do
        local a = actions[i]
        b:SetShown(a ~= nil)
        b:ClearAllPoints()
        if a then
            b:SetLabel(a.label)
            b:SetPoint("TOPLEFT", 16 + (i - 1) * 186, y)
            b:SetScript("OnClick", function()
                -- The window fades out for a moment after a click and its
                -- buttons are still there to be clicked: once only.
                if f._busy then return end
                f._busy = true
                -- an action that ends in a reload asks for it FIRST, before
                -- anything is written (LoadThenReload's note)
                if a.reload then Reload() end
                local ok, msg, res = Import.Run(info.text, a.id, { info = info, name = f.name:GetText() })
                if not ok then
                    f._busy = nil
                    Print("Import failed: " .. tostring(msg or "unknown error"))
                    return
                end
                -- THE WORK FIRST, THE ANIMATION SECOND - see UI.Confirm.
                if msg then Print(msg) end
                UI.CloseWindow(f)
                if res and res.reload then
                    Print("Reloading to apply.")
                    if not a.reload then Reload() end
                    -- still here a moment later: the reload did not happen
                    C_Timer.After(2, function() Print("The import is in, but the UI did not reload - type /reload to finish.") end)
                    return
                end
                if opts.onDone then opts.onDone(res) end
                if ns.ConfigIsOpen and ns.ConfigIsOpen() then RefreshConfig() end
            end)
        end
    end
    if #actions > 0 then y = y - 30 end
    f:SetHeight(-y + 46)
    UI.OpenWindow(f)
    f:Raise()
    return true
end

-- For a page's own Import button. `expected` is the kind that page
-- imports itself. Returns true when the box held a recognised string
-- of some other kind and this has taken it from here (offered it, or
-- said why it cannot be imported); false when the page should carry on
-- with its own importer - its own kind, nothing, or something nobody
-- recognises, which the page reports in its own words.
function Import.Redirect(text, expected, opts)
    local info = Import.Identify(text)
    local kind = info.kind
    if kind == "empty" or kind == "unknown" then return false end
    if kind == expected or (expected == "loadout" and kind == "myslot") then return false end
    opts = opts or {}
    opts.info = info
    opts.note = opts.note or "This is not what this page imports, but it does not have to be taken elsewhere."
    Import.Offer(text, opts)
    return true
end

-- The status line under an import box on a Layout page: one line (it
-- says what the pasted string is, short), cut short with a tooltip if it
-- ever runs longer, so an empty box leaves no hole under it.
function Import.StatusRow(L, box, expected)
    local host = UI.Holder(L.current)
    local w = math.min(400, L:Room())
    host:SetSize(w, 14)
    host:EnableMouse(true)
    local font = UI.Font(host, F.SMALL, { cat = "text", key = "gray", width = w, justify = "LEFT" })
    font:SetPoint("TOPLEFT", 0, 0)
    font:SetWordWrap(false)
    UI.TruncTip(font, host)
    L:Row(host, 16)
    Import.Watch(box, font, expected)
    return font
end

-- (wraps onto a second line rather than running past the card)
local function ButtonRow(L, defs)
    local list = {}
    for _, d in ipairs(defs) do
        local b = UI.Button(L.current, d[1], { width = d.width or 110, onClick = d[2] })
        if d.active then b:SetActive(true) end
        list[#list + 1] = b
    end
    L:Flow(list, 6, 6)
end

local function Dropdown(L, label, items, get, set, width)
    local lbl = UI.Font(L.current, F.LABEL, { text = label })
    lbl:SetPoint("TOPLEFT", L.current, "TOPLEFT", M.CONTROL_X, L.current._y)
    L.current._y = L.current._y - 16
    local function Label(v)
        for _, it in ipairs(items) do if it.value == v then return it.text end end
        return tostring(v)
    end
    local dd = UI.Dropdown(L.current, { width = width or 240,
        items = function() return items end,
        selected = function() return Label(get()) end,
        selectedValue = function() return get() end,
        onSelect = function(v) set(v) end })
    L:Row(dd, M.DROPDOWN_H + 6)
    return dd
end

RegisterPage("Profiles", function(L)
    L:Header("Profiles",
        "Every setting lives in a named profile each character wears. Switch, "
        .. "copy parts between profiles, reset parts, or move one to another "
        .. "account as text.")

    Profiles.WriteBack()
    local names = Profiles.List()
    local current = Profiles.Current() or Profiles.DEFAULT_NAME
    local items = {}
    for _, n in ipairs(names) do items[#items + 1] = { text = n, value = n } end

    -- ---------------------------------------------------------
    L:Card("This character")
    Dropdown(L, "Wears", items, function() return current end, function(v)
        if v == current then return end
        UI.Confirm({
            title = "Switch profile",
            text = "Put '" .. v .. "' on " .. UnitName("player") .. "? What this character has now is "
                .. "written back into '" .. current .. "' first, nothing is lost. A reload follows.",
            acceptText = "Switch",
            onAccept = function()
                LoadThenReload("Switched to '" .. v .. "'", function() return Profiles.Use(v) end)
            end,
        })
    end)
    local others = Profiles.UsedBy(current)
    local shown = {}
    for _, ck in ipairs(others) do if ck ~= Profiles.CharKey() then shown[#shown + 1] = (ck:match("^(.-) %- ") or ck) end end
    L:Desc("'" .. current .. "' is live on this character now and is saved back on logout, reload and "
        .. "when this window closes."
        .. (#shown > 0 and (" Also worn by " .. table.concat(shown, ", ") .. ".") or " No other character wears it."))
    Dropdown(L, "Profile for new characters", items, function() return Profiles.DefaultName() end,
        function(v) ZacUIDB.defaultProfile = v RefreshConfig() end)
    L:Desc("A character logging in for the first time with ZacUI wears this one.")
    L:EndCard()

    -- ---------------------------------------------------------
    L:Card("Profiles on this account")
    -- name | who wears it | Export X, the buttons held to the card's right
    -- edge and the two texts sharing what is left (cut short with the whole
    -- text on hover when a name is long)
    local lineW = math.min(460, L:Room())
    local textW = lineW - 60 - 4 - 20 - 8
    local nameW = math.floor(math.min(200, textW * 0.55))
    local subW = textW - nameW - 4
    for _, name in ipairs(names) do
        local line = UI.Holder(L.current)
        line:SetSize(lineW, M.BUTTON_H)
        line:EnableMouse(true)
        local label = UI.Font(line, F.LABEL, { text = name .. (name == current and "  (this character)" or "") })
        label:SetPoint("LEFT")
        label:SetWidth(nameW)
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
        UI.TruncTip(label, line)
        local who = {}
        for _, ck in ipairs(Profiles.UsedBy(name)) do who[#who + 1] = ck:match("^(.-) %- ") or ck end
        local sub = UI.Font(line, F.SMALL, { cat = "text", key = "gray",
            text = #who > 0 and table.concat(who, ", ") or "not worn" })
        sub:SetPoint("LEFT", line, "LEFT", nameW + 4, 0)
        sub:SetWidth(subW)
        sub:SetJustifyH("LEFT")
        sub:SetWordWrap(false)
        UI.TruncTip(sub, line)
        local export = UI.Button(line, "Export", { width = 60, height = 18, size = F.SMALL, onClick = function()
            local str, err = Profiles.Export(name, SelectedList())
            if str and L.exportBox then L.exportBox:SetText(str) L.exportBox:Focus()
                Print("Exported " .. SectionLabels(SelectedList()) .. " from '" .. name .. "'.")
            elseif not str then Print("Could not export: " .. tostring(err)) end
        end })
        export:SetPoint("RIGHT", line, "RIGHT", -28, 0)
        local del = UI.Button(line, "X", { width = 20, height = 18, size = F.SMALL, onClick = function()
            UI.Confirm({ title = "Delete profile", destructive = true, acceptText = "Delete",
                text = "Delete '" .. name .. "'? Characters wearing it fall back to the profile for new characters "
                    .. "at their next login.",
                onAccept = function()
                    local ok, err = Profiles.Delete(name)
                    if not ok then Print(tostring(err)) end
                    RefreshConfig()
                end })
        end })
        del:SetPoint("LEFT", export, "RIGHT", 4, 0)
        L:Row(line, M.BUTTON_H + 2)
    end
    L:Gap(4)
    local nameBox = UI.EditBox(L.current, { width = 220, height = 20, hint = "Name" })
    L:Row(nameBox, 26)
    ButtonRow(L, {
        { "New (shipped defaults)", function()
            local n = Trim(nameBox:GetText())
            local ok, err = Profiles.New(n, true)
            if ok then Print("Created '" .. n .. "' with shipped defaults.") RefreshConfig() else Print(tostring(err)) end
        end, width = 160 },
        { "Copy current as", function()
            local n = Trim(nameBox:GetText())
            local ok, err = Profiles.New(n, false)
            if ok then Print("Copied this character's settings to '" .. n .. "'.") RefreshConfig() else Print(tostring(err)) end
        end, width = 130 },
        { "Rename current", function()
            local n = Trim(nameBox:GetText())
            local ok, err = Profiles.Rename(current, n)
            if ok then RefreshConfig() else Print(tostring(err)) end
        end, width = 130 },
    })
    L:Desc("Export uses the sections ticked below. New profiles are not worn by anyone until a "
        .. "character switches to them.")
    L:EndCard()

    -- ---------------------------------------------------------
    L:Card("Sections")
    L:Desc("The parts of a profile. Tick what Export, Copy and Reset should work on.")
    local sel = Selected()
    for _, sec in ipairs(Profiles.SECTIONS) do
        local cb = UI.Checkbox(L.current, sec.label, sel[sec.key] and true or false, function(v)
            sel[sec.key] = v and true or false
        end)
        L:Row(cb, 17)
        if sec.desc then L:Desc(sec.desc) end
    end
    ButtonRow(L, {
        { "All", function() for _, sec in ipairs(Profiles.SECTIONS) do sel[sec.key] = true end RefreshConfig() end, width = 60 },
        { "None", function() for _, sec in ipairs(Profiles.SECTIONS) do sel[sec.key] = false end RefreshConfig() end, width = 60 },
    })
    L:Gap(6)
    local sources = {}
    for _, n in ipairs(names) do if n ~= current then sources[#sources + 1] = { text = n, value = n } end end
    local copyFrom = sources[1] and sources[1].value
    if #sources > 0 then
        Dropdown(L, "Copy the ticked sections from", sources, function() return copyFrom end,
            function(v) copyFrom = v end)
        ButtonRow(L, { { "Copy into this character's profile", function()
            if not copyFrom then return end
            local keys = SelectedList()
            if #keys == 0 then Print("Tick at least one section.") return end
            UI.Confirm({ title = "Copy sections", acceptText = "Copy",
                text = "Copy " .. SectionLabels(keys) .. " from '" .. copyFrom .. "' over this character's "
                    .. "settings? A reload follows.",
                onAccept = function()
                    LoadThenReload("Copied from '" .. copyFrom .. "'", function()
                        local ok, err = Profiles.CopyFrom(copyFrom, keys)
                        if ok then Profiles.WriteBack() end
                        return ok, err
                    end)
                end })
        end, width = 230 } })
    end
    ButtonRow(L, { { "Reset the ticked sections to defaults", function()
        local keys = SelectedList()
        if #keys == 0 then Print("Tick at least one section.") return end
        UI.Confirm({ title = "Reset sections", destructive = true, acceptText = "Reset",
            text = "Reset " .. SectionLabels(keys) .. " on this character's profile to shipped defaults? A reload follows.",
            onAccept = function()
                LoadThenReload("Reset", function()
                    Profiles.ResetSections(keys)
                    Profiles.WriteBack()
                    return true
                end)
            end })
    end, width = 260 } })
    L:EndCard()

    -- ---------------------------------------------------------
    L:Card("Export")
    local exportBox = UI.TextBox(L.current, { width = 400, height = 72, selectOnFocus = true })
    L:Row(exportBox, 80)
    L.exportBox = exportBox
    ButtonRow(L, { { "Export this character's ticked sections", function()
        local str, err = Profiles.Export(nil, SelectedList())
        if not str then Print("Could not export: " .. tostring(err)) return end
        exportBox:SetText(str)
        exportBox:Focus()
    end, width = 260 } })
    L:Desc("Click the box, select all (Ctrl+A) and copy (Ctrl+C). The game has no clipboard API, so "
        .. "this is the only way out. Export next to a profile above does the same for that profile.")
    L:EndCard()

    -- ---------------------------------------------------------
    L:Card("Import")
    local importBox = UI.TextBox(L.current, { width = 400, height = 72 })
    L:Row(importBox, 80)
    Import.StatusRow(L, importBox, "profile")
    local importName = UI.EditBox(L.current, { width = 200, height = 20, hint = "Save as a new profile (optional)" })
    L:Row(importName, 26)
    ButtonRow(L, {
        { "Apply to this character", function()
            if Import.Redirect(importBox:GetText(), "profile") then return end
            local snap, err = Profiles.Import(Import.Clean(importBox:GetText()))
            if not snap then Print("Import failed: " .. tostring(err)) return end
            local carried = Profiles.SectionsIn(snap)
            UI.Confirm({ title = "Import", acceptText = "Import",
                text = "This string carries: " .. SectionLabels(carried) .. ". Those sections replace this "
                    .. "character's; everything else stays. A reload follows.",
                onAccept = function()
                    LoadThenReload("Imported", function()
                        local ok, applyErr = Profiles.Apply(snap)
                        if ok then Profiles.WriteBack() end
                        return ok, "Import failed: " .. tostring(applyErr)
                    end)
                end })
        end, width = 170 },
        { "Save as new profile", function()
            if Import.Redirect(importBox:GetText(), "profile") then return end
            local snap, err = Profiles.Import(Import.Clean(importBox:GetText()))
            if not snap then Print("Import failed: " .. tostring(err)) return end
            local n = Trim(importName:GetText())
            if n == "" then Print("Give the new profile a name first.") return end
            if Profiles.Store()[n] then Print("'" .. n .. "' already exists.") return end
            Profiles.Store()[n] = snap
            Print("Saved '" .. n .. "' (" .. SectionLabels(Profiles.SectionsIn(snap)) .. "). Switch a character to it above.")
            importBox:SetText("")
            RefreshConfig()
        end, width = 150 },
    })
    L:Desc("A ZacUI profile string from another character, account or person. Checked for damage "
        .. "and read as pure data - nothing inside an import string is ever executed. Any other "
        .. "string ZacUI or Readycheck exports can be pasted here too: the line under the box says "
        .. "what it is, and the buttons offer to import it as that.")
    L:EndCard()
end)
