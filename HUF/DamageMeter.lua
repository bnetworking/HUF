-- HUF: damage meter. Shows the game's own meter data (C_DamageMeter) in a
-- HUF window, with names that follow HUF's privacy setting and MMT's, and
-- hides Blizzard's meter window (CVar damageMeterEnabled, put back when off).
--
-- Names: out of combat the meter's names and GUIDs are readable. In combat in
-- instances the game hands them to addons as secret values: they can't be
-- looked at, only shown as they are (the real name). While names are private
-- HUF never shows a secret real name; it finds the player another way:
--   1. "this is you" (isLocalPlayer)
--   2. a readable GUID or name -> the group unit -> the privacy name
--   3. a class only one group member has -> that member
--   4. class + specialisation icon, learned from readable rows after a fight
--   5. otherwise the class name ("Hunter"): right again when the fight ends.

local _, ns = ...
local UI = ns.UI
local IsSecret = ns.IsSecret

local DM = {}
ns.DamageMeter = DM

-- Settings: the meter-wide ones in ns.db.damageMeter; the look and size can
-- differ per window (windows[i][key] set = its own value, else the shared
-- one). S() reads through the window at hand (`win`), so the window code
-- needs no change; writes go to the shared settings.
local PER_WINDOW = {}
for _, k in ipairs({ "width", "rows", "rowHeight", "rowGap", "scale", "locked", "windowBorder", "breakdownInline",
    "nameHover", "texture", "colorMode", "color", "bgAlpha", "bgColor", "icons", "rowBorder", "barBgAlpha", "barBgColor",
    "font", "fontSize", "outline", "numbers", "showRank", "titleHeight", "titleSize", "titleColor", "titleAlpha",
    "titleLine", "titleAccent", "titleIcons", "titleIconSize", "titleIconsMuted",
    "show", "fadeOOC", "fadeAlpha", "threatPets", "threatColors" }) do PER_WINDOW[k] = true end
DM.PER_WINDOW = PER_WINDOW
local win
local view = setmetatable({}, {
    __index = function(_, k)
        local wc = PER_WINDOW[k] and win and win.cfg
        if wc then
            local v = wc[k]
            if v ~= nil then return v end
        end
        return ns.db.damageMeter[k]
    end,
    __newindex = function(_, k, v) ns.db.damageMeter[k] = v end,
})
local function S() return view end

local TYPES = {
    { key = "DamageDone", text = "Damage done", perSecond = true },
    { key = "HealingDone", text = "Healing done", perSecond = true },
    { key = "DamageTaken", text = "Damage taken", perSecond = true },
    { key = "AvoidableDamageTaken", text = "Avoidable damage", perSecond = true },
    { key = "EnemyDamageTaken", text = "Enemy damage taken", perSecond = true },
    { key = "Interrupts", text = "Interrupts", count = true },
    { key = "Dispels", text = "Dispels", count = true },
    { key = "Deaths", text = "Deaths", deaths = true },
    { key = "Threat", text = "Threat", threat = true },     -- HUF's own: the group's threat on your enemy
}
DM.TYPES = TYPES
-- title bar icons (setting "titleIcons")
local TYPE_ICONS = {
    DamageDone = "Interface\\Icons\\INV_Sword_04",
    HealingDone = "Interface\\Icons\\Spell_Holy_FlashHeal",
    DamageTaken = "Interface\\Icons\\INV_Shield_06",
    AvoidableDamageTaken = "Interface\\Icons\\Spell_Fire_Fire",
    EnemyDamageTaken = "Interface\\Icons\\Ability_DualWield",
    Interrupts = "Interface\\Icons\\Ability_Kick",
    Dispels = "Interface\\Icons\\Spell_Holy_DispelMagic",
    Deaths = "Interface\\Icons\\Ability_Rogue_FeignDeath",
    Threat = "Interface\\Icons\\Spell_Nature_Reincarnation",
}
local SESSION_ICONS = {
    CURRENT = "Interface\\Icons\\Spell_Holy_BorrowedTime",      -- this fight
    OVERALL = "Interface\\Icons\\INV_Misc_PocketWatch_01",      -- all fights
    EARLIER = "Interface\\Icons\\INV_Misc_Note_01",              -- an earlier fight
}
local TYPE_BY_KEY = {}
for i, t in ipairs(TYPES) do t.index = i TYPE_BY_KEY[t.key] = t end

local function Available()
    return C_DamageMeter and C_DamageMeter.GetCombatSessionFromType and Enum and Enum.DamageMeterType
        and Enum.DamageMeterSessionType and true or false
end
DM.Available = Available

local function Plain(v) return v ~= nil and not IsSecret(v) end

---------------------------------------------------------------------------
-- Blizzard's meter window: off while HUF's meter is on
---------------------------------------------------------------------------
local function GetCV(name)
    if C_CVar and C_CVar.GetCVar then return C_CVar.GetCVar(name) end
    if GetCVar then return GetCVar(name) end
end
local function SetCV(name, value)
    if C_CVar and C_CVar.SetCVar then return pcall(C_CVar.SetCVar, name, value) end
    if SetCVar then return pcall(SetCVar, name, value) end
end

local cvarPending
function DM.ApplyBlizzard()
    if not HUFDB or not ns.db then return end
    if InCombatLockdown() then cvarPending = true return end
    cvarPending = nil
    local cur = GetCV("damageMeterEnabled")
    if cur == nil then return end
    local want = ns.db.damageMeter.enabled and Available()   -- HUF's meter on = the game's window off
    local saved = HUFDB.damageMeterCVar
    if want then
        if cur ~= "0" then
            if not saved then HUFDB.damageMeterCVar = { old = cur } end
            SetCV("damageMeterEnabled", "0")
        end
    elseif saved then
        if cur == "0" then SetCV("damageMeterEnabled", saved.old) end
        HUFDB.damageMeterCVar = nil
    end
end

---------------------------------------------------------------------------
-- Names
---------------------------------------------------------------------------
local function GroupUnits()
    local list = {}
    if IsInRaid() then
        for i = 1, (GetNumGroupMembers() or 0) do list[#list + 1] = "raid" .. i end
    else
        list[1] = "player"
        for i = 1, (GetNumSubgroupMembers() or 0) do list[#list + 1] = "party" .. i end
    end
    return list
end

local roster = { byGUID = {}, byName = {}, byClass = {}, guidOf = {} }   -- rebuilt on roster changes
local specGUID = {}      -- "HUNTER:132215" -> guid (false: two members share it)

local function RebuildRoster()
    local oldGuid = roster.guidOf or {}
    roster = { byGUID = {}, byName = {}, byClass = {}, guidOf = {} }
    for _, u in ipairs(GroupUnits()) do
        local okG, g = pcall(UnitGUID, u)
        if okG and Plain(g) then roster.byGUID[g] = u roster.guidOf[u] = g
        elseif oldGuid[u] then roster.guidOf[u] = oldGuid[u] end
        local first, last = ns.UnitRealNames(u)
        if Plain(first) then
            roster.byName[ns.NormKey(first)] = roster.byName[ns.NormKey(first)] == nil and u or false
            if Plain(last) and last then roster.byName[ns.NormKey(first .. " " .. last)] = u end
        end
        local class = ns.Safe(function() return select(2, UnitClass(u)) end)
        if class then roster.byClass[class] = roster.byClass[class] == nil and u or false end
    end
end

local function NamesPrivate()
    if ns.db.privacy.mode ~= "FULL" then return true end
    return ns.Bridge and ns.Bridge.Active() and true or false
end

local function ClassLabel(class)
    local names = LOCALIZED_CLASS_NAMES_MALE or {}
    return names[class] or (class:sub(1, 1) .. class:sub(2):lower())
end

-- a readable name of someone not in the group: MMT's name for a team
-- member, else HUF's name part
local function NameFromString(name)
    local m = ns.Bridge and ns.Bridge.Active() and ns.Bridge.MMT()
    if m and m.Resolve and m.ShownName then
        local ok, key = pcall(m.Resolve, name)
        if ok and key then
            local ok2, shown = pcall(m.ShownName, key)
            if ok2 and type(shown) == "string" and shown ~= "" then return shown end
        end
    end
    local first, last = name:match("^(%S+)%s+(.+)$")
    first = first or name
    local mode = ns.db.privacy.mode
    if mode == "LAST" and last then return last end
    if mode == "FULL" then return name end
    return first
end

ns.NameFromString = NameFromString

-- the unit (in your group) a meter row belongs to, if HUF can tell
local function RowUnit(src)
    if src.unit then return src.unit end
    local own = src.isLocalPlayer
    if Plain(own) and own == true then return "player" end
    local g = src.sourceGUID
    if Plain(g) and roster.byGUID[g] then return roster.byGUID[g] end
    local name = src.name
    if Plain(name) and type(name) == "string" then
        local u = roster.byName[ns.NormKey(name)]
        if u then return u end
        local first = name:match("^(%S+)")
        u = first and roster.byName[ns.NormKey(first)]
        if u then return u end
    end
    local class = src.classFilename
    if Plain(class) and type(class) == "string" and class ~= "" then
        local u = roster.byClass[class]
        if u then return u end
        local icon = src.specIconID
        if Plain(icon) then
            local sg = specGUID[class .. ":" .. tostring(icon)]
            if sg and roster.byGUID[sg] then return roster.byGUID[sg] end
        end
    end
end

-- is this row a player (not an NPC or a pet)?
local function IsPlayerRow(src)
    local class = src.classFilename
    if not Plain(class) then return nil end            -- can't tell
    if type(class) ~= "string" or class == "" then return false end
    local cid = src.sourceCreatureID
    if Plain(cid) and cid and cid ~= 0 then return false end
    return true
end

-- text and how it was found ("unit", "name", "class", "secret", "npc")
function DM.RowName(src)
    if src.pet then return src.name or "?", "pet" end
    local unit = RowUnit(src)
    if unit then return ns.NameText(unit, "PRIVACY"), "unit" end
    local player = IsPlayerRow(src)
    local name = src.name
    if player == false then return name or "?", "npc" end
    if Plain(name) and type(name) == "string" then
        if player then return NameFromString(name), "name" end
        return name, "npc"
    end
    -- secret name of a player (or of someone HUF can't tell apart)
    if not NamesPrivate() and name ~= nil then return name, "secret" end
    local class = src.classFilename
    if Plain(class) and type(class) == "string" and class ~= "" then return ClassLabel(class), "class" end
    return "?", "hidden"
end

-- learns class + spec icon -> GUID from readable rows (after a fight)
local function Learn()
    if not Available() or InCombatLockdown() then return end
    local ok, s = pcall(C_DamageMeter.GetCombatSessionFromType, Enum.DamageMeterSessionType.Overall,
        Enum.DamageMeterType.DamageDone)
    if not ok or type(s) ~= "table" or type(s.combatSources) ~= "table" then return end
    for _, src in ipairs(s.combatSources) do
        local g, cls, ic = src.sourceGUID, src.classFilename, src.specIconID
        if Plain(g) and Plain(cls) and Plain(ic) and type(cls) == "string" and cls ~= "" then
            local key = cls .. ":" .. tostring(ic)
            if specGUID[key] ~= nil and specGUID[key] ~= g then specGUID[key] = false
            else specGUID[key] = g end
        end
    end
end

---------------------------------------------------------------------------
-- Numbers
---------------------------------------------------------------------------
-- whole numbers up to 9999, then 12.3K / 1.23M. The game's own
-- AbbreviateNumbers with HUF's tiers: it also takes secret values (in combat)
-- and never shows decimals below 10,000 (per second used to read 845.3333).
local abbrevConfig
local function AbbrevConfig()
    if abbrevConfig ~= nil then return abbrevConfig end
    abbrevConfig = false
    if CreateAbbreviateConfig then
        local ok, cfg = pcall(CreateAbbreviateConfig, {
            { breakpoint = 1000000000, abbreviation = "B", significandDivisor = 10000000, fractionDivisor = 100, abbreviationIsGlobal = false },
            { breakpoint = 1000000, abbreviation = "M", significandDivisor = 10000, fractionDivisor = 100, abbreviationIsGlobal = false },
            { breakpoint = 10000, abbreviation = "K", significandDivisor = 100, fractionDivisor = 10, abbreviationIsGlobal = false },
            { breakpoint = 1, abbreviation = "", significandDivisor = 1, fractionDivisor = 1, abbreviationIsGlobal = false },
        })
        if ok and cfg then abbrevConfig = cfg end
    end
    return abbrevConfig
end

local function Short(v)
    if v == nil then return "" end
    if Plain(v) and type(v) == "number" then
        v = math.floor(v + 0.5)
        if v < 10000 then return tostring(v) end
    end
    local cfg = AbbrevConfig()
    if AbbreviateNumbers then
        local ok, s
        if cfg then ok, s = pcall(AbbreviateNumbers, v, cfg) else ok, s = pcall(AbbreviateNumbers, v) end
        if ok and s ~= nil then return s end
    end
    local ok, s = pcall(string.format, "%.0f", v)
    return ok and s or ""
end
DM.Short = Short

local function ValueText(fs, src, t)
    local c = S()
    if t.threat then
        local ok = pcall(fs.SetFormattedText, fs, "%d%%", src.threatPct or 0)
        if not ok then fs:SetText("") end
        return
    end
    if t.deaths then
        local secs = src.deathTimeSeconds
        if Plain(secs) and type(secs) == "number" then
            fs:SetFormattedText("%d:%02d", math.floor(secs / 60), math.floor(secs % 60))
        else
            fs:SetText("")
        end
        return
    end
    local total, ps = src.totalAmount, src.amountPerSecond
    if t.count or not t.perSecond or c.numbers == "TOTAL" or ps == nil then
        fs:SetText(Short(total))
    elseif c.numbers == "PERSECOND" then
        fs:SetText(Short(ps))
    else
        local ok = pcall(fs.SetFormattedText, fs, c.numbers == "BAR" and "%s | %s" or "%s (%s)", Short(total), Short(ps))
        if not ok then fs:SetText(Short(total)) end
    end
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
-- several windows (e.g. damage and threat side by side): each has its own
-- list, fight and position (S().windows[i]) and may have its own size and
-- look (PER_WINDOW). The window code works on `win`, the window at hand.
local wins = {}
function DM.Windows() return wins end
local ROW_POOL = 40
local MAX_WINDOWS = 5

local function WC() return win.cfg end
-- rows of the window at hand: its own (windows[i].rows, e.g. from an
-- EllesmereUI import) or the shared setting
local function Rows()
    local r = win and win.cfg and win.cfg.rows
    if type(r) == "number" and r >= 1 then return r end
    return S().rows
end
-- its width: its own (windows[i].width, e.g. from an EllesmereUI import,
-- whose windows can differ) or the shared setting
local function Width()
    local wd = win and win.cfg and win.cfg.width
    if type(wd) == "number" and wd >= 50 then return wd end
    return S().width
end

-- per-window settings; the first window takes over the settings from
-- before there were several windows
function DM.EnsureWindows()
    local c = S()
    if type(c.windows) ~= "table" then
        c.windows = { { meterType = c.meterType or "DamageDone", session = c.session or "CURRENT",
                        point = ns.CopyTable(c.point or { "BOTTOMRIGHT", "BOTTOMRIGHT", -40, 220 }) } }
    end
    c.windowCount = math.max(1, math.min(MAX_WINDOWS, c.windowCount or 1))
    for i = 1, c.windowCount do
        local w = c.windows[i]
        if type(w) ~= "table" then
            -- a new window: left of the one before, threat if that one shows damage
            local before = c.windows[i - 1]
            local p = before.point
            w = { meterType = before.meterType == "Threat" and "DamageDone" or "Threat", session = "CURRENT",
                  point = { p[1], p[2], p[3] - c.width - 8, p[4] } }
            c.windows[i] = w
        end
        w.meterType = w.meterType or "DamageDone"
        w.session = w.session or "CURRENT"
        w.point = w.point or { "BOTTOMRIGHT", "BOTTOMRIGHT", -40, 220 }
    end
    return c.windows
end

local function SessionLabel()
    local c = WC()
    if c.session == "OVERALL" then return "Overall" end
    if type(c.session) == "number" then return DM.SessionName(c.session) or "Earlier fight" end
    return "Current"
end

function DM.Sessions()
    local list = { { id = "CURRENT", text = "Current" }, { id = "OVERALL", text = "Overall" } }
    if Available() and C_DamageMeter.GetAvailableCombatSessions then
        local ok, sess = pcall(C_DamageMeter.GetAvailableCombatSessions)
        if ok and type(sess) == "table" then
            for i = #sess, 1, -1 do
                local s = sess[i]
                if Plain(s.sessionID) then
                    local name = Plain(s.name) and s.name or ("Fight " .. i)
                    list[#list + 1] = { id = s.sessionID, text = name }
                end
            end
        end
    end
    return list
end

function DM.SessionName(id)
    for _, e in ipairs(DM.Sessions()) do if e.id == id then return e.text end end
end

---------------------------------------------------------------------------
-- Threat: every group member's (and pet's) threat on your enemy, read with
-- UnitDetailedThreatSituation (readable on Forever)
---------------------------------------------------------------------------
local function Enemy()
    for _, u in ipairs({ "target", "targettarget" }) do
        local okE, e = pcall(UnitExists, u)
        local okA, a = pcall(UnitCanAttack, "player", u)
        local okD, d = pcall(UnitIsDead, u)
        if okE and ns.Bool(e) and okA and ns.Bool(a) and not (okD and ns.Bool(d)) then return u end
    end
end

local function ThreatSession()
    local mob = Enemy()
    if not mob then return { combatSources = {}, empty = "No enemy targeted" } end
    local list, sortable = {}, true
    local units = GroupUnits()
    local pets = {}
    for _, u in ipairs(units) do
        local p = (u == "player") and "pet" or u:gsub("^party", "partypet"):gsub("^raid", "raidpet")
        pets[#pets + 1] = p
    end
    local function Add(u, isPet)
        local okE, e = pcall(UnitExists, u)
        if not (okE and ns.Bool(e)) then return end
        local ok, tanking, status, pct, raw, value = pcall(UnitDetailedThreatSituation, u, mob)
        if not ok or pct == nil then return end
        if IsSecret(pct) or IsSecret(value) then sortable = false end
        local name
        if isPet then name = ns.Safe(function() return UnitName(u) end) or "Pet" end
        list[#list + 1] = { unit = (not isPet) and u or nil, pet = isPet, name = name, threatPct = pct,
            threatValue = value, threatStatus = status, tanking = tanking,
            classFilename = (not isPet) and ns.Safe(function() return select(2, UnitClass(u)) end) or "" }
    end
    for _, u in ipairs(units) do Add(u, false) end
    if S().threatPets then for _, u in ipairs(pets) do Add(u, true) end end
    if sortable then
        table.sort(list, function(a, b) return (a.threatValue or 0) > (b.threatValue or 0) end)
    end
    local title = ns.Safe(function() return UnitName(mob) end)
    return { combatSources = list, title = title }
end

local function GetSession()
    if not Available() then return nil end
    local c = WC()
    local t = TYPE_BY_KEY[c.meterType] or TYPES[1]
    if t.threat then return ThreatSession(), t end
    local mtype = Enum.DamageMeterType[t.key]
    if mtype == nil then return nil, t end
    local ok, s
    if type(c.session) == "number" and C_DamageMeter.GetCombatSessionFromID then
        ok, s = pcall(C_DamageMeter.GetCombatSessionFromID, c.session, mtype)
    else
        local st = c.session == "OVERALL" and Enum.DamageMeterSessionType.Overall or Enum.DamageMeterSessionType.Current
        ok, s = pcall(C_DamageMeter.GetCombatSessionFromType, st, mtype)
    end
    if not ok then
        if not DM.warned then ns.Log("meter", "reading the meter failed: %s", tostring(s)) DM.warned = true end
        return nil, t
    end
    return s, t
end

---------------------------------------------------------------------------
-- Breakdown: one row's spells (like the game's own meter). The game's
-- getters refuse secret arguments, so in combat a row needs a plain GUID:
-- yours, or a group member's that HUF recognised (RowUnit).
---------------------------------------------------------------------------
local bd = { open = false }      -- guid, cid, name, unit of the shown row

local function RowIdentity(src)
    local g, cid = src.sourceGUID, src.sourceCreatureID
    if Plain(g) and (cid == nil or Plain(cid)) then return g, cid end
    local unit = RowUnit(src)
    if unit then
        local okG, ug = pcall(UnitGUID, unit)
        if okG and Plain(ug) then return ug, nil end
        if roster.guidOf[unit] then return roster.guidOf[unit], nil end
    end
end

local function FetchSource(c, mtype, guid, cid)
    local ok, s
    if type(c.session) == "number" and C_DamageMeter.GetCombatSessionSourceFromID then
        ok, s = pcall(C_DamageMeter.GetCombatSessionSourceFromID, c.session, mtype, guid, cid)
    elseif C_DamageMeter.GetCombatSessionSourceFromType then
        local st = c.session == "OVERALL" and Enum.DamageMeterSessionType.Overall or Enum.DamageMeterSessionType.Current
        ok, s = pcall(C_DamageMeter.GetCombatSessionSourceFromType, st, mtype, guid, cid)
    end
    if ok and type(s) == "table" and s.combatSpells ~= nil then return s.combatSpells end
end

-- The row's own GUID / creature ID first, also when they are secret (the
-- game accepts the values it handed out itself, as EllesmereUI does it);
-- then the plain GUID of the group member HUF recognised.
local function GetBreakdown()
    local c = (bd.win or win).cfg
    local t = TYPE_BY_KEY[c.meterType] or TYPES[1]
    if t.threat or t.deaths then return nil, t, t.threat and "No breakdown for threat" or "No breakdown for deaths" end
    if not bd.guid and bd.unit then bd.guid = roster.guidOf[bd.unit] end
    local mtype = Enum.DamageMeterType[t.key]
    local spells
    if bd.rawGuid ~= nil or bd.rawCid ~= nil then spells = FetchSource(c, mtype, bd.rawGuid, bd.rawCid) end
    if spells == nil and (bd.guid or bd.cid) then spells = FetchSource(c, mtype, bd.guid, bd.cid) end
    if spells == nil then
        bd.fails = (bd.fails or 0) + 1
        if bd.fails == 1 then
            ns.Log("meter", ("breakdown: nothing (combat=%s raw guid %s cid %s, plain guid %s)"):format(
                tostring(InCombatLockdown()), IsSecret(bd.rawGuid) and "secret" or tostring(bd.rawGuid ~= nil),
                IsSecret(bd.rawCid) and "secret" or tostring(bd.rawCid), tostring(bd.guid ~= nil)))
        end
        return nil, t, InCombatLockdown() and "Available when the fight ends" or "Nothing in this fight"
    end
    bd.fails = nil
    return spells, t
end

local function SpellInfo(id)
    local name, icon
    if id ~= nil then
        if C_Spell and C_Spell.GetSpellName then
            local ok, n = pcall(C_Spell.GetSpellName, id)
            if ok then name = n end
        elseif GetSpellInfo then
            local ok, n = pcall(GetSpellInfo, id)
            if ok then name = n end
        end
        if C_Spell and C_Spell.GetSpellTexture then
            local ok, t = pcall(C_Spell.GetSpellTexture, id)
            if ok then icon = t end
        elseif GetSpellTexture then
            local ok, t = pcall(GetSpellTexture, id)
            if ok then icon = t end
        end
    end
    return name, icon
end

-- class icon before a bar (settings "icons" = CLASS); a class the game keeps
-- secret leaves the spot empty. "icons" = SPEC: the spec's icon (the game's
-- own when it gives one, else HUF's, Specs.lua), the class icon until known.
local CLASS_ICONS = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
local gameSpecIcons = 0   -- rows the game gave a spec icon for (debug report)
local function SpecIcon(src)
    local ic = src.specIconID
    if Plain(ic) and type(ic) == "number" and ic > 0 then
        gameSpecIcons = gameSpecIcons + 1
        return ic
    end
    if not ns.Specs then return nil end
    local unit = RowUnit(src)
    if not unit then return nil end
    local class = src.classFilename
    if not (Plain(class) and type(class) == "string" and class ~= "") then
        class = ns.Safe(function() return select(2, UnitClass(unit)) end)
    end
    return ns.Specs.Icon(unit, class)
end
local function ClassIcon(r, src)
    if not r.iconOn then return end
    if S().icons == "SPEC" then
        local icon = SpecIcon(src)
        if icon then
            r.icon:SetTexture(icon)
            r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            r.icon:Show()
            return
        end
    end
    local class = src.classFilename
    local coords = Plain(class) and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
    if coords then
        r.icon:SetTexture(CLASS_ICONS)
        r.icon:SetTexCoord(coords[1] + 0.02, coords[2] - 0.02, coords[3] + 0.02, coords[4] - 0.02)
        r.icon:Show()
    else
        r.icon:Hide()
    end
end

local function BarColor(bar, src)
    local c = S()
    if src.threatStatus ~= nil and c.threatColors then
        -- the game's threat colours: grey, yellow, orange, red (tanking)
        local st = src.threatStatus
        if Plain(st) and GetThreatStatusColor then
            local ok, r, g, b = pcall(GetThreatStatusColor, st)
            if ok and r then
                if st == 0 then r, g, b = 0.55, 0.55, 0.58 end
                bar:SetStatusBarColor(r, g, b)
                return
            end
        end
    end
    if c.colorMode == "ACCENT" then
        local a = ns.ACCENT
        bar:SetStatusBarColor(a[1], a[2], a[3])
        return
    elseif c.colorMode == "STATIC" then
        bar:SetStatusBarColor(c.color.r, c.color.g, c.color.b)
        return
    end
    local class = src.classFilename
    if Plain(class) then
        local col = ns.ClassColor(class)
        if col then bar:SetStatusBarColor(col.r, col.g, col.b) return end
    elseif class ~= nil and C_ClassColor and C_ClassColor.GetClassColor then
        local ok, col = pcall(C_ClassColor.GetClassColor, class)
        if ok and col and pcall(bar.SetStatusBarColor, bar, col:GetRGB()) then return end
    end
    bar:SetStatusBarColor(0.45, 0.45, 0.48)
end

local ShowNameHover, HideHover     -- the hover box, further down
local function Row(i)
    local r = win.rows[i]
    if r then return r end
    r = CreateFrame("StatusBar", nil, win.body)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    -- class icon before the bar (settings "icons"), border around icon and bar
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetPoint("RIGHT", r, "LEFT", 0, 0)
    r.icon:Hide()
    r.edge = CreateFrame("Frame", nil, r)
    r.edge:SetPoint("BOTTOMRIGHT")
    r.border = ns.Frame.MakeBorder(r.edge)
    r.left = r:CreateFontString(nil, "OVERLAY")
    r.right = r:CreateFontString(nil, "OVERLAY")
    ns.ApplyFont(r.left, "GLOBAL", 11, "OUTLINE")
    ns.ApplyFont(r.right, "GLOBAL", 11, "OUTLINE")
    r.left:SetJustifyH("LEFT")
    r.right:SetJustifyH("RIGHT")
    r.left:SetWordWrap(false)
    r:EnableMouse(true)
    r.win = win
    r:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" and self.src then
            win = self.win
            DM.OpenBreakdown(self.src, self.name)
        elseif button == "RightButton" and S().breakdownInline then
            win = self.win
            DM.OpenTypes()
        end
    end)
    r:SetScript("OnEnter", function(self)
        if not self.src or self.isThreat then return end
        if S().nameHover then
            DM.UseWindow(self.win)
            local ok, err = pcall(ShowNameHover, self)
            if ok then return end
            ns.Log("meter", "name details: %s", tostring(err))
        end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Click: what this was made of", 1, 1, 1)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() HideHover() end)
    win.rows[i] = r
    return r
end

local function RefreshOne()
    if not win or not win:IsShown() then return end
    local c = S()
    local wc = WC()
    local session, t = GetSession()
    t = t or TYPES[1]
    win.typeText:SetText(t.text)
    win.sessionText:SetText(SessionLabel())
    if c.titleIcons then
        -- inside the title bar: at most its height - 2
        local size = math.max(8, math.min(c.titleIconSize or 18, (c.titleHeight or 20) - 2))
        win.typeB:SetIcon(TYPE_ICONS[t.key] or TYPE_ICONS.DamageDone, size)
        local sk = (wc.session == "OVERALL" and "OVERALL") or (type(wc.session) == "number" and "EARLIER") or "CURRENT"
        win.sessB:SetIcon(SESSION_ICONS[sk], size)
        win.sessB:SetShown(not t.threat)                 -- threat: no fight to pick
        win.label:SetText(t.text)
    else
        win.typeB:SetIcon(nil)
        win.sessB:SetIcon(nil)
        win.sessB:Show()
        win.label:SetText("")
    end
    local sources = session and session.combatSources or {}
    local n = #sources
    win.sessB:SetDisabled(t.threat and true or false)    -- threat: the enemy's name stands there
    if t.threat then
        win.sessionText:SetText(session and session.title or "")
        -- icon title bar: the enemy's name where the meter type's name stands
        if c.titleIcons and session and session.title and session.title ~= "" then
            pcall(win.label.SetFormattedText, win.label, "%s: %s", t.text, session.title)
        end
        win.empty:SetText(session and session.empty or "No threat yet")
    else
        win.empty:SetText("No data yet")
    end
    win.addB:SetShown(S().windowCount < MAX_WINDOWS)
    win.offset = math.max(0, math.min(win.offset or 0, n - Rows()))
    local maxAmount = sources[1] and sources[1].totalAmount
    local shown = 0
    for i = 1, Rows() do
        local r = Row(i)
        local src = sources[i + win.offset]
        if src then
            shown = shown + 1
            local rank = i + win.offset
            local name = DM.RowName(src)
            r.src, r.name, r.isThreat = src, name, t.threat
            if c.showRank then
                local ok = pcall(r.left.SetFormattedText, r.left, "%d. %s", rank, name)
                if not ok then r.left:SetText(name) end
            else
                r.left:SetText(name)
            end
            ValueText(r.right, src, t)
            if t.threat then
                r:SetMinMaxValues(0, 100)
                if not pcall(r.SetValue, r, src.threatPct or 0) then r:SetValue(0) end
            elseif t.deaths or maxAmount == nil then
                r:SetMinMaxValues(0, 1) r:SetValue(1)
            else
                if not pcall(r.SetMinMaxValues, r, 0, maxAmount) then r:SetMinMaxValues(0, 1) end
                if not pcall(r.SetValue, r, src.totalAmount or 0) then r:SetValue(0) end
            end
            BarColor(r, src)
            ClassIcon(r, src)
            r:Show()
        else
            r.src = nil
            r:Hide()
        end
    end
    for i = Rows() + 1, #win.rows do win.rows[i]:Hide() end
    win.empty:SetShown(shown == 0)
end

function DM.Refresh()
    local keep = win
    for _, w in ipairs(wins) do
        win = w
        RefreshOne()
    end
    -- every window's own breakdown / meter list
    for _, w in ipairs(wins) do
        if w.bd and w.bd.open then
            DM.UseWindow(w)
            DM.RefreshBreakdown()
        end
    end
    win = keep
end

---------------------------------------------------------------------------
-- Breakdown panel: beside the meter (right, or left when there's no room)
-- or in its place. Every window has its own (w.panel) and its own state
-- (w.bd: what is open); `panel` and `bd` are the window at hand's.
---------------------------------------------------------------------------
local panel
function DM.UseWindow(w)
    win = w
    if not w.bd then w.bd = { open = false } end
    bd = w.bd
    panel = w.panel
end
---------------------------------------------------------------------------
-- Spell details on hover (a breakdown row): a box beside the window with
-- the spell's total, per second, share and rank, and the player's damage
-- per target. The game's meter data has no hits, crits or misses (only the
-- combat log has those, and addons may not read it here).
---------------------------------------------------------------------------
local hover
local HOVER_LINES = 14

local function BuildHover()
    if hover then return end
    local h = CreateFrame("Frame", "HUF_DamageMeterSpell", UIParent)
    hover = h
    h:SetFrameStrata("TOOLTIP")
    h:SetClampedToScreen(true)
    h.fill = h:CreateTexture(nil, "BACKGROUND")
    h.fill:SetAllPoints()
    h.border = UI.Border(h, 0, 0, 0, 1)
    h.top = h:CreateTexture(nil, "BORDER")
    h.top:SetPoint("TOPLEFT")
    h.top:SetPoint("TOPRIGHT")
    h.icon = h:CreateTexture(nil, "ARTWORK")
    h.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    h.head = h:CreateFontString(nil, "OVERLAY")
    h.head:SetJustifyH("LEFT")
    h.head:SetWordWrap(false)
    h.lines = {}
    for i = 1, HOVER_LINES do
        local l = {}
        l.bar = h:CreateTexture(nil, "BORDER", nil, 1)
        l.icon = h:CreateTexture(nil, "ARTWORK")
        l.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        l.left = h:CreateFontString(nil, "OVERLAY")
        l.right = h:CreateFontString(nil, "OVERLAY")
        l.left:SetJustifyH("LEFT")
        l.left:SetWordWrap(false)
        l.right:SetJustifyH("RIGHT")
        h.lines[i] = l
    end
    h:Hide()
end

-- the session of a meter type, as the window shows it
local function SessionOf(c, mtype)
    if not (Available() and mtype ~= nil) then return nil end
    local ok, s
    if type(c.session) == "number" and C_DamageMeter.GetCombatSessionFromID then
        ok, s = pcall(C_DamageMeter.GetCombatSessionFromID, c.session, mtype)
    elseif C_DamageMeter.GetCombatSessionFromType then
        local st = c.session == "OVERALL" and Enum.DamageMeterSessionType.Overall or Enum.DamageMeterSessionType.Current
        ok, s = pcall(C_DamageMeter.GetCombatSessionFromType, st, mtype)
    end
    return ok and type(s) == "table" and s or nil
end
local function SourceOf(c, mtype, guid, cid)
    local ok, s
    if type(c.session) == "number" and C_DamageMeter.GetCombatSessionSourceFromID then
        ok, s = pcall(C_DamageMeter.GetCombatSessionSourceFromID, c.session, mtype, guid, cid)
    elseif C_DamageMeter.GetCombatSessionSourceFromType then
        local st = c.session == "OVERALL" and Enum.DamageMeterSessionType.Overall or Enum.DamageMeterSessionType.Current
        ok, s = pcall(C_DamageMeter.GetCombatSessionSourceFromType, st, mtype, guid, cid)
    end
    return ok and type(s) == "table" and s or nil
end

-- the player's damage per enemy (from the enemies' damage taken; the
-- attackers' names are readable only out of combat), largest first
local function TargetsOf(c, realName)
    if not (Plain(realName) and Enum.DamageMeterType.EnemyDamageTaken) then return nil end
    local s = SessionOf(c, Enum.DamageMeterType.EnemyDamageTaken)
    if not (s and type(s.combatSources) == "table") then return nil end
    local list = {}
    for _, enemy in ipairs(s.combatSources) do
        local sd = SourceOf(c, Enum.DamageMeterType.EnemyDamageTaken, enemy.sourceGUID, enemy.sourceCreatureID)
        local sum = 0
        for _, sp in ipairs(sd and sd.combatSpells or {}) do
            local det = sp.combatSpellDetails
            local who, amt = det and det.unitName, sp.totalAmount
            if Plain(who) and who == realName and Plain(amt) and type(amt) == "number" then sum = sum + amt end
        end
        if sum > 0 then
            list[#list + 1] = { name = Plain(enemy.name) and enemy.name or "?", total = sum }
        end
    end
    table.sort(list, function(a, b) return a.total > b.total end)
    return list
end

-- the box in the meter's look, its title bar set up (icon and title come after)
local function HoverLook(c)
    BuildHover()
    local h = hover
    local bg, tc = c.bgColor or { r = 0.04, g = 0.04, b = 0.05 }, c.titleColor or { r = 0.08, g = 0.08, b = 0.09 }
    h:SetScale(c.scale)
    h.fill:SetColorTexture(bg.r, bg.g, bg.b, math.max(0.9, c.bgAlpha))
    h.top:SetColorTexture(tc.r, tc.g, tc.b, 1)
    local th = c.titleHeight or 20
    h.top:SetHeight(th)
    h.icon:SetSize(th - 4, th - 4)
    h.icon:ClearAllPoints()
    h.icon:SetPoint("TOPLEFT", 4, -2)
    h.head:ClearAllPoints()
    h.head:SetPoint("LEFT", h.icon, "RIGHT", 4, 0)
    h.head:SetPoint("RIGHT", h, "TOPRIGHT", -6, -th / 2)
    ns.ApplyFont(h.head, c.font, c.titleSize, c.outline)
    h.head:SetTextColor(1, 1, 1)
    return h
end

-- the lines (label, value, header?) under the title, the box beside window w
local DrawHover

local function ShowHover(row)
    local sp = row.sp
    if not sp then return end
    local c = S()
    local w = bd.win or win
    local h = HoverLook(c)
    local sname, icon = SpellInfo(sp.spellID)
    h.icon:SetTexture(icon or 134400)
    if sname ~= nil then h.head:SetText(sname)
    elseif sp.creatureName ~= nil then h.head:SetText(sp.creatureName)
    else h.head:SetText("Melee / other") end

    -- the lines: label, value (a header line has no value)
    local lines = {}
    local function Add(l, r, head) lines[#lines + 1] = { l, r, head } end
    local t = TYPE_BY_KEY[(w and w.cfg and w.cfg.meterType) or "DamageDone"] or TYPES[1]
    local total, ps = sp.totalAmount, sp.amountPerSecond
    Add(t.text, Short(total))
    if ps ~= nil then Add("Per second", Short(ps)) end
    local function Join(a, b)
        local ok, txt = pcall(function() return a .. b end)
        return ok and txt or a
    end
    if row.share then Add(Join("Share of ", bd.name or "the total"), row.share .. "%") end
    if row.rank then Add("Rank", ("%d of %d"):format(row.rank, row.count or row.rank)) end
    if t.key == "DamageDone" then
        local src = bd.src
        local targets = src and TargetsOf(w.cfg, src.name)
        if targets and #targets > 0 then
            Add(Join("Targets of ", bd.name or "the player") .. " (all spells)", nil, true)
            for i = 1, math.min(#targets, HOVER_LINES - #lines) do Add(targets[i].name, Short(targets[i].total)) end
        elseif InCombatLockdown() then
            Add("Targets: after the fight", nil, true)
        end
    end
    Add("Hits, crits and misses: not in the game's meter data", nil, true)
    DrawHover(c, lines, w)
end

DrawHover = function(c, lines, w)
    local h = hover
    local th = c.titleHeight or 20
    local lh = math.max(c.fontSize + 4, 14)
    local y = -(th + 4)
    for i, l in ipairs(h.lines) do
        local e = lines[i]
        l.left:ClearAllPoints()
        l.right:ClearAllPoints()
        l.icon:ClearAllPoints()
        l.bar:ClearAllPoints()
        if e then
            ns.ApplyFont(l.left, c.font, e[3] and math.max(8, c.fontSize - 2) or c.fontSize, c.outline)
            ns.ApplyFont(l.right, c.font, c.fontSize, c.outline)
            -- a spell line: its icon, and a bar in the player's colour
            local x = 6
            if e.icon then
                l.icon:SetTexture(e.icon)
                l.icon:SetSize(lh - 2, lh - 2)
                l.icon:SetPoint("TOPLEFT", 6, y + 1)
                l.icon:Show()
                x = 6 + lh
            else
                l.icon:Hide()
            end
            if e.frac and e.color then
                local full = c.width - x - 4
                l.bar:SetTexture(ns.TexturePath(c.texture))
                l.bar:SetVertexColor(e.color.r, e.color.g, e.color.b, 0.55)
                l.bar:SetPoint("TOPLEFT", x - 2, y + 1)
                l.bar:SetSize(math.max(1, full * math.min(1, e.frac)), lh - 2)
                l.bar:Show()
            else
                l.bar:Hide()
            end
            l.left:SetPoint("TOPLEFT", x, y)
            l.left:SetPoint("TOPRIGHT", -6, y)
            l.right:SetPoint("TOPRIGHT", -6, y)
            local okL = pcall(l.left.SetText, l.left, e[1])
            if not okL then l.left:SetText("?") end
            if e[3] then l.left:SetTextColor(0.6, 0.6, 0.62) else l.left:SetTextColor(1, 1, 1) end
            if e[2] ~= nil then
                if not pcall(l.right.SetText, l.right, e[2]) then l.right:SetText("") end
                l.left:SetPoint("TOPRIGHT", l.right, "TOPLEFT", -6, 0)
            else
                l.right:SetText("")
            end
            l.left:Show()
            l.right:Show()
            y = y - lh
        else
            l.left:Hide()
            l.right:Hide()
            l.icon:Hide()
            l.bar:Hide()
        end
    end
    h:SetSize(c.width, -y + 6)
    -- beside the window (the breakdown panel's side when it stands there)
    h:ClearAllPoints()
    local anchor = (panel and panel:IsShown() and not c.breakdownInline) and panel or w
    local right = (anchor:GetRight() or 0) + c.width + 4
    local screen = (UIParent:GetRight() or 1920) * (UIParent:GetEffectiveScale() or 1)
    if right * (anchor:GetEffectiveScale() or 1) > screen then
        h:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -2, 0)
    else
        h:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 2, 0)
    end
    h:Show()
end

-- a name (option): its top spells in the same box; a click still opens
-- the whole breakdown
ShowNameHover = function(row)
    local src, w = row.src, row.win
    if not (src and w and w.cfg) then return end
    local c = S()
    local t = TYPE_BY_KEY[w.cfg.meterType or "DamageDone"] or TYPES[1]
    if t.threat or t.deaths then return end
    local mtype = Enum.DamageMeterType[t.key]
    local spells
    if src.sourceGUID ~= nil or src.sourceCreatureID ~= nil then
        spells = FetchSource(w.cfg, mtype, src.sourceGUID, src.sourceCreatureID)
    end
    if spells == nil then
        local guid, cid = RowIdentity(src)
        if guid or cid then spells = FetchSource(w.cfg, mtype, guid, cid) end
    end
    local h = HoverLook(c)
    local first = spells and spells[1]
    local _, icon = SpellInfo(first and first.spellID)
    h.icon:SetTexture(icon or 134400)
    if not pcall(h.head.SetFormattedText, h.head, "%s - %s", row.name or "?", t.text) then h.head:SetText(t.text) end
    local class = src.classFilename
    local col = Plain(class) and ns.ClassColor(class) or nil
    if col then h.head:SetTextColor(col.r, col.g, col.b) end
    col = col or ns.AccentColor()
    local lines = {}
    local function Add(l, r, head) lines[#lines + 1] = { l, r, head } end
    if spells and #spells > 0 then
        local sum, plain = 0, true
        for _, sp in ipairs(spells) do
            local a = sp.totalAmount
            if Plain(a) and type(a) == "number" then sum = sum + a else plain = false end
        end
        local top = spells[1].totalAmount
        if not (Plain(top) and type(top) == "number" and top > 0) then top = nil end
        for i = 1, math.min(#spells, HOVER_LINES - 1) do
            local sp = spells[i]
            local sname, sicon = SpellInfo(sp.spellID)
            local label = sname or sp.creatureName or "Melee / other"
            local txt = Short(sp.totalAmount)
            if plain and sum > 0 then
                local okF, s2 = pcall(string.format, "%s  %d%%", txt, math.floor(sp.totalAmount / sum * 100 + 0.5))
                if okF then txt = s2 end
            end
            Add(label, txt)
            local e = lines[#lines]
            e.icon = sicon or 134400
            local a = sp.totalAmount
            if top and Plain(a) and type(a) == "number" then e.frac, e.color = a / top, col end
        end
    else
        Add(InCombatLockdown() and "Spells: after the fight" or "Nothing in this fight", nil, true)
    end
    Add("Click: the whole breakdown", nil, true)
    DrawHover(c, lines, w)
end

HideHover = function()
    if hover then hover:Hide() end
end

local TitleButton      -- defined with the window's title bar below
local function PanelRow(i)
    local r = panel.rows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, panel.body)
    r.w = win
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetPoint("TOPLEFT")
    r.icon:SetPoint("BOTTOMLEFT")
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.bar = CreateFrame("StatusBar", nil, r)
    r.bar:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 1, 0)
    r.bar:SetPoint("BOTTOMRIGHT")
    r.edge = CreateFrame("Frame", nil, r)
    r.edge:SetAllPoints()
    r.edge:SetFrameLevel(r.bar:GetFrameLevel() + 2)
    r.border = ns.Frame.MakeBorder(r.edge)
    r.bg = r.bar:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.left = r.bar:CreateFontString(nil, "OVERLAY")
    r.right = r.bar:CreateFontString(nil, "OVERLAY")
    ns.ApplyFont(r.left, "GLOBAL", 11, "OUTLINE")
    ns.ApplyFont(r.right, "GLOBAL", 11, "OUTLINE")
    r.left:SetJustifyH("LEFT")
    r.left:SetWordWrap(false)
    r.right:SetJustifyH("RIGHT")
    r:EnableMouse(true)
    -- hover: the spell's details in a box beside the window
    r:SetScript("OnEnter", function(self)
        if self.typeKey or not self.sp then return end
        DM.UseWindow(self.w)
        local ok, err = pcall(ShowHover, self)
        if not ok then ns.Log("meter", "spell details: %s", tostring(err)) end
    end)
    r:SetScript("OnLeave", function() HideHover() end)
    r:SetScript("OnMouseUp", function(self, button)
        DM.UseWindow(self.w)
        if button == "RightButton" and S().breakdownInline then DM.CloseBreakdown()
        elseif button == "LeftButton" and self.typeKey and bd.types then
            -- meter list: this meter in the window
            local w = bd.win
            DM.CloseBreakdown()
            if w and w.cfg then
                w.cfg.meterType = self.typeKey
                if self.typeKey == "Threat" and not InCombatLockdown() then w.keepThreat = true end
                w.offset = 0
                DM.Refresh()
            end
        end
    end)
    panel.rows[i] = r
    return r
end

local function BuildPanel()
    if win.panel then panel = win.panel return end
    local w = win
    local p = CreateFrame("Frame", "HUF_DamageMeterBreakdown" .. (w.index or 1), UIParent)
    w.panel = p
    panel = p
    p.w = w
    p:SetFrameStrata("MEDIUM")
    p:SetClampedToScreen(true)
    p:EnableMouse(true)
    p.rows = {}
    p.fill = p:CreateTexture(nil, "BACKGROUND")
    p.fill:SetAllPoints()
    p.border = UI.Border(p, 0.15, 0.15, 0.17, 1)
    local title = CreateFrame("Frame", nil, p)
    title:SetPoint("TOPLEFT")
    title:SetPoint("TOPRIGHT")
    title:SetHeight(20)
    p.titleBar = title
    p.title = title:CreateTexture(nil, "BORDER")
    p.title:SetAllPoints()
    p.line = title:CreateTexture(nil, "ARTWORK")
    p.line:SetPoint("BOTTOMLEFT")
    p.line:SetPoint("BOTTOMRIGHT")
    p.line:SetHeight(1)
    local close = TitleButton(title, function() DM.UseWindow(w) DM.CloseBreakdown() end, "Close")
    close:SetPoint("TOPRIGHT", -4, 0)
    close:SetPoint("BOTTOMRIGHT", -4, 0)
    close:SetWidth(16)
    close.text:SetText("x")
    p.closeText = close.text
    p.closeB = close
    -- inside the window: back to the names
    local back = TitleButton(title, function() DM.UseWindow(w) DM.CloseBreakdown() end, "Back to the names (or right-click the list)")
    back:SetPoint("TOPLEFT", 4, 0)
    back:SetPoint("BOTTOMLEFT", 4, 0)
    back:SetWidth(16)
    back.text:SetText("<")
    p.backB = back
    p.backText = back.text
    p.head = title:CreateFontString(nil, "OVERLAY")
    ns.ApplyFont(p.head, "GLOBAL", 11, "OUTLINE")
    p.head:SetPoint("LEFT", 6, 0)
    p.head:SetPoint("RIGHT", close, "LEFT", -4, 0)
    p.head:SetJustifyH("LEFT")
    p.head:SetWordWrap(false)
    p.body = CreateFrame("Frame", nil, p)
    p.body:SetPoint("TOPLEFT", 1, -21)
    p.body:SetPoint("BOTTOMRIGHT", -1, 1)
    p.body:EnableMouseWheel(true)
    p.body:SetScript("OnMouseWheel", function(_, delta)
        DM.UseWindow(w)
        p.offset = math.max(0, (p.offset or 0) - delta)
        DM.RefreshBreakdown()
    end)
    p.body:EnableMouse(true)
    p.body:SetScript("OnMouseUp", function(_, button)
        DM.UseWindow(w)
        if button == "RightButton" and S().breakdownInline then DM.CloseBreakdown() end
    end)
    p.empty = p.body:CreateFontString(nil, "OVERLAY")
    ns.ApplyFont(p.empty, "GLOBAL", 11, "OUTLINE")
    p.empty:SetPoint("TOP", 0, -8)
    p.empty:SetTextColor(0.5, 0.5, 0.5)
    p.offset = 0
    p:Hide()
end

local function LayoutPanel()
    local c = S()
    local p = panel
    p:SetScale(c.scale)
    p:SetSize(c.width, win:GetHeight())
    p:ClearAllPoints()
    local inline = c.breakdownInline
    if inline then
        -- in the window's place, above it: "<" (or a right-click) goes back
        p:SetPoint("TOPLEFT", win, "TOPLEFT", 0, 0)
        p:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", 0, 0)
        p:SetFrameLevel(win:GetFrameLevel() + 20)
    else
        local right = (win:GetRight() or 0) + c.width + 4
        local screen = (UIParent:GetRight() or GetScreenWidth and GetScreenWidth() or 1920) * (UIParent:GetEffectiveScale() or 1)
        if right * (win:GetEffectiveScale() or 1) > screen then
            p:SetPoint("TOPRIGHT", win, "TOPLEFT", -2, 0)
        else
            p:SetPoint("TOPLEFT", win, "TOPRIGHT", 2, 0)
        end
    end
    p.backB:SetShown(inline and true or false)
    p.closeB:SetShown(not inline)
    p.head:ClearAllPoints()
    p.head:SetPoint("LEFT", inline and p.backB or p.titleBar, inline and "RIGHT" or "LEFT", inline and 4 or 6, 0)
    p.head:SetPoint("RIGHT", p.closeB, "LEFT", -4, 0)
    -- the window's title bar and background settings
    local a = ns.ACCENT
    local th = c.titleHeight or 20
    local bg, tc = c.bgColor or { r = 0.04, g = 0.04, b = 0.05 }, c.titleColor or { r = 0.08, g = 0.08, b = 0.09 }
    local ta = (c.titleAlpha or -1) >= 0 and c.titleAlpha or math.min(1, c.bgAlpha + 0.15)
    p.titleBar:SetHeight(th)
    p.body:ClearAllPoints()
    p.body:SetPoint("TOPLEFT", 1, -(th + 1))
    p.body:SetPoint("BOTTOMRIGHT", -1, 1)
    p.fill:SetColorTexture(bg.r, bg.g, bg.b, c.bgAlpha)
    p.title:SetColorTexture(tc.r, tc.g, tc.b, ta)
    p.border:SetShown(c.windowBorder ~= false)
    -- inside the window: the window's own contents step aside, so the
    -- breakdown has exactly its background (also when see-through)
    DM.Cover(win, inline and true or false)
    p.line:SetColorTexture(a[1], a[2], a[3], 0.9)
    p.line:SetShown(c.titleLine ~= false)
    ns.ApplyFont(p.head, c.font, c.titleSize, c.outline)
    ns.ApplyFont(p.closeText, c.font, c.titleSize, c.outline)
    ns.ApplyFont(p.backText, c.font, c.titleSize, c.outline)
    ns.ApplyFont(p.empty, c.font, c.fontSize, c.outline)
    local tex = ns.TexturePath(c.texture)
    for i = 1, ROW_POOL do
        local r = PanelRow(i)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", p.body, "TOPLEFT", 0, -(i - 1) * (c.rowHeight + c.rowGap))
        r:SetPoint("TOPRIGHT", p.body, "TOPRIGHT", 0, -(i - 1) * (c.rowHeight + c.rowGap))
        r:SetHeight(c.rowHeight)
        r.icon:SetWidth(c.rowHeight)
        r.bar:SetStatusBarTexture(tex)
        -- inside the window: drawn like the meter's rows (icon flush, the same
        -- border and empty-bar colour); beside it as before
        local bb = c.barBgColor or { r = 0, g = 0, b = 0 }
        r.bar:ClearAllPoints()
        r.bar:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", inline and 0 or 1, 0)
        r.bar:SetPoint("BOTTOMRIGHT")
        if inline then r.bg:SetColorTexture(bb.r, bb.g, bb.b, c.barBgAlpha or 0.35)
        else r.bg:SetColorTexture(0, 0, 0, 0.35) end
        ns.Frame.LayoutBorder(r.border, r.edge, inline and (c.rowBorder or 0) or 0, { r = 0, g = 0, b = 0 }, 1)
        ns.ApplyFont(r.left, c.font, c.fontSize, c.outline)
        ns.ApplyFont(r.right, c.font, c.fontSize, c.outline)
        r.left:ClearAllPoints()
        r.left:SetPoint("LEFT", 4, 0)
        r.left:SetPoint("RIGHT", r.right, "LEFT", -4, 0)
        r.right:ClearAllPoints()
        r.right:SetPoint("RIGHT", -4, 0)
        if i > Rows() then r:Hide() end
    end
end

-- meter list inside the window (right-click on the names): a row per meter
-- type, the current one lit; a click picks it, a right-click goes back
function DM.OpenTypes()
    DM.UseWindow(win)
    bd = { open = true, types = true, win = win }
    win.bd = bd
    BuildPanel()
    LayoutPanel()
    panel.offset = 0
    panel:Show()
    DM.RefreshBreakdown()
end

local function RefreshTypes()
    local c = S()
    local cur = bd.win and bd.win.cfg and bd.win.cfg.meterType
    panel.head:SetText("Meters")
    panel.offset = math.max(0, math.min(panel.offset or 0, #TYPES - Rows()))
    local muted = c.titleIconsMuted ~= false
    local a = ns.ACCENT
    local shown = 0
    for i = 1, Rows() do
        local r = PanelRow(i)
        local t = TYPES[i + (panel.offset or 0)]
        if t then
            shown = shown + 1
            r.typeKey, r.spellID, r.sp = t.key, nil, nil
            r.icon:SetTexture(TYPE_ICONS[t.key] or TYPE_ICONS.DamageDone)
            r.icon:SetDesaturated(muted)
            if muted then r.icon:SetVertexColor(0.75, 0.75, 0.77) else r.icon:SetVertexColor(1, 1, 1) end
            r.left:SetText(t.text)
            r.right:SetText(t.key == cur and "<" or "")
            r.bar:SetMinMaxValues(0, 1)
            r.bar:SetValue(t.key == cur and 1 or 0)
            r.bar:SetStatusBarColor(a[1], a[2], a[3])
            r:Show()
        else
            r.typeKey = nil
            r:Hide()
        end
    end
    for i = Rows() + 1, #panel.rows do panel.rows[i]:Hide() end
    panel.empty:SetShown(shown == 0)
end

function DM.OpenBreakdown(src, name)
    local t = TYPE_BY_KEY[WC().meterType] or TYPES[1]
    if t.threat then return end
    DM.UseWindow(win)
    if bd.open and bd.src == src then DM.CloseBreakdown() return end
    local guid, cid = RowIdentity(src)
    bd = { open = true, src = src, guid = guid, cid = cid, name = name, unit = RowUnit(src),
           rawGuid = src.sourceGUID, rawCid = src.sourceCreatureID,
           color = src.classFilename, win = win }
    win.bd = bd
    BuildPanel()
    LayoutPanel()
    panel.offset = 0
    panel:Show()
    DM.RefreshBreakdown()
end

-- closes the window at hand's breakdown / meter list (the others stay)
function DM.CloseBreakdown()
    bd = { open = false }
    if win then win.bd = bd end
    HideHover()
    if panel then panel:Hide() end
    DM.Cover(win, false)
end

local function CloseAllBreakdowns()
    local keep = win
    for _, w in ipairs(wins) do
        if w.bd and w.bd.open then DM.UseWindow(w) DM.CloseBreakdown() end
    end
    win = keep
end

-- a window's own title bar, rows and background hidden (under a breakdown
-- inside it) or back
function DM.Cover(w, on)
    if not (w and w.body) or (w.covered or false) == on then return end
    w.covered = on
    w.body:SetShown(not on)
    w.titleBar:SetShown(not on)
    w.fill:SetShown(not on)
    w.border:SetShown(not on and S().windowBorder ~= false)
end

function DM.RefreshBreakdown()
    if win then DM.UseWindow(win) end
    if not (bd.open and panel and panel:IsShown()) then return end
    win = bd.win or win
    if bd.types then RefreshTypes() return end
    for _, r in ipairs(panel.rows) do
        r.typeKey = nil
        r.icon:SetDesaturated(false)
        r.icon:SetVertexColor(1, 1, 1)
    end
    local c = S()
    local spells, t, why = GetBreakdown()
    local ok = pcall(panel.head.SetFormattedText, panel.head, "%s - %s", bd.name or "?", t.text)
    if not ok then panel.head:SetText(t.text) end
    spells = spells or {}
    local n = #spells
    panel.offset = math.max(0, math.min(panel.offset or 0, n - Rows()))
    -- percent of the whole row, when the numbers are readable
    local sum, plain = 0, true
    for _, sp in ipairs(spells) do
        local a = sp.totalAmount
        if Plain(a) and type(a) == "number" then sum = sum + a else plain = false end
    end
    local max = spells[1] and spells[1].totalAmount
    local col = bd.color and Plain(bd.color) and ns.ClassColor(bd.color)
    local shown = 0
    for i = 1, Rows() do
        local r = PanelRow(i)
        local sp = spells[i + panel.offset]
        if sp then
            shown = shown + 1
            local id = sp.spellID
            local sname, icon = SpellInfo(id)
            r.spellID = id
            r.sp, r.rank, r.count, r.share = sp, i + panel.offset, n, nil
            if plain and sum > 0 then r.share = math.floor(sp.totalAmount / sum * 100 + 0.5) end
            r.icon:SetTexture(icon or 134400)          -- question mark
            if sname ~= nil then r.left:SetText(sname)
            elseif sp.creatureName ~= nil then r.left:SetText(sp.creatureName)
            else r.left:SetText("Melee / other") end
            local total = sp.totalAmount
            local txt = Short(total)
            if plain and sum > 0 then
                local okF, s2 = pcall(string.format, "%s  %d%%", txt, math.floor(total / sum * 100 + 0.5))
                if okF then txt = s2 end
            end
            r.right:SetText(txt)
            if max == nil or not pcall(r.bar.SetMinMaxValues, r.bar, 0, max) then r.bar:SetMinMaxValues(0, 1) end
            if not pcall(r.bar.SetValue, r.bar, total or 0) then r.bar:SetValue(0) end
            if col and c.colorMode == "CLASS" then r.bar:SetStatusBarColor(col.r, col.g, col.b)
            else BarColor(r.bar, { classFilename = bd.color }) end
            r:Show()
        else
            r.spellID, r.sp = nil, nil
            r:Hide()
        end
    end
    for i = Rows() + 1, #panel.rows do panel.rows[i]:Hide() end
    panel.empty:SetText(why or "Nothing in this fight")
    panel.empty:SetShown(shown == 0)
end

local function Layout()
    local c = S()
    local w = win
    w:SetScale(c.scale)
    local th = c.titleHeight or 20
    w:SetSize(Width(), th + Rows() * (c.rowHeight + c.rowGap) + 2)
    local pt = WC().point
    w:ClearAllPoints()
    w:SetPoint(pt[1], UIParent, pt[2], pt[3], pt[4])
    local a = ns.ACCENT
    local bg, tc = c.bgColor or { r = 0.04, g = 0.04, b = 0.05 }, c.titleColor or { r = 0.08, g = 0.08, b = 0.09 }
    local ta = (c.titleAlpha or -1) >= 0 and c.titleAlpha or math.min(1, c.bgAlpha + 0.15)
    w.fill:SetColorTexture(bg.r, bg.g, bg.b, c.bgAlpha)
    w.titleBar:SetHeight(th)
    w.title:SetColorTexture(tc.r, tc.g, tc.b, ta)
    w.line:SetColorTexture(a[1], a[2], a[3], 0.9)
    w.line:SetShown(c.titleLine ~= false)
    w.border:SetShown(c.windowBorder ~= false and not w.covered)
    w.body:ClearAllPoints()
    w.body:SetPoint("TOPLEFT", 1, -(th + 1))
    w.body:SetPoint("BOTTOMRIGHT", -1, 1)
    for _, fs in ipairs({ w.typeText, w.sessionText, w.resetText, w.closeText, w.addB.text }) do
        ns.ApplyFont(fs, c.font, c.titleSize, c.outline)
    end
    ns.ApplyFont(w.label, c.font, c.titleSize, c.outline)
    w.label:SetTextColor(1, 1, 1)
    -- every window has its x (also while locked); reset is in the fight list now,
    -- the old R button stays as a zero-width anchor
    local resetB = w.resetText:GetParent()
    local closeB = w.closeText:GetParent()
    closeB:Show()
    closeB:SetWidth(14)
    resetB:ClearAllPoints()
    resetB:SetPoint("TOPRIGHT", closeB, "TOPLEFT", -1, 0)
    resetB:SetPoint("BOTTOMRIGHT", closeB, "BOTTOMLEFT", -1, 0)
    resetB:SetWidth(0.1)
    resetB:Hide()
    w.typeB:ClearAllPoints()
    w.sessB:ClearAllPoints()
    w.addB:ClearAllPoints()
    w.label:ClearAllPoints()
    if c.titleIcons then
        -- like EllesmereUI's header: the name at the left; at the right the
        -- meter type and fight icons, + new window, x close
        local is = math.max(8, math.min(c.titleIconSize or 18, th - 2))
        w.addB:SetPoint("TOPRIGHT", resetB, "TOPLEFT", -3, 0)
        w.addB:SetPoint("BOTTOMRIGHT", resetB, "BOTTOMLEFT", -3, 0)
        w.addB:SetWidth(14)
        w.sessB:SetSize(is + 2, is + 2)
        w.sessB:SetPoint("RIGHT", w.addB, "LEFT", -3, 0)
        w.typeB:SetSize(is + 2, is + 2)
        w.typeB:SetPoint("RIGHT", w.sessB, "LEFT", -2, 0)
        w.label:SetPoint("LEFT", 6, 0)
        w.label:SetPoint("RIGHT", w.typeB, "LEFT", -4, 0)
        w.label:Show()
        w.labelB:Show()
    else
        w.typeB:SetPoint("TOPLEFT", 3, 0)
        w.typeB:SetPoint("BOTTOMLEFT", 3, 0)
        w.typeB:SetWidth(math.max(70, Width() * 0.42))
        w.addB:SetPoint("TOPLEFT", w.typeB, "TOPRIGHT", 3, 0)
        w.addB:SetPoint("BOTTOMLEFT", w.typeB, "BOTTOMRIGHT", 3, 0)
        w.addB:SetWidth(14)
        w.sessB:SetPoint("TOPRIGHT", resetB, "TOPLEFT", -3, 0)
        w.sessB:SetPoint("BOTTOMRIGHT", resetB, "BOTTOMLEFT", -3, 0)
        w.sessB:SetPoint("LEFT", w.addB, "RIGHT", 4, 0)
        w.label:Hide()
        w.labelB:Hide()
    end
    w.typeText:SetTextColor(1, 1, 1)
    if c.titleAccent == false then w.sessionText:SetTextColor(1, 1, 1)
    else w.sessionText:SetTextColor(a[1], a[2], a[3]) end
    local tex = ns.TexturePath(c.texture)
    local iconW = (c.icons == "CLASS" or c.icons == "SPEC") and c.rowHeight or 0
    local bb, rb = c.barBgColor or { r = 0, g = 0, b = 0 }, c.rowBorder or 0
    for i = 1, ROW_POOL do
        local r = Row(i)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", w.body, "TOPLEFT", iconW, -(i - 1) * (c.rowHeight + c.rowGap))
        r:SetPoint("TOPRIGHT", w.body, "TOPRIGHT", 0, -(i - 1) * (c.rowHeight + c.rowGap))
        r:SetHeight(c.rowHeight)
        r:SetStatusBarTexture(tex)
        r.bg:SetColorTexture(bb.r, bb.g, bb.b, c.barBgAlpha or 0.35)
        r.icon:SetSize(iconW > 0 and iconW or 1, c.rowHeight)
        r.iconOn = iconW > 0
        if not r.iconOn then r.icon:Hide() end
        r.edge:SetPoint("TOPLEFT", r, "TOPLEFT", -iconW, 0)
        ns.Frame.LayoutBorder(r.border, r.edge, rb, { r = 0, g = 0, b = 0 }, 1)
        ns.ApplyFont(r.left, c.font, c.fontSize, c.outline)
        ns.ApplyFont(r.right, c.font, c.fontSize, c.outline)
        r.left:ClearAllPoints()
        r.left:SetPoint("LEFT", 4, 0)
        r.left:SetPoint("RIGHT", r.right, "LEFT", -4, 0)
        r.right:ClearAllPoints()
        r.right:SetPoint("RIGHT", -4, 0)
        if i > Rows() then r:Hide() end
    end
    ns.ApplyFont(w.empty, c.font, c.fontSize, c.outline)
end
-- lays out one window (default: the one at hand); unlock mode boxes pass theirs
DM.LayoutWindows = function(w)
    if w then win = w end
    if win then Layout() end
end


-- a dropdown in the title bar: dark box, text, arrow; opens HUF's list
local function TitleDropdown(parent, items, get, set, tip)
    local b = CreateFrame("Button", nil, parent)
    b:RegisterForClicks("LeftButtonUp")
    b.box = b:CreateTexture(nil, "BACKGROUND")
    b.box:SetPoint("TOPLEFT", 0, -3)
    b.box:SetPoint("BOTTOMRIGHT", 0, 3)
    b.box:SetColorTexture(0.13, 0.13, 0.15, 1)
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints(b.box)
    b.hl:SetColorTexture(1, 1, 1, 0.07)
    b.arrow = b:CreateFontString(nil, "OVERLAY")
    ns.ApplyFont(b.arrow, "GLOBAL", 9, "OUTLINE")
    b.arrow:SetPoint("RIGHT", -4, 0)
    b.arrow:SetText("v")
    b.arrow:SetTextColor(0.65, 0.65, 0.65)
    b.text = b:CreateFontString(nil, "OVERLAY")
    ns.ApplyFont(b.text, "GLOBAL", 11, "OUTLINE")
    b.text:SetPoint("LEFT", 5, 0)
    b.text:SetPoint("RIGHT", b.arrow, "LEFT", -3, 0)
    b.text:SetJustifyH("LEFT")
    b.text:SetWordWrap(false)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("CENTER")
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.icon:Hide()
    -- muted icon: grey and dimmed, the accent colour under the mouse
    function b:TintIcon()
        local muted = S().titleIconsMuted ~= false
        self.icon:SetDesaturated(muted)
        if not muted then self.icon:SetVertexColor(1, 1, 1)
        elseif self:IsMouseOver() then local a = ns.ACCENT self.icon:SetVertexColor(a[1], a[2], a[3])
        else self.icon:SetVertexColor(0.6, 0.6, 0.62) end
    end
    -- an icon in place of the text, box and arrow (nil: the text again)
    function b:SetIcon(path, size)
        self.iconMode = path ~= nil
        if path then
            self.icon:SetTexture(path)
            self.icon:SetSize(size, size)
            self:TintIcon()
            self.icon:Show()
            self.text:Hide()
            self.arrow:Hide()
            self.box:Hide()
            self.hl:ClearAllPoints()
            self.hl:SetAllPoints(self.icon)
        else
            self.icon:Hide()
            self.text:Show()
            self.arrow:SetShown(not self.disabled)
            self.box:SetShown(not self.disabled)
            self.hl:ClearAllPoints()
            self.hl:SetAllPoints(self.box)
        end
    end
    b:SetScript("OnClick", function(self)
        if self.disabled then return end
        GameTooltip:Hide()
        UI.OpenList(self, items(), get(), function(v) set(v) end)
    end)
    b.items, b.get, b.set = items, get, set
    -- mouse wheel steps through the list without opening it
    b:EnableMouseWheel(true)
    b:SetScript("OnMouseWheel", function(self, delta)
        if self.disabled then return end
        local list, cur, idx = items(), get(), nil
        local values = {}
        for _, e in ipairs(list) do if not e.header and not e.noWheel then values[#values + 1] = e.value end end
        for i, v in ipairs(values) do if v == cur then idx = i end end
        idx = ((idx or 1) - 1 - delta) % #values + 1
        set(values[idx])
    end)
    b:SetScript("OnEnter", function(self)
        if self.disabled then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(type(tip) == "function" and tip() or tip, 1, 1, 1, 1, true)
        GameTooltip:Show()
        if self.iconMode then self:TintIcon() end
    end)
    b:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        if self.iconMode then C_Timer.After(0, function() self:TintIcon() end) end
    end)
    function b:SetDisabled(off)
        self.disabled = off
        self.arrow:SetShown(not off and not self.iconMode)
        self.box:SetShown(not off and not self.iconMode)
        self:EnableMouse(not off)
    end
    return b
end

TitleButton = function(parent, onClick, tip)
    local b = CreateFrame("Button", nil, parent)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", onClick)
    b.text = b:CreateFontString(nil, "OVERLAY")
    ns.ApplyFont(b.text, "GLOBAL", 11, "OUTLINE")
    b.text:SetAllPoints()
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(tip, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

local function Build(index)
    if wins[index] then win = wins[index] return end
    local w = CreateFrame("Frame", index == 1 and "HUF_DamageMeter" or ("HUF_DamageMeter" .. index), UIParent)
    if ns.Snap then ns.Snap.Register(w) end
    wins[index] = w
    w.index = index
    win = w
    w:SetFrameStrata("MEDIUM")
    w:SetClampedToScreen(true)
    w:SetMovable(true)
    w:EnableMouse(true)
    w.rows = {}
    w.fill = w:CreateTexture(nil, "BACKGROUND")
    w.fill:SetAllPoints()
    w.border = UI.Border(w, 0.15, 0.15, 0.17, 1)
    -- title bar: meter type (click: next, right-click: back), fight, reset
    local title = CreateFrame("Frame", nil, w)
    w.titleBar = title
    title:SetPoint("TOPLEFT")
    title:SetPoint("TOPRIGHT")
    title:SetHeight(20)
    title:EnableMouse(true)
    title:RegisterForDrag("LeftButton")
    title:SetScript("OnDragStart", function()
        if S().locked and not ns.unlocked then return end      -- unlock mode moves it even when locked
        w.dragFrom = { w:GetLeft() or 0, w:GetTop() or 0 }
        ns.Snap.StartDrag(w)
    end)
    title:SetScript("OnDragStop", function()
        ns.Snap.StopDrag(w)
        local from = w.dragFrom
        if not from then return end
        w.dragFrom = nil
        local p = w.cfg.point
        p[3] = math.floor(p[3] + (w:GetLeft() or 0) - from[1] + 0.5)
        p[4] = math.floor(p[4] + (w:GetTop() or 0) - from[2] + 0.5)
        win = w
        Layout()
        if w.bd and w.bd.open then DM.UseWindow(w) LayoutPanel() end
    end)
    w.title = title:CreateTexture(nil, "BORDER")
    w.title:SetAllPoints()
    w.line = title:CreateTexture(nil, "ARTWORK")
    w.line:SetPoint("BOTTOMLEFT")
    w.line:SetPoint("BOTTOMRIGHT")
    w.line:SetHeight(1)

    local typeB = TitleDropdown(title, function()
        local l = {}
        for _, t in ipairs(TYPES) do l[#l + 1] = { value = t.key, text = t.text } end
        return l
    end, function() return w.cfg.meterType end, function(v)
        w.cfg.meterType = v
        if v == "Threat" and not InCombatLockdown() then w.keepThreat = true end
        w.offset = 0
        DM.Refresh()
    end, function()
        local t = TYPE_BY_KEY[w.cfg.meterType] or TYPES[1]
        return t.text .. "\n|cffaaaaaaWhat the meter shows (damage, healing, taken, interrupts, dispels, deaths, threat). Mouse wheel: step through.|r"
    end)
    typeB:SetPoint("TOPLEFT", 3, 0)
    typeB:SetPoint("BOTTOMLEFT", 3, 0)
    typeB:SetWidth(120)
    w.typeB = typeB
    w.typeText = typeB.text

    -- new window
    local add = TitleButton(title, function() DM.AddWindow() end, "New window (up to 5)")
    add:SetPoint("TOPLEFT", typeB, "TOPRIGHT", 3, 0)
    add:SetPoint("BOTTOMLEFT", typeB, "BOTTOMRIGHT", 3, 0)
    add:SetWidth(14)
    add.text:SetText("+")
    w.addB = add
    w.quickLast = add

    -- close: this window and its settings (the last one: the meter off)
    local close = TitleButton(title, function() DM.CloseWindow(w.index) end, "Close this window (its settings go)")
    close:SetPoint("TOPRIGHT", -3, 0)
    close:SetPoint("BOTTOMRIGHT", -3, 0)
    close:SetWidth(14)
    close.text:SetText("x")
    w.closeText = close.text

    -- (no R button any more: "Reset all fights" is the last entry of the fight list)
    local reset = TitleButton(title, function() end, "")
    reset:SetPoint("TOPRIGHT", close, "TOPLEFT", -1, 0)
    reset:SetPoint("BOTTOMRIGHT", close, "BOTTOMLEFT", -1, 0)
    reset:SetWidth(0.1)
    reset:Hide()
    w.resetText = reset.text

    local sessB = TitleDropdown(title, function()
        local l = {}
        for _, e in ipairs(DM.Sessions()) do l[#l + 1] = { value = e.id, text = e.text } end
        l[#l + 1] = { value = "HUF_RESET", text = "|cffff6060Reset all fights|r", noWheel = true }   -- the wheel never lands on it
        return l
    end, function() return w.cfg.session end, function(v)
        if v == "HUF_RESET" then
            UI.Confirm("Reset all damage meter data?", "Reset", function()
                if Available() and C_DamageMeter.ResetAllCombatSessions then pcall(C_DamageMeter.ResetAllCombatSessions) end
                for _, o in ipairs(wins) do if o.cfg then o.cfg.session = "CURRENT" end end
                DM.Refresh()
            end)
            return
        end
        w.cfg.session = v
        w.offset = 0
        DM.Refresh()
    end, function()
        local prev = win
        win = w
        local label = SessionLabel()
        win = prev
        return label .. "\n|cffaaaaaaWhich fight: current, overall or an earlier one. Mouse wheel: step through.|r"
    end)
    sessB:SetPoint("TOPRIGHT", reset, "TOPLEFT", -3, 0)
    sessB:SetPoint("BOTTOMRIGHT", reset, "BOTTOMLEFT", -3, 0)
    sessB:SetPoint("LEFT", w.quickLast, "RIGHT", 4, 0)
    w.sessB = sessB
    w.sessionText = sessB.text
    -- icon title bar: the meter type's name between the buttons
    w.label = title:CreateFontString(nil, "OVERLAY")
    w.label:SetJustifyH("LEFT")
    w.label:SetWordWrap(false)
    -- the name is a button too: the meter list (as the type icon), the mouse
    -- wheel steps through; dragging it still moves the window
    local lb = CreateFrame("Button", nil, title)
    lb:SetAllPoints(w.label)
    lb:RegisterForClicks("LeftButtonUp")
    lb:RegisterForDrag("LeftButton")
    lb:SetScript("OnDragStart", function() title:GetScript("OnDragStart")(title) end)
    lb:SetScript("OnDragStop", function() title:GetScript("OnDragStop")(title) end)
    lb:SetScript("OnClick", function(self)
        local tb = w.typeB
        if tb.disabled then return end
        GameTooltip:Hide()
        UI.OpenList(self, tb.items(), tb.get(), function(v) tb.set(v) end)
    end)
    lb:EnableMouseWheel(true)
    lb:SetScript("OnMouseWheel", function(_, delta) w.typeB:GetScript("OnMouseWheel")(w.typeB, delta) end)
    lb:SetScript("OnEnter", function()
        local a = ns.ACCENT
        w.label:SetTextColor(a[1], a[2], a[3])
    end)
    lb:SetScript("OnLeave", function() w.label:SetTextColor(1, 1, 1) end)
    w.labelB = lb

    w.body = CreateFrame("Frame", nil, w)
    w.body:SetPoint("TOPLEFT", 1, -21)
    w.body:SetPoint("BOTTOMRIGHT", -1, 1)
    w.body:EnableMouseWheel(true)
    w.body:SetScript("OnMouseWheel", function(_, delta)
        w.offset = math.max(0, (w.offset or 0) - delta)
        DM.Refresh()
    end)
    -- inside-the-window navigation: right-click the names for the meter list
    w.body:EnableMouse(true)
    w.body:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" and S().breakdownInline then
            win = w
            DM.OpenTypes()
        end
    end)
    w.empty = w.body:CreateFontString(nil, "OVERLAY")
    ns.ApplyFont(w.empty, "GLOBAL", 11, "OUTLINE")
    w.empty:SetPoint("TOP", 0, -8)
    w.empty:SetTextColor(0.5, 0.5, 0.5)
    w.offset = 0
end

---------------------------------------------------------------------------
-- Showing, updating
---------------------------------------------------------------------------
-- the meter as a whole (each window's "Show" is checked in WindowWanted)
local function WantShown()
    return ns.db.damageMeter.enabled and Available() and true or false
end
-- a setting of window w (its own, else the shared one)
local function WOpt(w, k)
    local v = w and w.cfg and w.cfg[k]
    if v == nil then v = ns.db.damageMeter[k] end
    return v
end

-- threat windows out of combat (option): hidden. One switched to threat out of
-- combat stays until the next fight is over, so it doesn't vanish on the spot.
-- In unlock mode or while the damage meter settings are open every window
-- shows, so threat windows can be moved and changed out of combat too.
function DM.Editing()
    if ns.unlocked then return true end
    local page = ns.configPages and ns.configPages.damagemeter
    return page and page.frame and page.frame:IsVisible() and true or false
end
-- (0.5.51: "Hide threat windows out of combat" is gone - "Show" decides for
-- every window, "In combat" included)
local function WindowWanted(w)
    if DM.Editing() then return true end   -- settings open / unlock mode: always reachable
    local show = WOpt(w, "show")
    if show == "GROUP" then return IsInGroup() end
    if show == "INSTANCE" then return (IsInInstance()) and true or false end
    if show == "COMBAT" then return InCombatLockdown() and true or false end   -- combat start / end re-apply
    return true
end

-- out of combat (option): all windows at the set opacity, full while the
-- mouse is over one (checked 10x a second while it matters)
local fader
local function Fade()
    local dim = false
    local combat = InCombatLockdown()
    for _, w in ipairs(wins) do
        if w:IsShown() then
            local wdim = WOpt(w, "fadeOOC") and not combat
            dim = dim or wdim
            local p = w.bd and w.bd.open and w.panel
            local over = w:IsMouseOver() or (p and p:IsShown() and p:IsMouseOver())
            local a = (wdim and not over) and WOpt(w, "fadeAlpha") or 1
            w:SetAlpha(a)
            if p then p:SetAlpha(a) end
        end
    end
    if dim and not fader then
        fader = C_Timer.NewTicker(0.1, Fade)
    elseif not dim and fader then
        fader:Cancel()
        fader = nil
    end
end
DM.Fade = Fade

local function HideAll()
    for _, w in ipairs(wins) do w:Hide() end
    CloseAllBreakdowns()
end

function DM.Apply()
    DM.ApplyBlizzard()
    -- spec icons: HUF inspects the group (Specs.lua) only while a window shows them
    if ns.Specs then
        local any = false
        local d = ns.db.damageMeter
        if d.enabled then
            if d.icons == "SPEC" then any = true end
            for _, wc in ipairs(type(d.windows) == "table" and d.windows or {}) do
                if type(wc) == "table" and wc.icons == "SPEC" then any = true end
            end
        end
        ns.Specs.SetWanted(any)
    end
    if not Available() or not WantShown() then HideAll() return end
    local cfgs = DM.EnsureWindows()
    local count = S().windowCount
    for i = 1, count do
        Build(i)
        win.cfg = cfgs[i]
        Layout()
        win.empty:SetText("No data yet")
        win:SetShown(WindowWanted(win))
    end
    for i = count + 1, #wins do wins[i]:Hide() end
    Fade()
    for _, w in ipairs(wins) do
        if w.bd and w.bd.open then
            DM.UseWindow(w)
            if w:IsShown() then LayoutPanel() else DM.CloseBreakdown() end
        end
    end
    DM.Refresh()
end

-- refreshes at most 4x a second; the meter sends a lot of updates in combat
local pending
local function Soon()
    if pending then return end
    pending = true
    C_Timer.After(0.25, function()
        pending = false
        DM.Refresh()
    end)
end

ns.On("DAMAGE_METER_COMBAT_SESSION_UPDATED", Soon)
ns.On("DAMAGE_METER_CURRENT_SESSION_UPDATED", Soon)
ns.On("DAMAGE_METER_RESET", function()
    for _, w in ipairs(wins) do if w.cfg then w.cfg.session = "CURRENT" end end
    Soon()
end)
ns.On("PLAYER_REGEN_ENABLED", function()
    if cvarPending then DM.ApplyBlizzard() end
    C_Timer.After(0.5, function() Learn() DM.Refresh() end)
end)
-- threat view: the game's threat events, and twice a second in combat
local function ThreatSoon()
    for _, w in ipairs(wins) do
        if w:IsShown() and w.cfg and (TYPE_BY_KEY[w.cfg.meterType] or TYPES[1]).threat then Soon() return end
    end
end
ns.On("UNIT_THREAT_LIST_UPDATE", ThreatSoon)
ns.On("UNIT_THREAT_SITUATION_UPDATE", ThreatSoon)
ns.On("PLAYER_TARGET_CHANGED", ThreatSoon)
ns.On("UNIT_TARGET", function(u) if u == "target" then ThreatSoon() end end)
local ticker
ns.On("PLAYER_REGEN_DISABLED", function()
    if ticker then ticker:Cancel() end
    ticker = C_Timer.NewTicker(0.5, ThreatSoon)
    if S().enabled then DM.Apply() end         -- threat windows back, full opacity
end)
ns.On("PLAYER_REGEN_ENABLED", function()
    if ticker then ticker:Cancel() ticker = nil end
    for _, w in ipairs(wins) do w.keepThreat = nil end
    if S().enabled then DM.Apply() end         -- threat windows away, dimmed
    ThreatSoon()
end)
ns.On("GROUP_ROSTER_UPDATE", function() RebuildRoster() DM.Apply() end)
ns.On("PLAYER_ENTERING_WORLD", function() RebuildRoster() Learn() DM.Apply() end)
ns.On("ZONE_CHANGED_NEW_AREA", function() DM.Apply() end)
ns.OnLogin(function() RebuildRoster() DM.Apply() end)
ns.OnRefresh(function() if HUFDB then DM.Apply() end end)

function DM.AddWindow()
    local c = S()
    if c.windowCount >= MAX_WINDOWS then return end
    c.windowCount = c.windowCount + 1
    DM.EnsureWindows()
    local w = c.windows[c.windowCount]
    w.keep = true
    DM.Apply()
    local nw = wins[c.windowCount]
    if nw and w.meterType == "Threat" then nw.keepThreat = true nw:Show() end
    if ns.RefreshConfig then ns.RefreshConfig() end
end

-- closes window i: its settings go, the ones after move up; the only
-- window left: asks, then turns the meter off (its settings stay)
function DM.CloseWindow(i)
    local c = S()
    i = i or 1
    if i < 1 or i > c.windowCount then return end
    if c.windowCount <= 1 then
        UI.Confirm("Turn the damage meter off? (Back on: settings > Damage meter, or /huf meter)", "Turn off", function()
            c.enabled = false
            DM.Apply()
            if ns.RefreshConfig then ns.RefreshConfig() end
        end, "Cancel")
        return
    end
    -- the closed window's breakdown and those after it (their settings move up)
    for j = i, #wins do
        local w = wins[j]
        if w.bd and w.bd.open then DM.UseWindow(w) DM.CloseBreakdown() end
    end
    table.remove(c.windows, i)
    c.windowCount = c.windowCount - 1
    for _, w in ipairs(wins) do w.keepThreat = nil end
    DM.Apply()
    if ns.RefreshConfig then ns.RefreshConfig() end
end

function DM.Toggle()
    S().enabled = not S().enabled
    DM.Apply()
    ns.Print("Damage meter %s.", S().enabled and "on" or "off")
end

-- debug report: what the meter hands out right now
function DM.Report(add)
    local c = S()
    add(("damage meter spec icons from the game: %d rows"):format(gameSpecIcons))
    if ns.Specs then pcall(ns.Specs.Report, add) end
    add(("damage meter: available=%s enabled=%s windows=%s blizzard cvar=%s saved=%s"):format(
        tostring(Available()), tostring(c.enabled), tostring(c.windowCount),
        tostring(GetCV("damageMeterEnabled")), tostring(HUFDB.damageMeterCVar and HUFDB.damageMeterCVar.old)))
    for i, w in ipairs(wins) do
        add(("  window %d: shown=%s type=%s session=%s"):format(i, tostring(w:IsShown()),
            tostring(w.cfg and w.cfg.meterType), tostring(w.cfg and w.cfg.session)))
    end
    win = wins[1]
    if not win or not win.cfg then return end
    local session = GetSession()
    local srcs = session and session.combatSources
    if type(srcs) ~= "table" then return end
    local function V(v) if IsSecret(v) then return "SECRET" end return tostring(v) end
    for i = 1, math.min(#srcs, 6) do
        local s = srcs[i]
        local shown, how = DM.RowName(s)
        add(("  %d: name=%s guid=%s class=%s spec=%s me=%s creature=%s total=%s ps=%s -> %s (%s)"):format(i,
            V(s.name), V(s.sourceGUID), V(s.classFilename), V(s.specIconID), V(s.isLocalPlayer),
            V(s.sourceCreatureID), V(s.totalAmount), V(s.amountPerSecond), IsSecret(shown) and "SECRET" or tostring(shown), how))
    end
end
