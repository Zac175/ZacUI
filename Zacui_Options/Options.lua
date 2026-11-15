-- Options - ZacUI's settings, loaded on demand.
-- Part of ZacUI; this folder's TOC sets the load order (this file first).
--
-- The game loads this addon the first time the settings are asked for
-- (ZacUI's Config_Base, ns.LoadOptions): /zui, the minimap button, a
-- "settings" entry in any menu, the tour. Until then none of the window,
-- its search, its preview strip or the pages is read - 1.4 MB of Lua,
-- about a tenth of what a login or a reload used to read and compile.
--
-- Every file here writes into ZacUI's own namespace, exactly as it did
-- when it sat in the main addon or in its part.

local ns = _G.ZacUI
if not ns then return end

-- the door (Config_Base) hands on to what the files below define
ns.optionsLoaded = true
