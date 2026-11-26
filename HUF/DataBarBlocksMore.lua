-- HUF: more data bar blocks (ideas from EllesmereUI's data bars and ElvUI's data texts; no code
-- of theirs): bags, location, coordinates, hearthstone, XP / reputation, supplies, talents,
-- item level, system, currency, time played, profession, mail, a character stat, spacer -
-- and, while MMT is on, the team's gold, who is online, the layer and the fullest bags.
-- Loads after DataBarBlocks.lua (BL.Type and the helpers) and before DataBars.lua.

local _, ns = ...
local BL = ns.DataBlocks
local Type, Line, Grade, Money, Abbrev = BL.Type, BL.Line, BL.Grade, BL.Money, BL.Abbrev

local CC = C_Container or {}
local function Safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local r = { pcall(fn, ...) }
    if not r[1] then return nil end
    return unpack(r, 2)
end
local function Plain(v) return v ~= nil and not (ns.IsSecret and ns.IsSecret(v)) end
local GetItemCount = (C_Item and C_Item.GetItemCount) or GetItemCount
local function ItemName(id)
    local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    return (f and Safe(f, id)) or ("item " .. id)
end
local function Duration(s)
    s = math.max(0, math.floor(s or 0))
    if s >= 86400 then return ("%dd %dh"):format(s / 86400, (s % 86400) / 3600) end
    if s >= 3600 then return ("%dh %dm"):format(s / 3600, (s % 3600) / 60) end
    if s >= 60 then return ("%dm"):format(s / 60) end
    return s .. "s"
end

---------------------------------------------------------------------------
-- Bags: free slots
---------------------------------------------------------------------------
local function BagSpace()
    local free, total = 0, 0
    for bag = 0, (NUM_BAG_SLOTS or 4) + 1 do
        local slots = Safe(CC.GetContainerNumSlots or GetContainerNumSlots, bag) or 0
        local f, kind = Safe(CC.GetContainerNumFreeSlots or GetContainerNumFreeSlots, bag)
        -- only plain bags (no quiver, soul or herb bag)
        if slots > 0 and (kind == nil or kind == 0) then
            free, total = free + (f or 0), total + slots
        end
    end
    return free, total
end
Type("bags", {
    title = "Bags", showIcon = true, steady = 2,
    settings = { show = "FREE" },          -- FREE (12) | USED (68/80) | BOTH (12 / 80)
    icon = { file = "Interface\\Buttons\\Button-Backpack-Up" },
    events = { "BAG_UPDATE_DELAYED", "PLAYER_ENTERING_WORLD" },
    Text = function(b)
        local free, total = BagSpace()
        local r, g, bl = Grade(total > 0 and free / math.min(total, 20) or 1)
        local mode = b.cfg.settings.show
        if mode == "USED" then return (total - free) .. "/" .. total, r, g, bl end
        if mode == "BOTH" then return free .. " / " .. total, r, g, bl end
        return tostring(free), r, g, bl
    end,
    Tooltip = function(_, tt)
        local free, total = BagSpace()
        tt:SetText("Bags")
        Line(tt, "Free", free)
        Line(tt, "Used", (total - free) .. " / " .. total)
        Line(tt, "Click: bags.")
    end,
    Click = function() if ToggleAllBags then ToggleAllBags() end end,
})

---------------------------------------------------------------------------
-- Location and coordinates
---------------------------------------------------------------------------
local PVP = { sanctuary = { 0.41, 0.8, 0.94 }, friendly = { 0.1, 1, 0.1 }, hostile = { 1, 0.1, 0.1 },
    contested = { 1, 0.7, 0 }, combat = { 1, 0.1, 0.1 }, arena = { 1, 0.1, 0.1 } }
Type("location", {
    title = "Location", showIcon = false,
    settings = { subzone = true },
    icon = { file = "Interface\\Icons\\INV_Misc_Map_01" },
    events = { "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" },
    Text = function(b)
        local zone, sub = GetZoneText() or "", GetSubZoneText() or ""
        local text = (b.cfg.settings.subzone and sub ~= "") and sub or zone
        local c = PVP[(GetZonePVPInfo and GetZonePVPInfo()) or ""] or { 1, 0.82, 0 }
        return text, c[1], c[2], c[3]
    end,
    Tooltip = function(_, tt)
        local kind = GetZonePVPInfo and GetZonePVPInfo()
        tt:SetText(GetZoneText() or "")
        local sub = GetSubZoneText()
        if sub and sub ~= "" then Line(tt, "Here", sub) end
        if kind then Line(tt, "Territory", kind:gsub("^%l", string.upper)) end
        Line(tt, "Click: world map.")
    end,
    Click = function() if ToggleWorldMap then ToggleWorldMap() end end,
})

local function Coords()
    if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
    local map = Safe(C_Map.GetBestMapForUnit, "player")
    local pos = map and Safe(C_Map.GetPlayerMapPosition, map, "player")
    if not pos then return nil end
    local x, y = Safe(pos.GetXY, pos)
    if not (Plain(x) and Plain(y)) or (x == 0 and y == 0) then return nil end
    return x * 100, y * 100
end
Type("coords", {
    title = "Coordinates", showIcon = false, tick = true, steady = 4,
    icon = { file = "Interface\\Icons\\INV_Misc_Map_01" },
    Text = function()
        local x, y = Coords()
        if not x then return "-" end
        return ("%.1f, %.1f"):format(x, y)
    end,
    Click = function() if ToggleWorldMap then ToggleWorldMap() end end,
})

---------------------------------------------------------------------------
-- Hearthstone: where it is bound and its cooldown (blocks can't use items: use it from the bags)
---------------------------------------------------------------------------
local HEARTH = 6948
Type("hearth", {
    title = "Hearthstone", showIcon = true, tick = true,
    icon = { file = "Interface\\Icons\\INV_Misc_Rune_01" },
    Text = function()
        local start, dur = Safe(CC.GetItemCooldown or GetItemCooldown, HEARTH)
        if Plain(start) and Plain(dur) and start and dur and dur > 1.5 then
            return Duration(start + dur - GetTime()), 1, 0.5, 0.3
        end
        return GetBindLocation and GetBindLocation() or "Hearthstone"
    end,
    Tooltip = function(_, tt)
        tt:SetText("Hearthstone")
        Line(tt, "Bound to", GetBindLocation and GetBindLocation() or "?")
        local start, dur = Safe(CC.GetItemCooldown or GetItemCooldown, HEARTH)
        if Plain(start) and start and dur and dur > 1.5 then Line(tt, "Ready in", Duration(start + dur - GetTime()))
        else Line(tt, "Ready", "now") end
        Line(tt, "Use it from your bags (a data bar can't use items).")
    end,
})

---------------------------------------------------------------------------
-- XP / reputation
---------------------------------------------------------------------------
local function MaxLevel()
    return (GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion()) or (GetMaxPlayerLevel and GetMaxPlayerLevel()) or 60
end
local function Watched()
    if C_Reputation and C_Reputation.GetWatchedFactionData then
        local d = C_Reputation.GetWatchedFactionData()
        if d then return d.name, d.reaction, d.currentReactionThreshold, d.nextReactionThreshold, d.currentStanding end
    elseif GetWatchedFactionInfo then
        return GetWatchedFactionInfo()
    end
end
Type("xprep", {
    title = "XP / reputation", showIcon = false, steady = 3,
    settings = { show = "AUTO" },        -- AUTO (XP below the highest level, else reputation) | XP | REP
    icon = { file = "Interface\\Icons\\INV_Misc_Note_01" },
    events = { "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION", "PLAYER_LEVEL_UP", "UPDATE_FACTION", "PLAYER_ENTERING_WORLD" },
    Text = function(b)
        local mode = b.cfg.settings.show
        if mode == "XP" or (mode == "AUTO" and UnitLevel("player") < MaxLevel()) then
            local cur, max = UnitXP("player"), UnitXPMax("player")
            if not (Plain(cur) and Plain(max)) or max <= 0 then return "-" end
            local rested = GetXPExhaustion() or 0
            local t = ("%d%%"):format(cur / max * 100)
            if rested > 0 then t = t .. (" |cff4da6ff+%d%%|r"):format(rested / max * 100) end
            return t, 0.69, 0.53, 1
        end
        local name, standing, lo, hi, v = Watched()
        if not name or not Plain(v) then return "No faction watched", 0.6, 0.6, 0.6 end
        local c = FACTION_BAR_COLORS and FACTION_BAR_COLORS[standing] or { r = 0, g = 0.7, b = 0.2 }
        return ("%s %d%%"):format(name, (v - lo) / math.max(1, hi - lo) * 100), c.r, c.g, c.b
    end,
    Tooltip = function(_, tt)
        tt:SetText("XP / reputation")
        local cur, max = UnitXP("player"), UnitXPMax("player")
        if Plain(cur) and max and max > 0 and UnitLevel("player") < MaxLevel() then
            Line(tt, "XP", ("%s / %s"):format(BreakUpLargeNumbers and BreakUpLargeNumbers(cur) or cur, BreakUpLargeNumbers and BreakUpLargeNumbers(max) or max))
            Line(tt, "Rested", BreakUpLargeNumbers and BreakUpLargeNumbers(GetXPExhaustion() or 0) or (GetXPExhaustion() or 0))
        end
        local name, standing, lo, hi, v = Watched()
        if name and Plain(v) then
            Line(tt, name, ("%d / %d %s"):format(v - lo, hi - lo, _G["FACTION_STANDING_LABEL" .. tostring(standing)] or ""))
        end
        Line(tt, "Click: reputation.")
    end,
    Click = function() if ToggleCharacter then ToggleCharacter("ReputationFrame") end end,
})

---------------------------------------------------------------------------
-- Supplies: ammo / thrown, soul shards, class reagents
---------------------------------------------------------------------------
local REAGENTS = {
    MAGE = { 17020, 17031, 17032, 17056 },                 -- arcane powder, teleport / portal runes, light feather
    PRIEST = { 17028, 17029, 17056 },                      -- holy / sacred candle, light feather
    PALADIN = { 21177, 17033 },                            -- symbol of kings, symbol of divinity
    DRUID = { 17026, 17021, 17034, 17035, 17036, 17037, 17038 },   -- thornroot, berries, rebirth seeds
    SHAMAN = { 17030 },                                    -- ankh
    ROGUE = { 5140, 5530 },                                -- flash / blinding powder
    WARLOCK = { 6265, 5565, 16583 },                       -- soul shard, infernal stone, demonic figurine
}
local function Supplies()
    local list = {}
    -- ammo (classic ammo slot 0) or thrown weapon
    local ammo = Safe(GetInventoryItemCount, "player", 0)
    local ammoLink = Safe(GetInventoryItemLink, "player", 0)
    if ammoLink and ammo and ammo > 0 then list[#list + 1] = { name = ammoLink, n = ammo } end
    local _, class = UnitClass("player")
    for _, id in ipairs(REAGENTS[class] or {}) do
        local n = Safe(GetItemCount, id) or 0
        if n > 0 then list[#list + 1] = { name = ItemName(id), n = n, id = id } end
    end
    return list
end
Type("supplies", {
    title = "Supplies", showIcon = false, steady = 2,
    icon = { file = "Interface\\Icons\\INV_Ammo_Arrow_02" },
    events = { "BAG_UPDATE_DELAYED", "UNIT_INVENTORY_CHANGED", "PLAYER_ENTERING_WORLD" },
    Text = function()
        local l = Supplies()
        if #l == 0 then return "-" end
        local first = l[1]
        local r, g, b = Grade(math.min(1, first.n / 200))
        return tostring(first.n), r, g, b
    end,
    Tooltip = function(_, tt)
        tt:SetText("Supplies")
        local l = Supplies()
        if #l == 0 then Line(tt, "None carried") end
        for _, e in ipairs(l) do Line(tt, e.name, e.n) end
    end,
})

---------------------------------------------------------------------------
-- Talents: the main tree and the points (both dual specs in the tooltip when there are two)
---------------------------------------------------------------------------
local function Trees(group)
    local out = {}
    local n = Safe(GetNumTalentTabs) or 0
    for i = 1, n do
        local r = { pcall(GetTalentTabInfo, i, false, false, group) }
        if r[1] then
            -- classic: name, icon, points, file; newer: id, name, desc, icon, points, ...
            local name, points
            if type(r[2]) == "string" then name, points = r[2], r[4]
            else name, points = r[3], r[6] end
            if type(points) ~= "number" then for k = 2, #r do if type(r[k]) == "number" and k > 2 then points = r[k] break end end end
            out[#out + 1] = { name = name or ("Tree " .. i), points = tonumber(points) or 0 }
        end
    end
    return out
end
local function Build(group)
    local t = Trees(group)
    local best, pts = nil, {}
    for _, e in ipairs(t) do
        pts[#pts + 1] = e.points
        if not best or e.points > best.points then best = e end
    end
    if not best or best.points == 0 then return nil end
    return best.name, table.concat(pts, "/")
end
Type("spec", {
    title = "Talents", showIcon = false,
    icon = { file = "Interface\\Icons\\INV_Misc_Book_11" },
    events = { "CHARACTER_POINTS_CHANGED", "PLAYER_TALENT_UPDATE", "ACTIVE_TALENT_GROUP_CHANGED", "PLAYER_ENTERING_WORLD" },
    Text = function()
        local active = Safe(GetActiveTalentGroup) or 1
        local name, pts = Build(active)
        if not name then return "No talents" end
        return ("%s (%s)"):format(name, pts)
    end,
    Tooltip = function(_, tt)
        tt:SetText("Talents")
        local groups = Safe(GetNumTalentGroups) or 1
        local active = Safe(GetActiveTalentGroup) or 1
        for g = 1, math.max(1, groups) do
            local name, pts = Build(g)
            Line(tt, (groups > 1 and ("Spec " .. g .. (g == active and " (active)" or "")) or "Spec"), name and (name .. " " .. pts) or "-")
        end
        Line(tt, "Click: talents.")
    end,
    Click = function()
        if ToggleTalentFrame then ToggleTalentFrame()
        elseif PlayerTalentFrame_Toggle then PlayerTalentFrame_Toggle() end
    end,
})

---------------------------------------------------------------------------
-- Item level
---------------------------------------------------------------------------
local ILVL_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }
local function ItemLevels()
    local list, sum, n = {}, 0, 0
    local GetLevel = (C_Item and C_Item.GetDetailedItemLevelInfo) or GetDetailedItemLevelInfo
    for _, slot in ipairs(ILVL_SLOTS) do
        local link = GetInventoryItemLink("player", slot)
        if link then
            local lvl = GetLevel and Safe(GetLevel, link)
            if not lvl then lvl = select(4, Safe((C_Item and C_Item.GetItemInfo) or GetItemInfo, link)) end
            if type(lvl) == "number" then
                list[#list + 1] = { link = link, lvl = lvl }
                sum, n = sum + lvl, n + 1
            end
        end
    end
    table.sort(list, function(a, b) return a.lvl < b.lvl end)
    return n > 0 and sum / n or nil, list
end
Type("ilvl", {
    title = "Item level", showIcon = false, steady = 3,
    icon = { file = "Interface\\Icons\\INV_Chest_Plate06" },
    events = { "PLAYER_EQUIPMENT_CHANGED", "PLAYER_ENTERING_WORLD" },
    Text = function()
        local avg = ItemLevels()
        return avg and ("ilvl %.1f"):format(avg) or "-"
    end,
    Tooltip = function(_, tt)
        local avg, list = ItemLevels()
        tt:SetText("Item level")
        Line(tt, "Average equipped", avg and ("%.1f"):format(avg) or "-")
        for i = 1, math.min(4, #list) do tt:AddDoubleLine(list[i].link, list[i].lvl, 1, 1, 1, 1, 0.5, 0.3) end
        Line(tt, "Click: character.")
    end,
    Click = function() if ToggleCharacter then ToggleCharacter("PaperDollFrame") end end,
})

---------------------------------------------------------------------------
-- System: FPS, latency and the addons' memory (in the tooltip)
---------------------------------------------------------------------------
local AddOns = C_AddOns or {}
Type("system", {
    title = "System", showIcon = false, tick = true, steady = 6,
    icon = { file = "Interface\\Icons\\INV_Misc_PocketWatch_01" },
    Text = function()
        local fps = math.floor((GetFramerate() or 0) + 0.5)
        local _, _, home, world = GetNetStats()
        return ("%dfps %dms"):format(fps, math.max(home or 0, world or 0)), Grade(fps / 60)
    end,
    Tooltip = function(_, tt)
        tt:SetText("System")
        local _, _, home, world = GetNetStats()
        Line(tt, "Latency home / world", ("%d / %d ms"):format(home or 0, world or 0))
        if UpdateAddOnMemoryUsage then pcall(UpdateAddOnMemoryUsage) end
        local list, total = {}, 0
        local num = (AddOns.GetNumAddOns or GetNumAddOns)() or 0
        for i = 1, num do
            local kb = Safe(GetAddOnMemoryUsage, i)
            if kb and kb > 0 then
                local name = (AddOns.GetAddOnInfo or GetAddOnInfo)(i)
                list[#list + 1] = { name = name, kb = kb }
                total = total + kb
            end
        end
        table.sort(list, function(a, b) return a.kb > b.kb end)
        Line(tt, "Addon memory", ("%.1f MB"):format(total / 1024))
        for i = 1, math.min(10, #list) do
            local e = list[i]
            Line(tt, "  " .. e.name, e.kb > 1024 and ("%.1f MB"):format(e.kb / 1024) or ("%d KB"):format(e.kb))
        end
        Line(tt, "Click: free unused memory.")
    end,
    Click = function() collectgarbage("collect") end,
})

---------------------------------------------------------------------------
-- Currency: one chosen by name (empty: the first one you have)
---------------------------------------------------------------------------
function BL.Currencies()
    local out = {}
    local CI = C_CurrencyInfo
    local size = CI and CI.GetCurrencyListSize and Safe(CI.GetCurrencyListSize) or (GetCurrencyListSize and Safe(GetCurrencyListSize)) or 0
    for i = 1, size do
        local name, isHeader, count, icon
        if CI and CI.GetCurrencyListInfo then
            local d = Safe(CI.GetCurrencyListInfo, i)
            if d then name, isHeader, count, icon = d.name, d.isHeader, d.quantity, d.iconFileID end
        elseif GetCurrencyListInfo then
            local r = { Safe(GetCurrencyListInfo, i) }
            name, isHeader, count, icon = r[1], r[2], r[6], r[7]
        end
        if name and not isHeader then out[#out + 1] = { name = name, count = count or 0, icon = icon } end
    end
    if GetHonorCurrency then
        local h = Safe(GetHonorCurrency)
        if h then out[#out + 1] = { name = HONOR or "Honor", count = h } end
    end
    return out
end
local function Pick(b)
    local want = b.cfg.settings.name
    for _, c in ipairs(BL.Currencies()) do
        if (want ~= "" and c.name == want) or (want == "" and c.count > 0) then return c end
    end
end
Type("currency", {
    title = "Currency", showIcon = false,
    settings = { name = "" },
    icon = { file = "Interface\\Icons\\INV_Misc_Coin_17" },
    events = { "CURRENCY_DISPLAY_UPDATE", "PLAYER_ENTERING_WORLD" },
    IconFor = function(b)
        local c = Pick(b)
        return c and c.icon and { file = c.icon } or nil
    end,
    Text = function(b)
        local c = Pick(b)
        if not c then return "-" end
        return (b.cfg.showIcon and "" or (c.name .. " ")) .. (BreakUpLargeNumbers and BreakUpLargeNumbers(c.count) or c.count)
    end,
    Tooltip = function(_, tt)
        tt:SetText("Currencies")
        local l = BL.Currencies()
        if #l == 0 then Line(tt, "None") end
        for _, c in ipairs(l) do Line(tt, c.name, c.count) end
        Line(tt, "Click: currencies.")
    end,
    Click = function() if ToggleCharacter then ToggleCharacter("TokenFrame") end end,
})

---------------------------------------------------------------------------
-- Time played: this session; totals asked for on the first hover (the game's answer is also
-- its chat line) and kept per character
---------------------------------------------------------------------------
local loginTime = GetTime()
local played = { asked = false }
ns.On("TIME_PLAYED_MSG", function(total, level)
    played.total, played.level, played.at = total, level, GetTime()
    if HUFDB then
        HUFDB.played = HUFDB.played or {}
        HUFDB.played[(UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")] = total
    end
end)
Type("played", {
    title = "Time played", showIcon = false, tick = true, steady = 4,
    icon = { file = "Interface\\Icons\\INV_Misc_PocketWatch_02" },
    Text = function() return Duration(GetTime() - loginTime) end,
    Tooltip = function(_, tt)
        if not played.asked and RequestTimePlayed then played.asked = true pcall(RequestTimePlayed) end
        tt:SetText("Time played")
        Line(tt, "This session", Duration(GetTime() - loginTime))
        if played.total then
            local since = GetTime() - played.at
            Line(tt, "This level", Duration(played.level + since))
            Line(tt, "This character", Duration(played.total + since))
        else
            Line(tt, "Asking the game...")
        end
        local all, sum = HUFDB and HUFDB.played, 0
        if type(all) == "table" then
            for _, t in pairs(all) do sum = sum + (tonumber(t) or 0) end
            if sum > 0 then Line(tt, "All characters seen", Duration(sum)) end
        end
    end,
})

---------------------------------------------------------------------------
-- Profession: the first or second one with its skill
---------------------------------------------------------------------------
local function Professions()
    local out = {}
    if GetProfessions and GetProfessionInfo then
        local a, b = GetProfessions()
        for _, i in ipairs({ a, b }) do
            local name, icon, rank, max = GetProfessionInfo(i)
            if name then out[#out + 1] = { name = name, icon = icon, rank = rank, max = max } end
        end
        if #out > 0 then return out end
    end
    -- classic: the skill list ("Professions" header)
    local n = Safe(GetNumSkillLines) or 0
    local inProf = false
    for i = 1, n do
        local name, isHeader, _, rank, _, _, max = GetSkillLineInfo(i)
        if isHeader then inProf = (name == (TRADE_SKILLS or "Professions"))
        elseif inProf and name then out[#out + 1] = { name = name, rank = rank, max = max } end
    end
    return out
end
Type("profession", {
    title = "Profession", showIcon = false,
    settings = { which = 1 },
    icon = { file = "Interface\\Icons\\INV_Misc_Book_08" },
    events = { "SKILL_LINES_CHANGED", "TRADE_SKILL_UPDATE", "PLAYER_ENTERING_WORLD" },
    IconFor = function(b)
        local p = Professions()[b.cfg.settings.which or 1]
        return p and p.icon and { file = p.icon } or nil
    end,
    Text = function(b)
        local p = Professions()[b.cfg.settings.which or 1]
        if not p then return "-" end
        return ("%s %d"):format(b.cfg.showIcon and "" or p.name, p.rank or 0), Grade((p.rank or 0) / math.max(1, p.max or 300))
    end,
    Tooltip = function(_, tt)
        tt:SetText("Professions")
        local l = Professions()
        if #l == 0 then Line(tt, "None learned") end
        for _, p in ipairs(l) do Line(tt, p.name, ("%d / %d"):format(p.rank or 0, p.max or 0)) end
        Line(tt, "Click: spellbook (professions).")
    end,
    Click = function() if ToggleSpellBook then pcall(ToggleSpellBook, BOOKTYPE_PROFESSION or "professions") end end,
})

---------------------------------------------------------------------------
-- Mail
---------------------------------------------------------------------------
Type("mail", {
    title = "Mail", showIcon = true,
    icon = { file = "Interface\\Minimap\\Tracking\\Mailbox" },
    events = { "UPDATE_PENDING_MAIL", "MAIL_CLOSED", "PLAYER_ENTERING_WORLD" },
    Text = function()
        if HasNewMail and HasNewMail() then return "New mail", 0.3, 1, 0.3 end
        return "No mail", 0.6, 0.6, 0.6
    end,
    Tooltip = function(_, tt)
        tt:SetText("Mail")
        if HasNewMail and HasNewMail() then
            local senders = { Safe(GetLatestThreeSenders) }
            if #senders == 0 then Line(tt, "New mail waiting") end
            for _, s in ipairs(senders) do Line(tt, "From", s) end
        else
            Line(tt, "Nothing new")
        end
    end,
})

---------------------------------------------------------------------------
-- A character stat
---------------------------------------------------------------------------
local function SpellPower()
    local best = 0
    for school = 2, 7 do best = math.max(best, Safe(GetSpellBonusDamage, school) or 0) end
    return best
end
local STATS = {
    { key = "AP", name = "Attack power", get = function() local b, p, n = Safe(UnitAttackPower, "player") return (b or 0) + (p or 0) + (n or 0) end },
    { key = "RAP", name = "Ranged attack power", get = function() local b, p, n = Safe(UnitRangedAttackPower, "player") return (b or 0) + (p or 0) + (n or 0) end },
    { key = "CRIT", name = "Crit", pct = true, get = function() return Safe(GetCritChance) or 0 end },
    { key = "SPELLCRIT", name = "Spell crit", pct = true, get = function() return Safe(GetSpellCritChance, 2) or 0 end },
    { key = "HIT", name = "Hit", pct = true, get = function() return Safe(GetHitModifier) or 0 end },
    { key = "SP", name = "Spell power", get = SpellPower },
    { key = "HEAL", name = "Healing", get = function() return Safe(GetSpellBonusHealing) or 0 end },
    { key = "ARMOR", name = "Armor", get = function() local _, eff = Safe(UnitArmor, "player") return eff or 0 end },
    { key = "SPEED", name = "Speed", pct = true, get = function() local s = Safe(GetUnitSpeed, "player") return (s or 0) / 7 * 100 end },
    { key = "DODGE", name = "Dodge", pct = true, get = function() return Safe(GetDodgeChance) or 0 end },
    { key = "MP5", name = "Mana regen", get = function() local b, c = Safe(GetManaRegen) return ((c or b or 0) * 5) end },
}
BL.STATS = STATS
local function Stat(b)
    for _, s in ipairs(STATS) do if s.key == b.cfg.settings.stat then return s end end
    return STATS[1]
end
Type("stat", {
    title = "Character stat", showIcon = false, tick = true, steady = 4,
    settings = { stat = "AP" },
    icon = { file = "Interface\\Icons\\Ability_Warrior_BattleShout" },
    Text = function(b)
        local s = Stat(b)
        local v = s.get()
        if not Plain(v) then return "-" end
        return s.pct and ("%s %.1f%%"):format(s.name, v) or ("%s %d"):format(s.name, v)
    end,
    Tooltip = function(_, tt)
        tt:SetText("Character stats")
        for _, s in ipairs(STATS) do
            local v = s.get()
            if Plain(v) then Line(tt, s.name, s.pct and ("%.1f%%"):format(v) or tostring(math.floor(v + 0.5))) end
        end
        Line(tt, "Right-click: next stat. Left-click: character.")
    end,
    Click = function(b, button)
        if button == "RightButton" then
            local cur = Stat(b)
            for i, s in ipairs(STATS) do if s == cur then b.cfg.settings.stat = STATS[i % #STATS + 1].key break end end
        elseif ToggleCharacter then ToggleCharacter("PaperDollFrame") end
    end,
})

---------------------------------------------------------------------------
-- Spacer: an empty block (its side padding is its width)
---------------------------------------------------------------------------
Type("spacer", {
    title = "Spacer", showIcon = false,
    icon = { file = "Interface\\Buttons\\WHITE8X8" },
    Text = function() return "" end,
})

---------------------------------------------------------------------------
-- MMT's team (only while MMT is on and allowed): MMT.status[key] from its heartbeats
---------------------------------------------------------------------------
local function MMT() return ns.Bridge and ns.Bridge.MMT() end
local function MMTOn() return MMT() ~= nil end
local function Members()
    local m = MMT()
    if not (m and type(m.SortedMembers) == "function") then return {}, m end
    return Safe(m.SortedMembers) or {}, m
end
local function Status(m, key) return type(m.status) == "table" and m.status[key] or nil end
local function Name(m, key) return (Safe(m.ShownName, key)) or tostring(key) end

Type("teamgold", {
    title = "Team gold (MMT)", showIcon = false, available = MMTOn, tick = true,
    icon = { file = "Interface\\MoneyFrame\\UI-GoldIcon" },
    Text = function(b)
        local keys, m = Members()
        if not m then return "" end
        local sum = 0
        for _, k in ipairs(keys) do
            local s = Status(m, k)
            local v = (m.IsSelf and m.IsSelf(k)) and GetMoney() or (s and tonumber(s.money))
            sum = sum + (v or 0)
        end
        return Money(sum, { coinIcons = true, abbreviate = true })
    end,
    Tooltip = function(_, tt)
        local keys, m = Members()
        tt:SetText("Team gold")
        if not m then return end
        local all = { showSmall = false, coinIcons = true }
        for _, k in ipairs(keys) do
            local s = Status(m, k)
            local v = (m.IsSelf and m.IsSelf(k)) and GetMoney() or (s and tonumber(s.money))
            Line(tt, Name(m, k), v and Money(v, all) or "?")
        end
    end,
})

Type("teamonline", {
    title = "Team online (MMT)", showIcon = false, available = MMTOn, tick = true, steady = 3,
    icon = { atlas = "socialqueuing-icon-group", file = "Interface\\FriendsFrame\\UI-Toast-FriendOnlineIcon" },
    Text = function()
        local keys, m = Members()
        if not m then return "" end
        local on = 0
        for _, k in ipairs(keys) do if (m.IsSelf and m.IsSelf(k)) or Safe(m.IsOnline, k) then on = on + 1 end end
        return ("%d/%d"):format(on, #keys), Grade(#keys > 0 and on / #keys or 0)
    end,
    Tooltip = function(_, tt)
        local keys, m = Members()
        tt:SetText("Team")
        if not m then return end
        for _, k in ipairs(keys) do
            local on = (m.IsSelf and m.IsSelf(k)) or Safe(m.IsOnline, k)
            tt:AddDoubleLine(Name(m, k), on and "online" or "offline", 1, 1, 1, on and 0.3 or 0.6, on and 1 or 0.6, on and 0.3 or 0.6)
        end
    end,
})

Type("layer", {
    title = "Layer (MMT)", showIcon = false, available = MMTOn, tick = true, steady = 2,
    icon = { file = "Interface\\Icons\\INV_Misc_Map_02" },
    Text = function()
        local m = MMT()
        if not m then return "" end
        local l = m.layer
        return l and ("Layer " .. tostring(l)) or "Layer ?"
    end,
    Tooltip = function(_, tt)
        local keys, m = Members()
        tt:SetText("Layers (MMT)")
        if not m then return end
        Line(tt, "You", tostring(m.layer or "?"))
        for _, k in ipairs(keys) do
            if not (m.IsSelf and m.IsSelf(k)) then
                local s = Status(m, k)
                if s and s.layer and s.layer ~= "" then Line(tt, Name(m, k), tostring(s.layer)) end
            end
        end
    end,
})

Type("teambags", {
    title = "Team bag space (MMT)", showIcon = true, available = MMTOn, tick = true, steady = 2,
    icon = { file = "Interface\\Buttons\\Button-Backpack-Up" },
    Text = function()
        local keys, m = Members()
        if not m then return "" end
        local low, who
        for _, k in ipairs(keys) do
            local free
            if m.IsSelf and m.IsSelf(k) then free = BagSpace()
            else local s = Status(m, k) free = s and tonumber(s.free) end
            if free and (not low or free < low) then low, who = free, k end
        end
        if not low then return "-" end
        return ("%d %s"):format(low, Name(m, who)), Grade(low / 20)
    end,
    Tooltip = function(_, tt)
        local keys, m = Members()
        tt:SetText("Free bag slots (team)")
        if not m then return end
        for _, k in ipairs(keys) do
            local free, slots
            if m.IsSelf and m.IsSelf(k) then free, slots = BagSpace()
            else local s = Status(m, k) free, slots = s and tonumber(s.free), s and tonumber(s.slots) end
            Line(tt, Name(m, k), free and (slots and (free .. " / " .. slots) or tostring(free)) or "?")
        end
    end,
})
