-- ============================================================================
-- ZacUF - Blizzard.lua
-- Hides the default Blizzard frames that ZacUF replaces.  Each is gated by
-- both the per-type Blizzard toggle AND the matching ZacUF frame being
-- enabled, so disabling a ZacUF frame restores Blizzard's automatically (on
-- /reload).
--
-- Hiding follows the current oUF pattern (verified against oUF master and
-- the 2.5.6 client source, which Blizzard designated the reference
-- environment for 1.15.9):
--   1. UnregisterAllEvents + Hide + reparent under a permanently hidden
--      frame.  Anything parented here can be Show()n by Blizzard code all it
--      likes and never render.
--   2. hooksecurefunc the frame's SetParent.  Edit Mode layout application
--      and UIParent's managed-frame code (PlayerCastingBarFrame inherits
--      UIParentBottomManagedFrameTemplate on 1.15.9+) re-SetParent frames;
--      the hook puts them back under the hidden parent, deferring protected
--      frames to PLAYER_REGEN_ENABLED when it happens in combat.
--   3. No OnShow re-hide hooks.  The hidden parent already guarantees
--      invisibility, and re-hiding inside Edit Mode's secure Show calls is
--      pointless churn.  This matches oUF, which has coexisted with this
--      exact Edit Mode code on retail since Dragonflight.
--
-- Deliberately NO EditModeManagerFrame surgery (no method nops, no checkbox
-- hiding).  oUF ships none and has three years of production evidence that
-- hidden unit frames don't taint Edit Mode's secure paths.  Worst case, a
-- user ticking "Target and Focus Frames" inside Edit Mode self-targets via
-- Blizzard's own code and sees nothing; unticking reverts it.
--
-- Protected frames can't be touched in combat, so after a /reload during
-- combat the whole pass defers to PLAYER_REGEN_ENABLED.
-- ============================================================================
local ADDON, ns = ...

local hiddenParent = CreateFrame("Frame", nil, UIParent)
hiddenParent:SetAllPoints()
hiddenParent:Hide()

-- Protected frames that Blizzard code re-SetParent()ed while we were in
-- combat; re-reparented the moment combat drops.
local looseFrames = {}
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
watcher:SetScript("OnEvent", function()
    for frame in next, looseFrames do
        frame:SetParent(hiddenParent)
    end
    wipe(looseFrames)
end)

local function resetParent(self, parent)
    if parent ~= hiddenParent then
        if InCombatLockdown() and self:IsProtected() then
            looseFrames[self] = true
        else
            self:SetParent(hiddenParent)
        end
    end
end

-- Sub-widgets that register their own events.  Key spellings span the
-- 1.15.7/1.15.8 classic frames (lowercase, UnitFrame_Initialize) and the
-- 1.15.9+ / 2.5.6 modern ones (mixed case, mixins).
local CHILD_KEYS = {
    "healthbar", "healthBar", "HealthBar",
    "manabar", "ManaBar",
    "spellbar", "castBar",
    "powerBarAlt", "PowerBarAlt",
    "BuffFrame", "DebuffFrame", "totFrame",
}

-- Hide a frame and keep it hidden.  Reparenting is the primary mechanism;
-- the SetParent hook defends it.  doNotReparent is for frames whose position
-- and size are managed by a container we already reparented (pooled party
-- members, compact group members): reparenting those breaks the container's
-- layout math, and silencing their events is all that's needed.
local killed = {}
local function kill(frame, doNotReparent)
    if type(frame) == "string" then frame = _G[frame] end
    if not frame then return end
    if frame.UnregisterAllEvents then frame:UnregisterAllEvents() end
    frame:Hide()
    if not doNotReparent and frame.SetParent then
        frame:SetParent(hiddenParent)
        if not killed[frame] then
            hooksecurefunc(frame, "SetParent", resetParent)
        end
    end
    killed[frame] = true
    for i = 1, #CHILD_KEYS do
        local child = frame[CHILD_KEYS[i]]
        if child and child.UnregisterAllEvents then child:UnregisterAllEvents() end
    end
end
-- (the focus and boss frames hide the game's own the same way: Extras.lua)
ns.KillBlizzardFrame = kill

-- CompactPartyFrame ("raid-style party frames") is created lazily by
-- CompactPartyFrame_Generate on the 1.15.9+ client, so it may not exist at
-- our load time.  Members are named CompactPartyFrameMember1..5 (they each
-- register their own unit events via CompactUnitFrame) and are laid out by
-- the container, hence doNotReparent.
local function killCompactParty()
    if not CompactPartyFrame then return end
    kill(CompactPartyFrame)
    for i = 1, 5 do
        kill("CompactPartyFrameMember" .. i, true)
    end
end

local function disableAll()
    local b = ns.db.blizzard
    local f = ns.db.frames

    if b.player and f.player.enabled then
        -- TBC-era clients hang the shaman TotemFrame off PlayerFrame; lift it
        -- to UIParent first so totem timers survive PlayerFrame's burial.
        -- (Nil on Era - the vanilla gametype never loads it.)
        if TotemFrame then TotemFrame:SetParent(UIParent) end
        kill(PlayerFrame)
    end

    -- Player cast bar: a standalone frame (not a child of PlayerFrame), so
    -- hide it explicitly when ZacUF draws its own player castbar.
    -- CastingBarFrame is the 1.15.7/1.15.8 name, PlayerCastingBarFrame the
    -- 1.15.9+ / 2.5.6-era one (an Edit Mode system on a UIParent-managed
    -- template - the SetParent hook earns its keep here).
    if b.castbar and f.player.enabled and f.player.castbar then
        kill(CastingBarFrame)
        kill(PlayerCastingBarFrame)
    end

    if b.target and f.target.enabled then
        kill(TargetFrame)             -- kill() also silences its spellbar/ToT/aura children
        kill(TargetFrameToT, true)    -- legacy global ToT; child of TargetFrame, so no reparent
        kill(ComboFrame)              -- rogue/feral combo points ride on TargetFrame
    end

    if b.pet and f.pet.enabled then
        kill(PetFrame)
    end

    -- Party: traditional member frames (1.15.7/1.15.8), the modern
    -- PartyFrame container (1.15.9+ / 2.5.6-era UI, where the numbered
    -- globals no longer exist), and the compact party frame where present.
    if b.party and ns.db.party.enabled then
        for i = 1, 4 do
            kill(_G["PartyMemberFrame" .. i])
        end
        if PartyFrame then
            kill(PartyFrame)
            -- Pooled member frames register their own unit events; silence
            -- any that already exist.  Killing the container unregisters
            -- GROUP_ROSTER_UPDATE, so the pool never acquires new ones.
            local memberPool = PartyFrame.PartyMemberFramePool
            if memberPool and memberPool.EnumerateActive then
                for memberFrame in memberPool:EnumerateActive() do
                    kill(memberFrame, true)
                end
            end
        end
        if CompactPartyFrame then
            killCompactParty()
        elseif CompactPartyFrame_Generate then
            hooksecurefunc("CompactPartyFrame_Generate", killCompactParty)
        end
    end

    -- Raid: the compact raid manager + container.  Reparenting handles both
    -- clients; the UpdateShown hook covers the manager's own show logic
    -- (present on 1.15.8 and 2.5.6 alike) as belt-and-braces.
    if b.raid and ns.db.raid.enabled then
        kill(CompactRaidFrameManager)
        kill(CompactRaidFrameContainer)
        if CompactRaidFrameManager_UpdateShown then
            hooksecurefunc("CompactRaidFrameManager_UpdateShown", function()
                if not InCombatLockdown() and CompactRaidFrameManager then
                    CompactRaidFrameManager:Hide()
                end
            end)
        end
    end
end

function ns.DisableBlizzard()
    -- After a /reload during combat, protected frames can't be hidden yet;
    -- run the full pass the moment combat drops.
    if InCombatLockdown() then
        local waiter = CreateFrame("Frame")
        waiter:RegisterEvent("PLAYER_REGEN_ENABLED")
        waiter:SetScript("OnEvent", function(self)
            self:UnregisterAllEvents()
            disableAll()
        end)
        return
    end
    disableAll()
end
