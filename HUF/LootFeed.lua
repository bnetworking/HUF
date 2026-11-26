-- HUF: Loot Feed and Faster Looting (General > Loot Feed).
-- Loot Feed: a short stack of rows for what you gain (items, money,
-- reputation, currencies, skill ups). Each row fades out after a few seconds;
-- the same thing again adds to its row instead of opening another. The game's
-- own chat lines are read with its localized format strings, so every client
-- language works.
-- Faster Looting: every slot is taken the moment the loot window opens;
-- Shift held while looting shows the normal window.

local _, ns = ...
local UI = ns.UI

local LF = {}
ns.LootFeed = LF

local FADE_IN, FADE_OUT = 0.2, 0.6
local MONEY_ICON = "Interface\\Icons\\INV_Misc_Coin_02"
local REP_ICON = "Interface\\Icons\\INV_Misc_Note_02"
local SKILL_ICON = "Interface\\Icons\\INV_Misc_Book_08"
local CURRENCY_ICON = "Interface\\Icons\\INV_Misc_Token_ArgentDawn"
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

-- accent colours of rows without an item quality
local COLORS = {
    money = { 1.00, 0.82, 0.00 },
    rep = { 0.30, 0.85, 0.30 },
    skill = { 0.35, 0.65, 1.00 },
    currency = { 1.00, 1.00, 1.00 },
}

local function Cfg() return ns.db.lootFeed end

local GetItemInfo = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo

local function QualityColor(q)
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q or 1]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

local function Money(copper)
    if ns.Bags and ns.Bags.Money then return ns.Bags.Money(copper) end
    return GetCoinTextureString and GetCoinTextureString(copper) or tostring(copper)
end

-- Auctionator's price of its last scan (nil: not installed, never seen)
local function AuctionPrice(link)
    local api = type(Auctionator) == "table" and Auctionator.API and Auctionator.API.v1
    if not (api and api.GetAuctionPriceByItemLink) then return nil end
    local ok, price = pcall(api.GetAuctionPriceByItemLink, "HUF", link)
    if ok and type(price) == "number" and price > 0 then return price end
end
LF.HasAuctionator = function()
    return type(Auctionator) == "table" and Auctionator.API and Auctionator.API.v1 and true or false
end

---------------------------------------------------------------------------
-- Chat line matching: a Blizzard format string as a Lua pattern
---------------------------------------------------------------------------
local compiled = {}
local function Compile(fmt, anchored)
    local parts, i, first = {}, 1, nil
    while true do
        local s, e, pos, kind = fmt:find("%%(%d?)%$?([sd])", i)
        parts[#parts + 1] = (fmt:sub(i, s and s - 1):gsub("[%^%$%(%)%.%[%]%*%+%-%?%%]", "%%%0"))
        if not s then break end
        first = first or tonumber(pos)
        parts[#parts + 1] = kind == "d" and "(%d+)" or "(.-)"
        i = e + 1
    end
    local p = table.concat(parts)
    return { pat = anchored and ("^" .. p .. "$") or p, swap = first == 2 }
end
local function Match(key, text, loose)
    local c = compiled[key]
    if c == nil then
        local fmt = _G[key]
        c = type(fmt) == "string" and fmt ~= "" and Compile(fmt, not loose) or false
        compiled[key] = c
    end
    if not c then return end
    local a, b = text:match(c.pat)
    if c.swap then return b, a end
    return a, b
end

---------------------------------------------------------------------------
-- The feed frame and its rows
---------------------------------------------------------------------------
local anchor
local active, pool = {}, {}

local function Accent(r, g, b)
    local c = Cfg()
    if c.accentQuality then return r, g, b end
    local a = c.accentColor or { r = 1, g = 1, b = 1 }
    return a.r, a.g, a.b
end

local function StyleRow(row)
    local c = Cfg()
    local w, h = c.width, c.height
    row:SetSize(w, h)
    row.bg:SetColorTexture(0.05, 0.05, 0.06, c.bgAlpha or 0.6)
    local size, pos = math.max(1, c.accentSize or 3), c.accentPos or "LEFT"
    local bar = row.bar
    bar:ClearAllPoints()
    local padL, padR = 0, 0
    if pos == "RIGHT" then
        bar:SetPoint("TOPRIGHT") bar:SetPoint("BOTTOMRIGHT") bar:SetWidth(size)
        padR = size
    elseif pos == "TOP" then
        bar:SetPoint("TOPLEFT") bar:SetPoint("TOPRIGHT") bar:SetHeight(size)
    elseif pos == "BOTTOM" then
        bar:SetPoint("BOTTOMLEFT") bar:SetPoint("BOTTOMRIGHT") bar:SetHeight(size)
    else
        bar:SetPoint("TOPLEFT") bar:SetPoint("BOTTOMLEFT") bar:SetWidth(size)
        padL = size
    end
    local isz = math.max(8, h - 8)
    row.icon:SetSize(isz, isz)
    row.icon:ClearAllPoints()
    row.icon:SetPoint("LEFT", padL + 4, 0)
    ns.ApplyFont(row.text, c.font, c.fontSize, c.outline)
    ns.ApplyFont(row.value, c.font, math.max(6, c.fontSize - 1), c.outline)
    row.value:ClearAllPoints()
    row.value:SetPoint("RIGHT", -(padR + 6), 0)
    row.text:ClearAllPoints()
    row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.text:SetPoint("RIGHT", row.value, "LEFT", -6, 0)
    local r, g, b = Accent(row.r or 1, row.g or 1, row.b or 1)
    bar:SetColorTexture(r, g, b, 1)
    -- option qualityBorder: OFF | ICON | ROW, in the quality colour (money gold, ...)
    local mode, t = c.qualityBorder or "OFF", math.max(0.1, tonumber(c.qualityBorderSize) or 1)
    -- the game draws nothing under about half a screen pixel: thinner than
    -- one pixel becomes one pixel, fainter by as much
    local px = 1
    if PixelUtil and PixelUtil.GetPixelToUIUnitFactor then
        local ok, f = pcall(PixelUtil.GetPixelToUIUnitFactor)
        local s = row:GetEffectiveScale()
        if ok and f and s and s > 0 then px = f / s end
    end
    local alpha = 1
    if t < px then alpha, t = t / px, px end
    local e = row.edges
    for _, tex in ipairs(e) do tex:ClearAllPoints() tex:SetShown(mode ~= "OFF") end
    if mode ~= "OFF" then
        local target = mode == "ICON" and row.icon or row
        local o = mode == "ICON" and t or 0       -- the icon's border sits outside it, the row's inside
        e[1]:SetPoint("TOPLEFT", target, "TOPLEFT", -o, o) e[1]:SetPoint("TOPRIGHT", target, "TOPRIGHT", o, o) e[1]:SetHeight(t)
        e[2]:SetPoint("BOTTOMLEFT", target, "BOTTOMLEFT", -o, -o) e[2]:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", o, -o) e[2]:SetHeight(t)
        e[3]:SetPoint("TOPLEFT", e[1], "BOTTOMLEFT") e[3]:SetPoint("BOTTOMLEFT", e[2], "TOPLEFT") e[3]:SetWidth(t)
        e[4]:SetPoint("TOPRIGHT", e[1], "BOTTOMRIGHT") e[4]:SetPoint("BOTTOMRIGHT", e[2], "TOPRIGHT") e[4]:SetWidth(t)
        local qr, qg, qb = row.r or 1, row.g or 1, row.b or 1
        for _, tex in ipairs(e) do tex:SetColorTexture(qr, qg, qb, alpha) end
    end
end

local function NewRow()
    local row = table.remove(pool)
    if row then return row end
    row = CreateFrame("Frame", nil, anchor)
    row:EnableMouse(false)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bar = row:CreateTexture(nil, "ARTWORK")
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.edges = {}
    for k = 1, 4 do
        row.edges[k] = row:CreateTexture(nil, "OVERLAY", nil, 7)
        row.edges[k]:Hide()
    end
    row.text = row:CreateFontString(nil, "OVERLAY")
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    row.value = row:CreateFontString(nil, "OVERLAY")
    row.value:SetJustifyH("RIGHT")
    row.value:SetSpacing(1)
    -- option tooltips; items / currencies (data.link): their tooltip on hover; a click pins
    -- it (as a chat link click does), shift-click links it in chat,
    -- ctrl-click the dressing room; a row under the mouse doesn't fade
    row:SetScript("OnEnter", function(self)
        local link = self.data and self.data.link
        if not link then return end
        self.hover = true
        self:SetAlpha(1)
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        pcall(GameTooltip.SetHyperlink, GameTooltip, link)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function(self)
        self.hover = nil
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
    row:SetScript("OnMouseUp", function(self, button)
        local link = self.data and self.data.link
        if not link then return end
        local full = link
        if link:find("^item:") and GetItemInfo then
            local _, l = GetItemInfo(link)
            full = l or full
        elseif link:find("^currency:") and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyLink then
            local ok, l = pcall(C_CurrencyInfo.GetCurrencyLink, tonumber(link:match("%d+")), 1)
            full = ok and l or full
        end
        local handled = false
        if IsModifiedClick() and HandleModifiedItemClick then
            local ok, r = pcall(HandleModifiedItemClick, full)
            handled = ok and r
        end
        if not handled and SetItemRef then
            if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
            pcall(SetItemRef, link, full, button or "LeftButton")
        end
    end)
    return row
end

local function Layout()
    local c = Cfg()
    local gap = c.spacing or 2
    for i, row in ipairs(active) do
        row:ClearAllPoints()
        local off = (i - 1) * (c.height + gap)
        if c.grow == "DOWN" then
            row:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, -off)
        else
            row:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 0, off)
        end
    end
end

local function Release(i)
    local row = table.remove(active, i)
    row:Hide()
    if row.hover and GameTooltip:IsOwned(row) then GameTooltip:Hide() end
    row.key, row.data, row.hover = nil, nil, nil
    row:EnableMouse(false)
    pool[#pool + 1] = row
end

local function Draw(row)
    local d = row.data
    row.icon:SetTexture(d.icon or UNKNOWN_ICON)
    local text = d.text
    if (d.count or 1) > 1 then text = d.count .. "x " .. text end
    row.text:SetText(text)
    row.value:SetText(d.value and d.value(d.count or 1) or "")
end

local function OnUpdate()
    local now, removed = GetTime(), false
    for i = #active, 1, -1 do
        local row = active[i]
        -- hovered, or an example row while frames are unlocked: it stays
        if row.hover or (ns.unlocked and row.key and row.key:find("^sample:")) then
            row.expire = math.max(row.expire, now + 1)
        end
        local left = row.expire - now
        if row.hover or (ns.unlocked and row.key and row.key:find("^sample:")) then
            row:SetAlpha(1)
        elseif left <= 0 then
            local a = 1 + left / FADE_OUT
            if a <= 0 then Release(i) removed = true else row:SetAlpha(a) end
        else
            row:SetAlpha(math.min(1, (now - row.born) / FADE_IN))
        end
    end
    if #active == 0 then anchor:SetScript("OnUpdate", nil) elseif removed then Layout() end
end

-- a gain: key groups repeats, data = { icon, text, r, g, b, count, value(count) }
local function Push(key, data)
    local c = Cfg()
    if not (c.enabled and anchor) then return end
    local now = GetTime()
    for i, row in ipairs(active) do
        if row.key == key then
            row.data.count = (row.data.count or 1) + (data.count or 1)
            table.remove(active, i)
            table.insert(active, 1, row)
            row.expire = now + c.duration
            row:SetAlpha(1)
            Draw(row)
            Layout()
            return
        end
    end
    while #active >= math.max(1, c.maxRows) do Release(#active) end
    local row = NewRow()
    row.key, row.data = key, data
    row:EnableMouse(data.link and Cfg().tooltips and true or false)
    row.r, row.g, row.b = data.r, data.g, data.b
    StyleRow(row)
    Draw(row)
    row.born, row.expire = now, now + c.duration
    row:SetAlpha(0)
    row:Show()
    table.insert(active, 1, row)
    Layout()
    anchor:SetScript("OnUpdate", OnUpdate)
end

---------------------------------------------------------------------------
-- Sources
---------------------------------------------------------------------------
-- who: the looter's shown name for someone else's loot (nil: your own);
-- class: their class (the name in its colour, option classColors)
local function ShowItem(link, count, retried, who, class)
    if not GetItemInfo then return end
    local name, _, quality, _, _, _, _, _, _, icon, sellPrice = GetItemInfo(link)
    if not name then
        -- not cached yet: once more when the client has it
        if not retried and Item and Item.CreateFromItemLink then
            Item:CreateFromItemLink(link):ContinueOnItemLoad(function() ShowItem(link, count, true, who, class) end)
        end
        return
    end
    local c = Cfg()
    if (quality or 0) < (c.minQuality or 0) then return end
    local r, g, b = QualityColor(quality)
    local hex = ("|cff%02x%02x%02x"):format(r * 255, g * 255, b * 255)
    local text = hex .. name .. "|r"
    if who then
        local cc = c.classColors ~= false and class and ns.ClassColor(class)
        local nameHex = cc and ("|cff%02x%02x%02x"):format(cc.r * 255, cc.g * 255, cc.b * 255) or "|cffaaaaaa"
        text = nameHex .. who .. ":|r " .. text
    end
    Push("item:" .. name .. (who and ("@" .. who) or ""), {
        icon = icon, text = text, r = r, g = g, b = b, count = count, link = link,
        value = function(n)
            local lines = {}
            if c.vendorPrice and (sellPrice or 0) > 0 then lines[#lines + 1] = Money(sellPrice * n) end
            -- grey (poor) items: the vendor price only
            if c.auctionPrice and (quality or 0) > 0 then
                local ah = AuctionPrice(link)
                if ah then lines[#lines + 1] = "|cff9d9d9dAH|r " .. Money(ah * n) end
            end
            return table.concat(lines, "\n")
        end,
    })
end

-- own loot only; the multiple formats (link and count) first: the single
-- ones match their lines too
local ITEM_KEYS = {
    "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_SELF",
    "LOOT_ITEM_PUSHED_SELF_MULTIPLE", "LOOT_ITEM_PUSHED_SELF",
    "LOOT_ITEM_BONUS_ROLL_SELF_MULTIPLE", "LOOT_ITEM_BONUS_ROLL_SELF",
    "LOOT_ITEM_CREATED_SELF_MULTIPLE", "LOOT_ITEM_CREATED_SELF",
}
---------------------------------------------------------------------------
-- Other people's loot (option "Show loot of": SELF / TEAM / GROUP)
-- Their chat lines ("Name receives loot: ...") are read outside instances
-- (inside, the game makes them secret); for the MMT team MMT also passes
-- each client's own loot on (MMT.OnTeamLoot), which works in instances too.
-- The same item from both ways within a few seconds shows once.
---------------------------------------------------------------------------
local OTHER_KEYS = {
    "LOOT_ITEM_MULTIPLE", "LOOT_ITEM",
    "LOOT_ITEM_PUSHED_MULTIPLE", "LOOT_ITEM_PUSHED",
    "LOOT_ITEM_BONUS_ROLL_MULTIPLE", "LOOT_ITEM_BONUS_ROLL",
}
-- every capture of a format, in the format's argument order (%1$s, %2$s ...)
local allCompiled = {}
local function MatchAll(key, text)
    local c = allCompiled[key]
    if c == nil then
        local fmt = _G[key]
        if type(fmt) == "string" and fmt ~= "" then
            local parts, order, i, n = {}, {}, 1, 0
            while true do
                local s, e, pos, kind = fmt:find("%%(%d?)%$?([sd])", i)
                parts[#parts + 1] = (fmt:sub(i, s and s - 1):gsub("[%^%$%(%)%.%[%]%*%+%-%?%%]", "%%%0"))
                if not s then break end
                n = n + 1
                order[n] = tonumber(pos) or n
                parts[#parts + 1] = kind == "d" and "(%d+)" or "(.-)"
                i = e + 1
            end
            c = { pat = "^" .. table.concat(parts) .. "$", order = order }
        else
            c = false
        end
        allCompiled[key] = c
    end
    if not c then return nil end
    local caps = { text:match(c.pat) }
    if #caps == 0 then return nil end
    local out = {}
    for k, at in ipairs(c.order) do out[at] = caps[k] end
    return out
end
-- the looter as shown (MMT's privacy name for a team member), or nil when
-- the setting leaves this person out
local function Looter(name)
    local who = LF.Who()
    if who == "SELF" or type(name) ~= "string" or name == "" or ns.IsSecret(name) then return nil end
    local M = _G.MMT
    local key = type(M) == "table" and type(M.Resolve) == "function" and M.Resolve(name) or nil
    if who == "TEAM" and not key then return nil end
    if key and type(M.ShownName) == "function" then
        local ok, shown = pcall(M.ShownName, key)
        if ok and type(shown) == "string" and shown ~= "" then return shown end
    end
    return (name:gsub("%-.*$", ""))
end
local recent = {}

-- a looter's class: MMT's team list (key), else the group member of that name
local function ClassOf(name, key)
    local M = _G.MMT
    if key and type(M) == "table" and type(M.db) == "table" and type(M.db.team) == "table" then
        local m = M.db.team[key]
        if type(m) == "table" and type(m.class) == "string" and m.class ~= "" then return m.class end
    end
    local want = type(name) == "string" and name:gsub("%-.*$", "") or nil
    if not want then return nil end
    local units = { "player", "party1", "party2", "party3", "party4" }
    if IsInRaid() then for i = 1, GetNumGroupMembers() do units[#units + 1] = "raid" .. i end end
    for _, unit in ipairs(units) do
        local ok, n = pcall(UnitName, unit)
        if ok and type(n) == "string" and not ns.IsSecret(n) and n == want then
            local okC, _, class = pcall(UnitClass, unit)
            if okC and type(class) == "string" and not ns.IsSecret(class) then return class end
        end
    end
    return nil
end

-- whose loot: the setting; not set: the MMT team when MMT is loaded, else
-- only you; "team" without MMT: only you
function LF.HasMMT()
    local M = _G.MMT
    return type(M) == "table" and type(M.Resolve) == "function"
end
function LF.Who()
    local w = Cfg().who
    if w == nil then w = LF.HasMMT() and "TEAM" or "SELF" end
    if w == "TEAM" and not LF.HasMMT() then w = "SELF" end
    return w
end
local function Fresh(who, link)
    local id = who .. "|" .. (link:match("item:(%d+)") or link)
    local now = GetTime()
    if recent[id] and now - recent[id] < 4 then return false end
    recent[id] = now
    return true
end
local function OnOtherLoot(text, sender)
    for _, key in ipairs(OTHER_KEYS) do
        local caps = MatchAll(key, text)
        if caps then
            local name, item, count = caps[1], caps[2], caps[3]
            if type(sender) == "string" and sender ~= "" and not ns.IsSecret(sender) then name = sender end
            local who = Looter(name)
            if not who then return end
            local M = _G.MMT
            local key = type(M) == "table" and type(M.Resolve) == "function" and M.Resolve(name) or nil
            local link = type(item) == "string" and item:match("|H(item:[^|]+)|h")
            if link and Fresh(who, link) then ShowItem(link, tonumber(count) or 1, nil, who, ClassOf(name, key)) end
            return
        end
    end
end
-- MMT: a team member's own loot, sent by their client
function LF.TeamLoot(key, link, count)
    local c = Cfg()
    local w = LF.Who()
    if not (c.enabled and (w == "TEAM" or w == "GROUP")) then return end
    local M = _G.MMT
    local who
    if type(M) == "table" and type(M.ShownName) == "function" then
        local ok, shown = pcall(M.ShownName, key)
        who = ok and shown or nil
    end
    who = type(who) == "string" and who ~= "" and who or tostring(key):gsub("%-.*$", "")
    if type(link) == "string" and Fresh(who, link) then
        ShowItem(link, tonumber(count) or 1, nil, who, ClassOf(tostring(key), key))
    end
end
ns.OnLogin(function()
    local M = _G.MMT
    if type(M) == "table" and type(M.OnTeamLoot) == "function" then
        pcall(M.OnTeamLoot, function(key, link, count) pcall(LF.TeamLoot, key, link, count) end)
    end
end)

local function OnLoot(text, sender)
    for _, key in ipairs(ITEM_KEYS) do
        local item, count = Match(key, text)
        if item then
            local link = item:match("|H(item:[^|]+)|h")
            if not link then
                -- some lines (fishing, crafting) carry a plain [Name]
                local nm = item:match("^%[(.-)%]$")
                local id = nm and C_Item and C_Item.GetItemInfoInstant and C_Item.GetItemInfoInstant(nm)
                link = id and ("item:" .. id)
            end
            if link then ShowItem(link, tonumber(count) or 1) end
            return
        end
    end
    if LF.Who() ~= "SELF" then OnOtherLoot(text, sender) end
end

local COIN_KEYS = { GOLD_AMOUNT = 10000, SILVER_AMOUNT = 100, COPPER_AMOUNT = 1 }
local function ShowMoney(copper)
    local col = COLORS.money
    Push("money", {
        icon = MONEY_ICON, text = MONEY or "Money", r = col[1], g = col[2], b = col[3], count = 1, amount = copper,
        value = function() return "" end,
    })
    -- money adds up its copper, not a count
    for _, row in ipairs(active) do
        if row.key == "money" then
            local d = row.data
            d.total = (d.total or 0) + copper
            d.count = 1
            local total = d.total
            d.value = function() return Money(total) end
            Draw(row)
        end
    end
end
local function OnMoney(text)
    local copper = 0
    for key, mult in pairs(COIN_KEYS) do
        local n = Match(key, text, true)
        if n then copper = copper + tonumber(n) * mult end
    end
    if copper > 0 then ShowMoney(copper) end
end

local function ShowReputation(faction, delta)
    local col = COLORS.rep
    local key = "rep:" .. faction
    local total = delta
    for _, row in ipairs(active) do
        if row.key == key then total = (row.data.total or 0) + delta end
    end
    Push(key, { icon = REP_ICON, text = faction, r = col[1], g = col[2], b = col[3], count = 1, value = function() return "" end })
    for _, row in ipairs(active) do
        if row.key == key then
            row.data.total, row.data.count = total, 1
            row.data.value = function()
                return (total >= 0 and "|cff40ff40+" or "|cffff4040") .. total .. "|r"
            end
            Draw(row)
        end
    end
end
local REP_UP = { "FACTION_STANDING_INCREASED_DOUBLE_BONUS", "FACTION_STANDING_INCREASED_BONUS",
                 "FACTION_STANDING_INCREASED_ACH_BONUS", "FACTION_STANDING_INCREASED" }
local function OnFaction(text)
    for _, key in ipairs(REP_UP) do
        local faction, amount = Match(key, text, true)
        if faction and tonumber(amount) then return ShowReputation(faction, tonumber(amount)) end
    end
    local faction, amount = Match("FACTION_STANDING_DECREASED", text, true)
    if faction and tonumber(amount) then ShowReputation(faction, -tonumber(amount)) end
end

local function OnCurrency(text)
    for _, key in ipairs({ "CURRENCY_GAINED_MULTIPLE_BONUS", "CURRENCY_GAINED_MULTIPLE", "CURRENCY_GAINED" }) do
        local cur, count = Match(key, text)
        if cur then
            local id = tonumber(cur:match("currency:(%d+)"))
            local name, icon, quality = cur:match("%[(.-)%]"), CURRENCY_ICON, nil
            local info = id and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(id)
            if type(info) == "table" then
                name = info.name or name
                icon = info.iconFileID or icon
                quality = info.quality
            end
            if not name then return end
            local r, g, b = 1, 1, 1
            if quality then r, g, b = QualityColor(quality) end
            Push("cur:" .. name, { icon = icon, text = name, r = r, g = g, b = b, count = tonumber(count) or 1,
                link = id and ("currency:" .. id) or nil })
            return
        end
    end
end

local function OnSkill(text)
    local skill, rank = Match("ERR_SKILL_UP_SI", text)
    if not skill then return end
    local col = COLORS.skill
    Push("skill:" .. skill, {
        icon = SKILL_ICON, text = skill, r = col[1], g = col[2], b = col[3], count = 1,
        value = function() return "|cffffffff" .. tostring(rank) .. "|r" end,
    })
    for _, row in ipairs(active) do
        if row.key == "skill:" .. skill then
            row.data.count = 1
            row.data.value = function() return "|cffffffff" .. tostring(rank) .. "|r" end
            Draw(row)
        end
    end
end

local CHAT = {
    CHAT_MSG_LOOT = { "items", OnLoot },
    CHAT_MSG_MONEY = { "money", OnMoney },
    CHAT_MSG_COMBAT_FACTION_CHANGE = { "reputation", OnFaction },
    CHAT_MSG_CURRENCY = { "currency", OnCurrency },
    CHAT_MSG_SKILL = { "skills", OnSkill },
}

---------------------------------------------------------------------------
-- Faster Looting
---------------------------------------------------------------------------
local lastLoot = 0
-- master loot: is it on (any looter); taking such a slot as the master looter
-- opens the game's assign / roll menu, so those slots stay in the window
local function MasterLoot()
    local m
    if C_PartyInfo and C_PartyInfo.GetLootMethod then
        local ok, v = pcall(C_PartyInfo.GetLootMethod)
        if ok then m = v end
        if Enum and Enum.LootMethod and m ~= nil then
            return m == (Enum.LootMethod.Masterlooter or Enum.LootMethod.MasterLooter)
        end
    end
    if GetLootMethod then
        local ok, v = pcall(GetLootMethod)
        if ok then return v == "master" end
    end
    return false
end

local function FastLoot()
    if IsShiftKeyDown() then return end
    local now = GetTime()
    if now - lastLoot < 0.3 then return end
    lastLoot = now
    local master = MasterLoot()
    local threshold = master and GetLootThreshold and GetLootThreshold() or nil
    local n = GetNumLootItems() or 0
    for i = n, 1, -1 do
        local _, _, _, _, quality, locked = GetLootSlotInfo(i)
        -- under master loot, items at or above the threshold wait for the
        -- master looter's choice (unknown quality counts as "wait")
        local held = master and (type(quality) ~= "number" or not threshold or quality >= threshold)
        local coin = GetLootSlotType and Enum and Enum.LootSlotType and GetLootSlotType(i) == Enum.LootSlotType.Money
        if not locked and (coin or not held) then LootSlot(i) end
    end
end

---------------------------------------------------------------------------
-- Setup
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, text, sender)
    if event == "LOOT_READY" then
        FastLoot()
        return
    end
    local h = CHAT[event]
    if h and type(text) == "string" and not ns.IsSecret(text) then
        local ok, err = pcall(h[2], text, sender)
        if not ok then ns.LogError("lootfeed", err) end
    end
end)

function LF.Frame() return anchor end

function LF.Place()
    if not anchor then return end
    local c = Cfg()
    local p = c.point
    anchor:ClearAllPoints()
    anchor:SetPoint(p[1], UIParent, p[2], p[3] or 0, p[4] or 0)
    local rows = math.max(1, c.maxRows)
    anchor:SetSize(c.width, rows * c.height + (rows - 1) * (c.spacing or 2))
end

function LF.Apply()
    if not ns.db then return end
    local c = Cfg()
    events:UnregisterAllEvents()
    if c.fastLoot then events:RegisterEvent("LOOT_READY") end
    if c.enabled then
        if not anchor then
            anchor = CreateFrame("Frame", "HUF_LootFeed", UIParent)
            anchor:SetFrameStrata("MEDIUM")
            anchor:EnableMouse(false)
        end
        LF.Place()
        anchor:Show()
        local src = c.sources or {}
        for ev, h in pairs(CHAT) do
            if src[h[1]] ~= false then events:RegisterEvent(ev) end
        end
        for _, row in ipairs(active) do StyleRow(row) end
        while #active > math.max(1, c.maxRows) do Release(#active) end
        Layout()
    elseif anchor then
        for i = #active, 1, -1 do Release(i) end
        anchor:Hide()
    end
end

-- a few made-up rows to look at the style
local SAMPLES = {
    { key = "item", icon = "Interface\\Icons\\INV_Fabric_Linen_01", name = "Linen Cloth", q = 1, count = 4, sell = 13, ah = 180 },
    { key = "money", copper = 23456 },
    { key = "item", icon = "Interface\\Icons\\INV_Sword_04", name = "Sample Blade", q = 2, count = 1, sell = 1675, ah = 9800 },
    { key = "rep", name = "Sample Faction", amount = 25 },
    { key = "item", icon = "Interface\\Icons\\INV_Jewelry_Ring_03", name = "Sample Ring", q = 3, count = 1, sell = 4210 },
    { key = "skill", name = "Mining", rank = 87 },
    { key = "cur", icon = "Interface\\Icons\\INV_Misc_Token_ArgentDawn", name = "Sample Token", count = 2 },
    { key = "item", icon = "Interface\\Icons\\INV_Misc_Gem_Pearl_04", name = "Sample Pearl", q = 0, count = 1, sell = 5 },
}
function LF.ShowExamples()
    local c = Cfg()
    if not c.enabled then return end
    for i, s in ipairs(SAMPLES) do
        C_Timer.After((i - 1) * 0.25, function()
            if s.key == "item" then
                if s.q < (c.minQuality or 0) then return end
                local r, g, b = QualityColor(s.q)
                local hex = ("|cff%02x%02x%02x"):format(r * 255, g * 255, b * 255)
                Push("sample:" .. s.name, { icon = s.icon, text = hex .. s.name .. "|r", r = r, g = g, b = b, count = s.count,
                    value = function(n)
                        local lines = {}
                        if c.vendorPrice and s.sell then lines[#lines + 1] = Money(s.sell * n) end
                        if c.auctionPrice and s.ah and s.q > 0 then lines[#lines + 1] = "|cff9d9d9dAH|r " .. Money(s.ah * n) end
                        return table.concat(lines, "\n")
                    end })
            elseif s.key == "money" then
                ShowMoney(s.copper)
            elseif s.key == "rep" then
                ShowReputation(s.name, s.amount)
            elseif s.key == "skill" then
                local col = COLORS.skill
                Push("sample:" .. s.name, { icon = SKILL_ICON, text = s.name, r = col[1], g = col[2], b = col[3], count = 1,
                    value = function() return "|cffffffff" .. s.rank .. "|r" end })
            elseif s.key == "cur" then
                Push("sample:" .. s.name, { icon = s.icon, text = s.name, r = 1, g = 1, b = 1, count = s.count })
            end
        end)
    end
end

ns.OnLogin(function() LF.Apply() end)
ns.OnRefresh(function() LF.Apply() end)
