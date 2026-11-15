-- ============================================================================
-- ZacUF - Compat.lua   (must load FIRST, before any library)
--
-- Patch 1.15.9 shipped the retail-style AuraUtil (now in Blizzard_FrameXMLUtil).
-- Its FindAuraByName is a thin dispatch:
--
--     AuraUtil.FindAuraByName(name, unit, filter)
--       -> C_UnitAuras.GetAuraDataBySpellName(unit, name, filter)
--
-- ...but C_UnitAuras.GetAuraDataBySpellName never shipped on the Classic Era
-- client, so every FindAuraByName call errors with "attempt to call a nil
-- value". That is what kills LibHealComm-4.0's UNIT_AURA handler - which is
-- the entire HoT-tracking path - and any other addon using FindAuraByName.
--
-- Fix: polyfill using GetAuraDataByIndex, which the client does have (Blizzard's
-- own frames run on it).
--
-- SCOPE - deliberately narrow. HealVision patched C_UnitAuras.GetAuraDataBySpellName,
-- which repairs every caller at once. ZacUF does not, because ZacUF drives SECURE
-- unit frames and group headers: any Lua closure of ours sitting in a path that
-- Blizzard's own UI calls is a taint vector, and a tainted return value spreads
-- into whatever consumes it. C_UnitAuras is reachable from everywhere.
--
-- AuraUtil.FindAuraByName is the narrower door, and it is the only one we need:
-- LibHealComm captures it into a file-local upvalue at load time, so patching it
-- HERE - before the libs load, which is why this file is first in the TOC -
-- reaches LibHealComm's HoT tracking and effectively nothing else.
--
-- The shim self-retires: the guard below makes it a no-op the moment the real
-- function ships in a client hotfix.
--
-- Behavior mirrors the retail API: first matching aura, case-insensitive name
-- match, nil filter behaving as "HELPFUL" (GetAuraDataByIndex defaults it).
--
-- Ported, and tightened, from the HealVision addon that ZacUF now supersedes.
-- ============================================================================

local function findByName(unit, spellName, filter)
    if not unit or not spellName then return nil end
    local wanted = string.lower(spellName)
    local i = 1
    while true do
        local aura = C_UnitAuras.GetAuraDataByIndex(unit, i, filter)
        if not aura then return nil end
        -- (WoW Forever hides auras in combat: a secret name is no match)
        if issecretvalue ~= nil and issecretvalue(aura.name) then return nil end
        if aura.name and string.lower(aura.name) == wanted then return aura end
        i = i + 1
    end
end

-- Only patch when the provider is genuinely missing AND AuraUtil is already the
-- broken dispatch shape (it has UnpackAuraData, so it is the 1.15.9 version).
if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    and not C_UnitAuras.GetAuraDataBySpellName
    and AuraUtil and AuraUtil.UnpackAuraData then
    AuraUtil.FindAuraByName = function(auraName, unit, filter)
        return AuraUtil.UnpackAuraData(findByName(unit, auraName, filter))
    end
end
