-- Config_Import - adopt settings from the addons you already have, so the
-- whole UI matches without setting the same thing twice.
-- Part of ZacUI; load order is set by the TOC.
--
-- TWO DIRECTIONS, and the difference is stated plainly in the UI because
-- one of them is far more invasive than the other:
--
--   PULL   read another addon's settings and adopt them as ZacUI's. Only
--          ever writes to ZacUIDB. This is the default and the safe one.
--   PUSH   write ZacUI's colours into another addon's saved variables,
--          for widgets that addon owns and will not let a skinner touch
--          (Prat's edit box is the whole reason this exists). Always
--          opt-in, never part of the first-run prompt.
--
-- TIMING: this runs at PLAYER_LOGIN, not ADDON_LOADED. Another addon's
-- SavedVariables are only guaranteed to exist after its own ADDON_LOADED,
-- and load order between two addons is not ours to control.
--
-- Colours are read through the source addon's OWN accessor where it has
-- one. Readycheck keeps user overrides in its DB and defaults in code, so
-- reading the DB alone would import a half-empty palette; asking
-- Readycheck:GetColor returns what is actually on screen.

local ADDON_NAME, ns = ...

-- shared state from earlier ZacUI files
local GetColor = ns.GetColor
local Print = ns.Print
local RefreshConfig = ns.RefreshConfig
local RegisterPage = ns.RegisterPage
local ResolveFontPath = ns.ResolveFontPath
local SetColor = ns.SetColor
local UI = ns.UI

local M, F = UI.M, UI.F

local function Loaded(name)
    local fn = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    if not fn then return false end
    local ok, res = pcall(fn, name)
    return ok and res and true or false
end

-- ============================================================
-- READYCHECK -> ZACUI
-- ============================================================
-- Readycheck's palette is organised the same way ours is but with its own
-- key names. This is the whole translation, written out rather than
-- guessed at from string similarity.
local RC_COLORS = {
    { "ui", "windowBackground",   "ui", "windowBg"    },
    { "ui", "elementBackground",  "ui", "elementBg"   },
    { "ui", "cardBackground",     "ui", "cardBg"      },
    { "ui", "headerBackground",   "ui", "headerBg"    },
    { "ui", "borderNormal",       "ui", "border"      },
    { "ui", "borderHover",        "ui", "borderHover" },
    { "ui", "accentGold",         "ui", "accent"      },
    { "buttons", "normalBackground",     "button", "bg"          },
    { "buttons", "hoverBackground",      "button", "hover"       },
    { "buttons", "pressedBackground",    "button", "pressed"     },
    { "buttons", "disabledBackground",   "button", "disabled"    },
    { "buttons", "configuredBackground", "button", "active"      },
    { "buttons", "configuredHover",      "button", "activeHover" },
    { "buttons", "xNormal",              "button", "xNormal"     },
    { "buttons", "xHover",               "button", "xHover"      },
    { "sidebar", "background",         "sidebar", "bg"          },
    { "sidebar", "buttonNormal",       "sidebar", "rowNormal"   },
    { "sidebar", "buttonHover",        "sidebar", "rowHover"    },
    { "sidebar", "buttonSelected",     "sidebar", "rowSelected" },
    { "sidebar", "selectionIndicator", "sidebar", "indicator"   },
    { "checkbox", "background",  "checkbox", "bg"          },
    { "checkbox", "border",      "checkbox", "border"      },
    { "checkbox", "checkmark",   "checkbox", "check"       },
    { "checkbox", "hoverBorder", "checkbox", "hoverBorder" },
    { "dropdown", "background", "dropdown", "bg"        },
    { "dropdown", "itemHover",  "dropdown", "itemHover" },
    { "dropdown", "itemText",   "dropdown", "itemText"  },
    { "dropdown", "arrow",      "dropdown", "arrow"     },
    { "dropdown", "selected",   "dropdown", "selected"  },
    { "scrollbar", "track", "scrollbar", "track" },
    { "scrollbar", "thumb", "scrollbar", "thumb" },
    { "text", "normal", "text", "normal" },
    { "text", "gray",   "text", "gray"   },
    { "text", "gold",   "text", "gold"   },
    { "text", "green",  "text", "green"  },
    { "text", "red",    "text", "red"    },
    { "text", "orange", "text", "orange" },
    { "text", "blue",   "text", "blue"   },
    { "tooltip", "background", "tooltip", "bg"     },
    { "tooltip", "border",     "tooltip", "border" },
    { "tooltip", "titleText",  "tooltip", "title"  },
    { "tooltip", "bodyText",   "tooltip", "body"   },
}

-- Readycheck keeps user colour overrides PER CHARACTER, under
-- ReadycheckDB.characters[<charKey>].customColors - not at the root. The
-- root lookup found nothing, which silently disabled the "was this
-- deliberately set to white" escape hatch below and made the whole
-- no-Readycheck-loaded fallback path dead.
local function CustomColor(cat, key)
    local db = _G.ReadycheckDB
    if type(db) ~= "table" then return nil end
    local function From(tbl)
        local c = tbl and tbl.customColors and tbl.customColors[cat]
        return c and c[key] or nil
    end
    local direct = From(db)
    if direct then return direct end
    if type(db.characters) == "table" then
        -- Prefer this character's own overrides; fall back to any other
        -- character's, since a shared look is the point of importing.
        local me = UnitName and UnitName("player")
        local realm = GetRealmName and GetRealmName()
        if me and realm then
            local mine = From(db.characters[me .. " - " .. realm])
                or From(db.characters[me .. "-" .. realm])
            if mine then return mine end
        end
        for _, char in pairs(db.characters) do
            local c = From(char)
            if c then return c end
        end
    end
    return nil
end

local function ReadycheckColor(cat, key)
    local RC = _G.Readycheck
    if RC and RC.GetColor then
        local ok, c = pcall(RC.GetColor, RC, cat, key)
        if ok and type(c) == "table" and c.r then
            -- Readycheck answers an UNKNOWN key with white rather than
            -- nil, so a typo in the table above would import a UI full of
            -- white. Reject white unless the user really did choose it.
            if c.r == 1 and c.g == 1 and c.b == 1 then
                if not CustomColor(cat, key) then return nil end
            end
            return c
        end
    end
    return CustomColor(cat, key)
end

local function Channel(v)
    return type(v) == "number" and v >= 0 and v <= 1
end

local function ReadycheckFont()
    local RC = _G.Readycheck
    local fs = RC and RC.db and RC.db.fontSettings
    if not fs then
        local db = _G.ReadycheckDB
        fs = db and db.fontSettings
        -- Readycheck profiles its DB per character on some setups; take
        -- the first profile that actually carries font settings.
        if not fs and db and type(db.profiles) == "table" then
            -- pairs() has no defined order, so "the first profile" would
            -- be a different character between sessions. Sort the keys and
            -- take the lowest, so at least it is the same one every time.
            local names = {}
            for name, prof in pairs(db.profiles) do
                if type(prof) == "table" and prof.fontSettings then
                    names[#names + 1] = tostring(name)
                end
            end
            table.sort(names)
            if names[1] then fs = db.profiles[names[1]].fontSettings end
        end
    end
    return fs
end

-- ============================================================
-- SOURCES
-- ============================================================
-- Each source answers three questions: is it here, what would it change,
-- and how do I do it. The page and the first-run prompt are both just
-- renderings of this list.
local SOURCES = {
    {
        key = "rc_colors", addon = "Readycheck", direction = "pull",
        label = "Readycheck colours",
        desc = "Adopt Readycheck's palette so both addons share one look. "
            .. "Reads Readycheck's live colours, including any you have "
            .. "customised. Writes only to ZacUI.",
        available = function()
            return Loaded("Readycheck") or _G.ReadycheckDB ~= nil
        end,
        preview = function()
            local n = 0
            for _, map in ipairs(RC_COLORS) do
                if ReadycheckColor(map[1], map[2]) then n = n + 1 end
            end
            return n .. " colours available"
        end,
        apply = function()
            local n = 0
            for _, map in ipairs(RC_COLORS) do
                local c = ReadycheckColor(map[1], map[2])
                -- Validate before it reaches our saved variables. A
                -- hand-edited or malformed source DB with a STRING colour
                -- would be written straight through, and then every
                -- SetVertexColor in ZacUI errors - permanently, because
                -- it is saved.
                if c and Channel(c.r) and Channel(c.g) and Channel(c.b) then
                    -- Alpha is NOT imported. Readycheck's accent ships at
                    -- 0.6 alpha because it is only ever used as a hairline;
                    -- ZacUI uses the same hue as a solid text colour, and
                    -- copying the alpha across makes every gold label
                    -- translucent.
                    local keep = GetColor(map[3], map[4])
                    SetColor(map[3], map[4], c.r, c.g, c.b, keep and keep.a or 1)
                    n = n + 1
                end
            end
            return n .. " colours imported"
        end,
    },
    {
        key = "rc_font", addon = "Readycheck", direction = "pull",
        label = "Readycheck font",
        desc = "Adopt the typeface, size and outline Readycheck is using. "
            .. "Size is converted to ZacUI's relative adjustment, so "
            .. "Blizzard's own type hierarchy is preserved.",
        available = function()
            return ReadycheckFont() ~= nil
        end,
        preview = function()
            local fs = ReadycheckFont()
            if not fs then return "not found" end
            return (fs.selectedFont or "default") .. ", " .. (fs.fontSize or 12) .. "pt"
        end,
        apply = function()
            local fs = ReadycheckFont()
            if not fs then return "nothing to import" end
            local parts = {}
            local face = fs.selectedFont
            -- ResolveFontPath returns a file path given as-is, so a bare
            -- truthiness test is not enough. Readycheck ships the sentinel "default",
            -- which would then be stored as a font PATH and pushed into
            -- STANDARD_TEXT_FONT on the next login - from an unattended
            -- first-run prompt. Only adopt a name LSM actually resolved to
            -- something else, or a real file path.
            if type(face) == "string" and face ~= "" and face:lower() ~= "default" then
                local resolved = ResolveFontPath(face)
                local isPath = face:lower():match("%.ttf$") or face:lower():match("%.otf$")
                if isPath or (resolved and resolved ~= face) then
                    ZacUIDB.font.name = face
                    parts[#parts + 1] = face
                end
            end
            local size = tonumber(fs.fontSize)
            if size then
                -- Readycheck stores an absolute base size around 12.
                local delta = math.max(-3, math.min(6, size - 12))
                ZacUIDB.font.delta = delta
                parts[#parts + 1] = (delta >= 0 and "+" or "") .. delta .. "pt"
            end
            local flags = fs.fontOutline or fs.fontFlags
            if flags ~= nil then
                ZacUIDB.font.outline = (flags == "" ) and "NONE" or "OUTLINE"
                parts[#parts + 1] = (flags == "") and "no outline" or "outlined"
            end
            if ns.ApplyFonts then ns.ApplyFonts() end
            return #parts > 0 and table.concat(parts, ", ") or "nothing to import"
        end,
    },
}

local function Available()
    local out = {}
    for _, s in ipairs(SOURCES) do
        local ok, res = pcall(s.available)
        if ok and res then out[#out + 1] = s end
    end
    return out
end

local function Run(keys)
    local done = {}
    for _, s in ipairs(SOURCES) do
        if keys[s.key] then
            local ok, res = pcall(s.apply)
            done[#done + 1] = s.label .. ": " .. (ok and tostring(res) or "failed")
        end
    end
    -- `keys` carries explicit false entries for the unticked boxes, so
    -- this has to test the VALUE. Marking an unselected source as
    -- imported also flips its checkbox default on the next page build.
    ZacUIDB.importedFrom = ZacUIDB.importedFrom or {}
    for k, v in pairs(keys) do
        if v then ZacUIDB.importedFrom[k] = true end
    end
    for _, line in ipairs(done) do Print(line) end
    if RefreshConfig then RefreshConfig() end
    return done
end

-- ============================================================
-- FIRST RUN
-- ============================================================
-- Offered once, and only for PULL sources - a first-run prompt that writes
-- to somebody else's addon would be indefensible. Declining is remembered
-- so it never asks again; the page stays available either way.
local function FirstRunImport()
    if ZacUIDB.importPrompted then return end

    local pulls = {}
    for _, s in ipairs(Available()) do
        if s.direction == "pull" then pulls[#pulls + 1] = s end
    end
    -- Do NOT latch when there was nothing to offer. Installing ZacUI
    -- before Readycheck would otherwise mean the offer is never made.
    if #pulls == 0 then return end

    local names = {}
    for _, s in ipairs(pulls) do names[#names + 1] = s.label end

    -- First in the login popup queue (Core_Popups), a second after login
    -- so it lands after the login chat rather than underneath it.
    local function Show()
        ZacUIDB.importPrompted = true
        return UI.Confirm({
            title = "ZacUI - first run",
            text = "Found settings ZacUI can adopt so your interface "
                .. "matches what you already have:\n\n"
                .. table.concat(names, "\n") .. "\n\n"
                .. "This only changes ZacUI's own settings. You can undo it "
                .. "from Appearance > Import, or change anything by hand "
                .. "afterwards.",
            acceptText = "Adopt them",
            onAccept = function()
                local keys = {}
                for _, s in ipairs(pulls) do keys[s.key] = true end
                Run(keys)
                ns.AskReload("Imported. Frames that are already drawn pick the new colours and font up after a reload.")
            end,
        })
    end
    if ns.Popups then
        ns.Popups.Want("import", Show, { delay = 1 })
    else
        C_Timer.After(1, Show)
    end
end

-- ============================================================
-- PAGE
-- ============================================================
RegisterPage("Import", function(L)
    L:Header("Import",
        "Pick up settings from the addons you already have, so you are not "
        .. "configuring the same look twice.")

    local found = Available()
    if #found == 0 then
        L:Card("Nothing to import")
        L:Desc("ZacUI did not find any of the addons it knows how to import "
            .. "from. Supported today: Readycheck (colours and font).")
        L:EndCard()
        return
    end

    local picked = {}
    local function Section(direction, title, blurb)
        local list = {}
        for _, s in ipairs(found) do
            if s.direction == direction then list[#list + 1] = s end
        end
        if #list == 0 then return end

        L:Card(title)
        L:Desc(blurb)
        L:Gap(2)
        for _, s in ipairs(list) do
            local already = ZacUIDB.importedFrom and ZacUIDB.importedFrom[s.key]
            local cb = UI.Checkbox(L.current, s.label, direction == "pull" and not already,
                function(v) picked[s.key] = v end)
            picked[s.key] = (direction == "pull" and not already) or false
            L:Row(cb, 17)

            local ok, preview = pcall(s.preview)
            L:Desc(s.desc .. (ok and preview and ("  (" .. preview .. ")") or ""))
            if already then
                local note = UI.Font(L.current, F.SMALL,
                    { text = "already imported once", cat = "text", key = "green" })
                note:SetPoint("TOPLEFT", L.current, "TOPLEFT", M.DESC_X, L.current._y + 2)
                L.current._y = L.current._y - 14
            end
        end
        L:EndCard()
    end

    Section("pull", "Adopt into ZacUI",
        "Reads the other addon's settings. Only ZacUI's own saved variables "
        .. "are changed.")
    Section("push", "Send ZacUI's colours out",
        "Writes into the other addon's settings, for widgets it owns and "
        .. "will not let a skin touch. Reversible from that addon's options.")

    L:Card("Apply")
    local row = UI.Holder(L.current)
    row:SetSize(360, M.BUTTON_H)
    local go = UI.Button(row, "Apply selected", { width = 130, onClick = function()
        local any = false
        for _, v in pairs(picked) do if v then any = true end end
        if not any then
            Print("Nothing selected to import.")
            return
        end
        -- A push writes to somebody else's addon, so it gets a confirm.
        local pushing = false
        for _, s in ipairs(SOURCES) do
            if picked[s.key] and s.direction == "push" then pushing = true end
        end
        if pushing then
            UI.Confirm({
                title = "Write to another addon",
                text = "This will change settings inside another addon's "
                    .. "saved variables, not just ZacUI's. You can undo it "
                    .. "from that addon's own options.",
                acceptText = "Go ahead",
                onAccept = function() Run(picked) end,
            })
        else
            Run(picked)
        end
    end })
    go:SetPoint("LEFT")
    L:Row(row, M.BUTTON_H + 4)
    L:Desc("Colours apply to ZacUI's own windows immediately. Frames that "
        .. "are already skinned pick them up on the next reload.")
    L:EndCard()
end)

-- shared with later ZacUI files
ns.FirstRunImport = FirstRunImport
