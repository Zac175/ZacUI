-- HUD_Warrior_Display - every visible piece of the Warrior HUD, wired to
-- the state engine in HUD_Warrior_Core: main cooldown grid, resources
-- (stance/execute/rage/swing) and the active-buff row.
-- Part of ZacUI; load order is set by the TOC.
-- Perf: structural refresh on the 0.2s core ticker; a 0.1s ticker only
-- repaints countdown texts; swing bars animate on their own OnUpdate.
local ADDON_NAME = ...
-- Zacui_HUD is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end
if not ns.HUD then return end   -- (the part stands down on this game version: HUD_Shared, Core_Flavor)
if ns.HUD.RETAIL then return end   -- (Retail: its own class HUD, HUD_Retail.lua; this Classic one never loads there)

-- a value WoW Forever hands back hidden (a secret value: no maths on it)
local function Hidden(v) return ns.IsSecret ~= nil and ns.IsSecret(v) or false end
local HUD = ns.HUD
local UI = ns.UI
local Print = ns.Print

local WH = ns.WarriorHUD
local W = WH.Widgets

WH.Display = WH.Display or {}
local D = WH.Display
local S = WH.State

local GetSpellInfoC = HUD.GetSpellInfo
local GetItemInfoC = HUD.GetItemInfo

-- Settings preview: force every enabled icon visible (runtime-only flag).
D.preview = false
local QUESTION_ICON = 134400

function D:SetPreview(on)
    D.preview = on and true or false
    if D.InvalidateLayout then D:InvalidateLayout() end
    if WH.Wake then WH.Wake() end
end
-- Edit Mode shows the HUD itself while its boxes are placed
if HUD.EditPreview then
    HUD.EditPreview(function() local c = WH.Store and WH.Store() return c and c.enabled and true or false end,
        function() return D.preview end,
        function(v) D:SetPreview(v) end)
end

local function PreviewNameIcon(name)
    if name and GetSpellInfoC then
        local tex = select(3, GetSpellInfoC(name))
        if tex then return tex end
    end
    return QUESTION_ICON
end

-- WA condition colors (data from the decoded aura)
local RED_OOR    = { 1, 0.2431, 0.2275 }        -- template out-of-range tint
local RED_SOFT   = { 1, 0.5137, 0.4941 }        -- BT/WW out-of-range tint
local GOLD_COUNT = { 1, 0.8667, 0, 1 }          -- potion count text
local YEL_COUNT  = { 0.9725, 1, 0, 1 }          -- sapper/dense count text
local CYAN_COUNT = { 0, 0.9412, 1, 1 }          -- sapper nameplate count
local PEACH_GLOW = { 1, 0.8549, 0.6980, 1 }     -- sapper glow color
local RAGE_BASE  = { 0.7804, 0.2510, 0.2510 }
local RAGE_LOW   = { 0.9961, 0.2980, 0.3098 }
local EXEC_ICON  = 135358                        -- Execute
local BT_ICON    = 136012                        -- Bloodthirst
local SALV_ICON  = 135910
local HS_ICON    = 132282
local CLEAVE_ICON = 132338
local OP_ICON    = 132223
local STANCE_ICONS = { [1] = 132349, [2] = 132341, [3] = 132275 }

local HUD_STRATA = "MEDIUM"

-- The colour settings (Look tab) as { r, g, b, a } arrays, re-read after
-- any setting changed (HUD.serial). Published for the settings preview.
local wcol, wcolSerial
local function WCol()
    if not wcol or wcolSerial ~= HUD.serial then
        local cfg = WH.Store()
        local src = (cfg and cfg.colors) or {}
        local out = {}
        for k, d in pairs(WH.COLOR_DEFAULTS or {}) do
            local r, g, b, a = HUD.Col(src[k], d)
            out[k] = { r, g, b, a }
        end
        wcol, wcolSerial = out, HUD.serial
    end
    return wcol
end
D.Colors = WCol

-- Anchors (one per WA group). Each anchor sits centred on an UNSCALED
-- holder; the holder is what ZacUI's mover registry positions, so a
-- scaled anchor still reports plain UIParent offsets when dragged.
local anchors, holders = {}, {}

local function MakeAnchor(key, w, h)
    local holder = CreateFrame("Frame", "ZacUIHUD_Warrior_" .. key .. "_Holder", UIParent)
    holder:SetSize(w or 26, h or 26)
    holder:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    local f = CreateFrame("Frame", "ZacUIHUD_Warrior_" .. key, holder)
    f:SetSize(w or 26, h or 26)
    f:SetFrameStrata(HUD_STRATA)
    f:SetPoint("CENTER", holder, "CENTER", 0, 0)
    anchors[key] = f
    holders[key] = holder
    return f
end

-- The seven named anchor frames exist only for warriors: on any other
-- class nothing in this file ever shows, so creating them would just
-- park seven named frames in the frame census forever.
local IS_WARRIOR = select(2, UnitClass("player")) == "WARRIOR"

local mainAnchor, auraAnchor, stanceAnchor, execAnchor,
      rageAnchor, swingAnchor, groupHandle, debuffAnchor
if IS_WARRIOR then
    mainAnchor   = MakeAnchor("Main", 26, 26)
    auraAnchor   = MakeAnchor("AuraRow", 30, 30)
    -- Individually movable (user request: line stance icon up with the player frame).
    stanceAnchor = MakeAnchor("Stance", 32, 34)
    execAnchor   = MakeAnchor("Execute", 40, 38)
    rageAnchor   = MakeAnchor("RageBar", 229, 4)
    swingAnchor  = MakeAnchor("Swing", 229, 8)
    -- Invisible handle: dragging it in the UI mover moves the WHOLE HUD.
    groupHandle  = MakeAnchor("GroupHandle", 170, 24)
    -- (2026-11-09) the target debuff row
    debuffAnchor = MakeAnchor("DebuffRow", 26, 26)
end

local function ApplyAnchorPositions()
    if not mainAnchor then return end     -- non-warrior: no anchors exist
    local cfg = WH.Store()
    if not cfg then return end
    local r = cfg.resources
    HUD.PlaceAnchor("whMainRow", holders.Main, cfg.mainRow)
    HUD.PlaceAnchor("whAuraRow", holders.AuraRow, cfg.auraRow)
    HUD.PlaceAnchor("whStance", holders.Stance, r.stance)
    HUD.PlaceAnchor("whExecute", holders.Execute, r.execute)
    HUD.PlaceAnchor("whRageBar", holders.RageBar, r.rage)
    HUD.PlaceAnchor("whSwing", holders.Swing, r.swing)
    HUD.PlaceAnchor("whDebuffRow", holders.DebuffRow, cfg.debuffRow)
    debuffAnchor:SetScale(cfg.debuffRow.scale or 1)
    if cfg.group then HUD.PlaceAnchor("whGroup", holders.GroupHandle, cfg.group) end
    -- Scales for icon groups; explicit bar sizes go via ApplyBarSizes.
    mainAnchor:SetScale(cfg.mainRow.scale or 1)
    auraAnchor:SetScale(cfg.auraRow.scale or 1)
    stanceAnchor:SetScale(r.stance.scale or 1)
    execAnchor:SetScale(r.execute.scale or 1)
    if D.ApplyBarSizes then D:ApplyBarSizes(cfg) end
end
D.ApplyAnchorPositions = ApplyAnchorPositions

local function RegisterMovers()
    -- No warrior mover entries cluttering move mode on other classes.
    local _, playerClass = UnitClass("player")
    if playerClass ~= "WARRIOR" then return end
    local cfg = WH.Store()
    if not cfg then
        C_Timer.After(1, RegisterMovers)   -- saved vars not ready yet
        return
    end
    HUD.RegisterMover("whMainRow", "Warrior HUD Cooldown Grid", holders.Main, cfg.mainRow)
    HUD.RegisterMover("whAuraRow", "Warrior HUD Active Buffs", holders.AuraRow, cfg.auraRow)
    HUD.RegisterMover("whStance", "Warrior HUD Stance Icon", holders.Stance, cfg.resources.stance)
    HUD.RegisterMover("whExecute", "Warrior HUD Execute Helper", holders.Execute, cfg.resources.execute)
    HUD.RegisterMover("whRageBar", "Warrior HUD Rage Bar", holders.RageBar, cfg.resources.rage)
    HUD.RegisterMover("whSwing", "Warrior HUD Swing Timers", holders.Swing, cfg.resources.swing)
    HUD.RegisterMover("whDebuffRow", "Warrior HUD Target Debuffs", holders.DebuffRow, cfg.debuffRow)

    -- Whole-HUD mover: dragging the handle shifts every member anchor by
    -- the same delta (HUD_Shared carries the delta to the members).
    cfg.group = cfg.group or { x = (cfg.mainRow.x or 0),
                               y = (cfg.mainRow.y or -208) + 50 }
    HUD.PlaceAnchor("whGroup", holders.GroupHandle, cfg.group)
    HUD.RegisterGroup("whGroup", "Warrior HUD - MOVE ALL", holders.GroupHandle, cfg.group, {
        { key = "whMainRow", holder = holders.Main },
        { key = "whAuraRow", holder = holders.AuraRow },
        { key = "whStance",  holder = holders.Stance },
        { key = "whExecute", holder = holders.Execute },
        { key = "whRageBar", holder = holders.RageBar },
        { key = "whSwing",   holder = holders.Swing },
        { key = "whDebuffRow", holder = holders.DebuffRow },
    })
    HUD.Debug("WarriorHUD anchors registered with the mover registry")
end
C_Timer.After(2, function()
    ApplyAnchorPositions()
    RegisterMovers()
end)

-- Main cooldown grid definitions (order = WA child order).
-- kind "spell" fields: spell = State.spells key; stance = visible only
-- in that stance (WA 2nd trigger); noGCD = no plain-GCD swipe;
-- usableDesat = desaturate when IsUsableSpell false; usableGlow = glow
-- while usable; meleeGlow = glow in melee; softRed = BT/WW tint +
-- <2s text hide + <3s yellow text. kind "item*": consumable icons.
-- (2026-11-09) add = true: an entry newer than the pack - off unless your
-- spec's defaults or your own tick turn it on (WH.IsOff), its icon made
-- the first time it is on. stance may be a set ({ [1] = true, [2] = true });
-- oldStance = the stance rule a save from before the spec defaults keeps
-- (a frozen save, WH.Store); whenUsable = shown only while the game says
-- it can be pressed (Victory Rush after a kill).
local FLAVOR = WH.FLAVOR or "era"
local TBC, FOREVER = FLAVOR == "tbc", FLAVOR == "forever"
local MAIN_DEFS = {
    { key = "mortalStrike", kind = "spell", spell = "mortalStrike" },
    { key = "deathWish",    kind = "spell", spell = "deathWish" },
    { key = "reck",         kind = "spell", spell = "reck", stance = 3 },
    { key = "retaliation",  kind = "spell", spell = "retaliation", stance = 1 },
    { key = "shieldWall",   kind = "spell", spell = "shieldWall", stance = 2 },
    -- BT/WW: WA inverse=false -> action-button swipe, unlike the rest.
    -- (WA's melee-range glow on BT intentionally dropped - user pref.)
    { key = "bt",           kind = "spell", spell = "bloodthirst", usableDesat = true,
      softRed = true, actionSwipe = true },
    { key = "ww",           kind = "spell", spell = "whirlwind", usableDesat = true,
      softRed = true, actionSwipe = true },
    -- (TBC: only after a critical strike)
    TBC and { key = "rampage", kind = "spell", spell = "rampage", usableDesat = true, noRange = true,
      add = true, label = "Rampage" } or false,
    FOREVER and { key = "spearingStrike", kind = "spell", spell = "spearingStrike",
      add = true, label = "Spearing Strike" } or false,
    FOREVER and { key = "recklessSwings", kind = "spell", spell = "recklessSwings", noRange = true,
      add = true, label = "Reckless Swings" } or false,
    { key = "overpower",    kind = "spell", spell = "overpower", usableDesat = true,
      noRange = true },
    -- only while the target is under 20%
    { key = "execute",      kind = "spell", spell = "execute", usableDesat = true, execOnly = true },
    (TBC or FOREVER) and { key = "victoryRush", kind = "spell", spell = "victoryRush", whenUsable = true,
      add = true, label = "Victory Rush (after a kill)" } or false,
    { key = "revenge",      kind = "spell", spell = "revenge", stance = 2,
      usableDesat = true, usableGlow = true },
    -- (greyed without a shield: the game calls it unusable)
    { key = "shieldSlam",   kind = "spell", spell = "shieldSlam", usableDesat = true,
      add = true, label = "Shield Slam" },
    TBC and { key = "devastate", kind = "spell", spell = "devastate", usableDesat = true,
      add = true, label = "Devastate" } or false,
    { key = "concussionBlow", kind = "spell", spell = "concussionBlow",
      add = true, label = "Concussion Blow" },
    { key = "charge",       kind = "spell", spell = "charge" },
    { key = "intercept",    kind = "spell", spell = "intercept", stance = 3, noGCD = true },
    TBC and { key = "intervene", kind = "spell", spell = "intervene", stance = 2, noRange = true,
      add = true, label = "Intervene" } or false,
    { key = "bloodrage",    kind = "spell", spell = "bloodrage" },
    { key = "berserkerRage", kind = "spell", spell = "berserkerRage", stance = 3 },
    { key = "taunt",        kind = "spell", spell = "taunt", stance = 2 },
    -- (no stance rule in the game: the WA's Defensive-only stays on a
    -- save from before the spec defaults)
    { key = "lastStand",    kind = "spell", spell = "lastStand", oldStance = 2 },
    { key = "challShout",   kind = "spell", spell = "challShout" },
    { key = "shieldBlock",  kind = "spell", spell = "shieldBlock", stance = 2 },
    TBC and { key = "spellReflect", kind = "spell", spell = "spellReflect", stance = { [1] = true, [2] = true },
      usableDesat = true, noRange = true, add = true, label = "Spell Reflection" } or false,
    -- Defensive only (user pref; the WA showed it in every stance).
    { key = "shieldBash",   kind = "spell", spell = "shieldBash", stance = 2 },
    -- (TBC and WoW Forever: Battle and Defensive Stance; Classic Era:
    -- Battle Stance only)
    (TBC or FOREVER) and { key = "thunderClap", kind = "spell", spell = "thunderClap",
      stance = { [1] = true, [2] = true }, oldStance = 1 }
      or { key = "thunderClap",  kind = "spell", spell = "thunderClap", stance = 1 },
    { key = "sweeping",     kind = "spell", spell = "sweeping" },
    { key = "pummel",       kind = "spell", spell = "pummel", stance = 3 },
    { key = "mockingBlow",  kind = "spell", spell = "mockingBlow", stance = 1 },
    { key = "intimShout",   kind = "spell", spell = "intimShout" },
    { key = "disarm",       kind = "spell", spell = "disarm" },
    { key = "potion",       kind = "itemPotion" },
    { key = "sapper",       kind = "itemSapper" },
    { key = "dense",        kind = "itemDense" },
    { key = "dummy",        kind = "itemDummy" },
}
-- (entries of another game version were left as false: closed up here)
local function Compact(list)
    local out = {}
    for i = 1, table.maxn(list) do
        if list[i] then out[#out + 1] = list[i] end
    end
    return out
end
MAIN_DEFS = Compact(MAIN_DEFS)

-- Is the stance right for this entry (frozen: a save from before the
-- spec defaults keeps the stance rules it had).
local function StanceOK(def, frozen)
    local st = def.stance
    if frozen and def.oldStance then st = def.oldStance end
    if not st then return true end
    if type(st) == "table" then return st[S.stance] and true or false end
    return S.stance == st
end

-- The page's lists follow the definitions: an entry newer than the pack
-- joins its list where it sits in the row.
local function JoinList(list, defs)
    for i, def in ipairs(defs) do
        if def.add then table.insert(list, i, { key = def.key, label = def.label, add = true }) end
    end
end

local mainIcons = {}      -- key -> icon frame

-- Ordered key/label list for the settings page checkboxes.
D.MainIconList = {
    { key = "mortalStrike", label = "Mortal Strike" },
    { key = "deathWish",    label = "Death Wish" },
    { key = "reck",         label = "Recklessness" },
    { key = "retaliation",  label = "Retaliation" },
    { key = "shieldWall",   label = "Shield Wall" },
    { key = "bt",           label = "Bloodthirst" },
    { key = "ww",           label = "Whirlwind" },
    { key = "overpower",    label = "Overpower" },
    { key = "execute",      label = "Execute (target under 20%)" },
    { key = "revenge",      label = "Revenge" },
    { key = "charge",       label = "Charge" },
    { key = "intercept",    label = "Intercept" },
    { key = "bloodrage",    label = "Bloodrage" },
    { key = "berserkerRage", label = "Berserker Rage" },
    { key = "taunt",        label = "Taunt" },
    { key = "lastStand",    label = "Last Stand" },
    { key = "challShout",   label = "Challenging Shout" },
    { key = "shieldBlock",  label = "Shield Block" },
    { key = "shieldBash",   label = "Shield Bash" },
    { key = "thunderClap",  label = "Thunder Clap" },
    { key = "sweeping",     label = "Sweeping Strikes" },
    { key = "pummel",       label = "Pummel" },
    { key = "mockingBlow",  label = "Mocking Blow" },
    { key = "intimShout",   label = "Intimidating Shout" },
    { key = "disarm",       label = "Disarm" },
    { key = "potion",       label = "Potion" },
    { key = "sapper",       label = "Sapper" },
    { key = "dense",        label = "Dynamite/Grenade" },
    { key = "dummy",        label = "Target Dummy" },
}
JoinList(D.MainIconList, MAIN_DEFS)

-- One grid icon for one def, on `parent` (the grid anchor, or the
-- settings preview's canvas: the sample is built by this same function).
local function MakeMainIcon(parent, def)
    local inverse = def.kind == "spell" or def.kind == "itemPotion"
    local icon = W.CreateIcon(parent, {
        width = 26, height = 26, zoom = W.ICON_ZOOM, keepAspect = true,
        inverse = inverse,
    })
    if def.actionSwipe and icon.cd then icon.cd:SetReverse(false) end
    icon:SetFrameStrata(HUD_STRATA)
    icon:Hide()
    icon.def = def
    icon._hudSpot = def.key      -- its own text spots (HUD.IconSpotSpec)
    do
        -- Center countdown: 14px on spell icons, 12px on items (WA sizes).
        local pSize = (def.kind == "spell" or def.kind == "customBuff") and 14 or 12
        icon:AddText("p", "CENTER", pSize, { 1, 1, 1, 1 })
        icon:SetText("p", "")

        if def.kind == "itemPotion" then
            icon:AddText("count", "INNER_BOTTOMRIGHT", 12, GOLD_COUNT, 0, 0)
        elseif def.kind == "itemSapper" then
            icon:AddText("count", "INNER_BOTTOMRIGHT", 12, YEL_COUNT, 0, 0)
            icon:AddText("plates", "CENTER", 12, CYAN_COUNT, 0, 0)
            icon:AddGlow("sapper", "buttonOverlay",
                { color = PEACH_GLOW, freq = 0.1 })
        elseif def.kind == "itemDense" or def.kind == "itemDummy" then
            icon:AddText("count", "INNER_BOTTOMRIGHT", 12, YEL_COUNT, 0, 0)
        end
        if def.usableGlow then
            icon:AddGlow("usable", "Pixel",
                { color = { 1, 1, 1, 1 }, freq = 0.25, lines = 8, length = 10, thickness = 1 })
        end
        if def.key == "ww" then
            -- how many mobs Whirlwind reaches (the sapper's plate scan),
            -- bottom-left in the count size; a cyan flash when that many
            -- stand there and the spell is ready and unused
            icon:AddText("mobs", "INNER_BOTTOMLEFT", 11, CYAN_COUNT, 1, 1)
            icon:SetText("mobs", "")
            icon:AddGlow("mobs", "buttonOverlay", { color = CYAN_COUNT, freq = 0.12 })
        end
        if def.meleeGlow then
            icon:AddGlow("melee", "buttonOverlay",
                { color = { 1, 0.9412, 0, 1 }, freq = 0.15 })
        end
    end
    return icon
end
D.MakeMainIcon = MakeMainIcon

local function BuildMainIcons()
    for _, def in ipairs(MAIN_DEFS) do
        -- (a later entry's icon is made the first time it is on)
        if not def.add then mainIcons[def.key] = MakeMainIcon(mainAnchor, def) end
    end
end

-- Main grid per-frame update helpers
local function CdRemaining(cd)
    if not cd or not cd.real then return 0 end
    return math.max(0, cd.start + cd.duration - GetTime())
end

-- The hesitation call-out on the HUD's own icons (HUD > Hesitation
-- watches the abilities and decides): gold = up with the rage, grey with
-- a steady red ring = up but no rage, a big fast red glow and the icon a
-- size bigger = the NOOB (it has sat unpressed past the grace).
local HES_GOLD = { 1, 0.82, 0.2, 1 }
local HES_RED = { 1, 0.15, 0.1, 1 }
local function ApplyHesitation(icon, name)
    local Hs = ns.Hesitation
    local st, usable, short, first
    if Hs and Hs.HudState then st, usable, short, first = Hs.HudState(name) end
    -- how much rage it is short while it is (nearly) back: "-6", top-right
    if short and not icon.texts.short then
        icon:AddText("short", "INNER_TOPRIGHT", 10, { 1, 0.3, 0.3, 1 }, -1, -1)
    end
    if icon.texts.short then icon:SetText("short", short and string.format("-%d", short) or "") end
    if st and not icon.glows.hReady then
        icon:AddGlow("hReady", "buttonOverlay", { color = HES_GOLD, freq = 0.15 })
        icon:AddGlow("hNoRage", "Pixel", { color = { HES_RED[1], HES_RED[2], HES_RED[3], 0.85 }, static = true })
        icon:AddGlow("hNoob", "Pixel", { color = HES_RED, size = 1.35, freq = 0.08 })
    end
    -- "ready2": up and pressable, but the other one goes first - no gold
    if icon.glows.hReady then
        icon:SetGlow("hReady", st == "ready")
        icon:SetGlow("hNoRage", st == "norage")
        icon:SetGlow("hNoob", st == "noob")
    end
    if st == "norage" or (st == "noob" and not usable) then icon:SetDesat(true) end
    -- the button to press first (Hesitation's NEXT mark) comes up a little
    W.SetPop(icon, st == "noob" and 1.3 or (first and 1.15) or 1)
end

local function UpdateSpellIcon(icon, def)
    local sp = S.spells[def.spell]
    local cd = S.cds[def.spell]
    local us = S.usable[def.spell] or {}
    local inRange = (not def.noRange) and S.inRange[def.spell] or nil

    icon:SetIconTexture(sp.icon)

    -- Swipe (includes GCD when the WA had "Show GCD" on)
    if cd then
        if def.noGCD and not cd.real then
            icon:ClearSwipe()
        else
            icon:SetSwipe(cd.start, cd.duration, cd.durObj)
        end
    end

    local desat = (cd and cd.real) or us.noPower or false
    -- Overpower lights for an open window in any stance (Zac 2026-11-03:
    -- "needs to light up ... even when im in berserker stance ... currently
    -- only does it when i swap to battle"): the game calls it unusable
    -- outside Battle Stance, but the dodge window is what matters
    local opOpen = def.key == "overpower" and ns.Overpower and ns.Overpower.Left and ns.Overpower.Left() > 0
    if def.usableDesat and us.usable == false and not opOpen then desat = true end
    local tint = nil
    if inRange == 0 then
        desat = true
        -- the out of range tint setting; Bloodthirst / Whirlwind wear a
        -- paler one (the WA's: about a third of the way to white)
        local c = WCol().oor
        if def.softRed then
            -- (one table, refilled only when the colour changes: this
            -- runs every pass for every Bloodthirst / Whirlwind out of reach)
            local st = D._softOor
            if not st then st = { 0, 0, 0 } D._softOor = st end
            if st.r ~= c[1] or st.g ~= c[2] or st.b ~= c[3] then
                st.r, st.g, st.b = c[1], c[2], c[3]
                st[1], st[2], st[3] = c[1] + (1 - c[1]) * 0.36, c[2] + (1 - c[2]) * 0.36, c[3] + (1 - c[3]) * 0.36
            end
            tint = st
        else
            tint = c
        end
    end
    icon:SetDesat(desat)
    if tint then
        icon:SetIconColor(tint[1], tint[2], tint[3], 1)
    else
        icon:SetIconColor(1, 1, 1, 1)
    end

    -- Glows (WA: Revenge glows purely on spellUsable == 1)
    if def.usableGlow then
        icon:SetGlow("usable", us.usable or false)
    end
    if def.meleeGlow then
        icon:SetGlow("melee",
            (S.inCombat and S.targetAttackable and S.inRange[def.spell] == 1) or false)
    end
    if def.key == "ww" then
        local cfg = WH.Store()
        -- the count Hesitation's Whirlwind call is using (the pack before
        -- a pull too); with its NEXT mark on, that mark is the one rule
        -- that lights this icon and the old "enough mobs" flash stays off
        local Hs = ns.Hesitation
        local hn, owned = nil, false
        if Hs and Hs.HudMobs then hn, owned = Hs.HudMobs() end
        local n = 0
        if cfg and cfg.wwCount ~= false then
            if hn then n = hn elseif S.inCombat then n = S.plateCount or 0 end
        end
        icon:SetText("mobs", n >= 2 and tostring(n) or "")
        local ready = not (cd and cd.real) and us.usable ~= false and not us.noPower
        local at = tonumber(cfg and cfg.wwFlashAt) or 4
        icon:SetGlow("mobs", (not owned and n >= at and ready) or false)
    end
    ApplyHesitation(icon, sp.name)
end

-- Countdown texts (0.1s ticker). NB: the WA's "duration < 2 -> hide
-- text" compares TOTAL duration (suppress pure-GCD text), not time
-- remaining; CdRemaining() returns 0 for pure GCDs already.
local function UpdateSpellIconText(icon, def)
    local remaining = CdRemaining(S.cds[def.spell])
    icon:SetText("p", remaining > 0 and W.FormatTime(remaining, 0) or "")
end

-- Item icon updates
local function ItemCdInfo(itemId)
    local start, duration = WH.GetItemCD(itemId)
    local real = duration > 1.51
    local remaining = real and math.max(0, start + duration - GetTime()) or 0
    return real, start, duration, remaining
end

local function ResolvePotion()
    local cfg = WH.Store()
    local sel = cfg and WH.POTION_DROPDOWN[cfg.potionChoice or 1] or nil
    if sel then
        local entry = S.items[sel.id]
        if entry and (entry.count or 0) > 0 then
            return sel, entry.count
        end
    end
    return WH.FirstAvailable(WH.POTION_LIST)
end

-- A grid icon bound to a smart macro shows whatever that macro's winning
-- rule currently points at, instead of picking from its own item list. The
-- return is shaped like a POTION_LIST/DENSE_LIST entry so the rest of
-- UpdateItemIcon does not care where the item came from.
-- SmartMacro re-evaluates on target change and on bag/cooldown events; this
-- only reads the recorded result, so it costs a table lookup per refresh.
local function ResolveBoundMacro(def)
    local cfg = WH.Store()
    local name = cfg and cfg.mainRow.macroBind and cfg.mainRow.macroBind[def.key]
    if not name or name == "" then return nil end
    local SM = HUD.SmartMacro()
    local act = SM and SM.GetActive and SM:GetActive(name)
    if not (act and act.itemId) then return nil end
    -- GetItemInfo returns nothing for an item the client has not cached
    -- yet, so SmartMacro can record a hit with no texture. Retry here
    -- rather than blank the icon until the next macro re-evaluation.
    local tex = act.icon
    if not tex and act.item then tex = select(10, GetItemInfoC(act.item)) end
    if not tex then return nil end
    -- The resolved item is usually not one the HUD tracks at load, so it
    -- has to join the bag scan before GetItemCD can see its cooldown.
    WH.TrackExtraItem(act.itemId)
    local e = S.items[act.itemId]
    return { id = act.itemId, icon = tex }, (e and e.count or 0)
end

local function UpdateItemIcon(icon, def)
    local item, count
    local bound, boundCount = ResolveBoundMacro(def)
    if bound then
        item, count = bound, boundCount
    elseif def.kind == "itemPotion" then
        item, count = ResolvePotion()
    elseif def.kind == "itemSapper" then
        -- (one table for good, not one a pass: it is only read)
        item = D._sapperItem
        if not item then item = { id = WH.SAPPER_ID, icon = 135826 } D._sapperItem = item end
        local e = S.items[WH.SAPPER_ID]
        count = e and e.count or 0
    elseif def.kind == "itemDense" then
        item, count = WH.FirstAvailable(WH.DENSE_LIST)
    else
        item, count = WH.FirstAvailable(WH.DUMMY_LIST)
    end
    icon.curItem = item
    if not item or count == 0 then return false end

    icon:SetIconTexture(item.icon)
    icon:SetText("count", tostring(count))

    local real, start, duration = ItemCdInfo(item.id)
    icon:SetSwipe(start, duration)
    icon:SetDesat(real)
    icon.itemOnCd = real

    if def.kind == "itemSapper" then
        local cfg = WH.Store()
        local threshold = cfg and cfg.sapperThreshold or 7
        local glowing = (not real) and S.plateCount >= threshold
        icon:SetGlow("sapper", glowing)
        if glowing then WH.SapperTTS() end
    end
    return true
end

local function UpdateItemIconText(icon, def)
    local item = icon.curItem
    if not item then return end
    local thresh = (def.kind == "itemPotion") and 60 or 3
    local real, _, _, remaining = ItemCdInfo(item.id)
    icon:SetText("p", real and W.FormatTime(remaining, thresh) or "")
    if def.kind == "itemSapper" then
        -- Cyan plate count only while off cd (WA sub.4/sub.6 flip)
        if real then
            icon:SetText("plates", "")
        else
            icon:SetText("plates", S.plateCount > 0 and tostring(S.plateCount) or "")
        end
    end
end

-- Preview texture for a grid def (force-preview + pinned mini preview).
-- the positioned holder of one HUD piece ("AuraRow", "Main"...), for
-- things that want to sit next to it (the hesitation alert)
function D.Holder(name) return holders[name] end

function D.MainDefPreviewTex(def)
    if def.kind == "spell" then
        local sp = S.spells[def.spell]
        return sp and sp.icon
    elseif def.kind == "customBuff" then
        return PreviewNameIcon(def.name)
    end
    -- A bound icon previews the item its macro currently points at, so the
    -- preview matches what the grid will actually draw.
    local bound = ResolveBoundMacro(def)
    if bound then return bound.icon end
    if def.kind == "itemPotion" then return 134831
    elseif def.kind == "itemSapper" then return 135826
    elseif def.kind == "itemDense" then return 133714
    elseif def.kind == "itemDummy" then return 132762
    end
end

-- Did the shown-icon list change since the last layout? Compared by
-- position against the copy kept from last time, so a 0.2 s tick with the
-- same icons in the same order builds no string and lays nothing out.
local function ListMoved(list, last)
    local n = #list
    if n ~= (last.n or -1) then return true end
    for i = 1, n do if last[i] ~= list[i] then return true end end
    return false
end
local function RememberList(list, last)
    local n = #list
    for i = 1, n do last[i] = list[i] end
    for i = n + 1, (last.n or 0) do last[i] = nil end
    last.n = n
end

-- The user's custom entry lists are edited in place by the config page,
-- so "did they change" is a field-by-field compare against what the
-- icons were last built from - no per-tick string.
local function CustomListSame(list, src)
    if #list ~= #src then return false end
    for i = 1, #list do
        local e, c = list[i], src[i]
        if e.input ~= c.input or e.kind ~= c.kind or e.stance ~= c.stance then return false end
    end
    return true
end
local function RememberCustomList(list, src)
    for i = 1, #list do
        local e = list[i]
        local c = src[i]
        if not c then c = {} src[i] = c end
        c.input, c.kind, c.stance = e.input, e.kind, e.stance
    end
    for i = #list + 1, #src do src[i] = nil end
end

-- User-added cooldown icons: behave like template spell icons; frames
-- created on demand and re-used, keyed "cust<i>" (Core's State.spells).
local customMainDefs, customMainSrc = {}, {}

local function EnsureCustomMainIcons(cfg)
    local list = cfg.mainRow.custom or {}
    if customMainSrc.built and CustomListSame(list, customMainSrc) then return end
    RememberCustomList(list, customMainSrc)
    customMainSrc.built = true
    wipe(customMainDefs)
    for i = 1, #list do
        local entry = list[i]
        local key = "cust" .. i
        local kind = entry.kind or "cd"
        local stance = (entry.stance and entry.stance > 0) and entry.stance or nil
        if kind == "buff" then
            local id = tonumber(entry.input)
            local name = entry.input
            if id and GetSpellInfoC then name = GetSpellInfoC(id) or entry.input end
            customMainDefs[i] = { key = key, kind = "customBuff",
                name = name, stance = stance }
        else
            customMainDefs[i] = { key = key, kind = "spell", spell = key,
                stance = stance }
        end
        local icon = mainIcons[key]
        if not icon then
            icon = W.CreateIcon(mainAnchor, { width = 26, height = 26,
                zoom = W.ICON_ZOOM, keepAspect = true, inverse = true })
            icon:SetFrameStrata(HUD_STRATA)
            icon:Hide()
            icon:AddText("p", "CENTER", 14, { 1, 1, 1, 1 })
            mainIcons[key] = icon
        end
        icon.def = customMainDefs[i]
    end
    local i = #list + 1        -- hide frames past the shrunken list
    while mainIcons["cust" .. i] do
        mainIcons["cust" .. i]:Hide()
        i = i + 1
    end
    if D.ApplyAppearance then D:ApplyAppearance(cfg) end
end

-- Main grid refresh
local mainActive = {}
local mainLast = {}
local mainHold = W.NewHold()      -- (W.HeldList: a leaving icon's place kept a moment)

-- A held place closes on the first pass after its time is up. In a fight
-- that pass is a fifth of a second away anyway; out of one the HUD only
-- looks once a second, so one wake is booked for when the hold ends (one
-- timer however many places are held, and none while one is booked).
local holdWakeBooked = false
local function WakeWhenHoldEnds()
    if holdWakeBooked or S.inCombat then return end
    holdWakeBooked = true
    C_Timer.After((W.HOLD or 0.4) + 0.02, function()
        holdWakeBooked = false
        if WH.Wake then WH.Wake() end
    end)
end

-- one grid icon per call (a file-level function: the 0.2s refresh used to
-- build this closure on every tick)
local function MainHandle(def, cfg, frozen)
    local off = WH.IsOff("main", def, cfg)
    local icon = mainIcons[def.key]
    if not icon then
        if off then return end
        icon = MakeMainIcon(mainAnchor, def)
        mainIcons[def.key] = icon
        D.StyleIcon(icon, cfg)
        D._styleSerial = nil      -- the shared look with the rest on the next pass
    end
    local visible = false
    if D.preview and not off then
        icon:SetIconTexture(D.MainDefPreviewTex(def) or QUESTION_ICON)
        icon:ClearSwipe()
        icon:SetDesat(false)
        icon:SetIconColor(1, 1, 1, 1)
        for gk in pairs(icon.glows) do icon:SetGlow(gk, false) end
        W.SetPop(icon, 1)
        icon:SetText("p", "")
        if icon.texts.count then icon:SetText("count", "") end
        if icon.texts.plates then icon:SetText("plates", "") end
        if icon.texts.mobs then icon:SetText("mobs", "") end
        if icon.texts.short then icon:SetText("short", "") end
        visible = true
    elseif not off and StanceOK(def, frozen) then
        if def.kind == "spell" then
            local sp = S.spells[def.spell]
            visible = sp and sp.known or false
            local ghost = (not visible) and cfg.showUnlearned and sp and sp.name and true or false
            if ghost then visible = HUD.Ghost(icon, sp) end
            if visible and not ghost and def.whenUsable then
                local us = S.usable[def.spell]
                visible = (us and us.usable) and true or false
            end
            if visible and not ghost and def.execOnly then
                visible = S.targetAttackable and HUD.TargetHealthFrac() <= 0.20 or false
            end
            if visible and not ghost then UpdateSpellIcon(icon, def) end
        elseif def.kind == "customBuff" then
            local b = def.name and (S.buffs[def.name:lower()]
                or S.selfDebuffs[def.name:lower()])
            if b then
                icon:SetIconTexture(b.icon)
                if (b.duration or 0) > 0 then
                    icon:SetSwipe(b.expirationTime - b.duration, b.duration)
                else
                    icon:ClearSwipe()
                end
                icon:SetDesat(false)
                icon:SetIconColor(1, 1, 1, 1)
                icon.buffRef = b
                visible = true
            end
        else
            visible = UpdateItemIcon(icon, def)
        end
    end
    if visible then
        mainActive[#mainActive + 1] = icon
        W.SetShownAnimated(icon, true)
    else
        if icon._pop then W.SetPop(icon, 1) end
        W.SetShownAnimated(icon, false)
    end
end

local function RefreshMainRow(cfg)
    local show = cfg.mainRow.enabled
    wipe(mainActive)
    if show then
        EnsureCustomMainIcons(cfg)
        local frozen = cfg.specFrozen
        for _, def in ipairs(MAIN_DEFS) do MainHandle(def, cfg, frozen) end
        for _, def in ipairs(customMainDefs) do MainHandle(def, cfg, frozen) end
    else
        for _, icon in pairs(mainIcons) do icon:Hide() end
    end
    local list, held = mainActive, false
    if not D.preview then list, held = W.HeldList(mainActive, mainLast, mainHold, GetTime()) end
    if held then WakeWhenHoldEnds() end
    if ListMoved(list, mainLast) then
        RememberList(list, mainLast)
        W.LayoutMainRow(mainAnchor, list, cfg.mainRow.rows, cfg.mainRow.spacing)
    end
end

-- Resources: stance HUD, execute helper, rage bar, swing bars
local stanceIcon, execIcon, rageBar, swingMH, swingOH
D.STANCE_ICONS, D.EXEC_ICON, D.BT_ICON = STANCE_ICONS, EXEC_ICON, BT_ICON

-- ============================================================
-- IS THE QUEUED SWING ABOUT TO STARVE BLOODTHIRST / WHIRLWIND?
-- ============================================================
-- Heroic Strike / Cleave only spend their rage when the main-hand swing
-- lands, so it is all about WHEN, measured on the swing timer:
--  * the ability comes back BEFORE the swing lands: press it first and
--    nothing is lost - it only goes wrong if what you have now (plus
--    the off-hand's rage until the swing) cannot pay for both, or if
--    the swing lands so soon after it is back (REACT) that it has to be
--    pressed this instant;
--  * the swing lands FIRST: what is left after it, plus the off-hand's
--    rage until the ability is back, must pay for it - and if it is
--    back within GAP of the swing there is no time to build the rest.
-- Off-hand rage per hit is learned from your own hits (S.ohRage).
-- No swing data yet (no swing seen this fight): the plain rule - it is
-- back within 1.5s and what is left after the swing is short.
local REACT, GAP = 0.6, 2.0
local function OHHits(sw, now, t)
    if not (sw and sw.hasOH and sw.oh.duration and sw.oh.duration > 0 and sw.oh.start) then return 0 end
    local nextOH = sw.oh.start + sw.oh.duration
    while nextOH < now do nextOH = nextOH + sw.oh.duration end
    local n = 0
    while nextOH <= now + t and n < 5 do n = n + 1 nextOH = nextOH + sw.oh.duration end
    return n
end
-- one ability's verdict (a plain function: this runs ~20 times a second
-- while a swing is queued, so it builds nothing)
local function StarveCheck(key, need, power, cost, now, sw, tS, ohRage)
    local sp = S.spells[key]
    if not (sp and sp.known) then return false end
    need = need or 30
    local cd = S.cds[key]
    local tX = (cd and cd.real) and (cd.start + cd.duration - now) or 0
    if tX < 0 then tX = 0 end
    if not tS then
        return tX < 1.5 and power - cost < need
    end
    if tX <= tS then
        -- back before the swing lands
        local before = power + OHHits(sw, now, tS) * ohRage
        if before - cost >= need then return false end          -- enough for both
        if power + OHHits(sw, now, tX) * ohRage < need then return true end   -- it is starved already
        return (tS - tX) < REACT                                 -- has to be pressed right now
    end
    -- the swing lands first
    if tX - tS > GAP then return false end                       -- time to build it back
    local after = power - cost + OHHits(sw, now, tX) * ohRage
    return after < need
end
function D.QueueStarves(power, cost, now)
    now = now or GetTime()
    local sw = S.swing
    local tS
    if sw and sw.mh and sw.mh.start and (sw.mh.duration or 0) > 0 then
        tS = sw.mh.start + sw.mh.duration - now
        if tS < 0 then tS = 0 end
        if tS > sw.mh.duration then tS = nil end
    end
    local ohRage = S.ohRage or 5
    if StarveCheck("bloodthirst", S.btCost, power, cost, now, sw, tS, ohRage) then return "bloodthirst" end
    if StarveCheck("whirlwind", S.wwCost, power, cost, now, sw, tS, ohRage) then return "whirlwind" end
    return nil
end
-- the queued swing's block on the rage bar: Heroic Strike gold, Cleave green
local Q_HS     = { 1, 0.8, 0.25, hex = "ffcc40" }
local Q_CLEAVE = { 0.35, 0.95, 0.35, hex = "59f259" }

-- The resource pieces, each built on the anchor it is given: the live
-- HUD's, or the settings preview's canvas (its sample is made by these
-- same functions; only the live ones get the drivers below).
function D.MakeStanceIcon(parent)
    -- Stance HUD (WA 34x36; tuned to 32x34 to line up with player frame)
    local icon = W.CreateIcon(parent, { width = 32, height = 34, zoom = W.ICON_ZOOM,
        keepAspect = true, noCooldown = true })
    icon:SetFrameStrata(HUD_STRATA)
    icon:SetPoint("CENTER", parent, "CENTER", 0, 0)
    icon:Hide()
    return icon
end

function D.MakeExecIcon(parent)
    local icon = W.CreateIcon(parent, { width = 40, height = 38, zoom = W.ICON_ZOOM,
        keepAspect = true })
    icon:SetFrameStrata(HUD_STRATA)
    -- No countdown text: the swipe shows BT's cd; a number was misread.
    icon:SetPoint("CENTER", parent, "CENTER", 0, 0)
    icon:Hide()
    return icon
end

function D.MakeRageBar(parent)
    local rageBar = W.CreateBar(parent, { width = 229, height = 4,
        barColor = WCol().rage })
    rageBar:SetFrameStrata(HUD_STRATA)
    rageBar:SetPoint("CENTER", parent, "CENTER", 0, 0)
    -- Created on the StatusBar so it draws above the fill texture.
    local rt = HUD.Text(rageBar.bar, 14, "OUTLINE", "OVERLAY", "text")
    rt:SetPoint("CENTER", rageBar, "CENTER", 0, 0)
    rt:SetTextColor(1, 1, 1)
    -- over the cost marks and the queued-swing block below
    rt:SetDrawLayer("OVERLAY", 7)
    rageBar.text = rt
    if HUD.BarText then HUD.BarText(rt, rageBar) end
    -- The rage a queued Heroic Strike / Cleave is going to spend: a block
    -- over the end of the fill (gold for HS, green for Cleave), as wide as
    -- the cost. It turns white and blinks when the swing is going to cost
    -- you the next Bloodthirst / Whirlwind (D.QueueStarves, swing-timed). Marks on the bar at what BT and WW
    -- cost show at a glance when there is enough.
    local fillTex = rageBar.bar:GetStatusBarTexture()
    local qSeg = rageBar.bar:CreateTexture(nil, "OVERLAY", nil, 2)
    qSeg:SetTexture(W.WHITE_TEX or "Interface\\Buttons\\WHITE8X8")
    qSeg:SetPoint("TOPRIGHT", fillTex, "TOPRIGHT", 0, 0)
    qSeg:SetPoint("BOTTOMRIGHT", fillTex, "BOTTOMRIGHT", 0, 0)
    qSeg:Hide()
    rageBar.qSeg = qSeg
    rageBar.marks = {}
    for i = 1, 2 do
        -- on the StatusBar, like the block above: a texture on rageBar
        -- itself draws UNDER its child bar's fill, whatever its layer
        -- (Zac: "the 2 white lines are behind the rage bar")
        local m = rageBar.bar:CreateTexture(nil, "OVERLAY", nil, 3)
        m:SetTexture(W.WHITE_TEX or "Interface\\Buttons\\WHITE8X8")
        m:SetVertexColor(1, 1, 1, 0.75)
        m:SetWidth(1)
        m:Hide()
        rageBar.marks[i] = m
    end
    return rageBar
end

-- Swing timer bars (229x3; OH sits 4px above MH like the WA offsets)
function D.MakeSwingBars(parent)
    local swingMH = W.CreateBar(parent, { width = 229, height = 3, spark = true,
        barColor = WCol().swingMH })
    swingMH:SetFrameStrata(HUD_STRATA)
    swingMH:SetPoint("CENTER", parent, "CENTER", 0, 0)
    swingMH:Hide()
    -- the off hand thin and steel blue, the main hand thick and white: told
    -- apart at a glance without a label (sizes in D:ApplyBarSizes)
    local swingOH = W.CreateBar(parent, { width = 229, height = 3, spark = true,
        barColor = WCol().swingOH })
    swingOH:SetFrameStrata(HUD_STRATA)
    swingOH:SetPoint("CENTER", parent, "CENTER", 0, 4)
    swingOH:Hide()
    -- smooth: the fill, its sheen and the spark move by fractions of a
    -- pixel instead of snapping to whole pixels (whole-pixel steps at
    -- ~90px/s come out as uneven 1-2px hops every frame - the jitter)
    for _, b in ipairs({ swingMH, swingOH }) do
        local list = { b.bar.GetStatusBarTexture and b.bar:GetStatusBarTexture(), b.spark, b.fillSheen }
        for i = 1, 3 do
            local t = list[i]
            if t then
                if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false) end
                if t.SetTexelSnappingBias then t:SetTexelSnappingBias(0) end
            end
        end
    end
    return swingMH, swingOH
end

-- "Swing bar height" sets the pair: the main hand comes out thicker
-- (3 -> 5px), the off hand thinner (3 -> 2px), 1px apart. The main hand
-- stays centred where it always was. Returns the pair's total height.
function D.SizeSwingBars(swingMH, swingOH, parent, w, h)
    local mhH, ohH = D.SwingHeights(h)
    swingMH:SetSize(w, mhH)
    swingOH:SetSize(w, ohH)
    if swingMH.spark then swingMH.spark:SetHeight(mhH * 2.2) end
    if swingOH.spark then swingOH.spark:SetHeight(math.max(6, ohH * 2.5)) end
    swingOH:ClearAllPoints()
    swingOH:SetPoint("CENTER", parent, "CENTER", 0, mhH / 2 + 1 + ohH / 2)
    return mhH + 2 * ohH + 2
end

local function BuildResources()
    stanceIcon = D.MakeStanceIcon(stanceAnchor)
    execIcon = D.MakeExecIcon(execAnchor)
    -- Rage bar (229x4). Value updates on its own OnUpdate with lerp
    -- smoothing (the WA had smoothProgress on); only runs while shown.
    rageBar = D.MakeRageBar(rageAnchor)
    D.rageBar = rageBar
    -- Per frame: one rage read; a frame where nothing moved (same rage,
    -- the bar caught up, no queued swing) stops there. The "is the queued
    -- swing starving Bloodthirst / Whirlwind" verdict is worked out about
    -- 20 times a second (and at once when the rage or the cost changes);
    -- only its white blink is drawn every frame.
    local STARVE_EVERY = 0.05
    rageBar:SetScript("OnUpdate", function(self, elapsed)
        -- a colour setting changed: repaint on this frame
        if self._colSerial ~= HUD.serial then
            self._colSerial = HUD.serial
            self.lastPct, self.settled, self._qc = nil, false, nil
            local tc = WCol().rageText
            self.text:SetTextColor(tc[1], tc[2], tc[3], tc[4])
        end
        local power = UnitPower("player", 1) or 0
        local maxPower = UnitPowerMax("player", 1) or 100
        -- WoW Forever can hand back the rage as a hidden value: no maths or
        -- comparisons on it, so the bar and the number take it as it is
        -- (both accept hidden values) and the queued-swing block, the
        -- smoothing and the low-rage colour sit out until it reads again.
        if Hidden(power) or Hidden(maxPower) then
            if not self._secretPow then
                self._secretPow = true
                self.displayValue, self.lastPct, self._lastPow, self.settled = nil, nil, nil, false
                if self.qSeg:IsShown() then self.qSeg:Hide() end
                D.qStarving, self._qStarve, self._qc = false, nil, nil
                self._sAcc, self._sPow, self._sCost = nil, nil, nil
                local C = WCol()
                self:SetBarColor(C.rage[1], C.rage[2], C.rage[3], C.rage[4])
            end
            local okMax = Hidden(maxPower) and 100 or maxPower
            self.bar:SetMinMaxValues(0, okMax)
            self.bar:SetValue(power)
            self.text:SetText(power)
            return
        elseif self._secretPow then
            self._secretPow = nil
            self.bar:SetMinMaxValues(0, 1)
            self.displayValue, self.lastPct, self.settled = nil, nil, false
        end
        -- the queued swing (S.hsQueued / S.cleaveQueued, the core's scan)
        local cost = (self.qOn and (S.hsQueued and (S.hsCost or 15) or (S.cleaveQueued and (S.cleaveCost or 20)))) or nil
        if not cost and self.settled and power == self._lastPow and maxPower == self._lastMax
            and not self.qSeg:IsShown() then
            return
        end
        self._lastMax = maxPower
        local target = maxPower > 0 and (power / maxPower) or 0
        local cur = self.displayValue or target
        local diff = target - cur
        if math.abs(diff) < 0.002 then
            cur = target
            self.settled = true
        else
            cur = cur + diff * math.min(1, elapsed * 12)
            self.settled = false
        end
        self.displayValue = cur
        self.bar:SetValue(cur)
        local pct = math.floor(target * 100 + 0.5)
        -- gold for Heroic Strike, green for Cleave
        local C = WCol()
        local qc = (cost and not S.hsQueued) and C.queueCleave or C.queueHS
        -- learn what an off-hand hit brings in: a rage rise landing right
        -- after an off-hand swing (and not a main-hand one) is that hit
        local now = GetTime()
        if self._lastPow and power > self._lastPow then
            local sw = S.swing
            if sw and sw.hasOH and sw.oh.start and now - sw.oh.start < 0.3
                and not (sw.mh.start and now - sw.mh.start < 0.3) then
                local d = power - self._lastPow
                if d > 0 and d < 40 then S.ohRage = (S.ohRage or 5) * 0.8 + d * 0.2 end
            end
        end
        self._lastPow = power
        local starve = false
        if cost and power > 0 then
            self._sAcc = (self._sAcc or STARVE_EVERY) + elapsed
            if self._sAcc >= STARVE_EVERY or self._sPow ~= power or self._sCost ~= cost then
                self._sAcc, self._sPow, self._sCost = 0, power, cost
                self._sVal = (D.QueueStarves(power, cost, now)) and true or false
            end
            starve = self._sVal
            local w = (self.bar:GetWidth() or 229) * math.min(cost, power) / math.max(1, maxPower)
            if self.qW ~= w then self.qW = w self.qSeg:SetWidth(math.max(1, w)) end
            if starve then
                self._qt = (self._qt or 0) + elapsed
                self.qSeg:SetVertexColor(1, 1, 1, 0.55 + 0.4 * math.abs(math.sin(self._qt * 8)))
            elseif self._qStarve ~= false or self._qc ~= qc then
                self.qSeg:SetVertexColor(qc[1], qc[2], qc[3], qc[4] or 0.9)
            end
            if self._qc ~= qc then self._qc = qc self.lastPct = nil end
            if self._qStarve ~= starve then self._qStarve = starve self.lastPct = nil end
            D.qStarving = starve
            if not self.qSeg:IsShown() then self.qSeg:Show() self.lastPct = nil end
        elseif self.qSeg:IsShown() then
            self.qSeg:Hide()
            D.qStarving = false
            self._qStarve = nil
            self._qc = nil
            self._sAcc, self._sPow, self._sCost = nil, nil, nil
            self.lastPct = nil
        end
        if pct ~= self.lastPct then
            self.lastPct = pct
            -- just the rage: the coloured block shows what a queued swing takes
            self.text:SetText(tostring(pct))
            local rc = (pct <= 30) and C.rageLow or C.rage
            self:SetBarColor(rc[1], rc[2], rc[3], rc[4])
        end
    end)
    rageBar:Hide()

    swingMH, swingOH = D.MakeSwingBars(swingAnchor)

    -- Swing animation driver: runs every frame while the bars are allowed
    -- (HUD on, swing timers on, in combat - set by the 0.2s refresh) and
    -- shows / hides each bar itself the moment its swing starts or runs
    -- out, so a bar never waits up to 0.2s to appear (the old blink at
    -- every swing). A bar stays up GRACE past zero: the swing usually
    -- lands a moment after the timer ends, and hiding in that gap made it
    -- flicker. No table allocation inside the handler.
    local GRACE = 0.35
    local driver = CreateFrame("Frame")
    driver:Hide()
    local function AnimateSwing(barF, sw, allow, now)
        if D.preview then
            if not barF:IsShown() then return false end
            barF.bar:SetValue(0.65)
            if barF.UpdateSpark then barF:UpdateSpark(0.65) end
            return true
        end
        if not allow then
            if barF:IsShown() then barF:Hide() end
            return false
        end
        local dur = sw.duration or 0
        local remaining = dur > 0 and (sw.start + dur - now) or -1
        local active = dur > 0 and remaining > -GRACE
        if active ~= (barF:IsShown() and true or false) then barF:SetShown(active) end
        -- (WoW Forever: a hidden swing time runs on the game's clock)
        if active and HUD.TimedSwing(barF, sw.durObj) then return true end
        HUD.UntimedSwing(barF)
        if active then
            local frac = remaining > 0 and remaining / dur or 0
            if frac > 1 then frac = 1 end
            barF.bar:SetValue(frac)
            if barF.UpdateSpark then barF:UpdateSpark(frac) end
        end
        return true
    end
    driver:SetScript("OnUpdate", function()
        local now = GetTime()
        local a = AnimateSwing(swingMH, S.swing.mh, D.swingAllowMH, now)
        local b = AnimateSwing(swingOH, S.swing.oh, D.swingAllowOH, now)
        if not (a or b) then driver:Hide() end
    end)
    D.swingDriver = driver

    D:ApplyBarSizes()
end

-- Main-hand / off-hand bar heights from the one height setting.
function D.SwingHeights(h)
    h = h or 3
    return math.floor(h * 1.6 + 0.5), math.max(2, math.floor(h * 0.6 + 0.5))
end

-- Bar sizing from settings; safe to call before BuildResources runs.
function D:ApplyBarSizes(cfg)
    cfg = cfg or WH.Store()
    if not cfg then return end
    local r = cfg.resources
    -- Holders follow the bar size too: the mover proxy is sized from them.
    if rageBar then
        local w, h = r.rage.w or 229, r.rage.h or 4
        rageBar:SetSize(w, h)
        rageAnchor:SetSize(w, h)
        holders.RageBar:SetSize(w, h)
    end
    -- Stance icon: optional w/h in the store (default 32x34); its
    -- border is drawn outside this rect.
    if stanceIcon and r.stance then
        local w, h = r.stance.w or 32, r.stance.h or 34
        stanceIcon:SetSize(w, h)
        stanceAnchor:SetSize(w, h)
        holders.Stance:SetSize(w, h)
    end
    if swingMH then
        local w, h = r.swing.w or 229, r.swing.h or 3
        local total = D.SizeSwingBars(swingMH, swingOH, swingAnchor, w, h)
        swingAnchor:SetSize(w, total)
        holders.Swing:SetSize(w, total)
    end
end

-- Execute helper (WA custom trigger): toggle AND BT known AND Execute
-- known AND attackable target at <=20% hp. Runs from the 0.2s tick AND
-- the 0.1s text ticker (fresh HP read) so changes show next frame.
local function UpdateExecuteHelper()
    if not execIcon or D.preview then return end
    if not D._execEnabled then execIcon:Hide() return end

    if UnitExists("target") then
        S.targetHPpct = HUD.TargetHealthFrac() * 100
    else
        S.targetHPpct = 100
    end

    -- (WoW Forever hides the target's health in combat: the game answers
    -- "under 20%?" itself, as the icon's alpha - see the end)
    local hiddenAlpha = S.targetAttackable and HUD.TargetExecuteAlpha(0.2) or nil
    local bt, ex = S.spells.bloodthirst, S.spells.execute
    local execShown = bt and bt.known and ex and ex.known
        and S.targetAttackable and (hiddenAlpha ~= nil or S.targetHPpct <= 20)
    if execShown then
        local btCd = S.cds.bloodthirst
        local btRemaining = CdRemaining(btCd)
        -- the attack power where Bloodthirst beats Execute: Hesitation's
        -- setting (one line for both; 0 = always Execute)
        local Hs = ns.Hesitation
        local hcfg = Hs and Hs.Store and Hs.Store()
        local line = hcfg and tonumber(hcfg.execBTap) or 2000
        local apMode = line > 0 and S.ap >= line
        local btReady = (not (btCd and btCd.real)) or btRemaining < 1
        execIcon:SetIconTexture((apMode and btReady) and BT_ICON or EXEC_ICON)
        local usBT = S.usable.bloodthirst or {}
        local usEx = S.usable.execute or {}
        local desat
        if apMode then
            desat = btReady and (usBT.usable == false or usBT.noPower) or false
        else
            desat = (usEx.usable == false or usEx.noPower) and true or false
        end
        execIcon:SetDesat(desat)
        if btCd and btCd.real then
            execIcon:SetSwipe(btCd.start, btCd.duration, btCd.durObj)
        else
            execIcon:ClearSwipe()
        end
        execIcon:Show()
        if hiddenAlpha ~= nil then
            execIcon:SetAlpha(hiddenAlpha)
            execIcon._zHiddenA = true
        elseif execIcon._zHiddenA then
            execIcon._zHiddenA = nil
            execIcon:SetAlpha(1)
        end
    else
        execIcon:Hide()
    end
end

local function RefreshResources(cfg)
    local r = cfg.resources
    local show = r.enabled

    -- Settings preview: show every enabled element with static content
    if D.preview then
        if show and r.stanceHud then
            stanceIcon:SetIconTexture(STANCE_ICONS[S.stance] or STANCE_ICONS[1])
            stanceIcon:Show()
        else
            stanceIcon:Hide()
        end
        if show and r.executeHelper then
            execIcon:SetIconTexture(EXEC_ICON)
            execIcon:SetDesat(false)
            execIcon:ClearSwipe()
            if execIcon._zHiddenA then execIcon._zHiddenA = nil execIcon:SetAlpha(1) end
            execIcon:Show()
        else
            execIcon:Hide()
        end
        rageBar:SetShown(show and r.rageBar or false)
        swingMH:SetShown(show and r.swingTimer or false)
        swingOH:SetShown(show and r.swingTimer or false)
        if show and r.swingTimer and not D.swingDriver:IsShown() then
            D.swingDriver:Show()
        end
        return
    end

    local st = S.stance
    if show and r.stanceHud and STANCE_ICONS[st] then
        stanceIcon:SetIconTexture(STANCE_ICONS[st])
        stanceIcon:Show()
    else
        stanceIcon:Hide()
    end

    D._execEnabled = (show and r.executeHelper) or false
    UpdateExecuteHelper()

    if show and r.rageBar then
        rageBar:Show()
        rageBar.qOn = r.rageQueue ~= false
        -- the BT / WW cost marks: only for what this character knows,
        -- placed again only when the cost, the bar or the max changes
        local bw = rageBar.bar:GetWidth() or 229
        local mx = UnitPowerMax("player", 1) or 100
        if Hidden(mx) or mx <= 0 then mx = 100 end
        local c1, c2
        if r.rageMarks ~= false then
            if S.spells.bloodthirst and S.spells.bloodthirst.known then c1 = S.btCost or 30 end
            if S.spells.whirlwind and S.spells.whirlwind.known and (S.wwCost or 25) ~= (S.btCost or 30) then
                if c1 then c2 = S.wwCost or 25 else c1 = S.wwCost or 25 end
            end
        end
        local mk = rageBar._mk
        if not mk then mk = {} rageBar._mk = mk end
        if mk.bw ~= bw or mk.mx ~= mx or mk[1] ~= c1 or mk[2] ~= c2 then
            mk.bw, mk.mx, mk[1], mk[2] = bw, mx, c1, c2
            for i, m in ipairs(rageBar.marks) do
                local c = mk[i]
                if c and c < mx then
                    m:ClearAllPoints()
                    m:SetPoint("TOP", rageBar.bar, "TOPLEFT", bw * c / mx, 1)
                    m:SetPoint("BOTTOM", rageBar.bar, "BOTTOMLEFT", bw * c / mx, -1)
                    m:Show()
                else
                    m:Hide()
                end
            end
        end
    else
        rageBar:Hide()
    end

    -- Swing bars: combat + active timers only (WA use_combat + showOnActive).
    -- Here only whether they may show; the driver shows each one the frame
    -- its swing starts.
    local C = WCol()
    swingMH:SetBarColor(C.swingMH[1], C.swingMH[2], C.swingMH[3], C.swingMH[4])
    swingOH:SetBarColor(C.swingOH[1], C.swingOH[2], C.swingOH[3], C.swingOH[4])
    local allowMH = (show and r.swingTimer and S.inCombat) and true or false
    local allowOH = (allowMH and S.swing.hasOH) and true or false
    D.swingAllowMH, D.swingAllowOH = allowMH, allowOH
    if not allowMH then swingMH:Hide() end
    if not allowOH then swingOH:Hide() end
    if (allowMH or allowOH) and not D.swingDriver:IsShown() then
        D.swingDriver:Show()
    end
end

-- Active-buff row (order = WA child order in "Warrior Aura Bar");
-- kind "buff" shows while the player buff is up (swipe = duration).
local hamstringIcon = GetSpellInfoC and select(3, GetSpellInfoC(1715)) or 132316

local AURA_DEFS = {
    -- ZacUI's Battle Shout reminder, when it is set to live here (Buff
    -- reminders > "In the warrior HUD's buff row"): shows while the
    -- reminder would, glowing while it warns, the missing count under it
    { key = "bsRem",      kind = "shoutRem" },
    { key = "salv",       kind = "salvMissing" },
    { key = "salvDef",    kind = "salvActive" },
    { key = "trinket1",   kind = "trinket" },
    { key = "hs",         kind = "queued", queued = "hsQueued", icon = HS_ICON },
    { key = "cleave",     kind = "queued", queued = "cleaveQueued", icon = CLEAVE_ICON },
    { key = "opProc",     kind = "opProc" },
    { key = "sbBuff",     kind = "buff", buff = "shieldBlock" },
    { key = "enrage",     kind = "buff", buff = "enrage" },
    { key = "flurry",     kind = "buff", buff = "flurry" },
    -- (2026-11-09) the game version's own (add = true: as in the grid)
    TBC and { key = "rampageBuff", kind = "buff", buff = "rampage", add = true, label = "Rampage" } or false,
    FOREVER and { key = "rsBuff", kind = "buff", buff = "recklessSwings", add = true, label = "Reckless Swings" } or false,
    TBC and { key = "commShout", kind = "buff", buff = "commShout", add = true, label = "Commanding Shout" } or false,
    TBC and { key = "srBuff", kind = "buff", buff = "spellReflect", add = true, label = "Spell Reflection" } or false,
    { key = "reckBuff",   kind = "buff", buff = "reck" },
    { key = "retalBuff",  kind = "buff", buff = "retaliation" },
    { key = "swBuff",     kind = "buff", buff = "shieldWall" },
    { key = "squawk",     kind = "buff", buff = "squawk", zoom0 = true },
    { key = "dwBuff",     kind = "buff", buff = "deathWish", alsoDebuff = true },
    { key = "crusader",   kind = "buff", buff = "crusader", splitApps = true },
    { key = "mightyRage", kind = "buff", buff = "mightyRage" },
    { key = "stoneshield", kind = "buff", buff = "stoneshield" },
    { key = "fap",        kind = "buff", buff = "fap" },
    { key = "lip",        kind = "buff", buff = "lip" },
    { key = "oil",        kind = "buff", buff = "oil" },
    { key = "brBuff",     kind = "buff", buff = "bloodrage" },
    { key = "hamstring",  kind = "hamstring" },
    { key = "lsBuff",     kind = "buff", buff = "lastStand" },
    { key = "ssBuff",     kind = "buff", buff = "sweeping" },
}
AURA_DEFS = Compact(AURA_DEFS)

local auraIcons = {}
local BS_REM_ICON = (GetSpellTexture and GetSpellTexture(6673)) or 132333

-- The Battle Shout reminder's slot from the reminder's last decision
-- (BR.HudState: missing, low, lowAt, count, selfOnly, tex) - the live
-- row and the settings previews (HUD page, Buff reminders page) fill it
-- with this one function. Missing: greyed, how many in your party lack
-- it under it (not when only you are tracked); running low: in colour,
-- the seconds left in red; fine: in colour, nothing under it.
function D.FillShoutRem(icon, st, now)
    icon:SetIconTexture(st.tex or BS_REM_ICON)
    local low = st.low and not st.missing
    icon:SetDesat(st.missing and true or false)
    icon:SetText("p", (st.missing and not st.selfOnly and (st.count or 0) >= 1) and tostring(st.count) or "")
    icon:SetText("low", (low and st.lowAt) and tostring(math.max(0, math.floor(st.lowAt - (now or GetTime())))) or "")
    if icon.texts and icon.texts.names then
        icon:SetText("names", (st.missing and not st.selfOnly and st.names) or "")
    end
end
-- the reminder set to live in the buff row (Buff reminders page)
function D.ShoutDocked()
    return ns.BuffRem and ns.BuffRem.Opt and ns.BuffRem.Opt("battleshout", "hudDock") == true or false
end
D.SHOUT_REM_DEF = { key = "bsRem", kind = "shoutRem" }

-- Preview texture for a buff-row def.
function D.AuraDefPreviewTex(def)
    local k = def.kind
    if k == "buff" then return S.buffIcons and S.buffIcons[def.buff]
    elseif k == "salvMissing" or k == "salvActive" then return SALV_ICON
    elseif k == "shoutRem" then return BS_REM_ICON
    elseif k == "trinket" then return S.trinket13.texture
    elseif k == "queued" then return def.icon
    elseif k == "opProc" then return OP_ICON
    elseif k == "hamstring" then return hamstringIcon
    elseif k == "customBuff" then return PreviewNameIcon(def.name)
    elseif k == "customCd" then
        local sp = S.spells[def.spell]
        return sp and sp.icon
    end
end

D.AuraIconList = {
    { key = "bsRem",      label = "Battle Shout reminder" },
    { key = "salv",       label = "Missing Salv (Zerker)" },
    { key = "salvDef",    label = "Have Salv (Defensive)" },
    { key = "trinket1",   label = "Trinket 1" },
    { key = "hs",         label = "Heroic Strike queued" },
    { key = "cleave",     label = "Cleave queued" },
    { key = "opProc",     label = "Overpower proc" },
    { key = "sbBuff",     label = "Shield Block" },
    { key = "enrage",     label = "Enrage" },
    { key = "flurry",     label = "Flurry" },
    { key = "reckBuff",   label = "Recklessness" },
    { key = "retalBuff",  label = "Retaliation" },
    { key = "swBuff",     label = "Shield Wall" },
    { key = "squawk",     label = "Battle Squawk" },
    { key = "dwBuff",     label = "Death Wish" },
    { key = "crusader",   label = "Crusader" },
    { key = "mightyRage", label = "Mighty Rage" },
    { key = "stoneshield", label = "Stoneshield" },
    { key = "fap",        label = "Free Action" },
    { key = "lip",        label = "LIP" },
    { key = "oil",        label = "Oil of Immolation" },
    { key = "brBuff",     label = "Bloodrage" },
    { key = "hamstring",  label = "Hamstring (target)" },
    { key = "lsBuff",     label = "Last Stand" },
    { key = "ssBuff",     label = "Sweeping Strikes" },
}
JoinList(D.AuraIconList, AURA_DEFS)

-- One buff-row icon for one def (the live row and the preview's sample).
local function MakeAuraIcon(parent, def)
    do
        -- cropped even on salv (zoom 0 shows the texture's baked-in rim);
        -- inverse=true: duration swipes darken as the buff expires (WA look).
        local icon = W.CreateIcon(parent, {
            width = 30, height = 30,
            zoom = def.zoom0 and 0 or W.ICON_ZOOM,
            keepAspect = true,
            inverse = true,
        })
        icon:SetFrameStrata(HUD_STRATA)
        icon:Hide()
        icon.def = def
        icon._hudSpot = def.key  -- its own text spots (HUD.IconSpotSpec)

        -- Salv reminders: compact tag on the icon's bottom edge (red =
        -- missing in zerker, yellow = still on in defensive).
        -- Texts sit centred on the bottom edge, like every other aura
        -- icon in ZacUI (buff frame, nameplates); stacks flush top-right.
        if def.kind == "shoutRem" then
            -- missing: greyed, how many under it; running low: in colour,
            -- the time left in red (Zac 2026-11-04)
            icon:AddText("p", "BELOW", 14, { 1, 1, 1, 1 }, 0, 0)
            icon:AddText("low", "BELOW", 14, { 1, 0.2, 0.2, 1 }, 0, 0)
            -- who is missing it, on its left (Zac 2026-11-04; the
            -- reminder's own "show missing names" decides)
            icon:AddText("names", "OUTSIDE_LEFT", 11, { 1, 1, 1, 1 }, -4, 0)
        elseif def.kind == "salvMissing" then
            icon:AddText("label", "BELOW", 9, { 1, 0.35, 0.35, 1 }, 0, 0)
            icon:SetText("label", "SALV")
        elseif def.kind == "salvActive" then
            icon:AddText("label", "BELOW", 9, { 1, 0.9, 0.2, 1 }, 0, 0)
            icon:SetText("label", "SALV")
        -- opProc/queued: no glow (the old pixel-glow read as a fat white
        -- frame at 30px); the icon appearing at all is the signal.
        elseif def.kind == "opProc" then
            icon:AddText("p", "CENTER", 14, { 1, 1, 1, 1 }, 0, -12)
        elseif def.kind == "queued" then
        else
            icon:AddText("p", "BELOW", 14, { 1, 1, 1, 1 }, 0, 0)
            icon:AddText("s", "INNER_TOPRIGHT", 14, { 1, 1, 1, 1 }, 0, 0)
            -- Crusader: a steady white glow on every proc, so one stands out
            if def.splitApps then icon:AddGlow("proc", "Pixel", { color = { 1, 1, 1, 1 }, static = true }) end
        end
        return icon
    end
end
D.MakeAuraIcon = MakeAuraIcon

local function BuildAuraIcons()
    for _, def in ipairs(AURA_DEFS) do
        -- (the Battle Shout reminder's slot is made the first time it is
        -- set to live here)
        -- (and a later entry's the first time it is on)
        if def.kind ~= "shoutRem" and not def.add then auraIcons[def.key] = MakeAuraIcon(auraAnchor, def) end
    end
end

local function GetBuff(def)
    local name = S.buffNames[def.buff]
    if not name then return nil end
    local b = S.buffs[name:lower()]
    if not b and def.alsoDebuff then
        b = S.selfDebuffs[name:lower()]
    end
    return b
end

local function HasSalv()
    local n1, n2 = S.buffNames.salv, S.buffNames.greaterSalv
    return (n1 and S.buffs[n1:lower()]) or (n2 and S.buffs[n2:lower()]) or nil
end

-- Active trinket buffs (WA showClones: one icon per simultaneous proc).
local trinketBuffList = {}
local function TrinketBuffs()
    wipe(trinketBuffList)
    for _, name in ipairs(WH.TRINKET_BUFFS) do
        local b = S.buffs[name:lower()]
        if b then trinketBuffList[#trinketBuffList + 1] = b end
    end
    return trinketBuffList
end

-- Pooled clone frames (frame 1 is the regular "trinket1" icon).
-- The pool only grows: frames persist once created and are hidden, not freed.
local function GetTrinketClone(i)
    local key = "trinketClone" .. i
    local icon = auraIcons[key]
    if not icon then
        icon = W.CreateIcon(auraAnchor, { width = 30, height = 30,
            zoom = W.ICON_ZOOM, keepAspect = true })
        icon:SetFrameStrata(HUD_STRATA)
        icon:Hide()
        icon:AddText("p", "BELOW", 14, { 1, 1, 1, 1 }, 0, 0)
        icon:AddText("s", "INNER_TOPRIGHT", 14, { 1, 1, 1, 1 }, 0, 0)
        icon.def = { key = key, kind = "trinketClone" }
        auraIcons[key] = icon
    end
    return icon
end

local function HideTrinketClones(fromIndex)
    local i = fromIndex
    while auraIcons["trinketClone" .. i] do
        auraIcons["trinketClone" .. i]:Hide()
        i = i + 1
    end
end

local function ShowTrinketBuff(f, b)
    f:SetIconTexture(b.icon)
    if (b.duration or 0) > 0 then
        f:SetSwipe(b.expirationTime - b.duration, b.duration)
    else
        f:ClearSwipe()
    end
    f:SetDesat(false)
    f.buffRef = b
    f.trinketCd = nil
end

-- A buff that can be up more than once (Crusader on both weapons): one
-- icon per application, each with its own timer, every one of them in a
-- steady white glow (2026-10-22, Zac: "even 1 proc to have the white glow
-- ... so a proc is more visible"). Clone frames are pooled like the
-- trinket clones (icon 1 is the regular one).
local function GetAppClone(def, i)
    local key = def.key .. "App" .. i
    local icon = auraIcons[key]
    if not icon then
        icon = W.CreateIcon(auraAnchor, { width = 30, height = 30,
            zoom = W.ICON_ZOOM, keepAspect = true, inverse = true })
        icon:SetFrameStrata(HUD_STRATA)
        icon:Hide()
        icon:AddText("p", "BELOW", 14, { 1, 1, 1, 1 }, 0, 0)
        icon:AddText("s", "INNER_TOPRIGHT", 14, { 1, 1, 1, 1 }, 0, 0)
        icon.def = { key = key, kind = "appClone" }
        icon:AddGlow("proc", "Pixel", { color = { 1, 1, 1, 1 }, static = true })
        auraIcons[key] = icon
        D:ApplyAppearance()
    end
    return icon
end

local function HideAppClones(def, fromIndex)
    local i = fromIndex
    while auraIcons[def.key .. "App" .. i] do
        auraIcons[def.key .. "App" .. i]:Hide()
        i = i + 1
    end
end

local function SetIconBorderColor(icon, white)
    if not icon.border or icon._whiteBorder == white then return end
    icon._whiteBorder = white
    local c = white and 1 or 0
    for _, t in ipairs(icon.border) do t:SetVertexColor(c, c, c, 1) end
end

local appOrder = {}
local function ByExpiry(a, b) return (a.expirationTime or 0) < (b.expirationTime or 0) end

local function UpdateAuraIcon(icon, def)
    local now = GetTime()
    if def.kind == "buff" then
        local b = GetBuff(def)
        if not b then return false end
        icon:SetIconTexture(b.icon)
        if (b.duration or 0) > 0 then
            icon:SetSwipe(b.expirationTime - b.duration, b.duration)
        else
            icon:ClearSwipe()
        end
        icon.buffRef = b
        return true
    elseif def.kind == "queued" then
        if not S[def.queued] then
            if icon._pop then W.SetPop(icon, 1) end
            return false
        end
        icon:SetIconTexture(def.icon)
        icon:ClearSwipe()
        -- this swing is eating the rage a ready Bloodthirst / Whirlwind
        -- needs and the NOOB is up for it: the queued icon gets the same
        -- big red glow and grows, so the culprit is obvious
        local Hs = ns.Hesitation
        local dump = Hs and Hs.HudDumping and Hs.HudDumping() or false
        -- before it gets that far: about to starve one (the rage bar
        -- blinks) = a steady red ring - unqueue it
        local starving = (not dump) and D.qStarving or false
        if (dump or starving) and not icon.glows.hDump then
            icon:AddGlow("hDump", "Pixel", { color = { 1, 0.15, 0.1, 1 }, size = 1.35, freq = 0.08 })
            icon:AddGlow("hStarve", "Pixel", { color = { 1, 0.15, 0.1, 0.85 }, static = true })
        end
        if icon.glows.hDump then
            icon:SetGlow("hDump", dump)
            icon:SetGlow("hStarve", starving)
        end
        W.SetPop(icon, dump and 1.3 or 1)
        return true
    elseif def.kind == "opProc" then
        local sp = S.spells.overpower
        local cd = S.cds.overpower
        -- the same window the plate row shows: your target's own dodge
        local windowLeft = ns.Overpower.Left()
        if not (sp and sp.known and windowLeft > 0 and not (cd and cd.real)) then
            return false
        end
        icon:SetIconTexture(OP_ICON)
        return true
    elseif def.kind == "shoutRem" then
        local BR = ns.BuffRem
        local st = BR and BR.HudState and BR.HudState("battleshout")
        if not st then return false end
        D.FillShoutRem(icon, st, GetTime())
        return true
    elseif def.kind == "salvMissing" then
        if S.stance ~= 3 or HasSalv() then return false end
        icon:SetIconTexture(SALV_ICON)
        return true
    elseif def.kind == "salvActive" then
        if S.stance ~= 2 or not HasSalv() then return false end
        icon:SetIconTexture(SALV_ICON)
        return true
    elseif def.kind == "hamstring" then
        local h = S.hamstring
        if not h then return false end
        icon:SetIconTexture(hamstringIcon)
        if h.hidden then
            icon:SetHiddenSwipe("target", h.hidden)   -- (WoW Forever: a hidden timer, as it is)
        elseif (h.duration or 0) > 0 then
            icon:SetSwipe(h.expirationTime - h.duration, h.duration)
        else
            icon:ClearSwipe()
        end
        icon.buffRef = h
        return true
    elseif def.kind == "customBuff" then
        if not def.name then return false end
        local key = def.name:lower()
        local b = S.buffs[key] or S.selfDebuffs[key]
        if not b then return false end
        icon:SetIconTexture(b.icon)
        if (b.duration or 0) > 0 then
            icon:SetSwipe(b.expirationTime - b.duration, b.duration)
        else
            icon:ClearSwipe()
        end
        icon.buffRef = b
        return true
    elseif def.kind == "customCd" then
        -- User-added cd icon in the top row: standard template behavior.
        local sp = S.spells[def.spell]
        if not (sp and sp.known) then return false end
        icon:SetIconTexture(sp.icon)
        local cd = S.cds[def.spell]
        if cd then icon:SetSwipe(cd.start, cd.duration, cd.durObj) end
        local us = S.usable[def.spell] or {}
        icon:SetDesat((cd and cd.real) or us.noPower or us.usable == false or false)
        icon.buffRef = nil
        return true
    elseif def.kind == "trinket" then
        -- No-buff case only: slot 13 icon + cd swipe/desat. Active buffs
        -- are handled as clones in RefreshAuraRow.
        local t = S.trinket13
        if not t.texture then return false end
        icon:SetIconTexture(t.texture)
        icon.buffRef = nil
        icon.trinketCd = false
        if t.duration and t.duration > 1.51 then
            icon:SetSwipe(t.start, t.duration)
            icon:SetDesat(true)
            icon.trinketCd = true
        else
            icon:ClearSwipe()
            icon:SetDesat(false)
        end
        -- Hesitation's trinket call: gold and a size up when it should be
        -- used, red and bigger when you are sitting on it (2026-10-29)
        local Hs = ns.Hesitation
        local tname = "-"
        if Hs and Hs.cds then
            for _, e in ipairs(Hs.cds) do if e.slot == 13 then tname = e.name break end end
        end
        ApplyHesitation(icon, tname)
        return true
    end
    return false
end

-- Stack count top-right when the aura has >1 application (Badge etc.).
local function UpdateStackText(icon)
    local b = icon.buffRef
    local c = b and b.count or 0
    icon:SetText("s", (c and c > 1) and tostring(c) or "")
end

local function UpdateAuraIconText(icon, def)
    local now = GetTime()
    if def.kind == "opProc" then
        local windowLeft = ns.Overpower.Left()
        icon:SetText("p", windowLeft > 0 and W.FormatTime(windowLeft, 0) or "")
        return
    end
    if def.kind == "shoutRem" then
        -- the red time left counts down between the reminder's looks
        local BR = ns.BuffRem
        local st = BR and BR.HudState and BR.HudState("battleshout")
        if st and st.low and not st.missing and st.lowAt then
            icon:SetText("low", tostring(math.max(0, math.floor(st.lowAt - now))))
        end
        return
    end
    if def.kind == "queued" or def.kind == "salvMissing" or def.kind == "salvActive" then
        return
    end
    if def.kind == "customCd" then
        local remaining = CdRemaining(S.cds[def.spell])
        icon:SetText("p", remaining > 0 and W.FormatTime(remaining, 0) or "")
        return
    end
    if def.kind == "trinket" then
        local t = S.trinket13
        if icon.buffRef then
            local rem = math.max(0, (icon.buffRef.expirationTime or 0) - now)
            icon:SetText("p", W.FormatTime(rem, 1))
        elseif icon.trinketCd then
            icon:SetText("p", W.FormatTime(math.max(0, t.start + t.duration - now), 1))
        else
            icon:SetText("p", "")
        end
        UpdateStackText(icon)
        return
    end
    local b = icon.buffRef
    if b and b.hidden then
        -- (WoW Forever: the time left as the game hands it over)
        local left = ns.AuraTimeLeft("target", b.hidden)
        if left ~= nil then icon:SetHiddenText("p", "%.0f", left) else icon:SetText("p", "") end
        return
    elseif b and (b.expirationTime or 0) > 0 then
        icon:SetText("p", W.FormatTime(math.max(0, b.expirationTime - now), 0))
    else
        icon:SetText("p", "")
    end
    UpdateStackText(icon)
end

-- User-added buff icons ("bcust<i>"): show while the named player
-- buff/debuff is up, duration swipe + edge timer like the active row.
local customAuraDefs, customAuraSrc = {}, {}

local function EnsureCustomAuraIcons(cfg)
    local list = cfg.auraRow.custom or {}
    if customAuraSrc.built and CustomListSame(list, customAuraSrc) then return end
    RememberCustomList(list, customAuraSrc)
    customAuraSrc.built = true
    wipe(customAuraDefs)
    for i = 1, #list do
        local entry = list[i]
        local key = "bcust" .. i
        local kind = entry.kind or "buff"
        local stance = (entry.stance and entry.stance > 0) and entry.stance or nil
        if kind == "cd" then
            -- Cooldown icon in the top row (Core tracks it as "tcust<i>")
            customAuraDefs[i] = { key = key, kind = "customCd",
                spell = "tcust" .. i, stance = stance }
        else
            local id = tonumber(entry.input)
            local name = entry.input
            if id and GetSpellInfoC then
                name = GetSpellInfoC(id) or entry.input
            end
            customAuraDefs[i] = { key = key, kind = "customBuff",
                name = name, stance = stance }
        end
        local icon = auraIcons[key]
        if not icon then
            icon = W.CreateIcon(auraAnchor, { width = 30, height = 30,
                zoom = W.ICON_ZOOM, keepAspect = true })
            icon:SetFrameStrata(HUD_STRATA)
            icon:Hide()
            icon:AddText("p", "BELOW", 14, { 1, 1, 1, 1 }, 0, 0)
            icon:AddText("s", "INNER_TOPRIGHT", 14, { 1, 1, 1, 1 }, 0, 0)
            auraIcons[key] = icon
        end
        icon.def = customAuraDefs[i]
    end
    local i = #list + 1
    while auraIcons["bcust" .. i] do
        auraIcons["bcust" .. i]:Hide()
        i = i + 1
    end
    if D.ApplyAppearance then D:ApplyAppearance(cfg) end
end

local auraActive = {}
local auraLast = {}
local auraHold = W.NewHold()

-- one buff-row icon (and its clones) per call; file-level, built once
local function placeIcon(icon, key)
    auraActive[#auraActive + 1] = icon
    W.SetShownAnimated(icon, true)
end
local function AuraHandle(def, cfg)
    local off = WH.IsOff("buffs", def, cfg)
    local icon = auraIcons[def.key]
    if not icon then
        if off then return end
        icon = MakeAuraIcon(auraAnchor, def)
        auraIcons[def.key] = icon
        D.StyleIcon(icon, cfg)
        D._styleSerial = nil      -- the shared look with the rest on the next pass
    end
    if D.preview then
        if def.splitApps then
            HideAppClones(def, 1)
            SetIconBorderColor(icon, false)
        end
        if off then
            icon:Hide()
            if def.kind == "trinket" then HideTrinketClones(1) end
            return
        end
        icon:SetIconTexture(D.AuraDefPreviewTex(def) or QUESTION_ICON)
        icon:ClearSwipe()
        icon:SetDesat(false)
        for gk in pairs(icon.glows) do icon:SetGlow(gk, false) end
        icon:SetText("p", "")
        icon:SetText("s", "")
        placeIcon(icon, def.key)
        if def.kind == "trinket" then HideTrinketClones(1) end
        return
    end
    if def.kind == "trinket" then
        local clonesUsed = 0
        if off then
            icon:Hide()
        else
            local buffs = TrinketBuffs()
            if #buffs > 0 then
                for i, b in ipairs(buffs) do
                    local f = (i == 1) and icon or GetTrinketClone(i - 1)
                    ShowTrinketBuff(f, b)
                    placeIcon(f, def.key .. i)
                end
                clonesUsed = #buffs - 1
            elseif UpdateAuraIcon(icon, def) then
                placeIcon(icon, def.key)
            else
                W.SetShownAnimated(icon, false)
            end
        end
        HideTrinketClones(clonesUsed + 1)
        return
    end
    local visible = (not off)
        and not (def.stance and S.stance ~= def.stance)
        and UpdateAuraIcon(icon, def)
    if def.splitApps then
        local b = visible and icon.buffRef
        local n = b and (b.matches or 1) or 0
        if n >= 2 and b.apps then
            wipe(appOrder)
            for i = 1, n do
                if b.apps[i] then appOrder[#appOrder + 1] = b.apps[i] end
            end
            table.sort(appOrder, ByExpiry)   -- soonest to fall off first
            for i, a in ipairs(appOrder) do
                local f = (i == 1) and icon or GetAppClone(def, i - 1)
                ShowTrinketBuff(f, a)
                SetIconBorderColor(f, false)
                f:SetGlow("proc", true)
                placeIcon(f, def.key .. i)
            end
            HideAppClones(def, #appOrder)
            return
        end
        SetIconBorderColor(icon, false)
        icon:SetGlow("proc", visible and true or false)
        HideAppClones(def, 1)
    end
    if visible then
        placeIcon(icon, def.key)
    else
        W.SetShownAnimated(icon, false)
    end
end

local function RefreshAuraRow(cfg)
    local show = cfg.auraRow.enabled
    wipe(auraActive)
    if show then
        EnsureCustomAuraIcons(cfg)
        -- the Battle Shout reminder's slot only when it is set to live here
        local docked = ns.BuffRem and ns.BuffRem.Opt and ns.BuffRem.Opt("battleshout", "hudDock") == true
        for _, def in ipairs(AURA_DEFS) do
            if def.kind == "shoutRem" and docked and not auraIcons[def.key] then
                auraIcons[def.key] = MakeAuraIcon(auraAnchor, def)
                D._styleSerial = nil      -- styled with the rest on the next pass
            end
            if def.kind ~= "shoutRem" or docked then
                AuraHandle(def, cfg)
            elseif auraIcons[def.key] then
                auraIcons[def.key]:Hide()
            end
        end
        for _, def in ipairs(customAuraDefs) do AuraHandle(def, cfg) end
    else
        for _, icon in pairs(auraIcons) do icon:Hide() end
    end
    local list, held = auraActive, false
    if not D.preview then list, held = W.HeldList(auraActive, auraLast, auraHold, GetTime()) end
    if held then WakeWhenHoldEnds() end
    if ListMoved(list, auraLast) then
        RememberList(list, auraLast)
        W.LayoutHRow(auraAnchor, list,
            cfg.auraRow.iconW, cfg.auraRow.iconH, cfg.auraRow.spacing)
    end
end

-- ============================================================
-- THE TARGET DEBUFF ROW (2026-11-09)
-- ============================================================
-- Sunder Armor (its stacks top-right, always), Demoralizing Shout and
-- Thunder Clap from anyone, your own Rend and Hamstring, Blood Frenzy on
-- TBC: an icon while it is on your target, the time left under it. Every
-- entry starts off (add = true) and is turned on by your spec's defaults
-- or your own tick; you can add any debuff by name or spell ID. The core
-- reads the target's debuffs only while one of these is on.
local DEBUFF_DEFS = Compact({
    { key = "dSunder",    kind = "debuff", debuff = "sunder", stacks = true, add = true, label = "Sunder Armor" },
    { key = "dDemo",      kind = "debuff", debuff = "demoShout", add = true, label = "Demoralizing Shout" },
    { key = "dTclap",     kind = "debuff", debuff = "thunderClap", add = true, label = "Thunder Clap" },
    TBC and { key = "dBloodFrenzy", kind = "debuff", debuff = "bloodFrenzy", add = true, label = "Blood Frenzy" } or false,
    { key = "dRend",      kind = "debuff", debuff = "rend", mine = true, add = true, label = "Rend (yours)" },
    { key = "dHamstring", kind = "debuff", debuff = "hamstring", mine = true, add = true, label = "Hamstring (yours)" },
})
D.DebuffIconList = {}
JoinList(D.DebuffIconList, DEBUFF_DEFS)

local debuffIcons = {}
local customDebuffDefs, customDebuffSrc = {}, {}

function D.DebuffDefPreviewTex(def)
    if def.debuff then return S.debuffIcons and S.debuffIcons[def.debuff] end
    return PreviewNameIcon(def.name)
end

-- One debuff-row icon for one def (the live row and the preview's sample).
local function MakeDebuffIcon(parent, def)
    local icon = W.CreateIcon(parent, { width = 26, height = 26, zoom = W.ICON_ZOOM,
        keepAspect = true, inverse = true })
    icon:SetFrameStrata(HUD_STRATA)
    icon:Hide()
    icon.def = def
    icon._hudSpot = def.key      -- its own text spots (HUD.IconSpotSpec)
    icon:AddText("p", "BELOW", 14, { 1, 1, 1, 1 }, 0, 0)
    icon:AddText("s", "INNER_TOPRIGHT", 14, { 1, 1, 1, 1 }, 0, 0)
    return icon
end
D.MakeDebuffIcon = MakeDebuffIcon

-- User-added debuffs ("dcust<i>"): found on the target by name; kind
-- "mine" = only your own.
local function EnsureCustomDebuffDefs(cfg)
    local list = cfg.debuffRow.custom or {}
    if customDebuffSrc.built and CustomListSame(list, customDebuffSrc) then return end
    RememberCustomList(list, customDebuffSrc)
    customDebuffSrc.built = true
    wipe(customDebuffDefs)
    for i = 1, #list do
        local entry = list[i]
        local id = tonumber(entry.input)
        local name = entry.input
        if id and GetSpellInfoC then name = GetSpellInfoC(id) or entry.input end
        customDebuffDefs[i] = { key = "dcust" .. i, kind = "debuff", name = name,
            mine = entry.kind == "mine", stance = (entry.stance and entry.stance > 0) and entry.stance or nil }
        local icon = debuffIcons["dcust" .. i]
        if icon then icon.def = customDebuffDefs[i] end
    end
    local i = #list + 1        -- hide frames past the shrunken list
    while debuffIcons["dcust" .. i] do
        debuffIcons["dcust" .. i]:Hide()
        i = i + 1
    end
end

-- every debuff entry, the built-in ones then yours: fn(def)
function D.EachDebuffDef(cfg, fn)
    EnsureCustomDebuffDefs(cfg)
    for _, def in ipairs(DEBUFF_DEFS) do fn(def) end
    for _, def in ipairs(customDebuffDefs) do fn(def) end
end

local function UpdateDebuffIcon(icon, def)
    local name = def.name or S.debuffNames[def.debuff]
    local e = name and S.targetDebuffs[name:lower()]
    if not e or (def.mine and not e.mine) then return false end
    icon:SetIconTexture(e.icon or D.DebuffDefPreviewTex(def) or QUESTION_ICON)
    if e.hidden then
        icon:SetHiddenSwipe("target", e.hidden)   -- (WoW Forever: a hidden timer, as it is)
    elseif (e.duration or 0) > 0 then
        icon:SetSwipe(e.expirationTime - e.duration, e.duration)
    else
        icon:ClearSwipe()
    end
    icon:SetDesat(false)
    icon.buffRef = e
    return true
end

local debuffActive = {}
local debuffLast = {}
local debuffHold = W.NewHold()

-- one debuff icon per call; answers whether the entry is on (so the core
-- knows to read the target)
local function DebuffHandle(def, cfg)
    local off = WH.IsOff("debuffs", def, cfg)
    local icon = debuffIcons[def.key]
    if not icon then
        if off then return false end
        icon = MakeDebuffIcon(debuffAnchor, def)
        debuffIcons[def.key] = icon
        D.StyleIcon(icon, cfg)
        D._styleSerial = nil      -- the shared look with the rest on the next pass
    end
    local visible = false
    if off then
        visible = false
    elseif D.preview then
        icon:SetIconTexture(D.DebuffDefPreviewTex(def) or QUESTION_ICON)
        icon:ClearSwipe()
        icon:SetDesat(false)
        icon:SetText("p", "")
        icon:SetText("s", "")
        icon.buffRef = nil
        visible = true
    elseif not (def.stance and S.stance ~= def.stance) then
        visible = UpdateDebuffIcon(icon, def)
    end
    if visible then
        debuffActive[#debuffActive + 1] = icon
        W.SetShownAnimated(icon, true)
    else
        W.SetShownAnimated(icon, false)
    end
    return not off
end

local function RefreshDebuffRow(cfg)
    local row = cfg.debuffRow
    wipe(debuffActive)
    local want = false
    if row and row.enabled and debuffAnchor then
        EnsureCustomDebuffDefs(cfg)
        for _, def in ipairs(DEBUFF_DEFS) do
            if DebuffHandle(def, cfg) then want = true end
        end
        for _, def in ipairs(customDebuffDefs) do
            if DebuffHandle(def, cfg) then want = true end
        end
    else
        for _, icon in pairs(debuffIcons) do icon:Hide() end
    end
    WH.WantDebuffs(want and not D.preview)
    local list, held = debuffActive, false
    if not D.preview then list, held = W.HeldList(debuffActive, debuffLast, debuffHold, GetTime()) end
    if held then WakeWhenHoldEnds() end
    if ListMoved(list, debuffLast) then
        RememberList(list, debuffLast)
        if row then W.LayoutHRow(debuffAnchor, list, row.iconW or 26, row.iconH or 26, row.spacing) end
    end
end

-- the time left under a debuff icon; Sunder Armor's stacks from the first
local function UpdateDebuffIconText(icon, def)
    UpdateAuraIconText(icon, def)
    local e = icon.buffRef
    if def.stacks and e and not e.hidden then
        local c = e.count or 0
        icon:SetText("s", c >= 1 and tostring(c) or "")
    end
end

-- 0.1s text ticker: countdown texts, only while the HUD is active;
-- cheap cached-state reads + fontstring writes.
local textTicker = nil

local function TextTick()
    if not WH:IsActive() then return end
    for _, icon in ipairs(mainActive) do
        local def = icon.def
        if def.kind == "spell" then
            UpdateSpellIconText(icon, def)
        elseif def.kind == "customBuff" then
            local b = icon.buffRef
            if b and (b.expirationTime or 0) > 0 then
                icon:SetText("p",
                    W.FormatTime(math.max(0, b.expirationTime - GetTime()), 0))
            else
                icon:SetText("p", "")
            end
        else
            UpdateItemIconText(icon, def)
        end
    end
    for _, icon in ipairs(auraActive) do
        UpdateAuraIconText(icon, icon.def)
    end
    if not D.preview then
        for _, icon in ipairs(debuffActive) do
            UpdateDebuffIconText(icon, icon.def)
        end
    end
    UpdateExecuteHelper()
end

local function EnsureTextTicker()
    if textTicker then return end
    textTicker = HUD.Ticker(0.1, TextTick)
end

-- Public entry points
local built = false

function D:Refresh()
    if not built then
        built = true
        BuildMainIcons()
        BuildResources()
        BuildAuraIcons()
        ApplyAnchorPositions()
        D:ApplyAppearance()
    end
    local cfg = WH.Store()
    if not cfg then return end
    -- a setting changed since the last pass: the icons' look again
    if D._styleSerial ~= HUD.serial then
        D._styleSerial = HUD.serial
        D:ApplyAppearance(cfg)
    end
    RefreshMainRow(cfg)
    RefreshResources(cfg)
    RefreshAuraRow(cfg)
    RefreshDebuffRow(cfg)
    EnsureTextTicker()
end

-- Ordered preview textures for the pinned mini preview (non-hidden only).
function D:GetPreviewTextures(cfg)
    cfg = cfg or WH.Store()
    if not cfg then return nil end
    EnsureCustomMainIcons(cfg)
    EnsureCustomAuraIcons(cfg)
    local out = { grid = {}, buffs = {},
        stance = STANCE_ICONS[S.stance] or STANCE_ICONS[1],
        exec = EXEC_ICON }
    out.gridDefs = {}
    for _, list in ipairs({ MAIN_DEFS, customMainDefs }) do
        for _, def in ipairs(list) do
            if not WH.IsOff("main", def, cfg) then
                out.grid[#out.grid + 1] = D.MainDefPreviewTex(def) or QUESTION_ICON
                out.gridDefs[#out.grid] = def
            end
        end
    end
    out.buffDefs = {}
    local docked = ns.BuffRem and ns.BuffRem.Opt and ns.BuffRem.Opt("battleshout", "hudDock") == true
    for _, def in ipairs(AURA_DEFS) do
        if not WH.IsOff("buffs", def, cfg) and (def.kind ~= "shoutRem" or docked) then
            out.buffs[#out.buffs + 1] = D.AuraDefPreviewTex(def) or QUESTION_ICON
            out.buffDefs[#out.buffs] = def
        end
    end
    for _, def in ipairs(customAuraDefs) do
        if not WH.IsOff("buffs", def, cfg) then
            out.buffs[#out.buffs + 1] = D.AuraDefPreviewTex(def) or QUESTION_ICON
            out.buffDefs[#out.buffs] = def
        end
    end
    -- the target debuff row (nothing when the row is off)
    out.debuffs, out.debuffDefs = {}, {}
    if cfg.debuffRow and cfg.debuffRow.enabled then
        D.EachDebuffDef(cfg, function(def)
            if not WH.IsOff("debuffs", def, cfg) then
                out.debuffs[#out.debuffs + 1] = D.DebuffDefPreviewTex(def) or QUESTION_ICON
                out.debuffDefs[#out.debuffs] = def
            end
        end)
    end
    return out
end

-- Appearance from settings: border thickness, text sizes and the timer
-- colour on one icon (the HUD's own and the settings preview's samples).
function D.StyleIcon(icon, cfg)
    local ts = cfg.textSizes or {}
    local bs = cfg.borderSize or 1
    if icon.SetBorderSize then icon:SetBorderSize(bs) end
    if icon.texts then
        local tc = WCol().timer
        for key, fs in pairs(icon.texts) do
            if key == "p" then
                HUD.ApplyFont(fs, ts.timer or 14, "OUTLINE", "text")
                fs:SetTextColor(tc[1], tc[2], tc[3], tc[4])
            elseif key == "count" or key == "plates" or key == "s" then
                HUD.ApplyFont(fs, ts.count or 12, "OUTLINE", "text")
                if key == "s" then fs:SetTextColor(tc[1], tc[2], tc[3], tc[4]) end
            end
        end
    end
end

function D:ApplyAppearance(cfg)
    cfg = cfg or WH.Store()
    if not cfg then return end
    local function apply(icon) D.StyleIcon(icon, cfg) end
    for _, icon in pairs(mainIcons) do apply(icon) end
    for _, icon in pairs(auraIcons) do apply(icon) end
    for _, icon in pairs(debuffIcons) do apply(icon) end
    if execIcon then apply(execIcon) end
    if stanceIcon and stanceIcon.SetBorderSize then
        stanceIcon:SetBorderSize(cfg.borderSize or 1)
    end
end

-- Settings UI hook: relayout after sizing changes + re-apply anchors.
function D:InvalidateLayout()
    mainLast.n, auraLast.n, debuffLast.n = nil, nil, nil     -- forces the next layout
    ApplyAnchorPositions()
    D:ApplyAppearance()
    if WH.Wake then WH.Wake() end
end

function D:HideAll()
    -- The 0.1s text ticker only needs to run while the HUD is active.
    if textTicker then textTicker:Cancel() textTicker = nil end
    if not built then return end
    for _, icon in pairs(mainIcons) do icon:Hide() end
    for _, icon in pairs(auraIcons) do icon:Hide() end
    for _, icon in pairs(debuffIcons) do icon:Hide() end
    if stanceIcon then stanceIcon:Hide() end
    if execIcon then execIcon:Hide() end
    if rageBar then rageBar:Hide() end
    D.swingAllowMH, D.swingAllowOH = false, false
    if swingMH then swingMH:Hide() end
    if swingOH then swingOH:Hide() end
    mainLast.n, auraLast.n, debuffLast.n = nil, nil, nil     -- forces the next layout
    wipe(mainActive)
    wipe(auraActive)
    wipe(debuffActive)
    WH.WantDebuffs(false)
end
