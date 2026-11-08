-- Meter_RaidSummary - a summary of the whole raid for you, when its last
-- boss dies (or any time with /zui raid): your damage and where it ranks
-- in the raid and among your own class, every boss with your DPS and
-- rank, your abilities next to the rest of your class (share of damage,
-- hits a minute), the boss and trash abilities that hit you hardest next
-- to what they did to the rest of your class, your deaths and what killed
-- you, and - on a warrior - the hesitation numbers for the night (how
-- long Bloodthirst and Whirlwind sat ready, on bosses and on trash).
--
-- 2026-10-28, Zac: "i like that it has a ton of info but im already
-- ignoring it tbh. i feel like it needs to be more to the point." The
-- top is now one card: four numbers (boss DPS, class rank, against your
-- last time in this raid, deaths), one plain sentence, and at most three
-- things to fix - ranked by the DPS each one cost, with that number on
-- it - plus one thing that went well. Every table below it starts
-- folded.
-- Part of ZacUI; load order is set by the TOC.
--
-- WHERE THE NUMBERS COME FROM. The meter's own segments: every segment
-- that closes inside a raid instance is folded into that raid's session
-- here, as plain numbers (no meter objects are kept), so the summary
-- survives a reload and the last few raids stay in the per-character
-- saved variables. The hesitation system hands over each pull's numbers
-- the same way (H.OnFightStats). Nothing runs during combat: the work is
-- done once per closed segment.

local ADDON_NAME = ...
-- Zacui_Meter is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

-- shared state from earlier ZacUI files
local Meter = ns.Meter
if not Meter then return end
local Print = ns.Print
local UI = ns.UI

local RS = {}
Meter.RaidSummary = RS
ns.RaidSummary = RS

local floor, max, min, format = math.floor, math.max, math.min, string.format

local KEEP = 12              -- raids kept per character
local SESSION_GAP = 6 * 3600 -- a raid left this long ago is a new raid

-- the last boss of each raid (ENCOUNTER_END ids), with names as a fallback
-- (Classic Era's; another game version's are asked of Core_FlavorRaids,
-- and a game whose raids are not listed ends a raid by the lockout)
local FINAL_ID = { [672] = true, [1084] = true, [617] = true, [793] = true,
    [723] = true, [717] = true, [1114] = true }
local FINAL_NAME = { ["Ragnaros"] = true, ["Onyxia"] = true, ["Nefarian"] = true,
    ["Hakkar"] = true, ["Ossirian the Unscarred"] = true, ["C'Thun"] = true,
    ["Kel'Thuzad"] = true }

-- ============================================================
-- SETTINGS + STORE
-- ============================================================
local function Cfg()
    if type(ZacUIDB) ~= "table" then return nil end
    ZacUIDB.meter = ZacUIDB.meter or {}
    local d = ZacUIDB.meter
    if d.raidSummary == nil then d.raidSummary = true end
    if d.raidSummaryShow == nil then d.raidSummaryShow = true end
    -- the detail tables all start folded now (2026-10-28): what was
    -- left open before is forgotten once
    if not d._rsFoldV2 then d._rsFoldV2 = true d.raidSummaryOpen = nil end
    return d
end
RS.Cfg = Cfg

local function Store()
    ZacUICharDB = ZacUICharDB or {}
    ZacUICharDB.raidSummaries = ZacUICharDB.raidSummaries or {}
    return ZacUICharDB.raidSummaries
end
RS.Store = Store

local function MyClass()
    local _, c = UnitClass("player")
    return c or "WARRIOR"
end

local function NewSession(name, id)
    local s = {
        raid = name or "Raid", instanceID = id, started = time(), last = time(),
        class = MyClass(), me = UnitName("player"),
        bossTime = 0, trashTime = 0, segments = 0,
        players = {}, names = {}, bosses = {}, taken = {}, deaths = {}, myDeaths = {},
        hes = { boss = {}, trash = {}, wrongOrder = 0, pulls = 0 },
    }
    local st = Store()
    st[#st + 1] = s
    while #st > KEEP do table.remove(st, 1) end
    return s
end

-- the raid this segment belongs to: the open one for this instance, or a
-- new one (a finished raid takes what arrives in the minute after its
-- last boss - the last pull's hesitation numbers come a moment later).
-- name/id: the instance the fight was in, when the caller knows it (a
-- segment is folded in a moment after the fight, by when the player may
-- have released and left); otherwise the instance the player is in now.
local function Session(create, name, id)
    if not id then
        local n, itype, _, _, _, _, _, i = GetInstanceInfo()
        if itype ~= "raid" then return nil end
        name, id = n, i
    end
    local st = Store()
    local s = st[#st]
    local now = time()
    if s and s.instanceID == id and (now - (s.last or 0)) < SESSION_GAP then
        if not s.done or (now - (s.doneAt or 0)) < 60 then return s end
    end
    if not create then return nil end
    return NewSession(name, id)
end

-- ============================================================
-- COLLECTING
-- ============================================================
local function IsPlayerClass(c)
    return c and RAID_CLASS_COLORS and RAID_CLASS_COLORS[c] ~= nil
end

-- DPS ranks among players who were there for a decent part of it
local function Ranks(list, me, myClass)
    table.sort(list, function(a, b) return a.dps > b.dps end)
    local rank, of, crank, cof, top, ctop = nil, #list, nil, 0, list[1], nil
    for i, p in ipairs(list) do
        if p.name == me then rank = i end
        if p.class == myClass then
            cof = cof + 1
            if not ctop then ctop = p end
            if p.name == me then crank = cof end
        end
    end
    return rank, of, crank, cof, top, ctop
end

-- Deaths into the session: everyone's count, and for each of yours the
-- killing blow and the hits before it as plain numbers (the meter's own
-- DeathSummary, so the summary words a death exactly as the meter does).
-- The spell names are kept with them: the summary reads after a reload.
function RS.FoldDeaths(s, combat, me)
    for _, dt in ipairs(combat.deaths or {}) do
        if dt.name then
            s.deaths[dt.name] = (s.deaths[dt.name] or 0) + 1
            if dt.name == me then
                local d = { where = combat:Name(), at = floor(dt.deadAt or 0) }
                if Meter.DeathSummary then
                    local sum = Meter.DeathSummary(dt, 3)
                    d.spell, d.src, d.amt, d.over = sum.spell, sum.src, sum.amt, sum.over
                    d.sure, d.seen = sum.sure, sum.seen
                    d.before = {}
                    for _, e in ipairs(sum.before) do
                        d.before[#d.before + 1] = { dmg = e.dmg, spell = e.spell, src = e.src, amt = floor(e.amt or 0) }
                    end
                end
                s.myDeaths[#s.myDeaths + 1] = d
                local ids = { d.spell }
                for _, e in ipairs(d.before or {}) do ids[#ids + 1] = e.spell end
                for _, id in ipairs(ids) do
                    if id and GetSpellInfo and not s.names[id] then
                        local n = GetSpellInfo(id)
                        if n then s.names[id] = n end
                    end
                end
            end
        end
    end
end

function RS.OnSegment(combat, instName, instId)
    local d = Cfg()
    if not (d and d.raidSummary) or not combat or combat.overall then return end
    local s = Session(true, instName, instId)
    if not s then return end
    local dur = combat:GetCombatTime() or 0
    if dur < 1 then return end
    s.last = time()
    s.segments = s.segments + 1
    local boss = combat.isBoss
    if boss then s.bossTime = s.bossTime + dur else s.trashTime = s.trashTime + dur end
    local me, myClass = s.me, s.class

    local segList = {}
    local myActor
    for _, a in ipairs(combat.damage.actors) do
        if a.grupo and not a.ownerName and IsPlayerClass(a.class) then
            local act = a.ActivityTime and a:ActivityTime() or dur
            local dmg = floor(a.total or 0)
            local p = s.players[a.name]
            if not p then p = { class = a.class, dmg = 0, act = 0, bossDmg = 0, bossAct = 0 } s.players[a.name] = p end
            p.dmg, p.act = p.dmg + dmg, p.act + act
            if boss then p.bossDmg, p.bossAct = p.bossDmg + dmg, p.bossAct + act end
            -- your class: every ability, for the side-by-side
            if a.class == myClass then
                p.spells = p.spells or {}
                for id, sp in pairs(a.spells or {}) do
                    local e = p.spells[id]
                    if not e then e = { t = 0, n = 0, c = 0 } p.spells[id] = e end
                    e.t = e.t + floor(sp.total or 0)
                    e.n = e.n + (sp.counter or 0)
                    e.c = e.c + (sp.c_amt or 0)
                    if sp.name then s.names[id] = sp.name end
                end
            end
            if a.name == me then myActor = a end
            segList[#segList + 1] = { name = a.name, class = a.class, dps = dmg / max(dur, 1) }
        end
    end

    -- what hit your class: every enemy ability's damage on each of them
    local mine = {}
    for name, p in pairs(s.players) do if p.class == myClass then mine[name] = true end end
    for _, a in ipairs(combat.damage.actors) do
        if not a.grupo and not IsPlayerClass(a.class) then
            for id, sp in pairs(a.spells or {}) do
                for target, amt in pairs(sp.targets or {}) do
                    if mine[target] then
                        local t = s.taken[target]
                        if not t then t = {} s.taken[target] = t end
                        t[id] = (t[id] or 0) + floor(amt)
                        if sp.name then s.names[id] = sp.name end
                    end
                end
            end
        end
    end

    -- deaths, and what killed you
    RS.FoldDeaths(s, combat, me)

    -- a boss row: your DPS and where it ranked
    if boss then
        local rank, of, crank, cof, top, ctop = Ranks(segList, me, myClass)
        local myDps = 0
        if myActor then myDps = (myActor.total or 0) / max(dur, 1) end
        s.bosses[#s.bosses + 1] = { name = boss.name or "Boss", killed = boss.killed and true or false,
            dur = floor(dur), dps = floor(myDps), rank = rank, of = of, crank = crank, cof = cof,
            top = top and { top.name, floor(top.dps), top.class } or nil,
            ctop = ctop and { ctop.name, floor(ctop.dps) } or nil }
        if boss.killed and (FINAL_ID[boss.id or 0] or FINAL_NAME[boss.name or ""]
            or (ns.RaidLastBoss and ns.RaidLastBoss(boss.id, boss.name))) then
            s.done, s.doneAt = true, time()
            RS.ShowSoon(s)
        elseif boss.killed and ns.RaidEndsByLockout and ns.RaidEndsByLockout() then
            ns.WhenRaidCleared("RaidSummary", function()
                if not s.done then
                    s.done, s.doneAt = true, time()
                    RS.ShowSoon(s)
                end
            end)
        end
    end
end

-- the hesitation numbers of one pull (HUD_Hesitation hands them over)
function RS.OnFightStats(out)
    local d = Cfg()
    if not (d and d.raidSummary) or type(out) ~= "table" then return end
    local s = Session(true)
    if not s then return end
    local bucket = out.encounter and s.hes.boss or s.hes.trash
    s.hes.pulls = s.hes.pulls + 1
    s.hes.wrongOrder = s.hes.wrongOrder + (out.wrongOrder or 0)
    for name, a in pairs(out.abilities or {}) do
        local e = bucket[name]
        if not e then e = { short = a.short, presses = 0, total = 0, late = 0, wasted = 0, worst = 0, cdDur = a.cdDur } bucket[name] = e end
        e.presses = e.presses + (a.presses or 0)
        e.total = e.total + (a.total or 0)
        e.late = e.late + (a.late or 0)
        e.wasted = e.wasted + (a.wasted or 0)
        if (a.worst or 0) > e.worst then e.worst, e.worstCause = a.worst, a.worstCause end
        e.cdDur = e.cdDur or a.cdDur
    end
end

-- ============================================================
-- THE NUMBERS FOR THE PAGE
-- ============================================================
local function Num(v)
    v = v or 0
    -- (feature cluster 3) the shared formatter's "summary" style is this
    -- function to the byte, and takes a value the client hides
    if ns.Numbers then return ns.Numbers.Format(v, "summary") end
    if v >= 1e6 then return format("%.2fM", v / 1e6) end
    if v >= 1e4 then return format("%.1fK", v / 1e3) end
    return tostring(floor(v + 0.5))
end
RS.Num = Num

local function Clock(sec)
    sec = floor(sec or 0)
    if sec >= 3600 then return format("%dh %02dm", floor(sec / 3600), floor(sec % 3600 / 60)) end
    return format("%dm %02ds", floor(sec / 60), sec % 60)
end

local function Ordinal(n)
    if not n then return "-" end
    local s = "th"
    local m100 = n % 100
    if m100 < 11 or m100 > 13 then
        local m = n % 10
        if m == 1 then s = "st" elseif m == 2 then s = "nd" elseif m == 3 then s = "rd" end
    end
    return n .. s
end

local function ClassName(c)
    return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[c]) or c
end

local function SpellName(s, id)
    if id == 1 then return "Melee" end
    local n = s.names[id] or (GetSpellInfo and GetSpellInfo(id))
    return n or ("Spell " .. tostring(id))
end

-- one of your deaths in the meter's words: "You died to Shadow Flame from
-- Ebonroc (4,210, 1,350 overkill); before that: ..." (a death saved before
-- the summary kept the numbers has the spell alone)
function RS.DeathText(s, d, short)
    local nameOf = function(id) return SpellName(s, id) end
    if Meter.DeathSentence and (d.seen ~= nil or d.amt) then
        return Meter.DeathSentence(d, "You", nameOf, not short, short and 160 or 400)
    end
    if d.spell then return "You died to " .. SpellName(s, d.spell) .. "." end
    return "You died."
end
-- the killing blow alone, for the short lines
local function KillText(s, d)
    if Meter.KillingBlowText and d.spell then
        return Meter.KillingBlowText(d, function(id) return SpellName(s, id) end)
    end
    return d.spell and SpellName(s, d.spell) or nil
end

-- damage that is not a button you press (procs, auto attacks): never on
-- the fix list as "use it more"
local NOT_PRESSED = { ["Melee"] = true, ["Auto Shot"] = true, ["Shoot"] = true, ["Deep Wounds"] = true,
    ["Windfury Attack"] = true, ["Thrash"] = true, ["Fiery Weapon"] = true, ["Lightning Strike"] = true,
    ["Ignite"] = true, ["Seal of Command"] = true, ["Blade Flurry"] = true, ["Sword Specialization"] = true,
    ["Hand of Justice"] = true, ["Retaliation"] = true }

-- everything the page shows, worked out once
function RS.Build(s)
    local r = { s = s }
    local me = s.players[s.me] or { dmg = 0, act = 0, bossDmg = 0, bossAct = 0, class = s.class }
    r.me = me
    r.dps = me.dmg / max(me.act, 1)
    r.bossDps = me.bossDmg / max(me.bossAct, 1)
    -- raid and class ranks over the night (players there at least a third
    -- as long as you)
    local all, cls = {}, {}
    for name, p in pairs(s.players) do
        if p.act >= (me.act or 0) / 3 or name == s.me then
            local e = { name = name, class = p.class, dps = p.dmg / max(p.act, 1),
                bossDps = p.bossDmg / max(p.bossAct, 1), p = p }
            all[#all + 1] = e
            if p.class == s.class then cls[#cls + 1] = e end
        end
    end
    table.sort(all, function(a, b) return a.dps > b.dps end)
    for i, e in ipairs(all) do if e.name == s.me then r.rank = i end end
    r.of = #all
    table.sort(cls, function(a, b) return a.bossDps > b.bossDps end)
    for i, e in ipairs(cls) do if e.name == s.me then r.crank = i end end
    r.cof = #cls
    r.cbest = cls[1]
    r.classPeers = cls

    -- abilities: yours next to the class average (others of your class)
    local myTotal = 0
    for _, e in pairs(me.spells or {}) do myTotal = myTotal + e.t end
    local peers = {}
    for _, e in ipairs(cls) do if e.name ~= s.me and e.p.spells then peers[#peers + 1] = e.p end end
    r.peers = #peers
    local rows = {}
    for id, e in pairs(me.spells or {}) do
        if e.t > 0 then
            local share = e.t / max(myTotal, 1)
            -- (a night filled from the game's own meter - Forever, Retail -
            -- keeps no hit counts or crits: they read as none)
            local perMin = (e.n or 0) / max((me.act or 0) / 60, 0.1)
            local pShare, pMin, pn = 0, 0, 0
            for _, p in ipairs(peers) do
                local pt = 0
                for _, x in pairs(p.spells) do pt = pt + x.t end
                local x = p.spells[id]
                pShare = pShare + ((x and x.t or 0) / max(pt, 1))
                pMin = pMin + ((x and x.n or 0) / max((p.act or 0) / 60, 0.1))
                pn = pn + 1
            end
            rows[#rows + 1] = { id = id, name = SpellName(s, id), total = e.t, n = e.n or 0, share = share, perMin = perMin,
                crit = (e.c or 0) / max(e.n or 0, 1),
                pShare = pn > 0 and pShare / pn or nil, pMin = pn > 0 and pMin / pn or nil }
        end
    end
    table.sort(rows, function(a, b) return a.total > b.total end)
    r.abilities = rows

    -- what hit you hardest, next to the class average
    local takenRows = {}
    local mine = s.taken[s.me] or {}
    for id, amt in pairs(mine) do
        local sum, n = 0, 0
        for name, t in pairs(s.taken) do
            if name ~= s.me then sum, n = sum + (t[id] or 0), n + 1 end
        end
        takenRows[#takenRows + 1] = { id = id, name = SpellName(s, id), total = amt, avg = n > 0 and sum / n or nil }
    end
    table.sort(takenRows, function(a, b) return a.total > b.total end)
    r.taken = takenRows

    -- hesitation, bosses and trash together and apart
    local hes = {}
    local function Add(bucket, kind)
        for name, e in pairs(bucket) do
            local h = hes[name]
            if not h then h = { name = name, short = e.short, presses = 0, total = 0, late = 0, lost = 0, worst = 0 } hes[name] = h end
            h.presses = h.presses + e.presses
            h.total = h.total + e.total
            h.late = h.late + e.late
            if e.cdDur and e.cdDur > 1.5 then h.lost = h.lost + e.total / e.cdDur end
            if e.worst > h.worst then h.worst, h.worstCause = e.worst, e.worstCause end
            h[kind] = e.total / max(e.presses, 1)
        end
    end
    Add(s.hes.boss, "bossAvg")
    Add(s.hes.trash, "trashAvg")
    local hl = {}
    for _, h in pairs(hes) do h.avg = h.total / max(h.presses, 1) hl[#hl + 1] = h end
    table.sort(hl, function(a, b) return a.presses > b.presses end)
    r.hes = hl

    -- the key points, in two lists: what to work on (r.work) and what
    -- went well (r.good) - three of each at most, the biggest first
    local work, good = {}, {}
    local lc = ClassName(s.class):lower()
    for _, h in ipairs(hl) do
        if #work < 2 and h.presses >= 5 and h.avg >= 0.5 then
            local where = ""
            if h.bossAvg and h.trashAvg then where = format(" (bosses %.1fs, trash %.1fs)", h.bossAvg, h.trashAvg) end
            work[#work + 1] = format("%s sat ready %.1fs on average%s%s.", h.short or h.name, h.avg, where,
                h.lost >= 1 and format(" - about %d casts lost", floor(h.lost + 0.5)) or "")
        end
    end
    for i = 1, min(4, #rows) do
        local a = rows[i]
        if #work < 3 and a.pMin and a.pMin > 0 and a.share >= 0.08 and a.perMin < a.pMin * 0.85 then
            work[#work + 1] = format("%s: %.1f a minute, the other %ss %.1f.", a.name, a.perMin, lc, a.pMin)
        end
    end
    for i = 1, min(6, #takenRows) do
        local t = takenRows[i]
        if #work < 3 and t.avg and t.avg > 0 and t.total > t.avg * 1.6 and t.total > 2000 then
            work[#work + 1] = format("You took %.1fx the %s average from %s.", t.total / t.avg, lc, t.name)
        end
    end
    if #s.myDeaths > 0 then
        local d1 = s.myDeaths[1]
        local kb = KillText(s, d1)
        table.insert(work, math.min(#work + 1, 2), format("You died %d time%s.%s", #s.myDeaths, #s.myDeaths == 1 and "" or "s",
            kb and format(" First on %s, to %s.", d1.where or "?", kb) or ""))
        while #work > 3 do table.remove(work) end
    end
    -- went well: bosses you led your class on, quick buttons, more of an
    -- ability than the others, a clean night
    local tops = {}
    for _, b in ipairs(s.bosses) do
        if b.killed and b.crank == 1 and (b.cof or 0) > 1 then tops[#tops + 1] = b.name end
    end
    if #tops > 0 then
        local list = table.concat(tops, ", ", 1, min(3, #tops))
        if #tops > 3 then list = list .. format(" and %d more", #tops - 3) end
        good[#good + 1] = format("Top %s on %s.", lc, list)
    end
    for _, h in ipairs(hl) do
        if #good < 3 and h.presses >= 20 and h.avg < 0.3 then
            good[#good + 1] = format("%s pressed quickly: %.2fs ready on average.", h.short or h.name, h.avg)
        end
    end
    for i = 1, min(6, #rows) do
        local a = rows[i]
        if #good < 3 and a.pMin and a.pMin > 0 and a.share >= 0.08 and a.perMin > a.pMin * 1.1 then
            good[#good + 1] = format("%s: %.1f a minute, more than the other %ss (%.1f).", a.name, a.perMin, lc, a.pMin)
        end
    end
    if #good < 3 and #s.myDeaths == 0 and #s.bosses > 0 then good[#good + 1] = "No deaths all raid." end
    if #good < 3 and r.rank and r.of >= 8 and r.rank <= math.max(1, floor(r.of * 0.25 + 0.5)) then
        good[#good + 1] = format("%s in the raid on damage (of %d).", Ordinal(r.rank), r.of)
    end
    r.work, r.good = work, good

    -- one-line summaries for the folded sections
    local kills, wipes, bestB, bestP = 0, 0, nil, nil
    for _, b in ipairs(s.bosses) do
        if b.killed then
            kills = kills + 1
            local p = (b.ctop and b.ctop[2] or 0) > 0 and b.dps / b.ctop[2] or nil
            if p and (not bestP or p > bestP) then bestP, bestB = p, b end
        else
            wipes = wipes + 1
        end
    end
    r.kills, r.wipes, r.bestBoss = kills, wipes, bestB
    local gap
    for i = 1, min(6, #rows) do
        local a = rows[i]
        if not gap and a.pMin and a.pMin > 0 and a.share >= 0.08 and a.perMin < a.pMin * 0.85 then gap = a end
    end
    r.abilityGap = gap
    local hard
    for i = 1, min(8, #takenRows) do
        local t = takenRows[i]
        if t.avg and t.avg > 0 and t.total > 2000 and (not hard or t.total / t.avg > hard.total / hard.avg) then hard = t end
    end
    r.hardest = hard

    -- THE FIX LIST: each problem as the DPS it cost, biggest first, three
    -- at most. Hesitation: the casts the waiting cost (lost) times that
    -- ability's average hit. An ability used less often than the rest of
    -- your class: the missing casts a minute times its average hit.
    -- Divided by your active time, so the numbers add up to DPS.
    local act = max(me.act or 0, 1)
    local hitOf = {}
    for _, a in ipairs(rows) do hitOf[a.name] = a.total / max(a.n or 0, 1) end
    local fixes, used = {}, {}
    for _, h in ipairs(hl) do
        local hit = hitOf[h.name]
        if hit and h.lost >= 1 and h.presses >= 5 then
            local dps = h.lost * hit / act
            local where = ""
            if h.bossAvg and h.trashAvg then where = format(" (bosses %.1fs, trash %.1fs)", h.bossAvg, h.trashAvg) end
            fixes[#fixes + 1] = { dps = dps, key = h.name, avg = h.avg,
                text = format("Press %s sooner - it sat ready %.1fs on average%s, about %d casts lost.",
                    h.short or h.name, h.avg, where, floor(h.lost + 0.5)) }
            used[h.name] = true
        end
    end
    for _, a in ipairs(rows) do
        if not NOT_PRESSED[a.name] and a.id ~= 1 and a.pMin and a.pMin > a.perMin * 1.05 and a.share >= 0.04 then
            local dps = (a.pMin - a.perMin) * (act / 60) * (a.total / max(a.n or 0, 1)) / act
            local text = format("More %s - %.1f a minute, the other %ss %.1f.", a.name, a.perMin, lc, a.pMin)
            if used[a.name] then
                -- already on the list for sitting ready: one line, the
                -- bigger cost, and the words say what that cost is
                for _, f in ipairs(fixes) do
                    if f.key == a.name and dps > f.dps then
                        f.dps = dps
                        f.text = text .. format(" It also sat ready %.1fs on average.", f.avg or 0)
                    end
                end
            else
                fixes[#fixes + 1] = { dps = dps, key = a.name, text = text }
            end
        end
    end
    table.sort(fixes, function(a, b) return a.dps > b.dps end)
    local top = {}
    for _, f in ipairs(fixes) do
        if #top < 3 and f.dps >= 5 then top[#top + 1] = f end
    end
    -- dying on a boss outranks everything (its cost cannot be measured)
    local bossDeath
    for _, dd in ipairs(s.myDeaths) do
        if dd.where then
            for _, b in ipairs(s.bosses) do if b.name == dd.where then bossDeath = dd break end end
        end
        if bossDeath then break end
    end
    if bossDeath then
        local kb = KillText(s, bossDeath)
        table.insert(top, 1, { text = format("Stay alive - you died %d time%s. On %s%s.", #s.myDeaths,
            #s.myDeaths == 1 and "" or "s", bossDeath.where,
            kb and (", to " .. kb) or "") })
        while #top > 3 do table.remove(top) end
    end
    r.fixes = top
    r.well = good[1]

    -- against your last time in this raid: the newest earlier run of the
    -- same instance with boss time in it
    local prev = s._demoPrev
    if not prev then
        local st = Store()
        for i = #st, 1, -1 do
            local o = st[i]
            if o ~= s and o.instanceID == s.instanceID and (o.started or 0) < (s.started or 0) then
                local pm = o.players and o.players[o.me]
                if pm and (pm.bossAct or 0) > 0 then
                    prev = { dps = pm.bossDmg / pm.bossAct, at = o.started }
                    break
                end
            end
        end
    end
    r.prev = prev
    return r
end

-- ============================================================
-- THE WINDOW
-- ============================================================
local win, picker
local shownIndex, shownSession

-- WHERE A PAGE IS DRAWN: the summary window, or the settings page's
-- preview. Each target keeps its own pooled rows and tiles and its own
-- width, so the two never take each other's frames.
local function NewTarget(child, scroll, width)
    return { child = child, scroll = scroll, pageW = width or 530,
        rowPool = {}, rowsUsed = 0, tilePool = {}, tilesUsed = 0 }
end
RS.NewTarget = NewTarget
local main = NewTarget()
local cur = main

-- ---- colour words -------------------------------------------------
-- Colours go into the text as codes, never SetTextColor: a theme
-- repaint (_zPaint) puts every font back on its palette colour.
local function Hex(c) return format("|cff%02x%02x%02x", floor(c[1] * 255 + 0.5), floor(c[2] * 255 + 0.5), floor(c[3] * 255 + 0.5)) end
-- good / middling / bad, each a setting (Damage meter > Look); these are
-- the colours the page always had
local GOOD_D, BAD_D, MID_D = { 0.45, 0.85, 0.5 }, { 1, 0.42, 0.35 }, { 1, 0.82, 0.3 }
RS.COLOUR_DEFAULTS = { rsGood = GOOD_D, rsBad = BAD_D, rsMid = MID_D }
local GOOD, BAD, MID = GOOD_D, BAD_D, MID_D
local function ReadColours()
    local d = Cfg()
    local function C(c, dflt)
        if type(c) ~= "table" then return dflt end
        return { c.r or c[1] or dflt[1], c.g or c[2] or dflt[2], c.b or c[3] or dflt[3] }
    end
    GOOD = C(d and d.rsGood, GOOD_D)
    BAD = C(d and d.rsBad, BAD_D)
    MID = C(d and d.rsMid, MID_D)
end
local function Paint(col, text) return col and (Hex(col) .. text .. "|r") or text end

-- a name in its class colour
local function CC(class, text)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if not c then return text end
    if c.colorStr then return "|c" .. c.colorStr .. text .. "|r" end
    if c.r then return Hex({ c.r, c.g, c.b }) .. text .. "|r" end
    return text
end
local function ClassOf(s, name)
    local p = s.players[name]
    return p and p.class
end

-- a rank: green in the top quarter, red in the bottom half
local function RankText(rank, of)
    if not rank or not of or of < 1 then return "-" end
    local col
    if of >= 3 then
        if rank <= math.max(1, floor(of * 0.25 + 0.5)) then col = GOOD
        elseif rank > of * 0.5 then col = BAD end
    end
    return Paint(col, rank .. "/" .. of)
end
-- a share of the best: green 95% and up, red under 80%
local function PctCol(p)
    if p >= 95 then return GOOD elseif p < 80 then return BAD end
    return MID
end

local function SpellIcon(id)
    if id == 1 then return "Interface\\Icons\\INV_Sword_04" end
    return GetSpellTexture and GetSpellTexture(id) or nil
end

-- ---- pooled rows ----------------------------------------------------
-- A page is drawn again when another raid is picked, a section is folded
-- or opened, and when a resize ends. The client never frees a frame, so
-- the table rows (most of what a page is made of) are reused rather
-- than made again each time. A row with a .tip shows it on hover.
local MAX_COLS = 8

local function RowEnter(row)
    if not row.tip then return end
    row.hl:Show()
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    for i, line in ipairs(row.tip) do
        if i == 1 then GameTooltip:AddLine(line, 1, 0.82, 0)
        else GameTooltip:AddLine(line, 0.9, 0.9, 0.9, true) end
    end
    GameTooltip:Show()
end
local function RowLeave(row)
    row.hl:Hide()
    GameTooltip:Hide()
end

local function AcquireRow(card)
    cur.rowsUsed = cur.rowsUsed + 1
    local row = cur.rowPool[cur.rowsUsed]
    if not row then
        row = CreateFrame("Frame", nil, card)
        row.stripe = row:CreateTexture(nil, "BACKGROUND")
        row.stripe:SetAllPoints()
        row.stripe:SetColorTexture(1, 1, 1, 0.035)
        row.hl = row:CreateTexture(nil, "BACKGROUND", nil, 1)
        row.hl:SetAllPoints()
        row.hl:SetColorTexture(1, 1, 1, 0.07)
        row.hl:Hide()
        row.rule = row:CreateTexture(nil, "BORDER")
        row.rule:SetPoint("BOTTOMLEFT")
        row.rule:SetPoint("BOTTOMRIGHT")
        row.rule:SetHeight(1)
        row.rule:SetColorTexture(1, 1, 1, 0.12)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        ZacUI.Look.CropIcon(row.icon)
        row.cells, row.hcells = {}, {}
        row:SetScript("OnEnter", RowEnter)
        row:SetScript("OnLeave", RowLeave)
        cur.rowPool[cur.rowsUsed] = row
    end
    row:SetParent(card)
    row:ClearAllPoints()
    row.tip = nil
    row.hl:Hide()
    row:EnableMouse(false)
    row:Show()
    return row
end

local function Cell(row, i, header)
    -- headers and body text keep their own font strings, each made at
    -- its own size once, so a reused row never has to change a font
    local list = header and row.hcells or row.cells
    local fs = list[i]
    if not fs then
        fs = UI.Font(row, header and UI.F.SMALL or (UI.F.LABEL + 1),
            { cat = "text", key = header and "gray" or "normal" })
        fs:SetWordWrap(false)
        list[i] = fs
    end
    local other = header and row.cells[i] or row.hcells[i]
    if other then other:Hide() end
    fs:ClearAllPoints()
    fs:Show()
    return fs
end

-- the width the page has for a card's insides
local function Inner() return cur.pageW - 2 * UI.M.MARGIN - 2 * UI.M.CONTROL_X end

-- A table: columns laid out for a 480px card and spread when the window
-- is wider. cells may carry .icon (a texture for the first column) and
-- .tip (tooltip lines, the first one the title).
local function Table(L, cols, rows)
    local card = L.current
    local w = Inner()
    local k = math.min(1.7, math.max(1, w / 480))
    local function Line(cells, header, n)
        local row = AcquireRow(card)
        local h = header and 17 or 20
        row:SetSize(w, h)
        row.stripe:SetShown(not header and n % 2 == 0)
        row.rule:SetShown(header and true or false)
        if not header and cells.tip then
            row.tip = cells.tip
            row:EnableMouse(true)
        end
        local iconW = 0
        if not header and cells.icon then
            row.icon:SetTexture(cells.icon)
            row.icon:SetSize(16, 16)
            row.icon:ClearAllPoints()
            row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)
            row.icon:Show()
            iconW = 21
        else
            row.icon:Hide()
        end
        for i = 1, MAX_COLS do
            local c = cols[i]
            if c then
                local fs = Cell(row, i, header)
                fs:SetText(cells[i] or "")
                local x, cw = c.x * k, c.w * k
                if i == 1 then x, cw = x + iconW, cw - iconW end
                if c.right then
                    fs:SetJustifyH("RIGHT")
                    fs:SetPoint("RIGHT", row, "LEFT", x + cw, 0)
                    fs:SetWidth(0)
                else
                    fs:SetJustifyH("LEFT")
                    fs:SetPoint("LEFT", row, "LEFT", x + (i == 1 and 2 or 0), 0)
                    fs:SetWidth(cw)
                end
            else
                if row.cells[i] then row.cells[i]:Hide() end
                if row.hcells[i] then row.hcells[i]:Hide() end
            end
        end
        L:Row(row, h + (header and 2 or 0))
    end
    local head = {}
    for i, c in ipairs(cols) do head[i] = c.title end
    Line(head, true, 0)
    for n, r in ipairs(rows) do Line(r, false, n) end
end

-- ---- stat tiles -----------------------------------------------------
-- { value, label, sub }: the number big, what it is under it, and one
-- line of context at the bottom
local TILE_H = 62
local function Tiles(L, tiles)
    local card = L.current
    local w = Inner()
    local gap = 8
    local tw = (w - gap * (#tiles - 1)) / #tiles
    local host = CreateFrame("Frame", nil, card)
    host:SetSize(w, TILE_H)
    for i, t in ipairs(tiles) do
        cur.tilesUsed = cur.tilesUsed + 1
        local tile = cur.tilePool[cur.tilesUsed]
        if not tile then
            tile = CreateFrame("Frame", nil, host)
            tile.bg = tile:CreateTexture(nil, "BACKGROUND")
            tile.bg:SetAllPoints()
            tile.bg:SetColorTexture(1, 1, 1, 0.045)
            tile.value = UI.Font(tile, 20, { cat = "text", key = "normal", justify = "CENTER" })
            tile.value:SetPoint("TOP", 0, -7)
            tile.label = UI.Font(tile, UI.F.SMALL, { cat = "text", key = "gray", justify = "CENTER" })
            tile.label:SetPoint("TOP", tile.value, "BOTTOM", 0, -3)
            tile.sub = UI.Font(tile, UI.F.SMALL, { cat = "text", key = "normal", justify = "CENTER" })
            tile.sub:SetPoint("BOTTOM", 0, 6)
            tile.sub:SetWordWrap(false)
            cur.tilePool[cur.tilesUsed] = tile
        end
        tile:SetParent(host)
        tile:ClearAllPoints()
        tile:SetPoint("TOPLEFT", host, "TOPLEFT", (i - 1) * (tw + gap), 0)
        tile:SetSize(tw, TILE_H)
        tile.sub:SetWidth(tw - 8)
        tile.value:SetText(t[1])
        tile.label:SetText(t[2])
        tile.sub:SetText(t[3] or "")
        tile:Show()
    end
    L:Row(host, TILE_H + 8)
end

-- a line of text in the card: white, wrapping, with a small bullet in
-- the accent colour (or the one given: green for went well, red for
-- work on)
local function Line(L, text, bullet, gray)
    local card = L.current
    local x = UI.M.CONTROL_X + (bullet and 12 or 0)
    local fs = UI.Font(card, gray and UI.F.SMALL or (UI.F.LABEL + 1), { text = text, cat = "text",
        key = gray and "gray" or "normal", width = Inner() - (bullet and 12 or 0) })
    fs:SetPoint("TOPLEFT", card, "TOPLEFT", x, card._y)
    if bullet then
        local dot = card:CreateTexture(nil, "ARTWORK")
        dot:SetSize(5, 5)
        if type(bullet) == "table" then
            dot:SetColorTexture(bullet[1], bullet[2], bullet[3], 1)
        else
            local a = ns.GetColor and ns.GetColor("ui", "accent")
            if a then dot:SetColorTexture(a.r, a.g, a.b, 1) else dot:SetColorTexture(0.85, 0.65, 0.25, 1) end
        end
        dot:SetPoint("TOPLEFT", card, "TOPLEFT", UI.M.CONTROL_X + 2, card._y - 5)
    end
    card._y = card._y - math.max(14, fs:GetStringHeight()) - 6
end

-- a small gray heading inside a card
local function SubHead(L, text)
    local card = L.current
    local fs = UI.Font(card, UI.F.SMALL, { text = text, cat = "text", key = "gray" })
    fs:SetPoint("TOPLEFT", card, "TOPLEFT", UI.M.CONTROL_X, card._y)
    card._y = card._y - 16
end

local function ClearChild()
    local child = cur.child
    for _, k in ipairs({ child:GetChildren() }) do k:Hide() k:SetParent(nil) end
    for _, rg in ipairs({ child:GetRegions() }) do rg:Hide() end
    cur.rowsUsed, cur.tilesUsed = 0, 0
end

-- ---- folding sections -------------------------------------------------
-- The detail tables fold: the title row always shows, with a one-line
-- summary beside it, and a click on it opens or folds the table. What is
-- open is remembered (raidSummaryOpen) for every raid.
local Relayout   -- forward: a click redraws the page
local function IsOpen(key, dflt)
    local d = Cfg()
    local o = d and d.raidSummaryOpen
    if type(o) == "table" and o[key] ~= nil then return o[key] end
    return dflt
end
local function Section(L, key, title, summary, dflt, body)
    local open = IsOpen(key, dflt)
    local card = L:Card(title)
    local hb = CreateFrame("Button", nil, card)
    hb:SetPoint("TOPLEFT", card, "TOPLEFT", 0, 0)
    hb:SetPoint("TOPRIGHT", card, "TOPRIGHT", 0, 0)
    hb:SetHeight(30)
    local hl = hb:CreateTexture(nil, "BACKGROUND")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.04)
    hl:Hide()
    local act = UI.Font(hb, UI.F.SMALL, { text = open and "hide" or "show", cat = "text", key = "gray", justify = "RIGHT" })
    act:SetPoint("TOPRIGHT", hb, "TOPRIGHT", -UI.M.CARD_PAD, -11)
    if summary and summary ~= "" and card._zTitle then
        local sum = UI.Font(hb, UI.F.SMALL, { text = summary, cat = "text", key = "gray" })
        sum:SetPoint("LEFT", card._zTitle, "RIGHT", 12, 0)
        sum:SetPoint("RIGHT", act, "LEFT", -10, 0)
        sum:SetJustifyH("LEFT")
        sum:SetWordWrap(false)
    end
    hb:SetScript("OnEnter", function() hl:Show() end)
    hb:SetScript("OnLeave", function() hl:Hide() end)
    hb:SetScript("OnClick", function()
        local d = Cfg()
        if d then
            if type(d.raidSummaryOpen) ~= "table" then d.raidSummaryOpen = {} end
            d.raidSummaryOpen[key] = not open
        end
        if Relayout then Relayout() end
    end)
    if open then
        body()
    else
        card._y = -24
    end
    L:EndCard()
end

-- target: where to draw (the window when nil); topOnly: the night's
-- card alone, without the folding tables (the settings preview)
local function Fill(s, target, topOnly)
    cur = target or main
    ReadColours()
    if cur == main then
        shownSession = s
        cur.pageW = max(400, ((win and win:GetWidth()) or 560) - 26)
    end
    local child = cur.child
    child:SetWidth(cur.pageW)
    ClearChild()
    local L = ns.ConfigLayout.New(child, -6)
    local r = RS.Build(s)
    local cname = ClassName(s.class)
    local lc = cname:lower()
    local when = date and date("%a %d %b %H:%M", s.started) or ""
    L:Header(s.raid .. (s.done and "" or "  (in progress)"),
        format("%s  -  %s  -  %s (bosses %s)  -  %d kill%s%s", when, CC(s.class, cname),
            Clock(s.bossTime + s.trashTime), Clock(s.bossTime), r.kills, r.kills == 1 and "" or "s",
            r.wipes > 0 and format(", %d wipe%s", r.wipes, r.wipes == 1 and "" or "s") or ""))

    -- THE NIGHT: four numbers, one sentence, the fixes - the whole point
    -- of the page in one card; everything under it is folded detail
    L:Card(CC(s.class, s.me or "You"))
    local pct = r.cbest and r.cbest.name ~= s.me and floor(r.bossDps / max(r.cbest.bossDps, 1) * 100 + 0.5) or nil
    local dn = #s.myDeaths
    local d1 = s.myDeaths[1]
    local trend
    if r.prev and (r.prev.dps or 0) > 0 then
        trend = floor((r.bossDps / r.prev.dps - 1) * 100 + 0.5)
    end
    local third
    if trend then
        third = { Paint(trend > 0 and GOOD or (trend < 0 and BAD or nil), (trend > 0 and "+" or "") .. trend .. "%"),
            "vs last time", format("%s then%s", Num(r.prev.dps),
                (date and r.prev.at) and (" (" .. date("%d %b", r.prev.at) .. ")") or "") }
    else
        third = { RankText(r.rank, r.of), "Raid rank", Num(r.dps) .. " DPS overall" }
    end
    Tiles(L, {
        { Num(r.bossDps), "Boss DPS",
            pct and Paint(PctCol(pct), pct .. "% of the best " .. lc) or Paint(GOOD, "best " .. lc) },
        { RankText(r.crank, r.cof), cname .. " rank", "on bosses" },
        third,
        { dn == 0 and Paint(GOOD, "0") or Paint(BAD, tostring(dn)), "Deaths",
            dn == 0 and Paint(GOOD, "clean raid") or ((d1 and d1.where) or "") },
    })
    -- the one sentence
    local say
    if r.cbest and r.cbest.name ~= s.me then
        say = format("%s of %d %ss on bosses, %d%% of %s.", Ordinal(r.crank), r.cof, lc, pct or 0,
            CC(s.class, r.cbest.name))
    else
        say = format("The best %s on bosses.", lc)
    end
    if #r.fixes > 0 and r.fixes[1].dps then
        local sum = 0
        for _, f in ipairs(r.fixes) do sum = sum + (f.dps or 0) end
        say = say .. format("  The fixes below are worth about %s DPS.", Paint(GOOD, "+" .. floor(sum + 0.5)))
    end
    Line(L, say)
    L:Gap(2)
    if #r.fixes > 0 then
        SubHead(L, "FIX NEXT RAID")
        for _, f in ipairs(r.fixes) do
            Line(L, f.text .. (f.dps and ("  " .. Paint(GOOD, format("+%d DPS", floor(f.dps + 0.5)))) or ""), BAD)
        end
    else
        SubHead(L, "FIX NEXT RAID")
        Line(L, "Nothing that cost you real damage.", GOOD)
    end
    if r.well then
        L:Gap(2)
        Line(L, r.well, GOOD)
    end
    Line(L, "DPS figures are estimates: lost casts times your average hit with that ability.", nil, true)
    L:EndCard()
    if topOnly then
        for i = cur.rowsUsed + 1, #cur.rowPool do cur.rowPool[i]:Hide() end
        for i = cur.tilesUsed + 1, #cur.tilePool do cur.tilePool[i]:Hide() end
        child:SetHeight(L:Height())
        cur = main
        return
    end
    -- BOSSES (open unless folded): hover a row for who topped it
    if #s.bosses > 0 then
        local sum = format("%d kill%s%s", r.kills, r.kills == 1 and "" or "s",
            r.wipes > 0 and format(", %d wipe%s", r.wipes, r.wipes == 1 and "" or "s") or "")
        if r.bestBoss then
            sum = sum .. format("  -  best: %s (%s)", r.bestBoss.name, RankText(r.bestBoss.crank, r.bestBoss.cof))
        end
        Section(L, "bosses", "Bosses", sum, false, function()
            local rows = {}
            for _, b in ipairs(s.bosses) do
                local name = b.killed and b.name or (b.name .. "  " .. Paint(BAD, "wipe"))
                local vs = "-"
                if b.ctop and b.ctop[2] > 0 then
                    local p = floor(b.dps / b.ctop[2] * 100 + 0.5)
                    vs = Paint(b.killed and PctCol(p) or nil, p .. "%")
                end
                local tip = { b.name .. (b.killed and "" or "  (wipe)"),
                    format("%s  -  you %s DPS", Clock(b.dur), Num(b.dps)),
                    format("%s: %s of %d    Raid: %s of %d", cname, b.crank or "-", b.cof or 0, b.rank or "-", b.of or 0) }
                if b.ctop then tip[#tip + 1] = format("Best %s: %s  %s", lc, CC(s.class, b.ctop[1]), Num(b.ctop[2])) end
                if b.top then tip[#tip + 1] = format("Top of the raid: %s  %s", CC(b.top[3], b.top[1]), Num(b.top[2])) end
                rows[#rows + 1] = { name, Clock(b.dur), Num(b.dps), vs, RankText(b.crank, b.cof), RankText(b.rank, b.of),
                    b.ctop and CC(s.class, b.ctop[1]) or "-", tip = tip }
            end
            Table(L, {
                { title = "Boss", x = 0, w = 140 }, { title = "Time", x = 140, w = 50, right = true },
                { title = "DPS", x = 192, w = 48, right = true }, { title = "vs best", x = 242, w = 50, right = true },
                { title = cname, x = 294, w = 46, right = true }, { title = "Raid", x = 342, w = 40, right = true },
                { title = "Best " .. lc, x = 394, w = 86 },
            }, rows)
            Line(L, "vs best: your DPS as a share of the best " .. lc .. " on that boss. Hover a boss for more.", nil, true)
        end)
    end

    -- ABILITIES next to the rest of your class
    if #r.abilities > 0 then
        local g = r.abilityGap
        local sum = g and format("biggest gap: %s %.1f/min vs %.1f", g.name, g.perMin, g.pMin)
            or (r.peers > 0 and ("in line with the other " .. lc .. "s") or "")
        Section(L, "abilities", "Your abilities", sum, false, function()
            local rows = {}
            for i = 1, min(12, #r.abilities) do
                local a = r.abilities[i]
                local pm = format("%.1f", a.perMin)
                if a.pMin and a.pMin > 0 then
                    pm = Paint((a.perMin < a.pMin * 0.85) and BAD or (a.perMin > a.pMin * 1.05 and GOOD or nil), pm)
                end
                local tip = { a.name, format("%s damage, %d%% of yours", Num(a.total), floor(a.share * 100 + 0.5)),
                    format("%.1f a minute, %d%% crits", a.perMin, floor(a.crit * 100 + 0.5)) }
                if a.pMin then
                    tip[#tip + 1] = format("The other %ss: %d%% of their damage, %.1f a minute", lc,
                        floor((a.pShare or 0) * 100 + 0.5), a.pMin)
                end
                rows[#rows + 1] = { a.name, Num(a.total),
                    format("%d%%", floor(a.share * 100 + 0.5)),
                    a.pShare and Paint({ 0.6, 0.6, 0.6 }, format("%d%%", floor(a.pShare * 100 + 0.5))) or "-",
                    pm, a.pMin and Paint({ 0.6, 0.6, 0.6 }, format("%.1f", a.pMin)) or "-",
                    format("%d%%", floor(a.crit * 100 + 0.5)),
                    icon = SpellIcon(a.id), tip = tip }
            end
            Table(L, {
                { title = "Ability", x = 0, w = 150 }, { title = "Damage", x = 150, w = 60, right = true },
                { title = "Share", x = 215, w = 45, right = true }, { title = lc .. "s", x = 262, w = 45, right = true },
                { title = "Per min", x = 310, w = 55, right = true }, { title = lc .. "s", x = 368, w = 45, right = true },
                { title = "Crit", x = 418, w = 40, right = true },
            }, rows)
            Line(L, format("Gray: the other %ss' average%s.", lc, r.peers > 0 and format(" (%d of them)", r.peers) or ""), nil, true)
        end)
    end

    -- WHAT HIT YOU, next to the class average
    if #r.taken > 0 then
        local h = r.hardest
        local sum = h and format("most over the %s average: %s %.1fx", lc, h.name, h.total / h.avg) or ""
        Section(L, "taken", "What hit you hardest", sum, false, function()
            local rows = {}
            for i = 1, min(10, #r.taken) do
                local t = r.taken[i]
                local vs = "-"
                if t.avg and t.avg > 0 then
                    local x = t.total / t.avg
                    vs = Paint((x > 1.6) and BAD or (x < 0.8 and GOOD or nil), format("%.1fx", x))
                end
                rows[#rows + 1] = { t.name, Num(t.total), t.avg and Num(t.avg) or "-", vs, icon = SpellIcon(t.id) }
            end
            Table(L, {
                { title = "Ability", x = 0, w = 200 }, { title = "You", x = 200, w = 70, right = true },
                { title = cname .. " avg", x = 275, w = 80, right = true },
                { title = "vs avg", x = 360, w = 50, right = true },
            }, rows)
        end)
    end

    -- YOUR DEATHS: each one as the meter's death recap words it
    if #s.myDeaths > 0 then
        local d1 = s.myDeaths[#s.myDeaths]
        local kb = KillText(s, d1)
        local sum = format("%d - last: %s%s", #s.myDeaths, d1.where or "?", kb and (", to " .. kb) or "")
        Section(L, "deaths", "Your deaths", sum, false, function()
            for _, d in ipairs(s.myDeaths) do
                local where = d.where or "?"
                if d.at then where = where .. format(", %d:%02d in", floor(d.at / 60), d.at % 60) end
                Line(L, Paint(BAD, where) .. ":  " .. RS.DeathText(s, d), BAD)
            end
            Line(L, "The killing blow, then the hits and heals before it, newest first. The meter's Deaths display shows the full log.", nil, true)
        end)
    end

    -- HESITATION (a warrior's night): how long the big buttons sat ready
    if #r.hes > 0 then
        local parts = {}
        for i = 1, min(3, #r.hes) do
            local h = r.hes[i]
            parts[#parts + 1] = format("%s %s", h.short or h.name,
                Paint(h.avg >= 0.8 and BAD or (h.avg < 0.3 and GOOD or nil), format("%.2fs", h.avg)))
        end
        Section(L, "hesitation", "Hesitation", table.concat(parts, "   ") .. "  ready on average", false, function()
            local rows = {}
            for _, h in ipairs(r.hes) do
                local avg = format("%.2fs", h.avg)
                avg = Paint(h.avg >= 0.8 and BAD or (h.avg < 0.3 and GOOD or nil), avg)
                local tip = { h.name, format("%d casts, %.2fs ready on average", h.presses, h.avg) }
                if h.worst and h.worst > 0 then
                    tip[#tip + 1] = format("Longest: %.1fs%s", h.worst, h.worstCause and (" (" .. h.worstCause .. ")") or "")
                end
                rows[#rows + 1] = { h.short or h.name, tostring(h.presses), avg,
                    h.bossAvg and format("%.2fs", h.bossAvg) or "-", h.trashAvg and format("%.2fs", h.trashAvg) or "-",
                    format("%d%%", floor(h.late / max(h.presses, 1) * 100 + 0.5)),
                    h.lost >= 0.5 and format("%.1f", h.lost) or "-",
                    icon = GetSpellTexture and h.name and GetSpellTexture(h.name) or nil, tip = tip }
            end
            Table(L, {
                { title = "Ability", x = 0, w = 110 }, { title = "Casts", x = 110, w = 45, right = true },
                { title = "Avg", x = 160, w = 50, right = true }, { title = "Bosses", x = 215, w = 50, right = true },
                { title = "Trash", x = 270, w = 50, right = true }, { title = "Late", x = 325, w = 40, right = true },
                { title = "Lost", x = 370, w = 40, right = true },
            }, rows)
            Line(L, "Avg: how long it sat ready before you pressed it. Late: share of presses held too long. Lost: casts the waiting cost.", nil, true)
            if (s.hes.wrongOrder or 0) > 0 then
                Line(L, format("Whirlwind over a ready Bloodthirst on too few mobs for it: %s.",
                    Paint(s.hes.wrongOrder >= 5 and BAD or MID, s.hes.wrongOrder .. (s.hes.wrongOrder == 1 and " time" or " times"))))
            end
        end)
    end

    -- hide pooled rows and tiles this page did not use
    for i = cur.rowsUsed + 1, #cur.rowPool do cur.rowPool[i]:Hide() end
    for i = cur.tilesUsed + 1, #cur.tilePool do cur.tilePool[i]:Hide() end

    local h = L:Height()
    child:SetHeight(h)
    if cur.scroll then cur.scroll:Recalculate(h) end
    cur = main
end
RS.Fill = Fill

-- the page again at the window's new width, once the drag has ended
-- (and when a section is folded or opened)
Relayout = function()
    if shownSession and win and win:IsShown() then Fill(shownSession) end
end

local function Build()
    if win then return end
    -- (2026-11-08) the popup shell (UIF_Dialogs UI.Popup)
    win = UI.Popup("ZacUIRaidSummary", 600, 640, "Raid summary")
    -- not on the Escape list: Escape closes every window on it at once,
    -- and the end of a raid is all loot windows and Escape - the summary
    -- went with them. Its X and /zui raid close it.
    for i = #UISpecialFrames, 1, -1 do
        if UISpecialFrames[i] == "ZacUIRaidSummary" then table.remove(UISpecialFrames, i) end
    end
    win._zOnMoved = function()
        local p = { win:GetPoint(1) }
        local d = Cfg()
        if d then d.raidSummaryPos = { p[1], p[4], p[5] } end
    end
    local d = Cfg()
    if d and type(d.raidSummaryPos) == "table" then
        win:ClearAllPoints()
        win:SetPoint(d.raidSummaryPos[1] or "CENTER", UIParent, d.raidSummaryPos[1] or "CENTER",
            d.raidSummaryPos[2] or 0, d.raidSummaryPos[3] or 0)
    end
    if d and type(d.raidSummarySize) == "table" then
        win:SetSize(max(520, d.raidSummarySize[1] or 600), max(380, d.raidSummarySize[2] or 640))
    end
    if UI.AttachResizeGrip then
        UI.AttachResizeGrip(win, { minW = 520, minH = 380, maxW = 1100, maxH = 1300,
            onResizeStopped = function(f)
                local dd = Cfg()
                if dd then dd.raidSummarySize = { floor(f:GetWidth() + 0.5), floor(f:GetHeight() + 0.5) } end
                -- the top-left corner stays put; keep the saved spot right
                if win._zOnMoved then win._zOnMoved() end
                Relayout()
            end })
    end
    picker = UI.SettingsBuild(UI.Dropdown, win, { width = 260,
        items = function()
            local out = {}
            local st = Store()
            for i = #st, 1, -1 do
                local s = st[i]
                out[#out + 1] = { text = format("%s  %s", s.raid or "?", date and date("%d %b %H:%M", s.started or 0) or ""), value = i }
            end
            return out
        end,
        selectedValue = function() return shownIndex end,
        selected = function()
            local s = Store()[shownIndex or 0]
            return s and format("%s  %s", s.raid or "?", date and date("%d %b %H:%M", s.started or 0) or "") or "No raids yet"
        end,
        onSelect = function(v) RS.Open(v) end })
    picker:SetPoint("TOPLEFT", win, "TOPLEFT", win.pad, -win.headerHeight)
    local sa, ch, bar = UI.ScrollArea(win, { style = "settings" })
    sa:SetPoint("TOPLEFT", win, "TOPLEFT", 4, -(win.headerHeight + 42))
    sa:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -22, 18)
    if sa.SetClipsChildren then sa:SetClipsChildren(true) end
    bar:SetPoint("TOPLEFT", sa, "TOPRIGHT", 2, 0)
    bar:SetPoint("BOTTOMLEFT", sa, "BOTTOMRIGHT", 2, 0)
    ch:SetWidth(574)
    main.scroll, main.child = sa, ch
end

-- open raid `index` in the history (the latest when nil)
function RS.Open(index)
    local st = Store()
    if #st == 0 then
        Print("Raid summary: nothing yet - it fills in as you raid (the meter has to be on). /zui raid demo shows an example.")
        return
    end
    index = tonumber(index) or #st
    if index < 1 or index > #st then index = #st end
    Build()
    shownIndex = index
    if picker and picker.SetText then
        local s = st[index]
        picker:SetText(format("%s  %s", s.raid or "?", date and date("%d %b %H:%M", s.started or 0) or ""))
    end
    UI.OpenWindow(win)
    Fill(st[index])
end

function RS.Toggle(index)
    if win and win:IsShown() then UI.CloseWindow(win) return end
    RS.Open(index)
end

-- ============================================================
-- EXAMPLE - a made-up Naxxramas night on a warrior, to see the page
-- without raiding (/zui raid demo, or the button on the Meter page).
-- Built fresh each time and never stored.
-- ============================================================
local function DemoSession()
    local me = UnitName("player") or "You"
    local now = time()
    local s = {
        raid = "Naxxramas", instanceID = 533, started = now - 3 * 3600 - 600, last = now,
        class = "WARRIOR", me = me, done = true, doneAt = now,
        bossTime = 4260, trashTime = 6180, segments = 64,
        players = {}, bosses = {}, taken = {}, deaths = {}, myDeaths = {},
        names = { [23894] = "Bloodthirst", [1680] = "Whirlwind", [25286] = "Heroic Strike",
            [20662] = "Execute", [20569] = "Cleave", [12721] = "Deep Wounds", [25584] = "Windfury Attack",
            [7373] = "Hamstring", [28308] = "Hateful Strike", [27808] = "Frost Blast",
            [29371] = "Eruption", [28796] = "Poison Bolt Volley", [26613] = "Unbalancing Strike",
            [28522] = "Icebolt", [27810] = "Shadow Fissure", [29213] = "Curse of the Plaguebringer" },
        hes = { boss = {}, trash = {}, wrongOrder = 3, pulls = 58 },
        _demoPrev = { dps = 1218, at = now - 7 * 86400 },
    }
    -- spell mix of a warrior: { id, share of damage, hits a minute, crit }
    local function Spells(dmg, act, mix)
        local out = {}
        for _, m in ipairs(mix) do
            local n = floor(m[3] * act / 60 + 0.5)
            out[m[1]] = { t = floor(dmg * m[2]), n = n, c = floor(n * m[4]) }
        end
        return out
    end
    local MINE = { { 1, 0.38, 38.0, 0.31 }, { 23894, 0.20, 9.2, 0.33 }, { 1680, 0.10, 4.1, 0.32 },
        { 25286, 0.13, 7.5, 0.34 }, { 20662, 0.07, 2.4, 0.36 }, { 25584, 0.06, 3.3, 0.30 },
        { 12721, 0.04, 6.0, 0 }, { 20569, 0.02, 1.4, 0.33 } }
    local PEER = { { 1, 0.36, 37.5, 0.31 }, { 23894, 0.21, 10.6, 0.33 }, { 1680, 0.12, 5.6, 0.32 },
        { 25286, 0.12, 7.0, 0.33 }, { 20662, 0.08, 2.6, 0.36 }, { 25584, 0.06, 3.3, 0.30 },
        { 12721, 0.04, 6.2, 0 }, { 20569, 0.01, 0.8, 0.33 } }
    local roster = {
        { me, "WARRIOR", 1080, 1265, MINE },
        { "Brakka", "WARRIOR", 1190, 1402, PEER }, { "Tovren", "WARRIOR", 1120, 1318, PEER },
        { "Holgrim", "WARRIOR", 1015, 1188, PEER }, { "Sefa", "WARRIOR", 940, 1102, PEER },
        { "Quillan", "ROGUE", 1150, 1290 }, { "Nyssa", "ROGUE", 1060, 1235 },
        { "Orrin", "MAGE", 1210, 1380 }, { "Velka", "MAGE", 1105, 1260 },
        { "Durnik", "HUNTER", 990, 1120 }, { "Mirel", "WARLOCK", 1040, 1210 },
    }
    local act, bossAct = 8900, 3980
    for _, r in ipairs(roster) do
        local p = { class = r[2], dmg = r[3] * act, act = act, bossDmg = r[4] * bossAct, bossAct = bossAct }
        if r[5] then p.spells = Spells(p.dmg, act, r[5]) end
        s.players[r[1]] = p
    end
    -- what hit the warriors
    local function Hit(name, t) s.taken[name] = t end
    Hit(me, { [1] = 182000, [28308] = 0, [27808] = 31000, [29371] = 14200, [28796] = 9800,
        [26613] = 0, [28522] = 18400, [27810] = 7100, [29213] = 6900 })
    Hit("Brakka", { [1] = 176000, [27808] = 30500, [29371] = 0, [28796] = 6100, [28522] = 9200, [29213] = 4100 })
    Hit("Tovren", { [1] = 171000, [27808] = 29800, [29371] = 4500, [28796] = 5800, [28522] = 10100, [29213] = 3900 })
    Hit("Holgrim", { [1] = 190000, [27808] = 31200, [29371] = 0, [28796] = 6600, [28522] = 8800, [29213] = 4400 })
    Hit("Sefa", { [1] = 168000, [27808] = 30100, [29371] = 3900, [28796] = 5200, [28522] = 9600, [29213] = 4000 })
    for _, t in pairs(s.taken) do for id, v in pairs(t) do if v == 0 then t[id] = nil end end end
    s.myDeaths = { { where = "Heigan the Unclean", at = 104, spell = 29371, src = "Heigan the Unclean", amt = 4210,
        over = 1350, sure = true, seen = true, before = { { dmg = true, spell = 1, src = "Heigan the Unclean", amt = 1920 },
        { dmg = false, spell = 25315, src = "Pria", amt = 310 }, { dmg = true, spell = 1, src = "Heigan the Unclean", amt = 3050 } } } }
    s.names[25315] = "Renew"
    s.deaths[me] = 1
    local function Boss(name, dur, dps, rank, crank, top, ctop, wipe)
        s.bosses[#s.bosses + 1] = { name = name, killed = not wipe, dur = dur, dps = dps,
            rank = rank, of = 38, crank = crank, cof = 5, top = { top[1], top[2], top[3] }, ctop = ctop }
    end
    Boss("Anub'Rekhan", 74, 1520, 6, 3, { "Orrin", 1710, "MAGE" }, { "Brakka", 1640 })
    Boss("Grand Widow Faerlina", 98, 1380, 9, 3, { "Orrin", 1590, "MAGE" }, { "Tovren", 1510 })
    Boss("Maexxna", 121, 1295, 11, 4, { "Quillan", 1500, "ROGUE" }, { "Brakka", 1470 })
    Boss("Patchwerk", 162, 1410, 7, 2, { "Brakka", 1560, "WARRIOR" }, { "Brakka", 1560 })
    Boss("Grobbulus", 133, 1240, 12, 3, { "Velka", 1420, "MAGE" }, { "Tovren", 1380 })
    Boss("Gluth", 110, 1330, 9, 3, { "Orrin", 1505, "MAGE" }, { "Brakka", 1460 })
    Boss("Heigan the Unclean", 158, 610, 31, 5, { "Durnik", 1210, "HUNTER" }, { "Holgrim", 1105 }, true)
    Boss("Heigan the Unclean", 141, 1105, 10, 2, { "Mirel", 1290, "WARLOCK" }, { "Brakka", 1180 })
    Boss("Loatheb", 196, 1360, 8, 3, { "Orrin", 1530, "MAGE" }, { "Brakka", 1490 })
    Boss("Instructor Razuvious", 86, 1190, 13, 4, { "Quillan", 1420, "ROGUE" }, { "Tovren", 1350 })
    Boss("Gothik the Harvester", 228, 880, 14, 3, { "Velka", 1080, "MAGE" }, { "Brakka", 990 })
    Boss("The Four Horsemen", 254, 1150, 10, 3, { "Orrin", 1340, "MAGE" }, { "Brakka", 1290 })
    Boss("Noth the Plaguebringer", 92, 1280, 9, 3, { "Quillan", 1470, "ROGUE" }, { "Tovren", 1400 })
    Boss("Thaddius", 141, 1460, 6, 2, { "Brakka", 1580, "WARRIOR" }, { "Brakka", 1580 })
    Boss("Sapphiron", 186, 1225, 11, 4, { "Orrin", 1430, "MAGE" }, { "Brakka", 1350 })
    Boss("Kel'Thuzad", 318, 1290, 9, 3, { "Orrin", 1495, "MAGE" }, { "Brakka", 1420 })
    -- hesitation: presses, seconds sat ready in all, late presses, cooldown
    local function Hes(bucket, name, short, presses, total, late, worst, cause, cd)
        bucket[name] = { short = short, presses = presses, total = total, late = late, wasted = 0,
            worst = worst, worstCause = cause, cdDur = cd }
    end
    Hes(s.hes.boss, "Bloodthirst", "BT", 610, 427, 96, 4.8, "HS queued", 6)
    Hes(s.hes.trash, "Bloodthirst", "BT", 702, 302, 61, 3.1, "no rage", 6)
    Hes(s.hes.boss, "Whirlwind", "WW", 268, 241, 52, 5.6, "other buttons", 10)
    Hes(s.hes.trash, "Whirlwind", "WW", 371, 126, 22, 2.9, "no rage", 10)
    Hes(s.hes.boss, "Execute", "EXE", 145, 29, 6, 1.4, "HS queued", 0)
    Hes(s.hes.trash, "Overpower", "OP", 34, 41, 11, 2.6, "other buttons", 5)
    return s
end

RS.DemoSession = DemoSession

function RS.Demo()
    Build()
    shownIndex = nil
    if picker and picker.SetText then picker:SetText("Example raid - made-up numbers") end
    UI.OpenWindow(win)
    Fill(DemoSession())
end

-- after the last boss: a moment later, out of combat
local waitFrame
function RS.ShowSoon(s)
    Print(format("Raid summary for %s is ready - /zui raid opens it again any time.", s.raid or "the raid"))
    local d = Cfg()
    if not (d and d.raidSummaryShow) then return end
    C_Timer.After(4, function()
        if not InCombatLockdown() then RS.Open() return end
        waitFrame = waitFrame or CreateFrame("Frame")
        waitFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        waitFrame:SetScript("OnEvent", function(self)
            self:UnregisterAllEvents()
            RS.Open()
        end)
    end)
end

-- ============================================================
-- HOOKS - the meter's segment close, and the hesitation pulls
-- ============================================================
-- The meter closes a segment the moment a fight ends - the busiest frame
-- there is. The summary's work waits a second and is never done in
-- combat: segments queue up and are folded in one per frame once the
-- player is out of combat.
local pending = {}
local queueFrame = CreateFrame("Frame")
local Drain
local function DrainSoon()
    if InCombatLockdown() then
        queueFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    C_Timer.After(1, Drain)
end
Drain = function()
    if InCombatLockdown() then DrainSoon() return end
    local p = table.remove(pending, 1)
    if p then
        local ok, err = pcall(RS.OnSegment, p.combat, p.name, p.id)
        if not ok and ns.Debug then ns.Debug("raid summary: " .. tostring(err)) end
    end
    if #pending > 0 then C_Timer.After(0, Drain) end
end
queueFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    C_Timer.After(1, Drain)
end)

local prevEnd = Meter.OnCombatEnd
Meter.OnCombatEnd = function(combat, kept, ...)
    if prevEnd then prevEnd(combat, kept, ...) end
    local d = Cfg()
    if not (d and d.raidSummary) or not combat or combat.overall then return end
    -- a fight too short for the meter to keep is in no list and not in
    -- the overall; the summary leaves it out too
    if kept == false then return end
    -- only segments inside a raid instance are wanted; asked now, while
    -- the player is still where the fight was, and remembered for when
    -- the segment is folded in
    local name, itype, _, _, _, _, _, id = GetInstanceInfo()
    if itype ~= "raid" then return end
    pending[#pending + 1] = { combat = combat, name = name, id = id }
    if #pending == 1 then DrainSoon() end
end

local function HookHesitation()
    local H = ns.Hesitation
    if H and not H.OnFightStats then
        H.OnFightStats = function(out) pcall(RS.OnFightStats, out) end
        return true
    end
    return H ~= nil
end
if not HookHesitation() then
    -- the HUD part loads after the meter
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function(self) self:UnregisterAllEvents() HookHesitation() end)
end
