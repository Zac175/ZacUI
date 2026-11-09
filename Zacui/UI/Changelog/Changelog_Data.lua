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
