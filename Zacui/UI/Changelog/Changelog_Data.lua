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
