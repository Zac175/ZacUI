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
-- everywhere at once. An un-ticked target keeps a bar texture of its own;
-- its face is ZacUI's font all the same (one font for every text).
--
--   ns.Media.FontName() / FontPath()    the global font (name / file)
--   ns.Media.BarName()  / BarPath(dflt) the global bar texture
--   ns.Media.RegisterTarget(key, { label=, desc=, order=, manual=,
--                                  apply = function(font, bar) end })
--   ns.Media.Apply(key?)                push to every ticked target (or one)
--   ns.Media.SetTargetOn(key, on) / TargetOn(key) / Targets()
--   ns.Media.PushAuras(onDone)          the bar texture into the aura engine's displays
--
-- A target's apply runs under pcall and never in combat for anything
-- protected; the aura texture push is manual (a button) because it
-- rewrites every display's saved data. The aura engine's texts need no
-- push: their face is ZacUI's font as they are drawn (AE_Regions).

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
    -- the parts with a font setting of their own take it first, so the
    -- re-dress of every text below already reads their new setting
    Media.Apply(nil, true)
    if ns.ApplyFonts then ns.ApplyFonts() end
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

-- the font each target was last handed ("" for none), so a part that was
-- not loaded when the font changed catches up when it next loads (this
-- install's own record: outside the profile, so a profile brought from
-- another PC does not claim its parts were already handed it)
local function Pushed()
    ZacUIDB.fontPushed = ZacUIDB.fontPushed or {}
    return ZacUIDB.fontPushed
end

function Media.SetTargetOn(key, on)
    if on then DB().targets[key] = nil else DB().targets[key] = false end
end

-- Push the current font and texture into one target or every ticked one.
-- Manual targets (the aura push) only go when named. Returns how many
-- targets took it and a list of the ones that failed. The texts kept in
-- ZacUI's font are re-dressed after (a part's own font may have moved),
-- unless `noRedress` (Media.SetFont re-dresses them once itself).
function Media.Apply(onlyKey, noRedress)
    local font, bar = Media.FontName(), Media.BarName()
    local done, failed = 0, {}
    for _, t in ipairs(Media.Targets()) do
        -- An un-ticked target keeps its own texture, but not a face of its
        -- own: every text ZacUI draws wears ZacUI's one font (the parts
        -- force it where they resolve a face), so it is only restyled -
        -- nothing written into its settings. Readycheck (alwaysFont) is a
        -- separate addon with a font setting of its own: it is handed the
        -- font ticked or not, so the two always match.
        local ticked = t.manual or Media.TargetOn(t.key)
        local go = onlyKey and (t.key == onlyKey) or (not onlyKey and not t.manual)
        if go and (not t.available or t.available()) then
            local tFont, tBar = font, bar
            if not ticked then
                tBar = nil
                if not t.alwaysFont then tFont = nil end
            end
            -- ZacUI's font put back to none since this target last took
            -- one: the third argument says so, and the part goes back to
            -- its own face
            local last = Pushed()[t.key]
            local cleared = (ticked or t.alwaysFont) and font == nil and last ~= nil and last ~= "" or false
            local ok, err = pcall(t.apply, tFont, tBar, cleared)
            if ok then
                done = done + 1
                if not t.manual and (ticked or t.alwaysFont) then Pushed()[t.key] = font or "" end
            else
                failed[#failed + 1] = t.label .. " (" .. tostring(err) .. ")"
            end
        end
    end
    if #failed > 0 then Print("media: " .. table.concat(failed, ", ")) end
    if done > 0 and not noRedress and ns.ReapplyHouseFonts then ns.ReapplyHouseFonts() end
    return done, failed
end

-- A PART THAT MISSED A CHANGE. A target only hears a change of font while
-- its part is loaded; one that was off (or not installed yet) when the
-- font was picked would keep its own face until the next change. At login
-- every ticked target whose last-handed font is not today's gets it now.
-- A target seen for the first time is only noted, unless it says it still
-- wears its shipped face (t.untouched): a face set by hand on a part's own
-- page, from before this was kept, is never overwritten.
function Media.CatchUp()
    local font = Media.FontName()
    local pushed = Pushed()
    for _, t in ipairs(Media.Targets()) do
        if not t.manual and (Media.TargetOn(t.key) or t.alwaysFont) and (not t.available or t.available()) then
            local last = pushed[t.key]
            local due
            if last == nil then
                local ok, untouched = pcall(function() return t.untouched and t.untouched() end)
                due = font ~= nil and ok and untouched == true
                if not due then pushed[t.key] = font or "" end
            else
                due = last ~= (font or "")
            end
            if due then Media.Apply(t.key) end
        end
    end
end
do
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        -- after every part has set itself up at login
        C_Timer.After(1, function() pcall(Media.CatchUp) end)
    end)
end

-- A part's own font picker: "ZacUI's font" (the target ticked, today's
-- font handed over now) or a face of its own (the target unticked, so a
-- later change of ZacUI's font leaves the pick alone).
function Media.FollowTarget(key, follow)
    Media.SetTargetOn(key, follow and true or false)
    if follow and Media.FontName() then Media.Apply(key) end
end

-- ============================================================
-- THE CORE'S OWN TARGETS
-- ============================================================
-- Readycheck keeps its own font and texture (its Appearance page); its
-- setters restyle everything it has drawn.
Media.RegisterTarget("readycheck", {
    label = "Readycheck",
    desc = "Readycheck's bar texture. Its font is always ZacUI's, ticked or not, so the two addons match.",
    order = 80,
    -- handed ZacUI's font even un-ticked (the tick is its bar texture)
    alwaysFont = true,
    available = function() return _G.Readycheck ~= nil end,
    -- still on its shipped font
    untouched = function()
        local RC = _G.Readycheck
        local fs = RC and RC.db and RC.db.fontSettings
        return fs ~= nil and (fs.selectedFont == nil or fs.selectedFont == "Friz Quadrata")
    end,
    apply = function(font, bar, cleared)
        local RC = _G.Readycheck
        if font and RC.SetFont then RC:SetFont(font)
        elseif cleared and RC.SetFont then RC:SetFont("Friz Quadrata") end
        if bar and RC.SetTexture then RC:SetTexture(bar) end
    end,
})

-- ============================================================
-- THE AURA ENGINE
-- ============================================================
-- Every bar keeps its own texture in its saved data; the push walks the
-- saved displays, rewrites that field where it differs, and re-adds each
-- changed display so the engine rebuilds it - a handful per frame, so a
-- few hundred auras do not hitch the client. Fonts are not pushed: every
-- text the engine draws wears ZacUI's font already (AE_Regions R.SetFont),
-- and each aura's own face stays in its data, so an export still gives
-- the aura's original font.
local function RetargetDisplay(data, font, bar)
    local changed = false
    if bar and data.regionType == "aurabar" and data.texture ~= bar then
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
    local font, bar = nil, Media.BarName()
    if not bar then return false, "no bar texture chosen" end
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
    desc = "Rewrites the texture of every bar in your auras. A button, not automatic: it edits each aura's saved data. Their texts need nothing: they always use ZacUI's font.",
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
