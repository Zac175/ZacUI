-- QoL_Snowball - a Snowball button that only throws while you are in the
-- air: the "Snowball FIX 1.15.9" WeakAura, rebuilt into ZacUI. Part of
-- ZacUI; load order is set by the TOC.
--
-- HOW THE "ONLY IN THE AIR" PART WORKS. Two frames in one spot:
--   * ZacUISnowball - the real, secure button. A left click on it always
--     throws a Snowball at you (the "item" action, unit player: the same
--     as "/use [@player] Snowball"); a right click takes the snow off
--     ("cancelaura Snowball"). NOT a "macro" action: the client refuses
--     to start a macro while one is running, so a macrotext button
--     works from the mouse and does nothing from a "/click" line in a
--     macro - which is exactly the symptom the WeakAura had.
--   * the lock - an ordinary frame laid over it that takes the mouse.
--     On the ground it is on top and swallows your clicks (nothing
--     happens). The moment you are falling it turns see-through and
--     stops taking the mouse, so the same click lands on the button.
-- So you can spam-click the icon all fight and it throws only in the
-- air. The lock is the only thing that knows you are falling: the game
-- gives secure buttons no way to check that, and lets no addon change
-- one in combat, so a keybind or a "/click ZacUISnowball" macro line
-- goes straight to the button and throws wherever you are.
--
-- A MOUSE BUTTON THAT THROWS ONLY IN THE AIR (snowball.airButton, e.g.
-- "BUTTON4"). A keyboard key cannot be gated - the game runs a key's
-- binding without looking at what is under the cursor. A MOUSE button
-- can: the game offers the press to the frames under the cursor, top
-- down. Two screen-sized, click-only frames at the very bottom of the
-- UI (below every window and plate; the other four mouse buttons pass
-- straight through both, so steering and targeting are untouched):
--   * ZacUISnowballWide - a secure button that takes that mouse button
--     anywhere over the world. With the bind's modifiers (none for
--     "BUTTON4") it throws the Snowball; with any other modifiers it does
--     whatever your own binding for that combination does (it is read
--     from the Key Bindings and done by the button itself), so Shift-,
--     Ctrl- and Alt- keep working.
--   * the gate - an ordinary frame just above it that swallows the
--     button on the ground (only while exactly the bind's modifiers are
--     held) and steps aside in the air, so the press reaches the wide
--     button.
-- Why this way round and not a binding: the game has a quirk - after a
-- mouse event that went THROUGH a frame to the world (a wheel scroll, a
-- passed button) it sends the next click straight to the world as well
-- until the mouse moves. With a binding on the button, a wheel-spammed
-- Heroic Strike followed by the button threw on the ground (10-26
-- 13:28/14:02). Now a click that skips the frames reaches the world,
-- where nothing is bound: a missed throw at worst, never a ground throw.
-- Limits, the game's: the press must land on the world (over a window,
-- that window eats it), and while you hold the right button to steer
-- the UI gets no mouse at all, so a press then throws wherever you are.
-- Only BUTTON3/4/5 can be gated: the game can pass exactly five buttons
-- (left, right, middle, 4, 5) through a frame.
--
-- WHEN IT IS UP: switched on, and (by default) only inside a raid.
-- Showing and hiding a secure button waits for the end of a fight.
--
-- WHEN A THROW DID NOT HAPPEN, one chat line says why: no Snowballs in
-- your bags, or the game's own error ("Item is not ready yet." ...).
-- The first click the lock swallows in a session says so once too.
--
-- COST: the lock checks IsFalling() every frame only while the button is
-- on screen, and touches the frames only when that answer changes.

local ADDON_NAME = ...
-- Zacui_QoL is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

-- shared state from earlier ZacUI files
local Print = ns.Print
local QoL = ns.QoL

local SB = {}
QoL.Snowball = SB

local ITEM = 17202          -- Snowball
local ICON = 132387
local MOVER = "snowball"

SB.COUNT_DEFAULTS = { point = "BOTTOMRIGHT", relPoint = "BOTTOMRIGHT", x = -2, y = 2 }
function SB.Cfg()
    local d = QoL.DB()
    if type(d.snowball) ~= "table" then d.snowball = {} end
    local c = d.snowball
    if c.enabled == nil then c.enabled = false end
    -- raidsOnly took over from naxxOnly (10-26): the same tick, any raid
    if c.raidsOnly == nil then
        if c.naxxOnly ~= nil then c.raidsOnly = c.naxxOnly and true or false else c.raidsOnly = true end
    end
    c.naxxOnly = nil
    if c.size == nil then c.size = 45 end
    if c.showIcon == nil then c.showIcon = true end
    if type(c.targets) ~= "string" then c.targets = "" end    -- "Maexxna, Loatheb": shown only while targeting one of these
    if c.chatty == nil then c.chatty = false end               -- the explanations in chat (why a throw did not happen ...)
    if ns.FillDefaults then ns.FillDefaults(c, SB.DEFAULTS)
    else for k, v in pairs(SB.DEFAULTS) do if c[k] == nil then c[k] = v end end end
    return c
end

-- ============================================================
-- THE LOOK - the icon, the count and the lock's dimmed copy. Built and
-- dressed by Face / StyleFace, which the settings preview uses too (on
-- plain frames: a sample is never a secure button). nil in a colour or
-- the font means "as it has always looked".
-- ============================================================
SB.DEFAULTS = {
    showCount = true,         -- how many Snowballs you carry, in the corner
    countFont = nil,          -- nil: ZacUI's font, 12
    countColor = nil,         -- nil: white
    emptyColor = nil,         -- nil: red, when you have none (on the lock)
    lockColor = nil,          -- nil: a cool grey over the dimmed icon
    lockDesat = true,         -- the locked icon in grey
    showCooldown = true,      -- the cooldown sweep over the icon
    lockAnim = { style = "none", duration = 0.15, delay = 0, easing = "easeOutQuad", dir = "up", distance = 8 },
}

local function Col(c, r, g, b)
    if type(c) == "table" and ns.ColorOf then return ns.ColorOf(c) end
    return r, g, b, 1
end

-- an icon and a count on any frame
function SB.Face(f)
    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture(ICON)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local count = f:CreateFontString(nil, "OVERLAY")
    count:SetPoint("BOTTOMRIGHT", -2, 2)
    -- a font from the start: the game refuses text on a string without one
    count:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    if NumberFontNormal then count:SetFontObject(NumberFontNormal) end
    f.icon, f.count = icon, count
    return f
end

-- locked: the lock's copy (dimmed); n: Snowballs carried
function SB.StyleFace(f, c, locked, n)
    local spec = c.countFont
    if type(spec) == "table" and next(spec) and ns.ApplyFontSpec then
        local delta = ZacUIDB and ZacUIDB.font and tonumber(ZacUIDB.font.delta) or 0
        ns.ApplyFontSpec(f.count, spec, { size = 12 + delta, outline = "outline" })
    elseif ns.HouseFont then
        ns.HouseFont(f.count, 12, nil, STANDARD_TEXT_FONT)
    end
    f.count:SetShown(c.showCount ~= false)
    -- where the count sits (snowball.anchors.count, ZacUI's anchor shape;
    -- the bottom right corner is its spot). Nothing saved = never touched;
    -- out of combat only (the button is a secure one).
    local ca = type(c.anchors) == "table" and c.anchors.count or nil
    if (ca or f._zMoved) and ns.ApplyAnchor and not (InCombatLockdown and InCombatLockdown()) then
        f._zMoved = ca and true or nil
        local D = f._zCountDef or {}
        f._zCountDef = D
        D.point, D.to, D.relPoint, D.x, D.y = "BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2
        if not f._zAnchorTo then f._zAnchorTo = function(k) if k == "button" then return f end end end
        ns.ApplyAnchor(f.count, ca, D, f._zAnchorTo)
    end
    if ns.TagElement then ns.TagElement(f.count, "snowball.count") end
    if locked then
        f.icon:SetDesaturated(c.lockDesat ~= false)
        f.icon:SetVertexColor(Col(c.lockColor, 0.55, 0.55, 0.6))
        -- the lock sits over the button on the ground, so the count is on
        -- it too (red when there are none)
        f.count:SetText(tostring(n))
        if n > 0 then f.count:SetTextColor(Col(c.countColor, 1, 1, 1))
        else f.count:SetTextColor(Col(c.emptyColor, 1, 0.3, 0.3)) end
    else
        f.icon:SetDesaturated(n == 0)
        f.icon:SetVertexColor(1, 1, 1)
        f.count:SetText(n > 0 and tostring(n) or "")
        f.count:SetTextColor(Col(c.countColor, 1, 1, 1))
    end
end

-- the explanations (a swallowed click, a refused throw, what a press did):
-- only when asked for (snowball.chatty); the setup lines that matter -
-- a binding the gate cannot carry, no pass-through - are always said
local function Chat(msg) if SB.Cfg().chatty then Print(msg) end end

local holder, btn, lock, countText, lockCount, cdFrame, gate, wide, drv
local gateButton                 -- the physical button the gate takes ("Button4")
local wideAttrs = {}             -- attribute names set on the wide button last time
local wideMine = ""              -- the snowball combination's modifiers, as the snippet spells them ("shift")
local lastSummary, saidCombo = nil, 0
local gateMods                   -- the modifiers in front of it ("SHIFT-BUTTON4": shift)
local gateTaking = nil           -- what the gate is doing right now
-- only these can be gated: SetPassThroughButtons knows exactly five
-- button names (LeftButton, RightButton, MiddleButton, Button4, Button5),
-- so the gate can step out of the way of the others only for these. A
-- name it does not know makes the whole call a no-op, and the gate then
-- swallows EVERY click (the 10-26 13:13 "all my mouse buttons stopped
-- working"). BUTTON6 and up (MMO mice) cannot be gated cleanly.
local PHYS = { BUTTON3 = "MiddleButton", BUTTON4 = "Button4", BUTTON5 = "Button5" }
local SUFFIX = { MiddleButton = "3", Button4 = "4", Button5 = "5" }   -- secure attribute suffixes
local ALL = { "LeftButton", "RightButton", "MiddleButton", "Button4", "Button5" }
-- the stock buttons behind the client's binding names (used only when
-- nothing overrides the name - ZacUI's bars answer to these names
-- through overrides, which GetBindingAction(key, true) reports as CLICK commands)
local STOCK = { ACTIONBUTTON = "ActionButton", MULTIACTIONBAR1BUTTON = "MultiBarBottomLeftButton",
    MULTIACTIONBAR2BUTTON = "MultiBarBottomRightButton", MULTIACTIONBAR3BUTTON = "MultiBarRightButton",
    MULTIACTIONBAR4BUTTON = "MultiBarLeftButton", BONUSACTIONBUTTON = "PetActionButton", SHAPESHIFTBUTTON = "StanceButton" }
-- the Snowball's own cooldown, read from its bag slot (Classic Era has
-- no item-ID cooldown call)
local NumSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
local SlotItem = (C_Container and C_Container.GetContainerItemID) or GetContainerItemID
local SlotCD = (C_Container and C_Container.GetContainerItemCooldown) or GetContainerItemCooldown
local cdBag, cdSlot
local air = nil
local watchUntil = 0
local lastPress, saidGround, saidOther = 0, 0, 0   -- the diagnostics' clocks
local clickedInAir = false
local toldLock = false
local pending = false

-- "Only while targeting": the names in c.targets, one of which has to be
-- the target. Decided out of combat only (a secure button cannot be shown,
-- hidden or moved in a fight): target Maexxna before the pull and the
-- button is up for the fight; the next change of target after the fight
-- takes it down again.
local function TargetListed(c)
    local list = c.targets
    if not list or list == "" then return true end
    local name = UnitExists("target") and UnitName("target")
    if not name then return false end
    name = name:lower()
    for want in list:gmatch("[^,;\n]+") do
        want = want:lower():gsub("^%s+", ""):gsub("%s+$", "")
        if want ~= "" and want == name then return true end
    end
    return false
end
SB.TargetListed = TargetListed

-- the raid bosses and trash, for picking targets: Readycheck's own lists
-- when it is loaded (RC.raidData[raid].bosses / .trashSections), else
-- this copy of them. Names that are an encounter rather than a mob are
-- opened up into the mobs you can actually target.
local BOSS_LISTS = {
    { "Naxxramas", { "Anub'Rekhan", "Grand Widow Faerlina", "Maexxna", "Noth the Plaguebringer", "Heigan the Unclean", "Loatheb", "Instructor Razuvious", "Gothik the Harvester", "Four Horsemen", "Patchwerk", "Grobbulus", "Gluth", "Thaddius", "Sapphiron", "Kel'Thuzad" },
      trash = {
        { "Spider Quarter", { "Crypt Guard", "Crypt Reaver", "Crypt Crawler", "Venom Stalker", "Tomb Horror", "Naxxramas Follower", "Necropolis Acolyte", "Naxxramas Cultist", "Naxxramas Worshipper", "Necro Knight", "Necro Stalker", "Infectious Skitterer", "Dread Creeper", "Carrion Spinner", "Spirit of Naxxramas", "Shade of Naxxramas", "Infectious Ghoul", "Plagued Gargoyle" } },
        { "Plague Quarter", { "Plagued Warrior", "Plagued Champion", "Plagued Guardian", "Plagued Ghoul", "Plagued Bat", "Plagued Insect", "Plagued Maggot", "Frenzied Bat", "Infectious Ghoul", "Stoneskin Gargoyle", "Plague Beast", "Plague Slime", "Eye Stalk" } },
        { "Military Quarter", { "Deathknight", "Deathknight Captain", "Deathknight Cavalier", "Death Knight Understudy", "Shade of Naxxramas", "Spirit of Naxxramas", "Unholy Staff", "Unholy Swords", "Unholy Axe", "Spectral Deathknight", "Spectral Horseman", "Spectral Rider", "Spectral Trainee", "Unrelenting Trainee", "Unrelenting Deathknight", "Unrelenting Rider", "Risen Deathknight", "Skeletal Smith", "Skeletal Steed", "Necro Knight", "Necro Stalker", "Infectious Ghoul", "Plagued Gargoyle", "Necropolis Acolyte" } },
        { "Construct Quarter", { "Patchwork Golem", "Bile Retcher", "Sewage Slime", "Embalming Slime", "Mad Scientist", "Surgical Assistant", "Living Monstrosity", "Stitched Spewer", "Sludge Belcher" } },
        { "Frostwyrm Lair", { "Unstoppable Abomination", "Soul Weaver", "Soldier of the Frozen Wastes" } },
      } },
    { "Temple of Ahn'Qiraj", { "The Prophet Skeram", "Silithid Royalty", "Battleguard Sartura", "Fankriss the Unyielding", "Viscidus", "Princess Huhuran", "Twin Emperors", "Ouro", "C'Thun" },
      trash = {
        { "Anubisath", { "Anubisath Sentinel", "Anubisath Defender", "Anubisath Guardian", "Anubisath Warder" } },
        { "Qiraji", { "Qiraji Slayer", "Qiraji Champion", "Qiraji Warrior", "Qiraji Gladiator", "Qiraji Mindslayer", "Qiraji Brainwasher", "Qiraji Lasher" } },
        { "Obsidian", { "Obsidian Destroyer", "Obsidian Nullifier", "Obsidian Eradicator" } },
        { "Vekniss", { "Vekniss Drone", "Vekniss Guardian", "Vekniss Soldier", "Vekniss Stinger", "Vekniss Warrior", "Vekniss Wasp", "Vekniss Hatchling", "Vekniss Borer", "Vekniss Hive Crawler" } },
      } },
    { "Blackwing Lair", { "Razorgore the Untamed", "Vaelastrasz the Corrupt", "Broodlord Lashlayer", "Firemaw", "Ebonroc", "Flamegor", "Chromaggus", "Nefarian" },
      trash = {
        { "Blackwing", { "Blackwing Legionnaire", "Blackwing Mage", "Blackwing Spellbinder", "Blackwing Taskmaster", "Blackwing Technician", "Blackwing Warlock" } },
        { "Death Talon", { "Death Talon Captain", "Death Talon Dragonspawn", "Death Talon Flamescale", "Death Talon Hatcher", "Death Talon Overseer", "Death Talon Seether", "Death Talon Wyrmguard", "Death Talon Wyrmkin" } },
        { "Suppression Room", { "Corrupted Whelp" } },
      } },
    { "Molten Core", { "Lucifron", "Magmadar", "Gehennas", "Garr", "Baron Geddon", "Shazzrah", "Sulfuron Harbinger", "Golemagg the Incinerator", "Majordomo Executus", "Ragnaros" },
      trash = {
        { "Core Hounds", { "Core Hound", "Ancient Core Hound" } },
        { "Elementals", { "Lava Annihilator", "Lava Elemental", "Lava Reaver", "Lava Surger" } },
        { "Giants", { "Molten Destroyer", "Molten Giant" } },
        { "Flamewakers", { "Flamewaker Healer", "Flamewaker Elite", "Flamewaker Priest", "Flamewaker Protector" } },
        { "Other", { "Firewalker", "Flame Imp", "Flameguard", "Firelord" } },
      } },
}
local ENCOUNTER_MOBS = {
    ["Four Horsemen"] = "Thane Korth'azz, Lady Blaumeux, Highlord Mograine, Sir Zeliek",
    ["Twin Emperors"] = "Emperor Vek'lor, Emperor Vek'nilash",
    ["Silithid Royalty"] = "Lord Kri, Princess Yauj, Vem",
}
local RAID_ORDER = { "Naxxramas", "Temple of Ahn'Qiraj", "Blackwing Lair", "Molten Core" }
-- { { raid, { boss, ... }, trash = { { section, { mob, ... } }, ... } }, ... }
function SB.BossLists()
    local RC = _G.Readycheck
    local data = RC and RC.raidData
    if type(data) ~= "table" then return BOSS_LISTS end
    local out, seen = {}, {}
    local function add(raid)
        local r = data[raid]
        if type(r) == "table" and type(r.bosses) == "table" and not seen[raid] then
            seen[raid] = true
            local trash = {}
            if type(r.trashSections) == "table" then
                local names = {}
                for sec in pairs(r.trashSections) do names[#names + 1] = sec end
                table.sort(names)
                for _, sec in ipairs(names) do
                    if type(r.trashSections[sec]) == "table" then trash[#trash + 1] = { sec, r.trashSections[sec] } end
                end
            end
            out[#out + 1] = { raid, r.bosses, trash = trash }
        end
    end
    for _, raid in ipairs(RAID_ORDER) do add(raid) end
    local rest = {}
    for raid in pairs(data) do if not seen[raid] then rest[#rest + 1] = raid end end
    table.sort(rest)
    for _, raid in ipairs(rest) do add(raid) end
    return #out > 0 and out or BOSS_LISTS
end
-- what goes into the list for a picked name
function SB.TargetsFor(name) return ENCOUNTER_MOBS[name] or name end
-- the list with a name added (once)
function SB.AddTarget(list, name)
    list = list or ""
    local names = SB.TargetsFor(name)
    for n in names:gmatch("[^,]+") do
        n = n:gsub("^%s+", ""):gsub("%s+$", "")
        local have = false
        for had in list:gmatch("[^,;\n]+") do
            if had:gsub("^%s+", ""):gsub("%s+$", ""):lower() == n:lower() then have = true break end
        end
        if not have then list = (list == "" and n) or (list .. ", " .. n) end
    end
    return list
end

local function Wanted()
    local c = SB.Cfg()
    if not (QoL.enabled and c.enabled) then return false end
    if c.raidsOnly and not ns.InRaidInstance() then return false end
    return TargetListed(c)
end

local function FindSlot()
    cdBag, cdSlot = nil, nil
    if not (NumSlots and SlotItem) then return end
    for b = 0, 4 do
        for sl = 1, (NumSlots(b) or 0) do
            if SlotItem(b, sl) == ITEM then cdBag, cdSlot = b, sl return end
        end
    end
end

-- start, duration of the Snowball's cooldown (0, 0 when none / none carried)
local function SnowCD()
    if not cdBag then FindSlot() end
    if not (cdBag and SlotCD) then return 0, 0 end
    local st, du = SlotCD(cdBag, cdSlot)
    return st or 0, du or 0
end

local function UpdateCD()
    if not cdFrame then return end
    local st, du = SnowCD()
    if st > 0 and du > 1.5 then cdFrame:SetCooldown(st, du) else cdFrame:Clear() end
end
local QueueCD = ns.Coalescer(UpdateCD, 0.1)

local function UpdateCount()
    if not btn then return end
    FindSlot()
    local n = GetItemCount(ITEM) or 0
    local c = SB.Cfg()
    SB.StyleFace(btn, c, false, n)
    SB.StyleFace(lock, c, true, n)
    if cdFrame then cdFrame:SetShown(c.showCooldown ~= false) end
    UpdateCD()
end
-- the look changed (the settings page): the button follows
function SB.Restyle()
    if btn then UpdateCount() end
end
local QueueCount = ns.Coalescer(UpdateCount, 0.2)

-- the lock: on top and taking the mouse on the ground, out of the way in
-- the air. Only touches the frames when the answer changes.
-- the modifiers held right now are exactly the bind's: "BUTTON4" is
-- taken only with no modifier held, so Shift-BUTTON4 and the rest keep
-- their own bindings; "SHIFT-BUTTON4" only with Shift alone
local NO_MODS = {}
local function ModsHeld()
    local m = gateMods or NO_MODS
    if (IsShiftKeyDown() and true or false) ~= (m.shift or false) then return false end
    if (IsControlKeyDown() and true or false) ~= (m.ctrl or false) then return false end
    if (IsAltKeyDown() and true or false) ~= (m.alt or false) then return false end
    return true
end

-- runs on the driver frame (up whenever the button is active, icon shown
-- or not), so the mouse-button gate works with the icon hidden
-- "in the air" means IsFalling for at least this long: running over a
-- bump, a step or down a slope reports a fall for a few frames, and the
-- lid (and the gate) opened for them, so a button pressed while running
-- threw on the ground (13:38). A jump is ~0.8s; this costs its first bit.
local AIR_AFTER = 0      -- Zac (14:23): the air at once, bumps and all
local airSince = nil
local rearm = false
local function LockTick()
    local falling
    if IsFalling() then
        local now = GetTime()
        airSince = airSince or now
        falling = (now - airSince) >= AIR_AFTER
    else
        airSince = nil
        falling = false
    end
    if falling ~= air then
        air = falling
        lock:EnableMouse(not falling)
        SB.SetLock(lock, not falling, SB.Cfg().lockAnim)
    end
    if gate and gateButton then
        -- on the ground, with the modifiers (if any) held: take the button
        local take = (not falling) and ModsHeld()
        if take ~= gateTaking then
            gateTaking = take
            if gate.SetMouseClickEnabled then gate:SetMouseClickEnabled(take)
            else gate:EnableMouse(take) end
            -- closing again: shown afresh, so the game looks at what is
            -- under a still cursor again rather than at where the last
            -- click went (the wide button, if you threw in the air)
            if take then gate:Hide() gate:Show() end
        end
        -- EXPERIMENT (snowball.rearm): the same every frame
        if take and rearm then gate:Hide() gate:Show() end
    end
end

-- The lock on (the ground) or off (the air). Without an animation it
-- turns see-through at once, as it always has; with one it plays out and
-- in. Taking the mouse is the caller's and happens at once either way:
-- the animation is only what you see.
function SB.SetLock(f, on, spec)
    local M = ns.Motion
    local animated = M and type(spec) == "table" and spec.style and spec.style ~= "none" and M.Enabled()
    if not animated then
        if M then M.Stop(f) end
        f:SetAlpha(on and 1 or 0)
        if on then f:Show() end
        return
    end
    -- from the see-through rest the old way left, to a real one
    if f:GetAlpha() < 0.01 then
        M.Stop(f)
        f:SetAlpha(1)
        if not on then f:Hide() return end
        f:Hide()
    end
    if on then
        if not f:IsShown() or M.IsPlaying(f) then M.Show(f, spec) end
    else
        M.Hide(f, spec)
    end
end

-- the binding string's physical button: "SHIFT-BUTTON4" -> "Button4"
local function PhysOf(bind)
    if type(bind) ~= "string" then return nil end
    local b = bind:upper():match("(BUTTON%d+)$")
    return b and PHYS[b] or nil
end
SB.PhysOf = PhysOf

-- the frame behind a binding command, and the mouse button to click it
-- with: "CLICK Name:Btn", or a stock name; nil when it is neither
local function Replica(cmd)
    local name, mb = cmd:match("^CLICK ([^:]+):(.+)$")
    if name then return name, mb end
    local base, n = cmd:match("^([%u%d]-BUTTON)(%d+)$")
    if base and STOCK[base] then return STOCK[base] .. n, "LeftButton" end
    return nil
end
SB.Replica = Replica

-- the other four buttons pass through f to the world; false when the
-- game will not do that (then f must not stay up: it would eat them)
local function PassOthers(f, phys)
    if not f.SetPassThroughButtons then return false end
    local pass = {}
    for _, b in ipairs(ALL) do if b ~= phys then pass[#pass + 1] = b end end
    local ok = pcall(f.SetPassThroughButtons, f, unpack(pass))
    if ok and f.ShouldButtonPassThrough then
        for _, b in ipairs(pass) do
            if not f:ShouldButtonPassThrough(b) then ok = false break end
        end
    end
    if not ok then pcall(f.SetPassThroughButtons, f) end
    return ok
end

-- a bar button: its action slot can be followed (an "action" attribute,
-- or an id with a page like the stock buttons)
local function IsActionButton(f)
    if not (f and f.GetAttribute) then return false end
    if f:GetAttribute("action") ~= nil then return true end
    return f:GetAttribute("type") == "action" and f.GetID and (f:GetID() or 0) > 0
end
SB.IsActionButton = IsActionButton

-- the slot a bar button would use right now (out of combat; the snippet
-- keeps it current in combat)
local function SlotOf(f)
    if f.CalculateAction then
        local ok, a = pcall(f.CalculateAction, f, "LeftButton")
        if ok and type(a) == "number" then return a end
    end
    local a = f:GetAttribute("action")
    if type(a) == "number" then return a end
    local id = f.GetID and f:GetID() or 0
    if id > 0 then
        local page = f:GetAttribute("actionpage") or (f:GetParent() and f:GetParent():GetAttribute("actionpage")) or 1
        return id + (page - 1) * 12
    end
    return 1
end

-- Runs securely before each click of the wide button. Two jobs:
--   * the modifiers are read at the PRESS and kept for the release: the
--     game decides a click's action at the release, with the modifiers
--     held THEN, so Shift+BUTTON4 with Shift let go first came out as a
--     plain BUTTON4 - a Snowball on the ground (10-26 17:39). The click
--     is renamed to a virtual button ("zsnowshift4") built from the
--     press's modifiers, and every action is filed under that name with
--     a "*" (any-modifier) prefix, so the release cannot pick a different
--     one.
--   * every copied bar button's slot right now, into its "*action-..."
--     attribute (the bar button's own "action", or its id on its bar's
--     page), so paging and stance bars are followed in combat.
-- No table constructors in here (the restricted environment forbids them).
local SLOTS_SNIPPET = [[
    local sfx = self:GetAttribute("snowsfx")
    if button ~= self:GetAttribute("snowphys") then return end
    local pre = ""
    if IsAltKeyDown() then pre = "alt" end
    if IsControlKeyDown() then pre = pre .. "ctrl" end
    if IsShiftKeyDown() then pre = pre .. "shift" end
    if down then
        self:SetAttribute("snowpre", pre)
    else
        pre = self:GetAttribute("snowpre") or pre
    end
    for i = 0, 7 do
        local d = self:GetFrameRef("d" .. i)
        if d then
            local p = ""
            if i >= 4 then p = "alt" end
            if i % 4 >= 2 then p = p .. "ctrl" end
            if i % 2 == 1 then p = p .. "shift" end
            local a = tonumber(d:GetAttribute("action"))
            if not a then
                local id = tonumber(d:GetID()) or 0
                if id > 0 then
                    local page = tonumber(d:GetAttribute("actionpage"))
                    if not page then
                        local par = d:GetParent()
                        page = par and tonumber(par:GetAttribute("actionpage"))
                    end
                    a = id + ((page or 1) - 1) * 12
                end
            end
            if a then self:SetAttribute("*action-zsnow" .. p .. sfx, a) end
        end
    end
    return "zsnow" .. pre .. sfx
]]
SB.SLOTS_SNIPPET = SLOTS_SNIPPET

local function DropGate()
    if gate then gate:Hide() end
    if wide then
        for _, a in ipairs(wideAttrs) do wide:SetAttribute(a, nil) end
        wideAttrs = {}
        for i = 0, 7 do wide:SetAttribute("frameref-d" .. i, nil) end
        wide:Hide()
    end
    gateButton, gateMods, gateTaking = nil, nil, nil
end

local Explain   -- the PostClick explanations (below)

-- the wide button and the gate; out of combat only
local function ApplyGate(active)
    local c = SB.Cfg()
    local bind = type(c.airButton) == "string" and c.airButton:upper():gsub("%s+", "") or ""
    local phys = PhysOf(bind)
    if not (active and phys) then DropGate() return end
    local physKey = bind:match("(BUTTON%d+)$")
    rearm = c.rearm and true or false
    gateMods = nil
    if bind:find("%-") then
        gateMods = { shift = bind:find("SHIFT%-") ~= nil, ctrl = bind:find("CTRL%-") ~= nil, alt = bind:find("ALT%-") ~= nil }
    end
    local m = gateMods or NO_MODS
    local mine = (m.alt and "alt-" or "") .. (m.ctrl and "ctrl-" or "") .. (m.shift and "shift-" or "")
    local sfx = SUFFIX[phys]
    -- the virtual button a click becomes (see SLOTS_SNIPPET): "zsnow" +
    -- the press's modifiers without dashes + the button's number, and
    -- its attributes with the any-modifier "*" in front
    local function V(prefix) return "-zsnow" .. prefix:gsub("%-", "") .. sfx end
    wideMine = mine:gsub("%-", "")

    -- what the button's other modifier combinations do, read from the
    -- bindings: the wide button does those itself, so they keep working.
    -- A combination bound to something it cannot do means no gate at all
    -- (the wide button would swallow that combination).
    local keyDown = GetCVarBool and GetCVarBool("ActionButtonUseKeyDown")
    local plan, refs = {}, {}
    plan[#plan + 1] = { "*type" .. V(mine), "item" }
    plan[#plan + 1] = { "*item" .. V(mine), "item:" .. ITEM }
    plan[#plan + 1] = { "*unit" .. V(mine), "player" }
    for i = 0, 7 do
        local alt, ctrl, shift = i >= 4, i % 4 >= 2, i % 2 == 1
        local prefix = (alt and "alt-" or "") .. (ctrl and "ctrl-" or "") .. (shift and "shift-" or "")
        if prefix ~= mine then
            local key = (alt and "ALT-" or "") .. (ctrl and "CTRL-" or "") .. (shift and "SHIFT-" or "") .. physKey
            -- with overrides: ZacUI's bars answer to the stock names through
            -- override bindings, and it is the bar button that must be pressed
            local cmd = GetBindingAction and GetBindingAction(key, true)
            if cmd and cmd ~= "" then
                local name, mb = Replica(cmd)
                local target = name and _G[name]
                if name and not target then
                    -- a button that is not there (its addon is off): the
                    -- key does nothing as it is, so nothing to carry
                    -- (18:56: ZacUI off, Ctrl-BUTTON4 still bound to a ZacUI
                    -- bar button, and the gate refused to come up at all)
                    target = nil
                elseif not (target and target.IsObjectType and target:IsObjectType("Button")) then
                    DropGate()
                    Print(string.format("Snowball: %s is bound to %s, which the gate cannot pass on - unbind it or pick another mouse button. The mouse button is off.", key, cmd))
                    return
                end
                if not target then
                    -- nothing to carry for this combination
                elseif IsActionButton(target) then
                    -- a bar button: the wide button uses its action SLOT
                    -- itself ("action"), read from the bar button by a
                    -- secure snippet at every click (so paging and stance
                    -- bars are followed in combat). Not a click and not a
                    -- /click line: a click cannot press "down" (so "cast on
                    -- key down" users got nothing), and a /click line is a
                    -- macro, which may not run the macro in the slot (14:27).
                    plan[#plan + 1] = { "*type" .. V(prefix), "action" }
                    plan[#plan + 1] = { "*action" .. V(prefix), SlotOf(target) }
                    refs[i] = target
                elseif keyDown or mb ~= "LeftButton" then
                    -- the native click hands on neither "down" nor the
                    -- button name; a /click line does both
                    plan[#plan + 1] = { "*type" .. V(prefix), "macro" }
                    plan[#plan + 1] = { "*macrotext" .. V(prefix), "/click " .. name .. " " .. mb .. (keyDown and " 1" or "") }
                else
                    plan[#plan + 1] = { "*type" .. V(prefix), "click" }
                    plan[#plan + 1] = { "*clickbutton" .. V(prefix), target }
                end
            end
        end
    end

    if not wide then
        wide = CreateFrame("Button", "ZacUISnowballWide", UIParent, "SecureActionButtonTemplate, SecureHandlerBaseTemplate")
        wide:SetAttribute("snowsfx", sfx)
        wide:SetAttribute("snowphys", phys)
        -- before every click: the modifiers locked at the press, the
        -- copied bar buttons' current slots
        if SecureHandlerWrapScript then SecureHandlerWrapScript(wide, "OnClick", wide, SLOTS_SNIPPET) end
        wide:SetFrameStrata("BACKGROUND")
        wide:SetFrameLevel(0)
        wide:SetAllPoints(UIParent)
        wide:RegisterForClicks("AnyUp", "AnyDown")
        wide:SetAttribute("useOnKeyDown", false)
        wide:EnableMouseWheel(false)
        if wide.SetMouseMotionEnabled then wide:SetMouseMotionEnabled(false) end
        wide:HookScript("PostClick", function(self, mouseButton, down)
            -- PostClick gets the real button name (the snippet's renaming
            -- is for OnClick only); the press's modifiers are in the
            -- attribute the snippet stored them in (17:48: the "did not
            -- come from the button" line fired on every throw)
            local mods
            if mouseButton == gateButton then mods = self:GetAttribute("snowpre") or ""
            elseif type(mouseButton) == "string" then mods = mouseButton:match("^zsnow(%a*)%d$") end
            if not mods then return end
            if mods == wideMine then Explain(mouseButton, down) return end
            -- one of the copied combinations: say what was pressed on
            if down then return end
            local now = GetTime()
            if now - saidCombo < 10 then return end
            saidCombo = now
            local v = "-zsnow" .. mods .. SUFFIX[gateButton]
            local t = self:GetAttribute("*type" .. v)
            local what = t == "click" and self:GetAttribute("*clickbutton" .. v)
            what = what and what.GetName and what:GetName() or self:GetAttribute("*macrotext" .. v)
                or (t == "action" and ("slot " .. tostring(self:GetAttribute("*action" .. v)))) or "nothing (not bound)"
            Chat(string.format("Snowball: %s%s pressed on the gate -> %s (%s).", mods == "" and "" or mods:upper() .. "-", tostring(gateButton):upper(), tostring(what), tostring(t)))
        end)
        wide:Hide()
    end
    if not gate then
        gate = CreateFrame("Frame", "ZacUISnowballGate", UIParent)
        gate:SetFrameStrata("BACKGROUND")
        gate:SetFrameLevel(1)          -- just above the wide button
        gate:SetAllPoints(UIParent)
        gate:EnableMouse(true)
        gate:EnableMouseWheel(false)
        -- clicks only: it never takes the hover, so world mouseover,
        -- tooltips and nameplates are as before
        if gate.SetMouseMotionEnabled then gate:SetMouseMotionEnabled(false) end
        -- takes nothing until the first tick decides
        if gate.SetMouseClickEnabled then gate:SetMouseClickEnabled(false) end
        gate:Hide()
    end
    if gateButton ~= phys then
        if not (PassOthers(wide, phys) and PassOthers(gate, phys)) then
            DropGate()
            Print("Snowball: the game would not let the other mouse buttons through the gate, so the mouse button is off - click the icon instead.")
            return
        end
        gateButton = phys
    end
    for _, a in ipairs(wideAttrs) do wide:SetAttribute(a, nil) end
    wideAttrs = {}
    wide:SetAttribute("snowsfx", sfx)
    wide:SetAttribute("snowphys", phys)
    for i = 0, 7 do
        if refs[i] and SecureHandlerSetFrameRef then SecureHandlerSetFrameRef(wide, "d" .. i, refs[i])
        else wide:SetAttribute("frameref-d" .. i, nil) end
    end
    local told = {}
    for _, kv in ipairs(plan) do
        wide:SetAttribute(kv[1], kv[2])
        wideAttrs[#wideAttrs + 1] = kv[1]
        local mods = kv[1]:match("^%*type%-zsnow(%a*)%d$")
        if mods then told[#told + 1] = (mods == "" and "plain" or mods) .. "-" .. kv[2] end
    end
    -- say once what the button's combinations now do (again when it changes)
    local summary = string.format("Snowball: %s throws%s; the button's other combinations: %s%s.", bind,
        mine == "" and "" or " (" .. mine .. ")",
        #told > 1 and table.concat(told, ", ", 2) or "none bound",
        keyDown and " (cast on key down: /click lines)" or "")
    if summary ~= lastSummary then lastSummary = summary Chat(summary) end
    wide:Show()
    gate:Show()
    gateTaking = nil               -- the next tick sets the gate's state
end

-- after a throwing click has run (the icon or the wide button; the
-- action runs on the release, so the press is skipped)
Explain = function(mouseButton, down)
    if down then return end
    if (GetItemCount(ITEM) or 0) == 0 then
        Chat("Snowball: you have no Snowballs in your bags.")
        return
    end
    watchUntil = GetTime() + 0.6
    clickedInAir = IsFalling() and true or false
    lastPress = GetTime()
    -- the icon's lid swallows ground clicks, so a ground press came
    -- through the mouse button or a /click macro: say so
    if not air and lastPress - saidGround > 10 then
        saidGround = lastPress
        Chat("Snowball: pressed while on the ground - that came from the mouse button or a /click macro, not the icon.")
    end
end

local function Build()
    if btn then return true end
    if InCombatLockdown() then return false end
    local c = SB.Cfg()

    -- the spot: an ordinary frame the mover can drag (secure frames are
    -- not movable from addon code); both icons sit on it
    holder = CreateFrame("Frame", "ZacUISnowballHolder", UIParent)
    holder:SetSize(c.size, c.size)
    holder:SetPoint("CENTER", UIParent, "CENTER", 776, 254)
    holder:Hide()

    btn = CreateFrame("Button", "ZacUISnowball", UIParent, "SecureActionButtonTemplate")
    btn:SetFrameStrata("MEDIUM")
    btn:SetAllPoints(holder)
    -- as the buff remover's buttons: both edges registered, the action
    -- on release whatever "cast on key down" says - so a plain
    -- "/click ZacUISnowball" line in a macro presses it too
    btn:RegisterForClicks("AnyUp", "AnyDown")
    btn:SetAttribute("useOnKeyDown", false)
    -- left: throw at yourself; right: take the snow off
    btn:SetAttribute("type1", "item")
    btn:SetAttribute("item1", "item:" .. ITEM)
    btn:SetAttribute("unit1", "player")
    btn:SetAttribute("type2", "cancelaura")
    btn:SetAttribute("spell2", "Snowball")
    SB.Face(btn)
    countText = btn.count
    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.15)
    cdFrame = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
    cdFrame:SetAllPoints()
    btn:Hide()
    -- after the secure click has run: say why when nothing was thrown
    btn:HookScript("PostClick", function(_, mouseButton, down)
        if mouseButton == "RightButton" then return end
        Explain(mouseButton, down)
    end)

    -- the lock, over the button
    lock = CreateFrame("Button", nil, holder)
    lock:SetFrameStrata("HIGH")
    lock:SetAllPoints(holder)
    lock:RegisterForClicks("AnyUp", "AnyDown")
    SB.Face(lock)
    lockCount = lock.count
    SB.StyleFace(lock, c, true, GetItemCount(ITEM) or 0)
    lock:SetScript("OnClick", function()
        if toldLock then return end
        toldLock = true
        Chat("Snowball: on the ground the button is locked - jump, and click it while you are in the air.")
    end)
    drv = CreateFrame("Frame", nil, UIParent)
    drv:SetScript("OnUpdate", LockTick)
    drv:Hide()
    air = nil

    if ns.RegisterMover then
        ns.RegisterMover(MOVER, "Snowball button", function() return holder end, "CENTER", 776, 254, nil,
            { secure = true })
        local pos = ZacUIDB and ZacUIDB.movers and ZacUIDB.movers[MOVER]
        if pos then
            holder:ClearAllPoints()
            holder:SetPoint(pos.point or "CENTER", UIParent, pos.point or "CENTER", pos.x or 0, pos.y or 0)
        end
    end
    return true
end

-- show or hide (out of combat only: the button is secure)
function SB.Apply()
    if InCombatLockdown() then pending = true return end
    pending = false
    local want = Wanted()
    -- built as soon as it is switched on (so "Move it" works anywhere),
    -- shown only where it is wanted
    if QoL.enabled and SB.Cfg().enabled and not Build() then pending = true return end
    if not btn then return end
    if want then
        local c = SB.Cfg()
        local s = c.size or 45
        holder:SetSize(s, s)
        -- the icon can be hidden: the button still exists for the mouse
        -- button (a binding clicks a hidden button fine, as the buff
        -- remover's do), it just cannot be clicked on screen
        local iconOn = c.showIcon ~= false
        holder:SetShown(iconOn)
        -- the secure button is anchored to the holder, not parented to it:
        -- with the icon off it must go see-through and deaf as well, or it
        -- sits there visible and unlocked (a click on the ground would throw)
        btn:SetAlpha(iconOn and 1 or 0)
        btn:EnableMouse(iconOn)
        btn:Show()
        drv:Show()
        air = nil
        UpdateCount()
    else
        btn:Hide()
        holder:Hide()
        drv:Hide()
    end
    ApplyGate(want)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("ZONE_CHANGED_NEW_AREA")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("BAG_UPDATE_DELAYED")
ev:RegisterEvent("BAG_UPDATE_COOLDOWN")
ev:RegisterEvent("UI_ERROR_MESSAGE")
ev:RegisterEvent("UPDATE_BINDINGS")     -- the wide button copies the button's other bindings
ev:RegisterEvent("PLAYER_TARGET_CHANGED") -- "only while targeting" (out of combat)
ev:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
ev:SetScript("OnEvent", function(_, event, a1, a2, a3)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- a Snowball thrown without the button being pressed: a bar macro
        if a3 and GetSpellInfo(a3) == "Snowball" then
            local now = GetTime()
            if now - lastPress > 0.5 and now - saidOther > 10 then
                saidOther = now
                Chat("Snowball: that throw did not come from the Snowball button - something else used the item (a /use Snowball macro on a bar key?).")
            end
        end
        return
    end
    if event == "UI_ERROR_MESSAGE" then
        if watchUntil > 0 and GetTime() <= watchUntil then
            watchUntil = 0
            local msg = type(a2) == "string" and a2 or (type(a1) == "string" and a1) or nil
            -- only an item's error is the Snowball's: "Not enough rage" in
            -- the same half second is Heroic Strike's (14:08)
            if msg and (msg == ERR_ITEM_COOLDOWN or msg:find("Snowball") or msg:find("[Ii]tem")) then
                -- where you were, and whether the Snowball itself was on
                -- cooldown: tells a real cooldown from the game refusing
                local st, du = SnowCD()
                local left = st > 0 and (st + du - GetTime()) or 0
                Chat(string.format("Snowball: %s (%s; %s)", msg,
                    clickedInAir and "in the air" or "on the ground",
                    left > 0 and string.format("its cooldown: %.1fs of %.0fs left", left, du)
                        or "it was not on cooldown"))
            end
        end
    elseif event == "BAG_UPDATE_DELAYED" then
        if btn and btn:IsShown() then QueueCount() end
    elseif event == "BAG_UPDATE_COOLDOWN" then
        if btn and btn:IsShown() then QueueCD() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pending then SB.Apply() end
    elseif event == "PLAYER_TARGET_CHANGED" then
        -- only when the list is in use, and never mid-fight (Apply waits)
        if SB.Cfg().targets ~= "" then SB.Apply() end
    else
        SB.Apply()
    end
end)
