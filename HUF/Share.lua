-- HUF: profile export / import as one line of text (copy & paste between
-- accounts). "HUF1:" + base64 of a small length-prefixed serialization:
--   table {k v k v ...}  string s<len>:<bytes>  number n<value>;  true t  false f
-- Nothing is run when importing: the text is only parsed.

local _, ns = ...

local PREFIX = "HUF1:"

---------------------------------------------------------------------------
-- Serialize / parse
---------------------------------------------------------------------------
local function Ser(v, out, depth)
    local t = type(v)
    if t == "string" then
        out[#out + 1] = "s" .. #v .. ":" .. v
    elseif t == "number" then
        out[#out + 1] = "n" .. string.format("%.17g", v) .. ";"
    elseif t == "boolean" then
        out[#out + 1] = v and "t" or "f"
    elseif t == "table" then
        if depth > 20 then error("too deep") end
        out[#out + 1] = "{"
        -- sorted keys: the same settings give the same text
        local keys = {}
        for k in pairs(v) do
            local kt = type(k)
            if kt == "string" or kt == "number" then keys[#keys + 1] = k end
        end
        table.sort(keys, function(a, b)
            if type(a) == type(b) then return a < b end
            return type(a) == "number"
        end)
        for _, k in ipairs(keys) do
            local val = v[k]
            local vt = type(val)
            if vt == "string" or vt == "number" or vt == "boolean" or vt == "table" then
                Ser(k, out, depth)
                Ser(val, out, depth + 1)
            end
        end
        out[#out + 1] = "}"
    end
end

local function Parse(s)
    local pos = 1
    local function Value(depth)
        if depth > 20 then error("too deep") end
        local c = s:sub(pos, pos)
        if c == "s" then
            local len, colon = s:match("^(%d+)():", pos + 1)
            if not len then error("bad text at " .. pos) end
            len = tonumber(len)
            local start = colon + 1
            local v = s:sub(start, start + len - 1)
            if #v ~= len then error("text cut off") end
            pos = start + len
            return v
        elseif c == "n" then
            local num, after = s:match("^([^;]+);()", pos + 1)
            local v = tonumber(num or "")
            if not v then error("bad number at " .. pos) end
            pos = after
            return v
        elseif c == "t" then pos = pos + 1 return true
        elseif c == "f" then pos = pos + 1 return false
        elseif c == "{" then
            pos = pos + 1
            local t = {}
            while true do
                if pos > #s then error("text cut off") end
                if s:sub(pos, pos) == "}" then pos = pos + 1 return t end
                local k = Value(depth + 1)
                if type(k) ~= "string" and type(k) ~= "number" then error("bad key") end
                t[k] = Value(depth + 1)
            end
        end
        error("unexpected '" .. c .. "' at " .. pos)
    end
    local v = Value(0)
    if pos <= #s then error("extra text at the end") end
    return v
end

---------------------------------------------------------------------------
-- Base64 (letters, digits, + and /: safe in edit boxes and chat)
---------------------------------------------------------------------------
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local DEC = {}
for i = 1, 64 do DEC[B64:byte(i)] = i - 1 end

local function Encode(data)
    local out = {}
    for i = 1, #data, 3 do
        local a, b, c = data:byte(i, i + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        local c1 = math.floor(n / 262144) % 64
        local c2 = math.floor(n / 4096) % 64
        local c3 = math.floor(n / 64) % 64
        local c4 = n % 64
        out[#out + 1] = B64:sub(c1 + 1, c1 + 1) .. B64:sub(c2 + 1, c2 + 1)
            .. (b and B64:sub(c3 + 1, c3 + 1) or "=") .. (c and B64:sub(c4 + 1, c4 + 1) or "=")
    end
    return table.concat(out)
end

local function Decode(text)
    text = text:gsub("[^%w%+/=]", "")
    local out = {}
    for i = 1, #text, 4 do
        local q = { text:byte(i, i + 3) }
        local n, pad = 0, 0
        for j = 1, 4 do
            local ch = q[j]
            local v
            if not ch or ch == 61 then v = 0 pad = pad + 1 else v = DEC[ch] end
            if not v then error("not a HUF text") end
            n = n * 64 + v
        end
        local a, b, c = math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256
        out[#out + 1] = string.char(a)
        if pad < 2 then out[#out + 1] = string.char(b) end
        if pad < 1 then out[#out + 1] = string.char(c) end
    end
    return table.concat(out)
end

---------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------
-- only what differs from the defaults (import fills the rest back in)
local function Diff(t, d)
    if type(t) ~= "table" or type(d) ~= "table" then
        if t == d then return nil end
        return t
    end
    local out, any = {}, false
    for k, v in pairs(t) do
        local dv = d[k]
        local x
        if type(v) == "table" then x = Diff(v, dv) if x == nil and type(dv) ~= "table" then x = {} end
        elseif v ~= dv then x = v end
        if x ~= nil then out[k] = x any = true end
    end
    return any and out or nil
end

-- settings kept outside the profile, carried along under "_extra":
--   clickcast  this character's click-cast bindings (import: the importing character's)
--   cvars      the game's own settings HUF's pages change (chat, damage numbers)
--   chatColors the game's chat colours
--   configScale the settings window's size
--   places     other addons' windows HUF moves (HUF.RegisterMover with get / set, e.g. MMT's)
-- Not exported: kept chat lines, debug log, internal state.
local GAME_CVARS = { "chatBubbles", "chatBubblesParty", "showTimestamps", "chatStyle", "whisperMode",
    "profanityFilter", "chatMouseScroll", "WorldTextScale_v2", "WorldTextGravity_v2" }
local CHAT_COLOR_TYPES = { "SAY", "YELL", "EMOTE", "PARTY", "PARTY_LEADER", "RAID", "RAID_LEADER", "RAID_WARNING",
    "GUILD", "OFFICER", "WHISPER", "WHISPER_INFORM", "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER", "SYSTEM",
    "CHANNEL1", "CHANNEL2", "CHANNEL3", "CHANNEL4", "CHANNEL5" }
ns.SHARE_CVARS, ns.SHARE_CHAT_COLORS = GAME_CVARS, CHAT_COLOR_TYPES

local function GetCV(name)
    local fn = (C_CVar and C_CVar.GetCVar) or GetCVar
    local ok, v = pcall(fn, name)
    if ok and type(v) == "string" then return v end
end

local function Extra()
    local x = {}
    if ns.ClickCast then
        local d = ns.ClickCast.Data()
        if #d.bindings > 0 or d.enabled == false then x.clickcast = ns.CopyTable(d) end
    end
    local cv = {}
    for _, name in ipairs(GAME_CVARS) do
        local v = GetCV(name)
        if v then cv[name] = v end
    end
    if next(cv) then x.cvars = cv end
    if ChatTypeInfo then
        local cc = {}
        for _, t in ipairs(CHAT_COLOR_TYPES) do
            local i = ChatTypeInfo[t]
            if i and i.r then cc[t] = { r = math.floor(i.r * 1000 + 0.5) / 1000, g = math.floor(i.g * 1000 + 0.5) / 1000,
                b = math.floor(i.b * 1000 + 0.5) / 1000 } end
        end
        if next(cc) then x.chatColors = cc end
    end
    if HUFDB and tonumber(HUFDB.configScale) then x.configScale = tonumber(HUFDB.configScale) end
    local places = {}
    for id, sp in pairs(ns.Movers and ns.Movers.external or {}) do
        if type(sp.get) == "function" then
            local ok, v = pcall(sp.get)
            if ok and v ~= nil then places[id] = type(v) == "table" and ns.CopyTable(v) or v end
        end
    end
    if next(places) then x.places = places end
    return next(x) and x or nil
end

local function ApplyExtra(x)
    if type(x) ~= "table" then return end
    if type(x.clickcast) == "table" and ns.ClickCast then
        HUFDB.clickcast = HUFDB.clickcast or {}
        HUFDB.clickcast[ns.CharKey()] = ns.CopyTable(x.clickcast)
        ns.RunOOC("import clickcast", function() ns.ClickCast.Apply() end)
    end
    if type(x.cvars) == "table" then
        local set = (C_CVar and C_CVar.SetCVar) or SetCVar
        for _, name in ipairs(GAME_CVARS) do
            local v = x.cvars[name]
            if type(v) == "string" and GetCV(name) ~= nil then pcall(set, name, v) end
        end
    end
    if type(x.chatColors) == "table" and ChangeChatColor then
        for _, t in ipairs(CHAT_COLOR_TYPES) do
            local c = x.chatColors[t]
            if type(c) == "table" and tonumber(c.r) and tonumber(c.g) and tonumber(c.b) then
                pcall(ChangeChatColor, t, c.r, c.g, c.b)
            end
        end
    end
    if tonumber(x.configScale) and HUFDB then HUFDB.configScale = tonumber(x.configScale) end
    -- other addons' window places: now, or once the window registers (its addon loads later)
    if type(x.places) == "table" then
        for id, v in pairs(x.places) do
            local sp = ns.Movers and ns.Movers.external[id]
            if sp and type(sp.set) == "function" then
                local ok, err = pcall(sp.set, v)
                if not ok then ns.Print("Placing %s from the import: %s", tostring(sp.label), tostring(err)) end
            elseif HUFDB then
                HUFDB.pendingPlaces = HUFDB.pendingPlaces or {}
                HUFDB.pendingPlaces[id] = v
            end
        end
    end
end
ns.ShareExtra, ns.ShareApplyExtra = Extra, ApplyExtra

function ns.ExportProfile()
    local out = {}
    local changed = Diff(ns.db, ns.DEFAULTS) or {}
    changed.units = changed.units or {}       -- marks it as HUF settings
    changed._extra = Extra()
    Ser(changed, out, 0)
    return PREFIX .. Encode(table.concat(out))
end

-- ok, table or ok=false, error text
function ns.ReadProfileText(text)
    text = ns.Trim(text or "")
    if text == "" then return false, "Paste a HUF profile text first." end
    if text:sub(1, #PREFIX) ~= PREFIX then return false, "That is not a HUF profile text (it starts with " .. PREFIX .. ")." end
    local ok, data = pcall(Decode, text:sub(#PREFIX + 1))
    if not ok then return false, "The text is damaged (incomplete copy?)." end
    local okP, t = pcall(Parse, data)
    if not okP or type(t) ~= "table" then return false, "The text is damaged (incomplete copy?)." end
    if type(t.units) ~= "table" and type(t.global) ~= "table" then return false, "No HUF settings in this text." end
    return true, t
end

-- replaces every setting of the active profile
function ns.ImportProfile(t)
    local name = ns.CurrentProfileName()
    t = ns.CopyTable(t)
    local extra = t._extra
    t._extra = nil
    ApplyExtra(extra)
    HUFDB.profiles[name] = t
    ns.SetProfile(name)
    ns.Log("config", "profile imported into %s", name)
end

-- A HUF profile text's parts, for the import window's tick boxes, and the
-- profile made from the ticked ones (the active profile with those parts
-- replaced; click-cast bindings and the game's chat settings only if ticked)
local HUF_PARTS = {
    { "global", "General (fonts, accent, power colours)" }, { "privacy", "Names & MMT" },
    "UNITS",
    { "nameplates", "Nameplates" }, { "minimap", "Minimap" }, { "dataBars", "Data bars" },
    { "chat", "Chat" }, { "damageMeter", "Damage meter" }, { "bags", "Bags" },
    { "auraBars", "Buff bars" }, { "windows", "Windows" }, { "questLog", "Quest log" },
    { "raid", "Raid frames" }, { "lootFeed", "Loot feed" }, { "tooltip", "Tooltips" },
    { "actionBars", "Action bars" }, { "uiScale", "UI scale" }, { "resets", "Instance reset announce" },
    "OTHER",    -- every other settings table in the text, so nothing is left out silently
}
function ns.ProfileParts(t)
    local parts = {}
    for _, e in ipairs(HUF_PARTS) do
        if e == "UNITS" then
            local units = type(t.units) == "table" and t.units or {}
            for _, list in ipairs({ ns.UNITS, ns.GROUPS }) do
                for _, u in ipairs(list) do
                    if type(units[u.key]) == "table" then
                        parts[#parts + 1] = { title = u.title, tbl = units[u.key], on = true, path = { "units", u.key } }
                    end
                end
            end
        elseif e == "OTHER" then
            local known = { units = true, _extra = true }
            for _, k in ipairs(HUF_PARTS) do if type(k) == "table" then known[k[1]] = true end end
            local rest = {}
            for k, v in pairs(t) do
                if type(k) == "string" and not known[k] and type(v) == "table" then rest[#rest + 1] = k end
            end
            table.sort(rest)
            for _, k in ipairs(rest) do
                parts[#parts + 1] = { title = k, tbl = t[k], on = true, path = { k } }
            end
        elseif type(t[e[1]]) == "table" then
            parts[#parts + 1] = { title = e[2], tbl = t[e[1]], on = true, path = { e[1] } }
        end
    end
    local x = type(t._extra) == "table" and t._extra or {}
    if type(x.clickcast) == "table" then
        parts[#parts + 1] = { title = "Click-cast bindings (this character)", tbl = x.clickcast, on = true, extra = "clickcast" }
    end
    if type(x.cvars) == "table" or type(x.chatColors) == "table" then
        parts[#parts + 1] = { title = "The game's chat settings and colours", tbl = x, on = true, extra = "game" }
    end
    if type(x.places) == "table" and next(x.places) then
        parts[#parts + 1] = { title = "Other addons' window places (MMT and others)", tbl = x.places, on = true, extra = "places" }
    end
    return parts
end
function ns.MergeParts(_, parts, chosen)
    local final = ns.CopyTable(ns.db)
    local extra = {}
    for i, part in ipairs(parts) do
        if chosen[i] then
            if part.path then
                local t = final
                for j = 1, #part.path - 1 do
                    local k = part.path[j]
                    if type(t[k]) ~= "table" then t[k] = {} end
                    t = t[k]
                end
                t[part.path[#part.path]] = ns.CopyTable(part.tbl)
            elseif part.extra == "clickcast" then
                extra.clickcast = ns.CopyTable(part.tbl)
            elseif part.extra == "places" then
                extra.places = ns.CopyTable(part.tbl)
            elseif part.extra == "game" then
                extra.cvars = part.tbl.cvars and ns.CopyTable(part.tbl.cvars) or nil
                extra.chatColors = part.tbl.chatColors and ns.CopyTable(part.tbl.chatColors) or nil
            end
        end
    end
    if next(extra) then final._extra = extra end
    return final
end

-- an import into a new profile (the active one is left as it is): a free
-- name from base ("EllesmereUI", "EllesmereUI 2", ...), switched to
function ns.ImportProfileAsNew(base, t)
    local name, n = base, 1
    while HUFDB.profiles[name] do
        n = n + 1
        name = ("%s %d"):format(base, n)
    end
    t = ns.CopyTable(t)
    local extra = t._extra
    t._extra = nil
    ApplyExtra(extra)
    HUFDB.profiles[name] = t
    ns.SetProfile(name)
    ns.Log("config", "profile imported as %s", name)
    return name
end

ns.ShareTest = { Ser = Ser, Parse = Parse, Encode = Encode, Decode = Decode }
