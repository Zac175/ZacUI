-- Boot_Events - ADDON_LOADED / PLAYER_LOGIN, DB creation and migrations.
-- Part of ZacUI; load order is set by the TOC.

local ADDON_NAME, ns = ...

-- shared state from earlier ZacUI files
local ApplyAll = ns.ApplyAll
local ApplyAllMovers = ns.ApplyAllMovers
local DEFAULT_MODULES = ns.DEFAULT_MODULES
local LOD = ns.LOD
local MODULE_ORDER = ns.MODULE_ORDER
local Print = ns.Print
local ResolveFontPath = ns.ResolveFontPath
local ZUI = ns.ZUI

ZUI:RegisterEvent("ADDON_LOADED")
ZUI:RegisterEvent("PLAYER_LOGIN")
-- BLOCKED AND FORBIDDEN ACTIONS. Two reasons to watch for these.
--
-- The first is that Blizzard's popup is a lie: "This addon has been
-- disabled. You should install an updated version." Nothing has been
-- disabled and there is no updated version - one call was refused and
-- the rest of the addon carried on. Showing that to someone is worse
-- than useless, so it is dismissed for our own blocks only. Anybody
-- else's addon keeps its warning.
--
-- The second is the useful one. The message carries the NAME of the
-- function that was refused, and that name is the entire diagnosis -
-- chasing 'PlaceAuctionBid' took a round of guessing before an error
-- happened to include it. It goes to chat where it can be read.
ZUI:RegisterEvent("ADDON_ACTION_FORBIDDEN")
ZUI:RegisterEvent("ADDON_ACTION_BLOCKED")

-- ============================================================
-- WHICH POPUP WAS THAT
-- ============================================================
-- A popup reading "This addon has been disabled. You should install an
-- updated version." appears when posting an auction. It is NOT the
-- wording Blizzard uses for a blocked action - that one says "AddOn '%s'
-- has been blocked from an action only available to the Blizzard UI" -
-- so the handler above, which listens for exactly that event, never
-- fires and the popup is something else entirely.
--
-- Guessing which popup, from a screenshot, is how the button tray lost
-- four rounds. Every StaticPopup carries a KEY, and the key is the whole
-- answer, so this asks the client for it. Popups whose key looks like a
-- complaint about an addon are always reported; `/zui popupwatch` turns
-- on reporting for every popup, for when the interesting one is not
-- named the way anyone expects.
local SUSPICIOUS = { "FORBIDDEN", "BLOCK", "DISABL", "INCOMPAT", "OUT_OF_DATE",
                     "ADDON", "TAINT" }
ZUI.popupWatch = false

if type(StaticPopup_Show) == "function" then
    hooksecurefunc("StaticPopup_Show", function(which, arg1, arg2)
        local key = tostring(which)
        local interesting = ZUI.popupWatch
        if not interesting then
            local upper = key:upper()
            for _, needle in ipairs(SUSPICIOUS) do
                if upper:find(needle, 1, true) then interesting = true break end
            end
        end
        -- THE ONE WE ALREADY UNDERSTAND. Posting an auction on Classic
        -- Era goes through the legacy API, and the client answers with
        -- AUCTION_HOUSE_DEPRECATED - "This addon has been disabled. You
        -- should install an updated version." Nothing is disabled, the
        -- auction posts, and there is no newer API on this client to
        -- move to. Scoped by time to the post that caused it, so the
        -- same popup raised by anything else still gets through.
        -- DISMISSED AGAIN, AND THIS TIME ON EVIDENCE RATHER THAN THEORY.
        --
        -- The history is worth keeping because it is the whole lesson.
        -- This popup was originally hidden with a message asserting "your
        -- auction went up" - a claim nothing had checked. When posting
        -- turned out to be broken, hiding the dialog became a suspect:
        -- closing a dialog is not answering it, and it was plausible that
        -- the post was waiting on an answer this code was throwing away.
        -- So it was left alone.
        --
        -- Posting is now fixed, and the actual cause was a stack size the
        -- client could not build. The dialog appeared throughout, before
        -- and after, on posts that failed and posts that succeeded - which
        -- settles it: it is a notice, it gates nothing, and it can go.
        --
        -- What does NOT come back is the claim about the outcome. Whether
        -- the auction went up is reported by the code that watches the
        -- client say so, and nowhere else.
        if key == "AUCTION_HOUSE_DEPRECATED" and ns.AH and ns.AH.postedAt then
            local now = GetTime and GetTime() or 0
            if now - ns.AH.postedAt < 2 then
                if StaticPopup_Hide then StaticPopup_Hide(key) end
                if not ZUI._saidDeprecated then
                    ZUI._saidDeprecated = true
                    Print("hiding the client's 'addon has been disabled' popup "
                        .. "while you post - it is Classic Era complaining "
                        .. "about its own auction API, nothing is disabled, "
                        .. "and it says nothing about whether the auction "
                        .. "listed. Said once per session.")
                end
                return
            end
        end

        if not interesting then return end
        Print("|cffffd100popup|r " .. key
            .. (arg1 and ("  arg1=" .. tostring(arg1)) or "")
            .. (arg2 and ("  arg2=" .. tostring(arg2)) or ""))
    end)
end
-- ============================================================
-- WHERE THE TAINT IS
-- ============================================================
-- A blocked call on a frame ZacUI never names means a Blizzard function
-- wrote one of that frame's fields while ZacUI's code was somewhere on
-- the stack. The frame's own update path then reads that field - a raid
-- frame reads .unit before every Show/Hide - and the read poisons the
-- execution. The client knows which field: issecurevariable(t, k) returns
-- false plus the offending addon for a tainted key. So instead of asking
-- you to report a name, the reporter walks every key on the frame and
-- its parents and prints the ones that are ours. The tainted key names
-- the Blizzard function that wrote it, and that names the call of ours it
-- ran under.
local function TaintedKeys(t)
    if type(t) ~= "table" or type(issecurevariable) ~= "function" then return {} end
    local out = {}
    for k in pairs(t) do
        if type(k) == "string" then
            local secure, who = issecurevariable(t, k)
            if not secure then
                out[#out + 1] = k .. (who and (" (" .. tostring(who) .. ")") or "")
            end
        end
    end
    table.sort(out)
    return out
end

local function ProbeTaint(frameName)
    local f = _G[frameName]
    if type(f) ~= "table" then return end
    local depth = 0
    while f and depth < 4 do
        local keys = TaintedKeys(f)
        local name = (f.GetName and f:GetName()) or ("<unnamed " .. tostring(f) .. ">")
        if #keys > 0 then
            Print("  " .. name .. ": " .. table.concat(keys, ", "))
        else
            Print("  " .. name .. ": no tainted keys")
        end
        f = f.GetParent and f:GetParent() or nil
        depth = depth + 1
    end
end
ns.ProbeTaint = ProbeTaint

-- Once per distinct call per session. A raid join in combat blocks
-- forty frames at once and a two-line message for each is a wall that
-- hides the one line that matters.
local blockedSeen, blockedCount = {}, 0
ns.BlockedCount = function() return blockedCount end

ZUI:SetScript("OnEvent", function(self, event, arg1, arg2)
    if event == "ADDON_ACTION_FORBIDDEN" or event == "ADDON_ACTION_BLOCKED" then
        if arg1 ~= ADDON_NAME then return end
        if StaticPopup_Hide then
            StaticPopup_Hide("ADDON_ACTION_FORBIDDEN")
            StaticPopup_Hide("ADDON_ACTION_BLOCKED")
        end
        local fn = arg2 or "an unnamed function"
        blockedCount = blockedCount + 1
        -- Collapse CompactRaidFrame15:Hide() and CompactRaidFrame3:Show()
        -- into one report: the number is a slot, not a cause.
        local key = fn:gsub("%d+", "#")
        if blockedSeen[key] then return end
        blockedSeen[key] = true

        Print("|cffff9900the client refused|r " .. fn
            .. " |cffff9900- something of ours ran under Blizzard's own "
            .. "update of that frame.|r Tainted fields:")
        local frameName = fn:match("^([%w_]+):")
        if frameName then
            ProbeTaint(frameName)
        else
            Print("  (no frame in the name; /zacui taint <FrameName> to probe one)")
        end
        Print("Paste the lines above. Further blocks of this kind are "
            .. "counted, not printed (/zacui taint for the count).")
        return
    end

    if event == "ADDON_LOADED" then
        if arg1 == ADDON_NAME then
            -- FRESH INSTALL: the saved variables exactly as the client
            -- handed them over, before anything below fills them in. No
            -- table (or an empty one) means no character on this account
            -- has run ZacUI; only then is the first-run welcome offered
            -- (UI/Tutorial, read at PLAYER_LOGIN).
            ns.freshInstall = type(ZacUIDB) ~= "table" or next(ZacUIDB) == nil
            ZacUIDB = ZacUIDB or {}
            ZacUIDB.modules = ZacUIDB.modules or {}
            -- the third-party skins are gone (2026-10-28): their switches too
            for _, m in ipairs({ "baganator", "syndicator", "auctionator", "prat", "bartender4" }) do
                ZacUIDB.modules[m] = nil
            end
            for m, v in pairs(DEFAULT_MODULES) do
                if ZacUIDB.modules[m] == nil then
                    ZacUIDB.modules[m] = v
                end
            end
            ZacUIDB.font    = ZacUIDB.font or { name = nil, delta = 0, outline = nil }
            ZacUIDB.insets  = ZacUIDB.insets or {}
            ZacUIDB.lines   = ZacUIDB.lines or {}
            -- TWO colour stores, both kept: `colors` is the 1.x flat
            -- override a returning DB may still carry, `palette` is the
            -- structured one everything writes now. Core_Colors resolves
            -- palette first and falls through to colors, so an old DB
            -- keeps its look and a new write lands in the new store.
            ZacUIDB.colors  = ZacUIDB.colors or {}
            ZacUIDB.palette = ZacUIDB.palette or {}
            ZacUIDB.profiles = ZacUIDB.profiles or {}
            -- Per-CHARACTER, so one alt can wear a different profile from
            -- the rest of the account. Only ever holds the chosen name.
            ZacUICharDB = ZacUICharDB or {}

            -- MEDIA NAMES (2026-11-01): fonts and bar textures saved under
            -- the names of the media ZacUI used to carry are rewritten, once,
            -- to the names of ZacUI's own (Core_MediaNames) - the saved
            -- profiles too, so a profile worn below already has them.
            if (ZacUIDB.mediaRev or 0) < 1 and ns.MigrateMediaNames then
                pcall(ns.MigrateMediaNames, ZacUIDB)
                pcall(ns.MigrateMediaNames, ZacUICharDB)
                ZacUIDB.mediaRev = 1
            end

            -- THE PROFILE THIS CHARACTER WEARS, applied here and nowhere
            -- else. It has to run before ApplyAll reads ZacUIDB.modules at
            -- PLAYER_LOGIN, and after the DB exists - which is exactly
            -- this window. (Core_Profiles: first run on this build turns
            -- the live settings into "Default" so nothing changes.)
            if ns.Profiles and ns.Profiles.Login then
                local ok, name = pcall(ns.Profiles.Login)
                if ok and name then ZUI._autoProfile = name end
            end

            -- MODULE-DEFAULT MIGRATIONS: the nil-fill above only covers
            -- keys a DB has never seen. When a module ships that older
            -- revisions may have persisted as false (or a shipped
            -- default flips), the stored value wins silently and the
            -- module is invisible on every existing character - root
            -- cause #3 of the per-character styling bug. Bump the REV
            -- and list the modules to force back to shipped defaults.
            -- Mover storage + legacy migration: v1.3.1 stored the loot
            -- anchor as lootPos; the registry keys it under movers.
            ZacUIDB.movers = ZacUIDB.movers or {}
            if ZacUIDB.lootPos then
                ZacUIDB.movers.lootroll = ZacUIDB.lootPos
                ZacUIDB.lootPos = nil
            end

            -- PALETTE MIGRATION: the checkbox border shipped grey (0.4)
            -- for a while and old DBs persisted it, overriding today's
            -- black default forever. Reset ONLY an exact legacy value -
            -- a border someone actually picked is never touched.
            if not ZacUIDB.paletteRev or ZacUIDB.paletteRev < 2 then
                local cb = ZacUIDB.palette and ZacUIDB.palette.checkbox
                local bd = cb and cb.border
                if bd and math.abs((bd.r or 0) - 0.4) < 0.01
                    and math.abs((bd.g or 0) - 0.4) < 0.01
                    and math.abs((bd.b or 0) - 0.4) < 0.01 then
                    bd.r, bd.g, bd.b, bd.a = 0, 0, 0, 1
                end
                ZacUIDB.paletteRev = 2
            end

            -- NOTE for whoever adds the next module: you do not need a
            -- migration for it. The nil-fill above covers any key no DB
            -- has seen, and Profiles.Apply back-fills the same way after
            -- loading an older profile. A rev bump is only for when a
            -- module's shipped default CHANGES, where a stored value
            -- would otherwise win forever.
            local DEFAULTS_REV = 5
            local FORCE_DEFAULT_AT = {
                [2] = { "taxi", "readycheck" },
                [4] = { "lootroll" },
                [5] = { "inspect" },
                -- rev 3: defaults flipped to all-on; the formerly
                -- opt-in set gets one forced enable on old DBs. Turn
                -- any of them off afterwards and it stays off.
                [3] = { "character", "spellbook", "questlog", "friends",
                        "trade", "loot", "gossip", "options", "panels" },
            }
            local rev = ZacUIDB.defaultsRev or 1
            if rev < DEFAULTS_REV then
                for r = rev + 1, DEFAULTS_REV do
                    for _, m in ipairs(FORCE_DEFAULT_AT[r] or {}) do
                        ZacUIDB.modules[m] = DEFAULT_MODULES[m]
                    end
                end
                ZacUIDB.defaultsRev = DEFAULTS_REV
            end
            if ZacUIDB.modules.fonts then
                local fp = ResolveFontPath(ZacUIDB.font.name)
                if fp then
                    UNIT_NAME_FONT     = fp
                    DAMAGE_TEXT_FONT   = fp
                    STANDARD_TEXT_FONT = fp
                end
            end
        elseif LOD[arg1] then
            local fn = LOD[arg1]
            LOD[arg1] = nil
            local ok, err = pcall(fn)
            if not ok then Print(arg1 .. " skin failed: " .. tostring(err)) end
        end
    elseif event == "PLAYER_LOGIN" then
        local oldLoaded = _G.ReadycheckUIFrame ~= nil
        if not oldLoaded then
            local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
            if isLoaded then
                local ok, res = pcall(isLoaded, "ReadycheckUI")
                oldLoaded = ok and res and true or false
            end
        end
        if oldLoaded then
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cFFFF3333[ZacUI] OLD 'ReadycheckUI' ADDON DETECTED - delete the Interface\\\\AddOns\\\\ReadycheckUI folder and /reload.|r")
        end

        ApplyAll()
        ApplyAllMovers()
        -- Catches a module that was added to the run order but never given
        -- a home in the config sidebar - it would otherwise work perfectly
        -- and be impossible to find.
        if ns.AuditModules then ns.AuditModules() end
        -- FIRST RUN: offer to adopt settings from addons already installed.
        -- Deliberately here and not at ADDON_LOADED - another addon's saved
        -- variables only exist after its own ADDON_LOADED, and load order
        -- between two addons is not ours to control.
        if ns.FirstRunImport then pcall(ns.FirstRunImport) end
        local off = {}
        for _, m in ipairs(MODULE_ORDER) do
            if not ZacUIDB.modules[m] then off[#off + 1] = m end
        end
        if #off > 0 then
            Print("v" .. ZUI.VERSION .. " loaded - modules off: " .. table.concat(off, ", ")
                .. "  (/zacui <module> on)")
        else
            Print("v" .. ZUI.VERSION .. " loaded.")
        end
        if ZUI._autoProfile and ZUI._autoProfile ~= (ns.Profiles and ns.Profiles.DEFAULT_NAME) then
            Print("profile '" .. ZUI._autoProfile .. "' on this character.")
        end
    end
end)
