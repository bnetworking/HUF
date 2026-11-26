-- HUF: the blocks a data bar can show (FPS, latency, clock, gold, audio,
-- durability, combat, friends, guild; more in DataBarBlocksMore.lua). Each type: its icon (the game's own
-- art), its text, tooltip, clicks and when it updates. DataBars.lua builds the
-- bars and lays the blocks out.

local _, ns = ...
local BL = {}
ns.DataBlocks = BL

---------------------------------------------------------------------------
-- Shared helpers
---------------------------------------------------------------------------
-- the game's own art, drawn from its sheet so it can be cropped. trim: the
-- share of the art's width kept (micro menu art has a wide empty border);
-- the height is cut to keep it square. shift: the picture is off the art's
-- centre (a share of its width). coords: a part of a plain file. Sets
-- tex.aspect (width / height of what is shown).
function BL.SetIcon(tex, atlas, file, trim, shift, coords)
    local info = atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)
    local sheet = info and (info.file or info.filename)
    if sheet and info.width and info.width > 0 and info.height and info.height > 0 then
        local l, r, t, b = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
        local aspect = info.width / info.height
        if trim then
            local sy = math.min(1, trim * aspect)        -- the same pixels both ways
            local cx, cy = (l + r) / 2 + (r - l) * (shift or 0), (t + b) / 2
            local hw, hh = (r - l) * trim / 2, (b - t) * sy / 2
            l, r, t, b = cx - hw, cx + hw, cy - hh, cy + hh
            aspect = 1
        end
        tex:SetTexture(sheet)
        tex:SetTexCoord(l, r, t, b)
        tex.aspect = aspect
    else
        tex:SetTexture(file)
        if coords then tex:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        else tex:SetTexCoord(0, 1, 0, 1) end
        tex.aspect = 1
    end
end

function BL.FriendsOnline()
    local n = 0
    if C_FriendList and C_FriendList.GetNumOnlineFriends then
        local ok, v = pcall(C_FriendList.GetNumOnlineFriends)
        if ok and type(v) == "number" then n = n + v end
    end
    if BNGetNumFriends then
        local ok, _, online = pcall(BNGetNumFriends)
        if ok and type(online) == "number" then n = n + online end
    end
    return n
end

function BL.GuildOnline()
    if not (IsInGuild and IsInGuild()) then return nil end
    local ok, _, online = pcall(GetNumGuildMembers)
    return ok and type(online) == "number" and online or 0
end

-- a colour by mode: CLASS | ACCENT | CUSTOM (own); nil for the others
function BL.Tint(mode, custom)
    if mode == "CLASS" then
        local _, cls = UnitClass("player")
        local c = ns.ClassColor(cls)
        if c then return c.r, c.g, c.b end
        return 1, 1, 1
    elseif mode == "ACCENT" then
        local a = ns.ACCENT
        return a[1], a[2], a[3]
    elseif mode == "CUSTOM" and custom then
        return custom.r, custom.g, custom.b
    end
end

-- 0 = bad (red), 1 = good (green), yellow between
local function Grade(p)
    p = math.max(0, math.min(1, p or 0))
    if p < 0.5 then return 1, 0.25 + p * 1.3, 0.2 end
    return 1 - (p - 0.5) * 1.5, 0.9, 0.25
end

local function Line(tt, l, r)
    if r then tt:AddDoubleLine(l, r, 0.8, 0.8, 0.8, 1, 1, 1) else tt:AddLine(l, 0.7, 0.7, 0.7) end
end

local function Latency(mode)
    local _, _, home, world = GetNetStats()
    home, world = home or 0, world or 0
    if mode == "WORLD" then return world end
    if mode == "HIGHER" then return math.max(home, world) end
    return home
end

---------------------------------------------------------------------------
-- The types
---------------------------------------------------------------------------
-- title, icon = { atlas, file, trim, shift, coords }, showIcon (default),
-- settings (defaults), Text(b) -> text [, r, g, b: the value's own colour],
-- Tooltip(b, tt), Click(b, button), Wheel(b, delta), IconFor(b) -> icon,
-- tick (update every second), events (update on these)
BL.TYPES = {}
BL.ORDER = {}
local function Type(key, def)
    def.key = key
    BL.TYPES[key] = def
    BL.ORDER[#BL.ORDER + 1] = key
end

Type("fps", {
    steady = 3,          -- its width from the text with every digit an 8 (at least 3 of them)
    title = "FPS", showIcon = false, tick = true,
    icon = { file = "Interface\\Icons\\INV_Misc_PocketWatch_01" },
    Text = function()
        local n = math.floor((GetFramerate() or 0) + 0.5)
        return n .. "fps", Grade(n / 60)
    end,
    Tooltip = function(_, tt)
        tt:SetText("Performance")
        Line(tt, "Frames per second", math.floor((GetFramerate() or 0) + 0.5))
        Line(tt, "Latency, home", Latency("HOME") .. " ms")
        Line(tt, "Latency, world", Latency("WORLD") .. " ms")
    end,
})

Type("ms", {
    steady = 3,          -- its width from the text with every digit an 8 (at least 3 of them)
    title = "Latency", showIcon = false, tick = true,
    settings = { latency = "HOME" },           -- HOME | WORLD | HIGHER
    icon = { file = "Interface\\Icons\\INV_Misc_PocketWatch_01" },
    Text = function(b)
        local ms = Latency(b.cfg.settings.latency)
        return ms .. "ms", Grade(1 - (ms - 60) / 300)
    end,
    Tooltip = function(_, tt)
        tt:SetText("Latency")
        Line(tt, "Home (chat, auction house)", Latency("HOME") .. " ms")
        Line(tt, "World (combat, other players)", Latency("WORLD") .. " ms")
    end,
})

Type("clock", {
    steady = 1,          -- its width from the text with every digit an 8 (at least 1 of them)
    title = "Clock", showIcon = false, tick = true,
    settings = { twentyFour = true, localTime = true },
    icon = { file = "Interface\\Icons\\INV_Misc_PocketWatch_01" },
    Text = function(b)
        local st = b.cfg.settings
        local h, m
        if st.localTime then
            local t = date("*t")
            h, m = t.hour, t.min
        else
            h, m = GetGameTime()
        end
        if st.twentyFour then return string.format("%02d:%02d", h, m) end
        local pm = h >= 12
        h = h % 12
        if h == 0 then h = 12 end
        return string.format("%d:%02d %s", h, m, pm and "PM" or "AM")
    end,
    Tooltip = function(_, tt)
        local t = date("*t")
        local rh, rm = GetGameTime()
        tt:SetText("Clock")
        Line(tt, "Local time", string.format("%02d:%02d", t.hour, t.min))
        Line(tt, "Realm time", string.format("%02d:%02d", rh or 0, rm or 0))
        Line(tt, "Left-click: stopwatch and alarm. Right-click: calendar.")
    end,
    Click = function(_, button)
        if button == "RightButton" then
            if ToggleCalendar then ToggleCalendar() end
        else
            if not TimeManager_Toggle and C_AddOns and C_AddOns.LoadAddOn then pcall(C_AddOns.LoadAddOn, "Blizzard_TimeManager") end
            if TimeManager_Toggle then TimeManager_Toggle() end
        end
    end,
})

-- gold: this session's change in the tooltip
local sessionStart
local COIN = { Gold = "ffd700", Silver = "c7c7cf", Copper = "eda55f" }
local function Abbrev(n)
    if n >= 1000000 then return string.format("%.1fm", n / 1000000) end
    if n >= 10000 then return string.format("%.1fk", n / 1000) end
    return tostring(n)
end
local function Money(m, st)
    m = math.abs(m or 0)
    local g, s, c = math.floor(m / 10000), math.floor(m / 100) % 100, m % 100
    local function unit(n, kind)
        if st.coinIcons then return n .. "|TInterface\\MoneyFrame\\UI-" .. kind .. "Icon:0:0:2:0|t" end
        local letter = kind:sub(1, 1):lower()
        if st.coinColor then return n .. "|cff" .. COIN[kind] .. letter .. "|r" end
        return n .. letter
    end
    local gs = st.abbreviate and Abbrev(g) or (BreakUpLargeNumbers and BreakUpLargeNumbers(g) or tostring(g))
    local parts = {}
    if g > 0 or not st.showSmall then parts[#parts + 1] = unit(gs, "Gold") end
    if st.showSmall then
        if g > 0 or s > 0 then parts[#parts + 1] = unit(s, "Silver") end
        parts[#parts + 1] = unit(c, "Copper")
    end
    return table.concat(parts, " ")
end
Type("gold", {
    title = "Gold", showIcon = false,
    settings = { showSmall = false, coinIcons = true, coinColor = true, abbreviate = false },
    icon = { file = "Interface\\MoneyFrame\\UI-GoldIcon" },
    events = { "PLAYER_MONEY", "PLAYER_ENTERING_WORLD" },
    Text = function(b)
        local m = GetMoney() or 0
        sessionStart = sessionStart or m
        return Money(m, b.cfg.settings)
    end,
    Tooltip = function(b, tt)
        local m = GetMoney() or 0
        local diff = m - (sessionStart or m)
        local all = { showSmall = true, coinIcons = true }
        tt:SetText("Gold")
        Line(tt, "On this character", Money(m, all))
        Line(tt, diff >= 0 and "Earned this session" or "Spent this session", Money(diff, all))
        Line(tt, "Click: bags.")
    end,
    Click = function() if ToggleAllBags then ToggleAllBags() end end,
})

local CHANNELS = {
    master = { cvar = "Sound_MasterVolume", name = "Master" },
    music = { cvar = "Sound_MusicVolume", name = "Music" },
    sfx = { cvar = "Sound_SFXVolume", name = "Effects" },
    ambience = { cvar = "Sound_AmbienceVolume", name = "Ambience" },
    dialog = { cvar = "Sound_DialogVolume", name = "Dialog" },
}
BL.CHANNEL_ORDER = { "master", "music", "sfx", "ambience", "dialog" }
BL.CHANNELS = CHANNELS
local function Muted() return GetCVar("Sound_EnableAllSound") == "0" end
local function Channel(b) return CHANNELS[b.cfg.settings.channel] or CHANNELS.master end
Type("audio", {
    steady = 3,          -- its width from the text with every digit an 8 (at least 3 of them)
    title = "Audio", showIcon = true,
    settings = { channel = "master", style = "TEXT" },     -- style: TEXT (63%) | BAR (a volume bar)
    -- the volume bar (style BAR): how full, its colour (red when muted)
    Bar = function(b)
        local v = tonumber(GetCVar(Channel(b).cvar)) or 0
        if Muted() then return v, 0.85, 0.2, 0.2 end
        local a = ns.ACCENT
        return v, a[1], a[2], a[3]
    end,
    icon = { atlas = "voicechat-icon-speaker", file = "Interface\\Common\\VoiceChat-Speaker" },
    events = { "CVAR_UPDATE" },
    IconFor = function()
        if Muted() then return { atlas = "voicechat-icon-speaker-mute", file = "Interface\\Common\\VoiceChat-Muted" } end
        return { atlas = "voicechat-icon-speaker", file = "Interface\\Common\\VoiceChat-Speaker" }
    end,
    Text = function(b)
        if Muted() then return "Muted", 1, 0.3, 0.3 end
        local v = tonumber(GetCVar(Channel(b).cvar)) or 0
        return math.floor(v * 100 + 0.5) .. "%"
    end,
    Tooltip = function(b, tt)
        tt:SetText("Audio: " .. Channel(b).name)
        for _, k in ipairs(BL.CHANNEL_ORDER) do
            local c = CHANNELS[k]
            Line(tt, c.name, math.floor((tonumber(GetCVar(c.cvar)) or 0) * 100 + 0.5) .. "%")
        end
        Line(tt, "Mouse wheel: volume. Left-click: sound on / off. Right-click: next channel.")
    end,
    Click = function(b, button)
        if button == "RightButton" then
            local cur = b.cfg.settings.channel
            for i, k in ipairs(BL.CHANNEL_ORDER) do
                if k == cur then b.cfg.settings.channel = BL.CHANNEL_ORDER[i % #BL.CHANNEL_ORDER + 1] break end
            end
        else
            SetCVar("Sound_EnableAllSound", Muted() and "1" or "0")
        end
    end,
    Wheel = function(b, delta)
        local c = Channel(b).cvar
        local v = (tonumber(GetCVar(c)) or 0) + delta * 0.05
        SetCVar(c, string.format("%.2f", math.max(0, math.min(1, v))))
    end,
})

local SLOTS = { 1, 3, 5, 6, 7, 8, 9, 10, 16, 17, 18 }
local function Durability()
    local lo, any = 1, false
    for _, slot in ipairs(SLOTS) do
        local c, m = GetInventoryItemDurability(slot)
        if c and m and m > 0 then any = true lo = math.min(lo, c / m) end
    end
    return any and lo or nil
end
Type("durability", {
    steady = 3,          -- its width from the text with every digit an 8 (at least 3 of them)
    title = "Durability", showIcon = true,
    icon = { file = "Interface\\Minimap\\Tracking\\Repair" },
    events = { "UPDATE_INVENTORY_DURABILITY", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_ENTERING_WORLD" },
    Text = function()
        local d = Durability()
        if not d then return "-" end
        return math.floor(d * 100 + 0.5) .. "%", Grade(d)
    end,
    Tooltip = function(_, tt)
        tt:SetText("Durability")
        for _, slot in ipairs(SLOTS) do
            local c, m = GetInventoryItemDurability(slot)
            local link = GetInventoryItemLink("player", slot)
            if c and m and m > 0 and link then
                local p = c / m
                local r, g, bl = Grade(p)
                tt:AddDoubleLine(link, math.floor(p * 100 + 0.5) .. "%", 1, 1, 1, r, g, bl)
            end
        end
        Line(tt, "Click: character.")
    end,
    Click = function() if ToggleCharacter then ToggleCharacter("PaperDollFrame") end end,
})

local combatSince
Type("combat", {
    title = "Combat", showIcon = false, tick = true,
    settings = { onlyInCombat = false, timer = false },
    icon = { file = "Interface\\CharacterFrame\\UI-StateIcon", coords = { 0.5, 1, 0, 0.49 } },
    events = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" },
    Text = function(b)
        local st = b.cfg.settings
        if UnitAffectingCombat("player") then
            combatSince = combatSince or GetTime()
            local t = ""
            if st.timer then
                local s = math.floor(GetTime() - combatSince)
                t = string.format(" %d:%02d", math.floor(s / 60), s % 60)
            end
            return "In combat" .. t, 1, 0.3, 0.3
        end
        combatSince = nil
        if st.onlyInCombat then return "" end
        return "Out of combat", 0.45, 0.85, 0.45
    end,
})

Type("friends", {
    steady = 1,          -- its width from the text with every digit an 8 (at least 1 of them)
    title = "Friends online", showIcon = true,
    icon = { atlas = "socialqueuing-icon-group", file = "Interface\\FriendsFrame\\UI-Toast-FriendOnlineIcon" },
    events = { "FRIENDLIST_UPDATE", "BN_FRIEND_ACCOUNT_ONLINE", "BN_FRIEND_ACCOUNT_OFFLINE" },
    Text = function() return tostring(BL.FriendsOnline()) end,
    Tooltip = function(_, tt)
        tt:SetText("Friends online")
        Line(tt, "Online", BL.FriendsOnline())
        Line(tt, "Click: friends list.")
    end,
    Click = function() if ToggleFriendsFrame then ToggleFriendsFrame() end end,
})

Type("guild", {
    steady = 1,          -- its width from the text with every digit an 8 (at least 1 of them)
    title = "Guild online", showIcon = true,
    icon = { atlas = "UI-HUD-MicroMenu-GuildCommunities-Up", trim = 0.62, shift = 0.05,
             file = "Interface\\GossipFrame\\TabardGossipIcon" },
    events = { "GUILD_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE" },
    Text = function()
        local n = BL.GuildOnline()
        return n and tostring(n) or ""
    end,
    Tooltip = function(_, tt)
        tt:SetText("Guild")
        local n = BL.GuildOnline()
        Line(tt, n and "Online" or "Not in a guild", n)
        Line(tt, "Click: guild window.")
    end,
    Click = function()
        if ToggleGuildFrame then ToggleGuildFrame()
        elseif ToggleCommunitiesFrame then ToggleCommunitiesFrame() end
    end,
})

-- for the other block files (DataBarBlocksMore.lua)
BL.Type, BL.Line, BL.Grade, BL.Money, BL.Abbrev = Type, Line, Grade, Money, Abbrev

-- the choices for the settings page (a type with available() only while that is true:
-- the MMT team blocks while MMT is on)
function BL.Choices()
    local l = {}
    for _, k in ipairs(BL.ORDER) do
        local def = BL.TYPES[k]
        if not def.available or def.available() then l[#l + 1] = { value = k, text = def.title } end
    end
    return l
end

-- a new block of a type, with its defaults
function BL.New(key)
    local def = BL.TYPES[key]
    if not def then return nil end
    return {
        type = key, scale = 100, align = "CENTER", padL = 10, padR = 10, fill = false,
        width = 0,              -- a width of its own (dragging its edge while arranging); 0 = from its content
        center = false,         -- kept in the middle of the bar (spacing by content)
        showIcon = def.showIcon and true or false,
        textColor = "WHITE", textCustom = { r = 1, g = 1, b = 1 },
        iconColor = "MONO", iconCustom = { r = 0.85, g = 0.85, b = 0.88 },
        settings = ns.CopyTable(def.settings or {}),
    }
end

-- fills what an older or imported block is missing
function BL.Fill(cfg)
    local fresh = BL.New(cfg.type)
    if fresh then ns.FillDefaults(cfg, fresh) end
    return cfg
end
