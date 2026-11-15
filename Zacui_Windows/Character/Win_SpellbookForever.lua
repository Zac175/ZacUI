-- Win_SpellbookForever - what ZacUI's spellbook lists on WoW Forever: every
-- rank of every spell, the way the Classic Era book lists them.
-- Part of ZacUI; load order is set by the TOC (right before Win_Spellbook,
-- which asks ns.SpellbookForever for its rows when it is there).
--
-- WHY THIS IS NEEDED. On Classic Era the client hands the book over
-- already filtered: with "Show all spell ranks" off, the lower ranks are
-- simply not in it. Forever's client always hands over every rank and its
-- own book filters them in Lua (Blizzard_PlayerSpells/SpellBook/
-- Blizzard_SpellBookFrame.lua: ShouldDisplaySpellBookItem hides a slot
-- C_SpellBook.IsSpellBookItemLowRank calls low unless the ShowAllSpellRanks
-- CVar is on; skill lines with shouldHide are never shown). Its spell
-- calls also moved: C_SpellBook.GetSpellBookItemInfo gives the spell id,
-- name, rank text, icon, passive flag and item type in one table, which
-- the old name-based reads could not. Every call named here is in
-- Forever's API documentation (Gethe/wow-ui-source, branch "forever",
-- Blizzard_APIDocumentationGenerated/SpellBookDocumentation.lua).
--
-- A ROW CASTS BY SPELL ID. Forever's secure "spell" action casts a number
-- with CastSpellByID (Blizzard_FrameXML/SecureTemplates.lua, branch
-- "forever"), so a low rank row casts exactly that rank.

local ADDON_NAME = ...
-- Zacui_Windows is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end
if not _G.ZACUI_IS_FOREVER then return end
if ns.FeatureOn and not ns.FeatureOn("classic_book") then return end

local FB = {}
ns.SpellbookForever = FB

local BOOK_SPELL = BOOKTYPE_SPELL or "spell"
local BOOK_PET = BOOKTYPE_PET or "pet"

local function Plain(v)
    if v == nil or (ns.IsSecret and ns.IsSecret(v)) then return nil end
    return v
end
local function Num(v, d)
    v = Plain(v)
    if type(v) ~= "number" then return d end
    return v
end

local function Bank(isPet)
    local b = Enum and Enum.SpellBookSpellBank
    if b then return isPet and b.Pet or b.Player end
    return isPet and 1 or 0
end
FB.Bank = Bank

local function ItemType(name)
    local t = Enum and Enum.SpellBookItemType
    return t and t[name]
end

-- The skill lines the game's own book shows: { index, name, icon, offset,
-- count }. A line of a spec not in force (offSpecID) is not yours to cast.
function FB.Lines()
    local SB = C_SpellBook
    local out = {}
    if not (SB and SB.GetNumSpellBookSkillLines and SB.GetSpellBookSkillLineInfo) then return out end
    local ok, n = pcall(SB.GetNumSpellBookSkillLines)
    for i = 1, (ok and Num(n, 0) or 0) do
        local okI, info = pcall(SB.GetSpellBookSkillLineInfo, i)
        if okI and type(info) == "table" and not Plain(info.shouldHide) and not Plain(info.offSpecID) then
            out[#out + 1] = { index = i, name = Plain(info.name) or "", icon = Plain(info.iconID),
                offset = Num(info.itemIndexOffset, 0), count = Num(info.numSpellBookItems, 0) }
        end
    end
    return out
end

local function ShowAllRanks()
    return GetCVarBool and GetCVarBool("ShowAllSpellRanks") and true or false
end
FB.ShowAllRanks = ShowAllRanks

-- One slot as Win_Spellbook's row reads it; nil for what the book does not
-- list (a spell not learned yet, a pet command, a lower rank while the
-- player has "all ranks" off).
function FB.Entry(slot, isPet, schoolName, schoolIndex, allRanks)
    local SB = C_SpellBook
    if not (SB and SB.GetSpellBookItemInfo) then return nil end
    local bank = Bank(isPet)
    local ok, info = pcall(SB.GetSpellBookItemInfo, slot, bank)
    if not ok or type(info) ~= "table" then return nil end
    local kind = Plain(info.itemType)
    if kind ~= nil and kind ~= ItemType("Spell") then return nil end
    if Plain(info.isOffSpec) then return nil end
    local name = Plain(info.name)
    local spellID = Num(info.spellID) or Num(info.actionID)
    if not name or name == "" or not spellID then return nil end
    if not allRanks and SB.IsSpellBookItemLowRank then
        local okL, low = pcall(SB.IsSpellBookItemLowRank, slot, bank)
        if okL and Plain(low) then return nil end
    end
    local e = {
        slot = slot, book = isPet and BOOK_PET or BOOK_SPELL, bank = bank,
        name = name, rank = Plain(info.subName) or "", spellID = spellID,
        icon = Plain(info.iconID), passive = Plain(info.isPassive) and true or false,
        school = schoolName, schoolIndex = schoolIndex,
        -- the secure row casts this exact rank
        castValue = spellID,
    }
    if isPet and SB.GetSpellBookItemAutoCast then
        local okA, allowed, on = pcall(SB.GetSpellBookItemAutoCast, slot, bank)
        if okA then e.autoAllowed, e.autoOn = Plain(allowed) and true or false, Plain(on) and true or false end
    end
    return e
end

-- Every entry of a book (pet, or one school / all of them), in book order.
function FB.Entries(isPet, school)
    local out = {}
    local all = ShowAllRanks()
    if isPet then
        local SB = C_SpellBook
        local n = 0
        if SB and SB.HasPetSpells then
            local ok, num = pcall(SB.HasPetSpells)
            n = ok and Num(num, 0) or 0
        end
        for slot = 1, n do
            local e = FB.Entry(slot, true, PET or "Pet", 0, true)
            if e then out[#out + 1] = e end
        end
        return out
    end
    for _, line in ipairs(FB.Lines()) do
        if school == 0 or school == line.index then
            for slot = line.offset + 1, line.offset + line.count do
                local e = FB.Entry(slot, false, line.name, line.index, all)
                if e then out[#out + 1] = e end
            end
        end
    end
    return out
end

function FB.Tooltip(owner, e)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if GameTooltip.SetSpellBookItem then
        pcall(GameTooltip.SetSpellBookItem, GameTooltip, e.slot, e.bank)
    elseif GameTooltip.SetSpellByID and e.spellID then
        GameTooltip:SetSpellByID(e.spellID)
    end
    GameTooltip:Show()
end

function FB.Pickup(e)
    local SB = C_SpellBook
    if SB and SB.PickupSpellBookItem then pcall(SB.PickupSpellBookItem, e.slot, e.bank) end
end

function FB.PetCount()
    local SB = C_SpellBook
    if not (SB and SB.HasPetSpells) then return 0 end
    local ok, n = pcall(SB.HasPetSpells)
    return ok and Num(n, 0) or 0
end
