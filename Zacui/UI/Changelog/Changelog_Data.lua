-- Changelog_Data - ZacUI's version history, newest first.
-- Part of ZacUI; load order is set by the TOC (before Changelog).
--
-- One entry per version:
--   { version = "x.y.z", date = "YYYY-MM-DD", title = "...", sections = {
--       { type = "added" | "changed" | "fixed" | "removed", items = { "...", ... } },
--   } }
-- Newest at the top. The version must match ## Version in Zacui.toc (and
-- ZUI.VERSION in Core_Boot) for the "what's new" popup to show after an
-- update. Items are plain English for players: one short line per
-- change, no file, function or setting names. Do not comment entries.
--
-- AN ITEM FOR SOME GAME VERSIONS ONLY is a table instead of a string:
--   { "the line", feature = "buff_remover" }        shown where that feature runs
--   { "the line", feature = { "auction", "bags" } } shown where all of them run
--   { "the line", only = "tbc" }                    shown on that game version
--   { "the line", only = { "era", "tbc" } }         shown on any of those
-- feature ids are Core_Flavor's (the same table that hides a feature's
-- settings where it does not run); game versions are "era", "tbc",
-- "forever" and "retail". A plain string shows everywhere. Tag a line
-- only when it is plainly about one thing; a line about several things
-- stays a plain string. A version with nothing left for a game version
-- is not listed there, and brings no popup. A version may also carry
--   titles = { tbc = "...", retail = "..." }
-- for where its title names something that game version does not have.

local ADDON_NAME, ns = ...

ns.CHANGELOG = {
    {
        version = "3.0.14",
        date = "2026-11-16",
        title = "WoW Forever: game styles that fit, and the game's own micro menu and bags",
        titles = { era = "Windows and buttons with more depth", tbc = "Windows and buttons with more depth",
                   retail = "Windows and buttons with more depth" },
        sections = {
            {
                type = "added",
                items = {
                    "ZacUI's windows have a little shading, lit edges and raised title bars instead of one flat colour. The Style page has a \"Surface finish\" slider; 0% brings the flat windows back.",
                    "Action bars page, Advanced tab: \"Arrange for this style\" lays your bars out again for the style you picked.",
                    { "Gear slots in the character and inspect windows show each item's level.", only = "forever" },
                    { "Blizzard style: party frames wear the live game's party frame.", only = { "forever", "retail" } },
                    { "Blizzard style: the quest tracker wears the live game's art.", only = "forever" },
                },
            },
            {
                type = "changed",
                items = {
                    "Buttons and the settings window's page rows stand out more: a brighter raised face, a clearer outline and a thin shadow underneath.",
                    "Popup buttons are raised like every other button. The main choice has a gold face, a destructive one a red face.",
                    "Bars you have not moved are laid out again when you pick another style. Bars you moved stay where you put them.",
                    { "Under a game style the micro menu and the bag bar are the game's own, where the game puts them. Move them in the game's Edit Mode.", only = "forever" },
                    { "Under a game style the first action bar stays beside the game's micro menu, with the end cap at the end of the row and the XP bar across it.", only = "forever" },
                    { "Under Classic WoW UI and Blizzard style the game's windows wear ZacUI's style. Bars, unit frames, chat, minimap and the quest tracker keep the style you picked.", only = "forever" },
                    { "The character and inspect windows are the game's own, in ZacUI's style.", only = "forever" },
                    { "The Reputation, Skills, Statistics, Currency and PvP pages are styled.", only = "forever" },
                    { "New installs start with ZacUI's focus frame on.", feature = "uf_focus" },
                    { "Under Classic WoW UI and Blizzard style ZacUI's focus frame is switched on once, so it matches the other frames.", only = "forever" },
                },
            },
            {
                type = "fixed",
                items = {
                    { "The merchant window showed an error and overlapped its title.", only = "forever" },
                    { "The quest window showed the game's frame through ZacUI's.", only = "forever" },
                    { "The trade window showed the other player's portrait over the header.", only = "forever" },
                    { "An error when a target's cast was interrupted.", only = "forever" },
                    { "The stance bar sat left of the gryphon under a game style.", only = "forever" },
                    { "Minimap zoom jittered.", only = { "forever", "retail" } },
                    { "Classic WoW UI: a window's bottom tabs were the wrong size.", only = { "forever", "retail" } },
                    { "Bags under a game style: doubled labels on the Groups and Sort buttons.", feature = "bags" },
                },
            },
        },
    },
    {
        version = "3.0.12",
        date = "2026-11-15",
        title = "Shorter loading screens, a faster threat meter, and game styles on more of the screen",
        titles = { retail = "Shorter loading screens and game styles on more of the screen" },
        sections = {
            {
                type = "added",
                items = {
                    "The settings window loads when you first open it, so logging in is quicker.",
                    { "The boss mods for the five Classic raids load when you walk into the raid, not at login.", feature = "raidmods", only = "era" },
                    { "Threat meter: your row, the tank's row and \"You pull at\" update the moment your threat changes.", feature = "meter_threat" },
                    { "Threat meter: \"Make my row stand out\", with a colour of its own. On the Damage meter page, General tab.", feature = "meter_threat" },
                    { "Warrior HUD: Blood Fury, Berserking, War Stomp and Will of the Forsaken. On for Horde warriors.", feature = "hud_warrior" },
                    { "Warrior HUD: Fetish of the Sand Reaver's buff shows on the buff row with the trinket's icon.", feature = "hud_warrior", only = "era" },
                    { "Bags: a side-rail window style with a keyring, a pinned row and All, Kind and New views. Bags page, Look tab.", feature = "bags" },
                    { "World map: a new install is asked which map style to use the first time the map opens.", feature = "worldmap" },
                    "Under WoW Forever, Blizzard style and Classic WoW UI, ZacUI's raid timers, flight timer, buff reminder tracker, HUD icons and the raid mods' bars and icons now wear that style.",
                    "/zui perf shows what ZacUI is costing you.",
                },
            },
            {
                type = "changed",
                items = {
                    "New installs open ZacUI's windows at 80% size, and popups follow the settings window's size.",
                    "Every scroll bar is the same grey.",
                    "The colour picker no longer stutters while you drag.",
                    { "Under a game style the world map is the game's own window. ZacUI's map window and the seamless map are ticks on the Maps page.", feature = "maps" },
                    { "Under a game style the auction house is the game's own.", feature = "auction" },
                    { "A new install that picks a game style starts on the game's own bags.", feature = "bags" },
                    { "Raid mods: bars and warnings match ZacUI's look under ZacUI's style.", feature = "raidmods" },
                    { "Warrior HUD: a buff that ends fades out where it stands. No more empty slot on the buff row.", feature = "hud_warrior" },
                    { "Horde warriors on Classic Era: the Salvation icons and \"Drop Salvation while tanking\" are gone. There are no paladins to give it.", only = "era" },
                    { "Weapon stones: the menu and tooltip show your pick even when you carry none, and which stone is used instead.", feature = "consbars", only = "era" },
                    "Chat and unit frames do less work while nothing is happening.",
                },
            },
            {
                type = "fixed",
                items = {
                    { "The on/off switches in the settings sidebar did nothing on WoW Forever.", only = "forever" },
                    { "An error from heal prediction on WoW Forever with OldRaidFrames installed.", only = "forever" },
                    { "An error from the seamless map when zoomed far in.", feature = "worldmap" },
                    { "A purple ring on weapon stone buffs on the buff bar.", feature = "buffs", only = "era" },
                    { "Quick Keybind Mode: Escape no longer leaves the mode, and the game's extra action button no longer takes your key presses.", feature = "bars" },
                    { "Dropping a spell on a bar in combat no longer raises an \"action blocked\" error. A chat line says to drop it after the fight.", feature = "bars" },
                    { "The trade window's header matches the other windows.", feature = "windows" },
                },
            },
        },
    },
    {
        version = "3.0.11",
        date = "2026-11-12",
        title = "A changelog for the game version you play",
        sections = {
            {
                type = "changed",
                items = {
                    "What's New and the Changelog page list only the changes for the game version you are playing.",
                },
            },
        },
    },
    {
        version = "3.0.10",
        date = "2026-11-12",
        title = "A world-buff switch for the buff remover, and a smoother warrior HUD",
        titles = { tbc = "Whirlwind over Execute, and a smoother warrior HUD",
                   forever = "Whirlwind over Execute, and a smoother warrior HUD",
                   retail = "A solid resize corner" },
        sections = {
            {
                type = "added",
                items = {
                    { "Buff remover: an \"Only while world buffs are out\" switch. With no world buff on you nothing ticked is cancelled; once you have one, everything ticked goes as usual.", feature = "buff_remover" },
                    { "Buff remover: while that switch is on, a buff can be marked \"even with no WBs\" so it always goes. Salvation while tanking always goes too.", feature = "buff_remover" },
                    { "Hesitation prompts: in execute range, Whirlwind is marked ahead of Execute when there are enough mobs for it. It has its own switch.", feature = "hesitation" },
                    { "Hesitation prompts: a Glide option. The icons over your target fade, slide and grow instead of jumping.", feature = "hesitation" },
                    { "With Readycheck installed, its route tracker can sit along the top of the chat box in a raid, above the raid frames. The switch is on the Chat page under \"In a raid\", with two more for how gear swaps show on it.", only = { "era", "tbc" } },
                },
            },
            {
                type = "changed",
                items = {
                    { "Warrior HUD: icons grow smoothly, and an icon that leaves keeps its place for a moment so the row does not jump twice.", feature = "hud_warrior" },
                    "Every window's resize corner is one solid corner that lights up under the mouse and while you drag it.",
                },
            },
            {
                type = "fixed",
                items = {
                    { "A first login no longer ticks buffs for removal on a warrior, changes attack macros or makes a macro called \"dummy\".", feature = "buff_remover" },
                    { "Hesitation prompts: an ability that comes off cooldown during the global cooldown counts as ready.", feature = "hesitation" },
                    { "Hesitation prompts: Arms warriors get Mortal Strike where Bloodthirst would be.", feature = "hesitation" },
                    { "Hesitation prompts: Whirlwind was rated too high with a fast main-hand weapon.", feature = "hesitation" },
                    "The map window's title bar no longer shows a lighter slab behind it.",
                    { "Auction house: the line saying what you bought no longer flickers while buying stacks.", feature = "auction" },
                },
            },
        },
    },
    {
        version = "3.0.9",
        date = "2026-11-11",
        title = "The old raid frames, and one look everywhere",
        sections = {
            {
                type = "added",
                items = {
                    "With the Classic WoW UI style your raid uses the old Blizzard raid frames: class colours, groups four across, pets and main tanks. /orf opens their options.",
                    "Edit Mode: a Previews button shows or hides what is drawn under the boxes, and each frame's preview can be switched on its own. Right-click a frame in the Frames list.",
                    "Edit Mode: the party preview and the raid preview each have their own switch.",
                    "The bags and the auction house show an icon on their title bar.",
                },
            },
            {
                type = "changed",
                items = {
                    "The game's Options window matches ZacUI's settings window.",
                    "Checkboxes, dropdowns, sliders, tabs and text boxes look the same everywhere, inside the settings window and out.",
                    "Game windows that ZacUI restyles have their title at the left in ZacUI's font, over the same flat header as ZacUI's own windows.",
                    "The bar under the chat and the button column beside it are solid. The chat itself stays see-through.",
                    "The damage meter's menu page is the same grey as the other windows.",
                    "Dark window colours saved by older versions give way to the new lighter ones. Colours you picked yourself are kept.",
                    "The first-time tips in the settings window open beside it instead of over the tabs.",
                },
            },
            {
                type = "fixed",
                items = {
                    { "Buff remover: going to Defensive Stance and straight back no longer cancels Salvation.", feature = "buff_remover" },
                    "Edit Mode: a small slip of the mouse while clicking a frame no longer moves it.",
                    { "The auction buying window keeps its size when you press Buy.", feature = "auction" },
                    "The damage meter preview's size note no longer sits under the Layout button.",
                    "The mail windows have ZacUI's scroll bars.",
                },
            },
        },
    },
    {
        version = "3.0.8",
        date = "2026-11-10",
        title = "TBC raid mods, and class HUDs for your spec",
        titles = { era = "Class HUDs for your spec, and a buff filter",
                   forever = "Class HUDs for your spec, and a buff filter",
                   retail = "A first class HUD for Retail, and a buff filter" },
        sections = {
            {
                type = "added",
                items = {
                    { "Every class HUD starts on your spec's own list, with separate lists for Classic Era, TBC and WoW Forever.", only = { "era", "tbc", "forever" } },
                    { "Warrior, priest and paladin HUDs follow your spec too. Characters that already use them keep exactly what they had.", feature = "hud_classes" },
                    { "Warrior HUD: a row for debuffs on your target, such as Sunder Armor stacks and Demoralizing Shout.", feature = "hud_warrior" },
                    { "Priest HUD: a row for your own buffs. Paladin HUD: a row for your judgements on the target.", feature = "hud_classes" },
                    "A \"Show spells you haven't learned yet\" option on every class HUD.",
                    { "A first class HUD for Retail, for all classes. It is off until you switch it on and has not been tested in the game yet.", only = "retail" },
                    "A filter for buffs and debuffs on unit frames and on the nameplates' simple debuff row: pick what shows, add spells to always or never show, and set limits. Your old settings carry over.",
                    "Edit Mode has a bar across the top, and the box you click shows its own actions. Class HUDs show their real icons while you place them.",
                    { "The raid mods' boxes stay out of Edit Mode until you press \"Raid mods\" on the bar.", feature = "raidmods" },
                    "Bags can be split into groups by kind with the Groups button. New items get a gold edge, and a small bar shows how full your bags are.",
                    { "The auction buy window shows the item's quality and a progress bar, and can list every auction it will buy.", feature = "auction" },
                    { "TBC raid mods are filled out for all nine raids, Karazhan to Sunwell: cast bars with a KICK mark, debuff lists, tank icons, stand-in-it alarms and many more boss timers.", only = "tbc" },
                    { "Buff reminders on TBC: Commanding Shout, Earth Shield and the Master Soulstone. Fear Ward for priests who know it.", only = "tbc" },
                    { "Buff reminders can be limited to TBC's raids.", only = "tbc" },
                    "Your own buffs and debuffs by the minimap can use the buff filter, and party and raid frames can have a filter of their own.",
                    "A \"Seen lately\" list on the filter page: always show or never show a buff with one click.",
                    "Bags: an option to put Search and Sort on the title bar.",
                },
            },
            {
                type = "changed",
                items = {
                    "The settings window has a new look: sidebar pages, tabs and buttons are proper buttons, and section titles have a line across the page.",
                    "Custom nameplate debuffs can be added by name as well as by spell ID.",
                    "The window's corner buttons (reload, size, fold, close) are small raised buttons.",
                    "Options that do nothing on a game version are hidden on that version.",
                    { "The Darkmoon Faire mark on the damage meter hides while you have the fortune yourself, and is offered on Classic Era only.", feature = "meter_dmf" },
                    "The \"What's New\" window and the scroll bars match Readycheck's.",
                    "The map and the skinned game windows have the same flat header as the rest of ZacUI.",
                    "Edit Mode is easier to use: a line under the bar says how it works, the list shows what you can move first, and the box you click only offers what it can do.",
                    "Windows outside the settings window are a lighter grey instead of near-black.",
                    { "The auction buying window is much smaller.", feature = "auction" },
                    "On a fresh install more frames start in spots where they don't overlap. Setups you already have are not moved.",
                    "The settings search remembers what it has read, so it no longer stalls the first time you search each session.",
                },
            },
            {
                type = "fixed",
                items = {
                    "Several class HUD icons that tracked the wrong spell or never lit up, mostly on TBC.",
                    "Updating no longer changes the nameplate sizes you already had.",
                    "Scrolling a long page no longer slows down near the top and bottom.",
                    "Slider handles were dark instead of gold.",
                    "A line no longer runs through the percent text on the nameplate threat bar.",
                    { "Retail: the backpack icon was invisible, bag icons had black corners, and a gold line crossed the character window.", only = "retail" },
                    "Typing in the bag search or the Edit Mode search no longer lags.",
                    "Text on the Edit Mode bar no longer overlaps.",
                    "Features that are switched on can be placed in Edit Mode before they first appear.",
                },
            },
        },
    },
    {
        version = "3.0.6",
        date = "2026-11-09",
        title = "Move the previews around",
        sections = {
            {
                type = "added",
                items = {
                    "Drag a settings preview to move it around while you're zoomed in.",
                },
            },
            {
                type = "fixed",
                items = {
                    "Releases reach CurseForge again: 3.0.3 to 3.0.5 never made it there, and everything in them is in this version.",
                },
            },
        },
    },
    {
        version = "3.0.5",
        date = "2026-11-08",
        title = "Clear nameplate bars",
        sections = {
            {
                type = "fixed",
                items = {
                    "Nameplates under the game styles show nothing behind the missing health - no grey backing or white wash.",
                    "Nameplates under the Forever and live styles use the game's own bar art.",
                    "The game options window under the 2004 style has one close button, not two.",
                    "Quest and gossip text under the game styles is no longer heavy black.",
                    "No more blocked-action error when hovering an action button in combat.",
                    { "Action bar icons under the live style on WoW Forever fill their slots again.", only = "forever" },
                },
            },
        },
    },
    {
        version = "3.0.4",
        date = "2026-11-08",
        title = "Party frames and a new buy window",
        sections = {
            {
                type = "added",
                items = {
                    "Scroll the mouse wheel over a settings preview to zoom it in and out.",
                },
            },
            {
                type = "changed",
                items = {
                    "Party frames wear the game's own small party frame under the Classic, WoW Forever and Blizzard styles.",
                    { "The auction house buy window is redesigned: the item with its icon, what you've bought and spent, and one clear price button.", feature = "auction" },
                    "The key ring is a square slot with its own icon, like the bags beside it.",
                },
            },
            {
                type = "fixed",
                items = {
                    "Nameplates under the game styles have nothing behind the health bar, and no white wash on your target.",
                    "Party power bars (rage, energy, mana) show under the game styles instead of a white bar.",
                },
            },
        },
    },
    {
        version = "3.0.3",
        date = "2026-11-08",
        title = "Sharper buttons and a Twitch link",
        sections = {
            {
                type = "added",
                items = {
                    "A Twitch button next to the Discord one in the settings.",
                    "Classic WoW UI: the original stone bar behind the main action bar.",
                },
            },
            {
                type = "changed",
                items = {
                    "Close buttons, switches and slider knobs are sharper at any UI scale.",
                    "Settings: Reload and the window's size are small icons in the header; the bar along the bottom is gone.",
                    "The colour picker is smooth, and right-clicking a colour box resets it.",
                    "Small popups have a smaller close button, and their buttons always show.",
                    "Chat: the icons sit in a column joined to the chat's left side and show when the mouse is over the chat (the Chat page can keep them always up). The Party / Chat / Hide msgs buttons over the chat are gone - the icons do the same jobs.",
                    "Style page: a part ticked under a look can be unticked again.",
                    "The \"Move in Edit Mode\" tag on the settings pages is gone; Edit Mode is in the sidebar.",
                    "Windows use the flat header from the settings, with no sparkle.",
                    "Bags under the WoW Forever and Blizzard looks use the game's own bag window: the portrait, rim, title, close button and coin box.",
                    { "Classic WoW UI on WoW Forever: the minimap gets the 2004 grey ring and zone bar, the character pane and spellbook the 2004 look, and the bag bar and menu buttons their 2004 art.", only = "forever" },
                    "Nameplates: the hesitation icons sit above the mob's name instead of on it, and Demoralizing Shout shows with your other debuffs under the bar.",
                    "The changelog window is more compact.",
                    { "Classic WoW UI on WoW Forever: the game's own windows (character, spellbook, vendors, quests, mail, bank, friends, options, popups, tooltips and more) wear the 2004 border, gold title, round close button, old tabs and old buttons.", only = "forever" },
                    "Known issue: a few windows may still not fully match the look you picked (the world map keeps ZacUI's own frame). Keep sending screenshots.",
                },
            },
            {
                type = "fixed",
                items = {
                    { "Buffs and the bag bar were not getting ZacUI's look on Era and TBC.", only = { "era", "tbc" } },
                    { "A second close button on the loot window on Era and TBC.", only = { "era", "tbc" } },
                    "Square corners on the nameplate target glow.",
                    { "The colour picker's colour wheel was blank on Era and TBC, and the picker could open behind the settings.", only = { "era", "tbc" } },
                    { "The mount button on Era and TBC used a call that only works on WoW Forever and never mounted you; it uses your mount from your bags again.", only = { "era", "tbc" } },
                    { "The auction house buy window: the Buy button no longer covers the text, and it shows the amount and price again.", feature = "auction" },
                    "An error in the unit frame preview.",
                },
            },
        },
    },
    {
        version = "3.0.2",
        date = "2026-11-08",
        title = "Quieter starting settings",
        sections = {
            {
                type = "changed",
                items = {
                    "A fresh install starts with the warrior HUD, the hesitation prompts, the threat screen glow and scrolling combat text off. Each one can be turned on in the settings.",
                },
            },
        },
    },
    {
        version = "3.0.1",
        date = "2026-11-08",
        title = "A smoother setup and better starting settings",
        sections = {
            {
                type = "added",
                items = {
                    "A Discord button to contact Zac for help.",
                    "Chat: buttons on the rail to swap between the chat and the raid frames.",
                },
            },
            {
                type = "changed",
                items = {
                    "The first-time setup is one flow: pick a look, pick your parts, done.",
                    "Popups and their headers match the new settings window.",
                    "Bags and the bank follow the look you pick.",
                    "The chat rail sits on the right of the chat and never changes the chat's size.",
                    "A fresh install starts with one damage meter window, the threat window closed and the minimap button tray off.",
                    "A fresh install under the ZacUI look gets a clean action bar layout, shorter unit frames and cleaner nameplates, and the game's own damage meter stays hidden.",
                    "The XP bar is never wider than the main action bar.",
                },
            },
            {
                type = "fixed",
                items = {
                    { "An error from nameplates on WoW Forever.", only = "forever" },
                    "An error from the chat rail at login.",
                    "Tooltip boxes in the settings showing white.",
                    "Overlapping pieces in the settings preview.",
                },
            },
        },
    },
    {
        version = "3.0.0",
        date = "2026-11-08",
        title = "Looks, a new settings window and a polish pass on everything",
        sections = {
            {
                type = "added",
                items = {
                    "Pick a look: ZacUI, Classic WoW UI, WoW Forever (on Forever) or Blizzard style. Each one draws the unit frames, nameplates, action bars, buffs and windows in that style, and starts out looking like the real thing.",
                    "Classic WoW UI: the original player, target and target-of-target frames with round portraits, the original action buttons and the gryphons at the ends of the main bar.",
                    "WoW Forever and Blizzard style: the client's own frame, button, bar and nameplate art.",
                    "The look cards on the Style page and in the setup wizard preview the style before you reload.",
                    "Chat: an icon rail beside the chat with friends (and how many are online), copy chat, chat settings and scroll to newest. Guild, durability, channels and the chat menu can be added. Everything can be turned off.",
                    "Chat: a polished style for the panel, tabs and text, on by default and one switch to turn off.",
                    { "Damage meter: on WoW Forever and Retail, the game's own meter is used by default under the Forever and Blizzard looks. The Meter page lets you pick either one.", only = { "forever", "retail" } },
                    "Damage meter: a Classic-style meter for the Classic look.",
                    "Quests: hand-in and accept for you (never picks a reward or pays gold), objective and quest-complete sounds, progress told to your party, and the quest tracker hidden in raids.",
                    "Alerts: entering and leaving combat, group members dying, the instance reset line, and the screenshot text hidden.",
                    "Reminders for no pet, a pet on passive, nothing tracked, and low mana on a ready check.",
                    "A junk window listing your cheapest items to delete when your bags are full.",
                    "Character stats on screen, cursor rings, a target distance readout, and clock, coordinates, XP and supplies blocks for the chat bar.",
                    "Repair from guild funds, the skill a herb or ore node needs on its tooltip, and item level and BoE on gear in your bags.",
                    "Game art settings for the action bars: the gryphons and the bar frame can be turned on or off per bar.",
                },
            },
            {
                type = "changed",
                items = {
                    "A new settings window: bigger, with a sidebar, search, a pinned page title, banded rows and new round switches and sliders.",
                    "Turning a part on or off from the sidebar uses a small switch.",
                    "Unit frames, nameplates, action bars, buffs, consumables and buff reminders were reworked to a cleaner, sharper look under the ZacUI look.",
                    "Dragging things in the settings preview is much more accurate: pieces follow the cursor exactly, snapping only grabs nearby pieces, icons swap at the right moment and Escape cancels a drag.",
                    "Damage meter: the header no longer cuts off the name, mode tiles read in full on narrow windows, and the breakdown is now an easy-to-read table.",
                    "Icons are cropped a little more so the game's icon border never shows.",
                    "Bag bar and micro menu start where the game's own sat on a fresh install.",
                },
            },
            {
                type = "fixed",
                items = {
                    "Text on unit frames keeps its black outline.",
                    "Frames you had placed or sized are never moved or resized by an update.",
                    "A Classic setup no longer picks up ZacUI-look styling.",
                    "Several checkboxes that could not be turned off now can.",
                    "Reset ZacUI now opens the setup wizard afterwards.",
                    "A minimap button error some players saw at login.",
                },
            },
        },
    },
    {
        version = "2.0.0",
        date = "2026-11-01",
        title = "Changelog",
        sections = {
            {
                type = "added",
                items = {
                    "A changelog. What is new in each version shows here, and once after you update.",
                },
            },
        },
    },
}

-- A TAGGED LINE WRITES ITSELF AS ITS TEXT. The release notes are made by
-- joining each line onto "- " (the release tool, outside the addon), and a
-- tagged line is a table: joined as it stood, 3.0.12's and 3.0.13's notes
-- could not be written and those versions were never packaged. With this a
-- tagged line joins as its words, wherever lines are joined into text.
local LINE = {
    __concat = function(a, b)
        if type(a) == "table" then a = a[1] or "" end
        if type(b) == "table" then b = b[1] or "" end
        return a .. b
    end,
    __tostring = function(t) return t[1] or "" end,
}
for _, entry in ipairs(ns.CHANGELOG) do
    for _, sec in ipairs(entry.sections or {}) do
        for _, item in ipairs(sec.items or {}) do
            if type(item) == "table" and getmetatable(item) == nil then setmetatable(item, LINE) end
        end
    end
end
