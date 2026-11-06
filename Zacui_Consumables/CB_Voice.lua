-- CB_Voice - the bars' spoken warnings: an item's short name when its
-- buff enters the warning time (each bar its own switch), again after it
-- ran out when asked, "Potion ready" when the potion cooldown ends.
-- ZacUI's one voice (General page). Run by the bars' 1 s pass only.
-- Part of ZacUI; load order is set by the TOC.

local ADDON_NAME = ...
local ns = _G.ZacUI
if not ns then return end
local D, CB = ns.ConsData, ns.ConsBars
if not (D and CB) then return end

local V = {}
CB.Voice = V
local W = CB.World
local pairs, ipairs, tonumber, type = pairs, ipairs, tonumber, type

-- per item (itemTTS["<id>"] = { ttsText, ttsEnabled, repeatEnabled })
local function ItemSetting(id)
    local t = CB.T(CB.Cfg(), "itemTTS")
    return t and t[tostring(id)]
end
function V.ItemOn(id)
    local s = ItemSetting(id)
    if s and s.ttsEnabled ~= nil then return s.ttsEnabled ~= false end
    return not D.SPOKEN_OFF[id]
end
function V.RepeatOn(id)
    local s = ItemSetting(id)
    return not (s and s.repeatEnabled == false)
end
function V.Text(id, name)
    local s = ItemSetting(id)
    if s and type(s.ttsText) == "string" and s.ttsText ~= "" then return s.ttsText end
    return D.SpokenName(name)
end

V.said = {}     -- what was said (tests read it)
local lastLine, lastAt = nil, 0
function V.Say(text)
    if type(text) ~= "string" or text == "" then return end
    local now = GetTime()
    if text == lastLine and now - lastAt < 1 then return end
    lastLine, lastAt = text, now
    V.said[#V.said + 1] = text
    if #V.said > 20 then table.remove(V.said, 1) end
    if C_VoiceChat and C_VoiceChat.SpeakText then
        pcall(C_VoiceChat.SpeakText, ns.VoiceId and ns.VoiceId() or 0, text, 0, 100, 1)
    end
end

local prev, repeats = {}, {}
local potWas = 0
local function BarOf(id)
    if D.POTION_BAR[id] and not D.BOTH_BARS[id] then return "potions" end
    return "main"
end
function V.Tick(now)
    local c = CB.Cfg()
    local seen = {}
    local ids = CB.BuffMaps()
    -- buffs entering their bar's warning time
    for sid, a in pairs(ids) do
        local items = D.BY_BUFF[sid]
        local exp = tonumber(a.expirationTime) or 0
        if items and exp > 0 then
            local rem = exp - now
            for _, id in ipairs(items) do
                local key = BarOf(id)
                local cfg = c[key]
                if cfg and cfg.enabled and cfg.tts then
                    local thr = tonumber(cfg.showBeforeExpiry) or 60
                    seen[id] = rem
                    local p = prev[id]
                    if rem > 0 and rem <= thr and p ~= nil and p > thr and V.ItemOn(id) then
                        V.Say(V.Text(id, D.BY_ID[id] and D.BY_ID[id].name))
                    end
                end
            end
        end
    end
    -- gone: the repeats start
    for id, p in pairs(prev) do
        if type(id) == "number" and not seen[id] and c.ttsRepeat and V.RepeatOn(id) and V.ItemOn(id) then
            repeats[id] = { at = now + (tonumber(c.ttsRepeatInterval) or 60), left = tonumber(c.ttsRepeatCount) or 1 }
        end
    end
    prev = seen
    for id, r in pairs(repeats) do
        if seen[id] or not c.ttsRepeat then repeats[id] = nil
        elseif now >= r.at then
            if W.Count(id) > 0 then
                local s, d = W.Cooldown(id)
                if not (s > 0 and s + d - now > 0) then V.Say(V.Text(id, D.BY_ID[id] and D.BY_ID[id].name)) end
            end
            r.left = r.left - 1
            r.at = now + (tonumber(c.ttsRepeatInterval) or 60)
            if r.left <= 0 then repeats[id] = nil end
        end
    end
    -- a weapon's stone or oil entering its warning time
    local wc = c.weapons
    if wc and wc.enabled and wc.tts then
        local thr = tonumber(wc.showBeforeExpiry) or 60
        for _, slot in ipairs({ "mainhand", "offhand" }) do
            local has, rem, eid = W.Enchant(slot)
            local k = "w" .. slot
            local p = prev[k]
            if has and rem > 0 then
                if p and p > thr and rem <= thr then
                    local stone = eid and D.ENCHANT_TO_STONE[eid]
                    V.Say(stone and D.SpokenName(D.STONE_NAMES[stone]) or (slot == "mainhand" and "Main hand" or "Off hand"))
                end
                prev[k] = rem
            end
        end
    end
    -- the potion cooldown ending
    if c.potionReadyTTS then
        local left = 0
        for id, it in pairs(D.ITEMS.potions) do
            if W.Count(id) > 0 then
                local s, d = W.Cooldown(id)
                if s > 0 and d > 15 and s + d - now > left then left = s + d - now end
            end
        end
        if potWas > 0 and left <= 0 then V.Say("Potion ready") end
        potWas = left
    end
end
function V.Reset() prev, repeats, potWas = {}, {}, 0 end
