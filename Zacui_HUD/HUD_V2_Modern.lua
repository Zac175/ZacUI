-- HUD_V2_Modern - Class HUD v2 on the modern clients (WoW Forever now,
-- Retail later): what the game's own Cooldown Manager lists for the
-- class, read as data for the class HUDs' rows. Nothing of Blizzard's
-- Cooldown Manager frames is touched, hooked or moved; ZacUI draws its
-- own icons from the list. On Classic Era and TBC this file returns on
-- its first line: no frame, event or table is made there.
-- Part of ZacUI; load order is set by the TOC (after HUD_V2_Sources).
--
-- The list (C_CooldownViewer, Forever 1.60.1 / Mainline 12.x): per
-- category the cooldown ids (GetCooldownViewerCategorySet, unlearned
-- entries included so a spell learned later is already known), each with
-- its spell id, override and linked ids and whether it is known
-- (GetCooldownViewerCooldownInfo). Read once, again after the spells
-- change; every value through type() and ns.IsSecret before it is used,
-- every call under pcall (a client without the API, or one that refuses
-- a value, gives an empty list, never an error). An empty category never
-- says "nothing": it is the same as "not served".

local ns = _G.ZacUI
if not ns or not ns.HUD or not ns.HUD.V2 then return end
if not (ns.ModernClient and ns.ModernClient()) then return end
local HUD = ns.HUD
local V2 = HUD.V2

local GetSpellInfo = HUD.GetSpellInfo
local IsSecret = ns.IsSecret

-- Enum.CooldownViewerCategory: Essential 0, Utility 1, TrackedBuff 2,
-- TrackedBar 3 (the rest are retail's spec-agnostic / equipment sets)
local CATS = { essential = 0, utility = 1, buffs = 2, bars = 3 }
local function CatIndex(name)
    local evc = Enum and Enum.CooldownViewerCategory
    if name == "essential" then return evc and evc.Essential or CATS.essential end
    if name == "utility" then return evc and evc.Utility or CATS.utility end
    if name == "buffs" then return evc and evc.TrackedBuff or CATS.buffs end
    if name == "bars" then return evc and evc.TrackedBar or CATS.bars end
    return nil
end

local function Plain(v)
    if v == nil or IsSecret(v) then return nil end
    return v
end

local cache, dirty = nil, true

local function Read()
    local CV = C_CooldownViewer
    if not (CV and CV.GetCooldownViewerCategorySet and CV.GetCooldownViewerCooldownInfo) then return {} end
    local out = {}
    local seen = {}
    for _, name in ipairs({ "essential", "utility", "buffs", "bars" }) do
        local cat = CatIndex(name)
        local ok, ids = pcall(CV.GetCooldownViewerCategorySet, cat, true)
        if ok and type(ids) == "table" then
            for i = 1, #ids do
                local cdID = Plain(ids[i])
                if type(cdID) == "number" and not seen[cdID] then
                    seen[cdID] = true
                    local okI, info = pcall(CV.GetCooldownViewerCooldownInfo, cdID)
                    if okI and type(info) == "table" then
                        local sid = Plain(info.spellID)
                        if type(sid) == "number" and sid > 0 then
                            local linked = {}
                            if type(info.linkedSpellIDs) == "table" then
                                for _, l in ipairs(info.linkedSpellIDs) do
                                    l = Plain(l)
                                    if type(l) == "number" then linked[#linked + 1] = l end
                                end
                            end
                            local sname, _, icon = nil, nil, nil
                            if GetSpellInfo then
                                local okN, n, _, tex = pcall(GetSpellInfo, sid)
                                if okN then sname, icon = n, tex end
                            end
                            local known = Plain(info.isKnown)
                            local _, _, _, _, minR, maxR = GetSpellInfo and GetSpellInfo(sid)
                            out[#out + 1] = {
                                cdID = cdID, spellID = sid, overrideSpellID = Plain(info.overrideSpellID),
                                linked = linked, category = name, isKnown = known ~= false,
                                name = sname, icon = icon,
                                hasRange = (type(maxR) == "number" and maxR > 0) or false,
                            }
                        end
                    end
                end
            end
        end
    end
    return out
end

-- the list, read again only after the spells changed
function V2.Catalogue()
    if dirty or not cache then
        dirty = false
        cache = Read()
    end
    return cache
end

function V2.CatalogueDirty() dirty = true end

local ev = CreateFrame("Frame")
ev:RegisterEvent("SPELLS_CHANGED")
pcall(ev.RegisterEvent, ev, "LEARNED_SPELL_IN_SKILL_LINE")
ev:SetScript("OnEvent", function() dirty = true end)
