-- HUD_Retail - the class HUD on Retail (Mainline 12.x), for every one of
-- the 13 classes. Retail's classes play by spec, and the game ships its
-- own Cooldown Manager with a list of what matters for the spec you
-- play; this HUD is that list (HUD_V2_Modern reads it, HUD_V2_Sources
-- merges it), drawn by the class HUD engine with ZacUI's own icons:
--
--   cooldown grid   the game's "Essential" cooldowns for your spec
--   utility row     its "Utility" cooldowns; on by default are the ones
--                   the spec's preset below names (the interrupt and two
--                   or three defensives), the rest one tick away
--   buff row        its "Tracked buffs" (your own buffs while they are up)
--   buff bars       its "Tracked bars", as bars
--   power bar       your power, handed to the bar exactly as the game
--                   gives it (no pips, no maths: it may be hidden)
--   trinkets/racial the aux row, off until turned on
--
-- A spec swap replaces the lists (PLAYER_SPECIALIZATION_CHANGED, and
-- COOLDOWN_VIEWER_DATA_LOADED when the game's data arrives late). No
-- Classic piece exists here: no swing timer, five-second rule or mana
-- tick, no target debuff row (the game hides them from addons in a
-- fight), no reminders. Nothing of Blizzard's Cooldown Manager frames is
-- touched, hooked or moved.
--
-- Secret values (Retail hides cooldowns, power and auras from addons in a
-- fight): "on cooldown" comes from the game's never-hidden isActive flag,
-- the swipe from its duration object, the power bar and the hidden timers
-- take the values as they are. Nothing here compares or does maths on a
-- value before ns.IsSecret said it is plain.
--
-- NOT CHECKED ON A REAL RETAIL CLIENT (none was available, 2026-11-09):
-- every game call sits under pcall and a failed or refused read shows
-- nothing rather than something wrong. The HUD is off until its page
-- turns it on, like every class HUD.
-- On every other game version this file returns on its guard below.
-- Part of ZacUI; load order is set by the TOC (after the last HUD_V2 file).

local ns = _G.ZacUI
if not ns or not ns.HUD or not ns.HUD.DefineClass or not ns.HUD.ClassEngine or not ns.HUD.V2 then return end
local HUD = ns.HUD
if not HUD.RETAIL then return end
local V2 = HUD.V2
local Engine = HUD.ClassEngine

local IsSecret = ns.IsSecret
local GetTime = GetTime
local GCD_MAX = 1.51
-- a cooldown the game calls active counts as a real one (not the global
-- cooldown) at once when it says so, else once it outlasted any global one
local GCD_OUTLAST = 1.6

-- ============================================================
-- THE CLASSES, THEIR SPECS AND THE PRESETS
-- ============================================================
-- Spec ids: warcraft.wiki.gg SpecializationID (read 2026-11-09). A spec
-- not listed here (a new one) plays the class baseline: grid, buffs and
-- bars as the game lists them, the utility row empty until ticked.
-- util: the Utility cooldowns on by default for the spec, by spell id -
-- the interrupt, then two or three defensives. Every id was looked up by
-- name on 2026-11-09 (nether.wowhead.com/tooltip/spell/<id>); an id the
-- game does not list for the spec ticks nothing.
local KICK = {
    WARRIOR = 6552,      -- Pummel
    PALADIN = 96231,     -- Rebuke
    ROGUE = 1766,        -- Kick
    DEATHKNIGHT = 47528, -- Mind Freeze
    SHAMAN = 57994,      -- Wind Shear
    MAGE = 2139,         -- Counterspell
    WARLOCK = 19647,     -- Spell Lock (the Felhunter's)
    MONK = 116705,       -- Spear Hand Strike
    DEMONHUNTER = 183752,-- Disrupt
    EVOKER = 351338,     -- Quell
}

local CLASSES = {
    WARRIOR = { name = "Warrior", prefix = "rwr", specs = {
        { 71, "arms", "Arms", { KICK.WARRIOR, 118038, 97462, 23920 } },          -- Die by the Sword, Rallying Cry, Spell Reflection
        { 72, "fury", "Fury", { KICK.WARRIOR, 184364, 97462, 23920 } },          -- Enraged Regeneration
        { 73, "prot", "Protection", { KICK.WARRIOR, 871, 12975, 23920 } },       -- Shield Wall, Last Stand
    } },
    PALADIN = { name = "Paladin", prefix = "rpa", specs = {
        { 65, "holy", "Holy", { KICK.PALADIN, 642, 498, 633 } },                 -- Divine Shield, Divine Protection, Lay on Hands
        { 66, "prot", "Protection", { KICK.PALADIN, 31850, 86659, 642 } },       -- Ardent Defender, Guardian of Ancient Kings
        { 70, "ret", "Retribution", { KICK.PALADIN, 642, 184662, 633 } },        -- Shield of Vengeance
    } },
    HUNTER = { name = "Hunter", prefix = "rhu", specs = {
        { 253, "bm", "Beast Mastery", { 147362, 186265, 109304, 264735 } },      -- Counter Shot, Aspect of the Turtle, Exhilaration, Survival of the Fittest
        { 254, "mm", "Marksmanship", { 147362, 186265, 109304, 264735 } },
        { 255, "sv", "Survival", { 187707, 186265, 109304, 264735 } },           -- Muzzle
    } },
    ROGUE = { name = "Rogue", prefix = "rro", specs = {
        { 259, "sin", "Assassination", { KICK.ROGUE, 31224, 5277, 1966 } },      -- Cloak of Shadows, Evasion, Feint
        { 260, "outlaw", "Outlaw", { KICK.ROGUE, 31224, 5277, 1966 } },
        { 261, "sub", "Subtlety", { KICK.ROGUE, 31224, 5277, 1966 } },
    } },
    PRIEST = { name = "Priest", prefix = "rpr", specs = {
        { 256, "disc", "Discipline", { 33206, 19236, 586 } },                    -- Pain Suppression, Desperate Prayer, Fade
        { 257, "holy", "Holy", { 47788, 19236, 586 } },                          -- Guardian Spirit
        { 258, "shadow", "Shadow", { 15487, 47585, 19236, 586 } },               -- Silence, Dispersion
    } },
    DEATHKNIGHT = { name = "Death Knight", prefix = "rdk", specs = {
        { 250, "blood", "Blood", { KICK.DEATHKNIGHT, 55233, 48792, 48707 } },    -- Vampiric Blood, Icebound Fortitude, Anti-Magic Shell
        { 251, "frost", "Frost", { KICK.DEATHKNIGHT, 48792, 48707 } },
        { 252, "unholy", "Unholy", { KICK.DEATHKNIGHT, 48792, 48707 } },
    } },
    SHAMAN = { name = "Shaman", prefix = "rsh", specs = {
        { 262, "ele", "Elemental", { KICK.SHAMAN, 108271, 198103 } },            -- Astral Shift, Earth Elemental
        { 263, "enh", "Enhancement", { KICK.SHAMAN, 108271, 198103 } },
        { 264, "resto", "Restoration", { KICK.SHAMAN, 108271, 198103 } },
    } },
    MAGE = { name = "Mage", prefix = "rma", specs = {
        { 62, "arcane", "Arcane", { KICK.MAGE, 45438, 342245, 55342 } },         -- Ice Block, Alter Time, Mirror Image
        { 63, "fire", "Fire", { KICK.MAGE, 45438, 342245, 55342 } },
        { 64, "frost", "Frost", { KICK.MAGE, 45438, 342245, 55342 } },
    } },
    WARLOCK = { name = "Warlock", prefix = "rwl", specs = {
        { 265, "aff", "Affliction", { KICK.WARLOCK, 104773, 108416 } },          -- Unending Resolve, Dark Pact
        { 266, "demo", "Demonology", { KICK.WARLOCK, 104773, 108416 } },
        { 267, "destro", "Destruction", { KICK.WARLOCK, 104773, 108416 } },
    } },
    MONK = { name = "Monk", prefix = "rmo", specs = {
        { 268, "brew", "Brewmaster", { KICK.MONK, 115203, 122783 } },            -- Fortifying Brew, Diffuse Magic
        { 270, "mist", "Mistweaver", { KICK.MONK, 116849, 115203, 122783 } },    -- Life Cocoon
        { 269, "wind", "Windwalker", { KICK.MONK, 122470, 115203, 122783 } },    -- Touch of Karma
    } },
    DRUID = { name = "Druid", prefix = "rdr", specs = {
        { 102, "balance", "Balance", { 78675, 22812 } },                         -- Solar Beam, Barkskin
        { 103, "feral", "Feral", { 106839, 61336, 22812 } },                     -- Skull Bash, Survival Instincts
        { 104, "guardian", "Guardian", { 106839, 61336, 22812 } },
        { 105, "resto", "Restoration", { 102342, 22812 } },                      -- Ironbark
    } },
    DEMONHUNTER = { name = "Demon Hunter", prefix = "rdh", specs = {
        { 577, "havoc", "Havoc", { KICK.DEMONHUNTER, 198589, 196718 } },         -- Blur, Darkness
        { 581, "veng", "Vengeance", { KICK.DEMONHUNTER, 203720, 204021 } },      -- Demon Spikes, Fiery Brand
        { 1480, "devourer", "Devourer", { KICK.DEMONHUNTER, 196718 } },
    } },
    EVOKER = { name = "Evoker", prefix = "rev", specs = {
        { 1467, "dev", "Devastation", { KICK.EVOKER, 363916, 374348 } },         -- Obsidian Scales, Renewing Blaze
        { 1468, "pres", "Preservation", { KICK.EVOKER, 363916, 374348 } },
        { 1473, "aug", "Augmentation", { KICK.EVOKER, 363916, 374348 } },
    } },
}
V2.RETAIL_CLASSES = CLASSES

-- ============================================================
-- THE ENGINE ON RETAIL (this file is the only definition there, so the
-- engine's Classic reads are replaced for it; nothing here loads on
-- another game version)
-- ============================================================
local function Plain(v)
    if IsSecret(v) then return nil end
    return v
end

-- icons whose entry left the lists go; icons of entries that came back
-- point at today's entry. Run once per engine (the HUD and each preview
-- sample) after the lists changed.
local ROW_ICONS = { grid = "mainIcons", utility = "utilIcons", buffRow = "auraIcons" }
local function Prune(eng)
    local def = eng.def
    for listName, field in pairs(ROW_ICONS) do
        local icons = eng[field]
        if icons then
            local inList = {}
            for _, e in ipairs(def[listName] or {}) do inList[e.key] = e end
            for key, icon in pairs(icons) do
                local e = inList[key]
                if e then
                    icon.def = e
                elseif icon.def and icon.def.fromGame then
                    icon:Hide()
                    icon.auraRef = nil
                end
            end
        end
    end
    if eng.v2bars then
        local inRow = {}
        for _, e in ipairs(def.buffRow or {}) do inRow["buffs:" .. e.key] = true end
        for gk, f in pairs(eng.v2bars) do
            if not inRow[gk] then f:Hide() end
        end
    end
end

local BaseRefresh = Engine.Refresh
function Engine:Refresh()
    local ver = self.def._rver
    if self.built and self._rverSeen ~= ver then
        if self.V2BuildMissing then self:V2BuildMissing() end
        Prune(self)
        for _, m in pairs(self.memo or {}) do HUD.ForgetLayout(m) end
    end
    self._rverSeen = ver
    return BaseRefresh(self)
end

-- the preview's sample resolves the spells again after the lists changed
local BaseFill = Engine.FillSample
function Engine:FillSample(mode)
    if self._rverFill ~= self.def._rver then
        self._rverFill = self.def._rver
        self._resolved = nil
    end
    return BaseFill(self, mode)
end

-- the buff bars' seeds follow the game's tracked bars
local BaseSeeds = Engine.V2BarSeeds
if BaseSeeds then
    function Engine:V2BarSeeds()
        if self._rverSeeds ~= self.def._rver then
            self._rverSeeds = self.def._rver
            self._v2barSeeds = nil
        end
        return BaseSeeds(self)
    end
end

-- the utility row and the buff bars start on this HUD's own spots (the
-- engine makes their anchors on the spots the Classic HUDs use; a spot
-- the mover saved still wins, HUD.PlaceAnchor)
local BaseEnsureUtility = Engine.V2EnsureUtility
if BaseEnsureUtility then
    function Engine:V2EnsureUtility()
        local had = self.anchors.Utility
        BaseEnsureUtility(self)
        if not had and self.anchors.Utility then
            local cfg = self:Store()
            local u = cfg and V2.Util and V2.Util(cfg)
            if u and (u.x or u.y) then HUD.PlaceAnchor(self.def.prefix .. "Utility", self.holders.Utility, u) end
        end
    end
end
local BaseEnsureBars = Engine.V2EnsureBars
if BaseEnsureBars then
    function Engine:V2EnsureBars()
        local had = self.anchors.BuffBars
        BaseEnsureBars(self)
        if not had and self.anchors.BuffBars then
            local cfg = self:Store()
            local b = cfg and V2.BuffBarsCfg and V2.BuffBarsCfg(cfg)
            if b and (b.x or b.y) then HUD.PlaceAnchor(self.def.prefix .. "BuffBars", self.holders.BuffBars, b) end
        end
    end
end

-- ------------------------------------------------------------
-- spells: known is the game's own word on the entry; reads go by the id
-- in force (the override where one replaced the spell)
-- ------------------------------------------------------------
local BaseResolve = Engine.ResolveSpells
function Engine:ResolveSpells()
    BaseResolve(self)
    local S, def = self.S, self.def
    for key in pairs(S.spells) do
        if not (def.spells and def.spells[key]) then
            S.spells[key], S.cds[key], S.usable[key], S.inRange[key] = nil, nil, nil, nil
        end
    end
    local texOf = HUD.GetSpellTexture
    for li = 1, 2 do
        local list = (li == 1) and def.grid or def.utility
        for _, e in ipairs(list or {}) do
            local sp = e.fromGame and S.spells[e.key] or nil
            if sp then
                local id = e.curId or (def.spells and def.spells[e.key])
                sp.id = id
                if not self.sample then sp.known = (sp.name ~= nil and e.isKnown ~= false) and true or false end
                if id and texOf then
                    local ok, tex = pcall(texOf, id)
                    if ok and tex ~= nil and not IsSecret(tex) then sp.icon = tex end
                end
            end
        end
    end
end

-- one spell's cooldown, read safely into cd
local function ReadCooldown(cd, id, now)
    local CSp = C_Spell
    local s, d, act, gcd
    if CSp and CSp.GetSpellCooldown then
        local ok, info = pcall(CSp.GetSpellCooldown, id)
        if ok and type(info) == "table" then
            s, d, act, gcd = info.startTime, info.duration, info.isActive, info.isOnGCD
        end
    end
    local hidden = IsSecret(s) or IsSecret(d)
    if hidden or type(s) ~= "number" or type(d) ~= "number" then
        -- hidden: no numbers of ours; the game's duration object draws the swipe
        cd.start, cd.duration, cd.durObj = 0, 0, nil
        if hidden and CSp.GetSpellCooldownDuration then
            local ok, obj = pcall(CSp.GetSpellCooldownDuration, id)
            if ok and obj then cd.durObj = obj end
        end
        s, d = nil, nil
    else
        cd.start, cd.duration, cd.durObj = s, d, nil
    end
    -- on cooldown: the game's own flags (never hidden; API docs). isOnGCD
    -- is only a hint outside the cooldown event (and may be nil: then it
    -- is not the global one), so a cooldown it calls global still counts
    -- once it outlasted any global cooldown.
    act = Plain(act)
    if type(act) == "boolean" then
        if act then
            cd.since = cd.since or now
            local onGCD = Plain(gcd)
            if d and d > 0 then
                cd.real = d > GCD_MAX
            else
                cd.real = (onGCD ~= true) or (now - cd.since) > GCD_OUTLAST
            end
        else
            cd.since, cd.real = nil, false
        end
    else
        cd.since = nil
        cd.real = (d ~= nil and d > GCD_MAX) or false
    end
end

function Engine:UpdateSpellSnapshot()
    local S = self.S
    local CSp = C_Spell
    local now = GetTime()
    for key, sp in pairs(S.spells) do
        if sp.known and sp.name then
            local id = sp.id or sp.name
            local cd = S.cds[key]
            if not cd then cd = {} S.cds[key] = cd end
            ReadCooldown(cd, id, now)
            local us = S.usable[key]
            if not us then us = {} S.usable[key] = us end
            us.usable, us.noPower = true, false
            if CSp and CSp.IsSpellUsable then
                local ok, usable, noPower = pcall(CSp.IsSpellUsable, id)
                if ok then
                    usable, noPower = Plain(usable), Plain(noPower)
                    us.usable = usable ~= false
                    us.noPower = noPower == true
                end
            end
            local inRange
            if S.targetAttackable and CSp and CSp.IsSpellInRange then
                local ok, r = pcall(CSp.IsSpellInRange, id, "target")
                if ok then
                    r = Plain(r)
                    if type(r) == "boolean" then inRange = r and 1 or 0 end
                end
            end
            S.inRange[key] = inRange
        end
    end
end

-- no five-second rule, energy tick or wand on Retail: the power events
-- have nothing to time
function Engine:OnPowerEvent() end

-- no target debuff row on Retail (the game hides an enemy's auras from
-- addons in a fight): the target is never walked
function Engine:ScanTargetDebuffs() end

-- ------------------------------------------------------------
-- the power bar: the game's values straight onto the bar and its text
-- ------------------------------------------------------------
local POWER_COL = { [0] = "mana", [1] = "rage", [3] = "energy" }
local function PowerColor(eng, ptype, token)
    local key = POWER_COL[ptype]
    if key then return eng:Col(key) end
    -- every other power in the game's own colour for it
    local pc = PowerBarColor
    local c = type(pc) == "table" and ((token and pc[token]) or pc[ptype]) or nil
    if type(c) == "table" and type(c.r) == "number" then
        local t = eng._rpowCol
        if not t or t.token ~= (token or ptype) then
            t = { c.r, c.g, c.b, 1, token = token or ptype }
            eng._rpowCol = t
        end
        return t
    end
    return eng:Col("energy")
end

local BaseBuildBars = Engine.BuildBars
function Engine:BuildBars()
    BaseBuildBars(self)
    local b = self.powerBar
    if not b then return end
    local eng, S = self, self.S
    b:SetScript("OnUpdate", function(self2)
        local cur, max, ptype, token
        if eng.sample then
            cur, max, ptype = S.power or 0, S.powerMax or 100, 3
        else
            ptype, token = UnitPowerType("player")
            ptype, token = Plain(ptype), Plain(token)
            cur, max = UnitPower("player"), UnitPowerMax("player")
        end
        -- hidden or not, the bar and the number take them as they are
        -- (never compared, never counted with; a refused value shows nothing)
        if not (pcall(self2.bar.SetMinMaxValues, self2.bar, 0, max) and pcall(self2.bar.SetValue, self2.bar, cur)) then
            pcall(self2.bar.SetMinMaxValues, self2.bar, 0, 1)
            pcall(self2.bar.SetValue, self2.bar, 0)
        end
        if not pcall(self2.text.SetText, self2.text, cur) then self2.text:SetText("") end
        local c = PowerColor(eng, ptype, token)
        if self2.lastColor ~= c then
            self2.lastColor = c
            self2:SetBarColor(c[1], c[2], c[3], 1)
        end
    end)
end

local BaseResources = Engine.RefreshResources
function Engine:RefreshResources(cfg)
    BaseResources(self, cfg)
    if self.powerBar then
        self.powerBar:SetShown((self:On(cfg) and cfg.resources.power) and true or false)
    end
    if self.tickBar then self.tickBar:Hide() end
end

-- (the engine's own hide walks a list that ends at the first bar a HUD
-- does not have; this HUD has only the power bar)
local BaseHideAll = Engine.HideAll
function Engine:HideAll()
    BaseHideAll(self)
    if self.powerBar then self.powerBar:Hide() end
    if self.tickBar then self.tickBar:Hide() end
end

-- ------------------------------------------------------------
-- your buffs: one the game will not name in a fight is asked for by the
-- entry's spell ids, and shown as the game hands it over
-- ------------------------------------------------------------
local function AuraById(get, id)
    if type(id) ~= "number" then return nil end
    local ok, a = pcall(get, id)
    if ok and type(a) == "table" then return a end
    return nil
end

local BaseScanBuffs = Engine.ScanPlayerBuffs
function Engine:ScanPlayerBuffs()
    BaseScanBuffs(self)
    if self.sample then return end
    local get = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
    if not get then return end
    local S = self.S
    local cache = self._rbuffs
    if not cache then cache = {} self._rbuffs = cache end
    for _, e in ipairs(self.def.buffRow or {}) do
        local name = S.auraNames[e.key]
        local lname = name and name:lower()
        if lname and not S.buffs[lname] then
            local a = AuraById(get, e.id)
            if not a then
                for _, id in ipairs(e.altIds or {}) do
                    a = AuraById(get, id)
                    if a then break end
                end
            end
            if a then
                local b = cache[e.key]
                if not b then b = {} cache[e.key] = b end
                b.name, b.unit = name, "player"
                if ns.AuraFieldsHidden(a) then
                    b.icon, b.count, b.duration, b.expirationTime, b.hidden = a.icon, nil, nil, nil, a
                else
                    b.icon, b.count, b.duration, b.expirationTime, b.hidden =
                        a.icon, a.applications, a.duration, a.expirationTime, nil
                end
                S.buffs[lname] = b
            end
        end
    end
end

-- (the engine times a hidden aura as the target's; these are the player's)
local BaseAuraList = Engine.RefreshAuraList
function Engine:RefreshAuraList(cfg, list, icons, active, rowCfg, anchor, source, memo)
    BaseAuraList(self, cfg, list, icons, active, rowCfg, anchor, source, memo)
    for _, icon in ipairs(active) do
        local b = icon.auraRef
        if b and b.hidden and b.unit == "player" and icon.cd then
            ns.ShowAuraTimer(icon.cd, "player", b.hidden)
        end
    end
end

-- the buff bars ask the game for a hidden buff of yours themselves (by
-- the player's unit); the entries above stay out of their way
local BaseBars = Engine.V2RefreshBars
if BaseBars then
    function Engine:V2RefreshBars(cfg)
        local S = self.S
        local held = self._rheld
        if not held then held = {} self._rheld = held end
        local any = false
        for lname, b in pairs(S.buffs) do
            if b.hidden and b.unit == "player" then
                held[lname] = b
                any = true
            end
        end
        if any then for lname in pairs(held) do S.buffs[lname] = nil end end
        BaseBars(self, cfg)
        if any then
            for lname, b in pairs(held) do
                S.buffs[lname] = b
                held[lname] = nil
            end
        end
    end
end

-- ------------------------------------------------------------
-- timers the game hides: the text takes them as they are
-- ------------------------------------------------------------
local function Remaining(obj) return obj:GetRemainingDuration() end

local BaseTextTick = Engine.TextTick
function Engine:TextTick()
    BaseTextTick(self)
    if self.sample or not self:IsActive() then return end
    local S, W = self.S, self.W
    if not W then return end
    local now = GetTime()
    for li = 1, 2 do
        local list = (li == 1) and self.mainActive or self.utilActive
        for _, icon in ipairs(list or {}) do
            local def = icon.def
            local cd = def and def.kind == "spell" and S.cds[def.spell] or nil
            if cd and cd.real and cd.durObj then
                local ok, left = pcall(Remaining, cd.durObj)
                if ok then icon:SetHiddenText("p", "%.0f", left) end
            elseif li == 2 then
                -- (the utility row's plain countdown: the engine writes the grid's only)
                local left = (cd and cd.real) and (cd.start + cd.duration - now) or 0
                icon:SetText("p", left > 0 and W.FormatTime(left, 0) or "")
            end
        end
    end
    for _, icon in ipairs(self.auraActive) do
        local b = icon.auraRef
        if b and b.hidden and b.unit == "player" then
            local left = ns.AuraTimeLeft("player", b.hidden)
            if left ~= nil then icon:SetHiddenText("p", "%.0f", left) else icon:SetText("p", "") end
            icon:SetHiddenCount("s", "player", b.hidden)
        end
    end
end

-- ------------------------------------------------------------
-- glow conditions that would compare a hidden timer or stack count are
-- not offered on Retail (a saved rule keeps its condition listed)
-- ------------------------------------------------------------
local NO_GLOW_WHEN = { expiring = true, stacks = true, anticlip = true, queued = true }
local BaseGlowWhen = Engine.V2GlowWhenFor
if BaseGlowWhen then
    function Engine:V2GlowWhenFor(gk, keep)
        local list = BaseGlowWhen(self, gk, keep)
        local out = {}
        for _, w in ipairs(list) do
            if not NO_GLOW_WHEN[w.id] or w.id == keep then out[#out + 1] = w end
        end
        return out
    end
end

-- ============================================================
-- THE DEFINITION (the player's class only)
-- ============================================================
local _, CLASS = UnitClass("player")
local C = CLASS and CLASSES[CLASS]
if not C then return end

local roles = {}
for _, s in ipairs(C.specs) do
    local keys = {}
    for _, id in ipairs(s[4] or {}) do keys[#keys + 1] = "game" .. id end
    roles[#roles + 1] = { key = s[2], label = s[3], specID = s[1], show = { utility = keys } }
end

local eng = HUD.DefineClass({
    class = CLASS, className = C.name, label = C.name .. " HUD", store = "retail_" .. CLASS:lower(),
    prefix = C.prefix, frameName = "Retail" .. C.name:gsub("%s", ""),
    retail = true,
    blurb = "Your spec's cooldowns from the game's own Cooldown Manager list, a utility row with the interrupt "
        .. "and defensives, your tracked buffs and a power bar.",
    keywords = C.name:lower() .. " hud class cooldown manager cooldown grid utility interrupt defensive buffs "
        .. "buff bars power bar spec trinkets racial retail",
    powerLabel = "Power",
    spells = {}, grid = {}, utility = {}, buffRow = {},
    roles = roles,
    bars = { "power" },
    -- the utility row and the buff bars are part of this HUD from the start
    -- (elsewhere they are extras that start off), each on a spot of its own
    -- under the grid's three rows (the grid: -208 down to -284); the HUD
    -- itself is off until its page turns it on, like every class HUD
    defaults = { v2 = { utility = { enabled = true, x = 0, y = -300 }, buffBars = { enabled = true, x = 0, y = -330 } } },
})
HUD.RetailEngine = eng

-- the spec changed, or the game's Cooldown Manager data arrived or moved:
-- the list is read again on the next tick and the spec looked at again
-- (flags only here; HUD_V2_Modern marks its own cache on the same events)
local watch = CreateFrame("Frame")
do
    local valid = C_EventUtils and C_EventUtils.IsEventValid
    for _, e in ipairs({ "PLAYER_SPECIALIZATION_CHANGED", "COOLDOWN_VIEWER_DATA_LOADED",
        "COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED" }) do
        if not valid or valid(e) then pcall(watch.RegisterEvent, watch, e) end
    end
end
watch:SetScript("OnEvent", function()
    if V2.CatalogueDirty then V2.CatalogueDirty() end
    eng.dirty.spells = true
    if eng.V2MarkSpec then eng:V2MarkSpec() end
end)
