-- Config_AceRender - draws an AceConfig options table using ZacUI widgets.
-- Part of ZacUI; load order is set by the TOC.
--
-- WHY THIS EXISTS
-- WeakAuras does not hard-code its option screens. Nine builders -
-- GetTriggerOptions, GetLoadOptions, GetConditionOptions, GetActionOptions,
-- GetAnimationOptions, GetAuthorOptions, GetDisplayOptions,
-- GetGroupOptions, GetInformationOptions - each return a table describing
-- every control for a given aura, with `get` and `set` closing over the
-- real data.
--
-- Everything before this transcribed those descriptions by hand. That
-- approach cannot finish and cannot be trusted: it missed fields, it
-- ignored the gating that decides which fields apply, and where the
-- transcription drifted it wrote values the aura never reads - a form that
-- looks right and does nothing. Rendering the description itself removes
-- the entire class of mistake. What appears here is what WeakAuras would
-- show, gated how WeakAuras gates it, for this client and this aura.
--
-- THE CONTRACT, which is AceConfig's and not ours:
--   name/desc/values/hidden/disabled/order  value or function(info)
--   get(info) -> value                      set(info, value)
--   multiselect: get(info, key) -> bool     set(info, key, bool)
--   colour: get(info) -> r,g,b,a            set(info, r,g,b,a)
--   group: recurse into .args
--
-- `info` is an array of the key path with info[#info] the current key.
-- Handlers that ignore it still work; the ones that read info[#info] -
-- and WeakAuras has many - break without it, which is why it is built
-- properly rather than passed as nil.

local ADDON_NAME, ns = ...

-- shared state from earlier ZacUI files
local Print = ns.Print
local UI = ns.UI

local M, F = UI.M, UI.F

-- ============================================================
-- RESOLVING THE CONTRACT
-- ============================================================
local function Call(v, info, ...)
    if type(v) ~= "function" then return v end
    local ok, res = pcall(v, info, ...)
    if ok then return res end
    return nil
end

-- A WRITE THAT FAILS IS SAID OUT LOUD. Reads can fail quietly - a label
-- that falls back to its key is a cosmetic gap. A set that dies half way
-- is not: WeakAuras' group setters bracket their loop with
-- pauseOptionsProcessing(true) ... (false), and an error in between leaves
-- the engine refusing every load scan for the rest of the session, with
-- the only visible symptom being state that will not change. That is what
-- "Never is ticked and it still says loaded" was, and pcall had eaten the
-- reason.
local function Write(fn, info, ...)
    if type(fn) ~= "function" then return false end
    local ok, err = pcall(fn, info, ...)
    if not ok then
        Print("|cffff6666Setting '" .. tostring(info[#info])
            .. "' failed:|r " .. tostring(err))
    end
    return ok
end

local function Text(v, info)
    local r = Call(v, info)
    if type(r) == "string" then return r end
    if type(r) == "number" then return tostring(r) end
    return nil
end

-- Colour codes are how WeakAuras signals state in a label - a negated
-- toggle comes back wrapped in red. Stripping them keeps our own widget
-- colouring authoritative, and a label full of escape codes reads as
-- garbage in a font that is not the one they were written for.
local function Plain(s)
    if type(s) ~= "string" then return s end
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function Values(opt, info)
    local v = Call(opt.values, info)
    if type(v) == "string" then v = nil end
    return type(v) == "table" and v or nil
end

-- ============================================================
-- INHERITANCE, WHICH IS NOT A DETAIL OF ACECONFIG BUT THE WHOLE
-- MECHANISM BY WHICH A GROUP AURA IS EDITED
-- ============================================================
-- AceConfig lets a group node carry get, set, func, validate, confirm,
-- disabled, hidden and handler on behalf of everything beneath it. A leaf
-- that defines none of them uses its nearest ancestor's. This renderer
-- read them off the leaf only, and that is why the Load tab's Never box
-- would not tick.
--
-- Follow it through OptionsPrivate.GetLoadOptions. For a single aura the
-- leaves carry their own handlers and everything worked. For a GROUP the
-- builder takes a different branch:
--
--     if(data.controlledChildren) then
--       removeFuncs(load);
--       ...
--       load.get = function(info, ...) return getAll(data, info, ...); end;
--       load.set = function(info, ...) setAll(data, info, ...); ... end
--
-- and removeFuncs is recursive:
--
--     if(i == "get" or i == "set" or i == "hidden" or i == "disabled") then
--       intable[i] = nil;
--
-- So every leaf under a group is deliberately STRIPPED of its handlers and
-- given one pair at the top that reads the common value across the
-- children and writes to all of them. Reading `opt.get` on such a leaf
-- returns nil, so the control drew unchecked no matter what the auras
-- said; `opt.set` returned nil, so `if opt.set then` was false and the
-- click did nothing at all. Not a failed write - no write.
--
-- Every top-level row in the tree is a package, so this was every control
-- on every tab for everything you can see without expanding something.
-- Never was just the one that was obvious, because a checkbox that will
-- not tick is louder than a slider that snaps back.
local INHERITED = {
    "handler", "get", "set", "func", "validate", "confirm",
    "disabled", "hidden",
}

-- The environment a node passes to its children: what it declares itself,
-- over what it was handed. Returns the parent's table unchanged when the
-- node declares nothing, so a deep tree of plain groups costs no garbage.
local function Inherit(env, node)
    if type(node) ~= "table" then return env end
    local out
    for _, key in ipairs(INHERITED) do
        if node[key] ~= nil then
            if not out then
                out = {}
                for _, k in ipairs(INHERITED) do out[k] = env[k] end
            end
            out[key] = node[key]
        end
    end
    return out or env
end

-- One handler, resolved. AceConfig accepts a function OR a string naming a
-- method on `handler`, and the string form is called with the handler as
-- self. WeakAuras only ever uses functions, but a renderer that claims to
-- draw AceConfig tables should not quietly ignore half the contract.
local function Bind(env, opt, key)
    local v = opt[key]
    if v == nil then v = env[key] end
    if type(v) == "string" then
        local h = opt.handler or env.handler
        local m = h and h[v]
        if type(m) ~= "function" then return nil end
        return function(...) return m(h, ...) end
    end
    return v
end

-- ============================================================
-- ORDERING
-- ============================================================
-- AceConfig draws by `order`, and WeakAuras leans on it hard - the whole
-- layout of a trigger panel is expressed as fractional orders. Iterating
-- the table with pairs() instead produces a random pile of controls that
-- are individually correct and collectively unusable.
local function SortedKeys(args)
    local keys = {}
    for k in pairs(args) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        local oa = Call(args[a].order) or 0
        local ob = Call(args[b].order) or 0
        if type(oa) ~= "number" then oa = 0 end
        if type(ob) ~= "number" then ob = 0 end
        if oa ~= ob then return oa < ob end
        return tostring(a) < tostring(b)
    end)
    return keys
end

-- ============================================================
-- THE RENDERER
-- ============================================================
local MAX_DEPTH = 6

local function RenderArgs(stack, args, path, width, depth, stats, Refresh, env)
    if type(args) ~= "table" or depth > MAX_DEPTH then return end
    env = env or {}

    for _, key in ipairs(SortedKeys(args)) do
        local opt = args[key]
        if type(opt) == "table" then
            -- The info array AceConfig would have passed. Rebuilt per
            -- control because handlers key off its last element - and for
            -- a group aura the inherited get/set walk the WHOLE array to
            -- find the same option on each child, so a short or wrong path
            -- reads the wrong field rather than failing.
            local info = {}
            for i, p in ipairs(path) do info[i] = p end
            info[#info + 1] = key

            local hidden = Call(Bind(env, opt, "hidden"), info)
            if not hidden then
                local ok = pcall(function()
                    ns.RenderAceOption(stack, opt, info, key, width, depth,
                                       stats, Refresh, env)
                end)
                if not ok then
                    stats.failed = stats.failed + 1
                    stack:Label("(" .. tostring(key) .. " could not be drawn)",
                        nil, 0.85, 0.5, 0.5)
                end
            end
        end
    end
end

function ns.RenderAceOption(stack, opt, info, key, width, depth, stats, Refresh, env)
    env = env or {}
    local kind = opt.type
    local label = Plain(Text(opt.name, info)) or tostring(key)

    if kind == "group" then
        if label ~= "" then stack:Section(label) end
        RenderArgs(stack, opt.args, info, width, depth + 1, stats, Refresh,
                   Inherit(env, opt))
        return
    end

    -- Resolved once, from the leaf or from whichever ancestor declared it.
    local get      = Bind(env, opt, "get")
    local set      = Bind(env, opt, "set")
    local func     = Bind(env, opt, "func")
    local validate = Bind(env, opt, "validate")
    local disabled = Call(Bind(env, opt, "disabled"), info)

    if kind == "header" then
        stack:Gap(4)
        if label ~= "" then stack:Section(label) end
        return
    end

    if kind == "description" then
        if label and label ~= "" then stack:Label(label) end
        return
    end

    if kind == "execute" then
        local b = UI.Button(stack.p, label ~= "" and label or "Run",
            { width = math.min(160, width - 40), onClick = function()
                if disabled then return end
                if func then Write(func, info) end
                Refresh()
            end })
        stack:Add(b, 28)
        stats.drawn = stats.drawn + 1
        return
    end

    if kind == "toggle" then
        local cur = Call(get, info)
        local cb = UI.Checkbox(stack.p, label, cur and true or false,
            function(v)
                if disabled then return end
                if set then Write(set, info, v) end
                Refresh()
            end)
        stack:Add(cb, 19)
        stats.drawn = stats.drawn + 1
        return
    end

    if kind == "range" then
        local cur = Call(get, info)
        local w = UI.Slider(stack.p, {
            width = math.min(180, width - 40),
            min = opt.min or 0, max = opt.max or 100,
            step = opt.step or opt.bigStep or 1,
            value = tonumber(cur) or opt.min or 0,
            label = label,
            onChange = function(v)
                if disabled then return end
                if set then Write(set, info, v) end
            end,
        })
        stack:Add(w, 38)
        stats.drawn = stats.drawn + 1
        return
    end

    if kind == "select" then
        local values = Values(opt, info)
        if not values then
            stack:Label(label .. ": (no options)")
            return
        end
        local cur = Call(get, info)
        local w = UI.Dropdown(stack.p, {
            width = math.min(180, width - 40),
            items = function()
                local items = {}
                for k, text in pairs(values) do
                    items[#items + 1] = { text = Plain(tostring(text)), value = k }
                end
                table.sort(items, function(a, b) return a.text < b.text end)
                return items
            end,
            selected = function()
                local v = values[cur]
                return v and Plain(tostring(v)) or ""
            end,
            onSelect = function(v)
                if disabled then return end
                if set then Write(set, info, v) end
                Refresh()
            end,
        })
        stack:Label(label)
        stack:Add(w, 28)
        stats.drawn = stats.drawn + 1
        return
    end

    if kind == "multiselect" then
        local values = Values(opt, info)
        if not values then return end
        stack:Label(label)
        -- A checkbox per entry, which is what AceConfig draws. Long lists
        -- (every zone, every encounter) are capped so one option cannot
        -- produce four hundred frames on a redraw; the count says so.
        local shown, total = 0, 0
        for k, text in pairs(values) do
            total = total + 1
            if shown < 40 then
                shown = shown + 1
                local on = Call(get, info, k)
                local cb = UI.Checkbox(stack.p, "  " .. Plain(tostring(text)),
                    on and true or false,
                    function(v)
                        if disabled then return end
                        if set then Write(set, info, k, v) end
                        Refresh()
                    end)
                stack:Add(cb, 17)
            end
        end
        if total > shown then
            stack:Label("  ... and " .. (total - shown) .. " more options",
                nil, 0.7, 0.6, 0.35)
        end
        stats.drawn = stats.drawn + 1
        return
    end

    if kind == "input" then
        local cur = Call(get, info)
        stack:Label(label)
        if opt.multiline then
            local lines = type(opt.multiline) == "number" and opt.multiline or 8
            local h = math.max(80, math.min(220, lines * 13))
            local box = UI.TextBox(stack.p, {
                width = width - 24, height = h, text = tostring(cur or ""),
            })
            stack:Add(box, h + 6)
            local save = UI.Button(stack.p, "Save", { width = 70,
                onClick = function()
                    if disabled then return end
                    local text = box.editBox and box.editBox:GetText()
                        or (box.GetText and box:GetText())
                    if text == nil then return end
                    if validate then
                        local vok, verr = pcall(validate, info, text)
                        if vok and verr and verr ~= true then
                            Print("Not saved: " .. tostring(verr))
                            return
                        end
                    end
                    if set then Write(set, info, text) end
                    Refresh()
                end })
            stack:Add(save, 30)
        else
            local box = UI.EditBox(stack.p, {
                width = math.min(200, width - 40), text = tostring(cur or ""),
                onEnter = function(text)
                    if disabled then return end
                    if set then Write(set, info, text) end
                end,
            })
            stack:Add(box, 26)
        end
        stats.drawn = stats.drawn + 1
        return
    end

    -- Colour: a swatch that opens the game's colour picker (with opacity
    -- when the option has alpha), and the value as hex beside it - which
    -- is also the form people paste between auras. A renderer handed a
    -- widget set without UI.ColorPicker falls back to a plain chip.
    if kind == "color" then
        local r, g, b, a = Call(get, info)
        r, g, b = tonumber(r) or 1, tonumber(g) or 1, tonumber(b) or 1
        a = tonumber(a) or 1
        local cur = { r, g, b, a }

        local row = CreateFrame("Frame", nil, stack.p)
        row:SetSize(width - 24, 22)

        local function Hex(cr, cg, cb)
            return string.format("%02x%02x%02x", math.floor(cr * 255 + 0.5),
                math.floor(cg * 255 + 0.5), math.floor(cb * 255 + 0.5))
        end
        local chip, box
        local function Show()
            if chip and chip.Refresh then chip.Refresh()
            elseif chip then chip:SetColorTexture(cur[1], cur[2], cur[3], 1) end
            if box then box:SetText(Hex(cur[1], cur[2], cur[3])) end
        end
        if UI.ColorPicker then
            chip = UI.ColorPicker(row, { alpha = opt.hasAlpha and true or false,
                get = function() return cur[1], cur[2], cur[3], cur[4] end,
                set = function(nr, ng, nb, na)
                    if disabled then return end
                    cur[1], cur[2], cur[3] = nr, ng, nb
                    if na then cur[4] = na end
                    if set then Write(set, info, cur[1], cur[2], cur[3], cur[4]) end
                    if box then box:SetText(Hex(nr, ng, nb)) end
                end })
            chip:SetPoint("LEFT", 0, 0)
        else
            chip = row:CreateTexture(nil, "ARTWORK")
            chip._zui_own = true
            chip:SetSize(18, 18)
            chip:SetPoint("LEFT", 0, 0)
            chip:SetColorTexture(r, g, b, 1)
        end

        box = UI.EditBox(row, {
            width = math.min(120, width - 90), text = Hex(r, g, b),
            onEnter = function(text)
                if disabled then return end
                text = (text or ""):gsub("[^0-9a-fA-F]", "")
                if #text < 6 then
                    Print("Colour needs six hex digits, like ff8800.")
                    return
                end
                cur[1] = tonumber(text:sub(1, 2), 16) / 255
                cur[2] = tonumber(text:sub(3, 4), 16) / 255
                cur[3] = tonumber(text:sub(5, 6), 16) / 255
                Show()
                if set then Write(set, info, cur[1], cur[2], cur[3], cur[4]) end
            end,
        })
        box:SetPoint("LEFT", UI.ColorPicker and 38 or 24, 0)

        stack:Label(label)
        stack:Add(row, 26)
        stats.drawn = stats.drawn + 1
        return
    end

    -- Anything unrecognised is counted rather than silently dropped. A
    -- rendering gap that nobody can see is how the hand-written version
    -- stayed wrong for so long.
    stats.skipped = stats.skipped + 1
    stats.skippedTypes[tostring(kind)] = (stats.skippedTypes[tostring(kind)] or 0) + 1
end

-- ============================================================
-- ENTRY POINT
-- ============================================================
-- Returns what it managed to draw, so a caller can say "nothing here"
-- honestly instead of showing an empty panel.
function ns.RenderAceOptions(stack, options, width, Refresh)
    local stats = { drawn = 0, skipped = 0, failed = 0, skippedTypes = {} }
    if type(options) ~= "table" then return stats end

    Refresh = Refresh or function() end

    -- A builder returns either a group with .args, or the args directly.
    --
    -- THE ROOT IS A NODE, NOT A CONTAINER. Its own get/set/hidden/disabled
    -- are the ones a group aura's entire form runs on - dropping them here
    -- was the whole bug. Seed the chain with them.
    local args = options.args or options
    RenderArgs(stack, args, {}, width, 1, stats, Refresh,
               Inherit({}, options.args and options or nil))
    return stats
end
