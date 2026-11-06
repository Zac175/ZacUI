-- AB_Import - reads a Bartender4 saved-variables table into ZacUI bar
-- profiles, and the module entry point that decides who runs.
-- Part of ZacUI; load order is set by the TOC.
--
-- Bartender4DB is an AceDB store: only values that differ from
-- Bartender's defaults are written, so every missing key below means
-- "Bartender's default", and those defaults are spelled out here as
-- data. The translation is one-way and one-time; it runs while
-- Bartender4 is still loaded (its saved variables only exist in memory
-- then), writes every profile it finds, remembers which character wore
-- which, and then offers to turn Bartender4 off.
--
-- Keys are a separate, per-character step (AB.MigrateBartenderKeys): a
-- character's keys live in the client's binding cache, which outlives
-- the addon, so they are moved the first time each character logs in
-- with ZacUI's bars on.

local ADDON_NAME = ...
-- Zacui_Bars is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

-- shared state from earlier ZacUI files
local AB = ns.Bars
local Modules = ns.Modules
local Print = ns.Print
local UI = ns.UI
local ZUI = ns.ZUI

-- Bartender's own stance vocabulary -> bonusbar index on Classic Era.
local BT_STANCE_INDEX = {
    WARRIOR = { battle = 1, def = 2, berserker = 3 },
    DRUID   = { cat = 1, bear = 3, moonkin = 4, prowl = "prowl" },
    ROGUE   = { stealth = 1 },
}

local function Num(v, default) if type(v) == "number" then return v end return default end
local function Bool(v, default) if v == nil then return default end return v and true or false end

local function ImportPosition(dst, pos)
    pos = pos or {}
    dst.scale = Num(pos.scale, 1)
    dst.growH = pos.growHorizontal or "RIGHT"
    dst.growV = pos.growVertical or "DOWN"
    if pos.x ~= nil and pos.y ~= nil and pos.point then
        dst.point, dst.x, dst.y = pos.point, pos.x, pos.y
    end
end

local function ImportVisibility(dst, vis)
    vis = vis or {}
    dst.visibility = dst.visibility or {}
    local v = dst.visibility
    v.always   = Bool(vis.always, false)
    v.combat   = Bool(vis.combat, false)
    v.nocombat = Bool(vis.nocombat, false)
    v.pet      = Bool(vis.pet, false)
    v.nopet    = Bool(vis.nopet, false)
    v.mounted  = Bool(vis.mounted, false)
    v.stance   = {}
    for id, on in pairs(vis.stance or {}) do if on then v.stance[id] = true end end
    v.custom     = Bool(vis.custom, false)
    v.customdata = vis.customdata or ""
end

local function ImportCommon(dst, cfg)
    cfg = cfg or {}
    dst.alpha      = Num(cfg.alpha, 1)
    dst.fade       = Bool(cfg.fadeout, false)
    dst.fadeAlpha  = Num(cfg.fadeoutalpha, 0.1)
    dst.fadeDelay  = Num(cfg.fadeoutdelay, 0.2)
    dst.clickthrough = Bool(cfg.clickthrough, false)
    dst.padding    = Num(cfg.padding, dst.padding or 2)
    dst.rows       = Num(cfg.rows, 1)
    dst.hideHotkey = Bool(cfg.hidehotkey, dst.hideHotkey or false)
    dst.showgrid   = Bool(cfg.showgrid, false)
    ImportPosition(dst, cfg.position)
    ImportVisibility(dst, cfg.visibility)
end

local function ImportFonts(dst, elements)
    elements = elements or {}
    local fonts = dst.fonts
    for _, key in ipairs({ "hotkey", "count", "macro" }) do
        local src, el = elements[key], fonts[key]
        if src and el then
            if src.font and src.font ~= "" then el.font = src.font end
            if src.fontSize then el.size = src.fontSize end
            if src.fontFlags then el.flags = src.fontFlags end
            if type(src.fontColor) == "table" then
                el.color = { src.fontColor[1] or src.fontColor.r or 1,
                             src.fontColor[2] or src.fontColor.g or 1,
                             src.fontColor[3] or src.fontColor.b or 1 }
            end
            if src.textAnchor then el.anchor = src.textAnchor end
            if src.textOffsetX then el.x = src.textOffsetX end
            if src.textOffsetY then el.y = src.textOffsetY end
            if src.textJustifyH then el.justify = src.textJustifyH end
        end
    end
end

local function ImportActionBar(n, cfg)
    local dst = AB.DefaultBar(n)
    cfg = cfg or {}
    dst.enabled = Bool(cfg.enabled, n <= 6)
    dst.buttons = math.min(12, Num(cfg.buttons, 12))
    dst.offset  = Num(cfg.buttonOffset, 0)
    dst.hideMacro = Bool(cfg.hidemacrotext, false)
    ImportCommon(dst, cfg)
    ImportFonts(dst, cfg.elements)
    -- paging: Bartender's states table, same meaning
    local st = cfg.states or {}
    local p = dst.paging
    p.enabled   = Bool(st.enabled, n == 1)
    p.actionbar = Bool(st.actionbar, false)
    p.ctrl, p.alt, p.shift = Num(st.ctrl, 0), Num(st.alt, 0), Num(st.shift, 0)
    p.default   = Num(st.default, 0)
    p.customEnabled = Bool(st.customEnabled, false)
    p.custom    = type(st.custom) == "string" and st.custom or ""
    if type(st.stance) == "table" then
        for class, map in pairs(st.stance) do
            if type(map) == "table" and BT_STANCE_INDEX[class] then
                p.stance[class] = p.stance[class] or {}
                for stanceName, page in pairs(map) do
                    local idx = BT_STANCE_INDEX[class][stanceName]
                    if idx and type(page) == "number" then p.stance[class][idx] = page end
                end
            end
        end
    end
    return dst
end

-- One Bartender profile name -> one ZacUI profile table.
local function ImportProfile(db, name)
    local p = AB.DefaultProfile()
    local ns_ = db.namespaces or {}
    local function Prof(nsName)
        local t = ns_[nsName]
        return t and t.profiles and t.profiles[name] or nil
    end
    local ab = Prof("ActionBars")
    local bars = ab and ab.actionbars or {}
    for n = 1, AB.NUM_BARS do p.bars[n] = ImportActionBar(n, bars[n]) end

    local petc = Prof("PetBar")
    if petc then
        p.pet.enabled = Bool(petc.enabled, true)
        p.pet.hideHotkey = true
        ImportCommon(p.pet, petc)
        p.pet.hideHotkey = Bool(petc.hidehotkey, true)
        if not (petc.visibility and petc.visibility.nopet == false) then p.pet.visibility.nopet = true end
    end
    local stc = Prof("StanceBar")
    if stc then
        p.stance.enabled = Bool(stc.enabled, true)
        p.stance.scale = 1.5
        ImportCommon(p.stance, stc)
        p.stance.scale = Num(stc.position and stc.position.scale, 1.5)
        p.stance.hideHotkey = Bool(stc.hidehotkey, true)
    end
    local bag = Prof("BagBar")
    if bag then
        p.bagbar.enabled = Bool(bag.enabled, true)
        p.bagbar.keyring = Bool(bag.keyring, true)
        p.bagbar.onebag  = Bool(bag.onebag, false)
        p.bagbar.valign  = bag.verticalAlignment or "BOTTOM"
        ImportCommon(p.bagbar, bag)
    end
    local mm = Prof("MicroMenu")
    if mm then
        p.micro.enabled = Bool(mm.enabled, true)
        p.micro.vertical = Bool(mm.vertical, false)
        p.micro.padding = -3
        ImportCommon(p.micro, mm)
        p.micro.padding = Num(mm.padding, -3)
        p.micro.scale = Num(mm.position and mm.position.scale, 0.8)
    end
    local stb = Prof("StatusTrackingBar")
    if stb then
        p.status.enabled = Bool(stb.enabled, false)
        p.status.width = Num(stb.width, 1024)
        ImportCommon(p.status, stb)
    else
        local xp = Prof("XPBar")
        if xp and xp.enabled then
            p.status.enabled = true
            ImportCommon(p.status, xp)
        end
    end
    local core = db.profiles and db.profiles[name] or {}
    p.core.outofrange = core.outofrange or "button"
    p.core.buttonlock = Bool(core.buttonlock, true)
    p.core.tooltip    = core.tooltip or "enabled"
    p.core.selfcast   = Bool(core.selfcastmodifier, true)
    p.core.focuscast  = Bool(core.focuscastmodifier, true)
    p.core.rightclickself = Bool(core.selfcastrightclick, false)
    if type(core.colors) == "table" then
        local r, m = core.colors.range, core.colors.mana
        if type(r) == "table" then p.core.rangeColor = { r.r or 0.8, r.g or 0.1, r.b or 0.1 } end
        if type(m) == "table" then p.core.manaColor = { m.r or 0.5, m.g or 0.5, m.b or 1 } end
    end
    return p
end

-- Everything Bartender4DB holds: every profile, and the character map.
-- Returns how many profiles came across.
function AB.ImportBartender(db)
    db = db or _G.Bartender4DB
    if type(db) ~= "table" then return nil, "Bartender4's saved variables are not loaded (is Bartender4 enabled?)" end
    local store = AB.DB()
    local names, seen = {}, {}
    local function Note(name) if name and not seen[name] then seen[name] = true names[#names + 1] = name end end
    for _, name in pairs(db.profileKeys or {}) do Note(name) end
    for name in pairs(db.profiles or {}) do Note(name) end
    for _, nsTable in pairs(db.namespaces or {}) do
        for name in pairs(nsTable.profiles or {}) do Note(name) end
    end
    local count = 0
    for _, name in ipairs(names) do
        store.profiles[name] = ImportProfile(db, name)
        count = count + 1
    end
    for charKey, pname in pairs(db.profileKeys or {}) do
        if store.profiles[pname] then store.charProfile[charKey] = pname end
    end
    -- a character with no Bartender profile key wore a profile named
    -- after itself; the ZacUI side falls back the same way
    local mine = AB.CharKey()
    if not store.charProfile[mine] and store.profiles[mine] then store.charProfile[mine] = mine end
    if ZacUICharDB and store.charProfile[mine] then ZacUICharDB.barsProfile = store.charProfile[mine] end
    if not store.profiles[store.defaultProfile or ""] then
        store.defaultProfile = store.charProfile[mine] or names[1] or "Default"
    end
    store.importedBT4 = time()
    return count
end

-- ============================================================
-- MODULE ENTRY
-- ============================================================
local function DisableBartender()
    local disable = (C_AddOns and C_AddOns.DisableAddOn) or DisableAddOn
    if disable then pcall(disable, "Bartender4") end
    ReloadUI()
end

local function OfferBartenderHandoff(count)
    if not (UI and UI.Confirm) then
        Print("Bartender4 settings imported (" .. count .. " profiles). Disable Bartender4 and /reload to use ZacUI's bars.")
        return
    end
    UI.Confirm({
        title = "Bartender4 imported",
        text = count .. " Bartender4 profile" .. (count == 1 and "" or "s") .. " copied into ZacUI's "
            .. "action bars, with each character's choice. ZacUI's bars take over once Bartender4 "
            .. "is off. Turn Bartender4 off and reload now?",
        acceptText = "Turn off + reload",
        onAccept = DisableBartender,
    })
end

-- The "bars" module. Runs at PLAYER_LOGIN from the apply pass.
Modules.bars = function()
    if AB.BartenderLoaded() then
        local store = AB.DB()
        if not store.importedBT4 then
            local count, err = AB.ImportBartender()
            if count then
                OfferBartenderHandoff(count)
            elseif err then
                Print("Bartender4 import: " .. err)
            end
        else
            Print("Bartender4 is still enabled - ZacUI's action bars are standing down. Disable it to switch.")
        end
        return
    end
    if AB.active then return end
    AB.active = true
    AB.HideBlizzard()
    AB.ApplyAll()
    AB.MigrateBartenderKeys()
    -- and once more a moment after the world appears: character-specific
    -- bindings can arrive from the server after PLAYER_LOGIN
    local late = CreateFrame("Frame")
    late:RegisterEvent("PLAYER_ENTERING_WORLD")
    late:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        C_Timer.After(2, function() AB.MigrateBartenderKeys() end)
    end)
    if ns.WatchEditMode then
        ns.WatchEditMode(function(on) AB.SetUnlocked(on) end)
    end
    -- Blizzard's lock cvar changes under the hood when the player toggles
    -- it in Interface options: keep the profile honest
    hooksecurefunc("SetCVar", function(cvar, value)
        if cvar == "lockActionBars" and AB.active then
            local p = AB.Profile()
            p.core.buttonlock = (value == "1" or value == 1 or value == true)
        end
    end)
end
