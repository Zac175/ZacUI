-- AE_Edit - changing the library: rebuild after an edit, new, delete,
-- duplicate, switch on/off, pause, the preview of the display being
-- edited (drag it to move it), and the names other code calls.
-- Part of ZacUI (Zacui_Auras). Written for ZacUI.
local ns = _G.ZacUI
if not ns then return end
local E = ns.AuraEngine
if not E then return end

local WA = E.WA
local Gp, R = E.Groups, E.Regions

-- ============================================================
-- MEDIA PATHS THAT NAME A FOLDER THAT MOVED
-- ============================================================
-- Auras made for WeakAuras name its media folder in their paths
-- (Interface\AddOns\WeakAuras\Media\...). The same files ship in this
-- folder, so the name is corrected wherever a display passes in: when the
-- library is read, and when something is imported. Other moves (a pack's
-- helper addon whose files ZacUI now carries) register through
-- AddFolderMove.
local function ci(s)
    return (s:gsub("%a", function(c) return "[" .. c:lower() .. c:upper() .. "]" end))
end
local function magic(s) return (s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")) end
local moves = {
    { key = "weakauras", from = "WeakAuras", to = E.addon or "Zacui_Auras",
      path = "(" .. ci("Interface") .. "[\\/]+" .. ci("AddOns") .. "[\\/]+)" .. ci("WeakAuras") .. "([\\/])",
      repl = "%1" .. (E.addon or "Zacui_Auras") .. "%2" },
}

function E.AddFolderMove(from, to)
    if type(from) ~= "string" or type(to) ~= "string" or from == "" or to == "" or to:find("[\\/]") then return false end
    local key = from:lower()
    for _, m in ipairs(moves) do if m.key == key then return true end end
    moves[#moves + 1] = { key = key, from = from, to = to,
        path = "(" .. ci("Interface") .. "[\\/]+" .. ci("AddOns") .. "[\\/]+)" .. ci(magic(from)) .. "([\\/])",
        loaded = "(IsAddOnLoaded%s*%(%s*[\"'])" .. magic(from) .. "([\"'])",
        repl = "%1" .. to:gsub("%%", "%%%%") .. "%2" }
    return true
end

-- THE OLD RAID-PACK MEDIA FOLDER (the legacy-path bridge). The raid
-- packs' helper addon "FojjiCore", carried for a while as "Zacui_Fojji",
-- is gone with its media. A display's sound and texture paths into it are
-- answered where they are played or drawn (Core_Sounds: AE_Actions,
-- AE_Regions, and PlaySoundFile in custom code); here, as each display is
-- read, the two things that cannot wait for that are put right:
--   an inline icon |T<old path>:..|t in a text -> the icon that replaced it
--                                                 (or no icon)
--   a check that the helper addon is loaded    -> asks for Zacui_RaidTools,
--                                                 which does that job now
local OLD_HELPERS = { "FojjiCore", "Zacui_Fojji" }
local function FixLegacy(s, low)
    if not low:find("fojji", 1, true) then return s end
    for _, name in ipairs(OLD_HELPERS) do
        s = s:gsub("(IsAddOnLoaded%s*%(%s*[\"'])" .. magic(name) .. "([\"'])", "%1Zacui_RaidTools%2")
    end
    if ns.LegacyTexture then
        s = s:gsub("|T([^:|]+)(:?[^|]*)|t", function(path, rest)
            local v = ns.LegacyTexture(path)
            if v == nil then return nil end
            if not v then return "" end
            return "|T" .. v .. rest .. "|t"
        end)
    end
    return s
end

local function Fix(s)
    -- only a string with a path separator in it can hold a path
    local low = s:lower()
    if low:find("fojji", 1, true) then s = FixLegacy(s, low) low = s:lower() end
    if not (s:find("\\", 1, true) or s:find("/", 1, true)) then return s end
    for _, m in ipairs(moves) do
        if low:find(m.key, 1, true) then
            s = s:gsub(m.path, m.repl)
            if m.loaded then s = s:gsub(m.loaded, m.repl) end
        end
    end
    return s
end
E.FixMediaPath = Fix

local function FixAll(t, seen)
    seen = seen or {}
    if type(t) ~= "table" or seen[t] then return end
    seen[t] = true
    for k, v in pairs(t) do
        if type(v) == "string" then
            local f = Fix(v)
            if f ~= v then t[k] = f end
        elseif type(v) == "table" then
            FixAll(v, seen)
        end
    end
end
E.FixMediaPaths = FixAll

-- the library read at login gets the same pass, and a display saved in
-- an older format version is brought up to today's (AE_Modernize)
local ReadSaved = E.ReadSaved
E.ReadSaved = function()
    ReadSaved()
    for _, d in pairs(E.data) do FixAll(d) end
    if E.Modernize then
        for _, d in pairs(E.data) do
            if (tonumber(d.internalVersion) or 0) < (E.FORMAT_VERSION or 90) then E.Modernize(d) end
        end
    end
end
-- ============================================================
-- SHARING WITH WEAKAURAS
-- ============================================================
-- A string made here imports into WeakAuras, and one made there imports
-- here. What that takes, on the way out:
--   * every display carries a uid (WeakAuras matches updates by it), kept
--     in the library so the next export of it carries the same one;
--   * a group holding groups goes as format 2000 (children keep their
--     parent and their list); otherwise 1421, where the receiver rebuilds
--     the list from the order of the children;
--   * fields that only mean something in this library are left out;
--   * media paths name the folders WeakAuras users have (the reverse of
--     the moves above).
-- And on the way in: a 1421 string's children are put back under the top.
local B64 = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789()"
function E.UID()
    local t = {}
    for i = 1, 11 do
        local n = math.random(1, 64)
        t[i] = B64:sub(n, n)
    end
    return table.concat(t)
end

local function UidTaken(uid, except)
    for id, d in pairs(E.Saved().displays) do
        if type(d) == "table" and d.uid == uid and id ~= except then return true end
    end
    return false
end
function E.EnsureUID(id)
    local d = E.Saved().displays[id]
    if type(d) ~= "table" then return nil end
    if type(d.uid) ~= "string" or d.uid == "" or UidTaken(d.uid, id) then
        local u = E.UID()
        while UidTaken(u, id) do u = E.UID() end
        d.uid = u
    end
    return d.uid
end

local OUT_PATHS = {}
local function Unfix(s)
    if not (s:find("\\", 1, true) or s:find("/", 1, true)) then return s end
    for _, m in ipairs(moves) do
        if m.from and m.to then
            local pat = OUT_PATHS[m.to]
            if not pat then
                pat = "(" .. ci("Interface") .. "[\\/]+" .. ci("AddOns") .. "[\\/]+)" .. ci(magic(m.to)) .. "([\\/])"
                OUT_PATHS[m.to] = pat
            end
            s = s:gsub(pat, "%1" .. m.from:gsub("%%", "%%%%") .. "%2")
        end
    end
    return s
end
local function UnfixAll(t)
    for k, v in pairs(t) do
        if type(v) == "string" then t[k] = Unfix(v)
        elseif type(v) == "table" then UnfixAll(v) end
    end
end
E.ExportPath = Unfix

-- what never travels (as WeakAuras leaves it out)
local LOCAL_ONLY = { "authorMode", "skipWagoUpdate", "ignoreWagoUpdate", "preferToUpdate", "source" }
local function Clean(d, nested)
    local c = E.Copy(d)
    for _, k in ipairs(LOCAL_ONLY) do c[k] = nil end
    if type(c.information) == "table" then c.information.saved = nil end
    if not nested then
        c.controlledChildren = nil
        c.parent = nil
    end
    -- a trigger that is not custom carries no custom code
    for _, tr in ipairs(type(c.triggers) == "table" and c.triggers or {}) do
        local t = type(tr) == "table" and tr.trigger
        if type(t) == "table" and t.type ~= "custom" then
            t.custom, t.customDuration, t.customName, t.customIcon, t.customTexture, t.customStacks = nil, nil, nil, nil, nil, nil
            if type(tr.untrigger) == "table" then tr.untrigger.custom = nil end
        end
    end
    local build = GetBuildInfo and select(4, GetBuildInfo())
    if build then c.tocversion = build end
    UnfixAll(c)
    return c
end

function E.Export(id)
    local d = E.data[id]
    if not d then return nil, "no such display" end
    local kids = E.IsGroup(d) and E.Descendants(id) or {}
    local nested = false
    for _, k in ipairs(kids) do if E.IsGroup(E.data[k]) then nested = true break end end
    E.EnsureUID(id)
    for _, k in ipairs(kids) do E.EnsureUID(k) end
    local top = Clean(E.data[id], nested)
    top.parent = nil
    if nested then
        -- the top's list names only what is really there
        local list = {}
        for _, c in ipairs(E.children[id] or {}) do list[#list + 1] = c end
        top.controlledChildren = list
    end
    local payload = { m = "d", d = top, v = nested and 2000 or 1421, s = E.versionString or "5.19.10" }
    if E.IsGroup(d) then
        payload.c = {}
        for _, k in ipairs(kids) do
            local c = Clean(E.data[k], nested)
            if nested and type(c.controlledChildren) == "table" then
                local list = {}
                for _, x in ipairs(E.children[k] or {}) do list[#list + 1] = x end
                c.controlledChildren = list
            end
            payload.c[#payload.c + 1] = c
        end
        if not nested then top.controlledChildren = nil end
    end
    return E.Codec.Encode(payload)
end

-- a 1421 string: the children's places come from their order
local function Relink(payload)
    if type(payload) ~= "table" or type(payload.d) ~= "table" or type(payload.c) ~= "table" then return end
    if not (tonumber(payload.v) and tonumber(payload.v) < 2000) then return end
    local top = payload.d
    top.controlledChildren = {}
    for _, c in ipairs(payload.c) do
        if type(c) == "table" and c.id then
            table.insert(top.controlledChildren, c.id)
            c.parent = top.id
        end
    end
end

local Install = E.Install
if Install then
    E.Install = function(payload)
        if type(payload) == "table" then
            FixAll(payload)
            Relink(payload)
            -- an older string: brought up to today's format first
            if E.ModernizePayload then E.ModernizePayload(payload) end
        end
        local top = Install(payload)
        -- every display that came in has a uid of its own here
        if top then
            E.EnsureUID(top)
            for _, k in ipairs(E.Descendants(top)) do E.EnsureUID(k) end
        end
        return top
    end
end

-- ============================================================
-- REBUILDING AFTER AN EDIT
-- ============================================================
local function Drop(id)
    if E.loaded[id] then pcall(E.Unbuild, id) end
    local function Gone(r)
        if not r then return end
        r.finishing = nil
        r:Hide()
        r:ClearAllPoints()
    end
    Gone(E.regions[id])
    for _, r in pairs(E.clones[id] or {}) do Gone(r) end
    E.regions[id] = nil
    E.clones[id] = nil
    if E.Env then E.Env.Reset(id) end
    if E.customLogic then E.customLogic[id] = nil end
    if E.errors then E.errors[id] = nil end
end
E.Drop = Drop

local pending, structural = {}, false
local driver = CreateFrame("Frame")
driver:Hide()

local function RebuildNow(id)
    local d = E.data[id]
    if not d then Drop(id) return end
    if E.IsGroup(d) then
        local g = Gp.list[id]
        if g then
            g.d = d
            Gp.Modify(g)
            g.compiled = false
            Gp.Compile(g)
            g.compiled = true
        end
        for _, child in ipairs(E.Descendants(id)) do
            local cd = E.data[child]
            if cd and not E.IsGroup(cd) then
                Drop(child)
            elseif cd then
                local cg = Gp.list[child]
                if cg then cg.d = cd Gp.Modify(cg) end
            end
        end
    else
        Drop(id)
    end
end

driver:SetScript("OnUpdate", function(self)
    self:Hide()
    if structural then
        structural = false
        E.ReadSaved()
    end
    local list = pending
    pending = {}
    for id in pairs(list) do
        local ok, err = pcall(RebuildNow, id)
        if not ok then E.Error(id, "rebuild", err) end
    end
    if not E.paused then E.CheckLoads() end
    if E.previewId then E.ShowPreview(E.previewId) end
end)

-- once a frame at most, however many fields a drag changes
function E.Rebuild(id, isStructural)
    if id then pending[id] = true end
    if isStructural then structural = true end
    driver:Show()
end

-- ============================================================
-- THE LIBRARY: NEW, DELETE, DUPLICATE, ON / OFF
-- ============================================================
local function FreeId(want)
    local sv = E.Saved().displays
    if sv[want] == nil then return want end
    local n = 2
    while sv[want .. " " .. n] ~= nil do n = n + 1 end
    return want .. " " .. n
end
E.FreeId = FreeId

local TEMPLATES = {
    icon = { width = 48, height = 48, zoom = 0.1, cooldown = true, iconSource = -1,
        subRegions = { { type = "subbackground" },
            { type = "subtext", text_text = "%s", anchor_point = "INNER_BOTTOMRIGHT", text_visible = true,
              text_fontSize = 12, text_fontType = "OUTLINE", text_color = { 1, 1, 1, 1 }, text_justify = "CENTER", text_selfPoint = "AUTO" } } },
    aurabar = { width = 200, height = 18, icon = true, icon_side = "LEFT", barColor = { 1, 0.4, 0, 1 },
        backgroundColor = { 0, 0, 0, 0.5 }, orientation = "HORIZONTAL", texture = "Blizzard",
        subRegions = { { type = "subbackground" }, { type = "subforeground" },
            { type = "subtext", text_text = "%n", anchor_point = "INNER_LEFT", text_visible = true, text_fontSize = 12,
              text_fontType = "OUTLINE", text_color = { 1, 1, 1, 1 }, text_justify = "LEFT", text_selfPoint = "AUTO" },
            { type = "subtext", text_text = "%p", anchor_point = "INNER_RIGHT", text_visible = true, text_fontSize = 12,
              text_fontType = "OUTLINE", text_color = { 1, 1, 1, 1 }, text_justify = "RIGHT", text_selfPoint = "AUTO" } } },
    text = { displayText = "%p", fontSize = 14, outline = "OUTLINE", color = { 1, 1, 1, 1 }, justify = "CENTER",
        automaticWidth = "Auto", subRegions = {} },
    group = { controlledChildren = {} },
    dynamicgroup = { controlledChildren = {}, grow = "DOWN", align = "CENTER", space = 2, sort = "none" },
}
-- the other display types start from the format's own defaults
for _, kind in ipairs({ "texture", "progresstexture", "stopmotion", "model", "empty" }) do
    local def = R and R.defaults and R.defaults[kind]
    if def then
        local t = E.Copy(def)
        t.subRegions = { { type = "subbackground" } }
        TEMPLATES[kind] = t
    end
end
-- a dynamic group's point follows its grow direction (down, centred: TOP)
TEMPLATES.dynamicgroup.selfPoint = "TOP"

function E.New(regionType, parentId, name)
    local t = TEMPLATES[regionType] or TEMPLATES.icon
    local id = FreeId(name or ("New " .. (regionType == "aurabar" and "bar" or regionType)))
    local d = E.Copy(t)
    d.id, d.regionType = id, regionType
    d.alpha, d.anchorPoint, d.xOffset, d.yOffset = 1, "CENTER", 0, 0
    d.selfPoint = t.selfPoint or "CENTER"
    -- a text display has no opacity field in the format
    if regionType == "text" then d.alpha = nil end
    d.anchorFrameType, d.frameStrata = "SCREEN", 1
    d.load = {}
    d.conditions, d.config, d.authorOptions = {}, {}, {}
    d.actions = { init = {}, start = {}, finish = {} }
    d.animation = { start = { type = "none" }, main = { type = "none" }, finish = { type = "none" } }
    if not E.IsGroup(d) then
        d.triggers = { { trigger = { type = "aura2", unit = "player", debuffType = "HELPFUL" }, untrigger = {} },
            disjunctive = "any", activeTriggerMode = -10 }
    end
    d.internalVersion = 90
    d.uid = E.UID()
    local sv = E.Saved().displays
    sv[id] = d
    if parentId and sv[parentId] and E.IsGroup(sv[parentId]) then
        d.parent = parentId
        table.insert(sv[parentId].controlledChildren, id)
    end
    E.Rebuild(id, true)
    return id
end

-- removes a display (and, for a group, everything in it)
function E.Delete(id)
    local sv = E.Saved().displays
    local d = sv[id]
    if not d then return false end
    local all = E.Descendants(id)
    all[#all + 1] = id
    for _, x in ipairs(all) do Drop(x) end
    for _, x in ipairs(all) do sv[x] = nil end
    if d.parent and sv[d.parent] and type(sv[d.parent].controlledChildren) == "table" then
        local kids = sv[d.parent].controlledChildren
        for i = #kids, 1, -1 do if kids[i] == id then table.remove(kids, i) end end
    end
    if Gp.list[id] then
        Gp.list[id].frame:Hide()
        Gp.list[id] = nil
    end
    if E.previewId == id then E.SetPreview(nil) end
    E.Rebuild(nil, true)
    return true
end

-- a copy under a new name, beside the original
function E.Duplicate(id)
    local d = E.data[id]
    if not d then return nil end
    local payload = { d = E.Copy(d), c = {} }
    payload.d.parent = nil
    if E.IsGroup(d) then
        for _, child in ipairs(E.Descendants(id)) do payload.c[#payload.c + 1] = E.Copy(E.data[child]) end
    end
    local newId = E.Install(payload)
    if newId and d.parent and E.data[d.parent] then
        local sv = E.Saved().displays
        sv[newId].parent = d.parent
        table.insert(sv[d.parent].controlledChildren, newId)
        E.Rebuild(newId, true)
    end
    return newId
end

-- off = load never on every display it holds
function E.IsOff(id)
    local d = E.data[id]
    if not d then return true end
    if not E.IsGroup(d) then return d.load and d.load.use_never and true or false end
    local any = false
    for _, c in ipairs(E.Descendants(id)) do
        local cd = E.data[c]
        if cd and not E.IsGroup(cd) then
            any = true
            if not (cd.load and cd.load.use_never) then return false end
        end
    end
    return any
end

function E.SetEnabled(id, on)
    local list = E.Descendants(id)
    list[#list + 1] = id
    for _, x in ipairs(list) do
        local d = E.data[x]
        if d and not E.IsGroup(d) then
            d.load = type(d.load) == "table" and d.load or {}
            d.load.use_never = (not on) or nil
            E.Rebuild(x)
        end
    end
end

-- loaded now? (a group: anything inside it)
function E.IsLoaded(id)
    local d = E.data[id]
    if not d then return false end
    if not E.IsGroup(d) then return E.loaded[id] and true or false end
    for _, c in ipairs(E.Descendants(id)) do if E.loaded[c] then return true end end
    return false
end

-- ============================================================
-- PAUSE (everything off until resumed)
-- ============================================================
function E.SetPaused(on)
    E.paused = on and true or false
    if E.paused then
        for id in pairs(E.loaded) do pcall(E.Unbuild, id) end
    else
        E.CheckLoads()
    end
end

local CheckLoads = E.CheckLoads
E.CheckLoads = function()
    if E.paused then return end
    return CheckLoads()
end

-- ============================================================
-- THE PREVIEW: the display being edited, on screen and draggable
-- ============================================================
local function Sample(d)
    local now = GetTime()
    return { show = true, changed = true, progressType = "timed", duration = 30, expirationTime = now + 20,
        name = d.id, icon = d.displayIcon or 136243, stacks = 3, value = 60, total = 100, unit = "player",
        autoHide = false, preview = true }
end

local function Draggable(r, d)
    if r.dragReady then return end
    r.dragReady = true
    r:SetMovable(true)
    r:RegisterForDrag("LeftButton")
    r:SetScript("OnDragStart", function(self)
        if not self.previewing then return end
        self:StartMoving()
    end)
    r:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local dd = E.data[self.id]
        if not dd then return end
        local x, y = self:GetCenter()
        local s = self:GetEffectiveScale()
        local parent = self.groupFrame or UIParent
        local px, py = parent:GetCenter()
        local ps = parent:GetEffectiveScale()
        if not (x and px) then return end
        dd.selfPoint, dd.anchorPoint = "CENTER", "CENTER"
        if not self.groupFrame then dd.anchorFrameType = "SCREEN" end
        dd.xOffset = math.floor((x * s - px * ps) / ps + 0.5)
        dd.yOffset = math.floor((y * s - py * ps) / ps + 0.5)
        E.Rebuild(self.id)
        if ns.RefreshConfig then ns.RefreshConfig() end
    end)
end

function E.ShowPreview(id)
    local d = E.data[id]
    if not d or E.IsGroup(d) then return end
    local r = E.RegionFor(id, "")
    if not r then return end
    if r:IsShown() and not r.previewing then return end     -- the real thing is up
    r.previewing = true
    r.ctx = { state = Sample(d), triggers = { Sample(d) } }
    R.Apply(r, r.ctx.state)
    if not (r.group and r.group.dynamic) then R.Place(r, d, r.ctx.state) end
    r:Show()
    r.showing = true
    if r.group and r.group.dynamic then Gp.Changed(r) end
    r:EnableMouse(not (r.group and r.group.dynamic))
    Draggable(r, d)
end

function E.SetPreview(id)
    local old = E.previewId
    if old and old ~= id then
        local r = E.regions[old]
        if r and r.previewing then
            r.previewing = nil
            r:EnableMouse(false)
            r.showing = nil
            r:Hide()
            if r.group and r.group.dynamic then Gp.Changed(r) end
            E.Changed(old)
        end
    end
    E.previewId = id
    if id then E.ShowPreview(id) end
end

-- the real states take over from a preview the moment they arrive
local Changed = E.Changed
E.Changed = function(id)
    local r = E.regions[id]
    if r and r.previewing then
        r.previewing = nil
        r:EnableMouse(false)
        r.showing = nil
        r:Hide()
    end
    Changed(id)
    if E.previewId == id and not (E.regions[id] and E.regions[id]:IsShown()) then E.ShowPreview(id) end
end

-- ============================================================
-- THE NAMES OTHER CODE CALLS
-- ============================================================
WA.Add = function(data)
    if type(data) ~= "table" or not data.id then return end
    local sv = E.Saved().displays
    sv[data.id] = data
    E.Rebuild(data.id, true)
end
WA.Delete = function(data)
    local id = type(data) == "table" and data.id or data
    if id then E.Delete(id) end
end
WA.Import = function(str) return E.Import(str) end
WA.GetRegion = function(id, cloneId)
    if cloneId and cloneId ~= "" then return E.clones[id] and E.clones[id][cloneId] end
    return E.regions[id]
end
WA.IsAuraLoaded = function(id) return E.IsLoaded(id) end
WA.IsPaused = function() return E.paused and true or false end
WA.Toggle = function() E.SetPaused(not E.paused) end
WA.InternalVersion = function() return 90 end
WA.GetNameAndIcon = function(data)
    local d = type(data) == "table" and data or E.data[data]
    if not d then return nil, nil end
    local icon = d.displayIcon
    if not icon and type(d.triggers) == "table" and d.triggers[1] and d.triggers[1].trigger then
        local tr = d.triggers[1].trigger
        local name = (type(tr.auranames) == "table" and tr.auranames[1]) or tr.spellName or tr.itemName
        if name then
            local ok, t = pcall(GetSpellTexture, tonumber(name) or name)
            if ok and t then icon = t end
            if not icon and GetItemIcon then
                local ok2, t2 = pcall(GetItemIcon, tonumber(name) or name)
                if ok2 and t2 then icon = t2 end
            end
        end
    end
    return d.id, icon
end
WA.OpenOptions = function(id)
    if id then E.selectRequest = id end
    if ns.OpenConfig then ns.OpenConfig("auras") end
end
WA.ShowOptions = WA.OpenOptions

-- ZacUI's own pages look for this table to know the engine is ZacUI's
WA.ZacUI = type(WA.ZacUI) == "table" and WA.ZacUI or {}
local Z = WA.ZacUI
Z.addonName = E.addon
Z.engine = "zacui"
Z.AddFolderMove = E.AddFolderMove
Z.FixMediaPath = Fix
Z.FixMediaPaths = function(data) FixAll(data) end
-- the raid packs ZacUI now runs as Raid mods; copies in the library were
-- switched off once by the earlier engine (zuiRetired in the saved data)
Z.RetiredPacks = function()
    return { "Fojji - Blackwing Lair Pack [Classic]", "Fojji - Molten Core Pack [Classic]",
        "Fojji - Naxxramas Pack [Classic]", "Fojji - Temple of Ahn'Qiraj Pack [Classic]",
        "Fojji - Zul'Gurub Pack [Classic]", "Fojji - Pull & Break Timers", "Fojji - Raid Pack Anchors [Classic]" }
end

-- /wa and /weakauras open the editor (packs and players type them)
if type(SlashCmdList) == "table" and not SlashCmdList.WEAKAURAS then
    SLASH_WEAKAURAS1, SLASH_WEAKAURAS2 = "/wa", "/weakauras"
    SlashCmdList.WEAKAURAS = function(msg)
        msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        if msg == "pause" or msg == "stop" then E.SetPaused(true) return end
        if msg == "resume" or msg == "unpause" then E.SetPaused(false) return end
        WA.OpenOptions()
    end
end
