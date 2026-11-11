-- Core_Flavor - which game this is: Classic Era, TBC Anniversary, WoW
-- Forever or Retail, and what ZacUI switches off on each.
-- Part of ZacUI; load order is set by the TOC (right after Core_Boot, so
-- every later file and every part can ask).
-- ============================================================
--   ns.Flavor()             "era" | "tbc" | "forever" | "retail"
--   ns.ModernClient()       this client runs the Mainline UI family
--                           (Forever or Retail: the real client, never
--                           the override - Core_Forever's _G.ZACUI_MODERN)
--   ns.ModernRules()        Forever's and Retail's rules apply: the real
--                           client, or the override running as one
--   ns.FlavorSimulated()    true while the developer override runs ZacUI
--                           as another game than this client
--   ns.FEATURE_FLAVORS      every part and every notable feature inside
--                           one, with the games it runs on and the plain
--                           reason where it does not (or runs changed)
--   ns.FeatureOn(id)        ask before registering events, tickers or
--                           frames; true for any id not in the table
--   ns.PartOff(addon)       a whole part that does not run here
--   ns.NoCombatLog()        Forever's and Retail's rules for the combat
--                           log (the real client, or the override)
--   ns.AddonMessagesBlocked()  Forever or Retail, inside an instance
--   ns.IsSecret / ns.SafeHealth / ns.AuraHidden
--                           Forever's secret values, read safely
--   ns.Hidden / ns.HealthPercent / ns.ShowText / ns.ShowBar / ns.ReadAura
--   / ns.ShowAuraTimer / ns.ShowCastTimer ...
--                           ...and shown anyway: a hidden value handed
--                           straight to the widget that displays it
--
-- WHERE THE ANSWER COMES FROM. WOW_PROJECT_ID (1 Retail, 2 Classic Era,
-- 5 TBC Anniversary, 18 WoW Forever), then the interface number for a
-- client that reports something else. The same answer, in the same
-- words, as Readycheck's RC:Flavor() (Readycheck\Core\Core_Flavor.lua;
-- Readycheck itself does not run on Retail).
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

local VALID = { era = true, tbc = true, forever = true, retail = true }
local ORDER = { "era", "tbc", "forever", "retail" }
local NAMES = { era = "Classic Era", tbc = "TBC", forever = "Forever", retail = "Retail" }
ns.FLAVORS = ORDER
ns.FLAVOR_NAMES = NAMES
-- the games on the modern (Mainline) client: Forever and Retail share
-- the rules below (no combat log, secret values, held addon messages)
local MODERN_FLAVOR = { forever = true, retail = true }
ns.MODERN_FLAVORS = MODERN_FLAVOR

function ns.DetectFlavor()
    local pid = WOW_PROJECT_ID
    if pid == 1 then return "retail" end   -- (WOW_PROJECT_MAINLINE)
    if pid == 2 then return "era" end
    if pid == 5 then return "tbc" end
    if pid == 18 then return "forever" end
    local build = (GetBuildInfo and select(4, GetBuildInfo())) or 0
    if type(build) ~= "number" then build = tonumber(build) or 0 end
    if build >= 100000 then return "retail" end
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

-- the saved choice: "auto" (none), "era", "tbc", "forever" or "retail"
function ns.FlavorOverride()
    local ov = ReadOverride()
    return ov or "auto"
end

-- value: "auto", "era", "tbc", "forever" or "retail". True when it changes what the
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
--   kind     [flavor] = which kind of "off" that is:
--              not_needed  the game version does not have the problem
--                          (TBC and Forever have no buff limit you reach)
--              not_there   the content is not on that version
--              cant        the game keeps what it needs from addons, or
--                          ZacUI cannot do it there yet
--            Whatever the kind, it does not load there: no frames,
--            events, tickers, menu pages, options or search hits. Only
--            General > Game versions and /zacui flavor list it.
--   changed  [flavor] = what is different there (it still runs)
--   on       [flavor] = it runs there unchanged, and this is why that was
--            decided (an explicit verdict; a row without it is on by default)
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
-- Classic Era's world buffs stop working above level 63 on TBC (patch
-- 2.1, warcraft.wiki.gg); on Forever "world buffs are removed inside
-- dungeons and raids" (warcraft.wiki.gg, World of Warcraft: Forever)
local WB_TBC     = "Classic Era world buffs stop working above level 63 on TBC, so there are none to store"
local WB_FOREVER = "Forever removes world buffs inside dungeons and raids, so there is nothing to keep for a raid"
local CANT       = { forever = "cant" }
-- Retail (Mainline 12.x, from 2026-11-07): the same rules as Forever -
-- no combat log for addons (registering it is an error since 12.0), secret
-- values in combat, addon messages held inside instances - in Retail's
-- name. The Classic rebuilds (HUDs, buff reminders, consumables, the bank,
-- the character sheet) come later; until then they are off there.
local CLOG_R     = "needs the combat log, which Retail does not give addons"
local MSG_R      = "Retail blocks addon messages inside instances; sync waits until you leave"
local SECRET_R   = "Retail hides enemy health, casts and auras from addons in combat"
local SHOWN_R    = "Retail hides them from addons in combat; ZacUI hands them straight to the display"
local LATER_R    = "a Retail version is coming later"
local CANT_R     = { forever = "cant", retail = "cant" }

ns.FEATURE_FLAVORS = {
    -- ZacUI itself
    { id = "skins", part = "Zacui", name = "The skin: every game window and the dialogs in ZacUI's look" },
    { id = "minimap", part = "Zacui", name = "Minimap: zone, clock, coordinates, icons and the button tray" },
    { id = "chat", part = "Zacui", name = "Chat, the chat bar and the raid chat strip" },
    -- feature cluster 1 (2026-11-07): each with a Forever verdict of its own
    -- (Zac on Forever: "most of the quality of life stuff isnt needed")
    { id = "chat_history", part = "Zacui", name = "Chat history kept across /reload",
      changed = { forever = "lines Forever hides from addons in a fight are not kept; the rest come back as everywhere",
                  retail = "lines Retail hides from addons in a fight are not kept; the rest come back as everywhere" } },
    { id = "whisper_sound", part = "Zacui", name = "A sound on an incoming whisper",
      on = { forever = "a whisper arriving is the same event on every game" } },
    { id = "chat_privacy", part = "Zacui", name = "Streaming privacy cover (guild, officer and whisper text masked)",
      on = { forever = "masking what the chat shows works the same on every game; nothing sent is ever changed" } },
    -- feature cluster 1, group D (2026-11-07): the chat items from the chat survey
    { id = "chat_urls", part = "Zacui", name = "Clickable web addresses in the chat, with a copy box",
      changed = { forever = "a line Forever hides from addons in a fight is left as it is (its addresses are not linked)",
                  retail = "a line Retail hides from addons in a fight is left as it is (its addresses are not linked)" } },
    { id = "chat_link_tips", part = "Zacui", name = "A chat link's tooltip on hover",
      on = { forever = "hovering a link shows the game's own tooltip the same way on every game; a hidden link is never read",
             retail = "hovering a link shows the game's own tooltip the same way on every game; a hidden link is never read" } },
    { id = "chat_short_names", part = "Zacui", name = "Short channel names ([P] [R] [RL] [G], world channels as numbers)",
      off = { forever = "Forever draws the chat with secure code, and rewriting its lines would break the game's whisper reply in a fight",
              retail = "Retail draws the chat with secure code, and rewriting its lines would break the game's whisper reply in a fight" },
      kind = { forever = "cant", retail = "cant" } },
    { id = "chat_stamps", part = "Zacui", name = "Time stamps: the game's format, and a stamp on every line",
      changed = { forever = "the format picker (the game's own setting) works; stamping every line needs the chat's lines rewritten, "
                  .. "which Forever's secure chat does not allow",
                  retail = "the format picker (the game's own setting) works; stamping every line needs the chat's lines rewritten, "
                  .. "which Retail's secure chat does not allow" } },
    { id = "chat_name_colors", part = "Zacui", name = "Group members' names in class colour inside messages",
      changed = { forever = "a message Forever hides from addons in a fight is left as it is",
                  retail = "a message Retail hides from addons in a fight is left as it is" } },
    { id = "chat_idle_fade", part = "Zacui", name = "The whole chat fading when idle",
      on = { forever = "it only sets the chat's own frames' opacity and counts chat events, never reading them",
             retail = "it only sets the chat's own frames' opacity and counts chat events, never reading them" } },
    { id = "chat_visibility", part = "Zacui", name = "When the chat shows (always / in combat / out of combat / never)",
      on = { forever = "the rule only sets the chat's opacity, which every game allows in a fight",
             retail = "the rule only sets the chat's opacity, which every game allows in a fight" } },
    { id = "chat_panel_look", part = "Zacui", name = "The chat panel's texture, border size and colour, inner line",
      on = { forever = "the panel is ZacUI's own frame on every game",
             retail = "the panel is ZacUI's own frame on every game" } },
    { id = "chat_tab_look", part = "Zacui", name = "Chat tab name colours and chip padding",
      on = { forever = "the tab chips are ZacUI's own and the name colour is the tab's own text",
             retail = "the tab chips are ZacUI's own and the name colour is the tab's own text" } },
    { id = "chat_lock_size", part = "Zacui", name = "Lock the chat's size",
      on = { forever = "the resize grip is the chat's own button on every game",
             retail = "the resize grip is the chat's own button on every game" } },
    { id = "chat_bar_extras", part = "Zacui", name = "A settings cog and the game's chat menu on the chat bar",
      on = { forever = "both are ordinary buttons on ZacUI's bar; the chat menu is the game's own",
             retail = "both are ordinary buttons on ZacUI's bar; the chat menu is the game's own" } },
    -- feature cluster 3 (2026-11-07)
    { id = "chat_ldb", part = "Zacui", name = "Other addons' LibDataBroker blocks on the chat bar",
      on = { forever = "Broker addons register their blocks the same way on every game; a hidden value one writes is shown as it is",
             retail = "Broker addons register their blocks the same way on every game; a hidden value one writes is shown as it is" } },
    { id = "forever_names", part = "Zacui", name = "Surnames on ZacUI's names, and character keys by ruleset (WoW Forever's own)",
      on = { forever = "Forever's characters carry surnames and have no realms: names show the surname as the game does, "
             .. "and saved character data is keyed by name and ruleset (old realm keys move over once)" },
      off = { retail = "Retail's second name value is the realm, not a surname, and its realms are real: nothing to change" },
      kind = { retail = "not_there" } },
    { id = "raid_clear_timer", part = "Zacui", name = "Raid clear timer and splits on the raid chat strip",
      changed = { forever = "Forever's raids have no known last boss yet: a run ends when the game's lockout shows every boss down "
                  .. "(where the client reports it), else after four hours without a kill",
                  retail = "Retail's raids have no last-boss list yet: a run ends when the game's lockout shows every boss down "
                  .. "(where the client reports it), else after four hours without a kill" } },
    { id = "tooltips", part = "Zacui", name = "Tooltips",
      changed = { forever = "enemy health in combat shows as whole numbers and the game's own percent (" .. SHOWN
                  .. "); a saved health-line format waits until the health reads again",
                  retail = "enemy health in combat shows as whole numbers and the game's own percent (" .. SHOWN_R
                  .. "); a saved health-line format waits until the health reads again" } },
    { id = "tooltip_stats", part = "Zacui", name = "Short stat lines on item tooltips (\"+24 Attack Power\")",
      on = { forever = "Forever's items carry Classic's \"Equip:\" lines, the ones this shortens" },
      -- (2026-11-09) Retail's items have no "Equip:" stat lines of this kind
      off = { retail = "Retail already writes its stat lines short, and has no Classic-style \"Equip:\" lines to rewrite" },
      kind = { retail = "not_needed" } },
    { id = "buffs", part = "Zacui", name = "Your buffs and debuffs" },
    { id = "lootroll", part = "Zacui", name = "Loot rolls" },
    { id = "settings", part = "Zacui", name = "Settings window, appearance, profiles, import, movers and Edit Mode" },
    { id = "voice", part = "Zacui", name = "ZacUI's voice (the game's text to speech)" },
    { id = "tutorial", part = "Zacui", name = "First-run welcome, quick setup and the tour" },
    { id = "version_check", part = "Zacui", name = "Newer version notice (versions compared with your guild and group)",
      changed = { forever = MSG, retail = MSG_R } },
    { id = "dev_secrets", part = "Zacui", name = "Developer: force the game's addon restrictions (/zui dev secrets)",
      on = { forever = "the switch sets the client's own restriction settings where it has them; a client without them says so and sets nothing" } },

    -- the parts
    { id = "bars", part = "Zacui_Bars", name = "Action bars and bar loadouts",
      changed = { retail = "the game's own bars are tucked away the way its Edit Mode leaves them alone; the vehicle, "
                  .. "override and extra-action bars stay the game's, and the micro menu shows the buttons ZacUI knows "
                  .. "(Retail's own set, like Collections and the Adventure Guide, is coming later)" } },
    -- feature cluster 3 (2026-11-07)
    { id = "bars_uprank", part = "Zacui_Bars", name = "A new spell rank put on your bars when you learn it",
      on = { forever = "levelling on Forever is where new ranks come in; a rank is the game's own answer, the same on every Classic client" },
      off = { retail = "Retail's spells have no ranks to learn" },
      kind = { retail = "not_there" } },
    { id = "unitframes", part = "Zacui_UnitFrames", name = "Unit frames (player, target, party, raid)",
      changed = { forever = "enemy health, power, auras and casts show in combat as the game hands them over (" .. SHOWN
                  .. "): bars jump instead of gliding, health text is the whole number and the game's own percent "
                  .. "(a saved text format waits), no incoming-heal chips on a hidden health, a hidden cast wears the "
                  .. "normal cast colour, and aura filters that need a name or type let hidden auras by (\"only mine\" still works)",
                  retail = "enemy health, power, auras and casts show in combat as the game hands them over (" .. SHOWN_R
                  .. "): bars jump instead of gliding, health text is the whole number and the game's own percent "
                  .. "(a saved text format waits), no incoming-heal chips on a hidden health, a hidden cast wears the "
                  .. "normal cast colour, and aura filters that need a name or type let hidden auras by (\"only mine\" still works)" } },
    { id = "uf_heals", part = "Zacui_UnitFrames", name = "Incoming heals on the unit frames",
      changed = { forever = "other healers' heals are read from the combat log and addon messages, which Forever does not give addons; your own still show",
                  retail = "other healers' heals are read from the combat log and addon messages, which Retail does not give addons; "
                  .. "your own, and the game's own incoming-heal number, still show" } },
    { id = "uf_dispel", part = "Zacui_UnitFrames", name = "Dispel glow on the unit frames", note = "dispelGlow",
      changed = { forever = "goes quiet in combat: Forever hides other players' aura details from addons then",
                  retail = "goes quiet in combat: Retail hides other players' aura details from addons then" } },
    { id = "uf_taunt", part = "Zacui_UnitFrames", name = "AoE taunt glow, countdown and voice", note = "tauntGlow",
      changed = { forever = "seen from the cast event instead of the combat log; when the game hides the spell nothing shows",
                  retail = "seen from the cast event instead of the combat log; when the game hides the spell nothing shows" } },
    -- feature cluster 3 (2026-11-07)
    { id = "uf_missing_buffs", part = "Zacui_UnitFrames", name = "Your missing buffs on the party and raid frames",
      changed = { forever = "goes quiet in combat when Forever hides other players' buffs from addons; out of combat it works as everywhere" },
      off = { retail = "needs the buff reminders' tables of who gives what, which are off on Retail" },
      kind = { retail = "cant" } },
    -- feature cluster 2 (2026-11-07): frames for units Classic Era does not
    -- have (the only rows off on Era: the game has no such unit)
    { id = "uf_focus", part = "Zacui_UnitFrames", name = "Focus and focus-target frames",
      on = { tbc = "TBC has a focus target (/focus)" },
      changed = { forever = "the focus is often an enemy: its health, power, auras and cast show in combat as the game hands them over ("
                  .. SHOWN .. "), as on the target frame",
                  retail = "the focus is often an enemy: its health, power, auras and cast show in combat as the game hands them over ("
                  .. SHOWN_R .. "), as on the target frame" },
      off = { era = "Classic Era has no focus target" }, kind = { era = "not_there" } },
    { id = "uf_boss", part = "Zacui_UnitFrames", name = "Boss frames (boss 1 to 5)",
      on = { tbc = "TBC's encounters hand the game's boss units to addons" },
      changed = { forever = "a boss's health, power and cast show in combat as the game hands them over (" .. SHOWN .. ")",
                  retail = "a boss's health, power and cast show in combat as the game hands them over (" .. SHOWN_R .. ")" },
      off = { era = "Classic Era's encounters have no boss units" }, kind = { era = "not_there" } },
    { id = "uf_tanks", part = "Zacui_UnitFrames", name = "Tank frames (the raid's main tanks, or a list of names, beside the raid)",
      changed = { forever = "a tank's health, auras and the rest show as on the raid frames (" .. SHOWN .. ")",
                  retail = "players in the tank role show as well as the raid's main tanks; health and the rest as on the raid frames (" .. SHOWN_R .. ")" } },
    { id = "uf_party_targets", part = "Zacui_UnitFrames", name = "Party targets (who each party member is targeting)",
      changed = { forever = "an enemy target's health shows in combat as the game hands it over (" .. SHOWN .. ")",
                  retail = "an enemy target's health shows in combat as the game hands it over (" .. SHOWN_R .. ")" } },
    { id = "nameplates", part = "Zacui_Nameplates", name = "Nameplates (health, casts, threat, target arrows, soft target)",
      changed = { forever = "enemy health bars, the percent, cast bars and the debuff row show in combat as the game hands them over ("
                  .. SHOWN .. "): bars jump instead of gliding, and a hidden cast wears the plain cast colour with no "
                  .. "cast alert, script or cast target (they need the spell's id or the caster's target)",
                  retail = "enemy health bars, the percent, cast bars and the debuff row show in combat as the game hands them over ("
                  .. SHOWN_R .. "): bars jump instead of gliding, and a hidden cast wears the plain cast colour with no "
                  .. "cast alert, script or cast target (they need the spell's id or the caster's target); the game's own "
                  .. "personal resource bar is left alone" } },
    -- feature cluster 2 (2026-11-07)
    { id = "np_kick", part = "Zacui_Nameplates", name = "Cast bars coloured by your interrupt (ready, on cooldown, out of range)",
      changed = { forever = "in a fight Forever hides an enemy's cast, and some cooldowns and ranges, from addons: a hidden one "
                  .. "reads as unknown and the bar keeps its normal colour",
                  retail = "in a fight Retail hides an enemy's cast, and some cooldowns and ranges, from addons: a hidden one "
                  .. "reads as unknown and the bar keeps its normal colour" } },
    { id = "np_debuffs", part = "Zacui_Nameplates", name = "Nameplate debuffs, Sunder count and execute cue",
      -- (2026-11-09, Zac: "hide for now") Forever's reworked spells are not listed yet
      off = { forever = "Forever's reworked debuffs are not listed yet (the plain debuff row above the plate still shows them)" },
      kind = { forever = "not_there" },
      changed = { retail = "go quiet in combat: each is found by the debuff's name, which Retail hides from addons then "
                  .. "(the plain debuff row above the plate still shows them)" } },
    { id = "dodge_window", part = "Zacui_Nameplates", name = "Overpower window after a dodge, and the crosshair's miss marks",
      changed = { forever = "the Overpower window comes from the game's own Overpower button (Battle Stance, your target, "
                  .. "5 seconds from when it lights); the crosshair's miss marks need the combat log, which Forever does not give addons",
                  retail = "the Overpower window comes from the game's own Overpower button; the crosshair's miss marks " .. CLOG_R },
      notes = { "warrior" } },
    { id = "raidmods", part = "Zacui_RaidMods", whole = true,
      name = "Raid mods: boss timers, warnings and marks for each game's raids",
      changed = { tbc = "TBC's raids instead of Classic Era's: Karazhan, Gruul, Magtheridon, Serpentshrine, Tempest Keep, "
                  .. "Mount Hyjal, Black Temple, Zul'Aman and the Sunwell" },
      off = { forever = "Forever gives addons no combat log for the boss timers (and its raids open on 9 December)",
              retail = "Retail gives addons no combat log for the boss timers, and its raids are Midnight's, not the Classic "
              .. "raids these mods know; a Retail boss-mod pack is another product" },
      kind = CANT_R, pages = { "raidmods" } },
    { id = "raidtools", part = "Zacui_RaidTools", name = "/pull, /break, /range, raid sync and speech settings",
      changed = { forever = MSG, retail = MSG_R } },
    { id = "auras", part = "Zacui_Auras", name = "Aura engine",
      changed = { forever = "combat-log triggers never fire, auras and health read as hidden in combat, and sharing waits outside instances",
                  retail = "combat-log triggers never fire (an imported aura's combat-log trigger is dropped), auras and health "
                  .. "read as hidden in combat, and sharing waits outside instances" } },
    { id = "sbt", part = "Zacui_SBT", name = "Scrolling combat text",
      changed = { forever = "only hits and heals you take show (the game's own combat text); the combat log Forever does not give addons carries the rest",
                  retail = "only hits and heals you take show (the game's own combat text); the combat log Retail does not give addons carries the rest" } },
    { id = "sbt_plates", part = "Zacui_SBT", name = "Your damage on enemy nameplates (scrolling text)",
      off = { forever = "your hits on each enemy are only in the combat log, which Forever does not give addons",
              retail = "your hits on each enemy are only in the combat log, which Retail does not give addons" },
      kind = CANT_R, notes = { "sbt" } },
    { id = "meter_parser", part = "Zacui_Meter", name = "Damage meter: damage, healing, deaths, interrupts",
      changed = { forever = "filled from the game's own damage meter when each fight ends (Forever gives addons no combat log, "
                  .. "and hides the game meter's numbers in combat): numbers show after the fight; no hit counts, crits, "
                  .. "overhealing or death logs",
                  retail = "filled from the game's own damage meter when each fight ends (Retail gives addons no combat log, "
                  .. "and hides the game meter's numbers in combat): numbers show after the fight; no hit counts, crits, "
                  .. "overhealing or death logs" },
      notes = { "meter" } },
    { id = "meter_threat", part = "Zacui_Meter", name = "Threat meter, threat glow and pull warning",
      changed = { retail = "threat values are hidden from addons in combat: the threat window stays quiet until the fight ends" } },
    { id = "raid_summary", part = "Zacui_Meter", name = "Raid summary after the last boss",
      changed = { forever = "built from the game's own damage meter: damage, healing and each ability's total; no hits a minute, "
                  .. "no what hit you, no death causes. Forever's raids end by the lockout (every boss down); /zacui raid opens it any time",
                  retail = "built from the game's own damage meter: damage, healing and each ability's total; no hits a minute, "
                  .. "no what hit you, no death causes. Retail's raids end by the lockout (every boss down); /zacui raid opens it any time" } },
    { id = "meter_dmf", part = "Zacui_Meter", name = "Darkmoon Faire mark after names on the meter",
      -- (2026-11-09, Zac: "configurable in the ui in the meter settings only for era")
      off = { tbc = "TBC is not raided on world buffs, so there is nobody to catch with Sayge's fortune",
              forever = "whether Forever has the Darkmoon Faire and Sayge's fortunes is unconfirmed",
              retail = "Retail's Darkmoon Faire has no Sayge's fortune buffs to mark" },
      kind = { tbc = "not_needed", forever = "not_there", retail = "not_there" }, notes = { "meter" } },
    { id = "clicks", part = "Zacui_Clicks", name = "Click casting",
      changed = { retail = "the game has click bindings of its own for Blizzard's frames; ZacUI's apply to ZacUI's unit frames" } },
    { id = "blessings", part = "Zacui_Blessings", whole = true, name = "Blessings: casting bar and assignments",
      changed = { forever = "assignments shared with other paladins: " .. MSG },
      off = { retail = "Retail has no class-assigned blessings: a paladin buffs the whole raid with one spell" },
      kind = { retail = "not_there" }, pages = { "blessings" } },
    { id = "buffrem", part = "Zacui_BuffReminders", whole = true, name = "Buff reminders and the buff tracker",
      off = { retail = "Retail's raid buffs are raid-wide with no ranks or reagents, and other players' buffs are hidden "
              .. "from addons in combat; a table of Retail's buffs for the reminder is coming later" },
      kind = { retail = "cant" } },
    { id = "consbars", part = "Zacui_Consumables", whole = true, name = "Consumables, potion and weapon bars",
      changed = { tbc = "the bars follow TBC's own consumables: one battle and one guardian elixir or a flask, and poisons have no charges to warn about",
                  forever = "the bars follow Forever's own consumables; buffs with no known spell id, like Well Fed, are matched by name" },
      off = { retail = "Retail's own consumables (phials, flasks, food, potions, oils and stones) are not in ZacUI's tables; " .. LATER_R },
      kind = { retail = "cant" } },
    { id = "chronoboon", part = "Zacui_Consumables", name = "Chronoboon displacers on the consumables bar",
      off = { tbc = WB_TBC, forever = WB_FOREVER, retail = "Retail has no world buffs to store and no Chronoboon Displacer" },
      kind = { tbc = "not_there", forever = "not_needed", retail = "not_there" },
      notes = { "consbars" } },
    -- (2026-11-09) the part loads on Retail: its Classic HUDs stay off there
    -- (the rows below) and HUD_Retail.lua gives every class a HUD built on
    -- the game's own Cooldown Manager list for the spec you play
    { id = "hud", part = "Zacui_HUD", whole = true, name = "Class HUDs, Drink Ticker and Hesitation alerts (the part)",
      changed = { retail = "one HUD for every class, built from the game's own Cooldown Manager list for the spec you play: "
                  .. "its cooldowns, a utility row, your tracked buffs and a plain power bar. No swing timers, "
                  .. "five-second rule or mana ticks, and nothing is read off the target's debuffs in a fight" } },
    { id = "hud_warrior", part = "Zacui_HUD", name = "Warrior HUD",
      changed = { forever = "swing timers come from the game's own swing event; the Overpower window comes from the game's "
                  .. "Overpower button; in combat the execute cue asks the game's own health curve (" .. SECRET
                  .. "), and Hamstring's timer shows as the game hands it over while its name reads" },
      off = { retail = "the Classic warrior rotation (Bloodthirst, Sunder, Overpower, swing timers) is not Retail's; "
              .. "Retail's own class HUD takes its place" },
      kind = { retail = "cant" } },
    { id = "hud_classes", part = "Zacui_HUD", name = "Class HUDs (Paladin, Priest, Hunter, Rogue, Shaman, Mage, Warlock, Druid)",
      changed = { forever = "swing and Auto Shot bars come from the game's own swing event; your target debuffs show in combat "
                  .. "with their timers and stacks as the game hands them over (" .. SHOWN .. "); ones whose names are "
                  .. "hidden too fill the row in the game's order, past the per-debuff ticks" },
      off = { retail = "the Classic class rotations and items (mana gems, runes, Classic potions) are not Retail's; "
              .. "Retail's own class HUD (every class, from the game's Cooldown Manager) takes their place" },
      kind = { retail = "cant" } },
    { id = "hud_swing", part = "Zacui_HUD", name = "Swing timers on the HUDs",
      changed = { forever = "from the game's own swing event (PLAYER_SWING) instead of the combat log: each swing restarts its "
                  .. "bar at the game's swing time and a parry of yours speeds the next (Warrior HUD); a speed change "
                  .. "mid-swing is not stretched while the game hides your attack speed" },
      off = { retail = "Retail has neither the combat log nor Forever's swing event for addons to time swings by" },
      kind = { retail = "cant" }, notes = { "warrior", "paladin" } },
    { id = "drinkticker", part = "Zacui_HUD", name = "Drink Ticker",
      changed = { forever = "mana from a potion can nudge the tick: the combat log that tells them apart is not there" },
      off = { retail = "Retail's mana regenerates steadily, not in the two-second ticks the Drink Ticker shows" },
      kind = { retail = "not_needed" } },
    { id = "hesitation", part = "Zacui_HUD", name = "Hesitation alerts",
      changed = { forever = "execute abilities are not watched in combat (" .. SECRET .. ")" },
      off = { retail = "the alerts watch Classic abilities by name and id, which Retail's classes do not have" },
      kind = { retail = "not_there" } },
    { id = "bags", part = "Zacui_Bags", name = "Bags, bank and bag sorting",
      changed = { retail = "your character bags only (the game's reagent bag included); the bank is the game's own for now" } },
    { id = "bank", part = "Zacui_Bags", name = "ZacUI's bank window",
      off = { retail = "Retail's bank is tabs of its own, character and Warband, not the Classic bank bags ZacUI lays out; " .. LATER_R },
      kind = { retail = "cant" }, notes = { "bags" } },
    { id = "gold_sync", part = "Zacui_Bags", name = "Gold ledger shared between your characters",
      changed = { forever = MSG, retail = MSG_R } },
    -- (feature cluster 3) on every game version, Forever included: a list
    -- of your characters is as useful there as anywhere
    { id = "alt_bags", part = "Zacui_Bags", name = "Your other characters' gold list, remembered bags and bank, tooltip counts",
      changed = { retail = "bags only: ZacUI's bank window is off there, so no bank is remembered" } },
    { id = "auction", part = "Zacui_Bags", name = "Auction house",
      off = { retail = "Retail's auction house works another way (commodities and items through C_AuctionHouse), "
              .. "which ZacUI's price memory does not speak yet; " .. LATER_R },
      kind = { retail = "cant" }, pages = { "auction" } },
    { id = "maps", part = "Zacui_Maps", name = "Maps: world map window, pins, group dots, minimap pins",
      changed = { tbc = "on Outland and the new zones the flight masters come from the game; unexplored areas, dungeon "
                  .. "entrances, spirit healers and the HD map are Azeroth's only (they need the game's TBC map tables, which ZacUI does not ship yet)",
                  forever = "on Forever's own zones the flight masters come from the game; the rest of the pin data is Classic Era's Azeroth",
                  retail = "the map window in ZacUI's look, group dots and the battlefield map; the Classic Azeroth data "
                  .. "(unexplored areas, pins, HD map, minimap pins) stays off, and Retail's own map shows its flight masters, "
                  .. "dungeon entrances and group members" } },
    -- feature cluster 3 (2026-11-07)
    { id = "maps_game_fade", part = "Zacui_Maps", name = "The game's own map fade while moving, and a dim behind the maximized map",
      on = { forever = "the map fade setting and the map's black backing are the same on Forever; a client without the setting never shows it",
             retail = "the map fade setting and the map's black backing are the same on Retail; a client without the setting never shows it" } },
    { id = "maps_data", part = "Zacui_Maps", name = "Map data: unexplored areas, pins, zone levels, HD map tiles and minimap pins",
      off = { retail = "this is Classic Era's Azeroth data (Leatrix Maps); Retail's own map already shows flight masters, "
              .. "dungeon entrances and group members, and a Retail reveal set is a later import" },
      kind = { retail = "not_there" }, notes = { "maps" } },
    { id = "worldmap", part = "Zacui_WorldMap", whole = true, name = "Seamless world map",
      off = { tbc = "the stitched map holds Classic Era's Azeroth only: Outland needs its own minimap tiles and offsets, which ZacUI does not ship yet",
              retail = "the stitched map holds Classic Era's Azeroth only (its zone art and offsets); Retail's own map is already continuous per continent" },
      kind = { tbc = "cant", retail = "cant" } },
    { id = "map_pins_share", part = "Zacui_WorldMap", name = "Sharing map pins with your group",
      changed = { forever = MSG },
      off = { retail = "the seamless world map does not run on Retail" }, kind = { retail = "cant" } },
    -- Zacui_QoL, piece by piece (2026-11-07, Zac on Forever: "most of the
    -- quality of life stuff isnt needed ... the snowball and buff cancel
    -- stuff is not needed"): the generic pieces - automation, sound mutes,
    -- dialog keys, macro cleanup, raid performance - run everywhere; the
    -- ones tied to Classic mechanics are off, with the reason
    { id = "qol", part = "Zacui_QoL", name = "Quality of life: automation (vendor, loot, gossip, invites), sound mutes, dialog keys, macro cleanup" },
    { id = "smart_mount", part = "Zacui_QoL", name = "Smart mount macro",
      -- (the mount journal is a fact about the client, not the game version:
      -- where it exists the macro summons a random favourite through it)
      changed = (_G.C_MountJournal and type(_G.C_MountJournal.SummonByID) == "function")
          and { forever = "the macro summons a random favourite mount through the game's mount journal (mounts are learned there, not carried)",
                retail = "the macro summons a random favourite mount through the game's mount journal (mounts are learned there, not carried)" }
          or nil },
    { id = "snowball", part = "Zacui_QoL", name = "Snowball button (throws only in the air)",
      -- (2026-11-09, Zac: "remove the snowball tab on tbc")
      off = { tbc = "the snowball trick isn't needed on TBC", forever = "the snowball trick isn't needed on Forever",
              retail = "the snowball trick isn't needed on Retail" },
      kind = { tbc = "not_needed", forever = "not_needed", retail = "not_needed" }, notes = { "qol" } },
    { id = "gcd_tracker", part = "Zacui_QoL", name = "GCD tracker (what you pressed, what went off)",
      changed = { forever = "in a fight Forever hides spell cooldowns from addons: the GCD swipe can read as ready while the icons of what you pressed still roll",
                  retail = "in a fight Retail hides spell cooldowns from addons: the GCD swipe can read as ready while the icons of what you pressed still roll" } },
    { id = "raid_perf", part = "Zacui_QoL", name = "Raid performance mode" },
    { id = "boss_fx", part = "Zacui_QoL", name = "Boss particle levels",
      changed = { tbc = "TBC's raids (Karazhan to the Sunwell); Zul'Aman is not listed, its boss ids are not confirmed",
                  forever = "no bosses listed yet (Forever's raids are not out); the raid and world particle levels work",
                  retail = "no bosses listed (Retail's raid bosses are not in the list); the raid and world particle levels work" },
      notes = { "qol" } },
    { id = "autoroll", part = "Zacui_QoL", name = "Auto roll",
      changed = { tbc = "adds TBC's Primal Nether and Nether Vortex; the old raids' coin, bijou and scrap choices stay",
                  forever = "Forever's own shared roll items are not known yet: the quality rule and your own items cover it",
                  retail = "Retail's shared roll items are not listed: the quality rule and your own items cover it" } },
    { id = "raid_timers", part = "Zacui_QoL", name = "Pull and break bars",
      changed = { forever = "other raiders' timers (addon messages): " .. MSG,
                  retail = "other raiders' timers (addon messages): " .. MSG_R } },
    -- feature cluster 1 (2026-11-07)
    { id = "auto_combatlog", part = "Zacui_QoL", name = "Combat logging on its own when you enter a raid (or a dungeon)",
      changed = { forever = "Forever's raids open on 9 December; until then there is no raid to log, so on Forever it only "
                  .. "runs with \"dungeons too\" ticked and stands down otherwise" },
      notes = { "qol" } },
    { id = "durability_warning", part = "Zacui_QoL", name = "Low durability warning",
      on = { forever = "gear wears and repairs the same way on Forever" } },
    { id = "talent_reminder", part = "Zacui_QoL", name = "Unspent talent points reminder",
      changed = { forever = "shows only while Forever's client answers the Classic talent calls with a plain number; "
                  .. "a hidden or missing count shows nothing" },
      off = { retail = "Retail's talents are trees of their own inside the spellbook window, with no Classic point count to watch" },
      kind = { retail = "not_there" }, notes = { "qol" } },
    -- feature cluster 3 (2026-11-07)
    { id = "loot_feed", part = "Zacui_QoL", name = "Loot feed: fading rows for loot, money, reputation and skill-ups",
      on = { forever = "loot, money, reputation and skill lines arrive the same way on Forever; a line the game hides in a fight is skipped",
             retail = "loot, money, reputation and skill lines arrive the same way on Retail; a line the game hides in a fight is skipped" } },
    { id = "qol_autos", part = "Zacui_QoL", name = "Small automations: DELETE typed, containers opened, cinematics skipped, a res accepted, release in battlegrounds",
      on = { forever = "the popups, cinematics, resurrections and battlegrounds work the same way on Forever (the container list is Classic's; your own ids add the rest)" },
      changed = { retail = "the container list is Classic's (your own ids add Retail's); the rest works the same" } },
    -- overnight gap build (2026-11-08, ELLESMERE_GAPS_1108.md)
    { id = "quest_helpers", part = "Zacui_QoL", name = "Quest helpers: quests taken and handed in, objective and quest sounds, progress told to your party",
      on = { forever = "the quest pages and the quest log answer the same calls on Forever; a hidden value is skipped",
             retail = "the quest pages are the same; the log is read through C_QuestLog" } },
    { id = "qol_alerts", part = "Zacui_QoL", name = "Alerts: entering / leaving combat, group deaths, the instance reset line, the screenshot text hidden",
      on = { forever = "deaths are found by asking each member (no combat log needed); a hidden name is drawn by the game as it is; "
                       .. "a hidden system line is skipped before any string work",
             retail = "the same calls as on Forever" } },
    { id = "gather_skill", part = "Zacui_QoL", name = "The skill a herb or ore node needs, on its tooltip",
      changed = { tbc = "Outland's herbs and ores are listed too",
                  forever = "the same nodes as Classic Era; a node Forever adds stays as the game shows it until its skill is known" },
      off = { retail = "Retail's nodes need no skill level" }, kind = { retail = "not_needed" } },
    { id = "junk_items", part = "Zacui_QoL", name = "Junk items window: the cheapest junk in your bags, to delete when they are full",
      on = { forever = "bags, vendor prices and deleting an item work the same way on Forever",
             retail = "bags, vendor prices and deleting an item work the same way on Retail" } },
    { id = "qol_stats", part = "Zacui_QoL", name = "Character stats on the screen (attack power, crit, hit, spell power...)",
      changed = { tbc = "hit adds the hit rating's bonus to the talents', as TBC's character pane does",
                  forever = "a stat Forever hides in a fight is drawn as the game hands it; one that is a sum (attack power, spell power) shows ? until it reads again",
                  retail = "Retail's own ratings (mastery, versatility) are not listed; the stats Classic shares are" } },
    { id = "qol_cursor", part = "Zacui_QoL", name = "Rings round the mouse cursor (circle, GCD sweep, cast sweep)",
      changed = { forever = "a global cooldown Forever hides in a fight is swept by the game as it is; a cast whose times are hidden shows no cast ring",
                  retail = "the same as on Forever" } },
    { id = "qol_reminders", part = "Zacui_QoL", name = "Reminders: no pet, pet on Passive, nothing tracked, low mana at a ready check",
      on = { forever = "the pet bar, tracking and ready checks read the same way on Forever; hidden mana in a fight says nothing (ready checks come before the pull)" },
      changed = { retail = "Retail's pet classes keep their own spells; the hunter and warlock checks use Classic's" } },
    { id = "data_blocks", part = "Zacui_QoL", name = "Data blocks for the chat bar: clock, coordinates, experience / reputation, supplies",
      changed = { forever = "coordinates Forever hides (inside an instance) read --",
                  retail = "no ammo or Classic reagents on Retail: supplies reads --; coordinates hidden in instances read --" } },
    { id = "bag_item_text", part = "Zacui_Bags", name = "Item level and BoE text on the bag window's gear",
      on = { forever = "item levels and how an item binds read the same way on Forever",
             retail = "item levels and how an item binds read the same way on Retail" } },
    { id = "qol_distance", part = "Zacui_QoL", name = "Target distance text (yards, melee / dead zone / range colours)",
      changed = { forever = "range checks Forever refuses on an enemy in a fight read ?",
                  retail = "range checks Retail refuses on an enemy in a fight read ?" } },
    { id = "tracker_vis", part = "Zacui_QoL", name = "Quest tracker hidden in raids (dungeons, battlegrounds, fights)",
      changed = { forever = "Forever's tracker has quest item buttons, so it is collapsed the game's own way (never in a fight) instead of faded",
                  retail = "the same as on Forever" } },
    -- Zac: TBC and Forever have no buff limit you reach, so there is
    -- nothing to make room for (on its own merit, Readycheck or not)
    { id = "buff_remover", part = "Zacui_QoL", name = "Buff remover (the buff cap)",
      off = { tbc = "TBC has no buff limit you'll hit, so nothing is ever pushed off",
              forever = "Forever has no buff limit, so nothing is ever pushed off",
              retail = "Retail has no buff limit, so nothing is ever pushed off" },
      kind = { tbc = "not_needed", forever = "not_needed", retail = "not_needed" },
      notes = { "qol" } },
    { id = "windows", part = "Zacui_Windows", name = "The rebuilt game windows",
      changed = { retail = "the merchant, mail, trade, gossip, loot, macros, inspect, trainer, social and spellbook windows run "
                  .. "(the modern ones with the ZacUI title bar); the character sheet, pet, talents, quest log, PvP, group finder "
                  .. "and flight times stay the game's own, in ZacUI's skin" } },
    { id = "win_character", part = "Zacui_Windows", name = "The character sheet, its pages and the pet page",
      off = { retail = "Retail's character sheet is its own (character, reputation and currency tabs, no skills or honor page) "
              .. "and the pet page is the stable; " .. LATER_R },
      kind = { retail = "cant" }, notes = { "gamewindows" } },
    { id = "win_talents", part = "Zacui_Windows", name = "The talents window",
      off = { retail = "Retail's talents are trees of their own inside the game's spellbook window (hero talents too), not the three Classic trees" },
      kind = { retail = "not_there" }, notes = { "gamewindows" } },
    -- classic book and talents on Forever (2026-11-07): Win_TalentsForever,
    -- Win_SpellbookForever (Forever's own data in the Classic shapes)
    { id = "classic_book", part = "Zacui_Windows", name = "The Classic talent trees and every spell rank in ZacUI's windows",
      changed = { forever = "drawn from Forever's new talent and spellbook data, over the game's combined spells window" },
      off = { retail = "Retail's talents are trees of their own and its spellbook has no ranks" },
      kind = { retail = "not_there" } },
    { id = "win_questlog", part = "Zacui_Windows", name = "The quest log window",
      off = { retail = "Retail's quest log lives inside the world map" },
      kind = { retail = "not_there" }, notes = { "gamewindows" } },
    -- feature cluster 1 (2026-11-07)
    { id = "quest_reward_mark", part = "Zacui_Windows", name = "Coin mark on the quest reward that sells for most",
      on = { forever = "quest rewards and their vendor prices read the same way on Forever" } },
    { id = "win_pvp", part = "Zacui_Windows", name = "The battlemaster and scoreboard windows",
      off = { retail = "Retail's PvP window is a page of the game's group finder" },
      kind = { retail = "not_there" }, notes = { "gamewindows" } },
    { id = "win_lfg", part = "Zacui_Windows", name = "The group finder window",
      off = { retail = "Retail's group finder is the game's own window, which ZacUI skins instead" },
      kind = { retail = "not_there" }, notes = { "gamewindows" } },
    { id = "flight_times", part = "Zacui_Windows", name = "Flight times at the flight master and the countdown while flying",
      changed = { tbc = "no measured times carried over from the world map (it does not run on TBC): Outland's and "
                  .. "Azeroth's flights are learned from your own, and estimated until then" },
      off = { retail = "the route data is Classic Azeroth's, and Retail's own flight map shows its times" },
      kind = { retail = "cant" }, pages = { "flighttimes" } },
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

-- the three kinds of "off", as the Game versions page and /zacui flavor
-- name them
ns.FLAVOR_KIND_NAMES = { not_needed = "not needed", not_there = "not there", cant = "can't" }

-- "not_needed" | "not_there" | "cant" for a feature off on a flavor (this
-- one by default), nil where it runs; a row with no kind reads as "cant"
function ns.FeatureOffKind(id, flavor)
    flavor = flavor or ns.Flavor()
    local f = BY_ID[id]
    if not (f and f.off and f.off[flavor]) then return nil end
    return (f.kind and f.kind[flavor]) or "cant"
end

-- "on" | "off" | "changed", and the reason (nil for a plain "on"), for a
-- feature on a flavor (this one by default); for "off", the kind third.
function ns.FeatureState(id, flavor)
    flavor = flavor or ns.Flavor()
    local f = BY_ID[id]
    if not f then return "on", nil end
    local why = f.off and f.off[flavor]
    if why then return "off", why, ns.FeatureOffKind(id, flavor) end
    why = f.changed and f.changed[flavor]
    if why then return "changed", PartNote(f, flavor) or why end
    -- a plain "on" with a reason given on purpose (f.on[flavor]): the
    -- verdict was looked at for that game, not left to the default
    return "on", PartNote(f, flavor) or (f.on and f.on[flavor]) or nil
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

-- "Not needed on Forever: ...", "Not on TBC: ..." or "Can't run on
-- Forever: ...", plus "(simulated)" under the override (the same words
-- Readycheck uses)
local NOTE_FORMAT = { not_needed = "Not needed on %s: %s", not_there = "Not on %s: %s", cant = "Can't run on %s: %s" }
function ns.FeatureOffNote(id)
    local why = ns.FeatureOffReason(id)
    if not why then return nil end
    local note = string.format(NOTE_FORMAT[ns.FeatureOffKind(id)] or NOTE_FORMAT.cant, ns.FlavorName(), why)
    if ns.FlavorSimulated() then note = note .. " (simulated)" end
    return note
end

-- A stand-in for a frame a switched-off feature would make: every method
-- is there and does nothing, so its file runs unchanged and no frame
-- exists on that game version.
do
    local function Noop() end
    ns.FlavorNullFrame = setmetatable({}, { __index = function() return Noop end })
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
-- order: { { id =, name =, reason =, kind = }, ... }
function ns.FeaturesOff(flavor)
    flavor = flavor or ns.Flavor()
    local out = {}
    for _, f in ipairs(ns.FEATURE_FLAVORS) do
        local why = f.off and f.off[flavor]
        if why then
            out[#out + 1] = { id = f.id, name = f.name, reason = why, kind = ns.FeatureOffKind(f.id, flavor) }
        end
    end
    return out
end

-- ============================================================
-- WHAT FOREVER CHANGES, READ SAFELY
-- ============================================================
-- The modern client (Forever or Retail; Core_Forever sets the flag before
-- anything else loads): Mainline templates and windows, secret values, no
-- combat log. A fact about the real client, so never the override's.
function ns.ModernClient()
    return _G.ZACUI_MODERN == true
end

-- Forever's and Retail's rules: the real modern client, or the override
-- running ZacUI as one of them.
function ns.ModernRules()
    if _G.ZACUI_MODERN then return true end
    return MODERN_FLAVOR[ns.Flavor()] == true
end

-- The combat log: never there on a real Forever or Retail client
-- (registering it is an error since 12.0), and switched off under the
-- override too.
function ns.NoCombatLog()
    return ns.ModernRules()
end

-- Addon messages: Forever and Retail do not deliver them inside an
-- instance (AddOnMessageLockdown), so the senders skip them there.
function ns.AddonMessagesBlocked()
    if not ns.ModernRules() then return false end
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
-- /zacui flavor [era|tbc|forever|retail|auto]
-- ============================================================
function ns.FlavorCommand(arg)
    local Print = ns.Print
    arg = arg and arg:lower():gsub("^%s+", ""):gsub("%s+$", "") or ""
    if VALID[arg] or arg == "auto" then
        if type(ZacUIDB) ~= "table" then
            Print("Settings are not loaded yet - try again in a moment.")
            return
        end
        local changes = ns.SetFlavorOverride(arg)
        local target = ns.FlavorName(ns.PendingFlavor())
        if changes then
            if ns.AskReload then ns.AskReload(string.format("Game version set to %s. It takes hold after a reload.", target))
            else Print(string.format("Game version set to %s. Type /reload to apply it.", target)) end
        else
            Print(string.format("Game version set to %s - already running as that.", target))
        end
        if ns.RefreshConfig then pcall(ns.RefreshConfig) end
        return
    elseif arg ~= "" then
        Print("Usage: /zacui flavor [era|tbc|forever|retail|auto]")
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
        Print(string.format("Switched off on %s (not loaded at all):", ns.FlavorName(cur)))
        for _, f in ipairs(off) do
            Print("  " .. f.name .. " [" .. (ns.FLAVOR_KIND_NAMES[f.kind] or f.kind) .. "]: " .. f.reason)
        end
    end
    if #changed > 0 then
        Print(string.format("Changed on %s:", ns.FlavorName(cur)))
        for _, f in ipairs(changed) do Print("  " .. f.name .. ": " .. f.reason) end
    end
end
