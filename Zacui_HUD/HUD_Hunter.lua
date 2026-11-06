-- HUD_Hunter - the Hunter HUD, built by HUD_ClassHUD from this
-- definition: cooldown grid, active buffs, your stings and marks on the
-- target, reminders (no aspect, no pet, ammo running out, Trueshot
-- Aura down), mana + five-second-rule bars and an Auto Shot timer.
-- Spell ids are the Classic Era top ranks; the engine looks each one up
-- by name so the rank the character actually knows is what it tracks.
-- Part of ZacUI; load order is set by the TOC.

local ns = _G.ZacUI
if not ns or not ns.HUD or not ns.HUD.DefineClass then return end

local ASPECTS = { "aspectHawk", "aspectMonkey", "aspectCheetah", "aspectPack", "aspectBeast", "aspectWild" }

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
        explosiveTrap = 14317, immolationTrap = 14305, disengage = 20909,
        counterattack = 20910, wyvern = 19386, viperSting = 14280,
        scorpidSting = 14277, serpentSting = 13555, huntersMark = 14325,
        aspectHawk = 14322, aspectMonkey = 13163, aspectCheetah = 5118,
        aspectPack = 13159, aspectBeast = 13161, aspectWild = 20190,
        trueshot = 20906, callPet = 883, flare = 1543,
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
        { key = "serpentSting",  id = 13555 },
        { key = "viperSting",    id = 14280 },
        { key = "scorpidSting",  id = 14277 },
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

    bars = { "mana", "fsr", "ranged", "swing" },
})
