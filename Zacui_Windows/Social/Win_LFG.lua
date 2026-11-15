-- Win_LFG - ZacUI's Looking For Group window, laid over Era's group
-- finder (Blizzard_GroupFinder_VanillaStyle: LFGParentFrame with its
-- LFGListingFrame and LFGBrowseFrame pages).
-- Part of ZacUI; load order is set by the TOC.
--
-- Built on Win_Kit's cover, parented to LFGParentFrame, so it opens,
-- closes and takes the panel slot exactly when Blizzard's window does.
-- Two pages behind our own tabs, in Blizzard's order:
--
--   List group   category, the activities to list for (grouped, with
--                select-all per group, level ranges and lockout marks),
--                roles, new-player-friendly, the comment, List / Update /
--                Unlist.
--   Browse       category + activity filters, Search, a local search box
--                and Groups / Solo chips over the results; click selects,
--                right-click opens Blizzard-style actions; Whisper and
--                Invite work the way Blizzard's buttons do.
--
-- TAINT RULES THIS FILE KEEPS.
--   * Blizzard's LFG state is never written. Our own tables hold the
--     selection; C_LFGList is called directly, and only from click
--     handlers (Search / CreateListing / UpdateListing / RemoveListing
--     are restricted calls - a click is a hardware event). Blizzard's
--     LFGUtil_* helpers are NOT called: one memoises into a shared cache,
--     and our tainted writes there would ride into Blizzard's own code.
--   * The comment is Blizzard's edit box (LFGListingComment - stored as
--     a secure reference: the client reads the listing comment from it
--     and refuses SetText / paste from addons). The ScrollFrame is NOT a
--     protected frame (no secure template anywhere in it), so re-parenting
--     and anchoring it from addon code is allowed in or out of combat and
--     taints nothing the listing reads: the text is the player's typing,
--     read by the client, and the restricted calls are ours either way.
--     So it is MOVED into our page, never re-implemented, and handed back
--     when the window is turned off.
--   * If the client still refuses one of our LFG calls
--     (ADDON_ACTION_FORBIDDEN / _BLOCKED naming this addon), the window
--     steps aside for the session so Blizzard's own finder is usable.

local ADDON_NAME = ...
-- Zacui_Windows is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end
-- Not on every game version (Core_Flavor's feature table: Retail's group finder is the game's own window, skinned):
-- this window stands down here, before it makes a frame or a module.
if ns.FeatureOn and not ns.FeatureOn("win_lfg") then return end

-- shared state from earlier ZacUI files
local FLAT = ns.FLAT
local GetColor = ns.GetColor
local Kit = ns.Kit
local Modules = ns.Modules
local UI = ns.UI

local M, F = UI.M, UI.F

local LOD_NAME = "Blizzard_GroupFinder_VanillaStyle"
local HOME = LE_PARTY_CATEGORY_HOME or 1
local BROWSE_ROW_H = 34
local LIST_ROW_H = 20
local COMMENT_H = 54
-- The classic 384x512 shell: its art (and Blizzard's own hit rect,
-- right 30 / bottom 74) ends well inside the frame rectangle.
local DEFAULT_INSET = { l = 11, r = 32, t = 12, b = 74 }
-- WoW Forever's group finder (the same addon, its "modern style": a plain
-- 458x535 window, the three tabs down its right edge, a Who list page of
-- its own - LFGWhoListFrame). The window is the whole frame, so no art
-- margin; the side tabs are silenced like the bottom ones (ZacUI's own
-- tabs switch pages, and gain a Who tab); the Who page is covered by
-- ZacUI's Who window (Win_Social), which hangs on it.
local DEFAULT_INSET_MODERN = { l = 0, r = 0, t = 0, b = 0 }
local function ModernLFG()
    local f = _G.LFGParentFrame
    return f ~= nil and type(rawget(f, "WhoListingTab")) == "table"
end

local win, tabs, pageListing, pageBrowse, listBar, browseBar
local actList, resList
local catDD, npfCheck, roleTank, roleHeal, roleDps, roleDD, rolePoll
local soloRoles, groupRoles, actSearch, commentBox, autoNote
local postBtn, backBtn, listStatus
local bCatDD, bActDD, bSearchBtn, bSearch, chipGroups, chipSolo
local whisperBtn, inviteBtn, browseStatus
local page = "listing"
local blocked = false

-- ============================================================
-- SMALL HELPERS
-- ============================================================
local function Str(name, fallback)
    local v = _G[name]
    if type(v) == "string" and v ~= "" then return v end
    return fallback
end

local function Contains(t, v)
    if not t then return false end
    for i = 1, #t do if t[i] == v then return true end end
    return false
end

local function Enabled()
    return not blocked and ZacUIDB and ZacUIDB.modules and ZacUIDB.modules.lfgwin ~= false
end

local function ActInfo(id)
    return id and C_LFGList.GetActivityInfoTable(id) or nil
end

-- Blizzard prefers the short name, for consistency with its own lists.
local function ActName(info)
    if not info then return "" end
    if info.shortName and info.shortName ~= "" then return info.shortName end
    return info.fullName or ""
end

local function ActiveEntry()
    if C_LFGList.HasActiveEntryInfo() then return C_LFGList.GetActiveEntryInfo() end
    return nil
end

-- LFGListingUtil_CanEditListing, restated.
local function CanEdit()
    return not IsInGroup(HOME) or UnitIsGroupLeader("player", HOME)
end

local function NameLess(a, b)
    if strcmputf8i then return strcmputf8i(a or "", b or "") < 0 end
    return (a or "") < (b or "")
end

-- LFGUtil_GetFilteredActivities, restated without its cvar cache: the
-- suggested-level filter hides activities outside your level, except any
-- your current listing already includes.
local function FilteredActivities(categoryID, groupID)
    local list
    if groupID then
        list = C_LFGList.GetAvailableActivities(categoryID, groupID)
    else
        list = C_LFGList.GetAvailableActivities(categoryID)
    end
    list = list or {}
    if not GetCVarBool("disableSuggestedLevelActivityFilter") then
        local active = ActiveEntry()
        local level = UnitLevel("player")
        for i = #list, 1, -1 do
            local id = list[i]
            if not (active and Contains(active.activityIDs, id)) then
                local info = ActInfo(id)
                if info and ((info.minLevelSuggestion > 0 and info.minLevelSuggestion > level)
                    or (info.maxLevelSuggestion > 0 and info.maxLevelSuggestion < level)) then
                    table.remove(list, i)
                end
            end
        end
    end
    return list
end

local function SortGroups(ids)
    table.sort(ids, function(a, b)
        local na, oa = C_LFGList.GetActivityGroupInfo(a)
        local nb, ob = C_LFGList.GetActivityGroupInfo(b)
        if oa and ob and oa ~= ob then return oa < ob end
        if na and nb and na ~= nb then return NameLess(na, nb) end
        return a < b
    end)
end

-- LFGUtil_SortActivityIDs order (the browse filter menu).
local function SortActivities(ids)
    table.sort(ids, function(a, b)
        local ia, ib = ActInfo(a), ActInfo(b)
        if not (ia and ib) then return a < b end
        if ia.orderIndex ~= ib.orderIndex then return ia.orderIndex < ib.orderIndex end
        local na, nb = ActName(ia), ActName(ib)
        if na ~= nb then return NameLess(na, nb) end
        return a < b
    end)
end

-- The Listing page's own order (highest order index, then level band).
local function ListingLess(a, b)
    if a.orderIndex ~= b.orderIndex then return a.orderIndex > b.orderIndex end
    if a.maxLevel ~= b.maxLevel then
        if a.maxLevel == 0 or b.maxLevel == 0 then return a.maxLevel == 0 end
        return a.maxLevel > b.maxLevel
    end
    if a.minLevel ~= b.minLevel then return a.minLevel > b.minLevel end
    return NameLess(a.name, b.name)
end

local function LevelText(minL, maxL)
    if minL == maxL or maxL == 0 then
        if minL == 0 then return "" end
        return string.format(Str("LFD_LEVEL_FORMAT_SINGLE", "(%d)"), minL)
    end
    return string.format(Str("LFD_LEVEL_FORMAT_RANGE", "(%d - %d)"), minL, maxL)
end

-- Comments are strings the client may hand back in a protected form;
-- every touch goes through pcall so a refusal only costs the comment.
local function SafeLower(s)
    if type(s) ~= "string" then return nil end
    local ok, low = pcall(string.lower, s)
    return ok and low or nil
end

local function SetTextSafe(fs, s)
    if not pcall(fs.SetText, fs, s or "") then fs:SetText("") end
end

local function SetDropdownEnabled(dd, on)
    if on then dd:Enable() else dd:Disable() end
    -- _zDisabled keeps UI.Hover from lighting a dead dropdown gold.
    dd._zDisabled = (not on) or nil
    dd._zText._zPaintKey = on and "normal" or "disabled"
    dd._zText:_zPaint()
end

local function PlaySoundKit(key)
    if SOUNDKIT and SOUNDKIT[key] then PlaySound(SOUNDKIT[key]) end
end

-- Blizzard's leftovers go through Kit.Silence with QUIET: silenced once
-- (a repeat call leaves an already-faded piece alone) and only Frames lose
-- the mouse - textures and font strings just fade.
local QUIET = { once = true, framesOnly = true }

-- Children get levels above their parent explicitly: a reparented
-- frame's children are not guaranteed to follow it up, and an edit box
-- left below the cover's fill is an invisible edit box.
local function LevelTree(f, level, depth)
    depth = depth or 0
    if not f or depth > 4 or not f.SetFrameLevel then return end
    f:SetFrameLevel(math.min(level, 9000))
    for _, child in ipairs({ f:GetChildren() }) do
        LevelTree(child, level + 1, depth + 1)
    end
end

-- ============================================================
-- LISTING STATE
-- ============================================================
local L = {
    cat = nil,          -- category id being listed for
    sel = {},           -- activityID -> true
    collapsed = {},     -- activityGroupID -> true
    dirty = false,
    npf = false,
    query = "",
    saved = {},
    pending = false,    -- our own create/update/remove is in flight
}

local function SelectedIDs()
    local ids = {}
    for id, on in pairs(L.sel) do if on then ids[#ids + 1] = id end end
    return ids
end

local function SelectedCount()
    local n = 0
    for _, on in pairs(L.sel) do if on then n = n + 1 end end
    return n
end

local function CategoryInfo(cat)
    return cat and C_LFGList.GetLfgCategoryInfo(cat) or nil
end

-- Lockouts, as Blizzard's listing reads them for its warning icon.
local function FetchSaved()
    L.saved = {}
    local n = GetNumSavedInstances and GetNumSavedInstances() or 0
    for i = 1, n do
        local _, _, _, difficultyID, _, _, _, _, _, _, total, done, _, mapID = GetSavedInstanceInfo(i)
        local redirected
        if C_RaidLocks and C_RaidLocks.GetRedirectedDifficultyID and mapID then
            redirected = C_RaidLocks.GetRedirectedDifficultyID(mapID, difficultyID)
        end
        L.saved[#L.saved + 1] = {
            mapID = mapID, difficultyID = difficultyID, redirected = redirected,
            done = done or 0, total = total or 0,
        }
    end
end

local function LockFor(info)
    if not (info and info.mapID and info.difficultyID) then return nil end
    for _, s in ipairs(L.saved) do
        if s.mapID == info.mapID and s.done > 0 and s.total > 0 then
            if info.difficultyID == s.difficultyID
                or (s.redirected and s.redirected == info.redirectedDifficultyID) then
                return s
            end
        end
    end
    return nil
end

local function SetCategory(cat, fromEntry)
    L.cat = cat
    L.collapsed = {}
    if not fromEntry then wipe(L.sel) end
    if not cat then return end
    -- Blizzard folds away groups with nothing near your level when a
    -- category has more than one group.
    local groups = C_LFGList.GetAvailableActivityGroups(cat) or {}
    if #groups > 1 then
        local level = UnitLevel("player")
        for _, gid in ipairs(groups) do
            local suggested = false
            for _, id in ipairs(FilteredActivities(cat, gid)) do
                local info = ActInfo(id)
                if info and info.minLevelSuggestion <= level and level <= info.maxLevelSuggestion then
                    suggested = true
                    break
                end
            end
            if not suggested then L.collapsed[gid] = true end
        end
    end
    local ci = CategoryInfo(cat)
    if not fromEntry and not C_LFGList.HasActiveEntryInfo() and ci and ci.autoChooseActivity then
        for _, id in ipairs(FilteredActivities(cat)) do L.sel[id] = true end
    end
end

-- The listing always reflects the live entry (a leader's edit reaches
-- every member): category, activities, new-player flag.
local function LoadActiveEntry()
    local e = ActiveEntry()
    if not e then return false end
    local info = ActInfo(e.activityIDs and e.activityIDs[1])
    if info then SetCategory(info.categoryID, true) end
    wipe(L.sel)
    for _, id in ipairs(e.activityIDs or {}) do L.sel[id] = true end
    L.npf = e.newPlayerFriendly and true or false
    L.dirty = false
    return true
end

local function MarkDirty()
    if C_LFGList.HasActiveEntryInfo() then
        L.dirty = true
    else
        L.dirty = SelectedCount() > 0
    end
end

-- ============================================================
-- THE COMMENT (Blizzard's secure edit box, borrowed)
-- ============================================================
local function CommentFrame()
    local lf = _G.LFGListingFrame
    return lf and lf.ActivityView and lf.ActivityView.Comment or nil
end

local function CommentText()
    local c = CommentFrame()
    local eb = c and c.EditBox
    if not eb then return nil end
    local ok, t = pcall(eb.GetText, eb)
    if not ok then return nil end
    return t
end

-- Appended one by one: a nil in a table literal would end ipairs early
-- and leave the rest of the border art showing.
local function CommentArt(c)
    local t = {}
    for _, key in ipairs({ "TopLeftTex", "TopRightTex", "TopTex", "BottomLeftTex",
                           "BottomRightTex", "BottomTex", "LeftTex", "RightTex", "MiddleTex" }) do
        if c[key] then t[#t + 1] = c[key] end
    end
    return t
end

local borrowed = false
local hookedComment = false
local Queue   -- defined with the refresh below
local function PlaceComment()
    local c = CommentFrame()
    if not (c and commentBox) then return end
    -- The template hangs its scroll bar OUTSIDE the scroll frame's right
    -- edge (x +6, 16 wide): the right inset leaves room for it, or a long
    -- comment's bar would poke past the window.
    local RIGHT = 6 + 16 + 6
    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", commentBox, "TOPLEFT", 7, -6)
    c:SetPoint("BOTTOMRIGHT", commentBox, "BOTTOMRIGHT", -RIGHT, 5)
    local w = (commentBox:GetWidth() or 0) - 7 - RIGHT
    if w > 60 and c.EditBox then
        c.EditBox:SetWidth(w - 18)
        if c.EditBox.Instructions then c.EditBox.Instructions:SetWidth(w) end
    end
end

local function BorrowComment()
    local c = CommentFrame()
    if not (c and commentBox) then return end
    if not borrowed then
        if not pcall(c.SetParent, c, commentBox) then return end
        borrowed = true
        Kit.Silence(CommentArt(c), QUIET)
    end
    -- Typing only reaches Blizzard's own dirty flag. Ours needs it too:
    -- a comment-only edit must enable Update, and a mandatory comment
    -- must enable List as soon as there is one.
    if not hookedComment and c.EditBox then
        hookedComment = true
        c.EditBox:HookScript("OnTextChanged", function(_, userInput)
            if not borrowed then return end
            if userInput then L.dirty = true end
            if Queue then Queue() end
        end)
    end
    PlaceComment()
    LevelTree(c, commentBox:GetFrameLevel() + 2)
end

-- Back where Blizzard keeps it; its ActivityView re-lays it out on its
-- next show anyway, these are just its XML defaults.
local function ReturnComment()
    local c = CommentFrame()
    if not (c and borrowed) then return end
    borrowed = false
    local view = _G.LFGListingFrame.ActivityView
    c:SetParent(view)
    c:ClearAllPoints()
    c:SetPoint("BOTTOM", view, "BOTTOM", 0, 19)
    c:SetSize(285, 47)
    if c.EditBox then
        c.EditBox:SetWidth(285 - 18)
        if c.EditBox.Instructions then c.EditBox.Instructions:SetWidth(285) end
    end
    Kit.Unsilence(CommentArt(c), QUIET)
    LevelTree(c, view:GetFrameLevel() + 1)
end

-- What the box says and whether it can be typed in, per category - the
-- part of Blizzard's ActivityView OnShow that is about the comment.
local function SyncCommentMode()
    local c = CommentFrame()
    local eb = c and c.EditBox
    if not eb then return end
    local ci = CategoryInfo(L.cat)
    local secured = C_LFGList.IsPlayerAuthenticatedForLFG(L.cat)
    local hint
    if not secured then
        hint = Str("LFG_AUTHENTICATOR_DESCRIPTION_BOX", "An authenticator is required to add a comment.")
    elseif ci and ci.autoChooseActivity then
        hint = Str("DESCRIPTION_OF_YOUR_GROUP_MANDATORY", "Describe your group (required)")
    else
        hint = Str("DESCRIPTION_OF_YOUR_GROUP", "Describe your group")
    end
    if eb.Instructions then eb.Instructions:SetText(hint) end
    -- The box is security-restricted; if the client ever refuses this
    -- from an addon, the server still rejects an unauthenticated comment.
    if eb.SetEnabled then pcall(eb.SetEnabled, eb, secured and true or false) end
end

-- ============================================================
-- LISTING PAGE DATA
-- ============================================================
local function ActEntry(id, indent)
    local info = ActInfo(id)
    if not info then return nil end
    return {
        kind = "activity", id = id, indent = indent, info = info,
        name = ActName(info), orderIndex = info.orderIndex or 0,
        minLevel = info.minLevelSuggestion or 0, maxLevel = info.maxLevelSuggestion or 0,
        lock = LockFor(info),
    }
end

local function ListingRows()
    local rows = {}
    local cat = L.cat
    if not cat then return rows end
    local q = L.query

    -- Locked view (not the leader): just the live listing, read-only.
    if not CanEdit() then
        local e = ActiveEntry()
        if e then
            for _, id in ipairs(e.activityIDs or {}) do
                local a = ActEntry(id, 0)
                if a then a.readOnly = true; rows[#rows + 1] = a end
            end
        end
        return rows
    end

    local free = {}
    for _, id in ipairs(FilteredActivities(cat, 0)) do
        local a = ActEntry(id, 0)
        if a and Kit.Matches(q, a.name) then free[#free + 1] = a end
    end
    -- Blizzard's top level sorts loose activities by order index RISING
    -- (the group comparator), and only then by the activity rules.
    table.sort(free, function(a, b)
        if a.orderIndex ~= b.orderIndex then return a.orderIndex < b.orderIndex end
        return ListingLess(a, b)
    end)
    for _, a in ipairs(free) do rows[#rows + 1] = a end

    local groups = C_LFGList.GetAvailableActivityGroups(cat) or {}
    SortGroups(groups)
    local multi = #groups > 1
    for _, gid in ipairs(groups) do
        local acts = FilteredActivities(cat, gid)
        if #acts > 0 then
            local gname = C_LFGList.GetActivityGroupInfo(gid) or ""
            local nameHit = Kit.Matches(q, gname)
            local kids = {}
            for _, id in ipairs(acts) do
                local a = ActEntry(id, 1)
                if a and (nameHit or Kit.Matches(q, a.name)) then kids[#kids + 1] = a end
            end
            if #kids > 0 then
                table.sort(kids, ListingLess)
                -- A search opens every group it found something in.
                local folded = multi and q == "" and L.collapsed[gid]
                rows[#rows + 1] = {
                    kind = "group", id = gid, name = gname, multi = multi,
                    folded = folded, acts = acts,
                }
                if not folded then
                    for _, a in ipairs(kids) do rows[#rows + 1] = a end
                end
            end
        end
    end
    return rows
end

local function GroupState(acts)
    local any, all = false, true
    for _, id in ipairs(acts) do
        if L.sel[id] then any = true else all = false end
    end
    return any, all and #acts > 0
end

-- LFGListingMixin:UpdatePostButtonEnableState, restated. Returns
-- whether posting is possible and, if not, what to tell the player.
local function PostState()
    local active = C_LFGList.HasActiveEntryInfo()
    if not CanEdit() then
        return false, active and Str("LFG_LIST_ONLY_LEADER_UPDATE", "Only the group leader can update the listing.")
            or Str("LFG_LIST_ONLY_LEADER_CREATE", "Only the group leader can create a listing.")
    end
    local n = SelectedCount()
    local cap = Constants and Constants.LFGConstsExposed
        and Constants.LFGConstsExposed.GROUP_FINDER_MAX_ACTIVITY_CAPACITY
    if cap and n > cap then
        return false, Str("LFG_LIST_TOO_MANY_ACTIVITIES_SELECTED", "Too many activities selected.")
    end
    if not L.dirty or (not active and n == 0) then return false, nil end
    local ci = CategoryInfo(L.cat)
    if ci and ci.autoChooseActivity then
        local t = CommentText()
        if t == "" then return false, nil end
    end
    if IsInGroup(HOME) then
        local size = GetNumGroupMembers(HOME)
        local smallest = 0
        local fits = true
        for id, on in pairs(L.sel) do
            if on then
                local info = ActInfo(id)
                local maxP = info and info.maxNumPlayers or 0
                if maxP ~= 0 then
                    if maxP <= size then fits = false end
                    if smallest == 0 or maxP < smallest then smallest = maxP end
                end
            end
        end
        if not fits then
            return false, string.format(Str("LFG_LIST_TOO_MANY_FOR_ACTIVITY",
                "Your group is too large for an activity (max %d)."), smallest)
        end
    end
    return true, nil
end

local function SaveRoles()
    if not (C_LFGListRoles and C_LFGListRoles.SetRoles and roleTank) then return true end
    return C_LFGListRoles.SetRoles({
        tank = roleTank:GetChecked() and true or false,
        healer = roleHeal:GetChecked() and true or false,
        dps = roleDps:GetChecked() and true or false,
    })
end

local function LoadRoles()
    if not (roleTank and C_LFGListRoles and C_LFGListRoles.GetRoles) then return end
    local r = C_LFGListRoles.GetRoles()
    if not r then return end
    roleTank:SetChecked(r.tank)
    roleHeal:SetChecked(r.healer)
    roleDps:SetChecked(r.dps)
end

-- ============================================================
-- BROWSE STATE
-- ============================================================
local B = {
    cat = 0,          -- category searched / to search
    sel = "all",      -- "all", "self", "g<groupID>", or an activityID
    query = "",
    ids = {},         -- result IDs in Blizzard's sort order
    total = 0,
    entries = {},     -- resultID -> row table (kept, so selection survives)
    searching = false,
    failed = false,
    stale = false,
    token = 0,
}

local function SelfCategory()
    local e = ActiveEntry()
    if not e then return nil end
    for _, id in ipairs(e.activityIDs or {}) do
        if id ~= 0 then
            local info = ActInfo(id)
            if info then return info.categoryID end
        end
    end
    return nil
end

-- The activity IDs the current browse filter stands for.
local function FilterIDs()
    local cat = B.cat
    if not cat or cat <= 0 then return nil end
    local sel = B.sel
    if sel == "self" then
        local e = ActiveEntry()
        local ids = {}
        if e then
            for _, id in ipairs(e.activityIDs or {}) do
                local info = ActInfo(id)
                if info and info.categoryID == cat then ids[#ids + 1] = id end
            end
        end
        return ids
    elseif type(sel) == "string" and sel:sub(1, 1) == "g" then
        local gid = tonumber(sel:sub(2))
        local ids = {}
        for _, id in ipairs(FilteredActivities(cat)) do
            local info = ActInfo(id)
            if info and info.groupFinderActivityGroupID == gid then ids[#ids + 1] = id end
        end
        return ids
    elseif type(sel) == "number" then
        return { sel }
    end
    return nil
end

local function DoSearch()
    if B.searching or not B.cat or B.cat <= 0 then return end
    local ids = FilterIDs()
    if not ids or #ids == 0 then ids = FilteredActivities(B.cat) end
    C_LFGList.Search(B.cat, 0, 0, nil, false, nil, ids)
    B.searching, B.failed, B.stale = true, false, false
    -- Results normally arrive in well under a second. If they never do
    -- the Search button must not stay dead for the session.
    B.token = B.token + 1
    local token = B.token
    C_Timer.After(15, function()
        if B.searching and B.token == token then
            B.searching = false
            if ns.LFGWindow then ns.LFGWindow.Refresh() end
        end
    end)
end

-- The client's current result set (whoever searched), in Blizzard's own
-- order (self, matches, role fit, size, age). That sort is pure: it
-- orders the table we pass and writes nothing else.
local function FetchResults()
    local total, results = C_LFGList.GetFilteredSearchResults()
    B.total, B.ids = total or 0, results or {}
    if LFGBrowseUtil_SortSearchResults and #B.ids > 1 then
        pcall(LFGBrowseUtil_SortSearchResults, B.ids)
    end
end

local ROLE_ATLAS = {
    TANK = "groupfinder-icon-role-large-tank",
    HEALER = "groupfinder-icon-role-large-heal",
    DAMAGER = "groupfinder-icon-role-large-dps",
}

local function RoleIcon(role, size)
    local atlas = ROLE_ATLAS[role]
    if not atlas then return "" end
    return "|A:" .. atlas .. ":" .. (size or 14) .. ":" .. (size or 14) .. "|a"
end

local function MakeEntry(id, filterSet, active)
    local info = C_LFGList.GetSearchResultInfo(id)
    if not info then return nil end
    local e = B.entries[id]
    if not e then
        e = { id = id }
        B.entries[id] = e
    end
    local leader = C_LFGList.GetSearchResultLeaderInfo(id)
    e.numMembers = info.numMembers or 1
    e.solo = e.numMembers == 1
    e.delisted = info.isDelisted and true or false
    e.hasSelf = info.hasSelf and true or false
    e.npf = info.newPlayerFriendly and true or false
    e.comment = info.comment
    -- nil while the client is still fetching it: Whisper / Invite must
    -- not fire at a placeholder name.
    e.leader = info.leaderName or (leader and leader.name) or nil
    e.class = leader and leader.classFilename
    e.level = leader and leader.level
    e.soloRoles = nil
    if e.solo then
        local p = C_LFGList.GetSearchResultPlayerInfo(id, 1)
        if p then
            e.class = p.classFilename or e.class
            e.level = p.level or e.level
            e.soloRoles = p.lfgRoles
        end
    end
    e.counts = C_LFGList.GetSearchResultMemberCounts(id)

    -- Activity text and colour key, as Blizzard's row decides them.
    local matching = {}
    if active then
        for _, aid in ipairs(active.activityIDs or {}) do
            if Contains(info.activityIDs, aid) then matching[#matching + 1] = aid end
        end
    end
    local shown = (#matching > 0) and matching or (info.activityIDs or {})
    if e.hasSelf then
        e.actText = Str("LFG_SELF_LISTING", "Your listing")
        e.actKey = "green"
    elseif #shown == 1 then
        e.actText = ActName(ActInfo(shown[1]))
        e.actKey = (#matching > 0) and "blue" or "gray"
    else
        local fmt = (#matching > 0) and Str("LFGBROWSE_ACTIVITY_MATCHING_COUNT", "%d matching activities")
            or Str("LFGBROWSE_ACTIVITY_COUNT", "%d activities")
        e.actText = string.format(fmt, #shown)
        e.actKey = (#matching > 0) and "blue" or "gray"
    end
    e.activityIDs = info.activityIDs or {}
    e.matchesFilter = true
    if filterSet then
        e.matchesFilter = false
        for _, aid in ipairs(e.activityIDs) do
            if filterSet[aid] then e.matchesFilter = true break end
        end
    end
    -- Search text: leader and activity always; the comment only if the
    -- client lets us read it.
    local names = {}
    for _, aid in ipairs(e.activityIDs) do names[#names + 1] = ActName(ActInfo(aid)) end
    e.search = string.lower((e.leader or "") .. " " .. (e.actText or "") .. " " .. table.concat(names, " "))
    local lc = SafeLower(e.comment)
    if lc then e.search = e.search .. " " .. lc end
    return e
end

local function BrowseRows()
    local data = {}
    local active = ActiveEntry()
    local filterSet
    if B.sel ~= "all" then
        local ids = FilterIDs()
        if ids and #ids > 0 then
            filterSet = {}
            for _, id in ipairs(ids) do filterSet[id] = true end
        end
    end
    local wantGroups = chipGroups and chipGroups:IsOn()
    local wantSolo = chipSolo and chipSolo:IsOn()
    local seen = {}
    for _, id in ipairs(B.ids) do
        local e = MakeEntry(id, filterSet, active)
        if e then
            seen[id] = true
            local q = B.query
            if (q == "" or string.find(e.search, q, 1, true))
                and (not wantGroups or not e.solo)
                and (not wantSolo or e.solo) then
                data[#data + 1] = e
            end
        end
    end
    for id in pairs(B.entries) do
        if not seen[id] then B.entries[id] = nil end
    end
    return data
end

local function SelectedResult()
    local s = resList and resList.selected
    if s and C_LFGList.GetSearchResultInfo(s.id) then return s end
    return nil
end

-- LFGBrowseUtil_GetInviteActionForResult: only a lone player can be
-- invited, and only by someone allowed to invite.
local function CanInvite(e)
    if not e or not e.solo or e.delisted or not e.leader then return false end
    return not IsInGroup() or UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
end

local function Whisper(e)
    if not e or not e.leader then return end
    if ChatFrameUtil and ChatFrameUtil.SendTell then
        ChatFrameUtil.SendTell(e.leader)
    elseif ChatFrame_SendTell then
        ChatFrame_SendTell(e.leader)
    end
end

local function Invite(e)
    if not CanInvite(e) then return end
    if InviteToGroup then
        InviteToGroup(e.leader)
    elseif C_PartyInfo and C_PartyInfo.InviteUnit then
        C_PartyInfo.InviteUnit(e.leader)
    end
end

-- ============================================================
-- REFRESH
-- ============================================================
local function UpdateTabs()
    if not tabs then return end
    tabs:SetLabel("listing", C_LFGList.HasActiveEntryInfo()
        and Str("LFG_LIST_EDIT", "Edit Listing") or Str("LFG_LIST_TAB_1", "List Group"))
end

local function RefreshListing()
    local active = C_LFGList.HasActiveEntryInfo()
    local canEdit = CanEdit()
    local ci = CategoryInfo(L.cat)

    catDD:SetText(ci and ci.name or Str("CATEGORY", "Category"))
    SetDropdownEnabled(catDD, canEdit and not active)
    npfCheck:SetChecked(L.npf)
    npfCheck:SetEnabled(canEdit)
    npfCheck:SetAlpha(canEdit and 1 or 0.5)

    local grouped = IsInGroup(HOME)
    soloRoles:SetShown(not grouped)
    groupRoles:SetShown(grouped)
    if grouped then
        local role = UnitGroupRolesAssigned("player")
        roleDD:SetText(role == "TANK" and Str("TANK", "Tank") or role == "HEALER" and Str("HEALER", "Healer")
            or role == "DAMAGER" and Str("DAMAGER", "Damage") or Str("SELECT_YOUR_ROLE", "Select your role"))
        rolePoll:SetDisabled(not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")))
    end

    -- Auto-choose categories list for everything and only want the text.
    local auto = ci and ci.autoChooseActivity and canEdit
    actSearch:SetShown(not auto)
    autoNote:SetShown(auto and true or false)
    actList:SetShown(not auto)
    if not L.cat then
        actList:SetEmptyText(canEdit and "Choose a category to list your group for."
            or (active and Str("LFG_LIST_ONLY_LEADER_UPDATE", "Only the leader can update the listing.")
                or Str("LFG_LIST_ONLY_LEADER_CREATE", "Only the leader can create a listing.")))
    elseif not canEdit then
        actList:SetEmptyText(Str("LFG_LIST_ONLY_LEADER_CREATE", "Only the leader can create a listing."))
    else
        actList:SetEmptyText(L.query ~= "" and "Nothing matches." or "Nothing to list for at your level.")
    end
    if not auto then actList:SetData(ListingRows(), true) end
    commentBox:SetShown(L.cat ~= nil)
    if L.cat then SyncCommentMode() end

    local ok, err = PostState()
    postBtn:SetLabel(active and Str("LFG_POST_GROUP_UPDATE", "Update")
        or (IsInGroup(HOME) and Str("LFG_POST_GROUP_PARTY", "List Party") or Str("LFG_POST_GROUP_SOLO", "List Self")))
    postBtn:SetDisabled(not ok)
    postBtn._zErr = err
    backBtn:SetLabel(active and Str("LFG_LIST_UNLIST", "Unlist") or Str("BACK", "Back"))
    backBtn:SetDisabled(not (canEdit and (active or L.cat)))

    local n = SelectedCount()
    if err then
        listStatus:SetText(err)
        listStatus:SetTextColor(Kit.TextRGB("red"))
    else
        listStatus:SetText(L.cat and (n .. (n == 1 and " activity" or " activities")) or "")
        listStatus:SetTextColor(Kit.TextRGB("gray"))
    end
end

local function RefreshBrowse()
    local catText
    if B.sel == "self" then
        catText = Str("LFG_SELF_LISTING", "Your listing")
    elseif B.cat and B.cat > 0 then
        local ci = CategoryInfo(B.cat)
        catText = ci and ci.name
    end
    bCatDD:SetText(catText or Str("CATEGORY", "Category"))

    local actText = Str("LFGBROWSE_ACTIVITY_HEADER_DEFAULT", "All activities")
    if type(B.sel) == "number" then
        actText = ActName(ActInfo(B.sel))
    elseif type(B.sel) == "string" and B.sel:sub(1, 1) == "g" then
        actText = C_LFGList.GetActivityGroupInfo(tonumber(B.sel:sub(2))) or actText
    elseif B.sel == "self" then
        actText = Str("LFG_SELF_LISTING", "Your listing")
    end
    bActDD:SetText(actText)
    SetDropdownEnabled(bActDD, B.cat and B.cat > 0 and B.sel ~= "self")
    bSearchBtn:SetDisabled(B.searching or not (B.cat and B.cat > 0))

    local data = BrowseRows()
    if B.searching then
        resList:SetEmptyText(Str("SEARCHING", "Searching..."))
        data = {}
    elseif not B.cat or B.cat <= 0 then
        resList:SetEmptyText("Choose a category to search.")
    elseif B.failed then
        resList:SetEmptyText(Str("LFG_LIST_SEARCH_FAILED", "Search failed. Try again in a moment."))
    elseif B.total == 0 then
        resList:SetEmptyText(Str("LFG_LIST_NO_RESULTS_FOUND", "No groups found."))
    else
        resList:SetEmptyText("Nothing matches.")
    end
    -- A delisted group can no longer be picked.
    local s = resList.selected
    if s and (s.delisted or not B.entries[s.id]) then resList.selected = nil end
    resList:SetData(data, true)

    local shown, total = #data, #B.ids
    local txt
    if B.searching then
        txt = Str("SEARCHING", "Searching...")
    elseif B.stale then
        txt = "Filters changed - press Search"
    elseif shown ~= total then
        txt = shown .. " / " .. total
    else
        txt = total .. (total == 1 and " result" or " results")
    end
    browseStatus:SetText(txt)

    local sel = SelectedResult()
    whisperBtn:SetDisabled(not (sel and sel.leader))
    inviteBtn:SetDisabled(not CanInvite(sel))
end

local function Refresh()
    if not win or not win:IsVisible() then return end
    UpdateTabs()
    if page == "browse" then RefreshBrowse() else RefreshListing() end
end

Queue = Kit.Coalesce(Refresh, function() return win end)

local function ShowPage(key)
    page = (key == "browse") and "browse" or (key == "who" and ModernLFG()) and "who" or "listing"
    pageListing:SetShown(page == "listing")
    pageBrowse:SetShown(page == "browse")
    listBar:SetShown(page == "listing")
    browseBar:SetShown(page == "browse")
    if tabs then tabs:Paint(page) end
    -- Forever: Blizzard's own page follows (its Who list is a page of the
    -- window, covered by ZacUI's Who window; the listing's comment box
    -- lives on its listing page)
    if ModernLFG() and LFGParentFrame.selectedTab then
        local want = (page == "who") and 3 or (page == "browse") and 2 or 1
        if LFGParentFrame.selectedTab ~= want then
            local click = _G["LFGParentFrameTab" .. want .. "_OnClick"]
            if click then click() end
        end
    end
    if page == "listing" and RequestRaidInfo then RequestRaidInfo() end
    -- A hidden edit box can keep the keyboard; the borrowed comment must
    -- let go when its page does.
    if page ~= "listing" then
        local c = CommentFrame()
        if c and c.EditBox then c.EditBox:ClearFocus() end
    end
    UI.CloseAllDropdowns()
    Refresh()
end

-- ============================================================
-- TOOLTIPS
-- ============================================================
local ClassRGB = Kit.ClassRGB

-- The facts Blizzard's LFGBrowseSearchEntryTooltip shows, on GameTooltip.
local function ResultTooltip(row)
    local e = row.item
    if not e then return end
    local id = e.id
    local info = C_LFGList.GetSearchResultInfo(id)
    if not info then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    local lvl = Str("LEVEL_ABBR", "Lvl")
    local leader = C_LFGList.GetSearchResultLeaderInfo(id)
    local r, g, b = ClassRGB(leader and leader.classFilename or e.class)
    GameTooltip:AddLine((e.leader or "?") .. (e.level and ("  " .. lvl .. " " .. e.level) or ""), r, g, b)
    if info.isDelisted then
        GameTooltip:AddLine(Str("LFG_LIST_ENTRY_DELISTED", "This group is no longer listed."), Kit.TextRGB("red"))
    elseif info.newPlayerFriendly then
        GameTooltip:AddLine(Str("LFG_LIST_NEW_PLAYER_FRIENDLY_HEADER", "New player friendly"), Kit.TextRGB("green"))
    end
    local num = info.numMembers or 1
    if num > 1 and num <= 10 then
        for i = 1, num do
            local p = C_LFGList.GetSearchResultPlayerInfo(id, i)
            if p and p.name and not p.isLeader then
                local pr, pg, pb = ClassRGB(p.classFilename)
                GameTooltip:AddLine(RoleIcon(p.assignedRole, 12) .. " " .. p.name
                    .. (p.level and ("  " .. lvl .. " " .. p.level) or ""), pr, pg, pb)
            end
        end
    end
    if type(info.comment) == "string" then
        local ok, text = pcall(string.format, Str("LFG_LIST_COMMENT_FORMAT", "\"%s\""), info.comment)
        local okEmpty, empty = pcall(function() return info.comment == "" end)
        if ok and not (okEmpty and empty) then
            local c = GetColor("text", "gray")
            GameTooltip:AddLine(text, c.r, c.g, c.b, true)
        end
    end
    local counts = C_LFGList.GetSearchResultMemberCounts(id)
    local tc = GetColor("tooltip", "body")
    if num == 1 then
        GameTooltip:AddLine(string.format(Str("LFG_LIST_TOOLTIP_MEMBERS_SIMPLE", "Members: %d"), num), tc.r, tc.g, tc.b)
    elseif counts then
        GameTooltip:AddLine(string.format(Str("LFG_LIST_TOOLTIP_MEMBERS", "Members: %d (%d/%d/%d)"),
            num, counts.TANK or 0, counts.HEALER or 0, counts.DAMAGER or 0), tc.r, tc.g, tc.b)
    end
    local active = ActiveEntry()
    local ids = info.activityIDs or {}
    for _, aid in ipairs(ids) do
        local name = ActName(ActInfo(aid))
        if name ~= "" then
            if active and Contains(active.activityIDs, aid) then
                GameTooltip:AddLine(name, Kit.TextRGB("blue"))
            else
                GameTooltip:AddLine(name, Kit.TextRGB("gray"))
            end
        end
    end
    if #ids == 1 and C_LFGList.GetSearchResultEncounterInfo then
        local done = C_LFGList.GetSearchResultEncounterInfo(id)
        if done and #done > 0 then
            local t = GetColor("tooltip", "title")
            GameTooltip:AddLine(Str("LFG_LIST_BOSSES_DEFEATED", "Bosses defeated:"), t.r, t.g, t.b)
            for _, boss in ipairs(done) do GameTooltip:AddLine(boss, Kit.TextRGB("red")) end
        end
    end
    GameTooltip:Show()
end

local function ActivityTooltip(row)
    local a = row.item
    if not a then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    local t = GetColor("tooltip", "title")
    if a.kind == "group" then
        GameTooltip:AddLine(a.name, t.r, t.g, t.b)
        local c = GetColor("tooltip", "body")
        GameTooltip:AddLine("Click the box to pick every activity in this group"
            .. (a.multi and "; click the name to fold it." or "."), c.r, c.g, c.b, true)
    else
        GameTooltip:AddLine(a.info.fullName ~= "" and a.info.fullName or a.name, t.r, t.g, t.b)
        local lv = LevelText(a.minLevel, a.maxLevel)
        if lv ~= "" then GameTooltip:AddLine(lv, Kit.TextRGB("gray")) end
        if a.lock then
            GameTooltip:AddLine(string.format(Str("BOSSES_KILLED", "%d/%d bosses defeated"),
                a.lock.done, a.lock.total), Kit.TextRGB("red"))
        end
    end
    GameTooltip:Show()
end

-- ============================================================
-- LISTING ROWS
-- ============================================================
local function BuildActivityRow(row)
    row:RegisterForClicks("LeftButtonUp")
    local box = UI.Box(row, "checkbox", "bg", { borderCat = "checkbox", borderKey = "border" })
    box:SetSize(M.CHECK, M.CHECK)
    row.box = box
    local check = box:CreateTexture(nil, "ARTWORK")
    check._zui_own = true
    check:SetSize(M.CHECK - 6, M.CHECK - 6)
    check:SetPoint("CENTER")
    check:SetTexture(ns.TEX_CHECK)
    row.check = check
    -- "Some of this group" - a filled square rather than a tick.
    local part = box:CreateTexture(nil, "ARTWORK")
    part._zui_own = true
    part:SetSize(M.CHECK - 8, M.CHECK - 8)
    part:SetPoint("CENTER")
    part:SetTexture(FLAT)
    row.part = part

    row.fold = UI.Font(row, F.LABEL, { cat = "text", key = "gray", justify = "CENTER" })
    row.fold:SetWidth(12)

    row.level = UI.Font(row, F.SMALL, { justify = "RIGHT" })
    row.level:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.level:SetWordWrap(false)

    row.name = UI.Font(row, F.LABEL, { justify = "LEFT" })
    row.name:SetPoint("LEFT", box, "RIGHT", 6, 0)
    row.name:SetPoint("RIGHT", row.level, "LEFT", -6, 0)
    row.name:SetWordWrap(false)

    row:SetScript("OnEnter", ActivityTooltip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self)
        local a = self.item
        if not a or a.readOnly or not CanEdit() then return end
        if a.kind == "group" then
            if a.multi and not self.box:IsMouseOver() then
                L.collapsed[a.id] = not L.collapsed[a.id] or nil
            else
                local any = GroupState(a.acts)
                for _, id in ipairs(a.acts) do L.sel[id] = (not any) or nil end
                MarkDirty()
            end
        else
            L.sel[a.id] = (not L.sel[a.id]) or nil
            MarkDirty()
        end
        PlaySoundKit("IG_MAINMENU_OPTION_CHECKBOX_ON")
        Refresh()
    end)
end

local function UpdateActivityRow(row, a)
    local ck = UI.PaintTick and UI.PaintTick(row.check) or GetColor("checkbox", "check")
    if not UI.PaintTick then row.check:SetVertexColor(ck.r, ck.g, ck.b, 1) end
    row.part:SetVertexColor(ck.r, ck.g, ck.b, 0.9)
    row.box:ClearAllPoints()
    row.fold:ClearAllPoints()
    if a.kind == "group" then
        local any, all = GroupState(a.acts)
        row.check:SetShown(all)
        row.part:SetShown(any and not all)
        row.fold:SetShown(a.multi)
        row.fold:SetText(a.folded and "+" or "-")
        row.fold:SetPoint("LEFT", row, "LEFT", 2, 0)
        row.box:SetPoint("LEFT", row, "LEFT", a.multi and 16 or 4, 0)
        row.name:SetText(a.name)
        row.name._zPaintKey = "normal"
        row.name:_zPaint()
        local n = 0
        for _, id in ipairs(a.acts) do if L.sel[id] then n = n + 1 end end
        row.level:SetText(n > 0 and (n .. "/" .. #a.acts) or "")
        row.level:SetTextColor(Kit.TextRGB("gray"))
    else
        row.fold:Hide()
        row.part:Hide()
        row.check:SetShown(L.sel[a.id] and true or false)
        row.box:SetPoint("LEFT", row, "LEFT", 4 + (a.indent or 0) * 16, 0)
        row.box:SetAlpha(a.readOnly and 0.5 or 1)
        row.name:SetText(a.name)
        -- Blizzard's trivial / difficult shading for the level band.
        local level = UnitLevel("player")
        local key = "normal"
        if a.maxLevel ~= 0 and a.maxLevel < level then
            key = "gray"
        elseif a.minLevel ~= 0 and a.minLevel > level then
            key = "orange"
        end
        row.name._zPaintKey = key
        row.name:_zPaint()
        local lv = LevelText(a.minLevel, a.maxLevel)
        if a.lock then
            row.level:SetText(a.lock.done .. "/" .. a.lock.total .. "  " .. lv)
            row.level:SetTextColor(Kit.TextRGB("red"))
        else
            row.level:SetText(lv)
            row.level:SetTextColor(Kit.TextRGB(key))
        end
    end
    if a.kind == "group" then row.box:SetAlpha(1) end
end

-- ============================================================
-- BROWSE ROWS
-- ============================================================
local function ResultMenu(row, e)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    MenuUtil.CreateContextMenu(row, function(_, root)
        root:CreateTitle(e.leader or "")
        local w = root:CreateButton(Str("SEND_MESSAGE", "Send Message"), function() Whisper(e) end)
        w:SetEnabled(e.leader ~= nil)
        local i = root:CreateButton(Str("GROUP_INVITE", "Invite"), function() Invite(e) end)
        i:SetEnabled(CanInvite(e))
    end)
end

local function BuildResultRow(row)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    row.right = UI.Font(row, F.SMALL, { justify = "RIGHT" })
    row.right:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, -4)
    row.right:SetWordWrap(false)

    -- Name, then level / member count, then the new-player mark, left to
    -- right along the top line; widths are capped so the chain can never
    -- run under the role text on the right.
    row.name = UI.Font(row, F.LABEL, { justify = "LEFT" })
    row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 6, -3)
    row.name:SetWordWrap(false)
    row.lvl = UI.Font(row, F.SMALL, { cat = "text", key = "gray", justify = "LEFT" })
    row.lvl:SetPoint("BOTTOMLEFT", row.name, "BOTTOMRIGHT", 5, 0)
    row.lvl:SetWordWrap(false)
    row.npf = row:CreateTexture(nil, "ARTWORK")
    row.npf._zui_own = true
    row.npf:SetSize(14, 14)
    row.npf:SetPoint("LEFT", row.lvl, "RIGHT", 4, 0)
    if row.npf.SetAtlas then pcall(row.npf.SetAtlas, row.npf, "newplayerchat-chaticon-newcomer") end

    row.act = UI.Font(row, F.SMALL, { justify = "LEFT" })
    row.act:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 6, 4)
    row.act:SetWordWrap(false)
    row.comment = UI.Font(row, F.SMALL, { cat = "text", key = "gray", justify = "LEFT" })
    -- BOTTOMRIGHT, not RIGHT: a RIGHT anchor would put the line's middle
    -- on the row's middle and draw it into the name line above.
    row.comment:SetPoint("BOTTOMLEFT", row.act, "BOTTOMRIGHT", 8, 0)
    row.comment:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -4, 4)
    row.comment:SetWordWrap(false)

    row:SetScript("OnEnter", ResultTooltip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.UpdateTooltip = ResultTooltip
    row:SetScript("OnClick", function(self, button)
        local e = self.item
        -- Blizzard's rule: your own and delisted groups are not actionable.
        if not e or e.delisted or e.hasSelf then return end
        PlaySoundKit("IG_MAINMENU_OPTION_CHECKBOX_ON")
        if button == "RightButton" then
            resList:Select(e)
            ResultMenu(self, e)
        elseif resList.selected == e then
            resList:Select(nil)
        else
            resList:Select(e)
        end
        Refresh()
    end)
end

local function UpdateResultRow(row, e)
    local dim = e.delisted or not e.matchesFilter
    row.name:SetWidth(0)
    row.name:SetText(e.leader or "?")
    if dim then
        row.name:SetTextColor(Kit.TextRGB("disabled"))
    else
        row.name:SetTextColor(ClassRGB(e.class))
    end
    if (row.name:GetStringWidth() or 0) > 140 then row.name:SetWidth(140) end

    local lvl = Str("LEVEL_ABBR", "Lvl")
    if e.solo then
        row.lvl:SetText(e.level and (lvl .. " " .. e.level) or "")
    else
        row.lvl:SetText("(" .. e.numMembers .. ")")
    end
    row.lvl:SetTextColor(Kit.TextRGB(dim and "disabled" or "gray"))
    row.npf:SetShown(e.npf)
    row.npf:SetDesaturated(dim and true or false)

    local c = e.counts
    if e.solo then
        local r = e.soloRoles
        local bits = {}
        if r then
            if r.tank then bits[#bits + 1] = RoleIcon("TANK") end
            if r.healer then bits[#bits + 1] = RoleIcon("HEALER") end
            if r.dps then bits[#bits + 1] = RoleIcon("DAMAGER") end
        end
        row.right:SetText(table.concat(bits, " "))
    elseif c then
        row.right:SetText(RoleIcon("TANK") .. (c.TANK or 0) .. "  "
            .. RoleIcon("HEALER") .. (c.HEALER or 0) .. "  "
            .. RoleIcon("DAMAGER") .. (c.DAMAGER or 0))
    else
        row.right:SetText("")
    end
    row.right:SetTextColor(Kit.TextRGB(dim and "disabled" or "normal"))
    row.right:SetAlpha(dim and 0.5 or 1)

    row.act:SetWidth(0)
    row.act:SetText(e.actText or "")
    row.act:SetTextColor(Kit.TextRGB(dim and "disabled" or e.actKey))
    if (row.act:GetStringWidth() or 0) > 170 then row.act:SetWidth(170) end
    SetTextSafe(row.comment, type(e.comment) == "string" and e.comment or "")
    row.comment:SetTextColor(Kit.TextRGB(dim and "disabled" or "gray"))
end

-- ============================================================
-- BUILD
-- ============================================================
local function CategoryItems(forBrowse)
    local items = {}
    local cats = C_LFGList.GetAvailableCategories() or {}
    if forBrowse and C_LFGList.HasActiveEntryInfo() then
        items[#items + 1] = { value = "self", text = Str("LFG_SELF_LISTING", "Your listing") }
    end
    for _, cat in ipairs(cats) do
        if #FilteredActivities(cat) > 0 then
            local ci = CategoryInfo(cat)
            if ci then items[#items + 1] = { value = cat, text = ci.name } end
        end
    end
    if #items == 0 then
        items[1] = { value = 0, text = Str("LFG_TYPE_NONE", "None") }
    end
    return items
end

local function ActivityFilterItems()
    local items = { { value = "all", text = Str("LFGBROWSE_ACTIVITY_HEADER_DEFAULT", "All activities") } }
    if not B.cat or B.cat <= 0 then return items end
    local acts = FilteredActivities(B.cat)
    local byGroup, groups = {}, {}
    for _, id in ipairs(acts) do
        local info = ActInfo(id)
        local gid = info and info.groupFinderActivityGroupID or 0
        if not byGroup[gid] then
            byGroup[gid] = {}
            if gid ~= 0 then groups[#groups + 1] = gid end
        end
        table.insert(byGroup[gid], id)
    end
    if byGroup[0] then
        SortActivities(byGroup[0])
        for _, id in ipairs(byGroup[0]) do
            items[#items + 1] = { value = id, text = ActName(ActInfo(id)) }
        end
    end
    SortGroups(groups)
    for _, gid in ipairs(groups) do
        items[#items + 1] = { value = "g" .. gid, text = C_LFGList.GetActivityGroupInfo(gid) or "" }
        SortActivities(byGroup[gid])
        for _, id in ipairs(byGroup[gid]) do
            items[#items + 1] = { value = id, text = "    " .. ActName(ActInfo(id)) }
        end
    end
    return items
end

-- Every search here starts from a click (the dropdown row, the button):
-- the client only allows a search from real input.
local function SetBrowseCategory(val)
    if val == "self" then
        local cat = SelfCategory()
        if not cat then return end
        B.cat, B.sel = cat, "self"
    else
        B.cat, B.sel = tonumber(val) or 0, "all"
    end
    if B.searching then B.stale = true else DoSearch() end
    Refresh()
end

local function BuildListingPage()
    local p = pageListing

    catDD = UI.Dropdown(p, {
        width = 170,
        items = function() return CategoryItems(false) end,
        selectedValue = function() return L.cat end,
        onSelect = function(val)
            if not CanEdit() or C_LFGList.HasActiveEntryInfo() then return end
            val = tonumber(val)
            if not val or val == 0 then return end
            SetCategory(val, false)
            MarkDirty()
            PlaySoundKit("IG_MAINMENU_OPTION_CHECKBOX_ON")
            Refresh()
        end,
    })
    catDD:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)

    npfCheck = UI.Checkbox(p, "New player friendly", false, function(on)
        L.npf = on and true or false
        -- Blizzard remembers the choice for the next listing in this cvar.
        -- SETUP2: through ns.CVar (recorded; put back when the window is off)
        if ns.CVar then ns.CVar.Set("lfgNewPlayerFriendly", on and "1" or "0", "lfgwin")
        elseif SetCVar then SetCVar("lfgNewPlayerFriendly", on and "1" or "0") end
        PlaySoundKit(on and "IG_MAINMENU_OPTION_CHECKBOX_ON" or "IG_MAINMENU_OPTION_CHECKBOX_OFF")
        L.dirty = true
        Refresh()
    end, { tooltip = Str("LFG_LIST_NEW_PLAYER_FRIENDLY_TOOLTIP", "Welcome players new to the game.") })
    npfCheck:SetPoint("RIGHT", p, "TOPRIGHT", 0, -M.DROPDOWN_H / 2)

    local rowY = -(M.DROPDOWN_H + Kit.GAP)
    soloRoles = CreateFrame("Frame", nil, p)
    soloRoles:SetPoint("TOPLEFT", p, "TOPLEFT", 0, rowY)
    soloRoles:SetPoint("TOPRIGHT", p, "TOPRIGHT", 0, rowY)
    soloRoles:SetHeight(Kit.SEARCH_H)
    local label = UI.Font(soloRoles, F.SMALL, { cat = "text", key = "gray", text = "Roles:" })
    label:SetPoint("LEFT", 0, 0)
    local function RoleBox(role, text, anchor)
        local cb
        cb = UI.Checkbox(soloRoles, text, false, function()
            PlaySoundKit("IG_MAINMENU_OPTION_CHECKBOX_ON")
            -- SetRoles refuses a role the class cannot take: put it back,
            -- then take whatever the client actually holds.
            if SaveRoles() == false then
                cb:SetChecked(not cb:GetChecked())
                LoadRoles()
            end
        end)
        cb:SetPoint("LEFT", anchor, "RIGHT", 12, 0)
        cb:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local desc = _G["ROLE_DESCRIPTION_" .. role]
            local t = GetColor("tooltip", "title")
            GameTooltip:AddLine(text, t.r, t.g, t.b)
            if desc then
                local c = GetColor("tooltip", "body")
                GameTooltip:AddLine(desc, c.r, c.g, c.b, true)
            end
            if UnitGetAvailableRoles then
                local canT, canH, canD = UnitGetAvailableRoles("player")
                if (role == "TANK" and not canT) or (role == "HEALER" and not canH)
                    or (role == "DAMAGER" and not canD) then
                    GameTooltip:AddLine(Str("CLASS_ROLE_NOT_RECOMMENDED", "Your class is not recommended for this role."),
                        Kit.TextRGB("red"))
                end
            end
            GameTooltip:Show()
        end)
        cb:HookScript("OnLeave", function() GameTooltip:Hide() end)
        return cb
    end
    roleTank = RoleBox("TANK", Str("TANK", "Tank"), label)
    roleHeal = RoleBox("HEALER", Str("HEALER", "Healer"), roleTank)
    roleDps = RoleBox("DAMAGER", Str("DAMAGER", "Damage"), roleHeal)

    groupRoles = CreateFrame("Frame", nil, p)
    groupRoles:SetPoint("TOPLEFT", p, "TOPLEFT", 0, rowY)
    groupRoles:SetPoint("TOPRIGHT", p, "TOPRIGHT", 0, rowY)
    groupRoles:SetHeight(Kit.SEARCH_H)
    roleDD = UI.Dropdown(groupRoles, {
        width = 140,
        items = function()
            return {
                { value = "TANK", text = Str("TANK", "Tank") },
                { value = "HEALER", text = Str("HEALER", "Healer") },
                { value = "DAMAGER", text = Str("DAMAGER", "Damage") },
            }
        end,
        selectedValue = function() return UnitGroupRolesAssigned("player") end,
        onSelect = function(val)
            if UnitSetRole then UnitSetRole("player", val) end
            Queue()
        end,
    })
    roleDD:SetPoint("LEFT", groupRoles, "LEFT", 0, 0)
    rolePoll = UI.Button(groupRoles, Str("ROLE_POLL", "Role Check"), { width = 100, height = Kit.SEARCH_H })
    rolePoll:SetPoint("RIGHT", groupRoles, "RIGHT", 0, 0)
    rolePoll:SetScript("OnClick", function()
        PlaySoundKit("IG_MAINMENU_OPTION_CHECKBOX_ON")
        if InitiateRolePoll then InitiateRolePoll() end
    end)
    rolePoll:HookScript("OnEnter", function(self)
        if self._zDisabled then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(Str("ERR_LFG_ROLE_CHECK_ONLY_LEADER", "Only the leader can start a role check."),
                Kit.TextRGB("red"))
            GameTooltip:Show()
        end
    end)
    rolePoll:HookScript("OnLeave", function() GameTooltip:Hide() end)
    rolePoll:SetMotionScriptsWhileDisabled(true)

    local searchY = rowY - Kit.SEARCH_H - Kit.GAP
    actSearch = Kit.Search(p, 100, function(text)
        L.query = Kit.NormalizeQuery(text)
        Refresh()
    end, "Filter activities")
    actSearch:SetPoint("TOPLEFT", p, "TOPLEFT", 0, searchY)
    actSearch:SetPoint("TOPRIGHT", p, "TOPRIGHT", 0, searchY)

    commentBox = UI.Box(p, "ui", "elementBg")
    commentBox:SetHeight(COMMENT_H)
    commentBox:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 0, 0)
    commentBox:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 0)
    commentBox:SetScript("OnSizeChanged", PlaceComment)

    actList = Kit.List(p, {
        rowHeight = LIST_ROW_H,
        build = BuildActivityRow,
        update = UpdateActivityRow,
        wheelStep = 3,
    })
    actList:SetPoint("TOPLEFT", p, "TOPLEFT", 0, searchY - Kit.SEARCH_H - Kit.GAP)
    actList:SetPoint("BOTTOMRIGHT", commentBox, "TOPRIGHT", 0, Kit.GAP)

    autoNote = UI.Font(p, F.LABEL, { cat = "text", key = "gray", justify = "CENTER" })
    autoNote:SetPoint("TOPLEFT", actList, "TOPLEFT", 8, -24)
    autoNote:SetPoint("TOPRIGHT", actList, "TOPRIGHT", -8, -24)
    autoNote:SetText("Every activity in this category is included - describe your group below.")
    autoNote:Hide()

    -- Footer strip for this page.
    backBtn = UI.Button(listBar, Str("BACK", "Back"), { width = 90, height = 24 })
    postBtn = UI.Button(listBar, Str("LFG_POST_GROUP_SOLO", "List Self"), { width = 100, height = 24 })
    postBtn:SetPoint("RIGHT", listBar, "RIGHT", -6, 0)
    backBtn:SetPoint("RIGHT", postBtn, "LEFT", -Kit.GAP, 0)
    postBtn:SetMotionScriptsWhileDisabled(true)
    postBtn:HookScript("OnEnter", function(self)
        if self._zErr then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self._zErr, Kit.TextRGB("red"))
            GameTooltip:Show()
        end
    end)
    postBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)

    listStatus = UI.Font(listBar, F.SMALL, { cat = "text", key = "gray", justify = "LEFT" })
    listStatus:SetPoint("LEFT", listBar, "LEFT", 8, 0)
    listStatus:SetPoint("RIGHT", backBtn, "LEFT", -Kit.GAP, 0)
    listStatus:SetWordWrap(false)

    -- LFGListingMixin:CreateOrUpdateListing, from our own selection.
    postBtn:SetScript("OnClick", function()
        if not PostState() then return end
        PlaySoundKit("IG_MAINMENU_OPTION_CHECKBOX_ON")
        local ids = SelectedIDs()
        if C_LFGList.HasActiveEntryInfo() then
            L.pending = true
            if #ids > 0 then
                C_LFGList.UpdateListing({ activityIDs = ids, newPlayerFriendly = L.npf })
                SaveRoles()
            else
                C_LFGList.RemoveListing()
            end
        elseif #ids > 0 then
            L.pending = true
            C_LFGList.CreateListing({ activityIDs = ids, newPlayerFriendly = L.npf })
            SaveRoles()
        end
    end)
    -- Back (no listing): start over. Unlist (listed): take it down.
    backBtn:SetScript("OnClick", function()
        PlaySoundKit("IG_MAINMENU_OPTION_CHECKBOX_ON")
        if C_LFGList.HasActiveEntryInfo() then
            if not CanEdit() then return end
            L.pending = true
            C_LFGList.RemoveListing()
        else
            SetCategory(nil, false)
            L.dirty = false
            if C_LFGList.ClearCreationTextFields then C_LFGList.ClearCreationTextFields() end
            local c = CommentFrame()
            if c and c.EditBox then c.EditBox:ClearFocus() end
            Refresh()
        end
    end)
end

local function BuildBrowsePage()
    local p = pageBrowse

    bSearchBtn = UI.Button(p, Str("SEARCH", "Search"), { width = 70, height = M.DROPDOWN_H })
    bSearchBtn:SetPoint("TOPRIGHT", p, "TOPRIGHT", 0, 0)
    UI.Tooltip(bSearchBtn, Str("LFG_LIST_SEARCH_AGAIN", "Search Again"),
        "Search the group finder with the filters on the left.")
    bSearchBtn:SetScript("OnClick", function()
        PlaySoundKit("IG_MAINMENU_OPTION_CHECKBOX_ON")
        DoSearch()
        Refresh()
    end)

    bCatDD = UI.Dropdown(p, {
        width = 120,
        items = function() return CategoryItems(true) end,
        selectedValue = function() return B.sel == "self" and "self" or B.cat end,
        onSelect = function(val)
            if val == 0 then return end
            SetBrowseCategory(val)
        end,
    })
    bCatDD:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)

    bActDD = UI.Dropdown(p, {
        width = 130,
        items = ActivityFilterItems,
        selectedValue = function() return B.sel end,
        onSelect = function(val)
            B.sel = val
            if B.searching then B.stale = true else DoSearch() end
            Refresh()
        end,
    })
    bActDD:SetPoint("LEFT", bCatDD, "RIGHT", Kit.GAP, 0)
    bActDD:SetPoint("RIGHT", bSearchBtn, "LEFT", -Kit.GAP, 0)

    local rowY = -(M.DROPDOWN_H + Kit.GAP)
    chipSolo = Kit.Chip(p, "Solo", false, function(on)
        if on and chipGroups:IsOn() then chipGroups:SetOn(false) end
        Refresh()
    end, "Only players listed on their own.")
    chipSolo:SetPoint("TOPRIGHT", p, "TOPRIGHT", 0, rowY)
    chipGroups = Kit.Chip(p, "Groups", false, function(on)
        if on and chipSolo:IsOn() then chipSolo:SetOn(false) end
        Refresh()
    end, "Only groups of two or more.")
    chipGroups:SetPoint("RIGHT", chipSolo, "LEFT", -4, 0)

    bSearch = Kit.Search(p, 100, function(text)
        B.query = Kit.NormalizeQuery(text)
        Refresh()
    end, "Filter by name, activity or comment")
    bSearch:SetPoint("TOPLEFT", p, "TOPLEFT", 0, rowY)
    bSearch:SetPoint("RIGHT", chipGroups, "LEFT", -Kit.GAP, 0)

    resList = Kit.List(p, {
        rowHeight = BROWSE_ROW_H,
        build = BuildResultRow,
        update = UpdateResultRow,
        empty = "",
    })
    resList:SetPoint("TOPLEFT", p, "TOPLEFT", 0, rowY - Kit.SEARCH_H - Kit.GAP)
    resList:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 0)

    inviteBtn = UI.Button(browseBar, Str("GROUP_INVITE", "Invite"), { width = 80, height = 24 })
    inviteBtn:SetPoint("RIGHT", browseBar, "RIGHT", -6, 0)
    inviteBtn:SetScript("OnClick", function() Invite(SelectedResult()) end)
    whisperBtn = UI.Button(browseBar, Str("SEND_MESSAGE", "Send Message"), { width = 100, height = 24 })
    whisperBtn:SetPoint("RIGHT", inviteBtn, "LEFT", -Kit.GAP, 0)
    whisperBtn:SetScript("OnClick", function() Whisper(SelectedResult()) end)

    browseStatus = UI.Font(browseBar, F.SMALL, { cat = "text", key = "gray", justify = "LEFT" })
    browseStatus:SetPoint("LEFT", browseBar, "LEFT", 8, 0)
    browseStatus:SetPoint("RIGHT", whisperBtn, "LEFT", -Kit.GAP, 0)
    browseStatus:SetWordWrap(false)
end

local function Inset()
    local o = ZacUIDB and ZacUIDB.insets and ZacUIDB.insets.LFGParentFrame
    return o or (ModernLFG() and DEFAULT_INSET_MODERN) or DEFAULT_INSET
end

-- Everything of Blizzard's that hangs outside the cover: the bottom
-- tabs, the X, the eye portrait, and the skin's own panel (sized to the
-- whole 384x512 rectangle, it would frame the cover in dark margin).
local function Leftovers()
    local f = LFGParentFrame
    local t = {}
    local function Add(x) if x then t[#t + 1] = x end end
    for _, child in ipairs({ f:GetChildren() }) do
        if child ~= win and child.IsObjectType and child:IsObjectType("Button") then Add(child) end
    end
    Add(_G.LFGParentFramePortrait)
    -- Forever: the tabs down the right edge, and whatever of its three
    -- pages draws above the cover (the Who page's title bar and frame
    -- art, its search box and button in the HIGH strata)
    for _, key in ipairs({ "ListingTab", "BrowsingTab", "WhoListingTab" }) do
        local t = rawget(f, key)
        if type(t) == "table" then Add(t) end
    end
    if ModernLFG() and win then
        for _, pg in ipairs({ _G.LFGListingFrame, _G.LFGBrowseFrame, _G.LFGWhoListFrame }) do
            if pg then Kit.AboveCover(pg, win, t) end
        end
    end
    Add(f._zui_panel)
    Add(f._zui_artbg)
    Add(f._zui_band)
    return t
end

local function Build()
    if win then return win end
    win = Kit.Cover(LFGParentFrame, {
        name = "ZacUILFGWindow",
        title = Str("LFG_TITLE", "Looking For Group"),
        insetName = "LFGParentFrame",
        onClose = function() HideUIPanel(LFGParentFrame) end,
    })
    win.Reanchor = function() ns.AnchorPanel(win, LFGParentFrame, Inset()) end
    win.Reanchor()
    win:SetIcon("Interface\\LFGFrame\\UI-LFG-PORTRAIT")

    local tabList = {
        { key = "listing", label = Str("LFG_LIST_TAB_1", "List Group") },
        { key = "browse",  label = Str("LFG_LIST_TAB_2", "Browse Groups") },
    }
    if ModernLFG() then tabList[#tabList + 1] = { key = "who", label = Str("LFG_LIST_TAB_3", WHO or "Who") } end
    tabs = Kit.Tabs(win, tabList, function(key) ShowPage(key) end)
    tabs:SetPoint("TOPLEFT", win, "TOPLEFT", Kit.PAD, win.top)
    tabs:SetPoint("TOPRIGHT", win, "TOPRIGHT", -Kit.PAD, win.top)

    win.footer = Kit.Footer(win, Kit.FOOTER_H + 4)
    listBar = CreateFrame("Frame", nil, win.footer)
    listBar:SetAllPoints()
    browseBar = CreateFrame("Frame", nil, win.footer)
    browseBar:SetAllPoints()

    local top = win.top - Kit.TAB_H - Kit.GAP
    win.pageTop = top                    -- (the Who window hangs under the tabs here)
    local function Page()
        local p = CreateFrame("Frame", nil, win)
        p:SetPoint("TOPLEFT", win, "TOPLEFT", Kit.PAD, top)
        p:SetPoint("BOTTOMRIGHT", win.footer, "TOPRIGHT", -Kit.PAD + 1, Kit.GAP)
        return p
    end
    pageListing = Page()
    pageBrowse = Page()
    BuildListingPage()
    BuildBrowsePage()

    win:HookScript("OnShow", function()
        if C_LFGList.HasActiveEntryInfo() then
            LoadActiveEntry()
        elseif GetCVarBool then
            -- Blizzard's checkbox OnShow: a new listing starts from the
            -- remembered new-player-friendly choice.
            L.npf = GetCVarBool("lfgNewPlayerFriendly") and true or false
        end
        -- Blizzard may have searched while we were closed (its listing
        -- search at load); pick up whatever the client holds.
        if not B.searching then FetchResults() end
        LoadRoles()
        if RequestRaidInfo then RequestRaidInfo() end
        BorrowComment()
        ShowPage(page)
    end)
    win:HookScript("OnHide", function()
        UI.CloseAllDropdowns()
        local c = CommentFrame()
        if c and c.EditBox then c.EditBox:ClearFocus() end
    end)
    return win
end

-- ============================================================
-- EVENTS
-- ============================================================
local function OnEvent(_, event, ...)
    if event == "LFG_LIST_SEARCH_RESULTS_RECEIVED" or event == "LFG_LIST_SEARCH_FAILED" then
        B.searching = false
        B.failed = event == "LFG_LIST_SEARCH_FAILED"
        FetchResults()
        Queue()
    elseif event == "LFG_LIST_SEARCH_RESULT_UPDATED" then
        Queue()
    elseif event == "LFG_LIST_ACTIVE_ENTRY_UPDATE" then
        local createdNew = ...
        if C_LFGList.HasActiveEntryInfo() then
            LoadActiveEntry()
            -- A brand-new listing gets Blizzard's own sound and search;
            -- an edit we made gets the sound here.
            if L.pending and not createdNew then PlaySoundKit("PVP_ENTER_QUEUE") end
        else
            if L.pending then PlaySoundKit("LFG_DENIED") end
            MarkDirty()
        end
        L.pending = false
        Queue()
    elseif event == "GROUP_LEFT" then
        local category = ...
        if category == HOME and not C_LFGList.HasActiveEntryInfo() then SetCategory(nil, false) end
        Queue()
    elseif event == "LFG_LIST_AVAILABILITY_UPDATE" then
        if not C_LFGList.HasActiveEntryInfo() then SetCategory(nil, false) else LoadActiveEntry() end
        Queue()
    elseif event == "LFG_LIST_ROLE_UPDATE" then
        LoadRoles()
    elseif event == "UPDATE_INSTANCE_INFO" then
        FetchSaved()
        Queue()
    elseif event == "CVAR_UPDATE" then
        local name = ...
        if name == "disableSuggestedLevelActivityFilter" then Queue() end
    elseif event == "ADDON_ACTION_FORBIDDEN" or event == "ADDON_ACTION_BLOCKED" then
        local addon, fn = ...
        -- Once only: later refusals must not re-print or re-apply.
        if not blocked and addon == ADDON_NAME and type(fn) == "string"
            and (fn:find("LFG") or fn:find("Listing") or fn:find("Search")) then
            blocked = true
            if ns.Print then
                ns.Print("the client refused a group-finder call from ZacUI; Blizzard's group finder is back for this session.")
            end
            if ns.LFGWindow then ns.LFGWindow.Apply() end
        end
    else
        Queue()
    end
end

local function Apply()
    if not LFGParentFrame then return end
    if Enabled() then
        Build()
        win.Reanchor()
        win:Show()
        Kit.Silence(Leftovers(), QUIET)
        if LFGParentFrame:IsShown() then
            BorrowComment()
            Refresh()
        end
    elseif win then
        win:Hide()
        Kit.Unsilence(Leftovers(), QUIET)
        ReturnComment()
    end
end

-- ============================================================
-- MODULE
-- ============================================================
local function Setup()
    if ns._zLFGSetup or not LFGParentFrame or not LFGListingFrame or not LFGBrowseFrame then return end
    ns._zLFGSetup = true
    Apply()
    LFGParentFrame:HookScript("OnShow", function()
        Apply()
    end)
    -- Follow Blizzard's page when Blizzard picks one (keybinds, the
    -- minimap eye, the switch to Browse after a new listing).
    LFGListingFrame:HookScript("OnShow", function()
        if win and win:IsShown() and page ~= "listing" then ShowPage("listing") end
    end)
    LFGBrowseFrame:HookScript("OnShow", function()
        if win and win:IsShown() and page ~= "browse" then ShowPage("browse") end
    end)
    if ModernLFG() and _G.LFGWhoListFrame then
        _G.LFGWhoListFrame:HookScript("OnShow", function()
            if win and win:IsShown() and page ~= "who" then ShowPage("who") end
        end)
    end
    -- Blizzard's ActivityView re-lays out the comment every time it
    -- shows; while it is ours, put it straight back.
    local view = LFGListingFrame.ActivityView
    if view then
        view:HookScript("OnShow", function()
            -- It also re-sets the box's hint / enabled state for ITS
            -- category; the queued refresh puts ours back.
            if borrowed then PlaceComment() Queue() end
        end)
    end
    -- Blizzard searches the new listing's activities itself; show that
    -- search under the matching filter.
    if LFGBrowseFrame.SearchActiveEntry then
        hooksecurefunc(LFGBrowseFrame, "SearchActiveEntry", function()
            local cat = SelfCategory()
            if cat then
                B.cat, B.sel = cat, "self"
                B.searching = LFGBrowseFrame.searching and true or false
                B.failed = false
                if win and win:IsShown() and page ~= "browse" then ShowPage("browse") end
                Queue()
            end
        end)
    end

    local ev = CreateFrame("Frame", nil, LFGParentFrame)
    for _, e in ipairs({
        "LFG_LIST_SEARCH_RESULTS_RECEIVED", "LFG_LIST_SEARCH_FAILED",
        "LFG_LIST_SEARCH_RESULT_UPDATED", "LFG_LIST_ACTIVE_ENTRY_UPDATE",
        "LFG_LIST_AVAILABILITY_UPDATE", "LFG_LIST_ROLE_UPDATE",
        "GROUP_ROSTER_UPDATE", "GROUP_LEFT", "PARTY_LEADER_CHANGED",
        "PLAYER_ROLES_ASSIGNED", "UPDATE_INSTANCE_INFO", "CVAR_UPDATE",
        "ADDON_ACTION_FORBIDDEN", "ADDON_ACTION_BLOCKED",
    }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    ev:SetScript("OnEvent", OnEvent)
    FetchSaved()
end

-- Blizzard_GroupFinder_VanillaStyle is load-on-demand and the "misc"
-- skin already holds ns.RegisterLoD's one slot for it, so this watches
-- ADDON_LOADED itself. A frame late, so the skin has run first.
local function WhenLoaded(fn)
    local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    if isLoaded and isLoaded(LOD_NAME) then
        C_Timer.After(0, fn)
        return
    end
    local watch = CreateFrame("Frame")
    watch:RegisterEvent("ADDON_LOADED")
    watch:SetScript("OnEvent", function(self, _, name)
        if name ~= LOD_NAME then return end
        self:UnregisterEvent("ADDON_LOADED")
        C_Timer.After(0, function()
            local ok, err = pcall(fn)
            if not ok and ns.Print then ns.Print(LOD_NAME .. " window failed: " .. tostring(err)) end
        end)
    end)
end

Modules.lfgwin = function()
    if ns._zLFGWin or not C_LFGList then return end
    ns._zLFGWin = true
    WhenLoaded(Setup)
end

-- shared with later ZacUI files
ns.LFGWindow = { Refresh = function() Queue() end, Apply = Apply }
