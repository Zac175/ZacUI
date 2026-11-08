-- Tutorial_Hints - the one-time hints: a thing ZacUI says or shows once
-- per account (the first Edit Mode entry, the first part turned off, the
-- setup's own tips), written down so it is never said twice, and a reset
-- that lets every hint come back.
-- Part of ZacUI; load order is set by the TOC (after Tutorial_Core).
--
--   ns.Hints.Once(id, fn)   runs fn the first time only; true when it ran
--   ns.Hints.Seen(id)       has this hint been shown
--   ns.Hints.Mark(id)       count it as shown without showing anything
--   ns.Hints.Reset()        every hint may show again (and the welcome)
--   ns.Hints.List()         the ids seen, sorted (diagnostics, tests)
--   ns.Hints.Say(id, text)  one line in chat, once
--   ns.Hints.Callout(id, target, text, side)
--                           a box with an arrow at `target`, once (Okay)
--
-- Bookkeeping, account-wide, outside every profile (not in Core_Profiles'
-- SECTIONS): ZacUIDB.hints = { [id] = true }.

local ADDON_NAME, ns = ...

local Print = ns.Print

local Hints = {}

local function DB()
    if type(ZacUIDB) ~= "table" then return nil end
    if type(ZacUIDB.hints) ~= "table" then ZacUIDB.hints = {} end
    return ZacUIDB.hints
end

function Hints.Seen(id)
    local d = DB()
    return d ~= nil and d[id] == true
end

function Hints.Mark(id)
    local d = DB()
    if d and id then d[id] = true end
end

function Hints.Once(id, fn)
    if not id or Hints.Seen(id) then return false end
    local d = DB()
    if not d then return false end
    d[id] = true
    if type(fn) == "function" then
        local ok, err = pcall(fn)
        if not ok and Print then Print("hint '" .. tostring(id) .. "': " .. tostring(err)) end
    end
    return true
end

function Hints.Say(id, text)
    return Hints.Once(id, function() if Print then Print(text) end end)
end

-- A hint that points at the thing it is about (UI.Callout, UIF_Dialogs):
-- once per account, counted when the player presses Okay (a callout put
-- away because its thing hid is not an answer - it may show again).
function Hints.Callout(id, target, text, side)
    if not id or Hints.Seen(id) then return false end
    local UI = ns.UI
    if not (UI and UI.Callout) then return false end
    return UI.Callout(target, { key = id, text = text, side = side,
        onOkay = function() Hints.Mark(id) end }) and true or false
end

-- Every hint comes back, and so does the first-run welcome (its own
-- bookkeeping lives in Tutorial_Core).
function Hints.Reset()
    if type(ZacUIDB) ~= "table" then return end
    ZacUIDB.hints = {}
    if ns.Tutorial and ns.Tutorial.Reset then ns.Tutorial.Reset() end
end

function Hints.List()
    local out = {}
    local d = DB()
    if d then for id in pairs(d) do out[#out + 1] = id end end
    table.sort(out)
    return out
end

-- shared with later ZacUI files and the parts
ns.Hints = Hints
