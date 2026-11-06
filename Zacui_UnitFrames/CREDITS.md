# ZacUF - Credits and Third-Party Code

ZacUF is written by Zac. Everything below is someone else's work that ZacUF
bundles or builds on. If you find something here that is miscredited or
that should not be included, please raise it and it will be corrected or
removed.

---

## Bundled libraries

These ship inside `ZacUF/libs/` unmodified. Each retains its own copyright
and licence; the licence text in each file is authoritative.

| Library | Author | Licence |
|---|---|---|
| LibStub | WowAce community | Public Domain |
| CallbackHandler-1.0 | WowAce community | Ace3 licence (BSD-style), see `libs/Ace-3.0/LICENSE.txt` |
| ChatThrottleLib | Mikk | Public Domain |
| LibHealComm-4.0 | Shadowed | Ace3-style licence, see the header in `LibHealComm-4.0.lua` |

LibHealComm-4.0 is what makes cross-client incoming-heal attribution work:
it is a comms protocol, so every client in the group has to be speaking the
same one. That protocol is Shadowed's design.

---

## LibHealPredict-1.0

`libs/LibHealPredict-1.0/` is written for ZacUF, not imported. It is a
comms-free alternative to LibHealComm that derives per-caster incoming
heals from native Blizzard APIs alone. It is kept in `libs/` because it is
structured as a LibStub library and could be used by other addons, not
because it came from elsewhere.

---

## Optional integrations

LibSharedMedia-3.0 (Elkano, LGPL v2.1) is used, when present, to read fonts
and textures shared by other addons. It is not bundled.

---

## Game data

World of Warcraft is a trademark of Blizzard Entertainment, Inc. ZacUF is
an unofficial fan addon and is not affiliated with or endorsed by Blizzard
Entertainment.
