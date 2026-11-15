-- QoL_DialogKeys - the keyboard for NPC talk (2026-10-31, Zac: "dialog
-- key keybinds for chat menus"). Part of ZacUI; load order is set by
-- the TOC.
--
-- While an NPC window is up:
--   * 1-9 pick that line of the list: a gossip option, a quest on offer
--     or in progress, a reward to choose. Each line wears its number.
--   * Enter (and Space, if ticked) does the obvious thing: Accept on a
--     quest's text, Continue on its progress page, Complete on its
--     rewards (once a reward is picked, when there is a choice), the
--     first line of a gossip or quest list.
--   * With no NPC window, Space (if ticked) presses the first button of
--     the popup on screen - enter the instance, accept a res - when that
--     popup takes no typing. Never a summon (2026-11-03). NEVER Release Spirit, quit,
--     delete / abandon / destroy / bind / unlearn popups (Zac 2026-11-02:
--     "why did i just auto release" - Space is jump, and it pressed Release
--     Spirit while he was dead).
-- Escape is never touched, and nothing is taken while a chat box or
-- any other text box has the keyboard. Keys that mean nothing here go
-- through to the game as usual (the action bar's 1-9 included).
--
-- HOW THE KEYS ARE READ. One frame, keyboard-enabled only while such a
-- window is shown, on top of everything: it sees each key first and
-- hands back (SetPropagateKeyboardInput) every key it does not use.
-- That call is off limits in combat on this client, so the frame
-- stands down for a fight (EnableKeyboard false) and comes back after;
-- a quest turned in mid-fight is clicked.

local ADDON_NAME = ...
local ns = _G.ZacUI
if not ns then return end

local QoL = ns.QoL
local UI = ns.UI

local DK = {}
QoL.DialogKeys = DK

local function Cfg()
    local d = QoL.DB()
    if type(d.dialogKeys) ~= "table" then
        d.dialogKeys = { enabled = true, space = true, popups = true, numbers = true }
    end
    return d.dialogKeys
end
DK.Cfg = Cfg

local function On()
    return ZacUIDB and ZacUIDB.modules and ZacUIDB.modules.qol and Cfg().enabled ~= false
end

-- ============================================================
-- THE LISTS: what 1-9 point at, top to bottom
-- ============================================================
local function Shown(f) return type(f) == "table" and f.IsShown and f:IsShown() and f:IsVisible() end
local function Enabled(b) return type(b) == "table" and (not b.IsEnabled or b:IsEnabled()) end

local function SortTop(list)
    table.sort(list, function(a, b)
        local at, bt = a:GetTop() or 0, b:GetTop() or 0
        if at ~= bt then return at > bt end
        return (a:GetLeft() or 0) < (b:GetLeft() or 0)
    end)
    return list
end

-- the gossip window's lines: the scroll box's frames on this client,
-- the numbered buttons on an older one
local function GossipLines()
    local out = {}
    local gf = _G.GossipFrame
    if not Shown(gf) then return out end
    local gp = gf.GreetingPanel
    local sb = type(gp) == "table" and gp.ScrollBox
    if type(sb) == "table" and sb.ForEachFrame then
        sb:ForEachFrame(function(b)
            if Shown(b) and b.GetElementData then
                local d = b:GetElementData()
                -- titles and the greeting text are lines too, but not buttons
                if type(d) == "table" and (d.info or d.optionID or d.questID) and b.Click then
                    out[#out + 1] = b
                end
            end
        end)
        return SortTop(out)
    end
    for i = 1, 40 do
        local b = _G["GossipTitleButton" .. i]
        if not b then break end
        if Shown(b) and b.Click then out[#out + 1] = b end
    end
    return out
end

-- the quest greeting (several quests at one NPC)
local function GreetingLines()
    local out = {}
    local gp = _G.QuestFrameGreetingPanel
    if not Shown(gp) then return out end
    local pool = gp.titleButtonPool
    if type(pool) == "table" and pool.EnumerateActive then
        for b in pool:EnumerateActive() do
            if Shown(b) and b.Click then out[#out + 1] = b end
        end
        return SortTop(out)
    end
    for i = 1, 40 do
        local b = _G["QuestTitleButton" .. i]
        if not b then break end
        if Shown(b) and b.Click then out[#out + 1] = b end
    end
    return out
end

-- the rewards to choose from on a quest's reward page
local function ChoiceLines()
    local out = {}
    if not Shown(_G.QuestFrameRewardPanel) then return out end
    local n = GetNumQuestChoices and GetNumQuestChoices() or 0
    if n < 2 then return out end
    local rf = _G.QuestInfoRewardsFrame
    local buttons = rf and rf.RewardButtons
    if type(buttons) == "table" then
        for _, b in ipairs(buttons) do
            if Shown(b) and b.type == "choice" and b.Click then out[#out + 1] = b end
        end
        return SortTop(out)
    end
    for i = 1, n do
        local b = _G["QuestInfoRewardsFrameQuestInfoItem" .. i] or _G["QuestInfoItem" .. i]
        if Shown(b) and b.Click then out[#out + 1] = b end
    end
    return out
end

function DK.Lines()
    local l = GossipLines()
    if #l > 0 then return l, "gossip" end
    l = GreetingLines()
    if #l > 0 then return l, "greeting" end
    l = ChoiceLines()
    if #l > 0 then return l, "choice" end
    return l, nil
end

-- ============================================================
-- THE NUMBERS ON THE LINES
-- ============================================================
local badged = {}
local function Badge(b, n, corner)
    local t = b._zDK
    if not t then
        t = UI.Font(b, UI.F.SMALL, { cat = "text", key = "gold" })
        if corner then
            t:SetPoint("TOPLEFT", b, "TOPLEFT", 2, -1)
        else
            t:SetPoint("RIGHT", b, "RIGHT", -6, 0)
        end
        t:SetJustifyH(corner and "LEFT" or "RIGHT")
        b._zDK = t
        badged[#badged + 1] = b
    end
    if n then
        t:SetText(tostring(n))
        t:Show()
    else
        t:Hide()
    end
end
local function ClearBadges()
    for _, b in ipairs(badged) do if b._zDK then b._zDK:Hide() end end
end
function DK.Refresh()
    ClearBadges()
    if not (On() and Cfg().numbers ~= false) then return end
    local lines, kind = DK.Lines()
    for i = 1, math.min(9, #lines) do Badge(lines[i], i, kind == "choice") end
end
local refreshQueued = false
local function QueueRefresh()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0.05, function()
        refreshQueued = false
        DK.Refresh()
    end)
end

-- ============================================================
-- WHAT A KEY DOES
-- ============================================================
local function Press(b)
    if not (b and Enabled(b)) then return false end
    b:Click()
    return true
end

-- Enter / Space on an NPC window
function DK.Accept()
    if Shown(_G.QuestFrameDetailPanel) then return Press(_G.QuestFrameAcceptButton) end
    if Shown(_G.QuestFrameProgressPanel) then return Press(_G.QuestFrameCompleteButton) end
    if Shown(_G.QuestFrameRewardPanel) then
        -- a choice not made yet: the first key picks nothing, the game
        -- would only say "choose a reward"
        local n = GetNumQuestChoices and GetNumQuestChoices() or 0
        local qi = _G.QuestInfoFrame
    local picked = type(qi) == "table" and tonumber(qi.itemChoice)
        if n > 1 and not (picked and picked > 0) then return false end
        return Press(_G.QuestFrameCompleteQuestButton)
    end
    local lines = DK.Lines()
    if #lines > 0 then return Press(lines[1]) end
    return false
end

function DK.Pick(n)
    local lines = DK.Lines()
    local b = lines[n]
    if not b then return false end
    if Press(b) then
        -- a reward picked: the number stays on it for Enter
        QueueRefresh()
        return true
    end
    return false
end

-- Popups Space must never answer: their first button can't be undone.
-- Summons too (Zac 2026-11-03: "just had a summon auto accepted ... it
-- shouldnt of" - Space is jump, and it took the summon; whether a summon
-- is taken is Readycheck's auto-accept rules or his own click).
local NEVER = { DEATH = true, QUIT = true, CAMP = true, CONFIRM_SUMMON = true }
local NEVER_WORDS = { "DELETE", "ABANDON", "DESTROY", "BIND", "UNLEARN", "RELEASE", "DISENCHANT", "SELL", "REPLACE", "RESET", "DISBAND", "UNINVITE", "KICK", "SUMMON" }
local function Unsafe(p)
    local which = p and p.which
    if type(which) ~= "string" then return true end    -- unknown: leave it alone
    if NEVER[which] then return true end
    for _, w in ipairs(NEVER_WORDS) do
        if which:find(w, 1, true) then return true end
    end
    return false
end
DK.Unsafe = Unsafe

-- the popup on screen that takes no typing
function DK.Popup()
    if Cfg().popups == false then return false end
    local best
    for i = 1, (STATICPOPUP_NUMDIALOGS or 4) do
        local p = _G["StaticPopup" .. i]
        if Shown(p) and not Unsafe(p) then
            local eb = _G["StaticPopup" .. i .. "EditBox"] or p.editBox
            if Shown(eb) then return false end
            local b1 = _G["StaticPopup" .. i .. "Button1"] or p.button1
            if Shown(b1) and Enabled(b1) and (not best or p:GetFrameLevel() > best.lvl) then
                best = { b = b1, lvl = p:GetFrameLevel() }
            end
        end
    end
    return best and Press(best.b) or false
end

local function NpcWindowUp()
    return Shown(_G.GossipFrame) or Shown(_G.QuestFrame)
end

-- true when the key was used
function DK.Key(key)
    if not On() then return false end
    -- a text box has the keyboard: the key is typing
    local focus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
    if focus then return false end
    if key == "ENTER" or (key == "SPACE" and Cfg().space ~= false) then
        if NpcWindowUp() then return DK.Accept() end
        if key == "SPACE" then return DK.Popup() end
        return false
    end
    local n = key:match("^(%d)$") or key:match("^NUMPAD(%d)$")
    n = tonumber(n)
    if n and n >= 1 and NpcWindowUp() then return DK.Pick(n) end
    return false
end

-- ============================================================
-- THE KEY FRAME
-- ============================================================
local kf = CreateFrame("Frame", "ZacUIDialogKeys", UIParent)
kf:SetFrameStrata("TOOLTIP")
kf:SetFrameLevel(10000)
kf:SetSize(1, 1)
kf:SetPoint("TOPLEFT")
kf:EnableKeyboard(false)
kf:Hide()
kf:SetScript("OnKeyDown", function(self, key)
    local used = DK.Key(key)
    if self.SetPropagateKeyboardInput and not InCombatLockdown() then
        self:SetPropagateKeyboardInput(not used)
    end
end)
-- (OnKeyUp follows the same propagate state; nothing to do)

local function Arm()
    local want = On() and (NpcWindowUp() or (Cfg().popups ~= false and Cfg().space ~= false and DK.AnyPopup()))
    if want and not InCombatLockdown() then
        if not kf:IsShown() then kf:Show() end
        kf:EnableKeyboard(true)
        if kf.SetPropagateKeyboardInput then kf:SetPropagateKeyboardInput(true) end
    else
        kf:EnableKeyboard(false)
        kf:Hide()
    end
end
function DK.AnyPopup()
    for i = 1, (STATICPOPUP_NUMDIALOGS or 4) do
        local p = _G["StaticPopup" .. i]
        -- an unsafe popup alone doesn't take the keyboard: Space stays jump
        if Shown(p) and not Unsafe(p) then
            local eb = _G["StaticPopup" .. i .. "EditBox"] or p.editBox
            if not Shown(eb) then return true end
        end
    end
    return false
end
DK.Arm = Arm

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("GOSSIP_SHOW")
ev:RegisterEvent("GOSSIP_CLOSED")
ev:RegisterEvent("QUEST_GREETING")
ev:RegisterEvent("QUEST_DETAIL")
ev:RegisterEvent("QUEST_PROGRESS")
ev:RegisterEvent("QUEST_COMPLETE")
ev:RegisterEvent("QUEST_FINISHED")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        -- the lists come and go after their events: numbered a moment later
        for _, name in ipairs({ "GossipFrame", "QuestFrame" }) do
            local f = _G[name]
            if f then
                f:HookScript("OnShow", function() Arm() QueueRefresh() end)
                f:HookScript("OnHide", function() Arm() ClearBadges() end)
            end
        end
        local gp = _G.GossipFrame and _G.GossipFrame.GreetingPanel
        local sb = type(gp) == "table" and gp.ScrollBox
        if type(sb) == "table" and sb.RegisterCallback and type(_G.ScrollBoxListMixin) == "table" and _G.ScrollBoxListMixin.Event then
            local E = _G.ScrollBoxListMixin.Event
            if E.OnScroll then sb:RegisterCallback(E.OnScroll, QueueRefresh, DK) end
            if E.OnDataRangeChanged then sb:RegisterCallback(E.OnDataRangeChanged, QueueRefresh, DK) end
        end
        if _G.QuestInfoItem_OnClick then hooksecurefunc("QuestInfoItem_OnClick", QueueRefresh) end
        if _G.StaticPopup_Show then hooksecurefunc("StaticPopup_Show", function() C_Timer.After(0, Arm) end) end
        if _G.StaticPopup_Hide then hooksecurefunc("StaticPopup_Hide", function() C_Timer.After(0, Arm) end) end
        for i = 1, (STATICPOPUP_NUMDIALOGS or 4) do
            local p = _G["StaticPopup" .. i]
            if p then p:HookScript("OnHide", function() C_Timer.After(0, Arm) end) end
        end
        return
    end
    if event == "PLAYER_REGEN_DISABLED" then
        kf:EnableKeyboard(false)
        return
    end
    Arm()
    QueueRefresh()
end)

function DK.SettingsChanged()
    Arm()
    QueueRefresh()
end
