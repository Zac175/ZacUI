-- Core_Media - ONE font and ONE bar texture for everything.
-- Part of ZacUI; load order is set by the TOC.
--
-- The font is the one Core_Fonts already pushes into Blizzard's font
-- objects (ZacUIDB.font.name): ZacUI's own windows, the HUD and the
-- action bars read it directly. The bar texture is new here
-- (ZacUIDB.media.bar, a SharedMedia name): ZacUI's own status bars read
-- it through Media.BarPath().
--
-- Everything that keeps a font or texture of its own - the unit frames,
-- the nameplates, the meter, Readycheck, the aura engine - is a TARGET.
-- A target registers an apply function; Media.Apply() hands every ticked
-- target the current names and the target writes them into its own
-- settings and restyles. So a change on the Fonts & Textures page lands
-- everywhere at once, and any one target can still be un-ticked and set
-- by hand on its own page afterwards.
--
--   ns.Media.FontName() / FontPath()    the global font (name / file)
--   ns.Media.BarName()  / BarPath(dflt) the global bar texture
--   ns.Media.RegisterTarget(key, { label=, desc=, order=, manual=,
--                                  apply = function(font, bar) end })
--   ns.Media.Apply(key?)                push to every ticked target (or one)
--   ns.Media.SetTargetOn(key, on) / TargetOn(key) / Targets()
--   ns.Media.PushAuras(onDone)          rewrite the aura engine's displays
--
-- A target's apply runs under pcall and never in combat for anything
-- protected; the aura push is manual (a button) because it rewrites
-- every display's saved data.

local ADDON_NAME, ns = ...

local Print = ns.Print
local ResolveFontPath = ns.ResolveFontPath

local Media = {}
ns.Media = Media

local function LSM() return LibStub and LibStub("LibSharedMedia-3.0", true) end

local function DB()
    ZacUIDB.media = ZacUIDB.media or {}
    local m = ZacUIDB.media
    m.targets = m.targets or {}
    return m
end
Media.DB = DB

-- ============================================================
-- THE TWO VALUES
-- ============================================================
function Media.FontName()
    local f = ZacUIDB and ZacUIDB.font
    local n = f and f.name
    if n and n ~= "" then return n end
    return nil
end

function Media.FontPath()
    return ResolveFontPath(Media.FontName())
end

function Media.BarName()
    local n = ZacUIDB and ZacUIDB.media and ZacUIDB.media.bar
    if n and n ~= "" then return (ns.NewMediaName and ns.NewMediaName(n)) or n end
    return nil
end

-- the file behind the chosen texture; `default` (or ZacUI's gradient)
-- when nothing is chosen or the name is not registered
function Media.BarPath(default)
    local n = Media.BarName()
    local lsm = LSM()
    if n and lsm then
        local p = lsm:Fetch("statusbar", n, true)
        if p then return p end
    end
    return default or ns.TEX_NORM
end

function Media.SetFont(name)
    ZacUIDB.font = ZacUIDB.font or {}
    ZacUIDB.font.name = (name and name ~= "") and name or nil
    if ns.ApplyFonts then ns.ApplyFonts() end
    Media.Apply()
end

-- ZacUI's own status bars (the ones it skins or draws itself) register
-- here as they are made, so a new texture lands on them at once rather
-- than on the next reload. Weak keys: a bar that goes away is forgotten.
local tracked = setmetatable({}, { __mode = "k" })
function Media.TrackBar(bar)
    if bar and bar.SetStatusBarTexture then tracked[bar] = true end
end

function Media.RetextureTracked()
    local path = Media.BarPath()
    for bar in pairs(tracked) do
        if bar.SetStatusBarTexture then pcall(bar.SetStatusBarTexture, bar, path) end
    end
end

function Media.SetBar(name)
    DB().bar = (name and name ~= "") and name or nil
    Media.RetextureTracked()
    Media.Apply()
end

function Media.ListFonts()
    local out, lsm = {}, LSM()
    if lsm then for _, n in ipairs(lsm:List("font")) do out[#out + 1] = n end end
    return out
end

function Media.ListBars()
    local out, lsm = {}, LSM()
    if lsm then for _, n in ipairs(lsm:List("statusbar")) do out[#out + 1] = n end end
    return out
end

-- ============================================================
-- TARGETS
-- ============================================================
local targets = {}

function Media.RegisterTarget(key, t)
    t.key = key
    t.order = t.order or 50
    targets[key] = t
end

function Media.Targets()
    local list = {}
    for _, t in pairs(targets) do list[#list + 1] = t end
    table.sort(list, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.key < b.key
    end)
    return list
end

function Media.TargetOn(key)
    return DB().targets[key] ~= false
end

function Media.SetTargetOn(key, on)
    if on then DB().targets[key] = nil else DB().targets[key] = false end
end

-- Push the current font and texture into one target or every ticked one.
-- Manual targets (the aura push) only go when named. Returns how many
-- targets took it and a list of the ones that failed.
function Media.Apply(onlyKey)
    local font, bar = Media.FontName(), Media.BarName()
    local done, failed = 0, {}
    for _, t in ipairs(Media.Targets()) do
        local go = onlyKey and (t.key == onlyKey) or (not onlyKey and not t.manual and Media.TargetOn(t.key))
        if go and (not t.available or t.available()) then
            local ok, err = pcall(t.apply, font, bar)
            if ok then done = done + 1 else failed[#failed + 1] = t.label .. " (" .. tostring(err) .. ")" end
        end
    end
    if #failed > 0 then Print("media: " .. table.concat(failed, ", ")) end
    return done, failed
end

-- ============================================================
-- THE CORE'S OWN TARGETS
-- ============================================================
-- Readycheck keeps its own font and texture (its Appearance page); its
-- setters restyle everything it has drawn.
Media.RegisterTarget("readycheck", {
    label = "Readycheck",
    desc = "Readycheck's own font and bar texture (its Appearance > Fonts page).",
    order = 80,
    available = function() return _G.Readycheck ~= nil end,
    apply = function(font, bar)
        local RC = _G.Readycheck
        if font and RC.SetFont then RC:SetFont(font) end
        if bar and RC.SetTexture then RC:SetTexture(bar) end
    end,
})

-- ============================================================
-- THE AURA ENGINE
-- ============================================================
-- Every display keeps its own font (text, bar text, icon text, each text
-- sub-region) and every bar keeps its own texture. The push walks the
-- saved displays, rewrites those fields where they differ, and re-adds
-- each changed display so the engine rebuilds it - a handful per frame,
-- so a few hundred auras do not hitch the client. Fonts and textures are
-- SharedMedia names on both sides, so no translation is needed.
local function RetargetDisplay(data, font, bar)
    local changed = false
    local rt = data.regionType
    if font then
        if (rt == "text" or rt == "aurabar" or rt == "icon") and data.font and data.font ~= font then
            data.font = font; changed = true
        end
        if type(data.subRegions) == "table" then
            for _, s in ipairs(data.subRegions) do
                if type(s) == "table" and s.type == "subtext" and s.text_font ~= font then
                    s.text_font = font; changed = true
                end
            end
        end
    end
    if bar and rt == "aurabar" and data.texture ~= bar then
        data.texture = bar; changed = true
    end
    return changed
end

function Media.PushAuras(onDone)
    local saved, WA = _G.WeakAurasSaved, _G.WeakAuras
    -- ZacUI's own engine keeps its auras in its own saved variables
    if type(WA) == "table" and WA.IsZacUIEngine then saved = _G.ZacUIAurasSaved end
    if not (saved and type(saved.displays) == "table" and WA and WA.Add) then
        return false, "the aura engine is not loaded"
    end
    if InCombatLockdown and InCombatLockdown() then
        return false, "not in combat"
    end
    local font, bar = Media.FontName(), Media.BarName()
    if not font and not bar then return false, "no font or texture chosen" end
    local ids = {}
    for id in pairs(saved.displays) do ids[#ids + 1] = id end
    table.sort(ids)
    local i, changed = 0, 0
    local function step()
        local n = 0
        while n < 12 and i < #ids do
            i = i + 1
            local data = saved.displays[ids[i]]
            if type(data) == "table" and RetargetDisplay(data, font, bar) then
                changed = changed + 1
                pcall(WA.Add, data)
            end
            n = n + 1
        end
        if i < #ids then
            C_Timer.After(0, step)
        elseif onDone then
            onDone(changed, #ids)
        end
    end
    step()
    return true
end

Media.RegisterTarget("auras", {
    label = "Aura engine (WeakAuras)",
    desc = "Rewrites the font of every text and the texture of every bar in your auras. A button, not automatic: it edits each aura's saved data.",
    order = 90,
    manual = true,
    available = function() return _G.WeakAuras ~= nil end,
    apply = function() Media.PushAuras(function(c, n) Print(("auras: %d of %d updated."):format(c, n)) end) end,
})

-- ZacUI's gradient under the name the unit frames always used for it, so
-- it is in every texture list whether or not that part is loaded.
do
    local lsm = LSM()
    if lsm and ns.TEX_NORM then pcall(lsm.Register, lsm, "statusbar", "ZacUI Gradient", ns.TEX_NORM) end
end
