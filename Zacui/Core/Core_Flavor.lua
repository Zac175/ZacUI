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
--   ns.Hidden / ns.HealthPercent / ns.ShowText / ns.ShowBar / ns.ReadAura
--   / ns.ShowAuraTimer / ns.ShowCastTimer ...
--                           ...and shown anyway: a hidden value handed
--                           straight to the widget that displays it
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
-- what still shows there: ZacUI hands the hidden values straight to the
-- bars, texts, icons and timers that show them (the display helpers below)
local SHOWN     = "Forever hides them from addons in combat; ZacUI hands them straight to the display"
local ERA_ONLY  = { tbc = ERA, forever = ERA }

ns.FEATURE_FLAVORS = {
    -- ZacUI itself
    { id = "skins", part = "Zacui", name = "The skin: every game window and the dialogs in ZacUI's look" },
    { id = "minimap", part = "Zacui", name = "Minimap: zone, clock, coordinates, icons and the button tray" },
    { id = "chat", part = "Zacui", name = "Chat, the chat bar and the raid chat strip" },
    { id = "raid_clear_timer", part = "Zacui", name = "Raid clear timer and splits on the raid chat strip",
      changed = { forever = "Forever's raids have no known last boss yet: a run ends when the game's lockout shows every boss down "
                  .. "(where the client reports it), else after four hours without a kill" } },
    { id = "tooltips", part = "Zacui", name = "Tooltips",
      changed = { forever = "enemy health in combat shows as whole numbers and the game's own percent (" .. SHOWN
                  .. "); a saved health-line format waits until the health reads again" } },
    { id = "buffs", part = "Zacui", name = "Your buffs and debuffs" },
    { id = "lootroll", part = "Zacui", name = "Loot rolls" },
    { id = "settings", part = "Zacui", name = "Settings window, appearance, profiles, import, movers and Edit Mode" },
    { id = "voice", part = "Zacui", name = "ZacUI's voice (the game's text to speech)" },
    { id = "tutorial", part = "Zacui", name = "First-run welcome, quick setup and the tour" },
    { id = "version_check", part = "Zacui", name = "Newer version notice (versions compared with your guild and group)",
      changed = { forever = MSG } },

    -- the parts
    { id = "bars", part = "Zacui_Bars", name = "Action bars and bar loadouts" },
    { id = "unitframes", part = "Zacui_UnitFrames", name = "Unit frames (player, target, party, raid)",
      changed = { forever = "enemy health, power, auras and casts show in combat as the game hands them over (" .. SHOWN
                  .. "): bars jump instead of gliding, health text is the whole number and the game's own percent "
                  .. "(a saved text format waits), no incoming-heal chips on a hidden health, a hidden cast wears the "
                  .. "normal cast colour, and aura filters that need a name or type let hidden auras by (\"only mine\" still works)" } },
    { id = "uf_heals", part = "Zacui_UnitFrames", name = "Incoming heals on the unit frames",
      changed = { forever = "other healers' heals are read from the combat log and addon messages, which Forever does not give addons; your own still show" } },
    { id = "uf_dispel", part = "Zacui_UnitFrames", name = "Dispel glow on the unit frames", note = "dispelGlow",
      changed = { forever = "goes quiet in combat: Forever hides other players' aura details from addons then" } },
    { id = "uf_taunt", part = "Zacui_UnitFrames", name = "AoE taunt glow, countdown and voice", note = "tauntGlow",
      changed = { forever = "seen from the cast event instead of the combat log; when the game hides the spell nothing shows" } },
    { id = "nameplates", part = "Zacui_Nameplates", name = "Nameplates (health, casts, threat, target arrows, soft target)",
      changed = { forever = "enemy health bars, the percent, cast bars and the debuff row show in combat as the game hands them over ("
                  .. SHOWN .. "): bars jump instead of gliding, and a hidden cast wears the plain cast colour with no "
                  .. "cast alert, script or cast target (they need the spell's id or the caster's target)" } },
    { id = "np_debuffs", part = "Zacui_Nameplates", name = "Nameplate debuffs, Sunder count and execute cue",
      changed = { forever = "go quiet in combat: each is found by the debuff's name, which Forever hides from addons then "
                  .. "(the plain debuff row above the plate still shows them)" } },
    { id = "dodge_window", part = "Zacui_Nameplates", name = "Overpower window after a dodge, and the crosshair's miss marks",
      changed = { forever = "the Overpower window comes from the game's own Overpower button (Battle Stance, your target, "
                  .. "5 seconds from when it lights); the crosshair's miss marks need the combat log, which Forever does not give addons" },
      notes = { "warrior" } },
    { id = "raidmods", part = "Zacui_RaidMods", whole = true,
      name = "Raid mods: boss timers, warnings and marks for each game's raids",
      changed = { tbc = "TBC's raids instead of Classic Era's: Karazhan, Gruul, Magtheridon, Serpentshrine, Tempest Keep, "
                  .. "Mount Hyjal, Black Temple, Zul'Aman and the Sunwell" },
      off = { forever = "Forever's raids are not known yet, and it gives addons no combat log for the boss timers" },
      pages = { "raidmods" } },
    { id = "raidtools", part = "Zacui_RaidTools", name = "/pull, /break, /range, raid sync and speech settings",
      changed = { forever = MSG } },
    { id = "auras", part = "Zacui_Auras", name = "Aura engine",
      changed = { forever = "combat-log triggers never fire, auras and health read as hidden in combat, and sharing waits outside instances" } },
    { id = "sbt", part = "Zacui_SBT", name = "Scrolling combat text",
      changed = { forever = "only hits and heals you take show (the game's own combat text); the combat log Forever does not give addons carries the rest" } },
    { id = "sbt_plates", part = "Zacui_SBT", name = "Your damage on enemy nameplates (scrolling text)",
      off = { forever = "your hits on each enemy are only in the combat log, which Forever does not give addons" }, notes = { "sbt" } },
    { id = "meter_parser", part = "Zacui_Meter", name = "Damage meter: damage, healing, deaths, interrupts",
      changed = { forever = "filled from the game's own damage meter when each fight ends (Forever gives addons no combat log, "
                  .. "and hides the game meter's numbers in combat): numbers show after the fight; no hit counts, crits, "
                  .. "overhealing or death logs" },
      notes = { "meter" } },
    { id = "meter_threat", part = "Zacui_Meter", name = "Threat meter, threat glow and pull warning" },
    { id = "raid_summary", part = "Zacui_Meter", name = "Raid summary after the last boss",
      changed = { forever = "built from the game's own damage meter: damage, healing and each ability's total; no hits a minute, "
                  .. "no what hit you, no death causes. Forever's raids end by the lockout (every boss down); /zacui raid opens it any time" } },
    { id = "meter_dmf", part = "Zacui_Meter", name = "Darkmoon Faire mark after names on the meter",
      changed = { tbc = "marks Sayge's fortune in any raid: TBC is not raided on world buffs, so \"only while my world buffs are on\" is not asked" },
      off = { forever = "Forever's Darkmoon Faire and its fortunes are not known yet" }, notes = { "meter" } },
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
      changed = { forever = "swing timers come from the game's own swing event; the Overpower window comes from the game's "
                  .. "Overpower button; in combat the execute cue asks the game's own health curve (" .. SECRET
                  .. "), and Hamstring's timer shows as the game hands it over while its name reads" } },
    { id = "hud_classes", part = "Zacui_HUD", name = "Class HUDs (Paladin, Priest, Hunter, Rogue, Shaman, Mage, Warlock, Druid)",
      changed = { forever = "swing and Auto Shot bars come from the game's own swing event; your target debuffs show in combat "
                  .. "with their timers and stacks as the game hands them over (" .. SHOWN .. "); ones whose names are "
                  .. "hidden too fill the row in the game's order, past the per-debuff ticks" } },
    { id = "hud_swing", part = "Zacui_HUD", name = "Swing timers on the HUDs",
      changed = { forever = "from the game's own swing event (PLAYER_SWING) instead of the combat log: each swing restarts its "
                  .. "bar at the game's swing time and a parry of yours speeds the next (Warrior HUD); a speed change "
                  .. "mid-swing is not stretched while the game hides your attack speed" },
      notes = { "warrior", "paladin" } },
    { id = "drinkticker", part = "Zacui_HUD", name = "Drink Ticker",
      changed = { forever = "mana from a potion can nudge the tick: the combat log that tells them apart is not there" } },
    { id = "hesitation", part = "Zacui_HUD", name = "Hesitation alerts",
      changed = { forever = "execute abilities are not watched in combat (" .. SECRET .. ")" } },
    { id = "bags", part = "Zacui_Bags", name = "Bags, bank and bag sorting" },
    { id = "gold_sync", part = "Zacui_Bags", name = "Gold ledger shared between your characters",
      changed = { forever = MSG } },
    { id = "auction", part = "Zacui_Bags", name = "Auction house" },
    { id = "maps", part = "Zacui_Maps", name = "Maps: world map window, pins, group dots, minimap pins",
      changed = { tbc = "on Outland and the new zones the flight masters come from the game; unexplored areas, dungeon "
                  .. "entrances, spirit healers and the HD map are Azeroth's only (they need the game's TBC map tables, which ZacUI does not ship yet)",
                  forever = "on Forever's own zones the flight masters come from the game; the rest of the pin data is Classic Era's Azeroth" } },
    { id = "worldmap", part = "Zacui_WorldMap", whole = true, name = "Seamless world map",
      off = { tbc = "the stitched map holds Classic Era's Azeroth only: Outland needs its own minimap tiles and offsets, which ZacUI does not ship" } },
    { id = "map_pins_share", part = "Zacui_WorldMap", name = "Sharing map pins with your group",
      changed = { forever = MSG } },
    { id = "qol", part = "Zacui_QoL", name = "Quality of life: automation, sound mutes, dialog keys, macro cleanup, smart mount, Snowball, GCD tracker" },
    { id = "raid_perf", part = "Zacui_QoL", name = "Raid performance mode" },
    { id = "boss_fx", part = "Zacui_QoL", name = "Boss particle levels",
      changed = { tbc = "TBC's raids (Karazhan to the Sunwell); Zul'Aman is not listed, its boss ids are not confirmed",
                  forever = "no bosses listed yet (Forever's raids are not out); the raid and world particle levels work" },
      notes = { "qol" } },
    { id = "autoroll", part = "Zacui_QoL", name = "Auto roll",
      changed = { tbc = "adds TBC's Primal Nether and Nether Vortex; the old raids' coin, bijou and scrap choices stay",
                  forever = "Forever's own shared roll items are not known yet: the quality rule and your own items cover it" } },
    { id = "raid_timers", part = "Zacui_QoL", name = "Pull and break bars",
      changed = { forever = "other raiders' timers (addon messages): " .. MSG } },
    { id = "buff_remover", part = "Zacui_QoL", name = "Buff remover (the buff cap)",
      changed = { tbc = "follows Readycheck's buff counter, which learns TBC's buff limit from the first push-offs" },
      off = { forever = "Readycheck's buff counter stands down on Forever: Forever hides your buffs from addons in combat, where push-offs happen" },
      notes = { "qol" } },
    { id = "windows", part = "Zacui_Windows", name = "The rebuilt game windows" },
    { id = "flight_times", part = "Zacui_Windows", name = "Flight times at the flight master and the countdown while flying",
      changed = { tbc = "no measured times carried over from the world map (it does not run on TBC): Outland's and "
                  .. "Azeroth's flights are learned from your own, and estimated until then" } },
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
-- SHOWING WHAT FOREVER HIDES (2026-11-07). A secret value cannot be
-- compared or counted with, but the game's own widgets take it as it
-- is: a text (SetText / SetFormattedText), a bar (SetMinMaxValues /
-- SetValue), an icon (SetTexture), an alpha (SetAlpha), a timer (a
-- Cooldown or a StatusBar fed the game's duration object). These hand a
-- hidden value straight to the widget with no maths on it. Each answers
-- true when it drew; false sends the caller back to what it did before.
-- On Era and TBC nothing is ever secret, so no caller ever gets here and
-- every part runs exactly as it always did. The newer calls are looked
-- up by name when used and run under pcall: one this client lacks, or
-- one that refuses a value, draws nothing instead of throwing.
-- (warcraft.wiki.gg, Forever 1.60.1: UnitHealthPercent, C_CurveUtil,
-- C_UnitAuras.GetAuraDuration / GetAuraApplicationDisplayCount,
-- Cooldown:SetCooldownFromDurationObject, UnitCastingDuration,
-- UnitChannelDuration, StatusBar:SetTimerDuration.)
--   ns.Hidden(...)                 any of the values secret
--   ns.HealthHidden(unit)          hidden, health, max
--   ns.HealthPercent(unit)         0-100 for display (may be secret), or nil
--   ns.HealthAlpha(unit, below)    1 at or under `below` (0-1) of health,
--                                  else 0: for SetAlpha, never compared
--   ns.ShowText(fs, fmt, ...)      SetFormattedText with hidden values
--   ns.ShowBar(bar, value, max)    a bar straight from the values
--   ns.ReadAura(unit, i, filter)   C_UnitAuras' aura table (fields may be
--                                  secret); false = this one was refused,
--                                  nil = no more
--   ns.AuraFieldsHidden(a)         its name / id / icon / times / stacks hidden
--   ns.AuraIsMine(a)               cast by you (the never-hidden flag when
--                                  the caster is hidden)
--   ns.AuraDuration(unit, a)       the game's duration object for it, or nil
--   ns.ShowAuraTimer(cd, unit, a)  its timer onto a Cooldown
--   ns.AuraTimeLeft(unit, a)       seconds left (may be secret), or nil
--   ns.ShowAuraCount(fs, unit, a)  its stacks onto a text ("" under 2)
--   ns.CastDuration(unit, channel) the cast's duration object, or nil
--   ns.ShowCastTimer(bar, dur, channel)  the cast onto a StatusBar
-- ============================================================
function ns.Hidden(...)
    if issecret == nil then return false end
    for i = 1, select("#", ...) do
        if issecret((select(i, ...))) then return true end
    end
    return false
end

function ns.HealthHidden(unit)
    local hp, mx = UnitHealth(unit), UnitHealthMax(unit)
    if issecret ~= nil and (issecret(hp) or issecret(mx)) then return true, hp, mx end
    return false, hp, mx
end

-- a curve the game evaluates for us (CurveObject, warcraft.wiki.gg):
-- points as { x, y } pairs, Linear between them
local function Curve(points)
    local CU = C_CurveUtil
    if not (CU and CU.CreateCurve) then return nil end
    local ok, c = pcall(CU.CreateCurve)
    if not ok or not c then return nil end
    local built = pcall(function()
        local lct = Enum and Enum.LuaCurveType
        if lct and lct.Linear ~= nil then c:SetType(lct.Linear) end
        for _, p in ipairs(points) do c:AddPoint(p[1], p[2]) end
    end)
    return built and c or nil
end

local scale100
local function Scale100()
    if scale100 == nil then
        local cc = rawget(_G, "CurveConstants")
        scale100 = (type(cc) == "table" and cc.ScaleTo100) or Curve({ { 0, 0 }, { 1, 100 } }) or false
    end
    return scale100 or nil
end

function ns.HealthPercent(unit)
    local f, curve = UnitHealthPercent, nil
    if f == nil then return nil end
    curve = Scale100()
    if not curve then return nil end
    local ok, v = pcall(f, unit, true, curve)
    if ok then return v end
    return nil
end

local alphaCurves = {}
function ns.HealthAlpha(unit, below)
    local f = UnitHealthPercent
    if f == nil or type(below) ~= "number" then return nil end
    local c = alphaCurves[below]
    if c == nil then
        local pts = { { 0, 1 }, { below, 1 }, { below + 0.0005, 0 } }
        if below + 0.0005 < 1 then pts[4] = { 1, 0 } end
        c = Curve(pts) or false
        alphaCurves[below] = c
    end
    if not c then return nil end
    local ok, v = pcall(f, unit, true, c)
    if ok then return v end
    return nil
end

function ns.ShowText(fs, fmt, ...)
    if not (fs and fs.SetFormattedText) then return false end
    return pcall(fs.SetFormattedText, fs, fmt, ...) and true or false
end

function ns.ShowBar(bar, value, max)
    if not bar then return false end
    if not pcall(bar.SetMinMaxValues, bar, 0, max) then return false end
    return pcall(bar.SetValue, bar, value) and true or false
end

function ns.ReadAura(unit, index, filter)
    local UA = C_UnitAuras
    local get = UA and UA.GetAuraDataByIndex
    if not get then return nil end
    local ok, a = pcall(get, unit, index, filter)
    if not ok then return false end
    return a
end

function ns.AuraFieldsHidden(a)
    if issecret == nil or type(a) ~= "table" then return false end
    return (issecret(a.name) or issecret(a.spellId) or issecret(a.icon) or issecret(a.duration)
        or issecret(a.expirationTime) or issecret(a.applications)) and true or false
end

function ns.AuraIsMine(a)
    if type(a) ~= "table" then return false end
    local s = a.sourceUnit
    if issecret ~= nil and issecret(s) then return a.isFromPlayerOrPlayerPet == true end
    return s == "player"
end

function ns.AuraDuration(unit, a)
    local UA = C_UnitAuras
    local id = type(a) == "table" and a.auraInstanceID
    if not (id and UA and UA.GetAuraDuration) then return nil end
    local ok, dur = pcall(UA.GetAuraDuration, unit, id)
    if ok then return dur end
    return nil
end

function ns.ShowAuraTimer(cd, unit, a)
    if not (cd and a) then return false end
    local dur = ns.AuraDuration(unit, a)
    if dur and cd.SetCooldownFromDurationObject and pcall(cd.SetCooldownFromDurationObject, cd, dur) then
        return true
    end
    if cd.SetCooldownFromExpirationTime
        and pcall(cd.SetCooldownFromExpirationTime, cd, a.expirationTime, a.duration) then
        return true
    end
    return false
end

function ns.AuraTimeLeft(unit, a)
    local dur = ns.AuraDuration(unit, a)
    if not (dur and dur.GetRemainingDuration) then return nil end
    -- an aura with no end has a zero duration: no number for it
    if dur.IsZero then
        local ok, z = pcall(dur.IsZero, dur)
        if ok and not ns.IsSecret(z) and z then return nil end
    end
    local ok, left = pcall(dur.GetRemainingDuration, dur)
    if ok then return left end
    return nil
end

function ns.ShowAuraCount(fs, unit, a)
    if not (fs and a) then return false end
    local UA = C_UnitAuras
    local id = a.auraInstanceID
    if id and UA and UA.GetAuraApplicationDisplayCount then
        local ok, s = pcall(UA.GetAuraApplicationDisplayCount, unit, id, 2)
        if ok and s ~= nil and pcall(fs.SetText, fs, s) then return true end
    end
    local n = a.applications
    if not ns.IsSecret(n) then
        fs:SetText((n and n > 1) and n or "")
        return true
    end
    return false
end

function ns.CastDuration(unit, channel)
    local f = channel and UnitChannelDuration or UnitCastingDuration
    if f == nil then return nil end
    local ok, dur = pcall(f, unit)
    if ok then return dur end
    return nil
end

function ns.ShowCastTimer(bar, dur, channel)
    if not (bar and dur and bar.SetTimerDuration) then return false end
    local E = Enum
    local interp = E and E.StatusBarInterpolation and E.StatusBarInterpolation.Immediate or 0
    local dirs = E and E.StatusBarTimerDirection
    local dir = channel and (dirs and dirs.RemainingTime or 1) or (dirs and dirs.ElapsedTime or 0)
    return pcall(bar.SetTimerDuration, bar, dur, interp, dir) and true or false
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
