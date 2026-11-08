-- The "What's new" window's notes (Map/News.lua). Empty in ZacUI: the engine's own version
-- history is OpenMap's (CHANGELOG.md upstream), not this UI's, so the window shows only the
-- Credits page and no update notice is printed at login.

local _, ns = ...
if ns.flavorOff then return end   -- (ZacUI: not on this game version, Core.lua: nothing here loads)

ns.MapChangelog = {}
