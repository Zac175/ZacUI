-- Blz_Sweep - the game's own windows restyled IN PLACE, by what they are
-- made of, not window by window.
-- Part of ZacUI; load order is set by the TOC (before the Blz_* window
-- files that call it).
--
-- WHY (2026-11-15, Zac: "back to individually skinning things ... we need a
-- better way to do this"; his answer that night: restyle in place, one
-- engine). The modern client builds its windows from a small set of shared
-- templates and one family of art per kind of thing: a list header is the
-- same bar picture on the Skills, Statistics and Currency pages, a hovered
-- row the same highlight, a divider the same line. A rule per PIECE OF ART
-- therefore styles every window that uses it, including ones nobody has
-- opened yet; a window's own file only names the window.
--
-- The game's window keeps doing all the work: nothing here builds a
-- replacement, reads the game's data or calls its functions. It only
-- changes how pieces of art look:
--   gone   decoration (a parchment background, a carved frame, row
--          stripes): faded out, and kept faded if the game shows it again
--   wash   a hover / selected highlight: the same region, as a flat white
--          wash
--   band   a list header's bar: faded out, and the header gets ZacUI's
--          flat backing
--   line   a divider: the same region, as a one-pixel hairline
--   mono   a small state button (the + / - of a list header, a sub header's
--          red arrow): kept, with its colour taken out and ZacUI's text
--          colour put in - the shape still says open / closed
--   dark   a bar's carved backing: the same region, as ZacUI's dark fill
-- Icons, portraits, models, bars' fills and anything no rule names are left
-- exactly as the game drew them.
--
-- CARE. Only SetAlpha, SetColorTexture, SetHeight / SetWidth on textures and
-- ZacUI's own backing: never Show / Hide / SetParent / EnableMouse on the
-- game's frames, never a script set on them (HookScript and hooksecurefunc
-- only). What was done is remembered in weak side tables, not on the
-- game's frames. A forbidden frame is never touched; a frame another addon
-- put in the window (ZacUI's own included) is skipped with everything
-- under it. Each page is swept under pcall: one page failing leaves the
-- others. Runs when a page is first swept, when it shows, and for each
-- list row as the list hands it out - never per frame.
--
--   ns.Sweep.RULES                 { pattern (lower case, plain), treatment }
--   ns.Sweep.Rule(pattern, how)    add one (a window's file may)
--   ns.Sweep.Tree(frame, depth, rules)   every rule, on every texture under a
--                                  frame (rules: the page's own, looked at first)
--   ns.Sweep.Rows(scrollBox, rules) ...and on each row it hands out, from now on
--   ns.Sweep.Page(frame, opts)     a whole page: Tree, its lists' rows, its
--                                  scroll bars, again whenever it shows
--                                  (opts: depth, rules, bars = false, after)
--   ns.Sweep.Pages(names)          Page for each named frame that exists
--   ns.Sweep.done                  what was treated (weak; for /zui and tests)

local ADDON_NAME, ns = ...

local Sweep = {}
ns.Sweep = Sweep

local done = setmetatable({}, { __mode = "k" })     -- texture -> treatment it got
local held = setmetatable({}, { __mode = "k" })     -- texture -> true: kept faded
local backed = setmetatable({}, { __mode = "k" })   -- frame -> true: has ZacUI's flat backing
local paged = setmetatable({}, { __mode = "k" })    -- frame -> opts: a swept page
local rowed = setmetatable({}, { __mode = "k" })    -- scroll box -> true: its rows are swept
Sweep.done = done
Sweep.DEPTH = 7

-- ------------------------------------------------------------
-- THE RULES. First match wins; a pattern is found anywhere in the art's
-- name (atlas name or file path, lower case, no magic characters).
-- Names: the wow-ui-source forever branch (Blizzard_UIPanels_Game/Camelot/
-- CharacterFrame.xml, SkillsFrame.xml, Blizzard_Statistics/Camelot,
-- Blizzard_TokenUI/Camelot) and the shared templates.
-- ------------------------------------------------------------
Sweep.RULES = {
    -- list rows: the hover / selected highlight (three pieces across a row)
    { "charactercreate-customize-dropdown-linemouseover", "wash" },
    -- list headers: the bar behind a category's name (its highlight copy is
    -- an additive layer of the same picture: a wash)
    { "common-button-list-collapseexpand", "band" },
    { "ui-character-info-title", "band" },
    -- dividers
    { "ui-character-info-scrollline", "line" },
    -- the character window's page backgrounds, stat stripes and inner frames
    { "ui-character-info-general-bg", "gone" },
    { "ui-character-info-stat-bg", "gone" },
    { "ui-character-info-stat-stonebg", "gone" },
    { "ui-character-info-line-bounce", "gone" },
    { "ui-character-info-itemlevel-bounce", "gone" },
    { "common-insideframe", "gone" },
    { "common-framedivider", "gone" },
    -- the character window's gear slots: the bronze ring round each (ZacUI's
    -- flat slot border is the classifier's / Blz_Character's) and the model's
    -- carved inner frame. (The scene behind the model and the dark veil over
    -- it stay the game's: with the veil gone the scene was a bright grey
    -- photograph behind the slots - Zac, 2026-11-16, "half assed".)
    { "ui-character-info-gearslot", "gone" },
    { "char-paperdoll-", "gone" },
    -- the small tabs over the stats pane (the ring round each icon; the
    -- selected one's ring is a wash) and the outfit cards (the more
    -- particular names first: the first match wins)
    { "ui-character-info-stattab-selected", "wash" },
    { "ui-character-info-stattab", "gone" },
    { "ui-character-info-outfitcard-hover", "wash" },
    { "ui-character-info-outfitcard-selected", "wash" },
    { "ui-character-info-outfitcard", "dark" },
    { "ui-character-info-outfiticon-frame", "gone" },
    -- list state buttons
    { "common-button-list-plus", "mono" },
    { "common-button-list-minus", "mono" },
    { "campaign_headericon_", "mono" },
    -- a bar's backing
    { "common-stat-bar-bg", "dark" },
}
function Sweep.Rule(pattern, how)
    if type(pattern) ~= "string" or type(how) ~= "string" then return end
    Sweep.RULES[#Sweep.RULES + 1] = { pattern:lower(), how }
end

-- the art a texture wears: its atlas name, else its file path (lower case)
local function ArtOf(tex)
    local a = tex.GetAtlas and tex:GetAtlas()
    if type(a) == "string" and a ~= "" then return a:lower() end
    -- (2026-11-16, Zac's Forever character window: the rock strip and the
    -- inspect model's carved frame still there. On the client GetTexture
    -- answers a file's NUMBER, so a rule that names a file never matched;
    -- the file's path is asked for by its own call.)
    if tex.GetTextureFilePath then
        local ok, path = pcall(tex.GetTextureFilePath, tex)
        if ok and type(path) == "string" and path ~= "" then return path:lower() end
    end
    local t = tex.GetTexture and tex:GetTexture()
    if type(t) == "string" and t ~= "" then
        -- (the test client names an atlas "atlas:<name>")
        return (t:gsub("^atlas:", "")):lower()
    end
    return nil
end
-- (a page may bring rules of its own - opts.rules - looked at first: art
-- that is decoration on that page and something else elsewhere)
local function RuleFor(art, extra)
    if extra then
        for _, rule in ipairs(extra) do
            if art:find(rule[1], 1, true) then return rule[2] end
        end
    end
    for _, rule in ipairs(Sweep.RULES) do
        if art:find(rule[1], 1, true) then return rule[2] end
    end
    return nil
end

-- kept faded: the game may hand a faded piece its alpha back (a row
-- re-used, a pane re-laid); it goes back to nothing
local function Hold(tex)
    if held[tex] then return end
    held[tex] = true
    if not hooksecurefunc or not tex.SetAlpha then return end
    local busy = false
    pcall(hooksecurefunc, tex, "SetAlpha", function(self, a)
        if busy or (done[self] ~= "gone" and done[self] ~= "band") then return end
        -- (WoW Forever can hand over an alpha it keeps secret: never compared)
        local secret = issecretvalue and issecretvalue(a)
        if not secret and a == 0 then return end
        busy = true
        self:SetAlpha(0)
        busy = false
    end)
end

local function Col(key)
    if ns.Col then
        local ok, c = pcall(ns.Col, key)
        if ok and type(c) == "table" then return c end
    end
    return { r = 0.12, g = 0.12, b = 0.12 }
end

-- ZacUI's flat backing on a header (the frame's own, marked as ZacUI's)
local function Back(frame)
    if backed[frame] or not frame.CreateTexture then return end
    backed[frame] = true
    -- (already given ZacUI's backing by its window's own file)
    if rawget(frame, "_zui_cbg") then return end
    local t = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    t._zui_own = true
    t:SetAllPoints(frame)
    local c = Col("elementBg")
    t:SetColorTexture(c.r, c.g, c.b, 0.9)
    -- the surface finish (Core_Finish): a header is a raised band - lit
    -- along its top, a dark line along its foot, a little of the grain
    if ns.Finish then ns.Finish.Dress(t, "band", { inset = 0 }) end
end

local function Treat(tex, how, owner)
    if how == "gone" then
        tex:SetAlpha(0)
        Hold(tex)
    elseif how == "band" then
        -- the header's highlight copy (an additive layer, or the HIGHLIGHT
        -- draw layer) is a hover: a wash, not a second bar
        local layer = tex.GetDrawLayer and tex:GetDrawLayer()
        local add = tex.GetBlendMode and tex:GetBlendMode() == "ADD"
        if layer == "HIGHLIGHT" or add then
            tex:SetColorTexture(1, 1, 1, 0.08)
            how = "wash"
        else
            tex:SetAlpha(0)
            Hold(tex)
            if owner then Back(owner) end
        end
    elseif how == "wash" then
        tex:SetColorTexture(1, 1, 1, 0.08)
    elseif how == "mono" then
        -- (the game swaps this texture's art as the header opens and shuts:
        -- a look set on the region stays through the swap)
        if tex.SetDesaturated then tex:SetDesaturated(true) end
        local c = Col("text")
        tex:SetVertexColor(c.r or 0.85, c.g or 0.85, c.b or 0.85, 1)
    elseif how == "dark" then
        local c = Col("elementBg")
        tex:SetColorTexture(c.r, c.g, c.b, 0.9)
    elseif how == "line" then
        local b = Col("border")
        tex:SetColorTexture(b.r, b.g, b.b, 1)
        -- one physical pixel thick (Core_Pixel), along its long side
        local w, h = tex:GetWidth(), tex:GetHeight()
        local px = 1
        if ns.Pixel and ns.Pixel.One then
            local ok, one = pcall(ns.Pixel.One, owner or tex)
            if ok and type(one) == "number" and one > 0 then px = one end
        end
        local plain = type(w) == "number" and type(h) == "number"
            and not (issecretvalue and (issecretvalue(w) or issecretvalue(h)))
        if plain and h > w then tex:SetWidth(px) else tex:SetHeight(px) end
    end
    done[tex] = how
end

-- one named piece, by hand (a window's own file: a piece with no art name
-- to rule by - set from Lua, or a plain file)
function Sweep.Gone(tex)
    if type(tex) ~= "table" or not tex.SetAlpha or rawget(tex, "_zui_own") then return false end
    Treat(tex, "gone")
    return true
end
Sweep.Back = Back

-- a frame the game made (never another addon's, never ZacUI's own)
local function Ours(f) return rawget(f, "_zui_own") or rawget(f, "_zKitOwn") end
local function Skip(f)
    if type(f) ~= "table" then return true end
    if f.IsForbidden and f:IsForbidden() then return true end
    if Ours(f) then return true end
    -- a ZacUI cover sits in the game's window: its own business
    if ns.Kit and ns.Kit.covers then
        for _, c in ipairs(ns.Kit.covers) do if c == f then return true end end
    end
    return false
end

local function Regions(f, extra)
    if not f.GetRegions then return end
    for _, r in ipairs({ f:GetRegions() }) do
        if type(r) == "table" and not rawget(r, "_zui_own") and not done[r]
            and r.IsObjectType and r:IsObjectType("Texture") then
            local art = ArtOf(r)
            local how = art and RuleFor(art, extra)
            if how then Treat(r, how, f) end
        end
    end
    -- a button's state textures are not always among its regions
    for _, get in ipairs({ "GetHighlightTexture", "GetNormalTexture", "GetPushedTexture" }) do
        local t = f[get] and f[get](f)
        if type(t) == "table" and not done[t] and not rawget(t, "_zui_own") then
            local art = ArtOf(t)
            local how = art and RuleFor(art, extra)
            -- (only a state button's look: its normal / pushed art is never
            -- faded out or painted over - the button would be gone)
            if how and (get == "GetHighlightTexture" or how == "mono") then Treat(t, how, f) end
        end
    end
end

function Sweep.Tree(frame, depth, extra)
    if Skip(frame) then return end
    depth = depth or Sweep.DEPTH
    Regions(frame, extra)
    if depth <= 0 or not frame.GetChildren then return end
    for _, child in ipairs({ frame:GetChildren() }) do
        Sweep.Tree(child, depth - 1, extra)
    end
end

-- every row a list hands out, from now on (and the ones it has now)
function Sweep.Rows(box, extra)
    if type(box) ~= "table" or rowed[box] then return end
    if not (ScrollUtil and ScrollUtil.AddInitializedFrameCallback) then return end
    rowed[box] = true
    -- (the callback comes as (owner, row, data) on a new row and as
    -- (row, data) over the existing ones)
    local function Row(a, b)
        local row = (type(b) == "table" and b.GetRegions) and b or a
        if type(row) == "table" and row.GetRegions then pcall(Sweep.Tree, row, 3, extra) end
    end
    pcall(ScrollUtil.AddInitializedFrameCallback, box, Row, Sweep, true)
end

-- the lists under a frame: a modern ScrollBox has a ScrollTarget
local function Lists(frame, depth, out)
    if Skip(frame) then return out end
    if type(rawget(frame, "ScrollTarget")) == "table" then out[#out + 1] = frame end
    if depth > 0 and frame.GetChildren then
        for _, child in ipairs({ frame:GetChildren() }) do Lists(child, depth - 1, out) end
    end
    return out
end

local function SweepPage(frame)
    local opts = paged[frame]
    if not opts then return end
    Sweep.Tree(frame, opts.depth, opts.rules)
    for _, box in ipairs(Lists(frame, opts.depth or Sweep.DEPTH, {})) do Sweep.Rows(box, opts.rules) end
    if opts.bars ~= false and ns.SkinAllScrollBarsUnder then pcall(ns.SkinAllScrollBarsUnder, frame, 0) end
    -- (the page's OWN scroll bar: the walk above only looks at what a page's
    -- children carry - the stats list's bar is the swept page's own key)
    if opts.bars ~= false and ns.SkinAnyScrollBar then
        local sb = rawget(frame, "ScrollBar")
        if type(sb) == "table" then pcall(ns.SkinAnyScrollBar, sb) end
    end
    if type(opts.after) == "function" then pcall(opts.after, frame) end
end

-- a whole page (or window), now and whenever it shows
function Sweep.Page(frame, opts)
    if type(frame) ~= "table" or not frame.GetRegions or Skip(frame) then return false end
    if paged[frame] then return true end
    paged[frame] = type(opts) == "table" and opts or {}
    pcall(SweepPage, frame)
    if frame.HookScript then
        -- (pieces made on first open - a list's rows, a pane's rows - are
        -- there one frame after it shows)
        pcall(frame.HookScript, frame, "OnShow", function(self)
            pcall(SweepPage, self)
            if C_Timer and C_Timer.After then C_Timer.After(0, function() pcall(SweepPage, self) end) end
        end)
    end
    return true
end

function Sweep.Pages(names, opts)
    local n = 0
    for _, name in ipairs(names or {}) do
        local f = _G[name]
        if type(f) == "table" and Sweep.Page(f, opts) then n = n + 1 end
    end
    return n
end

-- ============================================================
-- BLIZZARD STYLE ON WOW FOREVER: THE QUEST TRACKER IN THE LIVE GAME'S ART
-- (2026-11-16)
-- ============================================================
-- Zac's Forever client under Blizzard style, 2026-11-15 23:06: "its still
-- mostly styled to match forever not the live client" - the tracker's
-- headers and buttons in WoW Forever's bronze beside live-art bars and
-- unit frames. The Forever client re-points the live game's art NAMES at
-- its own sheets, and still ships the live sheets (how ZacUI's bars and
-- unit frames already wear the live art there: AB_Core's AB.KitArt, the
-- unit frames' Kit.SetArt). The tracker is the game's own frame, so here
-- its pieces are re-pointed IN PLACE: a texture wearing one of the names
-- below is given the live sheet and that member's box. Every one of them
-- is the same size on both sheets (the client's own atlas listing), none
-- is tiled or sliced, so nothing is resized or re-anchored.
--   - only on the Forever client, only while the picked look is Blizzard
--     style and the tracker follows it (Look.StandsDown("tracker"));
--   - only where the client's own atlas is NOT already the live sheet, and
--     the live sheet is there (its file id asked of the client);
--   - texture calls only (SetTexture / SetTexCoord); what was done is kept
--     in weak side tables; the game setting an atlas again (a header
--     folding: its button's art) is followed by a post-hook on that one
--     texture; a texture given some other art gets its plain coords back;
--   - walked out of combat, a moment after login and after the quest log
--     changes (the event handlers only ask for the walk).
-- Boxes: left, right, top, bottom on the 1x sheet, then on the 2x sheet
-- where there is one - the Forever client's own records of the live
-- members (generated by tools/atlas_swapped.py from its atlas listing).
local LIVE_SHEETS = {
    { 5320671, "Interface\\QuestFrame\\QuestTracker" },
    { 5320674, "Interface\\QuestFrame\\QuestTracker2x" },
}
local LIVE_OWN_2X = 8268353           -- the client's own 2x sheet: it draws high-res
local LIVE = {
    ["ui-questtracker-lfg-eye"] = { 0.74609375, 0.81640625, 0.2421875, 0.421875, 0.7392578125, 0.8095703125, 0.236328125, 0.416015625 },
    ["ui-questtracker-lfg-eye-selected"] = { 0.8203125, 0.890625, 0.2421875, 0.421875, 0.8115234375, 0.8818359375, 0.236328125, 0.416015625 },
    ["ui-questtracker-objective-fail"] = { 0.919921875, 0.95703125, 0.00390625, 0.078125, 0.9150390625, 0.9521484375, 0.001953125, 0.076171875 },
    ["ui-questtracker-objective-nub"] = { 0.9609375, 0.998046875, 0.00390625, 0.078125, 0.9541015625, 0.9912109375, 0.001953125, 0.076171875 },
    ["ui-questtracker-objfx-barglow"] = { 0.55078125, 0.916015625, 0.00390625, 0.11328125, 0.5478515625, 0.9130859375, 0.001953125, 0.111328125 },
    ["ui-questtracker-objfx-shine"] = { 0.55078125, 0.8515625, 0.12109375, 0.2109375 },
    ["ui-questtracker-objfx_lineglow"] = { 0.001953125, 0.7265625, 0.76953125, 0.79296875 },
    ["ui-questtracker-primary-objective-header"] = { 0.001953125, 0.587890625, 0.48046875, 0.63671875, 0.0009765625, 0.5869140625, 0.470703125, 0.626953125 },
    ["ui-questtracker-progressbar-frame"] = { 0.001953125, 0.546875, 0.00390625, 0.234375, 0.0009765625, 0.5458984375, 0.001953125, 0.232421875 },
    ["ui-questtracker-progressbar-full-channel"] = { 0.001953125, 0.546875, 0.2421875, 0.47265625, 0.0009765625, 0.5458984375, 0.236328125, 0.466796875 },
    ["ui-questtracker-secondary-objective-header"] = { 0.001953125, 0.587890625, 0.64453125, 0.76171875, 0.0009765625, 0.5869140625, 0.630859375, 0.748046875 },
    ["ui-questtracker-tracker-check"] = { 0.85546875, 0.892578125, 0.12109375, 0.1953125, 0.8505859375, 0.8876953125, 0.115234375, 0.189453125 },
    ["ui-questtracker-tracker-check-glow"] = { 0.896484375, 0.93359375, 0.12109375, 0.1953125, 0.8896484375, 0.9267578125, 0.115234375, 0.189453125 },
    ["ui-questtrackerbutton-collapse-all"] = { 0.9375, 0.97265625, 0.12109375, 0.1953125, 0.9287109375, 0.9638671875, 0.115234375, 0.189453125 },
    ["ui-questtrackerbutton-collapse-all-pressed"] = { 0.89453125, 0.9296875, 0.2421875, 0.31640625, 0.8837890625, 0.9189453125, 0.236328125, 0.310546875 },
    ["ui-questtrackerbutton-expand-all"] = { 0.93359375, 0.96875, 0.2421875, 0.31640625, 0.8837890625, 0.9189453125, 0.314453125, 0.388671875 },
    ["ui-questtrackerbutton-expand-all-pressed"] = { 0.89453125, 0.9296875, 0.32421875, 0.3984375, 0.8837890625, 0.9189453125, 0.392578125, 0.466796875 },
    ["ui-questtrackerbutton-filter"] = { 0.93359375, 0.96875, 0.32421875, 0.3984375, 0.9208984375, 0.9560546875, 0.236328125, 0.310546875 },
    ["ui-questtrackerbutton-filter-pressed"] = { 0.591796875, 0.626953125, 0.48046875, 0.5546875, 0.9580078125, 0.9931640625, 0.236328125, 0.310546875 },
    ["ui-questtrackerbutton-questitem-frame"] = { 0.55078125, 0.64453125, 0.2421875, 0.4296875, 0.5478515625, 0.6416015625, 0.236328125, 0.423828125 },
    ["ui-questtrackerbutton-questitem-frame-glow"] = { 0.6484375, 0.7421875, 0.2421875, 0.4296875, 0.6435546875, 0.7373046875, 0.236328125, 0.423828125 },
    ["ui-questtrackerbutton-red-highlight"] = { 0.591796875, 0.626953125, 0.5625, 0.63671875, 0.9208984375, 0.9560546875, 0.314453125, 0.388671875 },
    ["ui-questtrackerbutton-secondary-collapse"] = { 0.89453125, 0.92578125, 0.40625, 0.46875, 0.9658203125, 0.9970703125, 0.115234375, 0.177734375 },
    ["ui-questtrackerbutton-secondary-collapse-pressed"] = { 0.93359375, 0.96484375, 0.40625, 0.46875, 0.9208984375, 0.9521484375, 0.392578125, 0.455078125 },
    ["ui-questtrackerbutton-secondary-expand"] = { 0.630859375, 0.662109375, 0.48046875, 0.54296875, 0.9580078125, 0.9892578125, 0.314453125, 0.376953125 },
    ["ui-questtrackerbutton-secondary-expand-pressed"] = { 0.630859375, 0.662109375, 0.55078125, 0.61328125, 0.9580078125, 0.9892578125, 0.380859375, 0.443359375 },
    ["ui-questtrackerbutton-yellow-highlight"] = { 0.666015625, 0.697265625, 0.48046875, 0.54296875, 0.5888671875, 0.6201171875, 0.470703125, 0.533203125 },
}
Sweep.LIVE = LIVE
local livePainted = setmetatable({}, { __mode = "k" })   -- texture -> the name it was painted for
local liveHooked = setmetatable({}, { __mode = "k" })
Sweep.livePainted = livePainted
local liveSheet = {}
local function LiveSheetHere(i)
    local v = liveSheet[i]
    if v == nil then
        v = false
        if type(GetFileIDFromPath) == "function" then
            local ok, id = pcall(GetFileIDFromPath, LIVE_SHEETS[i][2])
            v = (ok and id == LIVE_SHEETS[i][1]) and true or false
        end
        liveSheet[i] = v
    end
    return v
end
local function LiveBox(name)
    if type(name) ~= "string" or (issecretvalue and issecretvalue(name)) then return nil end
    local row = LIVE[name:lower()]
    if not row then return nil end
    local nf
    if C_Texture and C_Texture.GetAtlasInfo then
        local ok, info = pcall(C_Texture.GetAtlasInfo, name)
        if ok and type(info) == "table" then nf = info.file end
    end
    -- (the client draws the live art under this name itself: nothing to do)
    if nf == LIVE_SHEETS[1][1] or nf == LIVE_SHEETS[2][1] then return nil end
    local hi = (nf == LIVE_OWN_2X)
    if row[5] and (hi or not LiveSheetHere(1)) and LiveSheetHere(2) then
        return LIVE_SHEETS[2][1], row[5], row[6], row[7], row[8]
    end
    if LiveSheetHere(1) then return LIVE_SHEETS[1][1], row[1], row[2], row[3], row[4] end
    return nil
end
local liveBusy = false
local function LivePaint(tex, name)
    local file, l, r, t, b = LiveBox(name)
    if not file then
        -- (some other art now: the box of the last one must not crop it)
        if livePainted[tex] then
            livePainted[tex] = nil
            tex:SetTexCoord(0, 1, 0, 1)
        end
        return false
    end
    liveBusy = true
    tex:SetTexture(file)
    tex:SetTexCoord(l, r, t, b)
    liveBusy = false
    livePainted[tex] = name
    return true
end
local function LiveTexture(tex)
    if type(tex) ~= "table" or rawget(tex, "_zui_own") or not tex.GetAtlas then return end
    if not liveHooked[tex] then
        local a = tex:GetAtlas()
        if type(a) ~= "string" or (issecretvalue and issecretvalue(a)) or not LIVE[a:lower()] then return end
        liveHooked[tex] = true
        if hooksecurefunc and tex.SetAtlas then
            pcall(hooksecurefunc, tex, "SetAtlas", function(self, atlas)
                if liveBusy then return end
                pcall(LivePaint, self, atlas)
            end)
        end
        pcall(LivePaint, tex, a)
    end
end
-- every texture under a frame that wears one of the names (a button's state
-- textures too)
function Sweep.LiveTree(frame, depth)
    if type(frame) ~= "table" or (frame.IsForbidden and frame:IsForbidden()) or Ours(frame) then return end
    depth = depth or 8
    if frame.GetRegions then
        for _, r in ipairs({ frame:GetRegions() }) do
            if type(r) == "table" and r.IsObjectType and r:IsObjectType("Texture") then LiveTexture(r) end
        end
    end
    for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
        local t = frame[get] and frame[get](frame)
        if type(t) == "table" then LiveTexture(t) end
    end
    if depth > 0 and frame.GetChildren then
        for _, child in ipairs({ frame:GetChildren() }) do Sweep.LiveTree(child, depth - 1) end
    end
end
function Sweep.LiveTrackerOn()
    if _G.ZACUI_IS_FOREVER ~= true then return false end
    local L = ns.Look
    if not (L and L.Active and L.StandsDown and L.Settled and L.Settled()) then return false end
    return L.Active() == "blizzard" and L.StandsDown("tracker") and true or false
end
do
    local watch = CreateFrame("Frame")
    local queued = false
    local function Walk()
        queued = false
        if InCombatLockdown and InCombatLockdown() then return end
        local f = _G.ObjectiveTrackerFrame
        if type(f) == "table" then pcall(Sweep.LiveTree, f, 8) end
    end
    local function Ask()
        if queued then return end
        queued = true
        C_Timer.After(0.3, Walk)
    end
    Sweep.LiveTrackerAsk = Ask
    watch:RegisterEvent("PLAYER_LOGIN")
    watch:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_LOGIN" then
            -- (the look is settled a moment into the login)
            C_Timer.After(1, function()
                if not Sweep.LiveTrackerOn() then return end
                for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED",
                                     "ZONE_CHANGED_NEW_AREA", "PLAYER_REGEN_ENABLED" }) do
                    pcall(self.RegisterEvent, self, e)
                end
                Ask()
            end)
            return
        end
        Ask()
    end)
end
