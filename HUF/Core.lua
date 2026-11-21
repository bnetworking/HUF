-- HUF - Hivemind Unitframes: core (settings, media, accent, profiles, events).
--
-- Settings live in HUFDB (account-wide): HUFDB.profiles[name] holds every
-- frame's settings, HUFDB.chars["First Last-Realm"] the profile a character
-- uses. ns.db is the active profile, ns.db.units[key] one frame's settings.

local ADDON, ns = ...
_G.HUF = ns                      -- public: other addons (MMT) reach HUF here

ns.name = ADDON
ns.version = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version"))
    or (GetAddOnMetadata and GetAddOnMetadata(ADDON, "Version")) or "0.3.27"
ns.API_VERSION = 1
ns.MEDIA = "Interface\\AddOns\\HUF\\Media\\"
ns.LOGO = ns.MEDIA .. "Logo"

---------------------------------------------------------------------------
-- Accent colour (blue / purple / bronze or your own). ns.ACCENT is one table
-- whose values change in place, so everything holding it sees the new colour.
---------------------------------------------------------------------------
ns.ACCENTS = {
    { value = "BLUE",   text = "Blue",   color = { 0.31, 0.70, 1.00 } },
    { value = "PURPLE", text = "Purple", color = { 0.64, 0.42, 1.00 } },
    { value = "BRONZE", text = "Bronze", color = { 0.80, 0.56, 0.27 } },
    { value = "CUSTOM", text = "Custom" },
}
ns.ACCENT = { 0.31, 0.70, 1.00 }

function ns.ApplyAccent()
    local g = ns.db and ns.db.global
    local c
    if g and g.accent == "CUSTOM" then
        c = { g.accentColor.r, g.accentColor.g, g.accentColor.b }
    else
        for _, a in ipairs(ns.ACCENTS) do
            if g and a.value == g.accent then c = a.color end
        end
    end
    c = c or ns.ACCENTS[1].color
    ns.ACCENT[1], ns.ACCENT[2], ns.ACCENT[3] = c[1], c[2], c[3]
end

function ns.AccentColor()
    return { r = ns.ACCENT[1], g = ns.ACCENT[2], b = ns.ACCENT[3] }
end

---------------------------------------------------------------------------
-- Frames HUF draws (more follow: target of target, focus target, group,
-- raid, nameplates)
---------------------------------------------------------------------------
ns.UNITS = {
    { key = "player", unit = "player", title = "Player" },
    { key = "target", unit = "target", title = "Target" },
    { key = "targettarget", unit = "targettarget", title = "Target of target", polled = true },
    { key = "pet", unit = "pet", title = "Pet", noAuras = true },
}
-- frames of several units (a secure group header): raid follows later
ns.GROUPS = {
    { key = "party", title = "Group", group = true },
}
ns.UNIT_BY_KEY = {}
for _, u in ipairs(ns.UNITS) do ns.UNIT_BY_KEY[u.key] = u end
for _, u in ipairs(ns.GROUPS) do ns.UNIT_BY_KEY[u.key] = u end
-- every frame with a settings page, in page order
ns.FRAME_KEYS = {}
for _, u in ipairs(ns.UNITS) do ns.FRAME_KEYS[#ns.FRAME_KEYS + 1] = u end
for _, u in ipairs(ns.GROUPS) do ns.FRAME_KEYS[#ns.FRAME_KEYS + 1] = u end

---------------------------------------------------------------------------
-- Media: HUF's own, the game's, EllesmereUI's (when installed, used from its
-- folder), LibSharedMedia's (when present)
---------------------------------------------------------------------------
local EUI = "Interface\\AddOns\\EllesmereUI\\media\\"
local function Installed(addon)
    local info = (C_AddOns and C_AddOns.GetAddOnInfo) or GetAddOnInfo
    if not info then return false end
    local ok, name, _, _, _, reason = pcall(info, addon)
    return ok and name ~= nil and reason ~= "MISSING"
end

ns.fonts = {
    -- come with HUF (SIL Open Font License, Media\Fonts\OFL-*.txt)
    { name = "Barlow Condensed", path = ns.MEDIA .. "Fonts\\BarlowCondensed-SemiBold.ttf" },   -- HUF's default
    { name = "Roboto Condensed", path = ns.MEDIA .. "Fonts\\RobotoCondensed-SemiBold.ttf" },
    { name = "Friz Quadrata", path = "Fonts\\FRIZQT__.TTF" },
    { name = "Arial Narrow",  path = "Fonts\\ARIALN.TTF" },
    { name = "Morpheus",      path = "Fonts\\MORPHEUS.TTF" },
    { name = "Skurri",        path = "Fonts\\SKURRI.TTF" },
}
local EUI_FONTS = {
    "Expressway", "Expressway Bold", "Expressway CAPS", "Arial Bold", "Avant Garde Naowh", "Barlow Condensed",
    "Changa", "Cinzel Decorative", "Exo", "FiraSans Bold", "FiraSans Medium", "FiraSans Light", "Future X Black",
    "Gotham Narrow", "Gotham Narrow Ultra", "Homespun", "HWT Artz", "KMT Kimberley", "Poppins", "Russo One", "Ubuntu",
}
local EUI_FONT_FILES = {
    ["Expressway"] = "Expressway.TTF", ["Expressway Bold"] = "Expressway Bold.ttf", ["Expressway CAPS"] = "Expressway CAPS.ttf",
    ["Arial Bold"] = "Arial Bold.TTF", ["Avant Garde Naowh"] = "Avant Garde Naowh.ttf", ["Barlow Condensed"] = "Barlow Condensed.ttf",
    ["Changa"] = "Changa.ttf", ["Cinzel Decorative"] = "Cinzel Decorative.ttf", ["Exo"] = "Exo.otf",
    ["FiraSans Bold"] = "FiraSans Bold.ttf", ["FiraSans Medium"] = "FiraSans Medium.ttf", ["FiraSans Light"] = "FiraSans Light.ttf",
    ["Future X Black"] = "Future X Black.otf", ["Gotham Narrow"] = "Gotham Narrow.otf", ["Gotham Narrow Ultra"] = "Gotham Narrow Ultra.otf",
    ["Homespun"] = "Homespun.ttf", ["HWT Artz"] = "HWT Artz.ttf", ["KMT Kimberley"] = "KMT Kimberley.otf",
    ["Poppins"] = "Poppins.ttf", ["Russo One"] = "Russo One.ttf", ["Ubuntu"] = "Ubuntu.ttf",
}

ns.textures = {
    { name = "Flat",      path = "Interface\\Buttons\\WHITE8X8" },
    { name = "Smooth",    path = ns.MEDIA .. "Bars\\Smooth" },
    { name = "Gloss",     path = ns.MEDIA .. "Bars\\Gloss" },
    { name = "Matte",     path = ns.MEDIA .. "Bars\\Matte" },
    { name = "Bevel",     path = ns.MEDIA .. "Bars\\Bevel" },
    { name = "Soft",      path = ns.MEDIA .. "Bars\\Soft" },
    { name = "Stripes",   path = ns.MEDIA .. "Bars\\Stripes" },
    { name = "Honeycomb", path = ns.MEDIA .. "Bars\\Honeycomb" },
    { name = "Brushed",   path = ns.MEDIA .. "Bars\\Brushed" },
    { name = "Fade",      path = ns.MEDIA .. "Bars\\Fade" },
    { name = "Blizzard",  path = "Interface\\TargetingFrame\\UI-StatusBar" },
    { name = "Blizzard Raid", path = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" },
}
local EUI_TEXTURES = { "atrocity", "beautiful", "divide", "fade", "fade-right", "glass", "gradient-bt", "gradient-lr",
    "gradient-rl", "gradient-sharp", "gradient-tb", "matte", "plating", "sheer", "pixels-fill",
    "melli", "thin-line-top", "thin-line-bottom", "pixels-dark", "pixels-bg" }

-- tile = repeats (small patterns), else stretched
ns.backgrounds = {
    { name = "None" },
    { name = "Plain" },
    { name = "Honeycomb", path = ns.MEDIA .. "Backgrounds\\Honeycomb", tile = true },
    { name = "Carbon",    path = ns.MEDIA .. "Backgrounds\\Carbon", tile = true },
    { name = "Noise",     path = ns.MEDIA .. "Backgrounds\\Noise", tile = true },
    { name = "Brushed",   path = ns.MEDIA .. "Backgrounds\\Brushed", tile = true },
    { name = "Lines",     path = ns.MEDIA .. "Backgrounds\\Lines", tile = true },
    { name = "Vignette",  path = ns.MEDIA .. "Backgrounds\\Vignette" },
    { name = "Rock",      path = "Interface\\FrameGeneral\\UI-Background-Rock", tile = true },
    { name = "Marble",    path = "Interface\\FrameGeneral\\UI-Background-Marble", tile = true },
    { name = "Dialog",    path = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark", tile = true },
}

function ns.LoadMedia()
    if Installed("EllesmereUI") then
        ns.ellesmere = true
        for _, name in ipairs(EUI_FONTS) do
            -- EllesmereUI's own copy of a font HUF brings: listed as "(EUI)"
            local taken = false
            for _, f in ipairs(ns.fonts) do if f.name == name then taken = true end end
            local shown = taken and (name .. " (EUI)") or name
            ns.fonts[#ns.fonts + 1] = { name = shown, path = EUI .. "fonts\\" .. EUI_FONT_FILES[name], ellesmere = true }
        end
        for _, file in ipairs(EUI_TEXTURES) do
            local nice = file:gsub("%-", " "):gsub("(%a)([%w]*)", function(a, b) return a:upper() .. b end)
            ns.textures[#ns.textures + 1] = { name = "EUI " .. nice, path = EUI .. "textures\\" .. file, ellesmere = true }
        end
    end
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if not LSM then return end
    local function Add(list, kind)
        local known = {}
        for _, e in ipairs(list) do known[e.name] = true end
        for _, name in ipairs(LSM:List(kind) or {}) do
            if not known[name] then list[#list + 1] = { name = name, path = LSM:Fetch(kind, name) } end
        end
    end
    pcall(Add, ns.fonts, "font")
    pcall(Add, ns.textures, "statusbar")
end
-- now, so the lists are complete before any frame is drawn
ns.LoadMedia()

local function Lookup(list, name)
    for _, e in ipairs(list) do
        if e.name == name then return e end
    end
    return nil
end

local DEFAULT_FONT = "Fonts\\FRIZQT__.TTF"
function ns.FontPath(name)
    if name == nil or name == "GLOBAL" then name = ns.db and ns.db.global.font end
    local e = Lookup(ns.fonts, name)
    if e then return e.path end
    if type(name) == "string" and name:find("\\", 1, true) then return name end
    return ns.fonts[1].path        -- a font that is gone (e.g. Expressway without EllesmereUI): HUF's default
end

function ns.TexturePath(name)
    local e = Lookup(ns.textures, name)
    return e and e.path or "Interface\\Buttons\\WHITE8X8"
end

function ns.Background(name)
    return Lookup(ns.backgrounds, name) or ns.backgrounds[1]
end

-- outline "GLOBAL" = the General page's choice
function ns.ApplyFont(fs, name, size, outline, shadow)
    if outline == nil or outline == "GLOBAL" then outline = ns.db and ns.db.global.outline or "OUTLINE" end
    outline = (outline and outline ~= "NONE") and outline or ""
    if not fs:SetFont(ns.FontPath(name), size, outline) then
        fs:SetFont(DEFAULT_FONT, size, outline)
    end
    if shadow == nil then shadow = ns.db and ns.db.global.shadow end
    fs:SetShadowOffset(shadow and 1 or 0, shadow and -1 or 0)
    fs:SetShadowColor(0, 0, 0, shadow and 1 or 0)
end

---------------------------------------------------------------------------
-- Secret values (12.x engine): never compare, do arithmetic on, or index
-- with a secret. They may only be handed to setters (SetValue, SetText ...).
---------------------------------------------------------------------------
local issecretvalue = issecretvalue
function ns.IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end
local IsSecret = ns.IsSecret

function ns.Safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d = pcall(fn, ...)
    if not ok or IsSecret(a) then return nil end
    return a, b, c, d
end

function ns.Bool(v, default)
    if IsSecret(v) then return default or false end
    return v and true or false
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local PREFIX = "|cff4fb3ffHUF|r: "
function ns.Print(fmt, ...)
    local msg = select("#", ...) > 0 and fmt:format(...) or tostring(fmt)
    local a = ns.ACCENT
    local prefix = ("|cff%02x%02x%02xHUF|r: "):format(a[1] * 255, a[2] * 255, a[3] * 255)
    DEFAULT_CHAT_FRAME:AddMessage(prefix .. msg)
end

function ns.Trim(s) return ((s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

function ns.CopyTable(t)
    if type(t) ~= "table" then return t end
    local c = {}
    for k, v in pairs(t) do c[k] = ns.CopyTable(v) end
    return c
end

local function FillDefaults(t, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(t[k]) ~= "table" then t[k] = {} end
            FillDefaults(t[k], v)
        elseif t[k] == nil or type(t[k]) ~= type(v) then
            t[k] = v
        end
    end
    return t
end
ns.FillDefaults = FillDefaults

---------------------------------------------------------------------------
-- Defaults
---------------------------------------------------------------------------
local function C(r, g, b) return { r = r, g = g, b = b } end
local DARK_GREEN = C(0.08, 0.40, 0.16)
local BORDER = C(0.06, 0.06, 0.07)

-- the 9 text anchors of a bar
ns.ANCHORS = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }
ns.ANCHOR_TEXT = {
    TOPLEFT = "Top left", TOP = "Top center", TOPRIGHT = "Top right",
    LEFT = "Middle left", CENTER = "Middle center", RIGHT = "Middle right",
    BOTTOMLEFT = "Bottom left", BOTTOM = "Bottom center", BOTTOMRIGHT = "Bottom right",
}

local function Anchor(text, size)
    return {
        text = text or "",          -- template with values: "[hp] ([hp%])"
        font = "GLOBAL", size = size or 12, outline = "OUTLINE",
        colorMode = "WHITE",        -- WHITE | CUSTOM | CLASS | ACCENT | STATUS (health %)
        color = C(1, 1, 1),
        hideFull = false,           -- STATUS: invisible at full health
        x = 0, y = 0,
    }
end

local function Texts(fill)
    local t = {}
    for _, a in ipairs(ns.ANCHORS) do t[a] = Anchor("", 12) end
    for a, v in pairs(fill or {}) do t[a] = Anchor(v[1], v[2]) end
    return t
end

local function Bar(colorMode)
    return {
        texture = "Fade",
        reverse = false,
        colorMode = colorMode,      -- STATIC | GRADIENT | CLASS | STATUS | TYPE
        color = C(0.20, 0.65, 0.30),
        gradStart = ns.CopyTable(DARK_GREEN), gradStartAccent = false,
        gradEnd = C(0.31, 0.70, 1.00), gradEndAccent = true,
        high = C(0.20, 0.75, 0.30), mid = C(1.00, 0.70, 0.10), low = C(0.85, 0.15, 0.15),   -- status: >75% / >40% / below
        npcReaction = true,         -- class mode: NPCs in reaction colours
        deadGray = true,
        bgTexture = "Honeycomb", bgColor = C(0.55, 0.55, 0.58), bgAlpha = 1,
        borderSize = 1, borderColor = ns.CopyTable(BORDER), borderAlpha = 1,
    }
end

-- buff / debuff icons of a unit frame
local function AuraRow(on, position)
    return { enabled = on, mine = false, size = 20, gap = 2, perRow = 6, rows = 4,
             position = position, offset = 2, x = 0, y = 0, countSize = 9, timer = true,
             timerText = false, timerSize = 0,       -- time left as numbers; size 0: from the icon size
             filter = "ALL",         -- debuffs ALL | RAID | DISPELLABLE | TEAM (my group can) | CC; buffs ALL | RAID | DEFENSIVE | CANCELABLE
             ccFirst = false,        -- debuffs: crowd control first
             hideSated = false,      -- debuffs: no Sated / Exhaustion
             grow = "AUTO",          -- AUTO (from the position) | LEFT | RIGHT
             borderSize = 1,         -- the black edge around each icon
             dispelBorder = false }  -- debuffs: the edge in the debuff type's colour
end

local function UnitDefaults(point)
    local u = {
        enabled = true,
        width = 175, height = 24, scale = 1, alpha = 1,
        point = point,
        anchorTo = "SCREEN",        -- SCREEN or another frame's key: point is relative to it
        tooltip = true,
        frameBg = "None", frameBgColor = C(0.04, 0.04, 0.05), frameBgAlpha = 0.9, framePad = 0,
        portrait = { enabled = false, mode = "3D", side = "LEFT", gap = 1,
                     borderSize = 1, borderColor = ns.CopyTable(BORDER) },
        health = Bar("GRADIENT"),
        power = Bar("TYPE"),
        texts = {},
        debuffs = AuraRow(true, "BELOW_LEFT"),    -- small icons under the frame
        buffs = AuraRow(false, "ABOVE_LEFT"),
        -- incoming heals on the health bar: semi-transparent green after the
        -- filled part, may run past the bar's end by up to `overheal` %
        healPred = { enabled = true, color = C(0.25, 0.95, 0.45), alpha = 0.45, overheal = 10 },
        -- cast bar on the line between health and power bar, spell icon at the
        -- left inner edge (may be taller than the bar)
        castBar = { enabled = false, height = 5, x = 0, y = 0, texture = "Fade", color = C(1.00, 0.70, 0.20),
                    bgAlpha = 0.85, borderSize = 1, icon = true, iconSize = 14,
                    text = false, font = "GLOBAL", fontSize = 10, outline = "GLOBAL", textAlign = "CENTER",
                    interrupt = true, interruptColor = C(0.85, 0.15, 0.15), interruptTime = 1 },
    }
    u.power.enabled = true
    u.power.size = 9                -- health = height - power - gap = 14
    u.power.gap = 1
    u.power.divider = true          -- gap 0: a line between health and power (off: one border around both)
    u.power.color = C(0.25, 0.45, 1.00)
    return u
end

local function BuildDefaults()
    local u = {}
    -- Player: health dark green -> accent, "[hp]" bottom left; power "[mp]" middle right
    u.player = UnitDefaults({ "CENTER", "CENTER", -260, -200 })
    u.player.texts.health = Texts({ BOTTOMLEFT = { "[hp]", 24 } })
    u.player.texts.power = Texts({ RIGHT = { "[mp]", 12 } })
    u.player.hideBlizzardAuras = false      -- Blizzard's buff / debuff icons (top right)

    -- Target: health accent -> dark green, "[hp] ([hp%])" bottom right;
    -- power "55E | Northshire Guard" bottom left
    u.target = UnitDefaults({ "CENTER", "CENTER", 260, -200 })
    u.target.health.gradStart = C(0.31, 0.70, 1.00)
    u.target.health.gradStartAccent = true
    u.target.health.gradEnd = ns.CopyTable(DARK_GREEN)
    u.target.health.gradEndAccent = false
    u.target.texts.health = Texts({ BOTTOMRIGHT = { "[hp] ([hp%])", 24 } })
    u.target.texts.power = Texts({ BOTTOMLEFT = { "[levelclass:color] | [name]", 12 } })
    -- combo points (rogue, cat druid): a row of points above the frame
    u.target.combo = { enabled = true, pos = "ABOVE", x = 0, y = 2, width = 0, height = 5, gap = 2,
                       color = C(1.00, 0.82, 0.10), bgAlpha = 0.6, hideEmpty = true }

    -- Target of target: at the bottom right of the target frame, health only
    u.targettarget = UnitDefaults({ "TOPLEFT", "BOTTOMRIGHT", -20, -5 })
    u.targettarget.anchorTo = "target"
    u.targettarget.point[4] = -25
    u.targettarget.height = 16
    u.targettarget.power.enabled = false
    u.targettarget.health.gradStart = C(0.31, 0.70, 1.00)
    u.targettarget.health.gradStartAccent = true
    u.targettarget.health.gradEnd = ns.CopyTable(DARK_GREEN)
    u.targettarget.health.gradEndAccent = false
    u.targettarget.texts.health = Texts({ LEFT = { "[name]", 12 }, RIGHT = { "[hp%]", 12 } })
    u.targettarget.texts.power = Texts()
    u.targettarget.debuffs.enabled = false

    -- Pet: the player frame's look (175 x 20, health in status colours, 3 px
    -- power bar, health text 17, no power text), below the player frame on
    -- the left, no buffs / debuffs, no incoming heals
    local pet = ns.CopyTable(u.player)
    pet.hideBlizzardAuras = nil
    pet.anchorTo = "player"
    pet.point = { "BOTTOMLEFT", "BOTTOMLEFT", -140, -45 }
    pet.height = 20
    pet.health.colorMode = "STATUS"
    pet.power.size = 3
    pet.texts.health.BOTTOMLEFT.size = 17
    pet.texts.power.RIGHT.text = ""
    pet.debuffs.enabled = false
    pet.buffs.enabled = false
    pet.healPred.enabled = false
    -- hunter pet happiness on the right side of the health bar
    pet.happiness = { enabled = true, mode = "ICON", size = 20, x = -2, y = 0 }
    u.pet = pet

    -- Group (party): 200 x 25, health 18 + power 7, class colours; missing
    -- health top center in status colour (hidden at full health); name, level
    -- and power % on the power bar, reaching below it; my buffs top left,
    -- debuffs top right
    local g = UnitDefaults({ "TOPLEFT", "TOPLEFT", 40, -300 })
    g.width, g.height = 125, 28
    g.power.size, g.power.gap = 7, 0
    g.health.colorMode = "CLASS"
    g.texts.health = Texts({ TOP = { "[hp:missing]", 18 } })
    g.texts.health.TOP.colorMode = "STATUS"
    g.texts.health.TOP.hideFull = true
    g.texts.power = Texts({ CENTER = { "[name]", 12 }, LEFT = { "[level]", 12 }, RIGHT = { "[mp%]", 12 } })
    for _, a in ipairs({ "CENTER", "LEFT", "RIGHT" }) do g.texts.power[a].y = -5 end
    g.buffs = AuraRow(true, "ABOVE_LEFT")
    g.buffs.mine = true
    g.debuffs = AuraRow(true, "ABOVE_RIGHT")
    for _, r in ipairs({ g.buffs, g.debuffs }) do r.size, r.perRow, r.rows, r.offset = 16, 5, 1, 1 end
    g.buffs.position, g.buffs.offset = "BELOW_LEFT", 8     -- my HoTs under the frame
    g.castBar.enabled = true
    g.group = {
        showPlayer = true,          -- me in the group frames
        orientation = "DOWN",       -- growth: DOWN (vertical, top to bottom) | UP | RIGHT (horizontal, left to right) | LEFT
        sort = "NAME",              -- NAME (alphabetical) | INDEX (Blizzard's party order) | CLASS
        spacing = 10,               -- padding, vertical
        spacingH = 2,               -- padding, horizontal
        range = true,               -- members out of range faded
        rangeAlpha = 0.4,
    }
    u.party = g

    return {
        global = {
            accent = "BLUE", accentColor = C(0.31, 0.70, 1.00),
            font = "Barlow Condensed", -- comes with HUF (Media\\Fonts)
            outline = "OUTLINE",
            shadow = false,
            abbreviate = true,         -- 12.3k instead of 12345
            shortenTexts = false,      -- a left text next to a right text cut short ("Burnin...")
            statusText = true,         -- "Dead", "Ghost", "Offline" instead of health values
            hideBlizzard = true,
            hideRaidManager = true,    -- Blizzard's raid / party manager on the left edge
            menuMode = "PROXY",        -- right-click menu: PROXY (secure proxy, 12.x) | DIRECT
            clickCast = true,
            configBg = "None",         -- background of the settings window
            powerColors = "GAME",      -- power bars by type: GAME (the game's colours) | CUSTOM (below)
            customPower = {            -- softer than the game's (mana 0, 0.55, 1: EllesmereUI's)
                MANA = C(0.00, 0.55, 1.00), RAGE = C(0.90, 0.15, 0.15),
                ENERGY = C(1.00, 0.96, 0.41), FOCUS = C(0.87, 0.57, 0.22),
                RUNIC_POWER = C(0.77, 0.12, 0.23),
            },
        },
        privacy = {
            mode = "FIRST",            -- [name]: FIRST | LAST | FULL | CLASS | SLOT
            mmt = "ALWAYS",            -- MMT team members: ALWAYS | OUTSIDE (only with MMT's "hide outside") | NEVER
        },
        units = u,
        -- damage meter: the game's meter data in a HUF window, privacy names
        damageMeter = {
            enabled = true,
            hideBlizzard = true,        -- Blizzard's meter window off (CVar damageMeterEnabled, put back when off)
            show = "ALWAYS",            -- ALWAYS | GROUP | INSTANCE
            meterType = "DamageDone",
            session = "CURRENT",        -- CURRENT | OVERALL | a fight's session id
            point = { "BOTTOMRIGHT", "BOTTOMRIGHT", -40, 220 },
            width = 200, rows = 6, rowHeight = 17, rowGap = 1, scale = 1,
            windowCount = 1,            -- windows (each its own list, fight, position: windows[i])
            locked = false,
            texture = "Fade", colorMode = "CLASS", color = C(0.35, 0.55, 0.85),   -- CLASS | ACCENT | STATIC
            bgAlpha = 0.75,
            font = "GLOBAL", fontSize = 12, titleSize = 11, outline = "OUTLINE",
            showRank = true,
            numbers = "BOTH",           -- BOTH "12.3K (845)" | TOTAL | PERSECOND
            threatPets = true,          -- threat view: pets too
            threatColors = true,        -- threat view: bars in the game's threat colours
            fadeOOC = true, fadeAlpha = 0.4,   -- out of combat: windows at this opacity (full under the mouse)
            hideThreatOOC = true,       -- windows showing threat: hidden out of combat
            -- look (defaults: HUF's own; an EllesmereUI import sets Ellesmere's)
            bgColor = C(0.04, 0.04, 0.05),
            windowBorder = true,        -- a thin grey line around each window
            titleHeight = 20,
            titleColor = C(0.08, 0.08, 0.09), titleAlpha = -1,   -- -1: the background's opacity + 0.15
            titleLine = true,           -- accent line under the title bar
            titleAccent = true,         -- the fight in the accent colour (off: white)
            titleIcons = false,         -- the type's name at the left, meter type and fight as icon buttons at the right
            titleIconSize = 18,         -- those icons (may stand out of a lower title bar)
            titleIconsMuted = true,     -- those icons grey and dimmed, accent colour under the mouse
            nameHover = false,          -- hovering a name: its top spells beside the window (a click still opens the breakdown)
            breakdownInline = true,     -- a clicked name's breakdown and the meter list in its window (< back); off: the breakdown beside it
            icons = "NONE",             -- NONE | CLASS: class icon before each bar
            rowBorder = 0,              -- a border around each bar (0: none)
            barBgColor = C(0, 0, 0), barBgAlpha = 0.35,          -- the empty part of each bar
        },
        -- bags: HUF's one bag window, bank / other characters from snapshots,
        -- search, counts in tooltips (snapshots: HUFDB.inventory, not here)
        -- the game's own windows: drag to move, places remembered (Windows.lua)
        windows = { enabled = true, shift = false, positions = {} },
        bags = {
            enabled = true,
            oneBag = true,              -- the game's "combined bags" option
            point = { "BOTTOMRIGHT", "BOTTOMRIGHT", -60, 110 },
            cols = 10, size = 34, spacing = 4, scale = 1,
            bgColor = C(0.04, 0.04, 0.05), bgAlpha = 0.92,
            borderAccent = true, borderColor = C(0.2, 0.2, 0.22), borderSize = 1,
            qualityBorders = true, showEmpty = true,
            font = "GLOBAL", countSize = 12,
            tooltipCounts = true, openWithBank = true,
            sortButton = true,
            -- the reagent bag: own slot colour, optionally beside the window
            reagentTint = true, reagentColor = C(0.06, 0.20, 0.12),
            reagentSeparate = true, reagentSide = "LEFT", reagentCols = 4,
        },
        -- chat window: look, short channel names, links, history, buttons
        chat = {
            enabled = true,
            font = "GLOBAL", fontSize = 14, outline = "GLOBAL",
            bgColor = C(0.03, 0.03, 0.04), bgAlpha = 0.5,
            abbreviate = true,
            abbr = { CHANNEL = "%d", SAY = "S", YELL = "Y", PARTY = "P", PARTY_LEADER = "PL", GUILD = "G",
                     OFFICER = "GO", RAID = "R", RAID_LEADER = "RL", RAID_WARNING = "RW", WHISPER = "W",
                     INSTANCE_CHAT = "I", INSTANCE_CHAT_LEADER = "IL" },
            classColors = true, urls = true, linkTooltips = true,
            history = true, historyLines = 2000,
            buttons = { copy = true, guild = true, social = false, channels = true, chatmenu = true },
            buttonSide = "RIGHT", buttonX = 8, buttonY = 0,
            fade = true, fadeAlpha = 0.4, fadeDelay = 5, hideStock = true,     -- the buttons fade while the mouse is elsewhere
            inputPos = "BELOW", inputOffset = 0,              -- the input line: BELOW | ABOVE the chat
        },
        -- buff and debuff bars (HUF's instead of Blizzard's at the top right)
        auraBars = {
            buffs = { enabled = true, point = { "TOPRIGHT", "TOPRIGHT", -225, -20 }, scale = 1,
                      grow = "LEFT_DOWN", max = 32, columns = 12, rows = 3, padding = 4, size = 32, zoom = 0.08,
                      borderSize = 1, borderAccent = false, borderColor = C(0.06, 0.06, 0.07),
                      swipe = true, timer = true, timerFormat = "HHMM", timerPos = "BELOW", timerSize = 12,
                      countSize = 12, font = "GLOBAL", outline = "GLOBAL", sort = "TIME", sortDir = "-" },
            debuffs = { enabled = true, point = { "TOPRIGHT", "TOPRIGHT", -225, -175 }, scale = 1,
                        grow = "LEFT_DOWN", max = 16, columns = 8, rows = 2, padding = 4, size = 36, zoom = 0.08,
                        borderSize = 1, borderAccent = false, borderColor = C(0.06, 0.06, 0.07), typeColors = true,
                        swipe = true, timer = true, timerFormat = "HHMM", timerPos = "BELOW", timerSize = 12,
                        countSize = 12, font = "GLOBAL", outline = "GLOBAL", sort = "TIME", sortDir = "-" },
        },
        -- minimap: shape, size, look, texts and icons placed on it (each
        -- shown always, on mouseover or never), addon buttons on the map or
        -- in the addon bar
        minimap = {
            enabled = true,
            shape = "SQUARE",           -- SQUARE | ROUND
            size = 180, scale = 1,
            point = { "TOPRIGHT", "TOPRIGHT", -20, -20 },
            borderSize = 2, borderAccent = true, borderColor = C(0.06, 0.06, 0.07),
            shade = 14, shadeAlpha = 0.6,   -- dark shade outside the map: width, strength
            mouseZoom = true,
            font = "GLOBAL", outline = "GLOBAL",
            textAlpha = 1,              -- the texts on and around the map
            -- behaviour
            visibility = "ALWAYS",      -- ALWAYS | COMBAT (only in combat) | NOCOMBAT (hidden in combat) | HOVER
            opacity = 1,
            onlyInstances = false,      -- shown only in dungeons / raids / battlegrounds
            hideMounted = false,
            rotate = "GAME",            -- GAME (the game's setting) | ON | OFF
            zoomReset = 0,              -- seconds after a zoom until it zooms out again (0: never)
            iconScale = 1,              -- the game's icons (tracking, calendar ...)
            -- pos: inside the map (TOPLEFT ... BOTTOMRIGHT) or outside (ABOVE_*, BELOW_*)
            texts = {
                zone   = { mode = "ALWAYS", pos = "ABOVE", x = 0, y = -4, size = 13, color = "ZONE", sub = true },   -- sub: the subzone when there is one
                clock  = { mode = "ALWAYS", pos = "BELOW", x = 0, y = 4, size = 13, color = "WHITE", format = "24", localTime = true },
                coords = { mode = "ALWAYS", pos = "BOTTOMLEFT", x = 0, y = 2, size = 12, color = "WHITE", decimals = 1 },
                system = { mode = "ALWAYS", pos = "BOTTOMRIGHT", x = 0, y = 2, size = 12, color = "WHITE", show = "BOTH", latency = "HIGHER" },
                difficulty = { mode = "NEVER", pos = "TOPRIGHT", x = -4, y = -4, size = 12, color = "WHITE" },   -- "5N", "10H" in instances
            },
            icons = {
                tracking    = { mode = "HOVER", pos = "TOPLEFT", x = 0, y = -2 },
                calendar    = { mode = "HOVER", pos = "TOPRIGHT", x = -2, y = -2 },
                mail        = { mode = "ALWAYS", pos = "RIGHT", x = -2, y = 0 },
                crafting    = { mode = "HOVER", pos = "LEFT", x = 0, y = 0 },
                difficulty  = { mode = "ALWAYS", pos = "TOPLEFT", x = 2, y = -2 },
                landing     = { mode = "NEVER", pos = "LEFT", x = 2, y = -30 },
                zoom        = { mode = "NEVER", pos = "BOTTOMRIGHT", x = -2, y = 24 },
                addonbar    = { mode = "ALWAYS", pos = "OUTSIDE_LEFT_BOTTOM", x = -2, y = 0 },   -- the button bag, outside the lower left
            },
            buttonMode = "HOVER",       -- addon buttons on the map: ALWAYS | HOVER | NEVER (each one can differ: buttons[name])
            buttons = {},
            addonBar = true,            -- every addon button in one "addon bar" button
            barGrow = "AUTO",           -- AUTO (towards the screen's middle) | LEFT | RIGHT | UP | DOWN
            barIconSize = 26, barTimeout = 10,
            barLayout = "ROW",          -- ROW (one line) | GRID (barColumns wide) | LIST (one column with names)
            barColumns = 4,
            barSquare = false,          -- buttons in the bar as square icons on a dark background
            -- buttons[name] = "PIN": kept out of the bag, in a line from the bag button
            pinGrow = "UP",             -- UP | RIGHT | DOWN | LEFT
            pinGap = 2,
            pinOrder = {},              -- name -> place in the line (else by name)
        },
        -- data bars: for now the minimap data bar (DataBars.lua)
        dataBars = {
            minimap = {
                enabled = false,
                position = "BELOW",         -- BELOW | ABOVE the map
                height = 22, gap = 0,
                bgColor = C(0.067, 0.067, 0.067), bgAlpha = 0.95, borderSize = 1,
                friends = true, guild = true,
                fontSize = 12, spacing = 16,
                layout = "SIDE",            -- SIDE: icon, then the count | STACK: the count above a small icon
                iconColor = "MONO",         -- MONO (flat light grey) | GAME (the art's colours) | CLASS | ACCENT | CUSTOM
                iconCustom = C(0.85, 0.85, 0.88),
            },
            -- free bars anywhere on screen, each with its blocks (DataBars.lua)
            bars = {},
        },
        nameplates = {
            enabled = true,
            mode = "NAME_BAR",          -- NAME | NAME_BAR | BAR
            friendlyMode = "NAME",      -- SAME (as enemies) | NAME | NAME_BAR | BAR
            width = 125, height = 10,
            texture = "Fade",
            colorMode = "CLASS",        -- CLASS (players) / reaction (NPCs) | STATIC | STATUS
            color = C(0.20, 0.65, 0.30),
            high = C(0.20, 0.75, 0.30), mid = C(1.00, 0.70, 0.10), low = C(0.85, 0.15, 0.15),
            tappedGray = true,
            reactionColors = "GAME",    -- NPCs in class mode: GAME (HUF's reaction colours) | CUSTOM (below)
            hostileColor = C(0.85, 0.20, 0.20), neutralColor = C(0.93, 0.80, 0.20), friendlyColor = C(0.25, 0.78, 0.35),
            dimOutOfCombat = false,     -- hostile NPCs not in combat at 60% brightness
            bgTexture = "Plain", bgColor = C(0.05, 0.05, 0.06), bgAlpha = 0.85,
            borderSize = 1, borderColor = ns.CopyTable(BORDER),
            targetBorder = true,        -- your target's plate: accent border
            yOffset = 0,
            -- name
            font = "GLOBAL", fontSize = 12, outline = "OUTLINE",
            nameColor = "REACTION",     -- REACTION (class / reaction) | WHITE | CUSTOM
            nameCustom = C(1, 1, 1),
            nameGap = 1,                -- space between name and bar
            namePosition = "ABOVE",     -- ABOVE the bar | LEFT / CENTER: in the bar (name only: centred as ever)
            levelSep = " ",             -- between level and name ("55E Name" / "55E | Name")
            -- stacking (the game's nameplateStackingTypes; GAME: HUF leaves it alone)
            stackEnemies = "GAME",      -- GAME | ON (plates push each other apart) | OFF (overlap)
            stackFriendly = "GAME",
            stackSpacing = 100,         -- % of the plate's height the game keeps between stacked plates
            -- friendly units' names (default: as enemies')
            friendlyFontSize = 0,       -- 0: the size above
            friendlyLevel = "SAME",     -- SAME | SHOW | HIDE
            friendlyNameColor = "SAME", -- SAME | REACTION (class for players) | WHITE
            showLevel = true,           -- "55E" before the name, in difficulty colour
            levelAlways = false,        -- also when the game hides the level (earlier value, else uncoloured)
            showHealth = false,         -- health % at the right end of the bar
            healthTag = "[hp%]",        -- [hp%] | [hp%:nosign] | [hp]
            healthSize = 0,             -- 0: the name's size - 2
            showElite = true,           -- star right of the bar: elite gold, rare silver, rare elite silver + gold ring, boss red
            eliteSize = 10,
            showQuest = true,           -- quest progress ("2/10") left of the bar
            instanceFriends = "HIDE",   -- in instances friendly player plates are the game's (protected, real names):
                                        -- HIDE them (and the names above characters) while names are private | SHOW
            questieIcon = "LEFT",       -- Questie's quest icon: LEFT (of the progress / bar) | RIGHT (of the bar) | QUESTIE (its own spot)
            questColor = C(1.00, 0.82, 0.00),
            -- cast bar
            showCast = true,
            castHeight = 7, castGap = 1,
            castColor = C(1.00, 0.70, 0.20),
            castText = true, castFontSize = 10,
            castIcon = true,
            castInterrupt = true,       -- "Interrupted!" for a moment when someone interrupts the cast
            castInterruptColor = C(0.85, 0.15, 0.15), castInterruptTime = 1,
            -- threat: OFF | PERCENT (your threat %) | GLOW (about to pull) | BOTH
            threatMode = "GLOW", threatSize = 10, threatPos = "RIGHT", threatColors = true,
            threatGlowSize = 5, threatGlowColor = C(1.00, 0.60, 0.00),
            threatGlowAggro = false, threatAggroColor = C(1.00, 0.15, 0.15),
            -- threat colours on the bar: OFF | ALWAYS | INSTANCES (dungeons, raids, scenarios)
            threatBar = "OFF",
            threatDpsSafeOn = true, threatDpsSafe = C(0.35, 0.75, 0.35),
            threatDpsNear = C(0.95, 0.75, 0.20), threatDpsAggro = C(1.00, 0.30, 0.15),
            threatTankHoldOn = true, threatTankHold = C(0.10, 0.70, 0.55),
            threatTankLosing = C(0.95, 0.75, 0.20), threatTankLost = C(1.00, 0.20, 0.15),
            threatOffTankOn = true, threatOffTank = C(0.20, 0.60, 0.85),
            -- combo points (rogue, cat druid) under your target's plate
            comboShow = true, comboHeight = 4, comboGap = 2, comboSpace = 2,
            comboColor = C(1.00, 0.82, 0.10), comboHideEmpty = true,
            -- auras (small icons above the name)
            showBuffs = false, showDebuffs = true,
            debuffsMine = true,         -- only the debuffs you cast
            buffFilter = "ALL",         -- ALL | PURGE (dispellable / stealable) | IMPORTANT_PURGE (important or dispellable)
            buffTypeEdge = false,       -- buffs: edge in their type's colour (magic blue)
            auraSize = 15, auraMax = 5, auraRows = 1, auraGap = 1,
            auraTimer = true, auraTimerSize = 0,    -- time left on the icons; size 0: from the icon size
        },
    }
end
ns.BuildDefaults = BuildDefaults
ns.DEFAULTS = BuildDefaults()

---------------------------------------------------------------------------
-- Profiles
---------------------------------------------------------------------------
-- "First Last-Realm": characters on WoW: Forever share first names
local charKey
local function CharKey()
    if charKey then return charKey end
    local name, last = UnitName("player")
    if type(name) ~= "string" then return "?-" .. (GetRealmName and GetRealmName() or "") end
    if type(last) == "string" and last ~= "" then name = name .. " " .. last end
    local realm = GetRealmName and GetRealmName() or ""
    charKey = name .. "-" .. realm
    return charKey
end

ns.CharKey = CharKey

function ns.CurrentProfileName()
    return (HUFDB and HUFDB.chars[CharKey()]) or "Default"
end

function ns.ProfileNames()
    local list = {}
    for name in pairs(HUFDB.profiles) do list[#list + 1] = name end
    table.sort(list)
    return list
end

local function Activate(name)
    HUFDB.profiles[name] = HUFDB.profiles[name] or {}
    ns.db = FillDefaults(HUFDB.profiles[name], ns.DEFAULTS)
    HUFDB.chars[CharKey()] = name
    ns.ApplyAccent()
end

function ns.SetProfile(name)
    if not name or name == "" then return end
    Activate(name)
    ns.Fire("PROFILE_CHANGED")
    ns.Refresh(true)
end

function ns.CopyProfile(from)
    local src = HUFDB.profiles[from]
    if not src then return end
    local name = ns.CurrentProfileName()
    HUFDB.profiles[name] = ns.CopyTable(src)
    Activate(name)
    ns.Fire("PROFILE_CHANGED")
    ns.Refresh(true)
end

function ns.DeleteProfile(name)
    if not HUFDB.profiles[name] or name == ns.CurrentProfileName() then return false end
    HUFDB.profiles[name] = nil
    for char, p in pairs(HUFDB.chars) do
        if p == name then HUFDB.chars[char] = "Default" end
    end
    return true
end

function ns.ResetProfile()
    local name = ns.CurrentProfileName()
    HUFDB.profiles[name] = {}
    Activate(name)
    ns.Fire("PROFILE_CHANGED")
    ns.Refresh(true)
end

-- copies one frame's look to another (not its position, on/off state or texts)
local KEEP_ON_COPY = { enabled = true, point = true, anchorTo = true, texts = true, group = true }
function ns.CopyUnitSettings(fromKey, toKey)
    local src, dst = ns.db.units[fromKey], ns.db.units[toKey]
    if not src or not dst or fromKey == toKey then return end
    for k, v in pairs(src) do
        if not KEEP_ON_COPY[k] and (ns.DEFAULTS.units[toKey][k] ~= nil) then dst[k] = ns.CopyTable(v) end
    end
    ns.Refresh(true)
end

function ns.ResetUnit(key)
    local keepPoint, keepAnchor = ns.db.units[key].point, ns.db.units[key].anchorTo
    ns.db.units[key] = ns.CopyTable(ns.DEFAULTS.units[key])
    ns.db.units[key].point = keepPoint
    ns.db.units[key].anchorTo = keepAnchor
    ns.Refresh(true)
end

---------------------------------------------------------------------------
-- Events and callbacks
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local handlers = {}
function ns.On(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        -- unknown on this client: nothing to listen to (no error)
        if not pcall(eventFrame.RegisterEvent, eventFrame, event) then ns.Log("events", "no event %s on this client", event) end
    end
    table.insert(handlers[event], fn)
end
eventFrame:SetScript("OnEvent", function(_, event, ...)
    for _, fn in ipairs(handlers[event] or {}) do
        local ok, err = pcall(fn, ...)
        if not ok then ns.LogError("event " .. event, err) end
    end
end)

local callbacks = {}
function ns.Listen(name, fn)
    callbacks[name] = callbacks[name] or {}
    table.insert(callbacks[name], fn)
end
function ns.Fire(name, ...)
    for _, fn in ipairs(callbacks[name] or {}) do
        local ok, err = pcall(fn, ...)
        if not ok then ns.LogError("callback " .. name, err) end
    end
end

local loginFns = {}
function ns.OnLogin(fn) loginFns[#loginFns + 1] = fn end

-- debug log: Debug.lua (stubs until it is loaded)
function ns.Debug() end
function ns.Log() end
function ns.LogError(where, err) ns.Print("error in %s: %s", where, tostring(err)) end

---------------------------------------------------------------------------
-- Out-of-combat queue: secure frames can only change outside combat
---------------------------------------------------------------------------
local oocQueue, oocOrder = {}, {}
function ns.RunOOC(key, fn)
    if not InCombatLockdown() then
        local ok, err = pcall(fn)
        if not ok then ns.LogError(key, err) end
        return true
    end
    if not oocQueue[key] then oocOrder[#oocOrder + 1] = key end
    oocQueue[key] = fn
    ns.Log("combat", "queued until combat ends: %s", key)
    return false
end
ns.On("PLAYER_REGEN_ENABLED", function()
    local order = oocOrder
    oocOrder = {}
    for _, key in ipairs(order) do
        local fn = oocQueue[key]
        oocQueue[key] = nil
        if fn then
            ns.Log("combat", "after combat: %s", key)
            local ok, err = pcall(fn)
            if not ok then ns.LogError(key, err) end
        end
    end
end)

---------------------------------------------------------------------------
-- Refresh: settings changed -> frames apply them (batched to one per frame
-- draw, so dragging a slider doesn't rebuild every step twice)
---------------------------------------------------------------------------
local refreshers = {}
function ns.OnRefresh(fn) refreshers[#refreshers + 1] = fn end
local pending, pendingFull = false, false
function ns.Refresh(full)
    pendingFull = pendingFull or full
    if pending then return end
    pending = true
    C_Timer.After(0, function()
        pending = false
        local f = pendingFull
        pendingFull = false
        for _, fn in ipairs(refreshers) do
            local ok, err = pcall(fn, f)
            if not ok then ns.LogError("refresh", err) end
        end
    end)
end

---------------------------------------------------------------------------
-- Startup
---------------------------------------------------------------------------
ns.On("ADDON_LOADED", function(name)
    if name ~= ADDON then return end
    HUFDB = HUFDB or {}
    -- HUF 0.2 started over: settings of the earlier HUF don't fit any more
    if (HUFDB.dataVersion or 1) < 2 then
        HUFDB.profiles, HUFDB.chars = {}, {}
        HUFDB.dataVersion = 2
    end
    -- 0.3.1: new nameplate defaults (only where still the old default)
    if HUFDB.dataVersion < 3 then
        for _, prof in pairs(HUFDB.profiles or {}) do
            local n = prof.nameplates
            if n then
                if n.width == 110 then n.width = 125 end
                if n.height == 4 then n.height = 8 end
                if n.friendlyMode == "SAME" then n.friendlyMode = "NAME" end
                if n.fontSize == 9 then n.fontSize = 10 end
            end
        end
        HUFDB.dataVersion = 3
    end
    -- 0.3.4: nameplate aura icons 12 -> 15 (only where still the old default)
    if HUFDB.dataVersion < 4 then
        for _, prof in pairs(HUFDB.profiles or {}) do
            local n = prof.nameplates
            if n and n.auraSize == 12 then n.auraSize = 15 end
        end
        HUFDB.dataVersion = 4
    end
    -- 0.3.7: player / target bars +1 px each, target of target health only and
    -- anchored to the target frame (only where still the old defaults)
    if HUFDB.dataVersion < 5 then
        for _, prof in pairs(HUFDB.profiles or {}) do
            local u = prof.units
            if u then
                for _, k in ipairs({ "player", "target" }) do
                    local s = u[k]
                    if s and s.height == 22 and (not s.power or s.power.size == 8) then
                        s.height = 24
                        if s.power then s.power.size = 9 end
                    end
                end
                local t = u.targettarget
                if t and t.point and t.point[1] == "CENTER" and t.point[3] == 455 and t.point[4] == -200 then
                    t.point = { "TOPLEFT", "BOTTOMRIGHT", -20, -5 }
                    t.anchorTo = "target"
                end
                if t and t.power then t.power.enabled = false end
            end
        end
        HUFDB.dataVersion = 5
    end
    -- 0.3.8: target of target 16 high, 10 below the target; group frames
    -- vertical 150 x 30 with size 12 power texts (only where still the 0.3.7 defaults)
    if HUFDB.dataVersion < 6 then
        for _, prof in pairs(HUFDB.profiles or {}) do
            local u = prof.units
            local t = u and u.targettarget
            if t then
                if t.height == 22 then t.height = 16 end
                if t.anchorTo == "target" and t.point and t.point[4] == -5 then t.point[4] = -10 end
            end
            local g = u and u.party
            if g then
                if g.width == 200 and g.height == 25 then g.width, g.height = 150, 30 end
                if g.group and g.group.orientation == "HORIZONTAL" then g.group.orientation = "VERTICAL" end
                local pt = g.texts and g.texts.power
                if pt then
                    for _, a in ipairs({ "LEFT", "CENTER", "RIGHT" }) do
                        if pt[a] and pt[a].size == 16 then pt[a].size = 12 end
                    end
                end
            end
        end
        HUFDB.dataVersion = 6
    end
    -- 0.3.9: orientation became a growth direction
    if HUFDB.dataVersion < 7 then
        for _, prof in pairs(HUFDB.profiles or {}) do
            local g = prof.units and prof.units.party and prof.units.party.group
            if g then
                if g.orientation == "VERTICAL" then g.orientation = "DOWN"
                elseif g.orientation == "HORIZONTAL" then g.orientation = "RIGHT" end
            end
        end
        HUFDB.dataVersion = 7
    end
    -- 0.3.13: pet frame at the player frame's bottom left (only where still the 0.3.12 default)
    if HUFDB.dataVersion < 8 then
        for _, prof in pairs(HUFDB.profiles or {}) do
            local p = prof.units and prof.units.pet
            if p and p.anchorTo == "player" and p.point and p.point[1] == "TOPLEFT" and p.point[2] == "BOTTOMRIGHT"
                and p.point[3] == -20 and p.point[4] == -10 then
                p.point[2] = "BOTTOMLEFT"
            end
        end
        HUFDB.dataVersion = 8
    end
    -- 0.3.14: pet and target of target 25 below their frames (clear of the debuff icons)
    if HUFDB.dataVersion < 9 then
        for _, prof in pairs(HUFDB.profiles or {}) do
            local u = prof.units
            for _, k in ipairs({ "pet", "targettarget" }) do
                local f = u and u[k]
                if f and f.anchorTo and f.anchorTo ~= "SCREEN" and f.point and f.point[3] == -20 and f.point[4] == -10 then
                    f.point[4] = -25
                end
            end
        end
        HUFDB.dataVersion = 9
    end
    -- 0.3.16: Expressway no longer comes with HUF (licence): Barlow Condensed instead
    if HUFDB.dataVersion < 10 then
        local function Walk(t, depth)
            if depth > 8 then return end
            for k, v in pairs(t) do
                if k == "font" and v == "Expressway" then t[k] = "Barlow Condensed"
                elseif type(v) == "table" then Walk(v, depth + 1) end
            end
        end
        for _, prof in pairs(HUFDB.profiles or {}) do Walk(prof, 0) end
        HUFDB.dataVersion = 10
    end
    -- 0.3.21: new defaults from play (only where still the old defaults)
    if HUFDB.dataVersion < 11 then
        local function Same(p, a) return type(p) == "table" and p[1] == a[1] and p[2] == a[2] and p[3] == a[3] and p[4] == a[4] end
        for _, prof in pairs(HUFDB.profiles or {}) do
            local n = prof.nameplates
            if n then
                if n.height == 8 then n.height = 10 end
                if n.fontSize == 10 then n.fontSize = 12 end
                if n.castHeight == 3 then n.castHeight = 7 end
                if n.castFontSize == 7 then n.castFontSize = 10 end
            end
            local u = prof.units or {}
            local g = u.party
            if g then
                if g.width == 150 and g.height == 30 then g.width, g.height = 125, 28 end
                local b = g.buffs
                if b and b.position == "ABOVE_LEFT" and b.offset == 1 then b.position, b.offset = "BELOW_LEFT", 8 end
            end
            local p = u.pet
            if p then
                if Same(p.point, { "TOPLEFT", "BOTTOMLEFT", -20, -25 }) then
                    p.point = { "BOTTOMLEFT", "BOTTOMLEFT", -140, -45 }
                end
                if p.width == 175 and p.height == 24 then p.height = 20 end
                if p.health and p.health.colorMode == "GRADIENT" then p.health.colorMode = "STATUS" end
                if p.power and p.power.size == 9 then p.power.size = 3 end
                local t = p.texts
                if t and t.health and t.health.BOTTOMLEFT and t.health.BOTTOMLEFT.size == 24 then t.health.BOTTOMLEFT.size = 17 end
                if t and t.power and t.power.RIGHT and t.power.RIGHT.text == "[mp]" then t.power.RIGHT.text = "" end
                if p.healPred == nil then p.healPred = { enabled = false } end
            end
        end
        HUFDB.dataVersion = 11
    end
    -- 0.3.22: incoming heals at most 10% past the bar's end (where still 50)
    if HUFDB.dataVersion < 12 then
        for _, prof in pairs(HUFDB.profiles or {}) do
            for _, s in pairs(prof.units or {}) do
                if type(s) == "table" and type(s.healPred) == "table" and s.healPred.overheal == 50 then
                    s.healPred.overheal = 10
                end
            end
        end
        HUFDB.dataVersion = 12
    end
    -- 0.3.26: bar texture "Fade" everywhere, damage meter 200 wide, 6 rows of
    -- 17, font 12 (only where still the old defaults)
    if HUFDB.dataVersion < 13 then
        local function Walk(t, depth)
            if depth > 6 then return end
            for k, v in pairs(t) do
                if k == "texture" and v == "Smooth" then t[k] = "Fade"
                elseif type(v) == "table" then Walk(v, depth + 1) end
            end
        end
        for _, prof in pairs(HUFDB.profiles or {}) do
            Walk(prof, 0)
            local d = prof.damageMeter
            if d then
                if d.width == 240 then d.width = 200 end
                if d.rows == 8 then d.rows = 6 end
                if d.rowHeight == 18 then d.rowHeight = 17 end
                if d.fontSize == 11 then d.fontSize = 12 end
            end
        end
        HUFDB.dataVersion = 13
    end
    -- 14: settings window without the honeycomb pattern
    if HUFDB.dataVersion < 14 then
        for _, prof in pairs(HUFDB.profiles or {}) do
            if prof.global and prof.global.configBg == "Honeycomb" then prof.global.configBg = "None" end
        end
        HUFDB.dataVersion = 14
    end
    -- 15: chat buttons 8 px further out, no "to the end" button
    if HUFDB.dataVersion < 15 then
        for _, prof in pairs(HUFDB.profiles or {}) do
            local c = prof.chat
            if c then
                if c.buttonX == nil or c.buttonX == 0 then c.buttonX = 8 end
                if c.buttons then c.buttons.bottom = nil end
            end
        end
        HUFDB.dataVersion = 15
    end
    -- 16: minimap tracking under the map's left edge, the addon button bag in
    -- its lower left (only where still the old defaults)
    if HUFDB.dataVersion < 16 then
        for _, prof in pairs(HUFDB.profiles or {}) do
            local ic = prof.minimap and prof.minimap.icons
            local t = ic and ic.tracking
            if t and t.mode == "HOVER" and t.pos == "LEFT" and t.x == 2 and t.y == 0 then
                t.mode, t.pos, t.x, t.y = "ALWAYS", "BELOW_LEFT", 0, -2
            end
            local ab = ic and ic.addonbar
            if ab and ab.pos == "RIGHT" and ab.x == -4 and ab.y == 28 then
                ab.pos, ab.x, ab.y = "BOTTOMLEFT", 2, 2
            end
        end
        HUFDB.dataVersion = 16
    end
    -- 17: the addon button bag just outside the map's lower left corner
    -- (only where still the 16 place)
    if HUFDB.dataVersion < 17 then
        for _, prof in pairs(HUFDB.profiles or {}) do
            local ab = prof.minimap and prof.minimap.icons and prof.minimap.icons.addonbar
            if ab and ab.pos == "BOTTOMLEFT" and ab.x == 2 and ab.y == 2 then
                ab.pos, ab.x, ab.y = "OUTSIDE_LEFT_BOTTOM", -2, 0
            end
        end
        HUFDB.dataVersion = 17
    end
    -- 0.5.4: the reagent bag beside the bags by default
    if HUFDB.dataVersion < 18 then
        for _, prof in pairs(HUFDB.profiles or {}) do
            if type(prof.bags) == "table" and prof.bags.reagentSeparate == false then prof.bags.reagentSeparate = true end
        end
        HUFDB.dataVersion = 18
    end
    -- 0.5.5: bigger pet happiness icon
    if HUFDB.dataVersion < 19 then
        for _, prof in pairs(HUFDB.profiles or {}) do
            local h = prof.units and prof.units.pet and prof.units.pet.happiness
            if type(h) == "table" and h.size == 14 then h.size = 20 end
        end
        HUFDB.dataVersion = 19
    end
    -- 0.5.7: bag window edge fixed (no setting); new minimap defaults, applied where a
    -- profile still has the old default (anything changed by hand stays)
    if HUFDB.dataVersion < 20 then
        local function Move(t, old, new)
            if type(t) ~= "table" then return end
            for k, v in pairs(old) do if t[k] ~= v then return end end
            for k, v in pairs(new) do t[k] = v end
        end
        for _, prof in pairs(HUFDB.profiles or {}) do
            if type(prof.bags) == "table" then prof.bags.padding = nil end
            local m = prof.minimap
            if type(m) == "table" then
                if m.addonBar == false then m.addonBar = true end
                local i, t = m.icons or {}, m.texts or {}
                Move(i.tracking, { mode = "ALWAYS", pos = "BELOW_LEFT", x = 0, y = -2 }, { mode = "HOVER", pos = "TOPLEFT", x = 0, y = -2 })
                Move(i.crafting, { mode = "ALWAYS", pos = "RIGHT", x = -2, y = -26 }, { mode = "HOVER", pos = "LEFT", x = 0, y = 0 })
                Move(i.landing, { mode = "HOVER" }, { mode = "NEVER" })
                Move(t.zone, { pos = "TOP", x = 0, y = -4 }, { mode = "ALWAYS", pos = "ABOVE" })
                Move(t.clock, { pos = "BOTTOM", x = 0, y = 4 }, { mode = "ALWAYS", pos = "BELOW", size = 13 })
                Move(t.coords, { mode = "HOVER", pos = "BOTTOMLEFT", x = 4, y = 4, size = 11 }, { mode = "ALWAYS", x = 0, y = 2, size = 12 })
                Move(t.system, { mode = "HOVER", pos = "BOTTOMRIGHT", x = -4, y = 4, size = 11 }, { mode = "ALWAYS", x = 0, y = 2, size = 12 })
            end
        end
        HUFDB.dataVersion = 20
    end
    -- 0.5.8: buff / debuff bar growth names both directions (icons, then new lines)
    if HUFDB.dataVersion < 21 then
        local NEW = { LEFT = "LEFT_DOWN", RIGHT = "RIGHT_DOWN", DOWN = "DOWN_RIGHT", UP = "UP_RIGHT" }
        for _, prof in pairs(HUFDB.profiles or {}) do
            local ab = prof.auraBars
            if type(ab) == "table" then
                for _, k in ipairs({ "buffs", "debuffs" }) do
                    if type(ab[k]) == "table" and NEW[ab[k].grow] then ab[k].grow = NEW[ab[k].grow] end
                end
            end
        end
        HUFDB.dataVersion = 21
    end
    HUFDB.profiles = HUFDB.profiles or {}
    HUFDB.chars = HUFDB.chars or {}
    Activate(ns.CurrentProfileName())
end)

ns.On("PLAYER_LOGIN", function()
    for _, fn in ipairs(loginFns) do
        local ok, err = pcall(fn)
        if not ok then ns.LogError("login", err) end
    end
    ns.ready = true
    ns.Log("init", "login done: %d frames", #(ns.allFrames or {}))
end)
