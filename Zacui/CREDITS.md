# ZacUI - Credits and Third-Party Content

ZacUI is written by Zac. Everything below is someone else's work that
ZacUI bundles or builds on. If you find something here that is miscredited
or that should not be included, please raise it and it will be corrected or
removed.

---

## Bundled media

ZacUI's fonts are open-licence faces under the SIL Open Font License 1.1
(the licence is kept at `Media/Fonts/OFL.txt`):

| Font | File | Author |
|---|---|---|
| Red Hat Display (SemiBold) | `Media/Fonts/RedHatDisplay-SemiBold.ttf` | The Red Hat Project Authors |
| Barlow Semi Condensed (Black) | `Media/Fonts/BarlowSemiCondensed-Black.ttf` | The Barlow Project Authors (Jeremy Tribby) |
| Roboto Condensed (Bold) | `Media/Fonts/RobotoCondensed-Bold.ttf` | The Roboto Project Authors |

The bar textures, icons and interface textures in `Media` are made for
ZacUI.

Still bundled until their replacement lands: the voice callouts in
`Media/Naowh/Sounds/*.ogg` (Naowh UI), used by the aura and raid-mod
alerts.

---|---|
| `Media/Naowh/Fonts/Naowh.ttf`, `GothamNarrowUltra.ttf` | Naowh UI |
| `Media/Naowh/Sounds/*.ogg` | Naowh UI |
| `Media/Nameplates/Naowh.ttf` | Naowh UI |
| `Media/Nameplates/Melli.tga` | Melli, a widely redistributed nameplate/status bar texture |
| `Media/Nameplates/Numen.ttf` | Numen |

GothamNarrowUltra is a commercial typeface (Gotham, Hoefler & Co.). It is
included here because it arrived bundled with a UI pack; if ZacUI is ever
distributed publicly this file should be removed and replaced with a
freely-licensable font.

---

## Raid mods' sounds and shapes

ZacUI carries no raid sound files. Raid callouts are spoken by the game's
own text-to-speech, alert sounds are the game's own interface sounds
(`Zacui/Core/Core_Sounds.lua`), and the rings, circles, glows and arrow in
`Zacui_RaidMods/Media/Own` were drawn for ZacUI. The raid packs' old media folder is no
longer used; settings that still name its files are read through
`Core_Sounds.lua`.

---

## OpenMap (Ji and the OpenMap contributors) - the `Zacui_WorldMap` part

The seamless world map in `Zacui_WorldMap` is **OpenMap v0.7.5-beta**
(https://github.com/openmap-world/openmap), carried inside ZacUI with the
folder renamed, the TOC retargeted at Classic Era and WoW Forever, and the
chat prefix and settings-page title changed to ZacUI's. The engine, its
saved variables (`OpenMapDB`, `OpenMapCharDB`), its `_G.OpenMap` global and
its `/openmap` command are left as they are so addons that know OpenMap
keep working and a player's settings carry over.

OpenMap's code is **MIT licensed** - the licence is kept at
`Zacui_WorldMap/LICENSE.txt` and its in-game credits page (`Credits.lua`)
is unchanged. Its libraries (Ace3: AceConfig-3.0, AceGUI-3.0,
CallbackHandler-1.0, LibStub) are under `Zacui_WorldMap/LICENSES/`. The
map textures in `Zacui_WorldMap/Media` are cut from the game's own map
art (Blizzard Entertainment's; see `Media/Textures/NOTICE.md`), with the
hand-painted sea, blank-land and dungeon art by Santiago Reyes as credited
there. This part may be shared, under those terms, with this notice and
the licence file kept.

---

## Bartender4 (Nevcairiel)

ZacUI does **not** bundle, fork or modify Bartender4. An embedded copy was
tried and has been removed entirely - `Zacui/Bartender4/` no longer exists
and nothing in the `.toc` refers to it. Bartender4 runs as its own addon,
owns its own `Bartender4DB`, and ZacUI only restyles the frames it draws.

> Copyright (c) 2009-2017, Hendrik "Nevcairiel" Leppkes
> < h.leppkes at gmail dot com > - **All rights reserved.**

---

## Addons ZacUI skins

ZacUI restyles these by reading their public frames at runtime. It does not
bundle, fork or modify any of their code, and each remains installed and in
charge of its own settings and saved variables.

| Addon | Author | ZacUI module |
|---|---|---|
| Baganator | Plusmouse | `Modules/AddOns/Skin_Baganator.lua` |
| Syndicator | Plusmouse | `Modules/AddOns/Skin_Syndicator.lua` |
| Auctionator | Auctionator team | `Modules/AddOns/Skin_Auctionator.lua` |
| Prat-3.0 | Prat team | `Modules/AddOns/Skin_Prat.lua` |
| Bartender4 | Nevcairiel (Hendrik Leppkes) | `Modules/AddOns/Skin_Bartender4.lua` |

Bartender4 is licensed "All rights reserved". Skinning it from the
outside is fine; copying or bundling any part of it is not.

---

## Bundled libraries

Shipped unmodified; each keeps its own copyright and licence, and the
licence text in each file (or beside it) is authoritative.

| Library | Author | Licence | Where |
|---|---|---|---|
| LibStub | WowAce community | Public domain | `Zacui/Libs`, `Zacui_RaidMods/Libs`, `Zacui_RaidTools/Libs` |
| CallbackHandler-1.0 | the Ace3 team | Ace3 licence (BSD-style) | `Zacui/Libs`, `Zacui_RaidMods/Libs`, `Zacui_RaidTools/Libs` |
| LibSharedMedia-3.0 | Elkano | LGPL v2.1 | `Zacui_RaidTools/Libs` |
| LibDataBroker-1.1 | Tekkub | Public domain | `Zacui/Libs` |
| LibDBIcon-1.0 | the LibDBIcon authors | see its project page | `Zacui/Libs` |
| LibCustomGlow-1.0 | Benjamin Staneck | MIT (`LICENSE-LibCustomGlow.txt`) | `Zacui_RaidMods/Libs` |
| LibRangeCheck-3.0 | the WoWUIDev community | MIT (`LICENSE-LibRangeCheck.txt`) | `Zacui_RaidMods/Libs` |

The unit frames' libraries are listed in `Zacui_UnitFrames/CREDITS.md`.

---

## Formats ZacUI speaks

These are other projects' formats that ZacUI reads and writes so it works
with what players already have. ZacUI's code for them is its own; none of
these projects' code is bundled.

- **Auras** (`Zacui_Auras`): the aura engine runs auras in the WeakAuras
  display format and imports and exports WeakAuras strings, so existing
  auras keep working. WeakAuras is by the WeakAuras team.
- **Compressed strings and sync messages**: byte-compatible with
  LibDeflate's DEFLATE and its print and addon-channel encodings
  (Haoqian He) and with LibSerialize's layout (Ross Nichols), and framed
  for the addon channel the way AceComm-3.0 frames long messages, so other
  players' clients can read what ZacUI sends.

---

## Optional integrations

LibSharedMedia-3.0 (Elkano, LGPL v2.1) is used to publish ZacUI's fonts,
textures and sounds so WeakAuras, Plater, Details, Bartender4 and anything
else that reads LibSharedMedia can use them.

---

## Game data

World of Warcraft is a trademark of Blizzard Entertainment, Inc. ZacUI is
an unofficial fan addon and is not affiliated with or endorsed by Blizzard
Entertainment.
