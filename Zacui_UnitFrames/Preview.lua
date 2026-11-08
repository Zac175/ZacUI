-- ============================================================================
-- Zacui_UnitFrames - Preview.lua
-- The samples in the settings preview (ZacUI's preview dock): a player,
-- target, target of target, pet, party and raid made of fake people, built
-- and painted by the frames' OWN code - ns.BuildElements / StyleElements for
-- the frame, PaintHealth / PaintPower / PaintName / PaintAuras /
-- PaintIndicators / PaintHeals / CastbarStart for what it shows, the shout
-- glow and the low-health wash from their own files - so a sample is the
-- real thing with made-up numbers and changes the moment a setting does.
-- Part of ZacUI; load order is set by the TOC (after the frames, before
-- Options.lua, which declares the previews).
--
-- Samples are plain frames on one small host frame in the strip's canvas:
-- no unit, no events, kept out of every live frame list (BuildElements'
-- preview flag), never secure, never in move mode or Edit Mode. The strip
-- is wide and short, so samples sit side by side; every update lays them
-- out at their real size, centres what they draw and gives the canvas that
-- box (the strip scales it). The only thing that ticks is one OnUpdate on a
-- canvas child (the sample casts and the health glide demo), and it stops
-- by itself whenever the dock is hidden.
-- ============================================================================
local ADDON, ns = ...

local PV = {}
ns.UFPreview = PV

local function Z() return ns.ZUI or _G.ZacUI end
local function Motion() local z = Z() return z and z.Motion end

-- ----------------------------------------------------------------------------
-- The made-up people
-- ----------------------------------------------------------------------------
local ICON = "Interface\\Icons\\"
local A = {   -- auras: name, icon, spell id, dispel type
    battleShout = { name = "Battle Shout",         icon = ICON .. "Ability_Warrior_BattleShout",   spellID = 25289 },
    fortitude   = { name = "Power Word: Fortitude", icon = ICON .. "Spell_Holy_WordFortitude",     spellID = 10938 },
    motw        = { name = "Mark of the Wild",     icon = ICON .. "Spell_Nature_Regeneration",     spellID = 9885 },
    might       = { name = "Blessing of Might",    icon = ICON .. "Spell_Holy_FistOfJustice",      spellID = 25291 },
    renew       = { name = "Renew",                icon = ICON .. "Spell_Holy_Renew",              spellID = 10929 },
    frenzy      = { name = "Frenzy",               icon = ICON .. "Ability_Druid_ChallangingRoar", spellID = 19451 },
    swp         = { name = "Shadow Word: Pain",    icon = ICON .. "Spell_Shadow_ShadowWordPain",   spellID = 10894, dispelType = "Magic" },
    agony       = { name = "Curse of Agony",       icon = ICON .. "Spell_Shadow_CurseOfSargeras",  spellID = 11713, dispelType = "Curse" },
    sunder      = { name = "Sunder Armor",         icon = ICON .. "Ability_Warrior_Sunder",        spellID = 11597 },
    demo        = { name = "Demoralizing Shout",   icon = ICON .. "Ability_Warrior_WarCry",        spellID = 11556 },
    clap        = { name = "Thunder Clap",         icon = ICON .. "Spell_Nature_ThunderClap",      spellID = 11581 },
    faerie      = { name = "Faerie Fire",          icon = ICON .. "Spell_Nature_FaerieFire",       spellID = 9907, dispelType = "Magic" },
}
-- an aura as a frame shows it: who cast it, how many stacks
local function aura(a, source, count)
    return { name = a.name, icon = a.icon, spellID = a.spellID, dispelType = a.dispelType,
             source = source, count = count }
end

local POWER = {   -- class -> power token, index, current, max
    WARRIOR = { "RAGE", 1, 45, 100 }, ROGUE = { "ENERGY", 3, 80, 100 },
}
local function powerOf(class)
    local p = POWER[class]
    if p then return p[1], p[2], p[3], p[4] end
    return "MANA", 0, 2600, 4000
end

local function playerName()
    local n = UnitName and UnitName("player")
    return (type(n) == "string" and n ~= "") and n or "Zaccw"
end
local function playerClass()
    local _, c = UnitClass and UnitClass("player")
    return c or "WARRIOR"
end

-- one person: the fields Fill reads (hp / maxHp etc. are plain numbers)
local function person(t)
    t.maxHp = t.maxHp or 4200
    t.hp = math.floor(t.maxHp * (t.pct or 1) + 0.5)
    if t.isPlayer and not t.ptoken then
        t.ptoken, t.ptype, t.pp, t.maxPp = powerOf(t.class)
    end
    t.guid = t.guid or ("preview-" .. (t.name or "?"))
    return t
end

-- the single frames, by frame key
local function Singles()
    local me, myClass = playerName(), playerClass()
    return {
        player = person({ name = me, class = myClass, isPlayer = true, friendly = true, pct = 0.72,
            buffs = { aura(A.battleShout, "player"), aura(A.fortitude), aura(A.motw), aura(A.might) },
            debuffs = { aura(A.swp) },
            leader = "leader", combat = true, marker = 1, pvp = true,
            heals = { { amount = 900, previewClass = "PRIEST", previewSlot = 0, previewName = "Holyclone" },
                      { amount = 350, isHot = true, previewClass = "DRUID", previewSlot = 0, previewName = "Treehug" } },
            cast = { "Hearthstone", ICON .. "INV_Misc_Rune_01", 3.0 } }),
        target = person({ name = "Onyxia", reaction = 2, pct = 0.64, maxHp = 1200000,
            ptoken = "MANA", ptype = 0, pp = 70, maxPp = 100,
            portrait = ICON .. "INV_Misc_Head_Dragon_01", creature = 10184,
            buffs = { aura(A.frenzy) },
            debuffs = { aura(A.sunder, "player", 5), aura(A.demo, "player"), aura(A.clap), aura(A.faerie) },
            combat = true, marker = 8,
            heals = { { amount = 60000, previewClass = "PRIEST", previewSlot = 1, previewName = "Holyclone" } },
            cast = { "Fireball", ICON .. "Spell_Fire_FlameBolt", 2.5 } }),
        targettarget = person({ name = me, class = myClass, isPlayer = true, friendly = true, pct = 0.88,
            buffs = { aura(A.battleShout, "player") }, debuffs = {},
            leader = "leader", marker = 1,
            heals = { { amount = 400, previewClass = "PRIEST", previewSlot = 0, previewName = "Holyclone" } },
            cast = { "Slam", ICON .. "Ability_Warrior_DecisiveStrike", 1.5 } }),
        pet = person({ name = "Grimclaw", reaction = 5, pct = 0.9, maxHp = 2600, friendly = true,
            ptoken = "FOCUS", ptype = 2, pp = 70, maxPp = 100,
            portrait = ICON .. "Ability_Hunter_Pet_Wolf", creature = 299,
            buffs = { aura(A.motw) }, debuffs = {},
            heals = { { amount = 300, isHot = true, previewClass = "DRUID", previewSlot = 0, previewName = "Treehug" } },
            cast = { "Furious Howl", ICON .. "Ability_Hunter_Pet_Wolf", 1.0 } }),
    }
end

-- the makings of a sample, for the extra frames' own (Extras.lua: focus,
-- boss...), and their samples on top of the four above
function PV.Kit()
    return { person = person, aura = aura, A = A, ICON = ICON, playerName = playerName, playerClass = playerClass }
end
do
    local base = Singles
    Singles = function()
        local t = base()
        for _, e in ipairs(ns.UF_EXTRA_FRAMES or {}) do
            if e.sample and t[e.key] == nil then
                local ok, d = pcall(e.sample, PV.Kit())
                if ok and d then t[e.key] = d end
            end
        end
        return t
    end
end

-- a party of five (You first), each showing something worth seeing
local function Party()
    local me, myClass = playerName(), playerClass()
    return {
        person({ name = me, class = myClass, isPlayer = true, friendly = true, pct = 0.81,
            buffs = { aura(A.battleShout, "player"), aura(A.fortitude) }, debuffs = {},
            leader = "leader", role = "MAINTANK", combat = true, marker = 1, pvp = true,
            heals = { { amount = 700, previewClass = "PRIEST", previewSlot = 0, previewName = "Holyclone" } } }),
        person({ name = "Holyclone", class = "PRIEST", isPlayer = true, friendly = true, pct = 0.95,
            buffs = { aura(A.fortitude, "player"), aura(A.renew) }, debuffs = {},
            leader = "assist", combat = true, healerClass = "PRIEST", healerSlot = 0, taunt = true,
            cast = { "Greater Heal", ICON .. "Spell_Holy_GreaterHeal", 2.5 } }),
        person({ name = "Stabbz", class = "ROGUE", isPlayer = true, friendly = true, pct = 0.58, faded = true,
            buffs = { aura(A.might) }, debuffs = { aura(A.swp) },
            heals = { { amount = 600, previewClass = "PALADIN", previewSlot = 0, previewName = "Lightbulb" },
                      { amount = 250, isHot = true, previewClass = "DRUID", previewSlot = 0, previewName = "Treehug" } } }),
        person({ name = "Frostie", class = "MAGE", isPlayer = true, friendly = true, pct = 0, status = "Dead",
            rez = true, marker = 6, buffs = {}, debuffs = {} }),
        person({ name = "Treehug", class = "DRUID", isPlayer = true, friendly = true, pct = 0.42,
            buffs = { aura(A.motw, "player") }, debuffs = { aura(A.agony) },
            role = "MAINASSIST", healerClass = "DRUID", healerSlot = 0,
            heals = { { amount = 1100, previewClass = "PRIEST", previewSlot = 0, previewName = "Holyclone" } } }),
    }
end

-- forty raiders, one of every state somewhere in the grid
local RAID_CLASSES = { "WARRIOR", "PRIEST", "ROGUE", "MAGE", "WARLOCK", "HUNTER", "DRUID", "PALADIN" }
local RAID_NAMES = {
    "Zaccw", "Holyclone", "Stabbz", "Frostie", "Dotsy", "Bowman", "Treehug", "Lightbulb",
    "Shieldy", "Prayz", "Sneakz", "Blinky", "Fearme", "Pewpew", "Moonkin", "Bubbles",
    "Axel", "Mendy", "Kidney", "Polly", "Corrupt", "Trapz", "Barkskin", "Judge",
    "Revenge", "Renewz", "Ambush", "Scorch", "Felbro", "Aimshot", "Swiftmend", "Consecr",
    "Sunder", "Smitey", "Vanish", "Pyro", "Drainz", "Volley", "Rejuv", "Blessy",
}
local raidCache
local function Raid()
    if raidCache then return raidCache end
    local list = {}
    for i = 1, 40 do
        local class = RAID_CLASSES[((i - 1) % #RAID_CLASSES) + 1]
        local p = { name = RAID_NAMES[i], class = class, isPlayer = true, friendly = true,
            pct = 0.45 + ((i * 37) % 55) / 100, buffs = {}, debuffs = {} }
        if i == 1 then p.name = playerName() p.class = playerClass() p.leader = "leader" p.role = "MAINTANK" p.marker = 1
        elseif i == 9 then p.role = "MAINTANK" p.marker = 8 p.taunt = true   -- the shout glow + countdown
        elseif i == 17 then p.role = "MAINASSIST" p.leader = "assist"
        elseif i == 4 then p.pct, p.status, p.rez = 0, "Dead", true
        elseif i == 12 then p.pct, p.status = 0, "Dead"
        elseif i == 21 then p.online = false p.status = "Offline"
        elseif i == 6 or i == 30 then p.faded = true
        elseif i == 14 then p.debuffs = { aura(A.swp) }
        elseif i == 27 then p.debuffs = { aura(A.agony) }
        end
        if class == "PRIEST" or class == "DRUID" or class == "PALADIN" then
            p.healerClass, p.healerSlot = class, math.floor(i / 8)
        end
        if i == 1 or i == 9 or i == 19 then
            p.heals = { { amount = 900, previewClass = "PRIEST", previewSlot = 0, previewName = "Holyclone" },
                        { amount = 400, isHot = true, previewClass = "DRUID", previewSlot = 1, previewName = "Barkskin" } }
        end
        list[i] = person(p)
    end
    raidCache = list
    return list
end

-- ----------------------------------------------------------------------------
-- A sample frame, and painting a person onto it
-- ----------------------------------------------------------------------------
-- The live frames' constructor path with the preview flag: built like a
-- unit button, but no unit, no events, not secure, in no live list.
function PV.NewSample(parent)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetSize(100, 30)
    f.isPreview = true
    ns.BuildElements(f, true)
    return f
end

-- cfg: the frame's settings (a frame key's table, or a proxy over one)
function PV.Style(f, cfg)
    if f.Castbar then ns.CastbarStopMotion(f.Castbar) end
    f.cfg = cfg
    f:SetSize(cfg.width or 100, cfg.height or 30)
    ns.UI:FrameBackdrop(f, cfg.bgColor, cfg.borderColor)
    ns.StyleElements(f)
end

-- Paint person `d` onto sample `f` (already styled). Every part goes through
-- the same painter the live frame uses.
function PV.Fill(f, d)
    local cfg = f.cfg or {}
    local online = d.online ~= false
    local r, g, b
    if online then r, g, b = ns.HealthColorFor(cfg, d.isPlayer, d.class, d.reaction)
    else r, g, b = 0.45, 0.45, 0.45 end
    ns.PaintHealth(f, d.hp, d.maxHp, d.guid, online, d.status, r, g, b)
    -- the frame's opacity is the sample's to set: offline dims, out of range fades
    local alpha = 1
    if not online then alpha = 0.55
    elseif d.faded and cfg.rangeFade then alpha = ns.RangeAlpha and ns.RangeAlpha(cfg) or 0.4 end
    f:SetAlpha(alpha)
    f._alpha = nil
    if d.ptoken then ns.PaintPower(f, d.pp or 0, d.maxPp or 100, d.guid, d.ptoken, d.ptype)
    else ns.PaintPower(f, 0, 100, d.guid, "MANA", 0) end
    ns.PaintName(f, d.name, ns.NameColorFor(cfg, d.isPlayer, d.class))
    ns.PaintAuras(f, d.debuffs, d.buffs, d.friendly)
    ns.PaintIndicators(f, d.leader, d.combat, d.role, d.marker, d.rez)
    ns.PaintPvP(f, d.pvp)
    ns.PaintHeals(f, d.heals, d.hp, d.maxHp)
    ns.PaintHealerDot(f, d.healerClass, d.healerSlot)
    -- the portrait, when this frame wears one (Portrait.lua): a player's
    -- is yours, a creature's its own picture
    if ns.PaintPortrait and f.Portrait then ns.PaintPortrait(f, nil, d, true) end
    f._previewPerson = d
end

-- A sample cast: started now, part way through; `loop` restarts it before
-- it ends (the frames preview: always something to look at), otherwise it
-- ends with the castbar's "ends" animation and comes back after a beat.
local function StartCast(f, d, fresh, notInt)
    local cast = d and d.cast
    if not (cast and f.cfg and f.cfg.castbar) then
        ns.CastbarStopMotion(f.Castbar)
        f.Castbar.endT = nil
        f.Castbar:Hide()
        return
    end
    local now = GetTime()
    local len = cast[3] or 2
    local into = fresh and 0 or len * 0.4
    ns.CastbarStart(f, cast[1], cast[2], now - into, now - into + len, false, notInt)
    f.Castbar._previewCast = cast[1]
end

-- keep a sample's cast running across updates, unless it is someone else's
local function KeepCast(f, d)
    local cb = f.Castbar
    if cb:IsShown() and cb.endT and not cb._ending and cb._previewCast == d.cast[1] then return end
    StartCast(f, d, false)
end

-- ----------------------------------------------------------------------------
-- The ticking part: one OnUpdate on a canvas child per preview. It only
-- runs while the dock shows the canvas.
-- ----------------------------------------------------------------------------
local function Driver(canvas, st)
    local drv = CreateFrame("Frame", nil, canvas)
    drv:SetSize(1, 1)
    drv:SetPoint("TOPLEFT")
    drv:SetScript("OnUpdate", function()
        local now = GetTime()
        -- heals measure the health bar; on the first frame after a restyle
        -- the bar may not have its width yet, so they are painted once more
        if st.repaintHeals then
            st.repaintHeals = nil
            for _, f in ipairs(st.healFrames or {}) do
                local d = f._previewPerson
                if d and f:IsShown() then ns.PaintHeals(f, d.heals, d.hp, d.maxHp) end
            end
        end
        for _, c in ipairs(st.casts or {}) do
            local f = c.frame
            local cb = f.Castbar
            if f:IsShown() and f.cfg and f.cfg.castbar then
                if c.loop then
                    if cb.endT and now >= cb.endT - 0.05 then StartCast(f, c.person, true, c.notInt) end
                elseif not cb:IsShown() and not cb._ending then
                    c.wait = c.wait or (now + 0.7)
                    if now >= c.wait then
                        c.wait = nil
                        StartCast(f, c.person, true, c.notInt)
                    end
                end
            end
        end
        if st.glide then st.glide(now) end
        -- samples that wear the AoE-taunt glow light it again a second
        -- after it ends, so its countdown is always there to see
        for _, f in ipairs(st.taunts or {}) do
            local g = rawget(f, "ShoutGlow")
            if g and g:IsShown() then f._tauntAgain = nil
            elseif f:IsShown() then
                f._tauntAgain = f._tauntAgain or (now + 1)
                if now >= f._tauntAgain then
                    f._tauntAgain = nil
                    ns.ShoutGlowFrame(f, 6)
                end
            end
        end
    end)
    return drv
end

-- The samples hang from one host frame, so they move together.
local function NewHost(canvas)
    local h = CreateFrame("Frame", nil, canvas)
    h:SetSize(1, 1)
    h:SetPoint("CENTER", canvas, "CENTER", 0, 0)
    return h
end

-- A note sits beside the samples (the strip has room across, not down).
local NOTE_W = 140
local function Note(host)
    local z = Z()
    local UI = z and z.UI
    local fs
    if UI and UI.Font then
        fs = UI.Font(host, UI.F.SMALL, { cat = "text", key = "orange", justify = "LEFT", width = NOTE_W })
    else
        fs = host:CreateFontString(nil, "OVERLAY")
        fs:SetFont(STANDARD_TEXT_FONT, 10, "")
        fs:SetWidth(NOTE_W)
        fs:SetJustifyH("LEFT")
    end
    fs:SetPoint("CENTER", host, "CENTER", 0, 0)
    fs:Hide()
    return fs
end

local function SetNote(fs, text)
    fs._zNote = text
    if not text then fs:Hide() end
end

-- Frames left to right on the host, centred on its middle at height y,
-- each spaced by what it really draws (its auras and cast bar included),
-- `gap` apart. Returns the row's width.
local function LayRow(P, host, frames, gap, y)
    y = y or 0
    local boxes, total = {}, 0
    for i, f in ipairs(frames) do
        f:ClearAllPoints()
        f:SetPoint("CENTER", host, "CENTER", 0, y)
        local cx, w
        if P.Measure then
            local mx, _, mw = P.Measure(f)
            cx, w = mx, mw
        end
        if not cx then cx, w = 0, f:GetWidth() or 0 end
        boxes[i] = { cx, w }
        total = total + w + ((i > 1) and gap or 0)
    end
    local x = -total / 2
    for i, f in ipairs(frames) do
        local cx, w = boxes[i][1], boxes[i][2]
        f:ClearAllPoints()
        f:SetPoint("CENTER", host, "CENTER", x + w / 2 - cx, y)
        x = x + w + gap
    end
    return total
end

-- The canvas becomes what the samples draw (plus the note beside them),
-- centred; the strip scales it.
local FIT_PAD = 6
local function Fit(canvas, P, host, note)
    if not (P.Measure and P.Resize) then return end
    if note then note:Hide() end
    local cx, cy, w, h = P.Measure(host)
    if not cx then return end
    local text = note and note._zNote
    if text then
        note:ClearAllPoints()
        note:SetPoint("LEFT", host, "CENTER", cx + w / 2 + 12, cy)
        note:SetText(text)
        note:Show()
        local cx2, cy2, w2, h2 = P.Measure(host)
        if cx2 then cx, cy, w, h = cx2, cy2, w2, h2 end
    end
    host:ClearAllPoints()
    host:SetPoint("CENTER", canvas, "CENTER", -cx, -cy)
    P.Resize(w + FIT_PAD, h + FIT_PAD)
end

-- the castbar height a frame really uses
local function CastH(cfg)
    local h = (cfg.cbHeight and cfg.cbHeight > 0) and cfg.cbHeight or (ns.db.castbar.height or 16)
    return h
end

-- ----------------------------------------------------------------------------
-- PREVIEW 1: the frames (modes player / target / targettarget / pet / party / raid)
-- ----------------------------------------------------------------------------
PV.FRAME_MODES = {
    { id = "player", label = "Player" },
    { id = "target", label = "Target" },
    { id = "targettarget", label = "ToT" },
    { id = "pet", label = "Pet" },
    { id = "party", label = "Party" },
    { id = "raid", label = "Raid" },
}
-- the frames only some games have, each after the mode it names
for _, e in ipairs(ns.UF_EXTRA_FRAMES or {}) do
    local at = #PV.FRAME_MODES + 1
    for i, m in ipairs(PV.FRAME_MODES) do if e.after and m.id == e.after then at = i + 1 end end
    table.insert(PV.FRAME_MODES, at, { id = e.key, label = e.short or e.label })
end

local function cfgFor(mode)
    if mode == "party" or mode == "raid" then return ns.db[mode] end
    return ns.db.frames[mode] or ns.db.frames.player
end

-- The canvas a mode starts with at scale 1: the frame (a group's row)
-- with what hangs off it. Each update then fits the canvas to what the
-- samples really draw (Fit), so this only has to be close.
function PV.FrameCanvasSize(mode)
    if not ns.db then return 220, 70 end
    local cfg = cfgFor(mode)
    local ac = ns.db.auras
    local step = (ac.size or 20) + (ac.spacing or 2)
    local auraW = math.min(ac.max or 6, ac.perRow or 6) * step
    local hang = ((cfg.showBuffs and step) or 0) + ((cfg.showDebuffs and step) or 0)
    local w, h = math.max(cfg.width, (cfg.showBuffs or cfg.showDebuffs) and auraW or 0), cfg.height + hang
    if mode == "party" or mode == "raid" then
        -- the group's real footprint, as the headers lay it out
        local count, place = ns.GroupLayout(mode, cfg, nil, true)
        local l, r, t, b = 0, 0, 0, 0
        for i = 1, count do
            local x, y = place(i)
            l, r = math.min(l, x), math.max(r, x + cfg.width)
            t, b = math.max(t, y), math.min(b, y - cfg.height)
        end
        w, h = math.max(w, r - l), (t - b) + hang
    elseif cfg.castbar then
        h = h + CastH(cfg) + 4
    end
    -- a portrait beside the frame adds its width
    local pc = cfg.portrait
    if type(pc) == "table" and ns.PortraitOn(cfg) and pc.layout == "outside" and ns.PortraitSize then
        w = w + ns.PortraitSize(cfg) + (tonumber(pc.gap) or 2)
    end
    return math.floor(w + FIT_PAD), math.floor(h + FIT_PAD)
end

function PV.BuildFrames(canvas, P)
    local st = P.store
    st.host = NewHost(canvas)
    st.single = PV.NewSample(st.host)
    st.party, st.raid = {}, {}
    st.casts, st.healFrames = {}, {}
    st.taunts = {}
    st.note = Note(st.host)
    st.drv = Driver(canvas, st)
end

-- A group sample that wears the taunt glow (one member: the party's
-- priest, the raid's second tank) keeps it lit; any other has it put out.
local function TauntFill(st, f, d)
    if d.taunt then
        st.taunts[#st.taunts + 1] = f
        local g = rawget(f, "ShoutGlow")
        if not (g and g:IsShown()) then ns.ShoutGlowFrame(f, 6) end
    elseif rawget(f, "ShoutGlow") then
        ns.ShoutGlowOff(f)
    end
end

-- The members a group header would show, in its order: yourself left out
-- when Include yourself is off, sorted by name when asked, reversed for
-- descending (a grouped raid sorts inside each group of five).
local function Members(kind, cfg)
    local people = (kind == "party") and Party() or Raid()
    local out = {}
    local from = cfg.showPlayer and 1 or 2
    for i = from, #people do out[#out + 1] = people[i] end
    local function order(list, a, b)
        local seg = {}
        for i = a, b do seg[#seg + 1] = list[i] end
        if cfg.sortMethod == "Name" then
            table.sort(seg, function(x, y) return x.name < y.name end)
        end
        if cfg.sortDir == "Descending" then
            local n = #seg
            for i = 1, math.floor(n / 2) do seg[i], seg[n - i + 1] = seg[n - i + 1], seg[i] end
        end
        for i = a, b do list[i] = seg[i - a + 1] end
    end
    if kind == "raid" and cfg.groupBy then
        for g = 0, 7 do
            local a, b = g * 5 + 1, math.min(#out, g * 5 + 5)
            if a <= b then order(out, a, b) end
        end
    else
        order(out, 1, #out)
    end
    return out
end

-- The status icon being placed on the Position tab is always worn by the
-- samples (still only when its toggle is on), so it can be seen while it
-- is moved: Options sets PV.focus to the element picked there.
local FOCUS_ICON = { Combat = "combat", Leader = "leader", Role = "role", Marker = "marker", Rez = "rez", PvP = "pvp" }
local function FocusFill(f, d)
    local which = PV.focus and FOCUS_ICON[PV.focus]
    if not which then return end
    if which == "pvp" then ns.PaintPvP(f, true) return end
    ns.PaintIndicators(f,
        (which == "leader") and "leader" or d.leader,
        (which == "combat") or d.combat,
        (which == "role") and "MAINTANK" or d.role,
        (which == "marker") and (d.marker or 8) or d.marker,
        (which == "rez") or d.rez)
end

local function poolFrame(st, list, i)
    local f = list[i]
    if not f then
        f = PV.NewSample(st.host)
        list[i] = f
    end
    return f
end

function PV.UpdateFrames(canvas, P)
    local st = P.store
    local mode = P.mode or "player"
    local cfg = cfgFor(mode)
    wipe(st.casts)
    wipe(st.healFrames)
    st.taunts = st.taunts or {}
    wipe(st.taunts)
    -- a set of frames of an extra file (the boss frames...): its own layout
    local ex = ns.ExtraFrame and ns.ExtraFrame(mode)
    local lay = ex and ex.layout
    local single = (mode ~= "party" and mode ~= "raid") and not lay

    -- singles: the frame with its auras and cast bar, as one piece
    if single then
        local f = st.single
        PV.Style(f, cfg)
        local d = Singles()[mode]
        PV.Fill(f, d)
        FocusFill(f, d)
        f:ClearAllPoints()
        f:SetPoint("CENTER", st.host, "CENTER", 0, 0)
        f:Show()
        st.healFrames[1] = f
        if cfg.castbar then
            st.casts[1] = { frame = f, person = d, loop = true }
            KeepCast(f, d)
        else
            StartCast(f, nil)
        end
    else
        st.single:Hide()
    end

    -- party and raid: the whole group exactly as the headers lay it out in
    -- game (ns.GroupLayout: the party's column of five, the raid's groups
    -- side by side or its flat columns), members in the headers' order
    -- (yourself, sort, direction). The strip shows it at its real size and
    -- scales it down only when it does not fit.
    for _, kind in ipairs({ "party", "raid" }) do
        local list = st[kind]
        if mode == kind then
            local people = Members(kind, cfg)
            local count, place = ns.GroupLayout(kind, cfg, nil, true)
            count = math.min(count, #people)
            for i = 1, count do
                local f = poolFrame(st, list, i)
                PV.Style(f, cfg)
                local d = people[i]
                PV.Fill(f, d)
                FocusFill(f, d)
                f:Show()
                TauntFill(st, f, d)
                st.healFrames[#st.healFrames + 1] = f
                if cfg.castbar and d.cast then
                    st.casts[#st.casts + 1] = { frame = f, person = d, loop = true }
                    KeepCast(f, d)
                else
                    StartCast(f, nil)
                end
                local x, y = place(i)
                f:ClearAllPoints()
                f:SetPoint("TOPLEFT", st.host, "CENTER", x, y)
            end
            for i = count + 1, #list do list[i]:Hide() end
        else
            for _, f in ipairs(list) do f:Hide() end
        end
    end

    -- an extra set: the people its file lays out (its own frames first; a
    -- person may wear other settings, d._cfg - a party cell beside them),
    -- each placed from the host's middle as the groups are
    st.extra = st.extra or {}
    if lay then
        local people, place = lay(cfg, PV.Kit())
        people = people or {}
        for i, d in ipairs(people) do
            local f = poolFrame(st, st.extra, i)
            local fcfg = d._cfg or cfg
            PV.Style(f, fcfg)
            PV.Fill(f, d)
            FocusFill(f, d)
            f:Show()
            st.healFrames[#st.healFrames + 1] = f
            if fcfg.castbar and d.cast then
                st.casts[#st.casts + 1] = { frame = f, person = d, loop = true }
                KeepCast(f, d)
            else
                StartCast(f, nil)
            end
            local x, y = place(i, d)
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", st.host, "CENTER", x, y)
        end
        for i = #people + 1, #st.extra do st.extra[i]:Hide() end
    else
        for _, f in ipairs(st.extra) do f:Hide() end
    end

    st.repaintHeals = true
    SetNote(st.note, (not cfg.enabled) and "This frame is switched off (General tab)." or nil)
    Fit(canvas, P, st.host, st.note)
end

-- Replay: the health glides in from full (smooth bars), the cast starts
-- over with the castbar's "appears" animation.
function PV.ReplayFrames(canvas, P)
    local st = P.store
    for _, f in ipairs(st.healFrames or {}) do
        local d = f._previewPerson
        if d and f:IsShown() then
            f.Health._zsv = nil
            local online = d.online ~= false
            local r, g, b
            if online then r, g, b = ns.HealthColorFor(f.cfg, d.isPlayer, d.class, d.reaction)
            else r, g, b = 0.45, 0.45, 0.45 end
            ns.PaintHealth(f, d.maxHp, d.maxHp, d.guid, online, d.status, r, g, b)
            ns.PaintHealth(f, d.hp, d.maxHp, d.guid, online, d.status, r, g, b)
        end
    end
    for _, c in ipairs(st.casts or {}) do
        local cb = c.frame.Castbar
        ns.CastbarStopMotion(cb)
        cb.endT = nil
        cb:Hide()
        StartCast(c.frame, c.person, false)
    end
    st.repaintHeals = true
end

-- ----------------------------------------------------------------------------
-- PREVIEW 2: incoming heals - four of you, each telling a different story
-- (covered, exposed, not enough with a pile of healers, a healer's own dot)
-- ----------------------------------------------------------------------------
-- The samples wear the player frame's look with heals switched on, whatever
-- the player frame's own toggle says: a proxy over its settings.
local function healCfg()
    local base = ns.db.frames.player
    return setmetatable({ healPrediction = true, castbar = false, showBuffs = false, showDebuffs = false },
        { __index = base })
end

local function HealPeople()
    local me, myClass = playerName(), playerClass()
    return {
        person({ name = me, class = myClass, isPlayer = true, friendly = true, pct = 0.45,
            heals = { { amount = 1500, own = true, previewClass = "PRIEST", previewSlot = 0, previewName = me },
                      { amount = 900, previewClass = "PRIEST", previewSlot = 0, previewName = "Holyclone" },
                      { amount = 300, isHot = true, previewClass = "DRUID", previewSlot = 0, previewName = "Treehug" } } }),
        person({ name = "Shieldy", class = "WARRIOR", isPlayer = true, friendly = true, pct = 0.30,
            heals = { { amount = 800, previewClass = "PALADIN", previewSlot = 0, previewName = "Lightbulb" },
                      { amount = 500, isHot = true, previewClass = "DRUID", previewSlot = 1, previewName = "Barkskin" } } }),
        person({ name = "Stabbz", class = "ROGUE", isPlayer = true, friendly = true, pct = 0.12,
            heals = { { amount = 250, previewClass = "PRIEST", previewSlot = 0, previewName = "Holyclone" },
                      { amount = 200, previewClass = "PRIEST", previewSlot = 1, previewName = "Prayz" },
                      { amount = 200, previewClass = "PALADIN", previewSlot = 0, previewName = "Lightbulb" },
                      { amount = 150, isHot = true, previewClass = "DRUID", previewSlot = 0, previewName = "Treehug" },
                      { amount = 150, previewClass = "SHAMAN", previewSlot = 0, previewName = "Totemz" },
                      { amount = 100, generic = true } } }),
        person({ name = "Holyclone", class = "PRIEST", isPlayer = true, friendly = true, pct = 0.92,
            healerClass = "PRIEST", healerSlot = 0 }),
    }
end

-- Four player-sized frames, two by two (each a story of its own, not a
-- layout from the game: two columns keep them at their real size).
local HEAL_GAP = 8
function PV.HealCanvasSize()
    if not ns.db then return 300, 70 end
    local c = ns.db.frames.player
    return math.floor(2 * c.width + HEAL_GAP + FIT_PAD), math.floor(2 * c.height + HEAL_GAP + FIT_PAD)
end

function PV.BuildHeals(canvas, P)
    local st = P.store
    st.host = NewHost(canvas)
    st.rows = {}
    for i = 1, 4 do st.rows[i] = PV.NewSample(st.host) end
    st.healFrames = st.rows
    st.casts = {}
    st.drv = Driver(canvas, st)
end

function PV.UpdateHeals(canvas, P)
    local st = P.store
    local cfg = healCfg()
    local people = HealPeople()
    -- Forever (Core_Flavor): other healers' heals come from the combat log
    -- and addon messages, which it does not give addons - only your own show
    local z = Z()
    if z and z.NoCombatLog and z.NoCombatLog() then
        for _, p in ipairs(people) do
            if p.heals then
                local own = {}
                for _, h in ipairs(p.heals) do if h.own then own[#own + 1] = h end end
                p.heals = own
            end
        end
    end
    local bw, bh = cfg.width, cfg.height
    for i, f in ipairs(st.rows) do
        PV.Style(f, cfg)
        PV.Fill(f, people[i])
        f:ClearAllPoints()
        f:SetPoint("CENTER", st.host, "CENTER", 0, 0)
        f:Show()
        -- what it draws: the heals may run past the frame's end
        local cx, _, w, h
        if P.Measure then cx, _, w, h = P.Measure(f) end
        if cx then bw, bh = math.max(bw, w), math.max(bh, h) end
    end
    local dy = (bh + HEAL_GAP) / 2
    LayRow(P, st.host, { st.rows[1], st.rows[2] }, HEAL_GAP, dy)
    LayRow(P, st.host, { st.rows[3], st.rows[4] }, HEAL_GAP, -dy)
    st.repaintHeals = true
    Fit(canvas, P, st.host)
end

-- ----------------------------------------------------------------------------
-- PREVIEW 3: animation (modes castbar / shout / lowhp / bars)
-- ----------------------------------------------------------------------------
local LOW_PCT, LowSeverity

PV.MOTION_MODES = {
    { id = "castbar", label = "Castbar" },
    { id = "shout",   label = "Shout alert" },
    { id = "lowhp",   label = "Low health" },
    { id = "bars",    label = "Bars" },
}

-- a frame's settings with its castbar on (the castbar mode shows both kinds
-- of cast whatever the target frame's own toggle says)
local function withCast(base)
    return setmetatable({ castbar = true, showBuffs = false, showDebuffs = false,
        cbAnchor = "BELOW", cbX = 0, cbY = -2 }, { __index = base })
end
local function plain(base)
    return setmetatable({ castbar = false, showBuffs = false, showDebuffs = false }, { __index = base })
end

-- The low-health sample sits at 20% health; its wash is as strong as the
-- live warning would make it there (none at or above the threshold).
LOW_PCT = 20
function LowSeverity()
    local lh = ns.db.lowHealth
    local thr = tonumber(lh and lh.threshold) or 35
    if LOW_PCT >= thr or thr <= 0 then return nil end
    return math.min(1, math.max(0, (thr - LOW_PCT) / thr))
end

function PV.BuildMotion(canvas, P)
    local st = P.store
    st.host = NewHost(canvas)
    st.a, st.b, st.c = PV.NewSample(st.host), PV.NewSample(st.host), PV.NewSample(st.host)
    st.casts, st.healFrames, st.taunts = {}, {}, {}
    st.note = Note(st.host)
    st.drv = Driver(canvas, st)
end

local function hideAll(st)
    for _, f in ipairs({ st.a, st.b, st.c }) do
        ns.ShoutGlowOff(f)
        if ns.LowHealthWash then ns.LowHealthWash(f, nil) end
        ns.CastbarStopMotion(f.Castbar)
        f.Castbar.endT = nil
        f.Castbar:Hide()
        f:Hide()
    end
end

function PV.UpdateMotion(canvas, P)
    local st = P.store
    local mode = P.mode or "castbar"
    wipe(st.casts)
    wipe(st.healFrames)
    wipe(st.taunts)
    st.glide = nil
    hideAll(st)
    local note
    local singles = Singles()
    if mode == "castbar" then
        local cfg = withCast(ns.db.frames.target)
        local tgt = singles.target
        local foe = person({ name = "Death Talon Wyrmguard", reaction = 2, pct = 0.8, maxHp = 60000,
            buffs = {}, debuffs = {}, cast = { "War Stomp", ICON .. "Ability_WarStomp", 2.0 } })
        for i, f in ipairs({ st.a, st.b }) do
            PV.Style(f, cfg)
            PV.Fill(f, i == 1 and tgt or foe)
            f:Show()
            st.casts[i] = { frame = f, person = i == 1 and tgt or foe, notInt = (i == 2) }
        end
        note = "Left: a cast you can interrupt. Right: one you can't."
    elseif mode == "shout" then
        local cfg = plain(ns.db.party)
        local people = Party()
        for i, f in ipairs({ st.a, st.b, st.c }) do
            PV.Style(f, cfg)
            PV.Fill(f, people[i])
            f:Show()
        end
        -- the middle one taunted: its glow and countdown, again and again
        st.taunts[1] = st.b
        if not (ns.db.shoutAlert and ns.db.shoutAlert.enabled) then
            note = "The shout alert is off (General tab) - this is how it would look."
        end
    elseif mode == "lowhp" then
        local cfg = plain(ns.db.frames.player)
        local d = person({ name = playerName(), class = playerClass(), isPlayer = true, friendly = true,
            pct = LOW_PCT / 100, combat = true })
        local f = st.a
        PV.Style(f, cfg)
        PV.Fill(f, d)
        f:ClearAllPoints()
        f:SetPoint("CENTER", st.host, "CENTER", 0, 0)
        f:Show()
        local lh = ns.db.lowHealth
        if not (lh and lh.enabled) then
            note = "The low-health warning is off (General tab) - this is how it would look."
        elseif not lh.glow then
            note = "The wash is off (General tab)."
        elseif not LowSeverity() then
            note = ("At %d%% health you are above the warning's threshold."):format(LOW_PCT)
        end
    else -- bars: the health and power glide back and forth
        local cfg = plain(ns.db.frames.player)
        local d = person({ name = playerName(), class = playerClass(), isPlayer = true, friendly = true, pct = 0.85 })
        local f = st.a
        PV.Style(f, cfg)
        PV.Fill(f, d)
        f:ClearAllPoints()
        f:SetPoint("CENTER", st.host, "CENTER", 0, 0)
        f:Show()
        local nextAt, low = 0, false
        st.glide = function(now)
            if now < nextAt then return end
            nextAt = now + 1.2
            low = not low
            local hp = math.floor(d.maxHp * (low and 0.35 or 0.85))
            local r, g, b = ns.HealthColorFor(f.cfg, true, d.class)
            ns.PaintHealth(f, hp, d.maxHp, d.guid, true, nil, r, g, b)
            ns.PaintPower(f, low and 15 or (d.pp or 45), d.maxPp or 100, d.guid, d.ptoken, d.ptype)
        end
        if ns.db.smoothBars == false then note = "Smooth bars are off - the bars jump."
        else
            local Mo = Motion()
            if Mo and Mo.Enabled and not Mo.Enabled() then note = "Animations are off (Appearance > Motion)." end
        end
    end
    SetNote(st.note, note)
    PV.ReplayMotion(canvas, P)
    -- after the replay, so the casts and the glow are up when it measures
    if mode == "castbar" then LayRow(P, st.host, { st.a, st.b }, 16, 0)
    elseif mode == "shout" then
        -- three party members in the party's own column
        local cfg = ns.db.party
        local _, place = ns.GroupLayout("party", cfg, nil, false)
        for i, f in ipairs({ st.a, st.b, st.c }) do
            local x, y = place(i)
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", st.host, "CENTER", x, y)
        end
    end
    Fit(canvas, P, st.host, st.note)
end

function PV.ReplayMotion(canvas, P)
    local st = P.store
    local mode = P.mode or "castbar"
    if mode == "castbar" then
        for _, c in ipairs(st.casts) do
            local cb = c.frame.Castbar
            ns.CastbarStopMotion(cb)
            cb.endT = nil
            cb:Hide()
            c.wait = nil
            StartCast(c.frame, c.person, true, c.notInt)
        end
    elseif mode == "shout" then
        ns.ShoutGlowOff(st.b)
        ns.ShoutGlowFrame(st.b, 6)
    elseif mode == "lowhp" then
        ns.LowHealthWash(st.a, nil)
        ns.LowHealthWash(st.a, LowSeverity())
    end
end
