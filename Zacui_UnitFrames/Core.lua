-- ============================================================================
-- Zacui_UnitFrames - Core.lua
-- ZacUI's unit frames (the addon that used to be ZacUF). A part of ZacUI:
-- depends on it, keeps its OWN private namespace (this `ns`, not ZacUI's -
-- the two share only what ns.ZUI hands over), and keeps every setting in
-- ZacUIDB.unitframes so the ZacUI profile system carries it like the rest.
-- ============================================================================
local ADDON, ns = ...

-- Expose a single global for slash/debug access (does not clash with anything).
_G.ZacUF = ns
-- ZacUI's namespace: the config page, the palette, the header art
ns.ZUI = _G.ZacUI

local getAddOnMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
ns.version = (getAddOnMeta and getAddOnMeta(ADDON, "Version")) or "0.1.0"
ns.frames  = ns.frames or {}     -- registered top-level frames {key = frame}

-- ----------------------------------------------------------------------------
-- Output
-- ----------------------------------------------------------------------------
-- ZacUI's chat name, in its chat colour (looked up per line: the palette
-- can change)
local function PREFIX() return ((ns.ZUI and ns.ZUI.ChatCode and ns.ZUI.ChatCode()) or "|cffffd100") .. "[ZacUI]|r " end
function ns.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX() .. tostring(msg))
end

-- ----------------------------------------------------------------------------
-- Color helpers
-- ----------------------------------------------------------------------------
local CLASS_COLORS = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)

-- Returns r,g,b for a unit's class/reaction, honoring config, else the fallback.
-- Health bar color for a frame's unit. Per frame: healthClassColor on -> class
-- color for players, reaction color for NPCs; off -> the frame's flat healthColor.
-- The colour rule itself, apart from any real unit: the settings preview
-- paints its sample frames through these same two, so a sample is coloured
-- exactly as a live frame would be. isPlayer + class for a player, else a
-- reaction (1..8) for an NPC; nil for "no unit".
function ns.HealthColorFor(cfg, isPlayer, class, reaction)
    local fb  = (cfg and cfg.healthColor) or (ns.db and ns.db.colors.health) or { 0.2, 0.2, 0.2 }
    if cfg and cfg.healthClassColor then
        if isPlayer then
            local c = class and CLASS_COLORS[class]
            if c then return c.r, c.g, c.b end
        elseif reaction then
            local c = FACTION_BAR_COLORS and FACTION_BAR_COLORS[reaction]
            if c then return c.r, c.g, c.b end
        end
    end
    return fb[1], fb[2], fb[3]
end

function ns.NameColorFor(cfg, isPlayer, class)
    local fb  = (cfg and cfg.nameColor) or (ns.db and ns.db.colors.nameText) or { 1, 1, 1 }
    if cfg and cfg.nameClassColor and isPlayer then
        local c = class and CLASS_COLORS[class]
        if c then return c.r, c.g, c.b end
    end
    return fb[1], fb[2], fb[3]
end

function ns.UnitColor(unit, frame)
    local cfg = frame and frame.cfg
    -- every health tick comes through here: no unit lookups unless the
    -- colour actually depends on the unit
    if not (cfg and cfg.healthClassColor) or not unit or not UnitExists(unit) then
        return ns.HealthColorFor(cfg)
    end
    if UnitIsPlayer(unit) then
        local _, class = UnitClass(unit)
        return ns.HealthColorFor(cfg, true, class)
    end
    return ns.HealthColorFor(cfg, false, nil, UnitReaction(unit, "player"))
end

-- Class color for name text (separate toggle from health coloring).
-- Name text color. Per frame: nameClassColor on -> class color (players);
-- off -> the frame's flat nameColor.
function ns.NameColor(unit, frame)
    local cfg = frame and frame.cfg
    if cfg and cfg.nameClassColor and unit and UnitExists(unit) and UnitIsPlayer(unit) then
        local _, class = UnitClass(unit)
        return ns.NameColorFor(cfg, true, class)
    end
    return ns.NameColorFor(cfg)
end

-- Abbreviate large health numbers (e.g. 12345 -> 12.3k)
function ns.Short(n)
    if n >= 1e6 then return string.format("%.1fm", n / 1e6)
    elseif n >= 1e3 then return string.format("%.1fk", n / 1e3)
    else return tostring(n) end
end

-- ----------------------------------------------------------------------------
-- Saved variables / init
-- ----------------------------------------------------------------------------
local function InitDB()
    -- the match overlay, decided now that the look is latched (Config.lua),
    -- and the kit's fresh-install spots under a game look (Kit.lua)
    if ns.ApplyMatchOverlay then ns.ApplyMatchOverlay() end
    if ns.ApplyKitDefaults then ns.ApplyKitDefaults() end
    -- Settings live in ZacUIDB.unitframes (ZacUI's saved variables, so the
    -- profile system carries them). The first time a ZacUIDB has none, the
    -- old standalone ZacUF settings (ZacUFDB, still loaded by the ZacUF
    -- settings-carrier addon when that is present) are adopted as they are.
    ZacUIDB = ZacUIDB or {}
    if type(ZacUIDB.unitframes) ~= "table" then
        if type(ZacUFDB) == "table" and next(ZacUFDB) then
            ZacUIDB.unitframes = CopyTable(ZacUFDB)
            ns._adoptedOld = true
        else
            ZacUIDB.unitframes = {}
        end
    end
    ns.db = ZacUIDB.unitframes
    ns.DeepFill(ns.db, ns.defaults)
    -- ZacUI's Edit Mode unlocks the frames only while it is open; a save
    -- written in the middle of it (a /reload, an error on the way out)
    -- came back with the drag handles and sample frames stuck on
    if ns.db._editUnlocked then
        ns.db._editUnlocked = nil
        ns.db.locked = true
    end

    -- One-time migrations for saved variables created before a default changed.
    -- DeepFill only adds missing keys, so values already saved (e.g. the old
    -- name strip = on) would otherwise persist.
    local v = ns.db._cfgVersion or 1
    if v < 2 then
        local n = ns.db.name
        if n then
            n.anchor, n.justify, n.point, n.x, n.y = nil, nil, nil, nil, nil  -- legacy global keys; text anchoring is per-frame now
            n.showStrip = false             -- remove the unwanted bar behind names
        end
        -- adopt the new (smaller) default sizes; positions and toggles are kept
        for k, d in pairs(ns.defaults.frames) do
            local c = ns.db.frames[k]
            if c then c.width, c.height = d.width, d.height end
        end
        ns.db.party.width, ns.db.party.height = ns.defaults.party.width, ns.defaults.party.height
        ns.db.raid.width,  ns.db.raid.height  = ns.defaults.raid.width,  ns.defaults.raid.height
    end
    if v < 3 then
        -- party/raid power/auras/castbar are now opt-in (off by default)
        for _, k in ipairs({ "party", "raid" }) do
            local c = ns.db[k]
            if c then
                c.power, c.castbar = false, false
                c.showBuffs, c.showDebuffs = false, false
            end
        end
    end
    if v < 4 then
        -- raid name now defaults left (paired with HP right) to avoid overlap on small frames
        if ns.db.raid and ns.db.raid.nameAnchor == "CENTER" then
            ns.db.raid.nameAnchor = "LEFT"
        end
    end
    if v < 5 then
        -- Health/name coloring is now per-frame. Seed each frame from the old global
        -- class-color toggles + shared color swatches so existing setups look unchanged.
        local oldHealthClass = ns.db.health and ns.db.health.classColor
        local oldNameClass   = ns.db.name and ns.db.name.classColor
        local oldHealthCol   = ns.db.colors and ns.db.colors.health
        local oldNameCol     = ns.db.colors and ns.db.colors.nameText
        local function seed(c)
            if not c then return end
            if oldHealthClass ~= nil then c.healthClassColor = oldHealthClass end
            if oldNameClass   ~= nil then c.nameClassColor   = oldNameClass end
            if oldHealthCol then c.healthColor = ns.Copy(oldHealthCol) end
            if oldNameCol   then c.nameColor   = ns.Copy(oldNameCol)   end
        end
        for _, k in ipairs({ "player", "target", "targettarget", "pet" }) do
            seed(ns.db.frames[k])
        end
        seed(ns.db.party); seed(ns.db.raid)
    end
    if v < 6 then
        -- Frame background + border are now per-frame too. Seed from the old globals
        -- so existing setups keep their backdrop look.
        local oldBg     = ns.db.colors and ns.db.colors.background
        local oldBorder = ns.db.colors and ns.db.colors.border
        local function seedBg(c)
            if not c then return end
            if oldBg     then c.bgColor     = ns.Copy(oldBg)     end
            if oldBorder then c.borderColor = ns.Copy(oldBorder) end
        end
        for _, k in ipairs({ "player", "target", "targettarget", "pet" }) do
            seedBg(ns.db.frames[k])
        end
        seedBg(ns.db.party); seedBg(ns.db.raid)
    end
    if v < 7 then
        -- Focus frame removed (no native focus unit in Classic Era); drop any orphaned config.
        if ns.db.frames then ns.db.frames.focus = nil end
        if ns.db.blizzard then ns.db.blizzard.focus = nil end
    end
    if v < 8 then
        ns.db.skinMenus = nil   -- menu-skin feature removed; drop the orphaned flag
    end
    -- Lead/assist/tank icons sit just inside the top-left corner by default --
    -- centered slightly in from it so they straddle the top + left lines (mostly
    -- in, a little out), small badges over the name. Earlier builds in this dev
    -- line tried the inside corner, the outside-left edge, and a dead-centre
    -- corner straddle; force every frame onto the final nudged default so whatever
    -- interim state a save landed in, it ends up consistent. Guard is v<12 so
    -- saves already on the v11 straddle get nudged too.
    if v < 12 then
        local function straddle(c)
            if not c then return end
            c.leaderAnchor, c.leaderX, c.leaderY = "TOPLEFT", 3,  -3
            c.roleAnchor,   c.roleX,   c.roleY   = "TOPLEFT", 19, -3
        end
        if ns.db.frames then
            for _, k in ipairs({ "player", "target", "targettarget", "pet" }) do
                straddle(ns.db.frames[k])
            end
        end
        straddle(ns.db.party); straddle(ns.db.raid)
    end
    if v < 13 then
        -- Raid target marker: nicer default placement. Player / target / party get
        -- it on the top-middle edge; raid gets it centered on the bar (under the
        -- top-anchored name). Only moved for configs still on the previous
        -- TOPRIGHT default, so any custom placement is kept.
        local function remark(c, anchor)
            if c and c.raidAnchor == "TOPRIGHT" and c.raidX == -2 and c.raidY == -2 then
                c.raidAnchor, c.raidX, c.raidY = anchor, 0, 0
            end
        end
        if ns.db.frames then
            remark(ns.db.frames.player, "TOP")
            remark(ns.db.frames.target, "TOP")
        end
        remark(ns.db.party, "TOP")
        remark(ns.db.raid, "CENTER")
    end
    if v < 14 then
        -- Force the raid target marker ON for the frames that should show it. It
        -- was already the default, but a config that had it toggled off (or that
        -- predates the key on some frame) wouldn't show markers - this guarantees
        -- it once; you can still turn it off afterward and it won't be re-forced.
        local function markon(c) if c then c.raidIcon = true end end
        if ns.db.frames then
            markon(ns.db.frames.player)
            markon(ns.db.frames.target)
        end
        markon(ns.db.party)
        markon(ns.db.raid)
    end
    if v < 15 then
        -- Status-icon default size bumped 14 -> 18 (14 was too small to read,
        -- especially the raid target marker). Only adopt the new size if the
        -- saved value is still the old default, so a custom size is respected.
        if ns.db.indicators and ns.db.indicators.size == 14 then
            ns.db.indicators.size = 18
        end
    end
    if v < 16 then
        -- Two fixes that have to reach existing saved DBs, not just fresh installs.
        --
        -- (a) Incoming-res icon: force it ON for the frames whose default is on
        --     (player / target / party / raid). It's a default-on key, but a save
        --     that predates the key on some frame - or had it toggled off - wouldn't
        --     show res. Guarantee it once (same pattern as the v14 marker force-on);
        --     you can still turn it off afterward and it won't be re-forced.
        local function rezon(c) if c then c.rezIcon = true end end
        if ns.db.frames then
            rezon(ns.db.frames.player)
            rezon(ns.db.frames.target)
        end
        rezon(ns.db.party)
        rezon(ns.db.raid)
        -- (b) Raid layout: group by subgroup. Without it the header fills by roster
        --     index, so the raid leader (usually roster index 1) lands top-left no
        --     matter their group. GROUP ordering puts a group-8 member in group 8's
        --     column. Applied here so existing saves adopt it; takes effect on the
        --     same load since InitDB runs before the raid header spawns.
        if ns.db.raid then ns.db.raid.groupBy = true end
    end
    if v < 17 then
        -- Incoming-heal settings moved out of the flat top-level `healSlots` key
        -- and into the `heal` block (which also carries colors, HoT handling,
        -- markers and the legend dot). Carry the saved slot assignments across so
        -- healers keep the colors they already had.
        if ns.db.healSlots then
            ns.db.heal.slots = ns.db.heal.slots or {}
            for role, names in pairs(ns.db.healSlots) do
                if type(names) == "table" then
                    ns.db.heal.slots[role] = ns.db.heal.slots[role] or {}
                    for name, slot in pairs(names) do
                        if ns.db.heal.slots[role][name] == nil then
                            ns.db.heal.slots[role][name] = slot
                        end
                    end
                end
            end
            ns.db.healSlots = nil
        end
        -- ZacUF used to render every healer in slot colors because that was its
        -- only mode. Class mode is the new default (deterministic across clients),
        -- so leave existing users on what they had: if they had slot assignments,
        -- they were using slot colors.
        if ns.db.heal.slots and next(ns.db.heal.slots) ~= nil then
            ns.db.heal.colorMode = "slot"
        end
    end
    if v < 18 then
        -- Heal chips used to default to drawing ABOVE the text overlay, which
        -- buried the health percentage and the name under an incoming heal. They
        -- now sit under the text. Move saves still on the old default across;
        -- anyone who deliberately picked "front" since then keeps it, because
        -- this only rewrites the value the old default produced.
        if ns.db.heal and ns.db.heal.segment and ns.db.heal.segment.layer == "front" then
            ns.db.heal.segment.layer = "behind"
        end
    end
    if v < 19 then
        -- The player frame now defaults to heal prediction ON, because that frame
        -- is where incoming healing is a decision ("back out or commit?") rather
        -- than information. DeepFill only adds MISSING keys, so an existing save
        -- still carries the old `false` and would never see the change - hence a
        -- migration. Only the player frame; every other frame stays opt-in.
        if ns.db.frames and ns.db.frames.player then
            ns.db.frames.player.healPrediction = true
        end
    end
    if v < 20 then
        -- The incoming-heal total now sits beside the health text instead of in
        -- the frame's top-right corner. TOPRIGHT was the only value the old
        -- default ever produced, so rewriting exactly that is safe: anyone who
        -- had deliberately moved it elsewhere keeps their choice.
        if ns.db.heal and ns.db.heal.total and ns.db.heal.total.anchor == "TOPRIGHT" then
            ns.db.heal.total.anchor = "LEFT_OF_HP"
        end
    end
    if v < 21 then
        -- "Line up with chat" shipped switched on; it is an opt-in layout
        -- choice, so it goes back to off (Options > Raid turns it on).
        if ns.db.raid then ns.db.raid.fitChat = false end
    end
    -- Portraits follow the look when nothing was chosen (Config.lua,
    -- ns.PortraitOn, 2026-11-07): the old shipped `false` - every look's
    -- off - becomes nil, once, under any look; a `true` set by hand stays.
    if not ns.db._portraitRev then
        local function free(c)
            local pc = type(c) == "table" and c.portrait
            if type(pc) == "table" and pc.enabled == false then pc.enabled = nil end
        end
        for _, c in pairs(ns.db.frames or {}) do free(c) end
        free(ns.db.party); free(ns.db.raid)
        ns.db._portraitRev = 1
    end
    -- The match pass (Config.lua, 2026-11-07): under ZacUI's look, once, every
    -- saved value still on the OLD shipped default moves to the new one; a
    -- value set by hand stays. Not marked under another look, so a save
    -- that turns to ZacUI's look later is moved then.
    if ns._matchApplied and not ns.db._matchRev then
        ns.MatchMigrate(ns.db)
        ns.db._matchRev = 2
    elseif ns._matchApplied and ns.db._matchRev == 1 then
        -- (the first pass moved sizes too: they go back, once)
        ns.MatchRestoreGeometry(ns.db)
        ns.db._matchRev = 2
    end
    -- frames a later build brought back (the focus frame, Extras.lua: put
    -- into the defaults only on a game that has one) come back filled when
    -- the v7 clean-up above took an old copy away
    ns.DeepFill(ns.db.frames, ns.defaults.frames)
    ns.DeepFill(ns.db.blizzard, ns.defaults.blizzard)
    ns.db._cfgVersion = 21
    -- the game looks' stock style defaults (Kit.lua, Core_Look)
    if ns.FollowLookDefaults then ns.FollowLookDefaults() end
end

-- Re-apply cheap settings (colors, media, text, single-frame size/position) to
-- already-built frames. Structural changes (enabling a frame type, header
-- layout) are applied on /reload.
function ns.ApplySettings()
    -- Heal colors are cached per caster GUID, so any color / mode change has to
    -- drop the cache before frames repaint or they redraw the old colors.
    if ns.HealColors then ns.HealColors:Flush() end
    if ns.Heal then ns.Heal:Configure() end   -- push heal settings into the live library
    for _, f in pairs(ns.frames) do
        if f.LeanRestyle then f:LeanRestyle() end
    end
    if ns.RefreshHealerDots then ns.RefreshHealerDots() end
    if ns.RestyleLowHealth then ns.RestyleLowHealth() end
    if ns.ShoutAlertApply then ns.ShoutAlertApply() end   -- a profile switch can flip it
    if ns.UpdateMocks then ns.UpdateMocks() end
end

local function Init()
    InitDB()

    -- Heal color engine + data provider. Resolved before any frame spawns so the
    -- first repaint already has a backend and the legend colors are seeded.
    if ns.HealColors then ns.HealColors:Init() end
    if ns.Heal then ns.Heal:Resolve() end

    -- a fresh install starts each frame where Blizzard's is (ZacUI's
    -- Core_FreshLayout; nothing on an existing install), read before they go
    local Z = ns.ZUI
    if Z and Z.FreshLayout and Z.FreshLayout.Units then pcall(Z.FreshLayout.Units, ns) end

    -- Disable Blizzard frames first (out of combat) so ours own the screen.
    if ns.DisableBlizzard then ns.DisableBlizzard() end

    -- Single unit frames
    if ns.SpawnUnit then
        for _, key in ipairs({ "player", "target", "targettarget", "pet", "softtarget" }) do
            local cfg = ns.db.frames[key]
            if cfg and cfg.enabled then ns.SpawnUnit(key) end
        end
    end

    -- Group headers
    if ns.SpawnHeader then
        if ns.db.party.enabled then ns.SpawnHeader("party") end
        if ns.db.raid.enabled  then ns.SpawnHeader("raid")  end
    end

    -- the frames only some games have (focus, boss...: Extras.lua and
    -- theirs), each made only when it is switched on
    for _, spawn in ipairs(ns.ExtraSpawns or {}) do spawn() end

    -- no "loaded" line of its own: ZacUI says it once for all of its parts.
    -- The one thing worth a line is the first-time adoption of old settings.
    if ns._adoptedOld then
        ns._adoptedOld = nil
        ns.Print("unit frames: your ZacUF settings were adopted. The old ZacUF folder is no longer needed.")
    end
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    Init()
end)

-- ----------------------------------------------------------------------------
-- Slash command
-- ----------------------------------------------------------------------------
-- Toggle move mode: unlock/lock frames and open/close the position dialog + grid
function ns.ToggleMoveMode()
    ns.db.locked = not ns.db.locked
    ns.ApplySettings()
    if ns.db.locked then
        if ns.HideMoveDialog then ns.HideMoveDialog() end
        ns.Print("Move mode off - frames locked.")
    else
        if ns.ShowMoveDialog then ns.ShowMoveDialog() end
        ns.Print("Move mode on - drag frames (snap to grid), or type exact coords. /zmove again to lock.")
    end
end

-- Set raid groups-per-row (1-8) and apply live. Safe in combat: the value
-- saves immediately and the regrid (protected header positions) re-runs the
-- moment combat drops. Returns true when the regrid was deferred. Used by the
-- /zuf groups command and the move dialog's stepper.
function ns.SetRaidGroupsPerRow(n)
    ns.db.raid.maxColumns = n
    ns.ApplySettings()
    if InCombatLockdown() then
        if not ns._regenApply then
            ns._regenApply = CreateFrame("Frame")
            ns._regenApply:SetScript("OnEvent", function(self)
                self:UnregisterAllEvents()
                ns.ApplySettings()
            end)
        end
        ns._regenApply:RegisterEvent("PLAYER_REGEN_ENABLED")
        return true
    end
end

SLASH_ZACUF1 = "/zuf"
SLASH_ZACUF2 = "/zacuf"
SlashCmdList.ZACUF = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local cmd = msg:match("^(%S*)")

    if cmd == "" or cmd == "config" or cmd == "options" then
        if ns.ToggleConfig then ns.ToggleConfig() else ns.Print("Config UI not loaded.") end
        return
    end

    if cmd == "lock" then
        ns.db.locked = true;  ns.ApplySettings(); ns.Print("Frames locked.");   return
    elseif cmd == "unlock" then
        ns.db.locked = false; ns.ApplySettings(); ns.Print("Frames unlocked - drag to move."); return
    elseif cmd == "moveui" or cmd == "move" then
        ns.ToggleMoveMode(); return
    elseif cmd == "reset" then
        ZacUIDB.unitframes = nil; InitDB()
        local Z = ns.ZUI
        if Z and Z.AskReload then Z.AskReload("Unit frame settings are back to their defaults. The frames are rebuilt after a reload.")
        else ns.Print("Settings reset. Type /reload to rebuild frames.") end
        return
    end

    -- Fire the Challenging Shout alert on yourself: glow + TTS sanity check
    -- without needing a warrior to press the button.
    if cmd == "shout" then
        if ns.ShoutAlertTest then ns.ShoutAlertTest() end
        return
    end

    -- Preview the low-health wash + TTS line at the current settings.
    if cmd == "low" or cmd == "lowhp" then
        if ns.LowHealthTest then ns.LowHealthTest() end
        return
    end

    -- Incoming-heal display: status, diagnostics and a quick color-mode switch.
    -- "why" is the one that matters when something looks wrong - it prints what
    -- is actually tracked on the unit under your cursor and why each chip is the
    -- color it is, so you can tell ZacUF's chips from another addon's.
    if cmd == "heal" or cmd == "heals" then
        local sub = msg:match("^%S+%s+(%S+)") or ""
        if sub == "why" then
            ns.HealWhy()
        elseif sub == "spy" then
            local on = ns.Heal:SetSpy(not ns.Heal:GetSpy())
            ns.Print("heal: spy " .. (on
                and "ON - printing every heal event with the caster it is attributed to. /zuf heal spy again to stop."
                or "off."))
        elseif sub == "class" or sub == "slot" then
            ns.HealColors:SetMode(sub)
            ns.ApplySettings()
            ns.Print(("heal: color mode %s.%s"):format(sub, sub == "slot"
                and "  Same-class healers now get different colors."
                or "  Every healer uses their class color."))
        elseif sub == "resetcolors" then
            ns.HealColors:ResetAll()
            ns.ApplySettings()
            ns.Print("heal: colors reset to defaults.")
        else
            ns.HealStatus()
        end
        return
    end

    -- Quick raid-layout switch: /zuf groups 4 -> groups 1-4 across the top,
    -- 5-8 in a second row below; /zuf groups 8 -> one strip.
    if cmd == "groups" then
        local n = tonumber(msg:match("^groups%s+(%d+)"))
        if n and n >= 1 and n <= 8 then
            local deferred = ns.SetRaidGroupsPerRow(n)
            ns.Print(("Raid: %d group%s per row%s."):format(
                n, n == 1 and "" or "s", deferred and " (regrids when combat ends)" or ""))
        else
            ns.Print(("Raid groups per row: %d.  Usage: /zuf groups <1-8>  (4 = groups 1-4 top, 5-8 below)"):format(ns.db.raid.maxColumns or 8))
        end
        return
    end

    ns.Print("commands:  /zuf (options)  |  /zuf heal  |  /zuf low  |  /zuf groups <1-8>  |  /zuf move  |  /zmove  |  lock  |  unlock  |  reset")
end

-- /zmove jumps straight into move mode
SLASH_ZACUFMOVE1 = "/zmove"
SlashCmdList.ZACUFMOVE = function() ns.ToggleMoveMode() end
