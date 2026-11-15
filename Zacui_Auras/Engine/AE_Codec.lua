-- AE_Codec - aura strings in and out: the "!WA:2!" format players paste.
-- Part of ZacUI (Zacui_Auras). Written for ZacUI.
--
-- A string is three layers, outermost first:
--   1. print-safe text: 6 bits a character, alphabet a-z A-Z 0-9 ( ),
--      four characters to three bytes, least significant first
--   2. raw DEFLATE (RFC 1951)
--   3. a binary serialisation of the table (the LibSerialize layout,
--      version 1): a type byte per value, small numbers, strings and
--      tables with counts folded into the type byte, repeated strings
--      and tables sent as references
-- Every layer here is ZacUI's own code. Strings it writes use stored
-- (uncompressed) DEFLATE blocks: longer than a compressed string, and
-- read by every DEFLATE reader there is.
local ns = _G.ZacUI
if not ns then return end
local E = ns.AuraEngine
if not E then return end

local Co = {}
E.Codec = Co

local byte, char, concat, floor = string.byte, string.char, table.concat, math.floor

-- ============================================================
-- 1. PRINT-SAFE TEXT
-- ============================================================
local ALPHA = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789()"
local toVal, toChar = {}, {}
for i = 1, 64 do
    local c = ALPHA:sub(i, i)
    toVal[byte(c)] = i - 1
    toChar[i - 1] = c
end

function Co.FromPrint(s)
    s = s:gsub("^[%c ]+", ""):gsub("[%c ]+$", "")
    local out, n = {}, 0
    local cache, bits = 0, 0
    for i = 1, #s do
        local v = toVal[byte(s, i)]
        if not v then return nil end
        cache = cache + v * 2 ^ bits
        bits = bits + 6
        while bits >= 8 do
            local b = cache % 256
            n = n + 1
            out[n] = char(b)
            cache = (cache - b) / 256
            bits = bits - 8
        end
    end
    return concat(out)
end

function Co.ToPrint(s)
    local out, n = {}, 0
    local cache, bits = 0, 0
    for i = 1, #s do
        cache = cache + byte(s, i) * 2 ^ bits
        bits = bits + 8
        while bits >= 6 do
            local v = cache % 64
            n = n + 1
            out[n] = toChar[v]
            cache = (cache - v) / 64
            bits = bits - 6
        end
    end
    if bits > 0 then
        n = n + 1
        out[n] = toChar[cache]
    end
    return concat(out)
end

-- ============================================================
-- 2. INFLATE
-- ============================================================
local LBASE = { 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258 }
local LEXTRA = { 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0 }
local DBASE = { 1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073,
    4097, 6145, 8193, 12289, 16385, 24577 }
local DEXTRA = { 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13 }
local CLORDER = { 16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15 }

-- a Huffman table from code lengths: [length] = { [code] = symbol }
local function Huffman(lengths, n)
    local count = {}
    local maxLen = 0
    for i = 0, n - 1 do
        local l = lengths[i] or 0
        if l > 0 then
            count[l] = (count[l] or 0) + 1
            if l > maxLen then maxLen = l end
        end
    end
    local code, nextCode = 0, {}
    for bitsN = 1, maxLen do
        code = (code + (count[bitsN - 1] or 0)) * 2
        nextCode[bitsN] = code
    end
    local t = { max = maxLen }
    for i = 0, n - 1 do
        local l = lengths[i] or 0
        if l > 0 then
            local c = nextCode[l]
            nextCode[l] = c + 1
            t[l] = t[l] or {}
            t[l][c] = i
        end
    end
    return t
end

function Co.Inflate(src)
    local pos, bitBuf, bitCnt = 1, 0, 0
    local len = #src
    local out, outN = {}, 0
    local function Bits(n)
        while bitCnt < n do
            if pos > len then error("deflate data ended early") end
            bitBuf = bitBuf + byte(src, pos) * 2 ^ bitCnt
            pos = pos + 1
            bitCnt = bitCnt + 8
        end
        local v = bitBuf % 2 ^ n
        bitBuf = (bitBuf - v) / 2 ^ n
        bitCnt = bitCnt - n
        return v
    end
    -- Huffman codes are read most significant bit first, one bit at a time
    local function Sym(t)
        local code = 0
        for l = 1, t.max do
            code = code * 2 + Bits(1)
            local row = t[l]
            if row then
                local s = row[code]
                if s then return s end
            end
        end
        error("bad Huffman code")
    end
    local fixedLit, fixedDist
    local function Fixed()
        if not fixedLit then
            local l = {}
            for i = 0, 143 do l[i] = 8 end
            for i = 144, 255 do l[i] = 9 end
            for i = 256, 279 do l[i] = 7 end
            for i = 280, 287 do l[i] = 8 end
            fixedLit = Huffman(l, 288)
            local d = {}
            for i = 0, 29 do d[i] = 5 end
            fixedDist = Huffman(d, 30)
        end
        return fixedLit, fixedDist
    end
    local function Dynamic()
        local hlit, hdist, hclen = Bits(5) + 257, Bits(5) + 1, Bits(4) + 4
        local cl = {}
        for i = 1, hclen do cl[CLORDER[i]] = Bits(3) end
        local clt = Huffman(cl, 19)
        local lengths, i = {}, 0
        while i < hlit + hdist do
            local s = Sym(clt)
            if s < 16 then
                lengths[i] = s
                i = i + 1
            elseif s == 16 then
                local prev = lengths[i - 1] or 0
                for _ = 1, 3 + Bits(2) do lengths[i] = prev i = i + 1 end
            elseif s == 17 then
                for _ = 1, 3 + Bits(3) do lengths[i] = 0 i = i + 1 end
            else
                for _ = 1, 11 + Bits(7) do lengths[i] = 0 i = i + 1 end
            end
        end
        local lit, dist = {}, {}
        for k = 0, hlit - 1 do lit[k] = lengths[k] end
        for k = 0, hdist - 1 do dist[k] = lengths[hlit + k] end
        return Huffman(lit, hlit), Huffman(dist, hdist)
    end
    repeat
        local final = Bits(1)
        local kind = Bits(2)
        if kind == 0 then
            bitBuf, bitCnt = 0, 0                -- to the byte boundary
            if pos + 3 > len then error("stored block header past the end") end
            local n = byte(src, pos) + byte(src, pos + 1) * 256
            pos = pos + 4
            for k = 0, n - 1 do
                outN = outN + 1
                out[outN] = byte(src, pos + k)
            end
            pos = pos + n
        elseif kind == 1 or kind == 2 then
            local lit, dist
            if kind == 1 then lit, dist = Fixed() else lit, dist = Dynamic() end
            while true do
                local s = Sym(lit)
                if s < 256 then
                    outN = outN + 1
                    out[outN] = s
                elseif s == 256 then
                    break
                else
                    local li = s - 256
                    local l = LBASE[li] + Bits(LEXTRA[li])
                    local di = Sym(dist) + 1
                    local dd = DBASE[di] + Bits(DEXTRA[di])
                    local from = outN - dd
                    for k = 1, l do out[outN + k] = out[from + k] end
                    outN = outN + l
                end
            end
        else
            error("bad block type")
        end
    until final == 1
    -- bytes to a string, in pieces (char takes only so many arguments)
    local parts = {}
    for k = 1, outN, 4096 do
        parts[#parts + 1] = char(unpack(out, k, math.min(outN, k + 4095)))
    end
    return concat(parts)
end

-- ============================================================
-- DEFLATE (writing): repeats found in a 32 KB window, coded with the
-- fixed Huffman table - about a third of the size of the input for an
-- aura, and read by every DEFLATE reader.
-- ============================================================
local function Writer()
    local out, n = {}, 0
    local buf, cnt = 0, 0
    local w = {}
    function w.Bits(v, len)
        buf = buf + v * 2 ^ cnt
        cnt = cnt + len
        while cnt >= 8 do
            local b = buf % 256
            n = n + 1
            out[n] = char(b)
            buf = (buf - b) / 256
            cnt = cnt - 8
        end
    end
    -- Huffman codes go most significant bit first
    function w.Code(code, len)
        local r = 0
        for _ = 1, len do
            r = r * 2 + code % 2
            code = floor(code / 2)
        end
        w.Bits(r, len)
    end
    function w.Finish()
        if cnt > 0 then
            n = n + 1
            out[n] = char(buf)
        end
        return concat(out)
    end
    return w
end

local function Lit(w, v)
    if v < 144 then w.Code(48 + v, 8)
    elseif v < 256 then w.Code(400 + v - 144, 9)
    elseif v < 280 then w.Code(v - 256, 7)
    else w.Code(192 + v - 280, 8) end
end

local LCODE, DCODE = {}, {}
for i = 1, 29 do
    local base, extra = LBASE[i], LEXTRA[i]
    for l = base, base + 2 ^ extra - 1 do
        if l <= 258 and not LCODE[l] then LCODE[l] = i end
    end
end
LCODE[258] = 29

local function DistCode(dd)
    local lo, hi = 1, 30
    while lo < hi do
        local mid = floor((lo + hi + 1) / 2)
        if DBASE[mid] <= dd then lo = mid else hi = mid - 1 end
    end
    return lo
end

function Co.Deflate(s)
    local n = #s
    local w = Writer()
    w.Bits(1, 1)          -- the only block, and the last
    w.Bits(1, 2)          -- fixed Huffman
    local heads = {}      -- 3-byte key -> latest position
    local prev = {}       -- position -> previous position with that key
    local i = 1
    local MAXCHAIN = 24
    while i <= n do
        local bestLen, bestDist = 0, 0
        if i + 2 <= n then
            local key = s:sub(i, i + 2)
            local cand = heads[key]
            local chain = 0
            while cand and i - cand <= 32768 and chain < MAXCHAIN do
                local l = 3
                local maxl = math.min(258, n - i + 1)
                while l < maxl and byte(s, cand + l) == byte(s, i + l) do l = l + 1 end
                if l > bestLen then
                    bestLen, bestDist = l, i - cand
                    if l == maxl then break end
                end
                cand = prev[cand]
                chain = chain + 1
            end
            prev[i] = heads[key]
            heads[key] = i
        end
        if bestLen >= 3 then
            local li = LCODE[bestLen]
            Lit(w, 256 + li)
            if LEXTRA[li] > 0 then w.Bits(bestLen - LBASE[li], LEXTRA[li]) end
            local di = DistCode(bestDist)
            w.Code(di - 1, 5)
            if DEXTRA[di] > 0 then w.Bits(bestDist - DBASE[di], DEXTRA[di]) end
            -- the skipped positions still go in the window
            for j = i + 1, math.min(i + bestLen - 1, n - 2) do
                local key = s:sub(j, j + 2)
                prev[j] = heads[key]
                heads[key] = j
            end
            i = i + bestLen
        else
            Lit(w, byte(s, i))
            i = i + 1
        end
    end
    Lit(w, 256)
    return w.Finish()
end

-- ============================================================
-- 3. THE SERIALISED TABLE
-- ============================================================
local function Float(str)
    local b1, b2, b3, b4, b5, b6, b7, b8 = byte(str, 1, 8)
    local sign = b1 > 127 and -1 or 1
    local expo = (b1 % 128) * 16 + floor(b2 / 16)
    local mant = ((((((b2 % 16) * 256 + b3) * 256 + b4) * 256 + b5) * 256 + b6) * 256 + b7) * 256 + b8
    if mant == 0 and expo == 0 then return sign * 0 end
    if expo == 2047 then return mant == 0 and sign * math.huge or 0 / 0 end
    return sign * math.ldexp(1 + mant / 4503599627370496, expo - 1023)
end

function Co.Deserialize(s)
    local pos = 1
    local strRefs, tabRefs = {}, {}
    local function Bytes(n)
        local v = s:sub(pos, pos + n - 1)
        if #v < n then error("serialised data ended early") end
        pos = pos + n
        return v
    end
    local function Int(n)
        local v = 0
        for i = 1, n do
            v = v * 256 + byte(s, pos + i - 1)
        end
        pos = pos + n
        return v
    end
    local Object
    local function Str(n)
        local v = Bytes(n)
        if n > 2 then strRefs[#strRefs + 1] = v end
        return v
    end
    local function Map(n, t)
        if not t then
            t = {}
            tabRefs[#tabRefs + 1] = t
        end
        for _ = 1, n do
            local k = Object()
            local v = Object()
            if k ~= nil then t[k] = v end
        end
        return t
    end
    local function Array(n, t)
        if not t then
            t = {}
            tabRefs[#tabRefs + 1] = t
        end
        for i = 1, n do t[i] = Object() end
        return t
    end
    local function Mixed(na, nm)
        local t = {}
        tabRefs[#tabRefs + 1] = t
        Array(na, t)
        Map(nm, t)
        return t
    end
    local READ = {
        [0] = function() return nil end,
        [1] = function() return Int(2) end, [2] = function() return -Int(2) end,
        [3] = function() return Int(3) end, [4] = function() return -Int(3) end,
        [5] = function() return Int(4) end, [6] = function() return -Int(4) end,
        [7] = function() return Int(7) end, [8] = function() return -Int(7) end,
        [9] = function() return Float(Bytes(8)) end,
        [10] = function() return tonumber(Bytes(Int(1))) end,
        [11] = function() return -tonumber(Bytes(Int(1))) end,
        [12] = function() return true end, [13] = function() return false end,
        [14] = function() return Str(Int(1)) end, [15] = function() return Str(Int(2)) end,
        [16] = function() return Str(Int(3)) end,
        [17] = function() return Map(Int(1)) end, [18] = function() return Map(Int(2)) end,
        [19] = function() return Map(Int(3)) end,
        [20] = function() return Array(Int(1)) end, [21] = function() return Array(Int(2)) end,
        [22] = function() return Array(Int(3)) end,
        [23] = function() local a = Int(1) return Mixed(a, Int(1)) end,
        [24] = function() local a = Int(2) return Mixed(a, Int(2)) end,
        [25] = function() local a = Int(3) return Mixed(a, Int(3)) end,
        [26] = function() return strRefs[Int(1)] end, [27] = function() return strRefs[Int(2)] end,
        [28] = function() return strRefs[Int(3)] end,
        [29] = function() return tabRefs[Int(1)] end, [30] = function() return tabRefs[Int(2)] end,
        [31] = function() return tabRefs[Int(3)] end,
    }
    Object = function()
        local v = Int(1)
        if v % 2 == 1 then return (v - 1) / 2 end
        if v % 4 == 2 then
            local typ = (v - 2) / 4
            local count = floor(typ / 4)
            typ = typ % 4
            if typ == 0 then return Str(count)
            elseif typ == 1 then return Map(count)
            elseif typ == 2 then return Array(count) end
            return Mixed(count % 4 + 1, floor(count / 4) + 1)
        end
        if v % 8 == 4 then
            local packed = Int(1) * 256 + v
            if v % 16 == 12 then return -(packed - 12) / 16 end
            return (packed - 4) / 16
        end
        local fn = READ[v / 8]
        if not fn then error("unknown type byte " .. v) end
        return fn()
    end
    if byte(s, 1) ~= 1 then error("unsupported serialisation version") end
    pos = 2
    local out = {}
    local n = 0
    while pos <= #s do
        n = n + 1
        out[n] = Object()
    end
    return unpack(out, 1, n)
end

local function IntBytes(v, n)
    local t = {}
    for i = n, 1, -1 do
        t[i] = v % 256
        v = floor(v / 256)
    end
    return char(unpack(t))
end

function Co.Serialize(value)
    local out = { char(1) }
    local seen = {}
    local function W(s) out[#out + 1] = s end
    local Write
    local function Num(v)
        if v == floor(v) and v > -2 ^ 53 and v < 2 ^ 53 then
            local a = math.abs(v)
            if v >= 0 and v < 128 then return W(char(v * 2 + 1)) end
            if a < 4096 then
                local packed = a * 16 + (v < 0 and 12 or 4)
                return W(char(packed % 256, floor(packed / 256)))
            end
            local neg = v < 0 and 1 or 0
            if a < 65536 then return W(char((1 + neg) * 8) .. IntBytes(a, 2)) end
            if a < 16777216 then return W(char((3 + neg) * 8) .. IntBytes(a, 3)) end
            if a < 4294967296 then return W(char((5 + neg) * 8) .. IntBytes(a, 4)) end
            return W(char((7 + neg) * 8) .. IntBytes(a, 7))
        end
        local s = string.format("%.17g", math.abs(v))
        W(char((v < 0 and 11 or 10) * 8) .. char(#s) .. s)
    end
    local function Str(v)
        local n = #v
        if n < 16 then W(char(n * 16 + 2))
        elseif n < 256 then W(char(14 * 8) .. char(n))
        elseif n < 65536 then W(char(15 * 8) .. IntBytes(n, 2))
        else W(char(16 * 8) .. IntBytes(n, 3)) end
        W(v)
    end
    local function Tab(t)
        if seen[t] then error("a table appears twice") end
        seen[t] = true
        local keys = {}
        for k, v in pairs(t) do
            local kt = type(k)
            if (kt == "string" or kt == "number" or kt == "boolean")
                and (type(v) ~= "function" and type(v) ~= "userdata") then
                keys[#keys + 1] = k
            end
        end
        local n = #keys
        if n < 16 then W(char(n * 16 + 1 * 4 + 2))
        elseif n < 256 then W(char(17 * 8) .. char(n))
        elseif n < 65536 then W(char(18 * 8) .. IntBytes(n, 2))
        else W(char(19 * 8) .. IntBytes(n, 3)) end
        for _, k in ipairs(keys) do
            Write(k)
            Write(t[k])
        end
        seen[t] = nil
    end
    Write = function(v)
        local tv = type(v)
        if tv == "nil" then W(char(0))
        elseif tv == "boolean" then W(char(v and 96 or 104))
        elseif tv == "number" then Num(v)
        elseif tv == "string" then Str(v)
        elseif tv == "table" then Tab(v)
        else W(char(0)) end
    end
    Write(value)
    return concat(out)
end

-- ============================================================
-- THE WHOLE STRING
-- ============================================================
local PREFIX = "!WA:2!"

-- returns the payload table: { m = "d", d = display, c = { children }, ... }
function Co.Decode(str)
    if type(str) ~= "string" then return nil, "nothing to import" end
    str = str:gsub("^%s+", ""):gsub("%s+$", "")
    if str:sub(1, #PREFIX) ~= PREFIX then
        if str:sub(1, 6) == "!WA:1!" or not str:find("^!") then
            return nil, "this is an older aura string format the engine does not read yet"
        end
        return nil, "this is not an aura string"
    end
    local raw = Co.FromPrint(str:sub(#PREFIX + 1))
    if not raw then return nil, "the string has characters that do not belong in it" end
    local ok, inflated = pcall(Co.Inflate, raw)
    if not ok then return nil, "the string is damaged (" .. tostring(inflated) .. ")" end
    local ok2, payload = pcall(Co.Deserialize, inflated)
    if not ok2 then return nil, "the string is damaged (" .. tostring(payload) .. ")" end
    if type(payload) ~= "table" then return nil, "the string holds no aura" end
    return payload
end

function Co.Encode(payload)
    return PREFIX .. Co.ToPrint(Co.Deflate(Co.Serialize(payload)))
end

-- ============================================================
-- INTO THE LIBRARY, AND OUT OF IT
-- ============================================================
-- A string for a display (and everything under it, when it is a group)
function E.Export(id)
    local d = E.data[id]
    if not d then return nil, "no such display" end
    local top = E.Copy(d)
    top.parent = nil
    local payload = { m = "d", d = top, v = 1421, s = "ZacUI" }
    if E.IsGroup(d) then
        payload.c = {}
        for _, child in ipairs(E.Descendants(id)) do
            payload.c[#payload.c + 1] = E.Copy(E.data[child])
        end
    end
    return Co.Encode(payload)
end

-- a free id like the one asked for ("Name", "Name 2", ...)
local function FreeId(want)
    local sv = E.Saved().displays
    if sv[want] == nil then return want end
    local n = 2
    while sv[want .. " " .. n] ~= nil do n = n + 1 end
    return want .. " " .. n
end

-- adds what a string holds to the saved displays; returns the new top id
function E.Install(payload)
    if type(payload) ~= "table" or type(payload.d) ~= "table" then return nil, "the string holds no display" end
    local sv = E.Saved().displays
    local rename = {}
    local all = { payload.d }
    for _, c in ipairs(type(payload.c) == "table" and payload.c or {}) do
        if type(c) == "table" and c.id then all[#all + 1] = c end
    end
    for _, d in ipairs(all) do
        local id = d.id or "New aura"
        rename[id] = FreeId(id)
        -- reserve it so the next free id is different
        sv[rename[id]] = sv[rename[id]] or false
    end
    for _, d in ipairs(all) do
        local copy = E.Copy(d)
        copy.id = rename[d.id or "New aura"]
        if copy.parent then copy.parent = rename[copy.parent] or copy.parent end
        if type(copy.controlledChildren) == "table" then
            for i, child in ipairs(copy.controlledChildren) do copy.controlledChildren[i] = rename[child] or child end
        end
        copy.source = "import"
        sv[copy.id] = copy
    end
    for k, v in pairs(sv) do if v == false then sv[k] = nil end end
    E.ReadSaved()
    if E.CheckLoads then E.CheckLoads() end
    return rename[payload.d.id or "New aura"]
end

function E.Import(str)
    local payload, err = Co.Decode(str)
    if not payload then return nil, err end
    return E.Install(payload)
end
