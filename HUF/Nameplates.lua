-- HUF: nameplates. HUF draws its own slim plate on each of Blizzard's
-- nameplates (Blizzard's plate stays for clicks and stacking, made
-- invisible):
--   * what to show: name only, name + bar, or bar only (enemies; friendly
--     units the same or their own choice)
--   * the level ("55E") before the name, in difficulty colour
--   * a thin cast bar with spell name and icon
--   * small buff and debuff icons
-- Names follow the privacy setting (and MMT's for your team). Health is a
-- secret value on this client: it only goes to the bar.
-- Plates the game forbids addons to touch (friendly plates in some
-- instances) stay Blizzard's.

local _, ns = ...
local IsSecret, Bool = ns.IsSecret, ns.Bool
local function Plain(v) if v == nil or IsSecret(v) then return nil end return v end
local Frame = ns.Frame

local NP = {}
ns.Nameplates = NP
NP.plates = {}           -- unit token -> our plate
local pool = {}

local function S() return ns.db.nameplates end

---------------------------------------------------------------------------
-- Blizzard's plate: invisible while ours is on it
---------------------------------------------------------------------------
local owned = setmetatable({}, { __mode = "k" })   -- Blizzard UnitFrame -> true while ours shows
local hooked = setmetatable({}, { __mode = "k" })

local function HideBlizzard(nameplate)
    local uf = nameplate.UnitFrame
    if not uf or uf:IsForbidden() then return end
    owned[uf] = true
    uf:SetAlpha(0)
    local cb = uf.castBar or (uf.CastBarsContainer and uf.CastBarsContainer.castBar)
    if cb and not cb:IsForbidden() then cb:SetAlpha(0) end
    if not hooked[uf] then
        hooked[uf] = true
        local busy = false
        -- Blizzard sets the alpha again on updates: back to 0 while ours shows
        hooksecurefunc(uf, "SetAlpha", function(self)
            if busy or not owned[self] then return end
            busy = true
            self:SetAlpha(0)
            busy = false
        end)
    end
end

local function RestoreBlizzard(nameplate)
    local uf = nameplate and nameplate.UnitFrame
    if not uf or uf:IsForbidden() then return end
    owned[uf] = nil
    uf:SetAlpha(1)
    local cb = uf.castBar or (uf.CastBarsContainer and uf.CastBarsContainer.castBar)
    if cb and not cb:IsForbidden() then cb:SetAlpha(1) end
end

---------------------------------------------------------------------------
-- Building one plate
---------------------------------------------------------------------------
local function NewFont(parent, size)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ns.ApplyFont(fs, "GLOBAL", size or 9, "OUTLINE")
    fs:SetWordWrap(false)
    return fs
end

local plateCount = 0
local function Build()
    local p = CreateFrame("Frame")
    p:EnableMouse(false)
    p.health = CreateFrame("StatusBar", nil, p)
    p.health:SetAllPoints()
    p.health.bg = p.health:CreateTexture(nil, "BACKGROUND")
    p.health.bg:SetAllPoints()
    p.health.edge = CreateFrame("Frame", nil, p)
    p.health.border = Frame.MakeBorder(p.health.edge)
    p.text = CreateFrame("Frame", nil, p)
    p.text:SetAllPoints()
    p.name = NewFont(p.text, 9)
    p.hp = NewFont(p.text, 7)
    p.quest = NewFont(p.text, 9)
    p.quest:SetJustifyH("RIGHT")
    p.elite = CreateFrame("Frame", nil, p.text)
    p.elite.fill = p.elite:CreateTexture(nil, "OVERLAY", nil, 1)
    p.elite.fill:SetAllPoints()
    p.elite.fill:SetTexture(ns.MEDIA .. "Icons\\Star")
    p.elite.ring = p.elite:CreateTexture(nil, "OVERLAY", nil, 2)
    p.elite.ring:SetAllPoints()
    p.elite.ring:SetTexture(ns.MEDIA .. "Icons\\StarRing")

    -- threat: percent text and a glow round the bar
    p.threat = NewFont(p.text, 9)
    p.threat:Hide()
    p.glow = CreateFrame("Frame", nil, p)
    p.glow:SetFrameLevel(math.max(0, p.health:GetFrameLevel() - 1))
    p.glow.edges = {}
    for i = 1, 4 do p.glow.edges[i] = p.glow:CreateTexture(nil, "BACKGROUND") end
    p.glow:Hide()

    p.cast = CreateFrame("StatusBar", nil, p)
    p.cast.bg = p.cast:CreateTexture(nil, "BACKGROUND")
    p.cast.bg:SetAllPoints()
    p.cast.bg:SetColorTexture(0.05, 0.05, 0.06, 0.9)
    p.cast.edge = CreateFrame("Frame", nil, p.cast)
    p.cast.edge:SetAllPoints()
    p.cast.border = Frame.MakeBorder(p.cast.edge)
    p.cast.icon = p.cast:CreateTexture(nil, "ARTWORK")
    p.cast.icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    p.cast.text = NewFont(p.text, 7)
    ns.Cast.Decorate(p.cast)
    p.cast:Hide()

    p.auras = CreateFrame("Frame", nil, p)
    p.auras:SetSize(1, 1)
    plateCount = plateCount + 1
    p.auraRows = {
        debuffs = ns.Auras.NewRow(p, "plate" .. plateCount .. " debuffs", true),
        buffs = ns.Auras.NewRow(p, "plate" .. plateCount .. " buffs", true),
    }

    p.ev = CreateFrame("Frame")
    p.ev.plate = p
    return p
end

---------------------------------------------------------------------------
-- Which mode a unit gets
---------------------------------------------------------------------------
local function IsFriendly(unit)
    local ok, v = pcall(UnitCanAttack, "player", unit)
    if ok and not IsSecret(v) then return not v end
    return false
end

local function ModeFor(unit)
    local s = S()
    if s.friendlyMode ~= "SAME" and IsFriendly(unit) then return s.friendlyMode end
    return s.mode
end

---------------------------------------------------------------------------
-- Layout (whenever settings change or a plate gets a unit)
---------------------------------------------------------------------------
local function Layout(p)
    local s = S()
    local mode = ModeFor(p.unit)
    p.mode = mode
    local showBar = mode ~= "NAME"
    local showName = mode ~= "BAR"
    local bs = s.borderSize

    p:ClearAllPoints()
    p:SetPoint("CENTER", p.nameplate, "CENTER", 0, s.yOffset)
    p:SetSize(s.width, s.height)

    local h = p.health
    h:SetShown(showBar)
    h.edge:SetShown(showBar)
    h:SetStatusBarTexture(ns.TexturePath(s.texture))
    Frame.SetBackground(h.bg, s.bgTexture, s.bgColor, s.bgAlpha)
    h.edge:SetAllPoints(h)
    h.edge:SetFrameLevel(h:GetFrameLevel() + 2)
    Frame.LayoutBorder(h.border, h, bs, s.borderColor, 1)
    p.text:SetFrameLevel(h:GetFrameLevel() + 4)

    -- friendly units may have their own name size
    p.friendly = IsFriendly(p.unit)
    local nameSize = (p.friendly and (s.friendlyFontSize or 0) > 0) and s.friendlyFontSize or s.fontSize
    ns.ApplyFont(p.name, s.font, nameSize, s.outline)
    p.name:ClearAllPoints()
    local inside = showBar and (s.namePosition == "LEFT" or s.namePosition == "CENTER")
    p.nameInside = inside
    if inside then
        -- in the bar: left (room for the health text on the right) or centred
        local left = s.namePosition == "LEFT"
        p.name:SetPoint(left and "LEFT" or "CENTER", p, left and "LEFT" or "CENTER", left and 3 or 0, 0)
        p.name:SetJustifyH(left and "LEFT" or "CENTER")
        p.name:SetWidth(math.max(10, s.width - (left and (s.showHealth and 34 or 6) or 4)))
    elseif showBar then
        p.name:SetJustifyH("CENTER")
        p.name:SetPoint("BOTTOM", p, "TOP", 0, s.nameGap + bs)
        p.name:SetWidth(s.width + 40)
    else
        p.name:SetJustifyH("CENTER")
        p.name:SetPoint("CENTER", p, "CENTER", 0, 0)
        p.name:SetWidth(0)
    end
    p.name:SetShown(showName)

    local hs = (s.healthSize or 0) > 0 and s.healthSize or math.max(6, s.fontSize - 2)
    ns.ApplyFont(p.hp, s.font, hs, s.outline)
    p.hp:ClearAllPoints()
    p.hp:SetPoint("RIGHT", p, "RIGHT", inside and -3 or -1, 0)
    p.hp:SetShown(showBar and s.showHealth)

    -- quest progress ("2/10") left outside the bar (left of the name without a bar)
    ns.ApplyFont(p.quest, s.font, s.fontSize, s.outline)
    p.quest:ClearAllPoints()
    if showBar then p.quest:SetPoint("RIGHT", p, "LEFT", -(3 + bs), 0)
    else p.quest:SetPoint("RIGHT", p.name, "LEFT", -3, 0) end
    p.quest:SetTextColor(s.questColor.r, s.questColor.g, s.questColor.b)

    -- elite / rare star right outside the bar (right of the name without a bar)
    local e = p.elite
    e:ClearAllPoints()
    e:SetSize(s.eliteSize, s.eliteSize)
    if showBar then e:SetPoint("LEFT", p, "RIGHT", 2 + bs, 0)
    else e:SetPoint("LEFT", p.name, "RIGHT", 2, 0) end

    -- cast bar under the bar (under the name in name-only mode)
    local c = p.cast
    c:ClearAllPoints()
    local iconW = s.castIcon and (s.castHeight + 4 + bs) or 0
    local room = ns.Combo and ns.Combo.PlateRoom() or 0      -- combo points between bar and cast bar
    if showBar then
        c:SetPoint("TOPLEFT", p, "BOTTOMLEFT", iconW, -(s.castGap + bs * 2 + room))
        c:SetPoint("TOPRIGHT", p, "BOTTOMRIGHT", 0, -(s.castGap + bs * 2 + room))
    else
        c:SetPoint("TOP", p.name, "BOTTOM", iconW / 2, -(s.castGap + bs * 2 + room))
        c:SetWidth(s.width - iconW)
    end
    c:SetHeight(s.castHeight)
    if NP.LayoutThreat then NP.LayoutThreat(p) end
    c:SetStatusBarTexture(ns.TexturePath(s.texture))
    c:SetStatusBarColor(s.castColor.r, s.castColor.g, s.castColor.b)
    Frame.LayoutBorder(c.border, c, bs, s.borderColor, 1)
    c.icon:ClearAllPoints()
    c.icon:SetSize(s.castHeight + 4, s.castHeight + 4)
    c.icon:SetPoint("TOPRIGHT", c, "TOPLEFT", -bs, bs)
    c.icon:SetShown(s.castIcon)
    ns.ApplyFont(c.text, s.font, s.castFontSize, s.outline)
    c.text:ClearAllPoints()
    c.text:SetPoint("TOP", c, "BOTTOM", 0, -1)
    c.text:SetShown(s.castText and c:IsShown())

    -- aura row above the name (above the bar in bar-only mode)
    local a = p.auras
    a:ClearAllPoints()
    if showName and not inside then
        a:SetPoint("BOTTOMLEFT", p.name, "TOPLEFT", 0, s.auraGap)
        a:SetPoint("BOTTOMRIGHT", p.name, "TOPRIGHT", 0, s.auraGap)
    else
        a:SetPoint("BOTTOMLEFT", p, "TOPLEFT", 0, s.auraGap + bs)
        a:SetPoint("BOTTOMRIGHT", p, "TOPRIGHT", 0, s.auraGap + bs)
    end
    a:SetHeight(s.auraSize)
    -- debuffs from the left, buffs from the right, more rows go up
    local common = { size = s.auraSize, gap = s.auraGap, perRow = s.auraMax, rows = s.auraRows or 1,
                     countSize = math.max(6, math.floor(s.auraSize * 0.6)), timer = true, growV = "UP",
                     timerText = s.auraTimer, timerSize = s.auraTimerSize }
    local d, bf = {}, {}
    for k, v in pairs(common) do d[k], bf[k] = v, v end
    d.enabled, d.kind, d.mine = s.showDebuffs, "HARMFUL", s.debuffsMine
    d.anchor, d.growH, d.point = "BOTTOMLEFT", "RIGHT", { "BOTTOMLEFT", a, "BOTTOMLEFT", 0, 0 }
    bf.enabled, bf.kind, bf.mine = s.showBuffs, "HELPFUL", false
    bf.filter, bf.dispelBorder = s.buffFilter or "ALL", s.buffTypeEdge and true or false
    bf.anchor, bf.growH, bf.point = "BOTTOMRIGHT", "LEFT", { "BOTTOMRIGHT", a, "BOTTOMRIGHT", 0, 0 }
    p.auraRows.debuffs:Configure(d)
    p.auraRows.buffs:Configure(bf)

    -- the area the game stacks plates by: ours, not Blizzard's (bigger) one
    local np = p.nameplate
    if np.SetStackingBoundsFrame then
        p.bounds = p.bounds or {}
        local sb = p.bounds[np]
        if not sb then
            sb = CreateFrame("Frame", nil, np)
            local t = sb:CreateTexture(nil, "BACKGROUND")
            t:SetColorTexture(0, 0, 0, 0)
            t:SetAllPoints()
            p.bounds[np] = sb
        end
        -- from the bar's bottom up to the top of the name and the icon row,
        -- so a plate's icons don't sit on the plate above
        local sh = s.height + ((showName and not inside) and (s.fontSize + s.nameGap) or 0)
        if s.showDebuffs or s.showBuffs then
            sh = sh + bs + s.auraGap + s.auraSize * (s.auraRows or 1)
        end
        sb:ClearAllPoints()
        sb:SetPoint("BOTTOM", np, "CENTER", 0, s.yOffset - s.height / 2)
        sb:SetSize(s.width, math.max(1, sh * (s.stackSpacing or 100) / 100))
        sb:Show()
        pcall(np.SetStackingBoundsFrame, np, sb)
    end
    if NP.PlaceQuestie then NP.PlaceQuestie(p) end
end

---------------------------------------------------------------------------
-- Threat colours on the bar (option): what the mob's threat means for you.
-- Damage and healers: safe / about to pull it / it attacks you. Tanks:
-- holding it / losing it / lost it (or another tank has it). You count as a
-- tank with the tank role or a tank spec, and on WoW Forever in bear form,
-- defensive stance or with Righteous Fury up (the game's role there is
-- often "damage" for everyone).
---------------------------------------------------------------------------
local function ThreatShared()
    if IsInGroup and IsInGroup() then return true end
    local ok, e = pcall(UnitExists, "pet")
    return ok and Bool(e)
end

local PLAYER_CLASS = select(2, UnitClass("player"))
local TANK_FORMS = { [5] = true, [8] = true, [18] = true }   -- bear, dire bear, defensive stance
local FURY_IDS = { 25780, 407627, 407628 }                   -- Righteous Fury
local hasFury = false
local playerTanks = false

-- Righteous Fury: read when the game lets us; a refused read keeps the last answer
local function ReadFury()
    if PLAYER_CLASS ~= "PALADIN" or not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then return end
    local answered = false
    for _, id in ipairs(FURY_IDS) do
        local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
        if ok and not IsSecret(aura) then
            if aura then hasFury = true return end
            answered = true
        end
    end
    if answered then hasFury = false end
end

local function TankCheck()
    local ok, role = pcall(UnitGroupRolesAssigned, "player")
    if ok and Plain(role) == "TANK" then return true end
    if PLAYER_CLASS == "DRUID" or PLAYER_CLASS == "WARRIOR" then
        local okF, form = pcall(GetShapeshiftFormID)
        form = okF and Plain(form) or nil
        if TANK_FORMS[form or 0] then return true end
        -- a druid out of bear form / a warrior in another stance: not tanking
        if okF and (form ~= nil or PLAYER_CLASS == "DRUID") then return false end
    end
    if PLAYER_CLASS == "PALADIN" and hasFury then return true end
    if GetSpecialization and GetSpecializationRole then
        local okS, spec = pcall(GetSpecialization)
        spec = okS and Plain(spec) or nil
        if spec then
            local okR, r = pcall(GetSpecializationRole, spec)
            return okR and Plain(r) == "TANK"
        end
    end
    return false
end

-- another group member with the tank role has the mob (off-tanking)
local function OtherTankHolds(unit)
    if not (IsInGroup and IsInGroup()) then return false end
    local raid = IsInRaid and IsInRaid()
    local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    for i = 1, raid and n or math.max(0, n - 1) do
        local m = (raid and "raid" or "party") .. i
        local okU, me = pcall(UnitIsUnit, m, "player")
        local okR, role = pcall(UnitGroupRolesAssigned, m)
        if not (okU and Bool(me)) and okR and Plain(role) == "TANK" then
            local ok, tanking = pcall(UnitDetailedThreatSituation, m, unit)
            if ok and tanking == true then return true end
        end
    end
    return false
end

local function ThreatBarColor(unit, s)
    local mode = s.threatBar
    if mode ~= "ALWAYS" and mode ~= "INSTANCES" then return nil end
    if mode == "INSTANCES" then
        local _, kind = IsInInstance()
        if kind ~= "party" and kind ~= "raid" and kind ~= "scenario" then return nil end
    end
    local ok, status = pcall(UnitThreatSituation, "player", unit)
    if not ok or status == nil or IsSecret(status) then return nil end   -- not fighting your group
    if playerTanks then
        if status >= 3 then return s.threatTankHoldOn and s.threatTankHold or nil end
        if status >= 1 then return s.threatTankLosing end
        if s.threatOffTankOn and OtherTankHolds(unit) then return s.threatOffTank end
        return s.threatTankLost
    end
    if not ThreatShared() then return nil end    -- alone without a pet: always yours
    if status >= 3 then return s.threatDpsAggro end
    if status >= 2 then return s.threatDpsNear end
    return s.threatDpsSafeOn and s.threatDpsSafe or nil
end

---------------------------------------------------------------------------
-- Updates
---------------------------------------------------------------------------
local function UpdateHealth(p)
    local unit = p.unit
    local h = p.health
    local okM, max = pcall(UnitHealthMax, unit)
    local okC, cur = pcall(UnitHealth, unit)
    if okM and okC then
        pcall(h.SetMinMaxValues, h, 0, max)
        pcall(h.SetValue, h, cur)
    end
    local s = S()
    if s.showHealth then ns.SetTemplateText(p.hp, p, s.healthTag or "[hp%]") end
    if s.tappedGray and UnitIsTapDenied then
        local ok, t = pcall(UnitIsTapDenied, unit)
        if ok and Bool(t) then h:SetStatusBarColor(0.5, 0.5, 0.5) return end
    end
    local tc = ThreatBarColor(unit, s)
    if tc then h:SetStatusBarColor(tc.r, tc.g, tc.b) return end
    if s.colorMode == "STATUS" then
        local ok, r, g, b = ns.UnitStatusColor(unit, s, false)
        if ok then h:SetStatusBarColor(r, g, b) return end
    end
    local c, dim
    if s.colorMode == "CLASS" then
        local okP, isPlayer = pcall(UnitIsPlayer, unit)
        local okR, reaction = pcall(UnitReaction, unit, "player")
        if s.reactionColors == "CUSTOM" and not (okP and Bool(isPlayer))
            and okR and reaction and not IsSecret(reaction) then
            -- own colours (EllesmereUI's way): a neutral NPC fighting counts as hostile
            local okC, fighting = pcall(UnitAffectingCombat, unit)
            fighting = okC and Bool(fighting)
            if reaction <= 3 or (reaction == 4 and fighting) then
                c = s.hostileColor
                dim = s.dimOutOfCombat and not fighting
            elseif reaction == 4 then c = s.neutralColor
            else c = s.friendlyColor end
        else
            c = ns.UnitColor(unit, true)
        end
    end
    c = c or s.color
    if dim then h:SetStatusBarColor(c.r * 0.6, c.g * 0.6, c.b * 0.6)
    else h:SetStatusBarColor(c.r, c.g, c.b) end
end

local LEVEL_CLASS = { elite = "E", rareelite = "RE", rare = "R", worldboss = "B" }

-- the difficulty colour of a mob whose level is hidden: the game ranks it
-- itself (trivial .. impossible) without telling the level. "" when it
-- won't say either.
local DIFF_COLOR_NAMES = {
    Trivial = "TRIVIAL_DIFFICULTY_COLOR", Easy = "EASY_DIFFICULTY_COLOR", Fair = "FAIR_DIFFICULTY_COLOR",
    Difficult = "DIFFICULT_DIFFICULTY_COLOR", Impossible = "IMPOSSIBLE_DIFFICULTY_COLOR",
}
local DIFF_FALLBACK = { [0] = { 0.5, 0.5, 0.5 }, { 0.25, 0.75, 0.25 }, { 1, 0.82, 0 }, { 1, 0.5, 0.25 }, { 1, 0.1, 0.1 } }
local function HiddenLevelColor(unit)
    local api = C_PlayerInfo and C_PlayerInfo.GetContentDifficultyCreatureForPlayer
    if not api then return "" end
    local ok, diff = pcall(api, unit)
    if not ok or diff == nil or IsSecret(diff) then return "" end
    local c
    if GetDifficultyColor then
        local okC, col = pcall(GetDifficultyColor, diff)
        if okC and type(col) == "table" and type(col.r) == "number" then c = { col.r, col.g, col.b } end
    end
    if not c and Enum and Enum.RelativeContentDifficulty then
        for name, v in pairs(Enum.RelativeContentDifficulty) do
            local g = v == diff and _G[DIFF_COLOR_NAMES[name] or ""]
            if type(g) == "table" and type(g.r) == "number" then c = { g.r, g.g, g.b } end
        end
    end
    c = c or DIFF_FALLBACK[diff]
    if not c then return "" end
    return ("|cff%02x%02x%02x"):format(math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end
local function UpdateName(p)
    local s = S()
    local unit = p.unit
    if p.mode == "BAR" then return end
    local name = ns.NameText(unit, "PRIVACY")
    p.friendly = IsFriendly(unit)
    local showLevel = s.showLevel
    if p.friendly and s.friendlyLevel and s.friendlyLevel ~= "SAME" then showLevel = s.friendlyLevel == "SHOW" end
    if showLevel then
        local holder = { hunit = unit }
        -- level + classification ("55E") in difficulty colour, then the name
        ns.SetTemplateText(p.name, holder, "[levelclass:color]")
        local okL, lvl = pcall(p.name.GetText, p.name)
        local sep = s.levelSep or " "
        if okL and lvl ~= nil and not IsSecret(lvl) and lvl ~= "" then
            p.levelText = lvl       -- kept while this unit is on the plate
            pcall(p.name.SetFormattedText, p.name, "%s%s%s", lvl, sep, name)
        elseif s.levelAlways and p.levelText then
            -- the game hides the level now: the one read earlier, in colour
            pcall(p.name.SetFormattedText, p.name, "%s%s%s", p.levelText, sep, name)
        elseif s.levelAlways then
            -- hidden since the plate came: the game's value as it is (it
            -- can't be checked), in the colour the game ranks the mob, the
            -- classification after it
            local ok, level = pcall(UnitLevel, unit)
            local okC, cl = pcall(UnitClassification, unit)
            cl = (okC and not IsSecret(cl) and LEVEL_CLASS[cl]) or ""
            local hex = HiddenLevelColor(unit)
            local fmt = hex ~= "" and "%s%s%s|r%s%s" or "%s%s%s%s%s"
            if not (ok and level ~= nil and pcall(p.name.SetFormattedText, p.name, fmt, hex, level, cl, sep, name)) then
                pcall(p.name.SetText, p.name, name)
            end
        else
            pcall(p.name.SetText, p.name, name)
        end
    else
        pcall(p.name.SetText, p.name, name)
    end
    local c
    local mode = s.nameColor
    if p.friendly and s.friendlyNameColor and s.friendlyNameColor ~= "SAME" then mode = s.friendlyNameColor end
    if mode == "CUSTOM" then c = s.nameCustom
    elseif mode == "REACTION" then c = ns.UnitColor(unit, true) end
    c = c or { r = 1, g = 1, b = 1 }
    p.name:SetTextColor(c.r, c.g, c.b)
end

local STAR = {
    elite     = { fill = { 1.00, 0.78, 0.15 } },
    rare      = { fill = { 0.80, 0.82, 0.88 } },
    rareelite = { fill = { 0.80, 0.82, 0.88 }, ring = { 1.00, 0.78, 0.15 } },
    worldboss = { fill = { 0.90, 0.15, 0.15 }, ring = { 1.00, 0.78, 0.15 } },
}
local function UpdateElite(p)
    local e = p.elite
    local ok, cl = pcall(UnitClassification, p.unit)
    local star = S().showElite and ok and not IsSecret(cl) and STAR[cl or ""] or nil
    if not star then e:Hide() return end
    e.fill:SetVertexColor(star.fill[1], star.fill[2], star.fill[3])
    if star.ring then
        e.ring:SetVertexColor(star.ring[1], star.ring[2], star.ring[3])
        e.ring:Show()
    else
        e.ring:Hide()
    end
    e:Show()
end

local function UpdateTarget(p)
    local s = S()
    local ok, isT = pcall(UnitIsUnit, p.unit, "target")
    local c = s.borderColor
    if s.targetBorder and ok and Bool(isT) then c = ns.AccentColor() end
    Frame.LayoutBorder(p.health.border, p.health, s.borderSize, c, 1)
    Frame.LayoutBorder(p.cast.border, p.cast, s.borderSize, s.borderColor, 1)
end

---------------------------------------------------------------------------
-- Quest progress: the unit's tooltip lists the objectives it counts for
-- (kills and quest item drops), as Blizzard's plates show them. Only your
-- own unfinished objectives; "2/10" or "45%". Cached per unit until the
-- quest log changes.
---------------------------------------------------------------------------
local questCache = {}

local function FromText(text)
    if type(text) ~= "string" then return nil end
    local pct = text:match("(%d+)%s*%%")
    if pct then return pct .. "%", true end
    local have, need = text:match("(%d+)%s*/%s*(%d+)")
    have, need = tonumber(have), tonumber(need)
    if have and need then return have .. "/" .. need, have >= need end
    return nil
end

local function ScanStructured(unit)
    local ok, info = pcall(C_TooltipInfo.GetUnit, unit)
    if not ok or type(info) ~= "table" or type(info.lines) ~= "table" then return nil end
    local LT = Enum.TooltipDataLineType
    local questID
    for _, line in ipairs(info.lines) do
        local kind = line.type
        if IsSecret(kind) then kind = nil end
        if kind == LT.QuestTitle then
            local id = line.id
            questID = (id ~= nil and not IsSecret(id)) and id or nil
        elseif kind == LT.QuestObjective then
            local done = line.completed
            if not IsSecret(done) and done ~= true then
                -- another group member's objective doesn't count
                local mine = true
                if questID and C_QuestLog and C_QuestLog.IsOnQuest then
                    local okQ, r = pcall(C_QuestLog.IsOnQuest, questID)
                    if okQ and not IsSecret(r) then mine = r and true or false end
                end
                if mine then
                    local lt = line.leftText
                    if lt ~= nil and IsSecret(lt) then lt = nil end
                    local text = FromText(lt)
                    if text and text:find("%%") then return text end
                    local have, need = line.numFulfilled, line.numRequired
                    if have ~= nil and need ~= nil and not IsSecret(have) and not IsSecret(need) then
                        if have < need then return have .. "/" .. need end
                    elseif text then
                        local _, finished = FromText(lt)
                        if not finished then return text end
                    end
                end
            end
        end
    end
    return nil
end

-- older clients: read the tooltip's text lines ("Kobold Worker slain: 2/10")
local scanTip
local function ScanText(unit)
    scanTip = scanTip or CreateFrame("GameTooltip", "HUFQuestScanTooltip", nil, "GameTooltipTemplate")
    scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
    local ok = pcall(scanTip.SetUnit, scanTip, unit)
    if not ok then return nil end
    for i = 2, scanTip:NumLines() do
        local fs = _G["HUFQuestScanTooltipTextLeft" .. i]
        local t = fs and fs:GetText()
        if t and not IsSecret(t) then
            local text, finished = FromText(t)
            if text and not finished and t:find(":") then return text end
        end
    end
    return nil
end

local function QuestText(unit)
    local c = questCache[unit]
    if c ~= nil then return c or nil end
    local text
    if C_TooltipInfo and C_TooltipInfo.GetUnit and Enum and Enum.TooltipDataLineType
        and Enum.TooltipDataLineType.QuestObjective then
        text = ScanStructured(unit)
    else
        local ok, r = pcall(ScanText, unit)
        if ok then text = r end
    end
    questCache[unit] = text or false
    return text
end

NP.QuestText = function(unit) questCache[unit] = nil return QuestText(unit) end

local function UpdateQuest(p)
    local s = S()
    local text = s.showQuest and p.mode ~= nil and QuestText(p.unit) or nil
    p.quest:SetText(text or "")
    p.quest:SetShown(text ~= nil)
end

---------------------------------------------------------------------------
-- Cast bar (cast times may be secret: the game's timer drives the bar)
---------------------------------------------------------------------------
local Cast = ns.Cast
local function StopCast(p) Cast.Stop(p.cast, true) end

local function CastSetup(p)
    local s, c = S(), p.cast
    c.color = s.castColor
    c.showText = s.castText
    c.showInterrupt = s.castInterrupt
    c.interruptColor = s.castInterruptColor
end

local function UpdateCast(p)
    local s = S()
    if not s.showCast then StopCast(p) return end
    CastSetup(p)
    Cast.Start(p.cast, p.unit)
end


---------------------------------------------------------------------------
-- Threat on the plate's unit: your percent (as the damage meter's threat
-- view) and / or a glow round the bar when the mob is about to switch to you
-- (the game's threat situation 2; 3 = it attacks you, glow optional). Solo
-- without a pet you always hold it: no glow then. Percent and situation may
-- be secret: the percent goes straight into the text, a secret situation
-- shows nothing.
---------------------------------------------------------------------------
local function LayoutThreat(p)
    local s = S()
    local t = p.threat
    ns.ApplyFont(t, s.font, s.threatSize, "OUTLINE")
    t:ClearAllPoints()
    local pos = s.threatPos
    if pos == "LEFT" then t:SetPoint("LEFT", p.health, "LEFT", 2, 0) t:SetJustifyH("LEFT")
    elseif pos == "CENTER" then t:SetPoint("CENTER", p.health, "CENTER", 0, 0) t:SetJustifyH("CENTER")
    elseif pos == "OUTSIDE" then t:SetPoint("LEFT", p.health, "RIGHT", 4 + (s.eliteSize or 0), 0) t:SetJustifyH("LEFT")
    else t:SetPoint("RIGHT", p.health, "RIGHT", -2, 0) t:SetJustifyH("RIGHT") end
    -- glow: soft edges outside the bar
    local g, w = p.glow, s.threatGlowSize
    g:ClearAllPoints()
    g:SetPoint("TOPLEFT", p.health, "TOPLEFT", -w, w)
    g:SetPoint("BOTTOMRIGHT", p.health, "BOTTOMRIGHT", w, -w)
    local e = g.edges
    for i = 1, 4 do e[i]:ClearAllPoints() e[i]:SetTexture("Interface\\Buttons\\WHITE8X8") end
    e[1]:SetPoint("TOPLEFT") e[1]:SetPoint("TOPRIGHT") e[1]:SetHeight(w)               -- top
    e[2]:SetPoint("BOTTOMLEFT") e[2]:SetPoint("BOTTOMRIGHT") e[2]:SetHeight(w)         -- bottom
    e[3]:SetPoint("TOPLEFT", 0, -w) e[3]:SetPoint("BOTTOMLEFT", 0, w) e[3]:SetWidth(w) -- left
    e[4]:SetPoint("TOPRIGHT", 0, -w) e[4]:SetPoint("BOTTOMRIGHT", 0, w) e[4]:SetWidth(w)
end

local function GlowColor(p, c)
    local e = p.glow.edges
    local a = 0.9
    if CreateColor and e[1].SetGradient then
        local solid, clear = CreateColor(c.r, c.g, c.b, a), CreateColor(c.r, c.g, c.b, 0)
        e[1]:SetGradient("VERTICAL", solid, clear)
        e[2]:SetGradient("VERTICAL", clear, solid)
        e[3]:SetGradient("HORIZONTAL", clear, solid)
        e[4]:SetGradient("HORIZONTAL", solid, clear)
        for i = 1, 4 do e[i]:SetVertexColor(1, 1, 1, 1) end
    else
        for i = 1, 4 do e[i]:SetVertexColor(c.r, c.g, c.b, a * 0.6) end
    end
end

local function UpdateThreat(p)
    local s = S()
    local mode = s.threatMode
    local unit = p.unit
    local showPct = (mode == "PERCENT" or mode == "BOTH") and p.mode ~= "NAME"
    local showGlow = (mode == "GLOW" or mode == "BOTH") and p.mode ~= "NAME"
    local friendly = IsFriendly(unit)
    if friendly or not unit then p.threat:Hide() p.glow:Hide() return end
    if showPct then
        local ok, tanking, status, pct = pcall(UnitDetailedThreatSituation, "player", unit)
        if ok and pct ~= nil and (IsSecret(pct) or type(pct) == "number") then
            pcall(p.threat.SetFormattedText, p.threat, "%.0f%%", pct)
            if s.threatColors and ok and status ~= nil and not IsSecret(status) and GetThreatStatusColor then
                p.threat:SetTextColor(GetThreatStatusColor(status))
            else
                p.threat:SetTextColor(1, 1, 1)
            end
            p.threat:Show()
        else
            p.threat:Hide()
        end
    else
        p.threat:Hide()
    end
    if showGlow and ThreatShared() then
        local ok, status = pcall(UnitThreatSituation, "player", unit)
        if ok and status ~= nil and not IsSecret(status) and (status == 2 or (status == 3 and s.threatGlowAggro)) then
            GlowColor(p, status == 3 and s.threatAggroColor or s.threatGlowColor)
            p.glow:Show()
            return
        end
    end
    p.glow:Hide()
end
NP.UpdateThreat = UpdateThreat
NP.LayoutThreat = LayoutThreat

---------------------------------------------------------------------------
-- Auras: Auras.lua (the game's aura containers, they watch UNIT_AURA)
---------------------------------------------------------------------------
local function UpdateAuras(p)
    for _, row in pairs(p.auraRows) do row:Refresh() end
end

local function UpdateAll(p)
    if not p.unit then return end
    UpdateHealth(p)
    UpdateName(p)
    UpdateElite(p)
    UpdateTarget(p)
    UpdateAuras(p)
    UpdateCast(p)
    UpdateQuest(p)
    UpdateThreat(p)
end
NP.UpdateAll = UpdateAll

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local CAST_EVENT = {}
for _, e in ipairs(Cast.EVENTS) do CAST_EVENT[e] = true end
local UNIT_EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_NAME_UPDATE", "UNIT_LEVEL", "UNIT_FACTION", "UNIT_FLAGS",
    "UNIT_CLASSIFICATION_CHANGED",
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_UPDATE",
    "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_THREAT_SITUATION_UPDATE", "UNIT_THREAT_LIST_UPDATE" }

local function OnUnitEvent(ev, event, _, castGUID, spellID, interruptedBy)
    local p = ev.plate
    if not p.unit then return end
    if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then UpdateHealth(p)
    elseif event == "UNIT_THREAT_SITUATION_UPDATE" or event == "UNIT_THREAT_LIST_UPDATE" then
        UpdateThreat(p)
        if S().threatBar ~= "OFF" then UpdateHealth(p) end
    elseif CAST_EVENT[event] then
        if not S().showCast then StopCast(p) return end
        CastSetup(p)
        Cast.OnEvent(p.cast, p.unit, event, castGUID, spellID, interruptedBy, S().castInterruptTime)
    elseif event == "UNIT_FACTION" or event == "UNIT_FLAGS" then
        local mode = ModeFor(p.unit)
        if mode ~= p.mode then Layout(p) end
        UpdateAll(p)
    else
        UpdateName(p)
        UpdateElite(p)
    end
end

local function Attach(unit)
    local s = S()
    if not s.enabled then return end
    local nameplate = C_NamePlate.GetNamePlateForUnit(unit)
    if not nameplate or nameplate:IsForbidden() then return end
    local p = NP.plates[unit] or table.remove(pool) or Build()
    NP.plates[unit] = p
    p.unit = unit
    p.hunit = unit              -- for the text templates
    p.levelText = nil
    p.nameplate = nameplate
    p:SetParent(nameplate)
    p:SetFrameLevel(nameplate:GetFrameLevel() + 2)
    HideBlizzard(nameplate)
    Layout(p)
    p.ev:UnregisterAllEvents()
    p.ev:SetScript("OnEvent", OnUnitEvent)
    for _, e in ipairs(UNIT_EVENTS) do pcall(p.ev.RegisterUnitEvent, p.ev, e, unit) end
    for _, row in pairs(p.auraRows) do row:SetUnit(unit) end
    p:Show()
    UpdateAll(p)
    C_Timer.After(0, function() if NP.plates[unit] == p then NP.PlaceQuestie(p) end end)
end

local function Detach(unit)
    local p = NP.plates[unit]
    if not p then return end
    NP.plates[unit] = nil
    questCache[unit] = nil
    p.ev:UnregisterAllEvents()
    StopCast(p)
    for _, row in pairs(p.auraRows) do row:SetUnit(nil) end
    p:Hide()
    p:SetParent(nil)
    if NP.QuestieRelease then NP.QuestieRelease(p.nameplate) end
    if p.nameplate and p.nameplate.UnitFrame then owned[p.nameplate.UnitFrame] = nil end
    p.unit, p.hunit, p.nameplate, p.levelText = nil, nil, nil, nil
    pool[#pool + 1] = p
end

ns.On("NAME_PLATE_UNIT_ADDED", function(unit)
    if not ns.db then return end
    local ok, err = pcall(Attach, unit)
    if not ok then ns.LogError("nameplate " .. tostring(unit), err) end
end)
ns.On("NAME_PLATE_UNIT_REMOVED", function(unit) Detach(unit) end)

-- tank or not: forms, stances, Righteous Fury, role and spec
local function TankChanged()
    ReadFury()
    local now = TankCheck()
    if now == playerTanks then return end
    playerTanks = now
    if S().threatBar == "OFF" then return end
    for _, p in pairs(NP.plates) do if p.unit then UpdateHealth(p) end end
end
for _, e in ipairs({ "UPDATE_SHAPESHIFT_FORM", "PLAYER_SPECIALIZATION_CHANGED", "PLAYER_ROLES_ASSIGNED",
                     "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED" }) do
    pcall(ns.On, e, TankChanged)
end
if PLAYER_CLASS == "PALADIN" then
    pcall(ns.On, "UNIT_AURA", function(unit) if unit == "player" then TankChanged() end end)
end
ns.On("PLAYER_TARGET_CHANGED", function()
    for _, p in pairs(NP.plates) do UpdateTarget(p) end
end)

-- quest log changed (a kill counted, quest taken or done): progress again,
-- at most a few times a second
local questPending = false
local function QuestChanged()
    if questPending then return end
    questPending = true
    C_Timer.After(0.3, function()
        questPending = false
        questCache = {}
        for _, p in pairs(NP.plates) do UpdateQuest(p) end
    end)
end
ns.On("QUEST_LOG_UPDATE", QuestChanged)
ns.On("UNIT_QUEST_LOG_CHANGED", function(unit) if unit == "player" then QuestChanged() end end)
ns.On("ZONE_CHANGED_NEW_AREA", QuestChanged)

-- settings changed: every plate again; switched off: Blizzard's back
-- stacking: the game's own switch per enemies / friendly units (only when
-- set here; not in combat, the game may refuse it there)
local function ApplyStacking()
    local s = S()
    if not C_CVar then return end
    local types = Enum and Enum.NamePlateStackType
    local function Set(idx, mode)
        if idx == nil or mode == nil or mode == "GAME" or not C_CVar.SetCVarBitfield then return end
        pcall(C_CVar.SetCVarBitfield, "nameplateStackingTypes", idx, mode == "ON")
    end
    ns.RunOOC("nameplate stacking", function()
        if types then
            Set(types.Enemy, s.stackEnemies)
            Set(types.Friendly, s.stackFriendly)
        end
        -- older clients (WoW Forever): one switch for all plates,
        -- nameplateMotion 0 = overlap, 1 = stack; it follows the enemies setting
        if s.stackEnemies == "ON" or s.stackEnemies == "OFF" then
            pcall(C_CVar.SetCVar, "nameplateMotion", s.stackEnemies == "ON" and "1" or "0")
        end
    end)
end
NP.ApplyStacking = ApplyStacking

function NP.ApplyAll()
    local s = S()
    ApplyStacking()
    if not s.enabled then
        for unit, p in pairs(NP.plates) do
            local np = p.nameplate
            Detach(unit)
            RestoreBlizzard(np)
        end
        return
    end
    for _, p in pairs(NP.plates) do
        Layout(p)
        UpdateAll(p)
    end
    -- plates that were there before (HUF just switched on)
    if C_NamePlate and C_NamePlate.GetNamePlates then
        for _, np in ipairs(C_NamePlate.GetNamePlates() or {}) do
            local unit = np.namePlateUnitToken or (np.UnitFrame and np.UnitFrame.unit)
            if unit and not NP.plates[unit] then pcall(Attach, unit) end
        end
    end
end
ns.OnRefresh(function() if ns.ready then NP.ApplyAll() end end)
ns.Listen("PROFILE_CHANGED", function() NP.ApplyAll() end)

---------------------------------------------------------------------------
-- Questie's quest icon: Questie pins it to the left edge of the game's
-- nameplate (under ours, on the level). HUF puts it on its own plate: left
-- of the quest progress, right of the bar, or where Questie wants it.
---------------------------------------------------------------------------
-- Questie's icon frames on one game nameplate (a child with .Icon and .lastIcon)
local function QuestieFrames(nameplate)
    local list = {}
    if not nameplate then return list end
    local ok, kids = pcall(function() return { nameplate:GetChildren() } end)
    if not ok then return list end
    for _, k in ipairs(kids) do
        if type(rawget(k, "Icon")) == "table" and rawget(k, "lastIcon") ~= nil then list[#list + 1] = k end
    end
    return list
end

-- back to Questie's own spot (its setting, relative to the game's nameplate)
local function QuestieHome(f)
    local db = Questie and Questie.db and Questie.db.profile
    f:ClearAllPoints()
    f:SetPoint("LEFT", (db and db.nameplateX) or -17, (db and db.nameplateY) or -7)
end

function NP.PlaceQuestie(p)
    if not (p and p.nameplate) then return end
    local where = S().questieIcon or "LEFT"
    for _, f in ipairs(QuestieFrames(p.nameplate)) do
        if where == "QUESTIE" then
            QuestieHome(f)
        else
            -- always (and only) the LEFT point, as Questie sets it: when
            -- Questie moves the frame to another nameplate, its SetPoint
            -- replaces ours instead of tying the frame to two nameplates
            -- ("anchor family connection")
            f:ClearAllPoints()
            if where == "RIGHT" then
                -- after the elite star's spot, clear of the bar
                f:SetPoint("LEFT", p.elite, "RIGHT", 1, 0)
            else
                -- left of the quest progress ("0/6"), or of the bar without it
                f:SetPoint("LEFT", p.quest, "LEFT", -((f:GetWidth() or 16) + 2), 0)
            end
        end
    end
end

function NP.QuestieRelease(nameplate)
    for _, f in ipairs(QuestieFrames(nameplate)) do QuestieHome(f) end
end

local function PlaceQuestieFor(token)
    local p = token and NP.plates[token]
    if p then
        NP.PlaceQuestie(p)
    elseif token and C_NamePlate then
        -- no HUF plate here (any more): Questie's own spot
        local ok, np = pcall(C_NamePlate.GetNamePlateForUnit, token)
        if ok and np then for _, f in ipairs(QuestieFrames(np)) do QuestieHome(f) end end
    end
end

ns.OnLogin(function()
    local mods = QuestieLoader and QuestieLoader._modules
    local QN = type(mods) == "table" and mods.QuestieNameplate
    if type(QN) ~= "table" then return end
    local function All() for _, p in pairs(NP.plates) do NP.PlaceQuestie(p) end end
    if type(QN.NameplateCreated) == "function" then
        hooksecurefunc(QN, "NameplateCreated", function(_, token) PlaceQuestieFor(token) end)
    end
    for _, fn in ipairs({ "UpdateNameplate", "RedrawIcons" }) do
        if type(QN[fn]) == "function" then hooksecurefunc(QN, fn, All) end
    end
    ns.Log("init", "Questie nameplate icons follow HUF's plates")
end)

---------------------------------------------------------------------------
-- Instances: the game protects friendly player nameplates there (forbidden
-- frames): HUF can't draw on them and Blizzard's show the real full name.
-- While names are private, friendly player plates and the names the game
-- draws above characters are switched off inside instances and put back
-- outside. Values before are kept per character (HUFDB.instanceNames) and
-- only restored if nobody changed them in the meantime.
---------------------------------------------------------------------------
local INSTANCE_CVARS = { nameplateShowFriendlyPlayers = "0", nameplateShowFriends = "0", UnitNameFriendlyPlayerName = "0" }
local function GetCV(name)
    if C_CVar and C_CVar.GetCVar then return C_CVar.GetCVar(name) end
    if GetCVar then return GetCVar(name) end
end
local function SetCV(name, value)
    if C_CVar and C_CVar.SetCVar then return pcall(C_CVar.SetCVar, name, value) end
    if SetCVar then return pcall(SetCVar, name, value) end
end

-- names on screen differ from the real ones (HUF's setting or MMT's privacy)
local function NamesPrivate()
    if ns.db.privacy.mode ~= "FULL" then return true end
    return ns.Bridge and ns.Bridge.Active() and true or false
end

local instancePending, busy
-- confirmed: a second look a moment later. Right after a /reload the game can
-- briefly say "not in an instance" (and MMT's link may not be up yet):
-- old values only come back after that second look.
function NP.ApplyInstanceNames(confirmed)
    if not HUFDB or not ns.db then return end
    if InCombatLockdown() then instancePending = true return end
    instancePending = nil
    HUFDB.instanceNames = HUFDB.instanceNames or {}
    local me = ns.CharKey()
    local saved = HUFDB.instanceNames[me] or {}
    local inInst, itype = false, nil
    if IsInInstance then inInst, itype = IsInInstance() end
    local inside = inInst and itype ~= "none"
    local want = ns.db.nameplates.instanceFriends ~= "SHOW" and inside and NamesPrivate()
    if want then
        busy = true
        for cvar, value in pairs(INSTANCE_CVARS) do
            local cur = GetCV(cvar)
            if cur ~= nil and cur ~= value then
                if not saved[cvar] then saved[cvar] = { old = cur, set = value } end
                SetCV(cvar, value)
            end
        end
        busy = false
    elseif next(saved) then
        if not confirmed then
            C_Timer.After(2, function() NP.ApplyInstanceNames(true) end)
            return
        end
        busy = true
        for cvar, st in pairs(saved) do
            if type(st) == "table" and GetCV(cvar) == st.set then SetCV(cvar, st.old) end
            saved[cvar] = nil
        end
        busy = false
    end
    HUFDB.instanceNames[me] = next(saved) and saved or nil
    ns.Log("nameplates", "instance names: inside=%s (%s) private=%s hide=%s%s", tostring(inside), tostring(itype),
        tostring(NamesPrivate()), tostring(want and true or false), confirmed and " (2nd look)" or "")
end
ns.On("PLAYER_ENTERING_WORLD", function()
    NP.ApplyInstanceNames()
    -- once more when everything (MMT included) has settled
    C_Timer.After(3, function() NP.ApplyInstanceNames() end)
end)
ns.On("ZONE_CHANGED_NEW_AREA", function() NP.ApplyInstanceNames() end)
ns.On("PLAYER_REGEN_ENABLED", function() if instancePending then NP.ApplyInstanceNames() end end)
-- someone else (MMT's "Name above characters", the game) switched one of them
-- back on inside an instance: off again
ns.On("CVAR_UPDATE", function(name)
    if busy or type(name) ~= "string" then return end
    for cvar in pairs(INSTANCE_CVARS) do
        if cvar:lower() == name:lower() then
            C_Timer.After(0.3, function() NP.ApplyInstanceNames() end)
            return
        end
    end
end)
ns.OnRefresh(function() NP.ApplyInstanceNames() end)

function NP.Count()
    local n = 0
    for _ in pairs(NP.plates) do n = n + 1 end
    return n
end
