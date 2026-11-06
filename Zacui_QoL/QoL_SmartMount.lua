-- QoL_SmartMount - one mount macro for every character. The macro named
-- below (default "Mount") is rewritten out of combat to use whatever
-- this character actually has: inside the Temple of Ahn'Qiraj a Qiraji
-- Resonating Crystal from the bags, anywhere else the best mount item
-- carried (epic before rare) or, for a paladin or warlock, the summon
-- spell. So the same key mounts on every character and nobody edits
-- the macro by hand again. Part of ZacUI; load order is set by the TOC.
--
-- COST. Nothing runs in combat. The bag events only set a flag; one
-- timer a second later reads the bags (five of them, once) and writes
-- the macro only when its text would change - EditMacro makes every
-- action bar redraw, so it is never called for nothing.
local ADDON_NAME = ...
local ns = _G.ZacUI
if not ns then return end

local Print = ns.Print
local QoL = ns.QoL
local DB = QoL.DB

local SM = {}
QoL.SmartMount = SM

local GetContainerNumSlots = C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
local GetContainerItemID = C_Container and C_Container.GetContainerItemID or GetContainerItemID
local GetItemInfo = GetItemInfo
local InCombatLockdown = InCombatLockdown

local AQ40_INSTANCE = 531
-- the five crystals; the bugs only work inside the temple
local QIRAJI = { [21218] = true, [21321] = true, [21323] = true, [21324] = true, [21176] = true }
-- the two classes whose mount is a spell (epic first, then the 60%)
local SPELL_MOUNTS = {
    PALADIN = { { "Summon Charger", 4 }, { "Summon Warhorse", 3 } },
    WARLOCK = { { "Summon Dreadsteed", 4 }, { "Summon Felsteed", 3 } },
}
local CLASS_MISC, SUBCLASS_MOUNT = 15, 5    -- GetItemInfo classID/subclassID of a mount item
-- Era never reclassified the old mounts: a Swift Palomino is still
-- "Miscellaneous / Junk" to GetItemInfo. So a mount is recognised by its
-- own Use line ("Summons and dismisses a rideable ...") read from a
-- hidden tooltip, with the subclass and a known-ID list as the fallback
-- for clients in other languages.
local KNOWN = {}
for _, id in ipairs({
    -- horses                 rams                      sabers
    5655, 5656, 5668, 2411,   5864, 5872, 5873,         8629, 8631, 8632,
    18776, 18777, 18778,      18785, 18786, 18787,      18766, 18767, 18902,
    12353, 12354,             13328, 13329,             12302, 12303, 13086,
    -- mechanostriders        wolves                    kodos
    8563, 8595, 13321, 13322, 1132, 5665, 5668,         15277, 15290, 15292, 15293,
    13326, 13327, 18772,      18796, 18797, 18798,      18793, 18794, 18795,
    18773, 18774,             12330, 12351,
    -- raptors                skeletal horses           raid / pvp / special
    8588, 8591, 8592, 8586,   13331, 13332, 13333,      13335, 19902, 19872,
    18788, 18789, 18790,      13334, 18791,             18241, 18242, 18243, 18244,
    13317, 17450,             17462, 17463, 17464,      18245, 18246, 18247, 18248,
                              17465,                    19029, 19030,
    -- mechanostrider mods, old colours
    17453, 17454, 17455, 17456, 17457, 17458, 17459, 17460, 17461,
}) do KNOWN[id] = true end

local scan
-- reads the item's tooltip once: is it a mount, and is it one of the
-- Ahn'Qiraj crystals (its text names the temple)
local function ScanTooltip(id)
    if not scan then
        scan = CreateFrame("GameTooltip", "ZacUIMountScanTooltip", UIParent, "GameTooltipTemplate")
        scan:SetOwner(UIParent, "ANCHOR_NONE")
    end
    scan:ClearLines()
    local ok = pcall(scan.SetHyperlink, scan, "item:" .. id)
    if not ok then return false, false end
    local mount, qiraji = false, false
    for i = 1, math.min(scan:NumLines() or 0, 10) do
        local fs = _G["ZacUIMountScanTooltipTextLeft" .. i]
        local t = fs and fs:GetText()
        if t then
            if t:find("rideable", 1, true) or t:find("Summons and dismisses", 1, true) then mount = true end
            if t:find("Qiraj", 1, true) then qiraji = true end
        end
    end
    return mount, qiraji
end
-- Returns isMount, isQirajiCrystal (BagMounts keeps the answer per id).
-- A crystal is known by its id, its name or its tooltip - whichever the
-- client gives - so a crystal never passes for an ordinary mount and
-- gets picked outside the temple.
local function Classify(id, name, classID, subclassID)
    local mount, mentionsQiraj = ScanTooltip(id)
    if KNOWN[id] or (classID == CLASS_MISC and subclassID == SUBCLASS_MOUNT) then mount = true end
    -- a crystal: its id, its name ("... Qiraji Resonating Crystal"),
    -- or a mount whose tooltip names the temple. "Qiraji" alone is
    -- not enough - AQ40 drops plenty of Qiraji things that are not
    -- mounts (Qiraji Lord's Insignia was picked as one)
    local qiraji = QIRAJI[id] or (name and name:find("Resonating Crystal", 1, true))
        or (mount and mentionsQiraj) or false
    if qiraji then mount = true end
    return mount, qiraji and true or false
end

local DEFAULTS = { enabled = true, macro = "Mount", create = true }

local function Cfg()
    local d = DB()
    if type(d.smartMount) ~= "table" then d.smartMount = {} end
    local c = d.smartMount
    for k, v in pairs(DEFAULTS) do if c[k] == nil then c[k] = v end end
    return c
end
SM.Cfg = Cfg

local function InAQ40()
    if not GetInstanceInfo then return false end
    local _, _, _, _, _, _, _, instanceID = GetInstanceInfo()
    return instanceID == AQ40_INSTANCE
end

-- Every mount item in the bags: { id, name, quality, qiraji }. What each
-- item id is, is worked out once a session (GetItemInfo and the tooltip
-- only for an id not seen before); a pass is then one id read per slot.
local itemInfo = {}        -- item id -> { name, quality, mount, qiraji }
local function BagMounts()
    local out = {}
    for bag = 0, 4 do
        local n = GetContainerNumSlots(bag) or 0
        for slot = 1, n do
            local id = GetContainerItemID(bag, slot)
            if id then
                local info = itemInfo[id]
                if not info then
                    local name, _, quality, _, _, _, _, _, _, _, _, classID, subclassID = GetItemInfo(id)
                    if name then
                        local mount, qiraji = Classify(id, name, classID, subclassID)
                        info = { name = name, quality = quality or 0, mount = mount, qiraji = qiraji }
                        itemInfo[id] = info
                    end
                end
                if info and info.mount then
                    out[#out + 1] = { id = id, name = info.name, quality = info.quality, qiraji = info.qiraji }
                end
            end
        end
    end
    return out
end

-- What this character should mount with right now: { kind = "item"|"spell", name, quality }
-- or nil. Inside AQ40 the crystal wins outright; elsewhere the fastest
-- thing carried or known.
function SM.Pick()
    local mounts = BagMounts()
    local inAQ = InAQ40()
    local best
    local function Consider(c)
        if not best or c.quality > best.quality then best = c end
    end
    for _, m in ipairs(mounts) do
        if m.qiraji then
            if inAQ then return { kind = "item", name = m.name, quality = 9 } end
        else
            Consider({ kind = "item", name = m.name, quality = m.quality })
        end
    end
    local _, class = UnitClass("player")
    for _, s in ipairs(SPELL_MOUNTS[class] or {}) do
        -- GetSpellInfo by name answers only for spells this character knows
        if GetSpellInfo(s[1]) then
            -- an item of the same quality beats the spell (no cast time)
            if not best or s[2] > best.quality then best = { kind = "spell", name = s[1], quality = s[2] } end
        end
    end
    return best
end

-- The macro by name, case-insensitive (an old "mount" is adopted rather
-- than doubled by a "Mount"); exact case wins when both exist. Returns
-- the index of the one this module writes and the indexes of any other
-- same-named macros.
-- The macro indices this character has on its 120 action slots, and
-- the slots each sits in: { [idx] = { slot, ... } }. From the shared
-- macro and slot maps, kept until either changes; read-only.
local barsMap, barsKey
function SM.OnBars()
    local key = ns.Macros.Version() .. ":" .. ns.ActionSlots.Version()
    if barsMap and barsKey == key then return barsMap end
    local out = {}
    for idx in pairs(ns.Macros.Names()) do
        local slots = ns.ActionSlots.Find("macro", idx)
        if slots then out[idx] = slots end
    end
    barsMap, barsKey = out, key
    return out
end

-- after this module's own macro or slot writes, read back fresh
local function Wrote()
    ns.Macros.Invalidate()
    ns.ActionSlots.Invalidate()
end

-- The macro of the configured name. Several may share it (the case
-- differs, or two were made): the one on this character's bars wins,
-- then the exact spelling, then the first. Returns mine, others.
function SM.FindMacro(name)
    name = name or Cfg().macro
    local want = string.lower(name or "")
    if want == "" then return 0, {} end
    local acc = MAX_ACCOUNT_MACROS or 120
    local nA, nC = GetNumMacros()
    local onBars = SM.OnBars()
    local names = ns.Macros.Names()
    local used, exact, first, all = nil, nil, nil, {}
    local function look(i)
        local n = names[i]
        if n and string.lower(n) == want then
            all[#all + 1] = i
            if onBars[i] and not used then used = i end
            if n == name and not exact then exact = i end
            if not first then first = i end
        end
    end
    for i = 1, nA or 0 do look(i) end
    for i = acc + 1, acc + (nC or 0) do look(i) end
    local mine = used or exact or first
    local others = {}
    for _, i in ipairs(all) do if i ~= mine then others[#others + 1] = i end end
    return mine or 0, others
end

-- Lines that mean "mount": a mount item or crystal used, a summon cast,
-- the dismount/stopmacro boilerplate. A macro made only of those is an
-- old mount macro the smart one replaces.
local MOUNT_WORDS = { "Qiraji Resonating Crystal", "Reins of", "Swift ", "Horn of the", "Whistle of",
    "Bridle", "Kodo", " Ram", "Mechanostrider", "Steed", "Palomino", "Stallion", "Raptor", "Wolf",
    "Warhorse", "Skeletal Horse", "Frostsaber", "Nightsaber", "Tiger", "Charger", "Deathcharger",
    "Dreadsteed", "Felsteed", "Battle Tank", "War Tiger" }
local function MountLine(line)
    line = line:gsub("^%s+", ""):gsub("%s+$", "")
    if line == "" then return true end
    local l = string.lower(line)
    if l:find("^#showtooltip") or l:find("^/dismount") or l:find("^/stopmacro") or l:find("^/run zacui.print") then return true end
    if l:find("^/use ") or l:find("^/cast ") then
        for _, w in ipairs(MOUNT_WORDS) do
            if line:find(w, 1, true) then return true end
        end
    end
    return false
end
function SM.IsOldMountMacro(name, body)
    if not body or body == "" then return false end
    local anyUse = false
    for line in (body .. "\n"):gmatch("([^\n]*)\n") do
        if not MountLine(line) then return false end
        local l = string.lower(line)
        if l:find("^/use ") or l:find("^/cast ") then anyUse = true end
    end
    return anyUse
end

-- Every macro the smart one makes redundant: other same-named ones and
-- any macro that is nothing but mount lines - BUT never one a character
-- still has on a bar or a key. This character's are swapped for the
-- smart one by SM.Apply first (then they are no longer on a bar);
-- another character's are swapped when that character logs in. Deleting
-- a macro empties every slot it sat in, and nothing can refill a slot on
-- a character that is not logged in - Zac lost his mount button that way.
-- { { idx, name, body, account, usedBy } }; usedBy set = listed in the
-- second return (kept, with who still uses it) instead of the first.
function SM.Retired()
    local c = Cfg()
    local mine = SM.FindMacro(c.macro)
    local acc = MAX_ACCOUNT_MACROS or 120
    local nA, nC = GetNumMacros()
    local onBars = SM.OnBars()
    local MC = QoL.MacroCleanup
    local byOthers = (MC and MC.UsedByOthers and MC.UsedByOthers()) or {}
    local bound = (MC and MC.BoundNames and MC.BoundNames()) or {}
    local out, kept = {}, {}
    local function look(i)
        if i == mine then return end
        local n, icon, body = GetMacroInfo(i)
        if not n then return end
        if string.lower(n) == string.lower(c.macro or "") or SM.IsOldMountMacro(n, body) then
            local m = { idx = i, name = n, icon = icon, body = body or "", account = i <= acc }
            if onBars[i] or bound[n] then
                m.usedBy = "you"
                kept[#kept + 1] = m
            elseif i <= acc and byOthers[n] then
                m.usedBy = byOthers[n]
                kept[#kept + 1] = m
            else
                out[#out + 1] = m
            end
        end
    end
    for i = 1, nA or 0 do look(i) end
    for i = acc + 1, acc + (nC or 0) do look(i) end
    return out, kept
end

-- An old mount macro to turn INTO the smart one when none of the
-- configured name exists: the one on this character's bars if any, so
-- the button he already presses becomes the smart macro (a rename keeps
-- a macro in its slots; a new macro would sit in no slot at all).
local function Adoptable()
    local acc = MAX_ACCOUNT_MACROS or 120
    local nA, nC = GetNumMacros()
    local onBars = SM.OnBars()
    local used, any
    local function look(i)
        local n, _, body = GetMacroInfo(i)
        if n and SM.IsOldMountMacro(n, body) then
            if onBars[i] and not used then used = i end
            if not any then any = i end
        end
    end
    for i = 1, nA or 0 do look(i) end
    for i = acc + 1, acc + (nC or 0) do look(i) end
    return used or any
end

-- Puts the smart macro into every action slot of this character that
-- holds another mount macro (an old one, or a same-named twin), so the
-- leftovers end up on no bar and the cleanup tab can offer them. Never
-- while the cursor holds something of the player's.
function SM.TakeSlots(mine)
    if not (mine and mine > 0) or InCombatLockdown() then return 0 end
    if not (PickupMacro and PlaceAction and GetCursorInfo) then return 0 end
    if GetCursorInfo() then return 0 end
    local want = string.lower(Cfg().macro or "")
    local n = 0
    for idx, slots in pairs(SM.OnBars()) do
        if idx ~= mine then
            local name, _, body = GetMacroInfo(idx)
            if name and (string.lower(name) == want or SM.IsOldMountMacro(name, body)) then
                for _, slot in ipairs(slots) do
                    PickupMacro(mine)
                    if GetCursorInfo() then
                        PlaceAction(slot)      -- the old macro comes back on the cursor
                        n = n + 1
                    end
                    ClearCursor()
                end
            end
        end
    end
    if n > 0 then ns.ActionSlots.Invalidate() end
    return n
end

function SM.Body(pick)
    local head = "#showtooltip\n/dismount [mounted]\n/stopmacro [mounted]\n"
    if not pick then
        return head .. "/run ZacUI.Print(\"No mount in your bags.\")"
    end
    if pick.kind == "spell" then return head .. "/cast " .. pick.name end
    return head .. "/use " .. pick.name
end

-- Writes the macro when its text would change. Returns what it did.
-- Bag changes call this all the time while looting: when the pick, the
-- macro list and the bars are all as the last pass left them, there is
-- nothing to do and it stops before reading or writing anything.
local lastDone
function SM.Apply(why)
    local c = Cfg()
    if not (QoL.enabled and c.enabled) then return "off" end
    if InCombatLockdown() then SM.dirty = true return "combat" end
    local name = c.macro
    if not name or name == "" then return "noname" end
    local idx = SM.FindMacro(name)
    local pick = SM.Pick()
    local body = SM.Body(pick)
    local key = name .. "\031" .. idx .. "\031" .. body .. "\031" .. ns.Macros.Version() .. "\031" .. ns.ActionSlots.Version()
    if idx ~= 0 and key == lastDone then return "same" end
    lastDone = nil
    if idx == 0 then
        if not c.create then return "missing" end
        local old = Adoptable()
        if old then
            local oldName, icon = GetMacroInfo(old)
            EditMacro(old, name, icon, body)
            Wrote()
            Print("Mount macro: \"" .. tostring(oldName) .. "\" is now \"" .. name .. "\", the smart one"
                .. (pick and (": " .. pick.name) or "") .. ".")
            SM.TakeSlots((SM.FindMacro(name)))
            return "adopted"
        end
        local account = GetNumMacros() or 0
        if account >= (MAX_ACCOUNT_MACROS or 120) then return "full" end
        CreateMacro(name, "INV_Misc_QuestionMark", body, nil)
        Wrote()
        Print("Mount macro \"" .. name .. "\" made" .. (pick and (": " .. pick.name) or "") .. ".")
        return "created"
    end
    local took = SM.TakeSlots(idx)
    if took > 0 then
        Print("Mount macro \"" .. name .. "\" put on " .. took .. (took == 1 and " bar slot" or " bar slots")
            .. " in place of an old mount macro.")
    end
    local curName, icon, cur = GetMacroInfo(idx)
    if cur ~= body then
        EditMacro(idx, curName or name, icon, body)
        SM.last = pick and pick.name or nil
    end
    -- what this pass left behind (read after its own writes). Something on
    -- the cursor made TakeSlots stand down, so the next pass must try again.
    if took > 0 or cur ~= body then Wrote() end
    if GetCursorInfo and GetCursorInfo() then
        lastDone = nil
        return cur == body and "same" or "written"
    end
    lastDone = name .. "\031" .. idx .. "\031" .. body .. "\031" .. ns.Macros.Version() .. "\031" .. ns.ActionSlots.Version()
    return cur == body and "same" or "written"
end

-- The bar loadouts (ZacLayout copying Zacw's bars) treat the mount macro
-- as this module's: matched by name without regard to case, never
-- rewritten with another character's text, made with this character's
-- pick when missing.
local owned = false
local function RegisterOwner()
    if owned then return end
    local LO = ns.Loadouts
    if LO and LO.OwnMacro then
        owned = true
        LO.OwnMacro(function(n) return n and string.lower(n) == string.lower(Cfg().macro or "") end,
            function() return SM.Body(SM.Pick()) end)
    end
end
RegisterOwner()

-- The events: zoning (the crystal rule), bags (a new mount), and the
-- end of combat for anything that waited.
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
f:RegisterEvent("BAG_UPDATE_DELAYED")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
local queued = false
local function Queue(delay)
    if queued then return end
    queued = true
    C_Timer.After(delay or 1, function()
        queued = false
        SM.Apply("event")
    end)
end
f:SetScript("OnEvent", function(_, event)
    RegisterOwner()      -- the bars addon may have loaded after this file
    if event == "PLAYER_REGEN_ENABLED" then
        if SM.dirty then SM.dirty = nil Queue(0.5) end
    elseif event == "PLAYER_ENTERING_WORLD" then
        Queue(3)        -- item info needs a moment after a load
    else
        Queue(1)
    end
end)

function SM.Refresh() Queue(0.1) end

-- /zui mount: say what it would pick, and write it now
function SM.Status()
    local pick = SM.Pick()
    local c = Cfg()
    local where = InAQ40() and " (in Ahn'Qiraj: the crystal rule)" or ""
    if pick then
        Print("Mount macro \"" .. c.macro .. "\": " .. pick.name .. where .. ".")
    else
        Print("Mount macro \"" .. c.macro .. "\": no mount item in the bags and no summon spell known" .. where .. ".")
    end
    local did = SM.Apply("status")
    if did == "combat" then Print("  (written when combat ends)")
    elseif did == "missing" then Print("  The macro does not exist and creating it is off.")
    elseif did == "full" then Print("  No free account macro slot to make it.") end
end

-- ============================================================
-- SMART WEAPON MACROS (2026-10-30, Zac: "can we somehow make it smart and
-- find other peoples macros and make sure they are updated as well" -
-- other classes, his friend's copy, "same as the mount macro").
-- Every macro on the character - account-wide or its own, any class -
-- with /equipslot or /equip lines is kept on THIS character's weapons:
--   * a weapon the character does not have is swapped for its own one in
--     the same role, the role read from the item and the line:
--       shield, off-hand item (holdable), two-hander, ranged;
--       a one-hander in slot 17 = the off hand; in slot 16 (or /equip)
--       a quick one (1.9 or faster) = the fast weapon, else the main hand
--   * a weapon it does have stays - ALWAYS. A macro naming one is never
--     changed (2026-10-30 18:29, Zac: "this macro shit for dw just keeps
--     overwriting what i actually have in my main hand and off hand at the
--     time" - the first build followed whatever was worn and rewrote
--     carried weapons on an "upgrade"; both are gone)
--   * a macro with a "#keep" line is never touched.
-- This character's roles (they only fill in weapons it lacks): main and
-- off hand = the pair it dual wields in boss fights (learned at each
-- pull, the slower one main), else its best good weapons - never simply
-- what it happens to wear; fast = its quickest good main-
-- hand-capable weapon; the best shield, off-hand item, two-hander and
-- ranged weapon. "Good": rare or better, within 20 item levels of its
-- best one-hander. Shared with ZacLayout (ns.WeaponRoles), one system.
-- COST: out of combat only; at login, after a macro edit, a weapon swap
-- or a change of the weapons carried (the bag events only compare the
-- weapon ids carried - each item is looked up once a session). A macro
-- is written only when its text changes.
-- ============================================================
local SW = {}
QoL.SmartWeapons = SW
local WR = {}
ns.WeaponRoles = WR

local SW_DEFAULTS = { enabled = true, skip = "" }
-- names never picked for a role (2026-10-30, Zac: "kingsfall and claw of
-- the frost wyrm for me are trash weapons not boss weapons and shouldnt
-- be put in the dw macro"); a macro naming one on purpose keeps it
local function Skipped()
    local out = {}
    local d = DB()
    local c = type(d.smartWeapons) == "table" and d.smartWeapons or {}
    for n in tostring(c.skip or ""):gmatch("[^,\n]+") do
        n = n:gsub("^%s+", ""):gsub("%s+$", "")
        if n ~= "" then out[n:lower()] = true end
    end
    return out
end
function SW.Cfg()
    local d = DB()
    if type(d.smartWeapons) ~= "table" then d.smartWeapons = {} end
    local c = d.smartWeapons
    for k, v in pairs(SW_DEFAULTS) do if c[k] == nil then c[k] = v end end
    return c
end

local ONE_HAND = { INVTYPE_WEAPON = true, INVTYPE_WEAPONMAINHAND = true, INVTYPE_WEAPONOFFHAND = true }
local RANGED = { INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true }
local FAST_AT = 1.9

local wtip
local function TipSpeed(set, a, b)
    if not wtip then
        wtip = CreateFrame("GameTooltip", "ZacUIWeaponScanTooltip", UIParent, "GameTooltipTemplate")
    end
    wtip:SetOwner(UIParent, "ANCHOR_NONE")
    wtip:ClearLines()
    local ok = pcall(wtip[set], wtip, a, b)
    local speed
    if ok then
        for i = 2, math.min(wtip:NumLines() or 0, 10) do
            local fs = _G["ZacUIWeaponScanTooltipTextRight" .. i]
            local t = fs and fs:GetText()
            if t and t:find("Speed", 1, true) then speed = tonumber(t:match("(%d+%.%d+)")) break end
        end
    end
    wtip:Hide()
    return speed
end

-- item id -> { name, q, ilvl, loc, speed } (looked up once a session)
local winfo = {}
local function ItemFacts(id)
    local f = winfo[id]
    if f then return f end
    local _, _, _, loc = GetItemInfoInstant(id)
    if not (loc and (ONE_HAND[loc] or RANGED[loc] or loc == "INVTYPE_SHIELD" or loc == "INVTYPE_HOLDABLE"
        or loc == "INVTYPE_2HWEAPON")) then
        f = { skip = true }
        winfo[id] = f
        return f
    end
    local name, link, q, ilvl = GetItemInfo(id)
    if not name then return nil end              -- not in the cache yet: asked again next time
    f = { name = name, q = q or 0, ilvl = ilvl or 0, loc = loc }
    if ONE_HAND[loc] or loc == "INVTYPE_2HWEAPON" then f.speed = TipSpeed("SetHyperlink", link) end
    winfo[id] = f
    return f
end

-- every weapon, shield, holdable and ranged weapon carried or worn;
-- missing: one not in the item cache yet. idsKey: the ids, for a cheap
-- "did the weapons change" test.
WR.Facts = function(id) return ItemFacts(id) end     -- (the noob Whirlwind math reads the speed)
function WR.Scan()
    local list, missing, ids = {}, false, {}
    local function add(id, worn)
        local f = ItemFacts(id)
        if not f then missing = true return end
        if f.skip then return end
        ids[#ids + 1] = id
        list[#list + 1] = { name = f.name, q = f.q, ilvl = f.ilvl, loc = f.loc, speed = f.speed, worn = worn }
    end
    for _, s in ipairs({ 16, 17, 18 }) do
        local id = GetInventoryItemID("player", s)
        if id then add(id, s) end
    end
    for bag = 0, 4 do
        for slot = 1, (GetContainerNumSlots(bag) or 0) do
            local id = GetContainerItemID(bag, slot)
            if id then add(id, nil) end
        end
    end
    table.sort(ids)
    return list, missing, table.concat(ids, ",")
end

local function Best(list, test)
    local b
    for _, w in ipairs(list) do
        if test(w) and (not b or w.ilvl > b.ilvl) then b = w end
    end
    return b and b.name
end
-- this character's roles; store: where main / off hand are remembered
function WR.Roles(store)
    local all, missing = WR.Scan()
    local r, owned = {}, {}
    -- every name counts as carried; the skipped ones are never a role
    local skip = Skipped()
    local list = {}
    for _, w in ipairs(all) do
        owned[w.name] = true
        if not skip[w.name:lower()] then list[#list + 1] = w end
    end
    local best = 0
    for _, w in ipairs(list) do
        if ONE_HAND[w.loc] and w.q >= 3 and w.ilvl > best then best = w.ilvl end
    end
    local good = {}
    for _, w in ipairs(list) do
        if ONE_HAND[w.loc] and w.q >= 3 and w.ilvl >= best - 20 then good[#good + 1] = w end
    end
    if #good == 0 then for _, w in ipairs(list) do if ONE_HAND[w.loc] then good[#good + 1] = w end end end
    local w16, w17
    for _, w in ipairs(list) do
        if w.worn == 16 then w16 = w elseif w.worn == 17 then w17 = w end
    end
    -- the pair worn in boss fights (learned at each pull, see
    -- SW.LearnBossPair); else the best good weapons. What is worn right
    -- now never decides (trash weapons are worn too).
    local boss = store and store.bossMainOff
    if boss and boss.main and owned[boss.main] and not skip[boss.main:lower()] then r.main = boss.main end
    if boss and boss.off and owned[boss.off] and not skip[boss.off:lower()] then r.off = boss.off end
    do
        if not r.main then
            -- no boss pair seen yet: the best two by item level (the
            -- slower first on a tie)
            table.sort(good, function(x, y)
                if x.ilvl ~= y.ilvl then return x.ilvl > y.ilvl end
                return (x.speed or 0) > (y.speed or 0)
            end)
            for _, w in ipairs(good) do if w.loc ~= "INVTYPE_WEAPONOFFHAND" then r.main = w.name break end end
        end
        if not r.off then
            for _, w in ipairs(good) do
                if w.name ~= r.main and w.loc ~= "INVTYPE_WEAPONMAINHAND" then r.off = w.name break end
            end
        end
    end
    local fast
    for _, w in ipairs(good) do
        if w.loc ~= "INVTYPE_WEAPONOFFHAND" and w.speed
            and (not fast or w.speed < fast.speed or (w.speed == fast.speed and w.ilvl > fast.ilvl)) then fast = w end
    end
    r.fast = fast and fast.name
    r.shield = Best(list, function(w) return w.loc == "INVTYPE_SHIELD" end)
    r.holdable = Best(list, function(w) return w.loc == "INVTYPE_HOLDABLE" end)
    r.twohand = (w16 and w16.loc == "INVTYPE_2HWEAPON" and w16.name) or Best(list, function(w) return w.loc == "INVTYPE_2HWEAPON" end)
    r.ranged = (list and (function() for _, w in ipairs(list) do if w.worn == 18 then return w.name end end end)())
        or Best(list, function(w) return RANGED[w.loc] end)
    return r, missing, owned
end

-- the role of a weapon a macro names, from the item (in the client's
-- cache - any item this client has seen) and the line's slot
function WR.RoleOf(itemName, slot)
    local name, link, _, _, _, _, _, _, loc = GetItemInfo(itemName)
    if not name then return nil end
    if loc == "INVTYPE_SHIELD" then return "shield" end
    if loc == "INVTYPE_HOLDABLE" then return "holdable" end
    if loc == "INVTYPE_2HWEAPON" then return "twohand" end
    if RANGED[loc] then return "ranged" end
    if not ONE_HAND[loc] then return nil end
    if slot == 17 then return "off" end
    local speed = TipSpeed("SetHyperlink", link)
    if speed and speed <= FAST_AT then return "fast" end
    return "main"
end

-- The macro body on this character's weapons. prev: the roles last
-- time (an upgrade follows), cur: now, owned: names carried or worn.
-- Returns the new body (or the old one) and how many weapons changed.
local ROLES = { "main", "off", "fast", "shield", "holdable", "twohand", "ranged" }
function SW.Rewrite(body, cur, prev, owned)
    if not body:find("/equip", 1, true) then return body, 0 end
    for line in body:gmatch("[^\n]+") do
        if line:lower():match("^%s*#keep") then return body, 0 end
    end
    local map, n = {}, 0
    for line in body:gmatch("[^\n]+") do
        local slot, item = line:match("^%s*/equipslot%s+(%d+)%s+(.-)%s*$")
        if not slot then item = line:match("^%s*/equip%s+(.-)%s*$") end
        if item and item ~= "" and map[item] == nil then
            map[item] = false
            local to
            if owned[item] then
                -- carried: never changed
            else
                local role = WR.RoleOf(item, tonumber(slot))
                if role and cur[role] then to = cur[role] end
            end
            if to and to ~= item then map[item] = to n = n + 1 end
        end
    end
    if n == 0 then return body, 0 end
    local froms = {}
    for from, to in pairs(map) do if to then froms[#froms + 1] = from end end
    table.sort(froms, function(a, b) return #a > #b end)
    local out = body
    for k, from in ipairs(froms) do out = out:gsub((from:gsub("(%W)", "%%%1")), "\001" .. k .. "\001") end
    for k, from in ipairs(froms) do out = out:gsub("\001" .. k .. "\001", (map[from]:gsub("%%", "%%%%"))) end
    return out, n
end

local function CharStore()
    ZacUICharDB = ZacUICharDB or {}
    if type(ZacUICharDB.weaponRoles) ~= "table" then ZacUICharDB.weaponRoles = {} end
    return ZacUICharDB.weaponRoles
end
WR.Store = CharStore

local swTries = 0
function SW.Apply(why)
    local c = SW.Cfg()
    if not (QoL.enabled and c.enabled) then return "off" end
    if InCombatLockdown() then SW.dirty = true return "combat" end
    local store = CharStore()
    local cur, missing, owned = WR.Roles(store)
    if missing and swTries < 6 then
        swTries = swTries + 1
        C_Timer.After(3, function() SW.Apply("retry") end)
        return "waiting"
    end
    swTries = 0
    local prev = store.prev
    local acc = MAX_ACCOUNT_MACROS or 120
    local nA, nC = GetNumMacros()
    local changed = {}
    local function look(i)
        local name, icon, body = GetMacroInfo(i)
        if name and body then
            local nb, n = SW.Rewrite(body, cur, prev, owned)
            if n > 0 and nb ~= body and #nb <= 255 then
                SW.writing = true
                local ok = pcall(EditMacro, i, name, icon, nb)
                SW.writing = false
                if ok then changed[#changed + 1] = name end
            end
        end
    end
    for i = 1, nA or 0 do look(i) end
    for i = acc + 1, acc + (nC or 0) do look(i) end
    store.prev = cur
    if #changed > 0 then
        ns.Macros.Invalidate()
        Print("Weapon macros put on this character's weapons: " .. table.concat(changed, ", ") .. ".")
    end
    return #changed > 0 and "written" or "same"
end

-- THE BOSS PAIR: a few seconds into each boss pull (after any gear swap
-- on the engage) the two one-handers worn, if dual wielding, are this
-- character's main and off hand from then on - trash weapons worn on the
-- way never count. The slower one is the main hand. Read in combat (two
-- slot reads); the macros are rewritten once combat ends.
function SW.LearnBossPair()
    local id16, id17 = GetInventoryItemID("player", 16), GetInventoryItemID("player", 17)
    local a, b = id16 and ItemFacts(id16), id17 and ItemFacts(id17)
    if not (a and b and not a.skip and not b.skip and ONE_HAND[a.loc] and ONE_HAND[b.loc]) then return false end
    local skip = Skipped()
    if skip[a.name:lower()] or skip[b.name:lower()] then return false end
    if (b.speed or 0) > (a.speed or 0) and b.loc ~= "INVTYPE_WEAPONOFFHAND" then a, b = b, a end
    local store = CharStore()
    local was = store.bossMainOff
    store.bossMainOff = { main = a.name, off = b.name }
    if not (was and was.main == a.name and was.off == b.name) then SW.dirty = true end
    return true
end
if ns.Encounter and ns.Encounter.On then
    ns.Encounter.On("QoL.SmartWeapons", function(event)
        if event == "start" then
            C_Timer.After(6, SW.LearnBossPair)
            C_Timer.After(20, SW.LearnBossPair)   -- a slow swap
        end
    end)
end

local swQueued = false
local function SWQueue(delay)
    if swQueued then return end
    swQueued = true
    C_Timer.After(delay or 1, function()
        swQueued = false
        SW.Apply("event")
    end)
end
function SW.Refresh() SWQueue(0.1) end

local lastIds
local sw = CreateFrame("Frame")
sw:RegisterEvent("PLAYER_ENTERING_WORLD")
sw:RegisterEvent("UPDATE_MACROS")
sw:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
sw:RegisterEvent("BAG_UPDATE_DELAYED")
sw:RegisterEvent("PLAYER_REGEN_ENABLED")
sw:SetScript("OnEvent", function(_, event, a1)
    if event == "PLAYER_REGEN_ENABLED" then
        if SW.dirty then SW.dirty = nil SWQueue(1) end
    elseif event == "PLAYER_ENTERING_WORLD" then
        SWQueue(5)                          -- after ZacLayout's bars and the item cache
    elseif event == "UPDATE_MACROS" then
        if not SW.writing then SWQueue(1) end
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        if a1 == 16 or a1 == 17 or a1 == 18 then SWQueue(2) end
    elseif event == "BAG_UPDATE_DELAYED" then
        -- only a change of the weapons carried is worth a look
        if InCombatLockdown() then return end
        local _, _, key = WR.Scan()
        -- the first look only takes the baseline (login already checks)
        if lastIds == nil then lastIds = key
        elseif key ~= lastIds then lastIds = key SWQueue(2) end
    end
end)
