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

local ADDON_NAME, ns = ...

ns.CHANGELOG = {
    {
        version = "3.0.10",
        date = "2026-11-12",
        title = "A world-buff switch for the buff remover, and a smoother warrior HUD",
        sections = {
            {
                type = "added",
                items = {
                    "Buff remover: an \"Only while world buffs are out\" switch. With no world buff on you nothing ticked is cancelled; once you have one, everything ticked goes as usual.",
                    "Buff remover: while that switch is on, a buff can be marked \"even with no WBs\" so it always goes. Salvation while tanking always goes too.",
                    "Hesitation prompts: in execute range, Whirlwind is marked ahead of Execute when there are enough mobs for it. It has its own switch.",
                    "Hesitation prompts: a Glide option. The icons over your target fade, slide and grow instead of jumping.",
                    "With Readycheck installed, its route tracker can sit along the top of the chat box in a raid, above the raid frames. The switch is on the Chat page under \"In a raid\", with two more for how gear swaps show on it.",
                },
            },
            {
                type = "changed",
                items = {
                    "Warrior HUD: icons grow smoothly, and an icon that leaves keeps its place for a moment so the row does not jump twice.",
                    "Every window's resize corner is one solid corner that lights up under the mouse and while you drag it.",
                },
            },
            {
                type = "fixed",
                items = {
                    "A first login no longer ticks buffs for removal on a warrior, changes attack macros or makes a macro called \"dummy\".",
                    "Hesitation prompts: an ability that comes off cooldown during the global cooldown counts as ready.",
                    "Hesitation prompts: Arms warriors get Mortal Strike where Bloodthirst would be.",
                    "Hesitation prompts: Whirlwind was rated too high with a fast main-hand weapon.",
                    "The map window's title bar no longer shows a lighter slab behind it.",
                    "Auction house: the line saying what you bought no longer flickers while buying stacks.",
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
                    "Buff remover: going to Defensive Stance and straight back no longer cancels Salvation.",
                    "Edit Mode: a small slip of the mouse while clicking a frame no longer moves it.",
                    "The auction buying window keeps its size when you press Buy.",
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
        sections = {
            {
                type = "added",
                items = {
                    "Every class HUD starts on your spec's own list, with separate lists for Classic Era, TBC and WoW Forever.",
                    "Warrior, priest and paladin HUDs follow your spec too. Characters that already use them keep exactly what they had.",
                    "Warrior HUD: a row for debuffs on your target, such as Sunder Armor stacks and Demoralizing Shout.",
                    "Priest HUD: a row for your own buffs. Paladin HUD: a row for your judgements on the target.",
                    "A \"Show spells you haven't learned yet\" option on every class HUD.",
                    "A first class HUD for Retail, for all classes. It is off until you switch it on and has not been tested in the game yet.",
                    "A filter for buffs and debuffs on unit frames and on the nameplates' simple debuff row: pick what shows, add spells to always or never show, and set limits. Your old settings carry over.",
                    "Edit Mode has a bar across the top, and the box you click shows its own actions. Class HUDs show their real icons while you place them.",
                    "The raid mods' boxes stay out of Edit Mode until you press \"Raid mods\" on the bar.",
                    "Bags can be split into groups by kind with the Groups button. New items get a gold edge, and a small bar shows how full your bags are.",
                    "The auction buy window shows the item's quality and a progress bar, and can list every auction it will buy.",
                    "TBC raid mods are filled out for all nine raids, Karazhan to Sunwell: cast bars with a KICK mark, debuff lists, tank icons, stand-in-it alarms and many more boss timers.",
                    "Buff reminders on TBC: Commanding Shout, Earth Shield and the Master Soulstone. Fear Ward for priests who know it.",
                    "Buff reminders can be limited to TBC's raids.",
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
                    "The Darkmoon Faire mark on the damage meter hides while you have the fortune yourself, and is offered on Classic Era only.",
                    "The \"What's New\" window and the scroll bars match Readycheck's.",
                    "The map and the skinned game windows have the same flat header as the rest of ZacUI.",
                    "Edit Mode is easier to use: a line under the bar says how it works, the list shows what you can move first, and the box you click only offers what it can do.",
                    "Windows outside the settings window are a lighter grey instead of near-black.",
                    "The auction buying window is much smaller.",
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
                    "Retail: the backpack icon was invisible, bag icons had black corners, and a gold line crossed the character window.",
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
                    "Action bar icons under the live style on WoW Forever fill their slots again.",
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
                    "The auction house buy window is redesigned: the item with its icon, what you've bought and spent, and one clear price button.",
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
                    "Classic WoW UI on WoW Forever: the minimap gets the 2004 grey ring and zone bar, the character pane and spellbook the 2004 look, and the bag bar and menu buttons their 2004 art.",
                    "Nameplates: the hesitation icons sit above the mob's name instead of on it, and Demoralizing Shout shows with your other debuffs under the bar.",
                    "The changelog window is more compact.",
                    "Classic WoW UI on WoW Forever: the game's own windows (character, spellbook, vendors, quests, mail, bank, friends, options, popups, tooltips and more) wear the 2004 border, gold title, round close button, old tabs and old buttons.",
                    "Known issue: a few windows may still not fully match the look you picked (the world map keeps ZacUI's own frame). Keep sending screenshots.",
                },
            },
            {
                type = "fixed",
                items = {
                    "Buffs and the bag bar were not getting ZacUI's look on Era and TBC.",
                    "A second close button on the loot window on Era and TBC.",
                    "Square corners on the nameplate target glow.",
                    "The colour picker's colour wheel was blank on Era and TBC, and the picker could open behind the settings.",
                    "The mount button on Era and TBC used a call that only works on WoW Forever and never mounted you; it uses your mount from your bags again.",
                    "The auction house buy window: the Buy button no longer covers the text, and it shows the amount and price again.",
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
                    "An error from nameplates on WoW Forever.",
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
                    "Damage meter: on WoW Forever and Retail, the game's own meter is used by default under the Forever and Blizzard looks. The Meter page lets you pick either one.",
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
