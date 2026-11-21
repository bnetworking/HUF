-- HUF: buff and debuff icon rows, for the unit frames and the nameplates.
--
-- 12.x: the game's own aura containers (Blizzard_AuraContainer) do the work
-- when the client has them. They read the auras in C, so they keep working
-- where an addon may not read auras itself (nameplates, party, combat). Each
-- row holds two groups with fixed filters ("all" and "mine"); the one not in
-- use is parked at 0 icons. Without containers a row falls back to a plain
-- C_UnitAuras scan, and every failure of that scan goes to the debug log.

local _, ns = ...
local A = {}
ns.Auras = A

local floor = math.floor

---------------------------------------------------------------------------
-- Does the client have aura containers?
---------------------------------------------------------------------------
local engine, spare
local function Engine()
    if engine ~= nil then return engine end
    engine = false
    if C_AddOns and C_AddOns.LoadAddOn then
        local loaded = C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer")
        if not loaded then pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer") end
    end
    local ok, c = pcall(CreateFrame, "AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
    if ok and c and c.AddAuraGroup and c.SetUnit then
        engine = true
        c:Hide()
        spare = c
    end
    ns.Log("auras", "game aura containers: %s%s", engine and "yes" or "no (plain scan)",
        ok and "" or (" - " .. tostring(c)))
    return engine
end
A.Engine = Engine

-- are auras hidden from addons right now?
function A.Restricted()
    if C_Secrets and C_Secrets.ShouldAurasBeSecret then
        local ok, r = pcall(C_Secrets.ShouldAurasBeSecret)
        if ok and ns.Bool(r) then return true end
    end
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return true end
    return not pcall(C_UnitAuras.GetAuraDataByIndex, "player", 1, "HELPFUL")
end

local function Filter(kind, mine) return mine and (kind .. "|PLAYER") or kind end
A.Filter = Filter

-- What a row shows: the game's own aura filters, so they also work while
-- the auras are hidden from addons. A row has up to three groups that fill
-- one after another: "lead" (crowd control first), "main" and "extra" (a
-- second filter, made not to repeat the first).
--   cfg.filter: debuffs ALL | RAID | DISPELLABLE | CC
--               buffs   ALL | RAID | DEFENSIVE | CANCELABLE
--   cfg.ccFirst (debuffs): crowd control leads the row
--   cfg.hideSated (debuffs): no Sated / Exhaustion and the like
A.SLOTS = { "lead", "main", "extra" }
-- the game's own tokens: "dispellable by anyone" (purges, enrages; whatever
-- your class) and "important". Checked by the game, so they also work on
-- enemies whose buffs addons may not read.
local AF = AuraUtil and AuraUtil.AuraFilters
local DISPELLABLE = (AF and AF.Dispellable) or "DISPELLABLE"
local IMPORTANT = (AF and AF.Important) or "IMPORTANT"
local function SortKey(t) if t:sub(1, 1) == "!" then return t:sub(2) .. "!" end return t end
-- one spelling per filter (the game reads each spelling once per unit)
local function Make(base, mine, ...)
    local rest = {}
    for i = 1, select("#", ...) do
        local t = select(i, ...)
        if t then rest[#rest + 1] = t end
    end
    if mine then rest[#rest + 1] = "PLAYER" end
    table.sort(rest, function(a, b) return SortKey(a) < SortKey(b) end)
    if #rest == 0 then return base end
    return base .. "|" .. table.concat(rest, "|")
end
function A.Groups(cfg)
    local base, mine, f = cfg.kind, cfg.mine and true or false, cfg.filter or "ALL"
    local g = {}
    if base == "HARMFUL" then
        local lead = cfg.ccFirst and not mine and f ~= "CC"
        local nc = lead and "!CROWD_CONTROL" or nil
        if lead then g.lead = Make(base, false, "CROWD_CONTROL") end
        if f == "RAID" then
            g.main = Make(base, mine, "RAID", nc)
            g.extra = Make(base, mine, "RAID_IN_COMBAT", "!RAID", nc)
        elseif f == "DISPELLABLE" then
            g.main = Make(base, mine, "RAID_PLAYER_DISPELLABLE", nc)
        elseif f == "CC" then
            g.main = Make(base, mine, "CROWD_CONTROL")
        else
            g.main = Make(base, mine, nc)
        end
    else
        if f == "RAID" then
            g.main = Make(base, mine, "RAID")
        elseif f == "DEFENSIVE" then
            g.main = Make(base, mine, "BIG_DEFENSIVE")
            g.extra = Make(base, mine, "EXTERNAL_DEFENSIVE", "!BIG_DEFENSIVE")
        elseif f == "CANCELABLE" then
            g.main = Make(base, mine, "CANCELABLE")
        elseif f == "PURGE" then
            -- enemies: the ones you (or anyone) can dispel or steal
            g.main = Make(base, mine, DISPELLABLE)
        elseif f == "IMPORTANT_PURGE" then
            g.main = Make(base, mine, DISPELLABLE)
            g.extra = Make(base, mine, IMPORTANT, "!" .. DISPELLABLE)
        else
            g.main = Make(base, mine)
        end
    end
    return g
end

-- Sated, Exhaustion, Temporal Displacement, Insanity, Fatigued and kin
local SATED = { [57723] = true, [57724] = true, [80354] = true, [95809] = true,
                [160455] = true, [264689] = true, [390435] = true }
local SATED_CAND = { excludeSpellIDs = SATED }

---------------------------------------------------------------------------
-- "Ones my group can dispel" (filter TEAM): the debuff types anyone in the
-- group can remove - with MMT that is your whole team, not just the
-- character you play. Read from each member's class, and for the types
-- only healers remove (magic), from the role they have. The game then shows
-- only debuffs of those types (its own type filter: works in combat too).
---------------------------------------------------------------------------
local CLASS_DISPELS = {
    PRIEST  = { all = { "Disease" }, healer = { "Magic" } },
    PALADIN = { all = { "Poison", "Disease" }, healer = { "Magic" } },
    SHAMAN  = { all = { "Curse" }, healer = { "Magic" } },
    DRUID   = { all = { "Curse", "Poison" }, healer = { "Magic" } },
    MONK    = { all = { "Poison", "Disease" }, healer = { "Magic" } },
    EVOKER  = { all = { "Poison" }, healer = { "Magic" } },
    MAGE    = { all = { "Curse" } },
}
A.CLASS_DISPELS = CLASS_DISPELS
local TYPE_ORDER = { "Magic", "Curse", "Disease", "Poison", "Bleed" }
local teamTypes, teamKey = {}, ""
local teamCand, teamCandSated

local function Plain(v) if v == nil or ns.IsSecret(v) then return nil end return v end
-- the role of a member's spec, as far as the game knows it (others: once
-- inspected). Their group role is no help: a group made by hand, like an
-- MMT team, often has everyone as damage, healers too.
local function SpecRole(unit)
    if unit == "player" then
        if not (GetSpecialization and GetSpecializationRole) then return nil end
        local okS, spec = pcall(GetSpecialization)
        spec = okS and Plain(spec) or nil
        if not spec then return nil end
        local okR, r = pcall(GetSpecializationRole, spec)
        return okR and Plain(r) or nil
    end
    if not (GetInspectSpecialization and GetSpecializationRoleByID) then return nil end
    local okS, id = pcall(GetInspectSpecialization, unit)
    id = okS and Plain(id) or nil
    if not id or id == 0 then return nil end
    local okR, r = pcall(GetSpecializationRoleByID, id)
    return okR and Plain(r) or nil
end
local unknownSpec = {}      -- members whose spec isn't known yet
local function UnitHeals(unit)
    local role = SpecRole(unit)
    if role then return role == "HEALER" end
    local ok, r = pcall(UnitGroupRolesAssigned, unit)
    if ok and Plain(r) == "HEALER" then return true end
    -- spec not known yet: they might heal, so count it, and ask the game
    if unit ~= "player" then unknownSpec[#unknownSpec + 1] = unit end
    return true
end

-- inspect one member whose spec isn't known (the game answers with
-- INSPECT_READY, which reads the group again); out of combat only, never
-- while you have the inspect window open, a few tries per member
local inspectTries, inspectBusy = {}, false
local function InspectNext()
    if inspectBusy or #unknownSpec == 0 or not NotifyInspect then return end
    if InCombatLockdown() or (InspectFrame and InspectFrame:IsShown()) then return end
    for _, unit in ipairs(unknownSpec) do
        local okG, guid = pcall(UnitGUID, unit)
        guid = okG and Plain(guid) or nil
        local okC, can = pcall(CanInspect, unit)
        if guid and okC and Plain(can) and (inspectTries[guid] or 0) < 5 then
            inspectTries[guid] = (inspectTries[guid] or 0) + 1
            inspectBusy = true
            pcall(NotifyInspect, unit)
            C_Timer.After(3, function() inspectBusy = false end)
            return
        end
    end
end

local function GroupUnits()
    local list = { "player" }
    local raid = IsInRaid and IsInRaid()
    local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    if raid then
        for i = 1, n do list[#list + 1] = "raid" .. i end
    else
        for i = 1, math.max(0, n - 1) do list[#list + 1] = "party" .. i end
    end
    return list
end

-- works out the types again; true when they changed
local function ReadTeam()
    local set = {}
    wipe(unknownSpec)
    for _, unit in ipairs(GroupUnits()) do
        local okE, exists = pcall(UnitExists, unit)
        if okE and Plain(exists) then
            local okC, _, class = pcall(UnitClass, unit)
            class = okC and Plain(class) or nil
            local d = class and CLASS_DISPELS[class]
            if d then
                for _, t in ipairs(d.all or {}) do set[t] = true end
                if d.healer and UnitHeals(unit) then
                    for _, t in ipairs(d.healer) do set[t] = true end
                end
            end
        end
    end
    local key = {}
    for _, t in ipairs(TYPE_ORDER) do if set[t] then key[#key + 1] = t end end
    key = table.concat(key, ",")
    if key == teamKey and teamCand then return false end
    teamKey, teamTypes = key, set
    teamCand = { includeDispelTypes = set }
    teamCandSated = { includeDispelTypes = set, excludeSpellIDs = SATED }
    return true
end
function A.TeamTypes()
    if not teamCand then ReadTeam() end
    return teamKey
end

-- the candidate filter of a group slot ("lead": crowd control keeps every type)
local function Cand(cfg, key)
    if cfg.kind ~= "HARMFUL" then return nil end
    if cfg.filter == "TEAM" and key ~= "lead" then
        if not teamCand then ReadTeam() end
        return cfg.hideSated and teamCandSated or teamCand
    end
    if cfg.hideSated then return SATED_CAND end
    return nil
end
-- the group can dispel nothing: the TEAM row shows nothing
local function TeamEmpty(cfg)
    if cfg.kind ~= "HARMFUL" or cfg.filter ~= "TEAM" then return false end
    if not teamCand then ReadTeam() end
    return teamKey == ""
end

-- a debuff's border in its type's colour (magic blue, curse purple, ...)
local function WantDispel(cfg) return cfg.dispelBorder and true or false end
local function BorderSize(cfg) return math.max(0, cfg.borderSize or 1) end
local DISPEL_COLORS = {
    Magic = { 0.2, 0.6, 1 }, Curse = { 0.6, 0, 1 }, Disease = { 0.6, 0.4, 0 },
    Poison = { 0, 0.6, 0 }, Bleed = { 0.8, 0, 0 },
}
local dispelStyle
local function DispelOpts()
    if dispelStyle == nil then
        local E = Enum and Enum.CustomAuraButtonDispelTypeTextureStyle
        local s = E and E.PreserveAsset
        if s == nil then
            local L = (Enum and Enum.CustomAuraButtonBorderStyle) or _G.AuraButtonBorderStyle
            s = L and L.Color
        end
        dispelStyle = s ~= nil and { style = s, showWhenHarmful = true, showWhenHelpful = true } or false
    end
    return dispelStyle or nil
end

local function Flow(token)
    local FD = AnchorUtil and AnchorUtil.FlowDirection
    if not FD then return nil end
    if token == "LEFT" then return FD.Left end
    if token == "UP" then return FD.Up end
    if token == "DOWN" then return FD.Down end
    return FD.Right
end

-- the layout setters were renamed once; old names as fallback
local function Call(c, new, old, ...)
    local fn = c[new] or (old and c[old])
    if fn then return pcall(fn, c, ...) end
    return false, "no " .. new
end

---------------------------------------------------------------------------
-- A row
--   cfg: enabled, kind ("HARMFUL" / "HELPFUL"), mine, size, gap, perRow,
--        rows, point {point, rel, relPoint, x, y}, anchor (= point[1]),
--        growH ("LEFT"/"RIGHT"), growV ("UP"/"DOWN"), countSize, timer,
--        timerText (time left as numbers), timerSize (0: from the icon size)
---------------------------------------------------------------------------
local Row = {}
Row.__index = Row
local rows = {}

function A.NewRow(parent, label, plate)
    local r = setmetatable({
        parent = parent, label = label, plate = plate,
        buttons = {}, bdata = {}, icons = {}, errors = 0,
    }, Row)
    r.holder = CreateFrame("Frame", nil, parent)
    r.holder:SetSize(1, 1)
    r.holder:EnableMouse(false)
    r.ev = CreateFrame("Frame")
    r.ev:SetScript("OnEvent", function() r:Scan() end)
    rows[#rows + 1] = r
    return r
end

function Row:Fail(what, err)
    self.errors = self.errors + 1
    if self.errors <= 3 then
        ns.Log("auras", "%s: %s failed: %s", self.label, what, tostring(err))
    end
end

-- time left as numbers: the cooldown's own countdown (the game counts it,
-- so it also works while the aura's times are secret)
local function TimerSize(cfg)
    local s = cfg.timerSize or 0
    if s > 0 then return s end
    return math.max(7, math.floor((cfg.size or 20) * 0.5 + 0.5))
end
local function StyleTimer(cd, cfg)
    cd:SetHideCountdownNumbers(not cfg.timerText)
    if cd.SetCountdownAbbrevThreshold then pcall(cd.SetCountdownAbbrevThreshold, cd, 100) end
    local fs = cd.GetCountdownFontString and cd:GetCountdownFontString()
    if fs then
        ns.ApplyFont(fs, "GLOBAL", TimerSize(cfg), "OUTLINE")
        fs:ClearAllPoints()
        fs:SetPoint("CENTER", 0, 0)
    end
end

-- icon look shared by engine buttons and scan icons
local function Dress(b, cfg, top)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 1)
    -- the debuff type's colour over the black edge (the game shows and tints it)
    local ring = b:CreateTexture(nil, "BORDER")
    ring:SetAllPoints()
    ring:SetColorTexture(1, 1, 1, 1)
    ring:Hide()
    local icon = b:CreateTexture(nil, "ARTWORK")
    local bs = BorderSize(cfg)
    icon:SetPoint("TOPLEFT", bs, -bs)
    icon:SetPoint("BOTTOMRIGHT", -bs, bs)
    icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    local cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    cd:SetAllPoints(icon)
    cd:SetDrawEdge(false)
    cd:SetReverse(true)
    cd:SetDrawSwipe(cfg.timer ~= false)
    StyleTimer(cd, cfg)
    local over = CreateFrame("Frame", nil, b)
    over:SetAllPoints()
    over:SetFrameLevel(cd:GetFrameLevel() + 2)
    over:EnableMouse(false)
    local count = over:CreateFontString(nil, "OVERLAY")
    ns.ApplyFont(count, "GLOBAL", cfg.countSize or 9, "OUTLINE")   -- a font before any text
    count:SetPoint("BOTTOMRIGHT", 1, 0)
    count:SetJustifyH("RIGHT")
    return { icon = icon, cd = cd, count = count, ring = ring, border = bs,
             timerText = cfg.timerText, timerSize = TimerSize(cfg) }
end

local function Inset(d, bs)
    d.icon:ClearAllPoints()
    d.icon:SetPoint("TOPLEFT", bs, -bs)
    d.icon:SetPoint("BOTTOMRIGHT", -bs, bs)
end

-- registers (or drops) the ring with the game's button; false: denied now
local function SetDispel(b, d, on)
    if d.dispelWant == on then return true end
    local add = b.AddDispelTypeTexture or b.SetAuraBorder
    local clear = b.ClearDispelTypeTextures or b.ClearAuraBorder
    if d.dispelReg then
        if not (clear and pcall(clear, b)) then return false end
        d.dispelReg = nil
        d.ring:Hide()
    end
    local opts = DispelOpts()
    if on and add and opts then
        if not pcall(add, b, d.ring, opts) then
            if clear then pcall(clear, b) end
            d.ring:Hide()
            return false
        end
        d.dispelReg = true
    end
    d.dispelWant = on
    return true
end

---------------------------------------------------------------------------
-- Engine rows
---------------------------------------------------------------------------
local function GroupLayout(cfg)
    return { elementWidth = cfg.size, elementHeight = cfg.size,
             elementSpacing = cfg.gap, lineSpacing = cfg.gap }
end

function Row:InitButton(b)
    local cfg = self.cfg
    -- everything is made and given a font first: registering runs the
    -- button's own update, which writes into these right away
    local d = Dress(b, cfg)
    b:SetSize(cfg.size, cfg.size)
    pcall(b.SetMouseClickEnabled, b, false)
    if self.plate then pcall(b.EnableMouse, b, false) end
    b:SetIcon(d.icon)
    b:SetDurationCooldown(d.cd)
    b:SetApplicationCount(d.count, {})
    d.size, d.countSize = cfg.size, cfg.countSize
    if not SetDispel(b, d, WantDispel(cfg)) then self.pendingResize = true end
    self.bdata[b] = d
    self.buttons[#self.buttons + 1] = b
end

function Row:BuildEngine()
    local c = spare
    spare = nil
    if c then
        c:SetParent(self.parent)
    else
        c = CreateFrame("AuraContainer", nil, self.parent, "CustomAuraContainerTemplate")
    end
    c:ClearAllPoints()
    c:SetPoint("CENTER", self.parent, "CENTER")
    c:SetSize(1, 1)
    local cfg = self.cfg
    local cap = cfg.perRow * cfg.rows
    self.c = c
    self.kind = cfg.kind
    local init = function(b)
        local ok, err = pcall(self.InitButton, self, b)
        if not ok then self:Fail("icon setup", err) end
    end
    -- debuffs: lead (crowd control), main, extra; buffs: main, extra. The
    -- slots stay; their filters change with the settings.
    local g = A.Groups(cfg)
    self.slots = cfg.kind == "HARMFUL" and { "lead", "main", "extra" } or { "main", "extra" }
    self.filters, self.cands = {}, {}
    for _, key in ipairs(self.slots) do
        local filter = g[key] or (key == "lead" and Make(cfg.kind, false, "CROWD_CONTROL")) or g.main
        local cand = Cand(cfg, key)
        c:AddAuraGroup(key, filter, {
            maxFrameCount = cap,
            candidateFilters = cand,
            initializeFrame = init,
            layout = GroupLayout(cfg),
        })
        self.filters[key], self.cands[key] = filter, cand
    end
    if self.level then pcall(c.SetFrameLevel, c, self.level) end
    ns.Log("auras", "%s: game container ready (%s)", self.label, cfg.kind)
end

local function SetCap(c, key, cap)
    if c.SetAuraGroupEnabled then
        if cap > 0 then pcall(c.SetAuraGroupEnabled, c, key, true) end
        pcall(c.SetAuraGroupMaxFrameCount, c, key, cap)
        if cap <= 0 then pcall(c.SetAuraGroupEnabled, c, key, false) end
    else
        pcall(c.SetAuraGroupMaxFrameCount, c, key, cap)
    end
end

-- icon size and stack font (denied while auras are hidden: tried again later)
function Row:Resize()
    local cfg = self.cfg
    self.pendingResize = nil
    for _, b in ipairs(self.buttons) do
        local d = self.bdata[b]
        if d.size ~= cfg.size then
            if pcall(b.SetSize, b, cfg.size, cfg.size) then d.size = cfg.size
            else self.pendingResize = true end
        end
        if d.countSize ~= cfg.countSize then
            if pcall(ns.ApplyFont, d.count, "GLOBAL", cfg.countSize, "OUTLINE") then d.countSize = cfg.countSize
            else self.pendingResize = true end
        end
        if d.timer ~= cfg.timer then
            if pcall(d.cd.SetDrawSwipe, d.cd, cfg.timer ~= false) then d.timer = cfg.timer
            else self.pendingResize = true end
        end
        if d.timerText ~= cfg.timerText or d.timerSize ~= TimerSize(cfg) then
            if pcall(StyleTimer, d.cd, cfg) then d.timerText, d.timerSize = cfg.timerText, TimerSize(cfg)
            else self.pendingResize = true end
        end
        if d.border ~= BorderSize(cfg) then
            if pcall(Inset, d, BorderSize(cfg)) then d.border = BorderSize(cfg)
            else self.pendingResize = true end
        end
        if not SetDispel(b, d, WantDispel(cfg)) then self.pendingResize = true end
    end
end

function Row:ApplyEngine()
    local c, cfg = self.c, self.cfg
    c:ClearAllPoints()
    c:SetPoint(cfg.point[1], cfg.point[2], cfg.point[3], cfg.point[4], cfg.point[5])
    Call(c, "SetFlowLayoutAnchorPoint", "SetAuraLayoutAnchorPoint", cfg.anchor)
    Call(c, "SetFlowLayoutGrowthDirection", "SetAuraLayoutGrowthDirection", Flow(cfg.growH), Flow(cfg.growV))
    -- room for perRow icons, never perRow + 1 (works whether or not the
    -- engine counts the space after the last icon)
    Call(c, "SetFlowLayoutMaximumLineSize", "SetAuraLayoutRowWidth", cfg.perRow * (cfg.size + cfg.gap) + 0.4)
    local cap = cfg.perRow * cfg.rows
    local g, empty = A.Groups(cfg), TeamEmpty(cfg)
    for _, key in ipairs(self.slots) do
        local cand = Cand(cfg, key)
        pcall(c.SetAuraGroupLayout, c, key, GroupLayout(cfg))
        local filter, show = g[key], g[key] ~= nil
        if empty and key ~= "lead" then show = false end
        if filter and filter ~= self.filters[key] then
            local ok, err = Call(c, "SetAuraGroupFilterString", nil, key, filter)
            if ok then self.filters[key] = filter
            else
                self:Fail("filter " .. filter .. " (after /reload)", err)
                if key ~= "main" then show = false end
            end
        end
        if self.cands[key] ~= cand then
            local ok = pcall(c.SetAuraGroupCandidateFilters, c, key, cand)
            if not ok and cand == nil then ok = pcall(c.SetAuraGroupCandidateFilters, c, key, {}) end
            if ok then self.cands[key] = cand end
        end
        SetCap(c, key, show and cap or 0)
    end
    self:Resize()
    c:Show()
    self:BindEngine()
end

function Row:BindEngine()
    local c = self.c
    local unit = (self.cfg and self.cfg.enabled) and self.unit or nil
    if unit then
        if self.bound ~= unit then
            local ok, err = pcall(c.SetUnit, c, unit)
            if not ok then self:Fail("SetUnit " .. unit, err) end
            self.bound = unit
        end
        pcall(c.UpdateAllAuras, c)
    elseif self.bound then
        if not pcall(c.SetUnit, c, "none") then pcall(c.SetUnit, c, nil) end
        self.bound = nil
    end
end

---------------------------------------------------------------------------
-- Scan rows (no containers, or a container couldn't be made)
---------------------------------------------------------------------------
function Row:Icon(i)
    local b = self.icons[i]
    if not b then
        b = CreateFrame("Frame", nil, self.holder)
        b.d = Dress(b, self.cfg)
        b:EnableMouse(false)
        self.icons[i] = b
    end
    local cfg = self.cfg
    b:SetSize(cfg.size, cfg.size)
    if b.d.border ~= BorderSize(cfg) then
        Inset(b.d, BorderSize(cfg))
        b.d.border = BorderSize(cfg)
    end
    ns.ApplyFont(b.d.count, "GLOBAL", cfg.countSize or 9, "OUTLINE")
    b.d.cd:SetDrawSwipe(cfg.timer ~= false)
    StyleTimer(b.d.cd, cfg)
    return b
end

function Row:Place(b, n)
    local cfg = self.cfg
    local i = n - 1
    local col, line = i % cfg.perRow, floor(i / cfg.perRow)
    local step = cfg.size + cfg.gap
    local dx = col * step * (cfg.growH == "LEFT" and -1 or 1)
    local dy = line * step * (cfg.growV == "DOWN" and -1 or 1)
    b:ClearAllPoints()
    b:SetPoint(cfg.anchor, self.holder, cfg.anchor, dx, dy)
end

function Row:LayoutHolder()
    local cfg = self.cfg
    local h = self.holder
    h:ClearAllPoints()
    h:SetPoint(cfg.point[1], cfg.point[2], cfg.point[3], cfg.point[4], cfg.point[5])
    h:SetSize(math.max(1, cfg.perRow * (cfg.size + cfg.gap)), math.max(1, cfg.rows * (cfg.size + cfg.gap)))
    if cfg.level then self:SetLevel(cfg.level) end
end

-- the holder as big as the n icons it shows: a centred row stays centred
function Row:FitHolder(n)
    local cfg = self.cfg
    if n < 1 then return end
    local cols = math.min(n, cfg.perRow)
    local lines = math.ceil(n / cfg.perRow)
    self.holder:SetSize(cols * cfg.size + (cols - 1) * cfg.gap, lines * cfg.size + (lines - 1) * cfg.gap)
end

-- above the frame's bars and texts: icons inside the frame stay visible
function Row:SetLevel(level)
    self.level = level
    self.holder:SetFrameLevel(level)
    if self.c then pcall(self.c.SetFrameLevel, self.c, level) end
end

function Row:Scan()
    local cfg = self.cfg
    local n = 0
    local unit = self.unit
    if cfg and cfg.enabled and unit and not self.c and C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
        and ns.Bool(UnitExists(unit)) then
        local g = A.Groups(cfg)
        local max = cfg.perRow * cfg.rows
        local seen = {}
        local sated = cfg.kind == "HARMFUL" and cfg.hideSated
        local team = cfg.kind == "HARMFUL" and cfg.filter == "TEAM"
        if team and not teamCand then ReadTeam() end
        local ring = WantDispel(cfg)
        for _, key in ipairs(A.SLOTS) do
          local filter = g[key]
          for i = 1, filter and 40 or 0 do
            if n >= max then break end
            local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
            if not ok then self:Fail("reading " .. unit .. " " .. filter, a) break end
            if type(a) ~= "table" then break end
            local id, sid = a.auraInstanceID, a.spellId
            if ns.IsSecret(id) then id = nil end
            local skip = (id and seen[id]) or (sated and not ns.IsSecret(sid) and SATED[sid])
            if not skip and team and key ~= "lead" then
                local dn = a.dispelName
                if ns.IsSecret(dn) then dn = nil end
                skip = not (dn and teamTypes[dn])
            end
            if not skip then
            if id then seen[id] = true end
            n = n + 1
            local b = self:Icon(n)
            self:Place(b, n)
            local dn = ring and a.dispelName
            local col = dn and not ns.IsSecret(dn) and DISPEL_COLORS[dn]
            if col then
                b.d.ring:SetColorTexture(col[1], col[2], col[3], 1)
                b.d.ring:Show()
            else
                b.d.ring:Hide()
            end
            pcall(b.d.icon.SetTexture, b.d.icon, a.icon)
            local cnt = a.applications
            if ns.IsSecret(cnt) or type(cnt) ~= "number" or cnt < 2 then b.d.count:SetText("")
            else b.d.count:SetText(cnt) end
            local dur, exp = a.duration, a.expirationTime
            if not ns.IsSecret(dur) and not ns.IsSecret(exp) and type(dur) == "number"
                and type(exp) == "number" and dur > 0 then
                b.d.cd:SetCooldown(exp - dur, dur)
                b.d.cd:Show()
            else
                b.d.cd:Hide()
            end
            b:Show()
            end
          end
        end
    end
    self:FitHolder(n)
    for i = n + 1, #self.icons do self.icons[i]:Hide() end
end

---------------------------------------------------------------------------
-- Public row methods
---------------------------------------------------------------------------
function Row:Configure(cfg)
    self.cfg = cfg
    self.preview = nil
    self:LayoutHolder()
    if not cfg.enabled then
        self:Disable()
        return
    end
    if not self.c and not self.noEngine and Engine() then
        local ok, err = pcall(self.BuildEngine, self)
        if not ok then
            self:Fail("game container", err)
            if self.c then self.c:Hide() end
            self.c = nil
            self.noEngine = true       -- this row scans from now on
        end
    end
    if self.c then
        if self.level then pcall(self.c.SetFrameLevel, self.c, self.level) end
        for _, b in ipairs(self.icons) do b:Hide() end
        self.ev:UnregisterAllEvents()
        local ok, err = pcall(self.ApplyEngine, self)
        if not ok then self:Fail("layout", err) end
    else
        self:WatchScan()
        self:Scan()
    end
end

function Row:WatchScan()
    self.ev:UnregisterAllEvents()
    if self.unit and self.cfg and self.cfg.enabled and not self.c then
        pcall(self.ev.RegisterUnitEvent, self.ev, "UNIT_AURA", self.unit)
    end
end

function Row:Disable()
    self.ev:UnregisterAllEvents()
    for _, b in ipairs(self.icons) do b:Hide() end
    if self.c then
        self.c:Hide()
        self:BindEngine()
    end
end

function Row:SetUnit(unit)
    if ns.IsSecret(unit) then unit = nil end
    self.unit = unit
    if not self.cfg then return end
    if self.c then self:BindEngine()
    else
        self:WatchScan()
        self:Scan()
    end
end

-- the unit token now means someone else (target swapped, polled units)
function Row:Refresh()
    if not (self.cfg and self.cfg.enabled) or self.preview then return end
    if self.c then
        if self.bound then pcall(self.c.UpdateAllAuras, self.c) end
    else
        self:Scan()
    end
end

-- unlock mode: sample icons, nothing read from the game
local SAMPLE = { 136118, 135812, 136207, 132090, 136197, 135848, 132316, 136139 }
local SAMPLE_TYPES = { "Magic", "Curse", "None", "Poison", "Disease" }
function Row:Preview(cfg, n)
    self.cfg = cfg
    self.preview = true
    self:LayoutHolder()
    self.ev:UnregisterAllEvents()
    if self.c then self.c:Hide() end
    n = cfg.enabled and math.min(n or 3, cfg.perRow * cfg.rows) or 0
    for i = 1, n do
        local b = self:Icon(i)
        self:Place(b, i)
        b.d.icon:SetTexture(SAMPLE[(i - 1) % #SAMPLE + 1])
        b.d.count:SetText(i == 2 and "3" or "")
        b.d.cd:Hide()
        local col = WantDispel(cfg) and DISPEL_COLORS[SAMPLE_TYPES[(i - 1) % #SAMPLE_TYPES + 1]]
        if col then
            b.d.ring:SetColorTexture(col[1], col[2], col[3], 1)
            b.d.ring:Show()
        else
            b.d.ring:Hide()
        end
        b:Show()
    end
    self:FitHolder(n)
    for i = n + 1, #self.icons do self.icons[i]:Hide() end
end

function Row:Info()
    local cfg = self.cfg
    if not cfg then return "not set up" end
    if not cfg.enabled then return "off" end
    if self.preview then return "preview" end
    if self.c then
        return ("game container, unit %s, %d icons made%s"):format(tostring(self.bound), #self.buttons,
            self.pendingResize and ", resize pending" or "")
    end
    local shown = 0
    for _, b in ipairs(self.icons) do if b:IsShown() then shown = shown + 1 end end
    return ("scan, unit %s, %d shown, %d errors"):format(tostring(self.unit), shown, self.errors)
end

-- sizes the game refused while auras were hidden: once it allows them again
local function RetryResize()
    for _, r in ipairs(rows) do
        if r.pendingResize and r.c then pcall(r.Resize, r) end
    end
end
ns.On("PLAYER_REGEN_ENABLED", RetryResize)

-- the group changed: rows on "Ones my group can dispel" take the new types
local retrying = false
local function TeamChanged()
    local changed = ReadTeam()
    InspectNext()
    -- members out of range: try again in a while
    if #unknownSpec > 0 and not retrying then
        retrying = true
        C_Timer.After(10, function() retrying = false TeamChanged() end)
    end
    if not changed then return end
    ns.Log("auras", "group can dispel: %s", teamKey ~= "" and teamKey or "nothing")
    for _, r in ipairs(rows) do
        local cfg = r.cfg
        if cfg and cfg.enabled and cfg.filter == "TEAM" and cfg.kind == "HARMFUL" and not r.preview then
            if r.c then
                local ok, err = pcall(r.ApplyEngine, r)
                if not ok then r:Fail("group dispels", err) end
            else
                r:Scan()
            end
        end
    end
end
for _, e in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED", "PLAYER_SPECIALIZATION_CHANGED",
                     "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED" }) do
    pcall(ns.On, e, TeamChanged)
end
pcall(ns.On, "INSPECT_READY", function() inspectBusy = false TeamChanged() end)
ns.On("ZONE_CHANGED_NEW_AREA", RetryResize)

---------------------------------------------------------------------------
-- Diagnostics for the debug report and the recorder
---------------------------------------------------------------------------
local PROBE_FILTERS = { "HARMFUL", "HARMFUL|PLAYER", "HELPFUL", "HELPFUL|PLAYER" }
function A.ProbeUnit(unit)
    local out = {}
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return "no C_UnitAuras" end
    for _, filter in ipairs(PROBE_FILTERS) do
        local names, err = {}, nil
        for i = 1, 8 do
            local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
            if not ok then err = tostring(a) break end
            if type(a) ~= "table" then break end
            local nm = a.name
            names[#names + 1] = ns.IsSecret(nm) and "SECRET" or tostring(nm)
        end
        out[#out + 1] = filter .. "=" .. (err and ("ERR " .. err) or ("[" .. table.concat(names, ", ") .. "]"))
    end
    return table.concat(out, "  ")
end

function A.Report()
    local lines = { ("containers: %s, auras hidden now: %s"):format(tostring(Engine()), tostring(A.Restricted())) }
    for _, r in ipairs(rows) do
        if r.cfg and r.cfg.enabled and r.unit and not r.preview then
            lines[#lines + 1] = "  " .. r.label .. ": " .. r:Info()
        end
    end
    return lines
end
