-- HUD_Hunter - the Hunter HUD, built by HUD_ClassHUD from this
-- definition: cooldown grid, active buffs, your stings and marks on the
-- target, reminders (no aspect, no pet, ammo running out, Trueshot
-- Aura down), mana + five-second-rule bars and an Auto Shot timer.
-- Spell ids are the Classic Era top ranks; the engine looks each one up
-- by name so the rank the character actually knows is what it tracks.
-- Part of ZacUI; load order is set by the TOC.

local ns = _G.ZacUI
if not ns or not ns.HUD or not ns.HUD.DefineClass then return end
if ns.HUD.RETAIL then return end   -- (Retail: its own class HUD, HUD_Retail.lua; this Classic one never loads there)

local ASPECTS = { "aspectHawk", "aspectMonkey", "aspectCheetah", "aspectPack", "aspectBeast", "aspectWild", "aspectViper" }

ns.HUD.DefineClass({
    class = "HUNTER", className = "Hunter", label = "Hunter HUD", store = "hunter",
    prefix = "hh", frameName = "Hunter",
    blurb = "Cooldown grid, active buffs, stings on the target, reminders, mana + "
        .. "five-second-rule bars and an Auto Shot timer.",
    keywords = "hunter hud class pack cooldown grid aspect pet ammo sting trap "
        .. "rapid fire feign death auto shot timer mana bar trinkets racial",

    spells = {
        rapidFire = 3045, feign = 5384, deterrence = 19263, scatter = 19503,
        concussive = 5116, aimed = 20904, multi = 25294, intimidation = 19577,
        bestialWrath = 19574, frostTrap = 13809, freezingTrap = 14311,
        explosiveTrap = 14317, immolationTrap = 14305, disengage = 14273,
        counterattack = 20910, wyvern = 19386, viperSting = 14280,
        scorpidSting = 14277, serpentSting = 13555, huntersMark = 14325,
        aspectHawk = 14322, aspectMonkey = 13163, aspectCheetah = 5118,
        aspectPack = 13159, aspectBeast = 13161, aspectWild = 20190,
        trueshot = 20906, callPet = 883, flare = 1543,
        raptorStrike = 14266, mongooseBite = 14271, wingClip = 14268, arcaneShot = 14287,
        volley = 14295, tranqShot = 19801, scareBeast = 14327, mendPet = 13543, revivePet = 982,
    },

    grid = {
        { key = "rapidFire",     kind = "spell", spell = "rapidFire",     label = "Rapid Fire", noRange = true },
        { key = "feign",         kind = "spell", spell = "feign",         label = "Feign Death", noRange = true },
        { key = "deterrence",    kind = "spell", spell = "deterrence",    label = "Deterrence", noRange = true },
        { key = "scatter",       kind = "spell", spell = "scatter",       label = "Scatter Shot" },
        { key = "concussive",    kind = "spell", spell = "concussive",    label = "Concussive Shot" },
        { key = "aimed",         kind = "spell", spell = "aimed",         label = "Aimed Shot" },
        { key = "multi",         kind = "spell", spell = "multi",         label = "Multi-Shot" },
        { key = "intimidation",  kind = "spell", spell = "intimidation",  label = "Intimidation", noRange = true },
        { key = "bestialWrath",  kind = "spell", spell = "bestialWrath",  label = "Bestial Wrath", noRange = true },
        { key = "frostTrap",     kind = "spell", spell = "frostTrap",     label = "Frost Trap", noRange = true },
        { key = "freezingTrap",  kind = "spell", spell = "freezingTrap",  label = "Freezing Trap", noRange = true },
        { key = "explosiveTrap", kind = "spell", spell = "explosiveTrap", label = "Explosive Trap", noRange = true },
        { key = "disengage",     kind = "spell", spell = "disengage",     label = "Disengage" },
        { key = "counterattack", kind = "spell", spell = "counterattack", label = "Counterattack" },
        { key = "wyvern",        kind = "spell", spell = "wyvern",        label = "Wyvern Sting" },
        { key = "flare",         kind = "spell", spell = "flare",         label = "Flare", noRange = true },
        { key = "potion",        kind = "itemPotion", label = "Potion" },
        { key = "rune",          kind = "itemRune",   label = "Rune" },
    },

    buffRow = {
        { key = "rapidFire",     id = 3045 },
        { key = "quickShots",    id = 6150,  label = "Quick Shots" },
        { key = "aspectHawk",    id = 14322 },
        { key = "aspectMonkey",  id = 13163 },
        { key = "aspectCheetah", id = 5118 },
        { key = "aspectPack",    id = 13159 },
        { key = "aspectBeast",   id = 13161 },
        { key = "aspectWild",    id = 20190 },
        { key = "trueshot",      id = 20906 },
        { key = "zhc",           id = 24659, name = "Zandalarian Hero Charm", label = "Zandalarian Hero Charm" },
    },

    debuffRow = {
        { key = "serpentSting",  id = 13555, castsDot = true },
        { key = "viperSting",    id = 14280, castsDot = true },
        { key = "scorpidSting",  id = 14277, castsDot = true },
        { key = "wyvern",        id = 19386 },
        { key = "huntersMark",   id = 14325 },
        { key = "wingClip",      id = 14268 },
        { key = "concussive",    id = 5116 },
        { key = "scatter",       id = 19503 },
        { key = "freezingTrap",  id = 14309, label = "Freezing Trap Effect" },
        { key = "counterattack", id = 20910 },
    },

    reminders = {
        { key = "aspect", label = "No aspect up", spell = "aspectHawk",
          check = function(H) return H.Known("aspectHawk") and not H.AnyBuff(ASPECTS) end },
        { key = "trueshot", label = "Trueshot Aura down", spell = "trueshot", default = false,
          check = function(H) return H.Known("trueshot") and not H.Buff("trueshot") end },
        { key = "pet", label = "No pet out", spell = "callPet",
          check = function(H)
              if not H.Known("callPet") then return false end
              if UnitExists("pet") and not UnitIsDeadOrGhost("pet") then return false end
              return not (UnitIsDeadOrGhost("player") or IsMounted and IsMounted())
          end },
        { key = "ammo", label = "Ammo running out", icon = 132382, previewCount = 150,
          check = function(H)
              local n = GetInventoryItemCount and GetInventoryItemCount("player", 0) or 0
              if n >= 200 then return false end
              local tex = GetInventoryItemTexture and GetInventoryItemTexture("player", 0) or 132382
              return true, tex, n
          end },
    },


    -- Class HUD v2 (HUD_V2_Sources): the utility row's spells (off until
    -- the row is turned on), the roles "Set up for" can tick, a game
    -- version's own additions. Nothing here changes the HUD as it is.
    utility = {
        { key = "huntersMark",   kind = "spell", spell = "huntersMark",   label = "Hunter's Mark" },
        { key = "raptorStrike",  kind = "spell", spell = "raptorStrike",  label = "Raptor Strike", nextSwing = true },
        { key = "mongooseBite",  kind = "spell", spell = "mongooseBite",  label = "Mongoose Bite" },
        { key = "wingClip",      kind = "spell", spell = "wingClip",      label = "Wing Clip" },
        { key = "arcaneShot",    kind = "spell", spell = "arcaneShot",    label = "Arcane Shot" },
        { key = "immolationTrap", kind = "spell", spell = "immolationTrap", label = "Immolation Trap", noRange = true },
        { key = "volley",        kind = "spell", spell = "volley",        label = "Volley", noRange = true },
        { key = "tranqShot",     kind = "spell", spell = "tranqShot",     label = "Tranquilizing Shot" },
        { key = "scareBeast",    kind = "spell", spell = "scareBeast",    label = "Scare Beast" },
        { key = "mendPet",       kind = "spell", spell = "mendPet",       label = "Mend Pet", noRange = true },
        { key = "revivePet",     kind = "spell", spell = "revivePet",     label = "Revive Pet", noRange = true },
    },
    -- Spec presets (HUD_V2_Specs): each spec's default HUD, from what top
    -- players press and track (sources in CLASSHUD_V2_DESIGN_1107.md
    -- section 13: Icy Veins' and Wowhead's Classic and TBC hunter guides).
    -- The base lists are Classic Era's; a spec's tbc or forever block
    -- replaces the rows it names on that game version (WoW Forever: Summon
    -- Hawk, Sniper Shot and Lacerating Strikes are its own, and Serpent
    -- Sting is worth a slot there). Your own ticks always win.
    roles = {
        { key = "bm", label = "Beast Mastery", tab = 1, aux = true, show = {
            main = { "rapidFire", "bestialWrath", "aimed", "multi", "feign", "potion", "rune" },
            utility = { "huntersMark", "raptorStrike", "mendPet", "revivePet", "tranqShot", "arcaneShot" },
            buffs = { "rapidFire", "quickShots", "aspectHawk", "zhc" },
            debuffs = { "huntersMark" } },
          glows = { rapidFire = { { when = "ready", style = "edge", combatOnly = true } },
                    bestialWrath = { { when = "ready", style = "edge", combatOnly = true } } },
          tbc = { show = {
              main = { "rapidFire", "bestialWrath", "killCommand", "multi", "misdirection", "feign", "potion", "rune" },
              buffs = { "rapidFire", "beastWithin", "quickShots", "aspectHawk", "aspectViper", "zhc" } },
            glows = { rapidFire = { { when = "ready", style = "edge", combatOnly = true } },
                      bestialWrath = { { when = "ready", style = "edge", combatOnly = true } },
                      killCommand = { { when = "usable", style = "pulse", combatOnly = true } } } },
          forever = { show = {
              main = { "rapidFire", "bestialWrath", "aimed", "multi", "summonHawk", "feign", "potion", "rune" },
              debuffs = { "huntersMark", "serpentSting" } } } },
        { key = "mm", label = "Marksmanship", tab = 2, aux = true, show = {
            main = { "rapidFire", "aimed", "multi", "feign", "potion", "rune" },
            utility = { "huntersMark", "raptorStrike", "arcaneShot", "tranqShot", "mendPet" },
            buffs = { "rapidFire", "quickShots", "aspectHawk", "trueshot", "zhc" },
            debuffs = { "huntersMark" } },
          glows = { rapidFire = { { when = "ready", style = "edge", combatOnly = true } },
                    aimed = { { when = "ready", style = "edge", combatOnly = true } } },
          tbc = { show = {
              main = { "rapidFire", "killCommand", "multi", "silencingShot", "misdirection", "feign", "potion", "rune" },
              buffs = { "rapidFire", "quickShots", "aspectHawk", "aspectViper", "trueshot", "zhc" } },
            glows = { rapidFire = { { when = "ready", style = "edge", combatOnly = true } },
                      killCommand = { { when = "usable", style = "pulse", combatOnly = true } } } },
          forever = { show = {
              main = { "rapidFire", "aimed", "sniperShot", "multi", "feign", "potion", "rune" },
              debuffs = { "huntersMark", "serpentSting" } } } },
        { key = "sv", label = "Survival", tab = 3, aux = true, res = { queued = true, rangeDim = true }, show = {
            main = { "rapidFire", "aimed", "multi", "feign", "potion", "rune" },
            utility = { "huntersMark", "raptorStrike", "mongooseBite", "wingClip", "tranqShot", "mendPet" },
            buffs = { "rapidFire", "quickShots", "aspectHawk", "zhc" },
            debuffs = { "huntersMark" } },
          glows = { rapidFire = { { when = "ready", style = "edge", combatOnly = true } } },
          tbc = { res = {}, show = {
              main = { "rapidFire", "readiness", "killCommand", "multi", "misdirection", "feign", "potion", "rune" },
              utility = { "huntersMark", "arcaneShot", "tranqShot", "mendPet" },
              buffs = { "rapidFire", "quickShots", "aspectHawk", "aspectViper", "zhc" },
              debuffs = { "huntersMark", "exposeWeakness" } },
            glows = { rapidFire = { { when = "ready", style = "edge", combatOnly = true } },
                      killCommand = { { when = "usable", style = "pulse", combatOnly = true } } } },
          forever = { show = {
              debuffs = { "huntersMark", "serpentSting", "laceratingStrikes" } } } },
    },
    flavors = {
        tbc = { add = {
            { key = "misdirection",  kind = "spell", spell = "misdirection",  spellId = 34477, label = "Misdirection" },
            { key = "killCommand",   kind = "spell", spell = "killCommand",   spellId = 34026, label = "Kill Command", noRange = true },
            { key = "silencingShot", kind = "spell", spell = "silencingShot", spellId = 34490, label = "Silencing Shot" },
            { key = "snakeTrap",     kind = "spell", spell = "snakeTrap",     spellId = 34600, label = "Snake Trap", noRange = true },
            { key = "readiness",     kind = "spell", spell = "readiness",     spellId = 23989, label = "Readiness", noRange = true },
            { key = "aspectViper",   id = 34074, label = "Aspect of the Viper", row = "buffs" },
            { key = "beastWithin",   id = 34471, label = "The Beast Within", row = "buffs" },
            { key = "exposeWeakness", id = 34501, label = "Expose Weakness", row = "debuffs" },
        }, spells = { aspectViper = 34074 } },
        forever = { add = {
            { key = "summonHawk",        kind = "spell", spell = "summonHawk", spellId = 1293241, label = "Summon Hawk" },
            { key = "sniperShot",        kind = "spell", spell = "sniperShot", spellId = 1310687, label = "Sniper Shot" },
            { key = "laceratingStrikes", id = 1310533, label = "Lacerating Strikes", row = "debuffs" },
        } },
    },
    buffBars = { "rapidFire", "quickShots" },
    bars = { "mana", "fsr", "ranged", "swing" },
})
