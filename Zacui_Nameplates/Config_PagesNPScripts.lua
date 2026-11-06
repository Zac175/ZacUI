-- Config_PagesNPScripts - the script/mod editor for the nameplate
-- engine. Lists live here; the code editor is its own window.
-- Part of ZacUI; load order is set by the TOC.

local ADDON_NAME = ...
-- Zacui_Nameplates is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

-- shared state from earlier ZacUI files
local Print = ns.Print
local RefreshConfig = ns.RefreshConfig
local RegisterPage = ns.RegisterPage
local UI = ns.UI

local M, F = UI.M, UI.F

local function Engine()
    return ns.Nameplates and ns.Nameplates.Scripts
end

-- ============================================================
-- EDITOR WINDOW - one instance, retargeted per entry
-- ============================================================
local editor

local function BuildEditor()
    if editor then return editor end
    local S = Engine()
    editor = UI.Window("ZacUI_NPScriptEditor", 640, 540, "Plate script editor")

    local nameLabel = UI.Font(editor, F.LABEL,
        { text = "Name", cat = "text", key = "gray" })
    nameLabel:SetPoint("TOPLEFT", 14, -42)
    editor.nameBox = UI.EditBox(editor, { width = 280 })
    editor.nameBox:SetPoint("TOPLEFT", 14, -58)

    -- trigger row (scripts only; hidden for mods)
    editor.trigKindLabel = UI.Font(editor, F.LABEL,
        { text = "Trigger", cat = "text", key = "gray" })
    editor.trigKindLabel:SetPoint("TOPLEFT", 310, -42)
    local kinds = { cast = "Cast (spell id / name)",
                    aura = "Aura (spell id / name)",
                    npc = "NPC (npc id / name)" }
    editor.trigKind = UI.Dropdown(editor, { width = 150,
        items = function()
            return { { text = kinds.cast, value = "cast" },
                     { text = kinds.aura, value = "aura" },
                     { text = kinds.npc,  value = "npc" } }
        end,
        selected = function()
            return editor.entry and kinds[editor.entry.triggerKind or "cast"]
        end,
        onSelect = function(v)
            if editor.entry then editor.entry.triggerKind = v end
        end })
    editor.trigKind:SetPoint("TOPLEFT", 310, -58)
    editor.trigBox = UI.EditBox(editor, { width = 150,
        hint = "116, Frostbolt, ..." })
    editor.trigBox:SetPoint("LEFT", editor.trigKind, "RIGHT", 8, 0)

    -- hook picker
    editor.hookLabel = UI.Font(editor, F.LABEL,
        { text = "Hook", cat = "text", key = "gray" })
    editor.hookLabel:SetPoint("TOPLEFT", 14, -92)
    editor.hookDD = UI.Dropdown(editor, { width = 200,
        items = function()
            local S2 = Engine()
            local list = editor.isMod and S2.MOD_HOOKS or S2.SCRIPT_HOOKS
            local items = {}
            for _, h in ipairs(list) do
                local has = editor.entry and editor.entry.hooks
                    and editor.entry.hooks[h] and editor.entry.hooks[h] ~= ""
                items[#items + 1] = {
                    text = has and (h .. " *") or h, value = h }
            end
            return items
        end,
        selected = function()
            local h = editor.hook or "?"
            local has = editor.entry and editor.entry.hooks
                and editor.entry.hooks[h] and editor.entry.hooks[h] ~= ""
            return has and (h .. " *") or h
        end,
        onSelect = function(v)
            editor:StashCode()
            editor.hook = v
            editor.code:SetText((editor.entry.hooks or {})[v] or "")
            editor:SetStatus("")
        end })
    editor.hookDD:SetPoint("TOPLEFT", 14, -108)

    editor.status = UI.Font(editor, F.SMALL,
        { text = "", cat = "text", key = "gray", width = 380 })
    editor.status:SetPoint("LEFT", editor.hookDD, "RIGHT", 12, 0)

    editor.code = UI.TextBox(editor, { width = 612, height = 330 })
    editor.code:SetPoint("TOPLEFT", 14, -142)

    function editor:SetStatus(text, bad)
        self.status:SetText(text or "")
        self.status:SetTextColor(bad and 1 or 0.6, bad and 0.4 or 0.8,
            bad and 0.4 or 0.6, 1)
    end

    -- keep the code box's current text in the entry (unsaved until Save)
    function editor:StashCode()
        if self.entry and self.hook then
            self.entry.hooks = self.entry.hooks or {}
            self.entry.hooks[self.hook] = self.code:GetText()
        end
    end

    local check = UI.Button(editor, "Check code", { width = 100,
        tooltip = "Compiles the current hook without running it.",
        onClick = function()
            local S2 = Engine()
            local ok, err = S2.CheckCode(editor.code:GetText())
            if ok then
                editor:SetStatus("compiles clean.")
            else
                editor:SetStatus(tostring(err), true)
            end
        end })
    check:SetPoint("BOTTOMLEFT", 14, 14)

    local save = UI.Button(editor, "Save and apply", { width = 120,
        onClick = function()
            local S2 = Engine()
            editor:StashCode()
            editor.entry.name = editor.nameBox:GetText()
            if not editor.isMod then
                editor.entry.triggers = editor.trigBox:GetText()
            end
            editor.entry.rev = (editor.entry.rev or 0) + 1
            S2.Invalidate(editor.entry)
            local badHook, badErr
            for h, code in pairs(editor.entry.hooks or {}) do
                local ok, err = S2.CheckCode(code)
                if not ok then badHook, badErr = h, err break end
            end
            if badHook then
                editor:SetStatus(badHook .. ": " .. tostring(badErr), true)
            else
                editor:SetStatus("saved and live.")
                if ns.Nameplates then ns.Nameplates.RefreshAll() end
                RefreshConfig()
            end
        end })
    save:SetPoint("LEFT", check, "RIGHT", 8, 0)

    return editor
end

local function OpenEditor(entry, isMod)
    local e = BuildEditor()
    e.entry, e.isMod = entry, isMod
    e.nameBox:SetText(entry.name or "")
    e.trigKind:SetShown(not isMod)
    e.trigBox:SetShown(not isMod)
    e.trigKindLabel:SetShown(not isMod)
    if not isMod then e.trigBox:SetText(entry.triggers or "") end
    local S = Engine()
    local hooks = isMod and S.MOD_HOOKS or S.SCRIPT_HOOKS
    e.hook = hooks[1]
    for _, h in ipairs(hooks) do
        if entry.hooks and entry.hooks[h] and entry.hooks[h] ~= "" then
            e.hook = h
            break
        end
    end
    e.code:SetText((entry.hooks or {})[e.hook] or "")
    e:SetStatus("")
    UI.OpenWindow(e)
end

-- ============================================================
-- PAGE
-- ============================================================
RegisterPage("PlateScripts", function(L)
    local S = Engine()
    local blurb = "MODS run hooks on every plate; SCRIPTS fire on a trigger "
        .. "(a cast, an aura, an npc). Code is a function: "
        .. "function(self, unit, envTable, modTable) ... end. self is the plate "
        .. "frame, envTable persists per plate per script, ZNP is the engine. "
        .. "Errors print once and never take the plates down."
    if L.asTab then
        L:Card("Plate scripts")
        L:Desc(blurb)
        L:EndCard()
    else
        L:Header("Plate scripts", blurb)
    end

    if not S then
        L:Notice("missing", "The nameplate engine did not load.")
        return
    end
    local db = S.DB()

    local function EntryRow(list, i, entry, isMod)
        -- (the name wraps before Edit and x, which hold the right edge)
        local rowW = math.min(380, L:Room())
        local row = UI.Holder(L.current)
        row:SetSize(rowW, 18)
        local del = UI.Button(row, "x", { width = 16, height = 14,
            size = F.SMALL,
            onClick = function()
                table.remove(list, i)
                if ns.Nameplates then ns.Nameplates.RefreshAll() end
                RefreshConfig()
            end })
        del:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -2)
        local edit = UI.Button(row, "Edit", { width = 44, height = 14,
            size = F.SMALL,
            onClick = function() OpenEditor(entry, isMod) end })
        edit:SetPoint("RIGHT", del, "LEFT", -4, 0)
        local cb = UI.Checkbox(row, entry.name or "?",
            entry.enabled and true or false,
            function(v)
                entry.enabled = v and true or false
                if ns.Nameplates then ns.Nameplates.RefreshAll() end
            end, { width = rowW - (del:GetWidth() or 16) - 4 - (edit:GetWidth() or 44) - 8 })
        cb:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -2)
        row:SetHeight(math.max(18, (cb:GetHeight() or 14) + 4))
        L:Row(row, 21 + (cb._zExtraH or 0))
    end

    -- ============================================================
    L:Card("Mods (every plate)")
    for i, mod in ipairs(db.mods) do
        EntryRow(db.mods, i, mod, true)
    end
    local addMod = UI.Button(L.current, "New mod", { width = 90,
        onClick = function()
            db.mods[#db.mods + 1] = {
                name = "New mod", enabled = false, rev = 1, hooks = {} }
            RefreshConfig()
            OpenEditor(db.mods[#db.mods], true)
        end })
    L:Row(addMod, M.BUTTON_H + 4)
    L:EndCard()

    -- ============================================================
    L:Card("Scripts (trigger-driven)")
    for i, script in ipairs(db.scripts) do
        EntryRow(db.scripts, i, script, false)
    end
    local addScript = UI.Button(L.current, "New script", { width = 90,
        onClick = function()
            db.scripts[#db.scripts + 1] = {
                name = "New script", enabled = false, rev = 1,
                triggerKind = "cast", triggers = "", hooks = {} }
            RefreshConfig()
            OpenEditor(db.scripts[#db.scripts], false)
        end })
    L:Row(addScript, M.BUTTON_H + 4)
    L:EndCard()

    -- ============================================================
    L:Card("Hook reference")
    L:Desc("MOD hooks: Initialization (once, modTable only), Constructor "
        .. "(once per plate frame), Nameplate Added / Updated / Removed, "
        .. "Cast Start / Stop, Target Changed, Enter / Leave Combat. "
        .. "Updated ticks every 0.5s on every visible plate.")
    L:Desc("SCRIPT hooks: OnShow when the trigger starts matching on a "
        .. "plate, OnUpdate every 0.5s while it matches, OnHide when it "
        .. "stops (also when the plate's unit despawns). Triggers are a "
        .. "comma list; numbers match spell/npc ids, anything else "
        .. "matches names.")
    L:Desc("The disabled example script shows the working pattern: build "
        .. "widgets into envTable once, Show them in OnShow, Hide them "
        .. "in OnHide.")
    L:EndCard()
end)
