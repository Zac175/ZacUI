-- AE_Comm - addon messages between players, framed the way the common
-- comm library frames them, so an aura that keeps raiders in step talks
-- to everyone else's client, whatever addon they run it in.
-- Part of ZacUI (Zacui_Auras). Written for ZacUI.
--
-- On the wire (the interop format, not anyone's code):
--   * one addon message holds at most 255 bytes;
--   * a text that fits goes as it is - unless it starts with a byte from
--     1 to 9, in which case it gets a 4 in front so it is not mistaken
--     for a part marker;
--   * a longer text goes in parts of 254 bytes, each led by 1 (first),
--     2 (middle) or 3 (last), and the receiver joins them per sender,
--     channel and prefix.
-- For text that has been compressed, the bytes 0 and 1 are escaped first
-- (0 -> 1 2, 1 -> 1 3): the channel drops a 0.
--
-- The game limits how fast addon messages leave: a prefix gets a burst of
-- ten and then about one a second, and the channel as a whole a few
-- kilobytes a second. Messages queue and go out as the allowance comes
-- back, in the order they were sent, so the parts of one text stay in
-- order.
local ns = _G.ZacUI
if not ns then return end
local E = ns.AuraEngine
if not E then return end

local Co = E.Codec
local Cm = {}
E.Comm = Cm

local byte, sub, concat = string.byte, string.sub, table.concat

-- ============================================================
-- THE ESCAPE FOR COMPRESSED TEXT
-- ============================================================
local ESC = { ["\000"] = "\001\002", ["\001"] = "\001\003" }

function Co.ToAddon(s)
    return (s:gsub("[%z\001]", ESC))
end

local UNESC = { ["\001\002"] = "\000", ["\001\003"] = "\001" }

-- other pairs pass through untouched, as other clients' decoders do; a
-- bare 0 means the text was never escaped
function Co.FromAddon(s)
    if type(s) ~= "string" or s:find("%z") then return nil end
    return (s:gsub("\001[\002\003]", UNESC))
end

-- ============================================================
-- SENDING
-- ============================================================
local MAX = 255
local PER_PREFIX, PREFIX_REGEN = 10, 1      -- messages, messages a second
local BYTES, BYTES_REGEN = 4000, 800        -- bytes, bytes a second
local OVERHEAD = 40                          -- what a message costs beyond its text

local queue, head, tail = {}, 1, 0
local prefixLeft, bytesLeft = {}, BYTES
local lastFill
local pump = CreateFrame("Frame")
pump:Hide()

local function RawSend(prefix, text, channel, target)
    local api = C_ChatInfo and C_ChatInfo.SendAddonMessage or _G.SendAddonMessage
    if not api then return "drop" end
    -- WoW Forever delivers no addon messages inside an instance: held until
    -- you are out (Core_Flavor)
    if ns.AddonMessagesBlocked and ns.AddonMessagesBlocked() then return "wait" end
    local ok, res = pcall(api, prefix, text, channel, target)
    if not ok then return "drop" end
    -- newer clients answer with a result code, older ones with true/false
    if res == true or res == nil or res == 0 then return "sent" end
    if res == 3 or res == 8 then return "wait" end   -- throttled: try again shortly
    return "drop"
end

local function Fill(now)
    local dt = now - (lastFill or now)
    lastFill = now
    if dt <= 0 then return end
    bytesLeft = math.min(BYTES, bytesLeft + dt * BYTES_REGEN)
    for p, n in pairs(prefixLeft) do
        n = n + dt * PREFIX_REGEN
        if n >= PER_PREFIX then prefixLeft[p] = nil else prefixLeft[p] = n end
    end
end

local wait = 0
local function Pump(_, elapsed)
    if wait > 0 then
        wait = wait - (elapsed or 0)
        if wait > 0 then return end
    end
    Fill(GetTime())
    while head <= tail do
        local m = queue[head]
        local left = prefixLeft[m[1]] or PER_PREFIX
        local cost = #m[2] + OVERHEAD
        if left < 1 or bytesLeft < cost then return end
        local res = RawSend(m[1], m[2], m[3], m[4])
        if res == "wait" then
            wait = 1
            return
        end
        prefixLeft[m[1]] = left - 1
        bytesLeft = bytesLeft - cost
        queue[head] = nil
        head = head + 1
    end
    queue, head, tail = {}, 1, 0
    pump:Hide()
end
pump:SetScript("OnUpdate", Pump)

local function Queue(prefix, text, channel, target)
    tail = tail + 1
    queue[tail] = { prefix, text, channel, target }
    if not pump:IsShown() then
        pump:Show()
        Pump(nil, 0)
    end
end

-- Send one text of any length. Returns false when there is nobody to
-- send it to.
function Cm.Send(prefix, text, channel, target)
    if type(prefix) ~= "string" or type(text) ~= "string" or type(channel) ~= "string" then return false end
    if channel == "WHISPER" and type(target) ~= "string" then return false end
    local n = #text
    local first = byte(text, 1)
    local escaped = first and first >= 1 and first <= 9
    if n <= MAX and not (escaped and n + 1 > MAX) then
        Queue(prefix, escaped and ("\004" .. text) or text, channel, target)
        return true
    end
    local part = MAX - 1
    Queue(prefix, "\001" .. sub(text, 1, part), channel, target)
    local pos = part + 1
    while pos + part <= n do
        Queue(prefix, "\002" .. sub(text, pos, pos + part - 1), channel, target)
        pos = pos + part
    end
    Queue(prefix, "\003" .. sub(text, pos), channel, target)
    return true
end

-- ============================================================
-- RECEIVING
-- ============================================================
local handlers = {}   -- prefix -> { fn, ... }
local spool = {}      -- prefix \t channel \t sender -> { parts }

local function Deliver(prefix, text, channel, sender)
    for _, fn in ipairs(handlers[prefix] or {}) do
        local ok, err = pcall(fn, prefix, text, channel, sender)
        if not ok and E.Error then E.Error("comm", prefix, err) end
    end
end

local listener = CreateFrame("Frame")
listener:SetScript("OnEvent", function(_, _, prefix, text, channel, sender)
    if not handlers[prefix] or type(text) ~= "string" then return end
    local c = byte(text, 1)
    local key = prefix .. "\t" .. tostring(channel) .. "\t" .. tostring(sender)
    if c == 1 then
        spool[key] = { sub(text, 2) }
    elseif c == 2 then
        local s = spool[key]
        if s then s[#s + 1] = sub(text, 2) end
    elseif c == 3 then
        local s = spool[key]
        if s then
            spool[key] = nil
            s[#s + 1] = sub(text, 2)
            Deliver(prefix, concat(s), channel, sender)
        end
    elseif c == 4 then
        Deliver(prefix, sub(text, 2), channel, sender)
    else
        Deliver(prefix, text, channel, sender)
    end
end)

-- fn(prefix, text, channel, sender) for every whole text on this prefix
function Cm.Register(prefix, fn)
    if type(prefix) ~= "string" or type(fn) ~= "function" then return end
    if not handlers[prefix] then
        handlers[prefix] = {}
        local reg = C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix or _G.RegisterAddonMessagePrefix
        if reg then pcall(reg, prefix) end
        listener:RegisterEvent("CHAT_MSG_ADDON")
    end
    table.insert(handlers[prefix], fn)
end
