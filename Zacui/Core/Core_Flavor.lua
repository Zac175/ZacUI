-- Core_Flavor - which game this is: Classic Era, TBC Anniversary or WoW
-- Forever, and what ZacUI switches off on each.
-- Part of ZacUI; load order is set by the TOC (right after Core_Boot, so
-- every later file and every part can ask).
-- ============================================================
--   ns.Flavor()             "era" | "tbc" | "forever"
--   ns.FlavorSimulated()    true while the developer override runs ZacUI
--                           as another game than this client
--   ns.FEATURE_FLAVORS      every part and every notable feature inside
--                           one, with the games it runs on and the plain
--                           reason where it does not (or runs changed)
--   ns.FeatureOn(id)        ask before registering events, tickers or
--                           frames; true for any id not in the table
--   ns.PartOff(addon)       a whole part that does not run here
--   ns.NoCombatLog()        Forever's rules for the combat log (the real
--                           client, or the override)
--   ns.AddonMessagesBlocked()  Forever, inside an instance
--   ns.IsSecret / ns.SafeHealth / ns.AuraHidden
--                           Forever's secret values, read safely
--
-- WHERE THE ANSWER COMES FROM. WOW_PROJECT_ID (2 Classic Era, 5 TBC
-- Anniversary, 18 WoW Forever), then the interface number for a client
-- that reports something else. The same answer, in the same words, as
-- Readycheck's RC:Flavor() (Readycheck\Core\Core_Flavor.lua).
--
-- THE DEVELOPER OVERRIDE. ZacUIDB.dev.flavor (nil = this client, or a
-- flavor), set from General > Game versions or /zacui flavor, is read
-- once per session, so a change lands after /reload. With it, ZacUI
-- switches features off exactly as it would on that client. It never
-- fakes an API: a real Forever client still has no combat log however
-- the override is set, and an Era client keeps every API it has.
--
-- The flavor is fixed the first time it is read after the saved
-- variables exist (Boot_Events makes ZacUIDB at our ADDON_LOADED; every
-- part loads after that, so they all see the same answer). Read before
-- that, it is the real client's flavor and nothing is fixed yet.
-- ============================================================

local ADDON_NAME, ns = ...

local ipairs, pairs, type, select, tostring = ipairs, pairs, type, select, tostring

local VALID = { era = true, tbc = true, forever = true }
local ORDER = { "era", "tbc", "forever" }
local NAMES = { era = "Classic Era", tbc = "TBC", forever = "Forever" }
ns.FLAVORS = ORDER
ns.FLAVOR_NAMES = NAMES

function ns.DetectFlavor()
    local pid = WOW_PROJECT_ID
    if pid == 2 then return "era" end
    if pid == 5 then return "tbc" end
    if pid == 18 then return "forever" end
    local build = (GetBuildInfo and select(4, GetBuildInfo())) or 0
    if type(build) ~= "number" then build = tonumber(build) or 0 end
    if build >= 16000 and build < 20000 then return "forever" end
    if build >= 20000 and build < 30000 then return "tbc" end
    return "era"
end

-- the saved override, and whether the saved variables were there to read
local function ReadOverride()
    if type(ZacUIDB) ~= "table" then return nil, false end
    local dev = ZacUIDB.dev
    local v = type(dev) == "table" and dev.flavor or nil
    if VALID[v] then return v, true end
    return nil, true
end

local latched, simulated, realFlavor

function ns.Flavor()
    if latched then return latched end
    local real = ns.DetectFlavor()
    local ov, ready = ReadOverride()
    if not ready then return real end
    realFlavor = real
    if ov and ov ~= real then
        latched, simulated = ov, true
    else
        latched, simulated = real, false
    end
    return latched
end

function ns.RealFlavor() return realFlavor or ns.DetectFlavor() end

function ns.FlavorSimulated()
    ns.Flavor()
    return simulated and true or false
end

function ns.FlavorName(flavor)
    flavor = flavor or ns.Flavor()
    return NAMES[flavor] or tostring(flavor)
end

-- what /reload will bring: the saved choice, or the real client on auto
function ns.PendingFlavor()
    local ov = ReadOverride()
    return ov or ns.RealFlavor()
end

-- the saved choice: "auto" (none), "era", "tbc" or "forever"
function ns.FlavorOverride()
    local ov = ReadOverride()
    return ov or "auto"
end

-- value: "auto", "era", "tbc" or "forever". True when it changes what the
-- next /reload runs as.
function ns.SetFlavorOverride(value)
    if value ~= "auto" and not VALID[value] then return false end
    if type(ZacUIDB) ~= "table" then return false end
    if type(ZacUIDB.dev) ~= "table" then ZacUIDB.dev = {} end
    ZacUIDB.dev.flavor = (value ~= "auto") and value or nil
    if next(ZacUIDB.dev) == nil then ZacUIDB.dev = nil end
    return ns.PendingFlavor() ~= ns.Flavor()
end

-- ============================================================
-- THE FEATURE TABLE
-- ============================================================
-- One row per part and per notable feature inside a part, in the order
-- the settings menu shows them.
--   part     the addon folder the code lives in ("Zacui" = this one)
--   off      [flavor] = the plain reason it does not run there
--   changed  [flavor] = what is different there (it still runs)
--   whole    true: the whole part stands down (ns.PartOff)
--   pages    menu ids whose page shows the reason instead of the page
--   notes    menu ids whose page keeps working and says it at the top
-- Anything not listed runs everywhere; on Classic Era everything is on.
local ERA       = "Classic Era content"
local ERA_RAIDS = "Classic Era raids"
local CLOG      = "needs the combat log, which Forever does not give addons"
local MSG       = "Forever blocks addon messages inside instances; sync waits until you leave"
local SECRET    = "Forever hides enemy health, casts and auras from addons in combat"
local ERA_ONLY  = { tbc = ERA, forever = ERA }

ns.FEATURE_FLAVORS = {
    -- ZacUI itself
    { id = "skins", part = "Zacui", name = "The skin: every game window and the dialogs in ZacUI's look" },
    { id = "minimap", part = "Zacui", name = "Minimap: zone, clock, coordinates, icons and the button tray" },
    { id = "chat", part = "Zacui", name = "Chat, the chat bar and the raid chat strip" },
    { id = "raid_clear_timer", part = "Zacui", name = "Raid clear timer and splits on the raid chat strip",
      changed = { tbc = "only Classic Era raids have a last boss that ends a run; other raids end after four hours without a kill",
                  forever = "only Classic Era raids have a last boss that ends a run; other raids end after four hours without a kill" } },
    { id = "tooltips", part = "Zacui", name = "Tooltips",
      changed = { forever = "enemy health numbers stay blank in combat (" .. SECRET .. ")" } },
    { id = "buffs", part = "Zacui", name = "Your buffs and debuffs" },
    { id = "lootroll", part = "Zacui", name = "Loot rolls" },
    { id = "settings", part = "Zacui", name = "Settings window, appearance, profiles, import, movers and Edit Mode" },
    { id = "voice", part = "Zacui", name = "ZacUI's voice (the game's text to speech)" },
    { id = "tutorial", part = "Zacui", name = "First-run welcome, quick setup and the tour" },

    -- the parts
    { id = "bars", part = "Zacui_Bars", name = "Action bars and bar loadouts" },
    { id = "unitframes", part = "Zacui_UnitFrames", name = "Unit frames (player, target, party, raid)",
      changed = { forever = "enemy health and auras stay blank in combat (" .. SECRET .. ")" } },
    { id = "uf_heals", part = "Zacui_UnitFrames", name = "Incoming heals on the unit frames",
      changed = { forever = "other healers' heals are read from the combat log and addon messages, which Forever does not give addons; your own still show" } },
    { id = "uf_dispel", part = "Zacui_UnitFrames", name = "Dispel glow on the unit frames", note = "dispelGlow",
      changed = { forever = "goes quiet in combat: Forever hides other players' aura details from addons then" } },
    { id = "uf_taunt", part = "Zacui_UnitFrames", name = "AoE taunt glow, countdown and voice", note = "tauntGlow",
      changed = { forever = "seen from the cast event instead of the combat log; when the game hides the spell nothing shows" } },
    { id = "nameplates", part = "Zacui_Nameplates", name = "Nameplates (health, casts, threat, target arrows, soft target)",
      changed = { forever = "health numbers, cast bars and debuffs on enemies go blank in combat (" .. SECRET .. ")" } },
    { id = "np_debuffs", part = "Zacui_Nameplates", name = "Nameplate debuffs, Sunder count and execute cue",
      changed = { forever = "blank in combat (" .. SECRET .. ")" } },
    { id = "dodge_window", part = "Zacui_Nameplates", name = "Overpower window after a dodge, and the crosshair's miss marks",
      off = { forever = CLOG }, notes = { "warrior" } },
    { id = "raidmods", part = "Zacui_RaidMods", whole = true,
      name = "Raid mods: Molten Core, Blackwing Lair, Zul'Gurub, AQ40 and Naxxramas",
      off = { tbc = ERA_RAIDS, forever = ERA_RAIDS }, pages = { "raidmods" } },
    { id = "raidtools", part = "Zacui_RaidTools", name = "/pull, /break, /range, raid sync and speech settings",
      changed = { forever = MSG } },
    { id = "auras", part = "Zacui_Auras", name = "Aura engine",
      changed = { forever = "combat-log triggers never fire, auras and health read as hidden in combat, and sharing waits outside instances" } },
    { id = "sbt", part = "Zacui_SBT", name = "Scrolling combat text",
      changed = { forever = "only hits and heals you take show (the game's own combat text); the combat log Forever does not give addons carries the rest" } },
    { id = "sbt_plates", part = "Zacui_SBT", name = "Your damage on enemy nameplates (scrolling text)",
      off = { forever = CLOG }, notes = { "sbt" } },
    { id = "meter_parser", part = "Zacui_Meter", name = "Damage meter: damage, healing, deaths, interrupts",
      off = { forever = CLOG }, notes = { "meter" } },
    { id = "meter_threat", part = "Zacui_Meter", name = "Threat meter, threat glow and pull warning" },
    { id = "raid_summary", part = "Zacui_Meter", name = "Raid summary after the last boss",
      off = { forever = CLOG },
      changed = { tbc = "only Classic Era raids have a last boss that opens it; /zacui raid opens it any time" } },
    { id = "meter_dmf", part = "Zacui_Meter", name = "Darkmoon Faire mark after names on the meter",
      off = ERA_ONLY, notes = { "meter" } },
    { id = "clicks", part = "Zacui_Clicks", name = "Click casting" },
    { id = "blessings", part = "Zacui_Blessings", name = "Blessings: casting bar and assignments",
      changed = { forever = "assignments shared with other paladins: " .. MSG } },
    { id = "buffrem", part = "Zacui_BuffReminders", name = "Buff reminders and the buff tracker" },
    { id = "consbars", part = "Zacui_Consumables", name = "Consumables, potion and weapon bars",
      changed = { tbc = "the bars follow TBC's own consumables: one battle and one guardian elixir or a flask, and poisons have no charges to warn about",
                  forever = "the bars follow Forever's own consumables; buffs with no known spell id, like Well Fed, are matched by name" } },
    { id = "chronoboon", part = "Zacui_Consumables", name = "Chronoboon displacers on the consumables bar",
      off = ERA_ONLY, notes = { "consbars" } },
    { id = "hud_warrior", part = "Zacui_HUD", name = "Warrior HUD",
      changed = { forever = "no swing timers or Overpower window (combat log); the execute cue goes quiet in combat (" .. SECRET .. ")" } },
    { id = "hud_classes", part = "Zacui_HUD", name = "Class HUDs (Paladin, Priest, Hunter, Rogue, Shaman, Mage, Warlock, Druid)",
      changed = { forever = "no swing timers (combat log); target debuffs go blank in combat (" .. SECRET .. ")" } },
    { id = "hud_swing", part = "Zacui_HUD", name = "Swing timers on the HUDs",
      off = { forever = CLOG }, notes = { "warrior", "paladin" } },
    { id = "drinkticker", part = "Zacui_HUD", name = "Drink Ticker",
      changed = { forever = "mana from a potion can nudge the tick: the combat log that tells them apart is not there" } },
    { id = "hesitation", part = "Zacui_HUD", name = "Hesitation alerts",
      changed = { forever = "execute abilities are not watched in combat (" .. SECRET .. ")" } },
    { id = "bags", part = "Zacui_Bags", name = "Bags, bank and bag sorting" },
    { id = "gold_sync", part = "Zacui_Bags", name = "Gold ledger shared between your characters",
      changed = { forever = MSG } },
    { id = "auction", part = "Zacui_Bags", name = "Auction house" },
    { id = "maps", part = "Zacui_Maps", name = "Maps: world map window, pins, group dots, minimap pins",
      changed = { tbc = "Outland has no unexplored-area, pin or HD map data yet" } },
    { id = "worldmap", part = "Zacui_WorldMap", whole = true, name = "Seamless world map",
      off = { tbc = "the stitched map holds Classic Era's Azeroth only" } },
    { id = "map_pins_share", part = "Zacui_WorldMap", name = "Sharing map pins with your group",
      changed = { forever = MSG } },
    { id = "qol", part = "Zacui_QoL", name = "Quality of life: automation, sound mutes, dialog keys, macro cleanup, smart mount, Snowball, GCD tracker" },
    { id = "raid_perf", part = "Zacui_QoL", name = "Raid performance mode" },
    { id = "boss_fx", part = "Zacui_QoL", name = "Boss particle levels", off = { tbc = ERA_RAIDS, forever = ERA_RAIDS }, notes = { "qol" } },
    { id = "autoroll", part = "Zacui_QoL", name = "Auto roll",
      changed = { tbc = "the Zul'Gurub coin and bijou and Naxxramas scrap choices are Classic Era items",
                  forever = "the Zul'Gurub coin and bijou and Naxxramas scrap choices are Classic Era items" } },
    { id = "raid_timers", part = "Zacui_QoL", name = "Pull and break bars",
      changed = { forever = "other raiders' timers (addon messages): " .. MSG } },
    { id = "buff_remover", part = "Zacui_QoL", name = "Buff remover (the 32-buff cap)", off = ERA_ONLY, notes = { "qol" } },
    { id = "windows", part = "Zacui_Windows", name = "The rebuilt game windows" },
}

local BY_ID, BY_PAGE, BY_NOTE, BY_PART = {}, {}, {}, {}
for _, f in ipairs(ns.FEATURE_FLAVORS) do
    BY_ID[f.id] = f
    for _, p in ipairs(f.pages or {}) do BY_PAGE[p] = f end
    for _, p in ipairs(f.notes or {}) do
        BY_NOTE[p] = BY_NOTE[p] or {}
        table.insert(BY_NOTE[p], f)
    end
    if f.whole then BY_PART[f.part] = f end
end

-- The unit frames part keeps its own notes per feature (Glows.lua,
-- ZacUI.FlavorNotes.unitframes); a row that names one reads its words
-- for the hover.
local function PartNote(f, flavor)
    local key = f.note
    local all = key and ns.FlavorNotes and ns.FlavorNotes.unitframes
    local n = type(all) == "table" and all[key]
    return type(n) == "table" and n[flavor] or nil
end

-- "on" | "off" | "changed", and the reason (nil for a plain "on"), for a
-- feature on a flavor (this one by default).
function ns.FeatureState(id, flavor)
    flavor = flavor or ns.Flavor()
    local f = BY_ID[id]
    if not f then return "on", nil end
    local why = f.off and f.off[flavor]
    if why then return "off", why end
    why = f.changed and f.changed[flavor]
    if why then return "changed", PartNote(f, flavor) or why end
    return "on", PartNote(f, flavor)
end

-- true when the feature runs on this flavor (and for any id not listed)
function ns.FeatureOn(id)
    local f = BY_ID[id]
    if not (f and f.off) then return true end
    return f.off[ns.Flavor()] == nil
end

function ns.FeatureOffReason(id)
    local f = BY_ID[id]
    return f and f.off and f.off[ns.Flavor()] or nil
end

-- "Not on TBC: Classic Era raids", plus "(simulated)" under the override
-- (the same words Readycheck uses)
function ns.FeatureOffNote(id)
    local why = ns.FeatureOffReason(id)
    if not why then return nil end
    local note = string.format("Not on %s: %s", ns.FlavorName(), why)
    if ns.FlavorSimulated() then note = note .. " (simulated)" end
    return note
end

-- a whole part that stands down on this flavor (its files return at once)
function ns.PartOff(addonName)
    local f = BY_PART[addonName]
    return (f and not ns.FeatureOn(f.id)) and true or false
end

-- the switched-off feature behind a menu row, or nil
function ns.FeatureOffForPage(menuId)
    local f = menuId and BY_PAGE[menuId]
    if f and not ns.FeatureOn(f.id) then return f.id end
    return nil
end

-- the notes a page that keeps working shows at its top
function ns.FlavorPageNotes(menuId)
    local list = menuId and BY_NOTE[menuId]
    if not list then return nil end
    local out
    for _, f in ipairs(list) do
        if not ns.FeatureOn(f.id) then
            out = out or {}
            out[#out + 1] = f.name .. ". " .. ns.FeatureOffNote(f.id)
        end
    end
    return out
end

-- every switched-off feature on a flavor (this one by default), in table
-- order: { { id =, name =, reason = }, ... }
function ns.FeaturesOff(flavor)
    flavor = flavor or ns.Flavor()
    local out = {}
    for _, f in ipairs(ns.FEATURE_FLAVORS) do
        local why = f.off and f.off[flavor]
        if why then out[#out + 1] = { id = f.id, name = f.name, reason = why } end
    end
    return out
end

-- ============================================================
-- WHAT FOREVER CHANGES, READ SAFELY
-- ============================================================
-- The combat log: never there on a real Forever client (registering it
-- is an error), and switched off under the override too.
function ns.NoCombatLog()
    if _G.ZACUI_IS_FOREVER then return true end
    return ns.Flavor() == "forever"
end

-- Addon messages: Forever does not deliver them inside an instance, so
-- the senders skip them there.
function ns.AddonMessagesBlocked()
    if not (_G.ZACUI_IS_FOREVER or ns.Flavor() == "forever") then return false end
    local inInstance = IsInInstance and IsInInstance()
    return inInstance and true or false
end

-- Secret values (WoW Forever, in combat). They may not be compared, used
-- in arithmetic or used as a table key; on the other clients the test is
-- always false.
local issecret = issecretvalue
function ns.IsSecret(v)
    if issecret == nil then return false end
    return issecret(v) and true or false
end

-- UnitHealth / UnitHealthMax, or nil, nil when either is hidden
function ns.SafeHealth(unit)
    local hp, mx = UnitHealth(unit), UnitHealthMax(unit)
    if issecret ~= nil and (issecret(hp) or issecret(mx)) then return nil, nil end
    return hp, mx
end

-- an aura data table whose name, id or times are hidden reads as no aura
function ns.AuraHidden(a)
    if issecret == nil or type(a) ~= "table" then return false end
    return (issecret(a.name) or issecret(a.spellId) or issecret(a.expirationTime)
        or issecret(a.duration) or issecret(a.applications)) and true or false
end

-- ============================================================
-- THE NOTE ON SCREEN while the override runs ZacUI as another game, so
-- it cannot be forgotten. ns.BuildFlavorNote is the note's constructor;
-- the Game versions page draws its preview with it.
-- ============================================================
function ns.BuildFlavorNote(parent, flavor)
    local UI = ns.UI
    local f = CreateFrame("Button", nil, parent or UIParent)
    f:SetSize(180, 20)
    if UI then
        UI.Fill(f, "ui", "windowBg", 0.85)
        UI.Border(f, "ui", "border")
    end
    local fs = UI and UI.Font(f, UI.F and UI.F.SMALL or 11, { cat = "text", key = "orange" })
        or f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("CENTER", 0, 0)
    f._zText = fs
    function f:SetFlavor(fl)
        self._zText:SetText("ZacUI: testing as " .. ns.FlavorName(fl))
        local w = self._zText:GetStringWidth() or 120
        self:SetWidth(math.max(120, math.ceil(w) + 18))
    end
    f._zPaint = function(self)
        if UI and UI.PaintBox then UI.PaintBox(self) end
        if self._zText._zPaint then self._zText:_zPaint() end
    end
    f:SetFlavor(flavor or ns.Flavor())
    f:_zPaint()
    return f
end

local note
local function ShowNote()
    if note or not ns.FlavorSimulated() then return end
    note = ns.BuildFlavorNote(UIParent)
    note:SetFrameStrata("DIALOG")
    local function Spot()
        local p = ZacUIDB and type(ZacUIDB.dev) == "table" and ZacUIDB.dev.notePos
        note:ClearAllPoints()
        if type(p) == "table" and p.point then
            note:SetPoint(p.point, UIParent, p.point, p.x or 0, p.y or 0)
        else
            note:SetPoint("TOP", UIParent, "TOP", 0, -30)
        end
    end
    Spot()
    note:SetScript("OnClick", function()
        if ns.OpenConfig then ns.OpenConfig("flavors") end
    end)
    if ns.UI and ns.UI.Tooltip then
        ns.UI.Tooltip(note, "Testing another game version",
            "ZacUI is switching features off as it would on " .. ns.FlavorName() .. " (this client is "
            .. ns.FlavorName(ns.RealFlavor()) .. "). Click for General > Game versions; "
            .. "set it back to Auto there or with /zacui flavor auto, then /reload.")
    end
    note:Show()
    ns.FlavorNoteFrame = note
    if ns.RegisterMover then
        ns.RegisterMover("flavornote", "Game version testing note", function() return note end, "TOP", 0, -30, nil, {
            get = function()
                local p = ZacUIDB and type(ZacUIDB.dev) == "table" and ZacUIDB.dev.notePos
                if type(p) == "table" and p.point then return p.point, p.x or 0, p.y or 0 end
            end,
            set = function(point, x, y)
                if type(ZacUIDB) ~= "table" then return end
                ZacUIDB.dev = ZacUIDB.dev or {}
                ZacUIDB.dev.notePos = point and { point = point, x = x or 0, y = y or 0 } or nil
            end,
            reset = function()
                note:ClearAllPoints()
                note:SetPoint("TOP", UIParent, "TOP", 0, -30)
            end,
            own = true,
        })
    end
end
ns.ShowFlavorNote = ShowNote

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    -- only ever up under the override: on the client's own flavor nothing
    -- is made at all
    if ns.FlavorSimulated() then
        ShowNote()
        ns.Print("testing as " .. ns.FlavorName() .. " - " .. #ns.FeaturesOff() .. " features off. "
            .. "/zacui flavor for the list, /zacui flavor auto to stop.")
    end
end)

-- ============================================================
-- /zacui flavor [era|tbc|forever|auto]
-- ============================================================
function ns.FlavorCommand(arg)
    local Print = ns.Print
    arg = arg and arg:lower():gsub("^%s+", ""):gsub("%s+$", "") or ""
    if arg == "era" or arg == "tbc" or arg == "forever" or arg == "auto" then
        if type(ZacUIDB) ~= "table" then
            Print("Settings are not loaded yet - try again in a moment.")
            return
        end
        local changes = ns.SetFlavorOverride(arg)
        local target = ns.FlavorName(ns.PendingFlavor())
        if changes then
            Print(string.format("Game version set to %s. Type /reload to apply it.", target))
        else
            Print(string.format("Game version set to %s - already running as that.", target))
        end
        if ns.RefreshConfig then pcall(ns.RefreshConfig) end
        return
    elseif arg ~= "" then
        Print("Usage: /zacui flavor [era|tbc|forever|auto]")
        return
    end

    local cur = ns.Flavor()
    local line = string.format("Game version: %s", ns.FlavorName(cur))
    if ns.FlavorSimulated() then
        line = line .. " " .. string.format("(simulated - this client is %s)", ns.FlavorName(ns.RealFlavor()))
    end
    Print(line)
    local pending = ns.PendingFlavor()
    if pending ~= cur then
        Print(string.format("After /reload: %s", ns.FlavorName(pending)))
    end
    local off, changed = ns.FeaturesOff(cur), {}
    for _, f in ipairs(ns.FEATURE_FLAVORS) do
        local st, why = ns.FeatureState(f.id, cur)
        if st == "changed" then changed[#changed + 1] = { name = f.name, reason = why } end
    end
    if #off == 0 then
        Print("Every feature is on.")
    else
        Print(string.format("Switched off on %s:", ns.FlavorName(cur)))
        for _, f in ipairs(off) do Print("  " .. f.name .. ": " .. f.reason) end
    end
    if #changed > 0 then
        Print(string.format("Changed on %s:", ns.FlavorName(cur)))
        for _, f in ipairs(changed) do Print("  " .. f.name .. ": " .. f.reason) end
    end
end
