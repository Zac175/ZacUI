-- Core_Registry - the module table, the run order and the load-on-demand
-- registry. Every skin file adds itself to Modules; this file decides
-- WHEN each one runs and how the config window groups them.
-- Part of ZacUI; load order is set by the TOC.

local ADDON_NAME, ns = ...

local Print = ns.Print

-- ============================================================
-- LoD REGISTRY
-- ============================================================
-- Blizzard windows and third-party addons alike can load long after we
-- do. RegisterLoD runs the skin NOW if its addon is already up, and
-- otherwise parks it against the addon's ADDON_LOADED (drained in
-- Boot_Events). Every skin body must be idempotent either way.
local LOD = {}
local function RegisterLoD(addonName, fn)
    local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    if isLoaded and isLoaded(addonName) then
        local ok, err = pcall(fn)
        if not ok then Print(addonName .. " skin failed: " .. tostring(err)) end
    else
        LOD[addonName] = fn
    end
end

-- ============================================================
-- MODULES
-- ============================================================
local Modules = {}

-- RUN ORDER. Three rules hold it together:
--   * fonts and hooks lead - later modules inherit both.
--   * sweep and watcher trail - the classifier should meet a UI that
--     the named modules have already claimed, so its generic rules only
--     ever handle the long tail.
--   * everything between is independent; alphabetical within a group
--     purely so the list stays readable.
local MODULE_ORDER = {
    "fonts", "hooks",
    -- HUD
    "minimap", "chat", "tooltip", "auras", "bars", "actionbars", "unitframes",
    "castbar", "nameplates", "meter", "qol", "tracker",
    -- Windows
    -- merchantwin / spellbookwin are the rebuilt windows; they sit after
    -- the skins of the Blizzard windows they cover.
    -- Every "...win" key is a rebuilt ZacUI window; each sits right after
    -- the skin of the Blizzard window it covers.
    "dialogs", "gamemenu", "mail", "mailwin", "mailtabswin", "merchant", "merchantwin",
    "character", "paperdollwin", "petpaperdollwin", "chartabswin", "skillswin", "reputationwin",
    "honorwin", "inspect", "inspectwin",
    "spellbook", "spellbookwin", "questlog", "questlogwin",
    "friends", "friendswin", "whowin", "ignorewin", "raidwin", "friendtabswin", "bags", "bank",
    "trade", "tradewin", "loot", "lootwin", "lootroll", "gossip", "gossipwin", "questdialogwin",
    "taxi", "taxiwin", "readycheck", "addons", "guild", "guildwin", "pvp", "battlefieldwin", "scorewin",
    "inventory", "tray", "auctionhouse",
    -- worldmap SKINS the map; maps REBUILDS how it behaves. In that
    -- order, because the skin strips chrome the map layer then moves.
    "trainer", "trainerwin", "worldmap", "maps", "misc", "options", "panels",
    "talentswin", "tradeskillwin", "craftwin", "macroswin", "lfgwin",
    -- Generic passes, last by design
    "sweep", "watcher",
}

-- WHICH PART OWNS A MODULE. Modules whose code lives in one of the part
-- addons (see the TOC) are listed here, so the Modules page can say why
-- a tick box does nothing when that part is off in the AddOns list.
-- Everything not listed is in this addon.
local MODULE_ADDON = {}
local function Part(addon, ...)
    for i = 1, select("#", ...) do MODULE_ADDON[(select(i, ...))] = addon end
end
Part("Zacui_Bars", "bars")
Part("Zacui_Bags", "inventory", "auctionhouse")
Part("Zacui_Nameplates", "nameplates")
Part("Zacui_Meter", "meter")
Part("Zacui_Maps", "maps")
Part("Zacui_QoL", "qol")
Part("Zacui_Windows",
    "merchantwin", "spellbookwin", "talentswin", "tradeskillwin", "craftwin", "trainerwin",
    "paperdollwin", "petpaperdollwin", "chartabswin", "skillswin", "reputationwin", "honorwin",
    "inspectwin", "questlogwin", "mailwin", "mailtabswin", "friendswin", "whowin", "ignorewin",
    "raidwin", "friendtabswin", "guildwin", "tradewin", "lootwin", "gossipwin", "questdialogwin",
    "taxiwin", "battlefieldwin", "scorewin", "macroswin", "lfgwin")

-- NAV GROUPS: what the config sidebar shows, in the order it shows it.
-- Kept next to MODULE_ORDER on purpose - a module added above without a
-- home here is invisible in the UI, and the audit in Config_Base prints
-- exactly that if the two ever drift.
local MODULE_GROUPS = {
    {
        key = "hud", label = "HUD",
        desc = "The elements that live on screen while you play.",
        modules = {
            { key = "minimap",    label = "Minimap",      desc = "A square minimap in one ZacUI frame: zone name header, friends / clock / guild footer, coordinates, and the mail, tracking and battleground icons tucked into its corners. Wheel zoom." },
            { key = "tray",       label = "Button tray",  desc = "Sweeps every addon's minimap button into one movable bar with a flyout tray. Replaces ButtonStash." },
            { key = "chat",       label = "Chat",         desc = "Chat windows on dark panels with flat tabs, plus a bar under the docked chat: channel buttons, a whisper counter, and the numbers you pick (durability, bag space, gold, latency...). The edit box opens in that bar. Fine-tune on the Chat page." },
            { key = "tooltip",    label = "Tooltips",     desc = "Every tooltip in the game, plus a movable anchor." },
            { key = "auras",      label = "Buffs",        desc = "Buff, debuff and weapon-enchant buttons." },
            { key = "bars",       label = "Action bars",  desc = "ZacUI's own action bars: ten bars, pet and stance bars, bags, micro menu and XP strip, each placed, scaled, paged and faded from the Action bars page. Replaces Bartender4 and imports its settings. Stands down while Bartender4 is enabled." },
            { key = "actionbars", label = "Action bars (Blizzard)", desc = "Skins Blizzard's action buttons, pet and stance bars, the bar art and the micro menu. Only visible when the ZacUI action bars are off." },
            { key = "unitframes", label = "Unit frames",  desc = "Player, target, pet, party and their status bars." },
            { key = "castbar",    label = "Cast bars",    desc = "Player, target and mirror (breath / fatigue) bars." },
            { key = "nameplates", label = "Nameplates",   desc = "ZacUI's own nameplate engine: health, cast bars, auras and threat colors. Replaces Plater; defaults are the ported Naowh profile. Fine-tune on the Nameplates page." },
            { key = "meter",      label = "Damage meter", desc = "ZacUI's own damage meter and threat display. Replaces Details! and TinyThreat; windows, skin and formulas are the ported Naowh setup. Fine-tune on the Damage meter page." },
            { key = "qol",        label = "Quality of life", desc = "Auto sell junk, auto repair, gossip skipping, faster looting, whisper invites, error dismounting, screen effect removal and sound muting. Replaces Leatrix Plus; defaults are your audited Leatrix setup. Fine-tune on the Quality of life page." },
            { key = "tracker",    label = "Quest tracker",desc = "The objectives watch frame." },
        },
    },
    {
        key = "windows", label = "Windows",
        desc = "Panels that open over the world.",
        modules = {
            { key = "paperdollwin", label = "Character sheet", desc = "ZacUI's own character sheet: gear in two flat columns with quality borders, item levels, wear and cooldowns, a rotatable and zoomable 3D model, two stat cards you choose, average item level, durability and helm / cloak toggles. Every click works like Blizzard's slots, including right-click to use." },
            { key = "petpaperdollwin", label = "Pet",     desc = "ZacUI's Pet page: your pet's name, level and family, a rotatable and zoomable model, and for hunters happiness, loyalty, experience and training points, plus the same stats and resistances as Blizzard's pet sheet." },
            { key = "chartabswin", label = "Character tabs", desc = "The Character / Pet / Reputation / Skills / Honor tabs as full-size ZacUI tabs, flush under the character window. They click Blizzard's own tabs underneath, so switching page still works in combat." },
            { key = "inspectwin", label = "Inspect",      desc = "A wider ZacUI inspect window: the player's gear with item names and levels, their model, average item level, and their honor page." },
            { key = "skillswin",  label = "Skills",       desc = "ZacUI's Skills page: searchable skill list with collapsible groups, flat rank bars and Blizzard's unlearn prompt." },
            { key = "reputationwin", label = "Reputation", desc = "ZacUI's Reputation page: searchable factions with Hide inactive / At war filters, standing bars, and the At war / Inactive / Show as experience bar options." },
            { key = "honorwin",   label = "Honor",        desc = "ZacUI's Honor page: rank, rank progress, and kills and honor for today, yesterday, this week, last week and lifetime." },
            { key = "talentswin", label = "Talents",      desc = "ZacUI's own talent window: all three trees side by side with prerequisite lines, dual-spec tabs with Activate, and preview Learn / Reset. Click to learn, right-click to remove a preview point, shift-click to link." },
            { key = "tradeskillwin", label = "Professions", desc = "A wide, searchable recipe list and detail pane for every profession, with a tab for each profession you know (Engineering, Alchemy, Cooking, First Aid...), Have materials / Skill-ups filters and Create / Create all." },
            { key = "craftwin",   label = "Enchanting",   desc = "The same wide profession window for Enchanting and Beast Training." },
            { key = "character",  label = "Character (Blizzard)", desc = "Skins Blizzard's character window and its pages. Mostly covered by the ZacUI pages above; still styles anything they leave." },
            { key = "inspect",    label = "Inspect",      desc = "The inspect window." },
            { key = "spellbookwin", label = "Spellbook",  desc = "ZacUI's own spellbook: every spell in one searchable list, filtered by school, with cooldowns, an all-ranks toggle and pet autocast. Click to cast, drag to your bars. In combat the list stays put (spells still cast) and unlocks when the fight ends." },
            { key = "spellbook",  label = "Spellbook (Blizzard)", desc = "Skins Blizzard's spellbook. Only visible when the ZacUI spellbook is off." },
            { key = "inventory",  label = "Combined bag", desc = "One window for every bag, with search, sorting and quality borders. Replaces Blizzard's one-frame-per-bag layout, and stands down if another bag addon is loaded." },
            { key = "bags",       label = "Bags (Blizzard)", desc = "Skins Blizzard's separate bag frames. Only does anything when the combined bag is off." },
            { key = "bank",       label = "Bank",         desc = "Bank frame, bag slots and purchase prompt." },
            { key = "questlogwin", label = "Quest log",   desc = "ZacUI's own quest log: quests down the left in collapsible zones with level tags, a search box and Unfinished / Group filters, and the selected quest on the right with objectives, description and rewards. Abandon, share and track work exactly as Blizzard's do." },
            { key = "questlog",   label = "Quest log (Blizzard)", desc = "Skins Blizzard's quest log. Only visible when the ZacUI quest log is off." },
            { key = "gossip",     label = "Quests & gossip", desc = "Quest pages, gossip, and the parchment text fix." },
            { key = "merchantwin", label = "Merchant",    desc = "ZacUI's own merchant window: every item in one searchable list with usable / affordable filters, buyback, repair and sell-junk buttons. Blizzard's clicks and purchase prompts all still apply." },
            { key = "merchant",   label = "Merchant (Blizzard)", desc = "Skins Blizzard's vendor window. Only visible when the ZacUI merchant window is off." },
            { key = "mailwin",    label = "Mailbox",      desc = "ZacUI's own inbox: every mail in one searchable list with money, items and COD filters, a throttled Collect all, and right-click to empty one mail. C.O.D. mail is never paid automatically." },
            { key = "mailtabswin", label = "Mail tabs", desc = "The Inbox / Send Mail tabs as ZacUI tabs, flush under the mailbox." },
            { key = "mail",       label = "Mail (Blizzard)", desc = "Skins Blizzard's mail window: the send page, the open letter, and the inbox when the ZacUI mailbox is off." },
            { key = "tradewin",   label = "Trade",        desc = "ZacUI's own trade window: both sides' items as rows with quality borders, their money, who has accepted, and Trade / Cancel. Your gold, silver and copper boxes stay Blizzard's (the game locks them), framed into the window." },
            { key = "trade",      label = "Trade (Blizzard)", desc = "Skins Blizzard's trade window. Only visible when the ZacUI trade window is off." },
            { key = "loot",       label = "Loot",         desc = "Loot window and the master looter frame." },
            { key = "lootroll",   label = "Loot rolls",   desc = "Group loot rolls rebuilt as compact ElvUI-style bars: item icon, quality-colored timer, need/greed/pass with live roll counts and roller tooltips. Movable under Movers; /zui testroll shows fakes to place them by." },
            { key = "friendswin", label = "Friends",      desc = "ZacUI's own friends list: search, online-only filter, class colours, status, zone and note, with Blizzard's right-click menu." },
            { key = "whowin",     label = "Who",          desc = "ZacUI's own /who page: type a query and press Enter, sort by any column, then whisper, invite or add the player as a friend." },
            { key = "guildwin",   label = "Guild roster", desc = "ZacUI's own guild roster: search, online-only filter, MOTD, notes and officer notes, last online. Clicking a member opens Blizzard's member panel." },
            { key = "ignorewin",  label = "Ignore list",  desc = "A searchable ignore list with Ignore Player and Remove buttons." },
            { key = "raidwin",    label = "Raid",         desc = "The eight raid groups as flat cards: drag members between groups, right-click for the raid menu, plus Ready Check, All Assist, Raid Info and Convert." },
            { key = "friendtabswin", label = "Social tabs", desc = "The Friends / Who / Guild / Raid tabs and the Friends / Ignore tabs as full-size ZacUI tabs. They click Blizzard's own tabs underneath, so switching page still works in combat." },
            { key = "lfgwin",     label = "Group finder", desc = "ZacUI's own Looking For Group window: list your group for any mix of activities with roles and a comment, or browse listings with category and activity filters, search and solo / group chips. Whisper and invite work like Blizzard's." },
            { key = "battlefieldwin", label = "Battlemaster", desc = "The battlemaster window: instance list with queue status, the battleground's description, and Join / Join as group / Cancel through Blizzard's own buttons." },
            { key = "scorewin",   label = "Scoreboard",   desc = "The battleground scoreboard: sortable columns including each battleground's own stats, All / Alliance / Horde filter, name search, class and faction colours, your row highlighted, winner banner and a Leave button." },
            { key = "friends",    label = "Social (Blizzard)", desc = "Skins Blizzard's social window: the raid tab, ignore list and anything the ZacUI pages leave." },
            { key = "guild",      label = "Guild (Blizzard)", desc = "Guild control panel, member details and the guild bank." },
            { key = "pvp",        label = "PvP",          desc = "Battleground scoreboard, queue windows and the world state bar." },
            { key = "gossipwin",  label = "Gossip",       desc = "ZacUI's own gossip window: what the NPC says above one list of available quests, current quests and gossip options. Clicks, Goodbye and the X do exactly what Blizzard's do." },
            { key = "questdialogwin", label = "Quest dialogue", desc = "ZacUI's own quest pages: the NPC's quest list, the quest offer with objectives and rewards, the hand-in page with item counts, and the reward page where you pick your reward. Accept, decline, continue and complete go through Blizzard's own buttons." },
            { key = "lootwin",    label = "Loot",         desc = "ZacUI's own loot window: every slot in one list with quality borders, counts, quest marks and a Loot all button. Opens under the cursor like Blizzard's; master loot, bind prompts and shift / ctrl-click all still apply." },
            { key = "macroswin",  label = "Macros",       desc = "A searchable macro list and a full editor: icon picker, character counter, duplicate and unsaved-changes protection." },
            { key = "trainerwin", label = "Trainer",      desc = "ZacUI's own trainer window: every service in one searchable list with Blizzard's Available / Unavailable / Known filters, a detail pane with requirements and cost, and a Train all button that trains the next service you can afford with each click." },
            { key = "trainer",    label = "Trainer (Blizzard)", desc = "Skins Blizzard's trainer window and the talent-clear prompt. Only visible when the ZacUI trainer is off." },
            { key = "taxiwin",    label = "Flight master", desc = "ZacUI's own flight master window: a bigger flight map beside a searchable list of every place you can fly to, with zone, cost and stops. Hover a destination to see its route, click to fly; a Cheapest filter sorts by cost." },
            { key = "taxi",       label = "Flight map (Blizzard)", desc = "Skins Blizzard's flight map. Only visible when the ZacUI flight master window is off." },
            { key = "worldmap",   label = "World map",    desc = "World map, its chrome and the battlefield minimap." },
            { key = "maps",       label = "Maps",         desc = "Makes the map a movable, resizable window: unexplored areas revealed, flight points, dungeon entrances, spirit healers, zone crossings, coordinates and zone level ranges. Replaces Leatrix Maps." },
            { key = "gamemenu",   label = "Game menu",    desc = "The Esc menu and its buttons." },
            { key = "dialogs",    label = "Popups",       desc = "StaticPopups and shared dialog chrome." },
            { key = "readycheck", label = "Ready check",  desc = "The raid utility popups: ready check, the master looter picker and the role poll." },
            { key = "addons",     label = "Addon list",   desc = "The AddOn List window (Esc > AddOns): panel chrome, the four buttons, character dropdown, search box and its scroll bars." },
            { key = "options",    label = "Settings",     desc = "Blizzard's settings panel. Light touch by doctrine - it is already dark." },
            { key = "auctionhouse", label = "Auction house", desc = "Search, Sell and Cancel tabs with a price memory built from what you browse. Stands down if Auctionator is loaded." },
            { key = "panels",     label = "Talents & AH", desc = "Load-on-demand windows: talents, trade skills, crafting, auction house, macros." },
            { key = "misc",       label = "Odds and ends",desc = "Durability, tickets, help, the coin-flip and roll popups, and the rest of the long tail." },
        },
    },
    {
        key = "engine", label = "Engine",
        desc = "The generic passes. Turning these off leaves anything the named modules missed at Blizzard defaults.",
        modules = {
            { key = "fonts",   label = "Font system",  desc = "Applies your font face, size and outline to Blizzard's font objects." },
            { key = "hooks",   label = "Hooks",        desc = "Self-skinning hooks on scroll frames, dropdowns and tabs." },
            { key = "sweep",   label = "Login sweep",  desc = "One classifier pass over everything alive at login." },
            { key = "watcher", label = "Frame watcher",desc = "Classifies frames the moment they are born, so nothing appears unstyled." },
        },
    },
}

-- Reverse index: module key -> its group and metadata. Built once so the
-- config pages and the slash help can both answer "what is this module?"
-- without walking the tree.
local MODULE_INFO = {}
for _, group in ipairs(MODULE_GROUPS) do
    for _, m in ipairs(group.modules) do
        m.group = group.key
        MODULE_INFO[m.key] = m
    end
end

-- shared with later ZacUI files
ns.LOD = LOD
ns.MODULE_ADDON = MODULE_ADDON
ns.MODULE_GROUPS = MODULE_GROUPS
ns.MODULE_INFO = MODULE_INFO
ns.MODULE_ORDER = MODULE_ORDER
ns.Modules = Modules
ns.RegisterLoD = RegisterLoD
