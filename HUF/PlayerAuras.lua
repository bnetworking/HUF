-- HUF: buff bar and debuff bar (replacing Blizzard's icons at the top right).
-- Forever has no SecureAuraHeaderTemplate. With the game's aura containers
-- (CustomAuraContainerTemplate, as EllesmereUI's player aura bars) the engine
-- reads, sorts and lays out the auras and its buttons cancel a buff on
-- right-click, also in combat (SetCancelAuraButtons). Without containers HUF
-- draws the icons itself from your own auras (C_UnitAuras on UNIT_AURA; then
-- right-click cancels out of combat only).
-- Settings: ns.db.auraBars.buffs / .debuffs.

local _, ns = ...
local PA = {}
ns.PlayerAuras = PA

local A = ns.ACCENT
local function IsSecret(v) return issecretvalue and issecretvalue(v) or false end
local function Plain(v) return v ~= nil and not IsSecret(v) end

local KINDS = { buffs = "HELPFUL", debuffs = "HARMFUL" }
local bars = {}                  -- kind -> bar frame with .icons (or the engine container)
local engineBars = {}            -- kind -> the game's aura container
local engineButtons = { buffs = {}, debuffs = {} }
local movers = {}

local function S(kind) return ns.db.auraBars[kind] end

local DEBUFF_COLORS = {
    Magic = { 0.20, 0.60, 1.00 }, Curse = { 0.60, 0.00, 1.00 }, Disease = { 0.60, 0.40, 0.00 },
    Poison = { 0.00, 0.60, 0.00 }, none = { 0.80, 0.00, 0.00 },
}

---------------------------------------------------------------------------
-- Layout: growth direction -> where icon n goes
---------------------------------------------------------------------------
-- grow: "<icons>_<new lines>", e.g. LEFT_DOWN = icons right to left, new rows
-- below; DOWN_RIGHT = icons top to bottom, new columns to the right. Older
-- single values (LEFT / RIGHT / DOWN / UP) still read.
local OLD_GROW = { LEFT = "LEFT_DOWN", RIGHT = "RIGHT_DOWN", DOWN = "DOWN_RIGHT", UP = "UP_RIGHT" }
local function Grow(s)
    local g = OLD_GROW[s.grow] or s.grow or "LEFT_DOWN"
    local a, b = g:match("^(%u+)_(%u+)$")
    if not a then return "LEFT", "DOWN" end
    return a, b
end
PA.Grow = Grow

-- first icon's corner, the horizontal and vertical growth, whether icons run in columns
local function Flow(s)
    local a, b = Grow(s)
    local vertical = (a == "UP" or a == "DOWN")
    local h = vertical and b or a
    local v = vertical and a or b
    local corner = (v == "DOWN" and "TOP" or "BOTTOM") .. (h == "LEFT" and "RIGHT" or "LEFT")
    return corner, h, v, vertical
end
PA.Flow = Flow

local function Geometry(s)
    local step = s.size + s.padding
    local lineStep = s.size + s.padding + ((s.timer and s.timerPos == "BELOW") and (s.timerSize + 2) or 0)
    local corner, h, v, vertical = Flow(s)
    local perLine, lines
    if vertical then perLine, lines = s.rows, s.columns else perLine, lines = s.columns, s.rows end
    local t = { perLine = math.max(1, perLine), lines = math.max(1, lines), point = corner }
    local hs = (h == "RIGHT") and step or -step
    local vs = (v == "UP") and lineStep or -lineStep
    if vertical then
        t.x, t.y, t.wx, t.wy = 0, vs, hs, 0
        t.w = t.lines * step - s.padding
        t.h = t.perLine * lineStep - s.padding
    else
        t.x, t.y, t.wx, t.wy = hs, 0, 0, vs
        t.w = t.perLine * step - s.padding
        t.h = t.lines * lineStep - s.padding
    end
    return t
end
PA.Geometry = Geometry

---------------------------------------------------------------------------
-- Time text
---------------------------------------------------------------------------
local function FormatTime(sec, fmt)
    if sec >= 3600 then
        if fmt == "MM" then return ("%dm"):format(math.floor(sec / 60 + 0.5)) end
        local h = math.floor(sec / 3600)
        return ("%d:%02d"):format(h, math.floor((sec - h * 3600) / 60))
    elseif sec >= 60 then
        return ("%dm"):format(math.floor(sec / 60 + 0.5))
    elseif sec >= 10 then
        return ("%d"):format(math.floor(sec + 0.5))
    end
    return ("%.1f"):format(sec)
end
PA.FormatTime = FormatTime

local function OnUpdate(b, elapsed)
    b.tick = (b.tick or 0) + elapsed
    if b.tick < 0.1 then return end
    b.tick = 0
    local exp = b.expires
    if not exp then b.time:SetText("") return end
    local left = exp - GetTime()
    if left <= 0 then b.time:SetText("") return end
    b.time:SetText(FormatTime(left, S(b.kind).timerFormat))
    if left < 5 then b.time:SetTextColor(1, 0.3, 0.3) else b.time:SetTextColor(1, 1, 1) end
end

---------------------------------------------------------------------------
-- One icon
---------------------------------------------------------------------------
local function OnEnter(b)
    GameTooltip:SetOwner(b, "ANCHOR_BOTTOMLEFT")
    local d = b.data
    if not d then return end
    if d.slot then
        GameTooltip:SetInventoryItem("player", d.slot)
    elseif d.instance and GameTooltip.SetUnitAuraByAuraInstanceID then
        pcall(GameTooltip.SetUnitAuraByAuraInstanceID, GameTooltip, "player", d.instance)
    else
        pcall(GameTooltip.SetUnitAura, GameTooltip, "player", d.index, KINDS[b.kind])
    end
    if b.kind == "buffs" then GameTooltip:AddLine("Right-click: cancel (out of combat)", 0.6, 0.6, 0.6) end
    GameTooltip:Show()
end

local function OnClick(b, button)
    if button ~= "RightButton" or b.kind ~= "buffs" or not b.data then return end
    if InCombatLockdown() then
        ns.Print("Buffs can only be cancelled out of combat.")
        return
    end
    local d = b.data
    if d.slot then
        pcall(CancelItemTempEnchantment, d.slot - 15)
    elseif d.instance and C_UnitAuras and C_UnitAuras.CancelAuraByAuraInstanceID
        and pcall(C_UnitAuras.CancelAuraByAuraInstanceID, "player", d.instance) then
        -- done
    elseif CancelUnitBuff then
        pcall(CancelUnitBuff, "player", d.index, "HELPFUL")
    end
end

local function NewIcon(bar)
    local b = CreateFrame("Button", nil, bar)
    b.kind = bar.kind
    b:RegisterForClicks("RightButtonUp")
    b.border = b:CreateTexture(nil, "BACKGROUND")
    b.border:SetAllPoints()
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cd:SetAllPoints(b.icon)
    b.cd:SetReverse(true)
    b.cd:SetDrawEdge(false)
    if b.cd.SetHideCountdownNumbers then b.cd:SetHideCountdownNumbers(true) end
    local layer = CreateFrame("Frame", nil, b)
    layer:SetAllPoints()
    layer:SetFrameLevel(b.cd:GetFrameLevel() + 2)
    b.time = layer:CreateFontString(nil, "OVERLAY")
    b.count = layer:CreateFontString(nil, "OVERLAY")
    b:SetScript("OnUpdate", OnUpdate)
    b:SetScript("OnEnter", OnEnter)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", OnClick)
    b:Hide()
    return b
end

-- the icon's look
local function Dress(b, s)
    b:SetSize(s.size, s.size)
    local z = math.max(0, math.min(0.4, s.zoom))
    b.icon:SetTexCoord(z, 1 - z, z, 1 - z)
    local bs = s.borderSize
    b.icon:ClearAllPoints()
    b.icon:SetPoint("TOPLEFT", bs, -bs)
    b.icon:SetPoint("BOTTOMRIGHT", -bs, bs)
    b.border:SetShown(bs > 0)
    ns.ApplyFont(b.time, s.font, s.timerSize, s.outline)
    ns.ApplyFont(b.count, s.font, s.countSize, s.outline)
    b.time:ClearAllPoints()
    if s.timerPos == "BELOW" then b.time:SetPoint("TOP", b, "BOTTOM", 0, -1)
    else b.time:SetPoint("BOTTOM", b, "BOTTOM", 0, 2) end
    b.time:SetShown(s.timer)
    b.count:ClearAllPoints()
    b.count:SetPoint("TOPRIGHT", b, "TOPRIGHT", -1, -1)
end

local function Fill(b, d, s)
    b.data = d
    pcall(b.icon.SetTexture, b.icon, d.icon)
    local count = d.count
    if Plain(count) and count > 1 then b.count:SetText(count)
    elseif IsSecret(count) then pcall(b.count.SetText, b.count, count)
    else b.count:SetText("") end
    if Plain(d.expires) and d.expires > 0 then b.expires = d.expires else b.expires = nil b.time:SetText("") end
    b.tick = 1
    if s.swipe and Plain(d.duration) and Plain(d.expires) and d.duration > 0 and d.expires > 0 then
        b.cd:SetCooldown(d.expires - d.duration, d.duration)
        b.cd:Show()
    else
        b.cd:Clear()
        b.cd:Hide()
    end
    local c = s.borderAccent and { r = A[1], g = A[2], b = A[3] } or s.borderColor
    if b.kind == "debuffs" and s.typeColors then
        local t = Plain(d.dispel) and DEBUFF_COLORS[d.dispel] or DEBUFF_COLORS.none
        b.border:SetColorTexture(t[1], t[2], t[3], 1)
    else
        b.border:SetColorTexture(c.r, c.g, c.b, 1)
    end
    b:Show()
end

---------------------------------------------------------------------------
-- Reading your auras
---------------------------------------------------------------------------
local function Collect(kind)
    local list = {}
    local filter = KINDS[kind]
    local now = GetTime()
    if kind == "buffs" and GetWeaponEnchantInfo then
        local ok, hasMain, mainExp, mainCharges, _, hasOff, offExp, offCharges = pcall(GetWeaponEnchantInfo)
        if ok then
            if hasMain then list[#list + 1] = { slot = 16, icon = GetInventoryItemTexture("player", 16), count = mainCharges,
                expires = mainExp and now + mainExp / 1000, duration = 0, order = 0, name = "" } end
            if hasOff then list[#list + 1] = { slot = 17, icon = GetInventoryItemTexture("player", 17), count = offCharges,
                expires = offExp and now + offExp / 1000, duration = 0, order = 0, name = "" } end
        end
    end
    for i = 1, 80 do
        local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, filter)
        if not ok or not a then break end
        list[#list + 1] = { index = i, instance = a.auraInstanceID, icon = a.icon, count = a.applications,
            duration = a.duration, expires = a.expirationTime, dispel = a.dispelName, name = a.name, order = i }
    end
    return list
end

local function SortList(list, s)
    local desc = s.sortDir ~= "+"
    local function key(d)
        if s.sort == "NAME" then return Plain(d.name) and d.name or "" end
        if s.sort == "TIME" then
            -- no end (permanent) counts as the longest
            if Plain(d.expires) and d.expires > 0 then return d.expires end
            return math.huge
        end
        return d.order
    end
    local ok = pcall(table.sort, list, function(a, b)
        local ka, kb = key(a), key(b)
        if ka == kb then return a.order < b.order end
        if desc then return ka > kb end
        return ka < kb
    end)
    if not ok then table.sort(list, function(a, b) return a.order < b.order end) end
end

---------------------------------------------------------------------------
-- Bars
---------------------------------------------------------------------------
-- unlock mode: drag box over a bar
function PA.NewMover(kind)
    -- the box moves itself (nothing may be anchored to an aura container,
    -- and its rect may not be read); the bar follows on drop
    local m = CreateFrame("Button", nil, UIParent)
    m:SetFrameStrata("HIGH")
    m:SetMovable(true)
    m:SetClampedToScreen(true)
    m:EnableMouse(true)
    m:RegisterForDrag("LeftButton")
    m:RegisterForClicks("RightButtonUp")
    ns.UI.Fill(m, A[1], A[2], A[3], 0.15)
    m.border = ns.UI.Border(m, A[1], A[2], A[3], 0.8)
    m.label = m:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    m.label:SetPoint("CENTER")
    m.label:SetText(kind == "buffs" and "Buffs" or "Debuffs")
    m:SetScript("OnDragStart", function()
        m.from = { m:GetLeft(), m:GetTop() }
        ns.Snap.StartDrag(m)
    end)
    m:SetScript("OnDragStop", function()
        ns.Snap.StopDrag(m)
        if m.SetUserPlaced then m:SetUserPlaced(false) end
        local from = m.from
        if not from then return end
        m.from = nil
        local p = S(kind).point
        p[3] = math.floor((p[3] or 0) + (m:GetLeft() or 0) - (from[1] or 0) + 0.5)
        p[4] = math.floor((p[4] or 0) + (m:GetTop() or 0) - (from[2] or 0) + 0.5)
        PA.Apply()
    end)
    m:SetScript("OnClick", function() if ns.OpenConfigTab then ns.OpenConfigTab("aurabars", kind) end end)
    m:Hide()
    movers[kind] = m
    if ns.Snap then ns.Snap.Register(m) end
    -- unlock mode's corner grips: dragging sets how many icons fit across and down (columns /
    -- rows); Shift + drag: the icon size
    if ns.Movers and ns.Movers.AddGrips then
        ns.Movers.AddGrips(m, m, {
            box = m,
            unit = function() return m:GetEffectiveScale() end,
            point = function() return S(kind).point end,
            relayout = function() PA.Apply() end,
            sizer = {
                get = function() local g = Geometry(S(kind)) return g.w, g.h end,
                set = function(w, h)
                    local s = S(kind)
                    local extra = (s.timer and s.timerPos == "BELOW") and (s.timerSize + 2) or 0
                    local across = math.max(1, math.min(40, math.floor((w + s.padding) / (s.size + s.padding) + 0.5)))
                    local down = math.max(1, math.min(10, math.floor((h + s.padding) / (s.size + s.padding + extra) + 0.5)))
                    -- the width holds the columns and the height the rows, whichever way the icons flow
                    s.columns, s.rows = across, down
                    PA.Apply()
                end,
            },
            scaler = {
                get = function() return S(kind).size end,
                set = function(v)
                    S(kind).size = math.max(12, math.min(64, math.floor(v + 0.5)))
                    PA.Apply()
                end,
            },
        })
    end
    return m
end

local function BuildBar(kind)
    if bars[kind] then return bars[kind] end
    local bar = CreateFrame("Frame", "HUF_" .. (kind == "buffs" and "Buffs" or "Debuffs"), UIParent)
    bar.kind = kind
    bar.icons = {}
    bar:SetFrameStrata("LOW")
    bar:SetClampedToScreen(true)
    bar:SetMovable(true)
    bars[kind] = bar

    PA.NewMover(kind)
    return bar
end

function PA.Update(kind)
    local bar = bars[kind]
    if not bar or not bar:IsShown() or engineBars[kind] then return end
    local s = S(kind)
    local g = bar.geo or Geometry(s)
    local list = Collect(kind)
    SortList(list, s)
    local n = math.min(#list, s.max, g.perLine * g.lines)
    for i = 1, n do
        local b = bar.icons[i]
        if not b then
            b = NewIcon(bar)
            bar.icons[i] = b
            Dress(b, s)
        end
        local line = math.floor((i - 1) / g.perLine)
        local col = (i - 1) % g.perLine
        b:ClearAllPoints()
        b:SetPoint(g.point, bar, g.point, col * g.x + line * g.wx, col * g.y + line * g.wy)
        Fill(b, list[i], s)
    end
    for i = n + 1, #bar.icons do
        bar.icons[i].data = nil
        bar.icons[i]:Hide()
    end
    bar.count = n
end


---------------------------------------------------------------------------
-- Engine bars (the game's aura container)
---------------------------------------------------------------------------

local function FlowDir(token)
    local FD = AnchorUtil and AnchorUtil.FlowDirection
    if not FD then return nil end
    return ({ LEFT = FD.Left, RIGHT = FD.Right, UP = FD.Up, DOWN = FD.Down })[token]
end
local function Call(c, new, old, ...)
    local fn = c[new] or (old and c[old])
    if fn then return pcall(fn, c, ...) end
    return false
end

-- time left: the engine counts it (also while auras are secret); the text
-- comes from a rule formatter: seconds, minutes, then h:mm or minutes
local formatters = {}
local function Formatter(fmt)
    if formatters[fmt] ~= nil then return formatters[fmt] or nil end
    formatters[fmt] = false
    if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter and Enum and Enum.NumericRuleFormatRounding) then
        return nil
    end
    local Up, Down = Enum.NumericRuleFormatRounding.Up, Enum.NumericRuleFormatRounding.Down
    local base = {
        { threshold = 0, format = "%d", step = 1, rounding = Up },
        { threshold = 60, format = "%dm", step = 1, rounding = Up, components = { { div = 60 } } },
        { threshold = 61, format = "%dm", step = 1, rounding = Down, components = { { div = 60 } } },
    }
    local tries = {}
    if fmt == "HHMM" then
        local p = { unpack(base) }
        p[#p + 1] = { threshold = 3600, format = "%d:%02d", step = 1, rounding = Down,
            components = { { div = 3600 }, { div = 60, mod = 60 } } }
        tries[1] = p
    end
    tries[#tries + 1] = base       -- minutes all the way
    for _, points in ipairs(tries) do
        local f = C_StringUtil.CreateNumericRuleFormatter()
        if pcall(f.SetBreakpoints, f, points) then formatters[fmt] = f return f end
    end
    return nil
end

local function CellSize(s)
    local extra = (s.timer and s.timerPos == "BELOW") and (s.timerSize + 2) or 0
    return s.size, s.size + extra
end

-- the look of one engine button (sizes may be denied while auras are secret)
local function StyleEngineButton(b, d, s, kind)
    local w, h = CellSize(s)
    pcall(b.SetSize, b, w, h)
    local bs = s.borderSize
    d.border:ClearAllPoints()
    d.border:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    d.border:SetSize(s.size, s.size)
    d.border:SetShown(bs > 0)
    local c = s.borderAccent and { r = A[1], g = A[2], b = A[3] } or s.borderColor
    if kind == "debuffs" and s.typeColors then c = { r = 0.8, g = 0, b = 0 } end    -- untyped: red
    d.border:SetColorTexture(c.r, c.g, c.b, 1)
    if d.dispel then
        d.dispel:ClearAllPoints()
        d.dispel:SetAllPoints(d.border)
    end
    d.icon:ClearAllPoints()
    d.icon:SetPoint("TOPLEFT", b, "TOPLEFT", bs, -bs)
    d.icon:SetSize(math.max(1, s.size - 2 * bs), math.max(1, s.size - 2 * bs))
    local z = math.max(0, math.min(0.4, s.zoom))
    pcall(d.icon.SetTexCoord, d.icon, z, 1 - z, z, 1 - z)
    pcall(d.cd.SetDrawSwipe, d.cd, s.swipe)
    ns.ApplyFont(d.time, s.font, s.timerSize, s.outline)
    ns.ApplyFont(d.count, s.font, s.countSize, s.outline)
    d.time:ClearAllPoints()
    if s.timerPos == "BELOW" then d.time:SetPoint("TOP", d.border, "BOTTOM", 0, -1)
    else d.time:SetPoint("BOTTOM", d.border, "BOTTOM", 0, 2) end
    d.time:SetAlpha(s.timer and 1 or 0)
    d.count:ClearAllPoints()
    d.count:SetPoint("TOPRIGHT", d.border, "TOPRIGHT", -1, -1)
    if d.fmt ~= s.timerFormat then
        local f = Formatter(s.timerFormat)
        if pcall(b.SetDurationText, b, d.time, f and { textFormatter = f } or {}) then d.fmt = s.timerFormat end
    end
end

local function EngineInit(kind)
    return function(b)
        local ok, err = pcall(function()
            local s = S(kind)
            local d = {}
            d.border = b:CreateTexture(nil, "BACKGROUND")
            d.icon = b:CreateTexture(nil, "ARTWORK")
            d.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
            d.cd:SetAllPoints(d.icon)
            d.cd:SetReverse(true)
            d.cd:SetDrawEdge(false)
            if d.cd.SetHideCountdownNumbers then d.cd:SetHideCountdownNumbers(true) end
            local over = CreateFrame("Frame", nil, b)
            over:SetAllPoints()
            over:SetFrameLevel(d.cd:GetFrameLevel() + 2)
            over:EnableMouse(false)
            d.time = over:CreateFontString(nil, "OVERLAY")
            d.count = over:CreateFontString(nil, "OVERLAY")
            ns.ApplyFont(d.time, s.font, s.timerSize, s.outline)     -- fonts before the engine writes
            ns.ApplyFont(d.count, s.font, s.countSize, s.outline)
            -- debuff type colour: the engine tints this texture per dispel type
            local tint = Enum and Enum.CustomAuraButtonDispelTypeTextureStyle
                and Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset
            local addFn = b.AddDispelTypeTexture or b.SetAuraBorder
            if kind == "debuffs" and s.typeColors and tint ~= nil and addFn then
                d.dispel = b:CreateTexture(nil, "BORDER")
                d.dispel:SetColorTexture(1, 1, 1, 1)
                d.dispel:Hide()
                if not pcall(addFn, b, d.dispel, { style = tint, showWhenHarmful = true, showWhenHelpful = false }) then
                    d.dispel = nil
                end
            end
            StyleEngineButton(b, d, s, kind)
            b:SetIcon(d.icon)
            b:SetDurationCooldown(d.cd)
            b:SetApplicationCount(d.count, {})
            if kind == "buffs" then
                pcall(b.SetMouseClickEnabled, b, true)
                pcall(b.SetCancelAuraButtons, b, "RightButtonUp")
            else
                pcall(b.SetMouseClickEnabled, b, false)
            end
            engineButtons[kind][b] = d
        end)
        if not ok then ns.LogError("aura bar " .. kind, err) end
    end
end

local function EngineSort(s)
    local M, D = AuraContainerSortMethod, AuraContainerSortDirection
    if not (M and D) then return nil, nil end
    local m
    if s.sort == "NAME" then m = M.NameOnly or M.Name
    elseif s.sort == "INDEX" then m = M.AuraInstanceIDOnly or M.Default
    else m = M.ExpirationOnly or M.Expiration end
    return m, (s.sortDir == "+") and D.Normal or D.Reverse
end

local function EngineLayout(s)
    local w, h = CellSize(s)
    return { elementWidth = w, elementHeight = h, elementSpacing = s.padding, lineSpacing = s.padding }
end

local function BuildEngineBar(kind)
    if engineBars[kind] then return engineBars[kind] end
    if C_AddOns and C_AddOns.LoadAddOn and not (C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer")) then
        pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
    end
    local ok, c = pcall(CreateFrame, "AuraContainer", "HUF_" .. (kind == "buffs" and "Buffs" or "Debuffs"), UIParent,
        "CustomAuraContainerTemplate")
    if not ok or not c or not c.AddAuraGroup then return nil end
    c.kind = kind
    c:SetFrameStrata("LOW")
    c:SetClampedToScreen(true)
    c:SetMovable(true)
    c:SetPoint("CENTER")
    c:SetSize(1, 1)
    local s = S(kind)
    local m, dir = EngineSort(s)
    local g = Geometry(s)
    local opts = { maxFrameCount = math.min(s.max, g.perLine * g.lines), initializeFrame = EngineInit(kind),
        layout = EngineLayout(s) }
    if m ~= nil and dir ~= nil then opts.sortMethod, opts.sortDirection = m, dir end
    local okG, err = pcall(c.AddAuraGroup, c, "all", KINDS[kind], opts)
    if not okG then ns.LogError("aura bar " .. kind, err) return nil end
    -- weapon enchants (poisons, oils) ahead of the buffs
    local slots = AuraContainerItemEnchantmentSlot
    if kind == "buffs" and c.AddItemEnchantment and slots then
        for _, name in ipairs({ "MainHand", "OffHand", "Ranged" }) do
            if slots[name] ~= nil then
                pcall(c.AddItemEnchantment, c, slots[name], { initializeFrame = EngineInit(kind), hidePermanent = true })
            end
        end
    end
    engineBars[kind] = c
    bars[kind] = c
    ns.Log("auras", "aura bar %s: game container", kind)
    return c
end

local function ApplyEngineBar(kind, c)
    local s = S(kind)
    local g = Geometry(s)
    local anchor, gh, gv, vertical = Flow(s)
    -- the container sizes itself to its icons: it hangs by the corner the icons
    -- start from, at that corner of a fixed box where the bar's place is (as
    -- EllesmereUI anchors its containers by their flow corner)
    local holder = c.hufHolder
    if not holder then
        holder = CreateFrame("Frame", nil, UIParent)
        holder:SetFrameStrata("LOW")
        c.hufHolder = holder
        c:SetParent(holder)        -- takes the bar's scale from the box
        c:SetFrameStrata("LOW")
    end
    holder:ClearAllPoints()
    holder:SetPoint(s.point[1], UIParent, s.point[2], s.point[3], s.point[4])
    holder:SetSize(g.w, g.h)
    holder:SetScale(s.scale)
    c:ClearAllPoints()
    c:SetPoint(anchor, holder, anchor, 0, 0)
    c:SetSize(g.w, g.h)
    c:SetScale(1)
    Call(c, "SetFlowLayoutAnchorPoint", "SetAuraLayoutAnchorPoint", anchor)
    Call(c, "SetFlowLayoutGrowthDirection", "SetAuraLayoutGrowthDirection", FlowDir(gh), FlowDir(gv))
    local axes = AnchorUtil and AnchorUtil.FlowLayoutAxis
    if axes and c.SetFlowLayoutAxis then pcall(c.SetFlowLayoutAxis, c, vertical and axes.Vertical or axes.Horizontal) end
    local w, h = CellSize(s)
    local line = vertical and (g.perLine * (h + s.padding)) or (g.perLine * (w + s.padding))
    Call(c, "SetFlowLayoutMaximumLineSize", "SetAuraLayoutRowWidth", line + 0.4)
    pcall(c.SetAuraGroupLayout, c, "all", EngineLayout(s))
    pcall(c.SetAuraGroupMaxFrameCount, c, "all", math.min(s.max, g.perLine * g.lines))
    local m, dir = EngineSort(s)
    if m ~= nil and dir ~= nil and c.SetAuraGroupSortMethod then pcall(c.SetAuraGroupSortMethod, c, "all", m, dir) end
    if kind == "buffs" and c.SetItemEnchantmentLayout then
        local layout = EngineLayout(s)
        local pl = CustomAuraContainerItemEnchantmentPlacement
        if pl then layout.placement = pl.BeforeAuraGroups end
        pcall(c.SetItemEnchantmentLayout, c, layout)
    end
    for b, d in pairs(engineButtons[kind]) do StyleEngineButton(b, d, s, kind) end
    c:Show()
    if not c.hufBound then
        pcall(c.SetUnit, c, "player")
        c.hufBound = true
    end
    pcall(c.UpdateAllAuras, c)
end

function PA.PlaceMover(kind)
    local s = S(kind)
    local m = movers[kind] or PA.NewMover(kind)
    local g = Geometry(s)
    m:ClearAllPoints()
    m:SetPoint(s.point[1], UIParent, s.point[2], s.point[3], s.point[4])
    m:SetSize(g.w, g.h)
    m:SetScale(s.scale)
    m:SetShown(ns.unlocked and true or false)
end

local useEngine
local function ApplyBar(kind)
    local s = S(kind)
    if not s.enabled then
        if bars[kind] then bars[kind]:Hide() end
        if movers[kind] then movers[kind]:Hide() end
        return
    end
    if useEngine == nil then useEngine = ns.Auras and ns.Auras.Engine and ns.Auras.Engine() or false end
    if useEngine then
        local c = engineBars[kind] or BuildEngineBar(kind)
        if c then
            ApplyEngineBar(kind, c)
            PA.PlaceMover(kind)
            return
        end
    end
    local bar = BuildBar(kind)
    local g = Geometry(s)
    bar.geo = g
    bar:ClearAllPoints()
    bar:SetPoint(s.point[1], UIParent, s.point[2], s.point[3], s.point[4])
    bar:SetSize(g.w, g.h)
    bar:SetScale(s.scale)
    for _, b in ipairs(bar.icons) do Dress(b, s) end
    bar:Show()
    PA.Update(kind)
    PA.PlaceMover(kind)
end

function PA.Apply()
    if not (HUFDB and ns.db) then return end
    ApplyBar("buffs")
    ApplyBar("debuffs")
    if ns.unlocked then PA.SetUnlocked(true) end   -- the examples follow a change
    if ns.Units and ns.Units.HideBlizzardBars then ns.Units.HideBlizzardBars() end
end

---------------------------------------------------------------------------
-- Unlock mode: made-up auras where the bar is, in its look and layout (the
-- real icons are hidden meanwhile). Not clickable, no tooltips.
-- { icon, stacks, duration (0: no end), part of it left, debuff type }
---------------------------------------------------------------------------
local SAMPLES = {
    buffs = {
        { "Interface\\Icons\\Spell_Holy_WordFortitude", 0, 1800, 0.8 },
        { "Interface\\Icons\\Spell_Nature_Regeneration", 0, 1800, 0.6 },
        { "Interface\\Icons\\Spell_Holy_MagicalSentry", 0, 1800, 0.9 },
        { "Interface\\Icons\\Spell_Holy_DivineSpirit", 0, 1800, 0.4 },
        { "Interface\\Icons\\Spell_Shadow_AntiShadow", 0, 600, 0.7 },
        { "Interface\\Icons\\Spell_Nature_Thorns", 0, 600, 0.3 },
        { "Interface\\Icons\\Ability_Warrior_BattleShout", 0, 120, 0.5 },
        { "Interface\\Icons\\Spell_Holy_Renew", 0, 15, 0.6 },
        { "Interface\\Icons\\Spell_Nature_Rejuvenation", 0, 12, 0.3 },
        { "Interface\\Icons\\Spell_Holy_InnerFire", 0, 600, 0.9 },
        { "Interface\\Icons\\Spell_Misc_Food", 0, 900, 0.95 },
        { "Interface\\Icons\\Spell_Nature_LightningShield", 3, 600, 0.5 },
        { "Interface\\Icons\\Spell_Frost_FrostArmor02", 0, 0, 0 },
        { "Interface\\Icons\\Spell_Holy_PowerWordShield", 0, 30, 0.7 },
    },
    debuffs = {
        { "Interface\\Icons\\Spell_Shadow_CurseOfSargeras", 0, 24, 0.6, "Curse" },
        { "Interface\\Icons\\Ability_Creature_Poison_02", 2, 15, 0.5, "Poison" },
        { "Interface\\Icons\\Spell_Shadow_AbominationExplosion", 0, 18, 0.8, "Magic" },
        { "Interface\\Icons\\Spell_Shadow_CallOfBone", 0, 30, 0.4, "Disease" },
        { "Interface\\Icons\\Ability_Gouge", 0, 4, 0.5 },
    },
}
local previews = {}
local function PreviewFrame(kind)
    local p = previews[kind]
    if p then return p end
    p = CreateFrame("Frame", nil, UIParent)
    p.kind = kind
    p.icons = {}
    p:SetFrameStrata("MEDIUM")
    -- a timer that ran out starts again
    p:SetScript("OnUpdate", function(self, elapsed)
        self.t = (self.t or 0) + elapsed
        if self.t < 0.5 then return end
        self.t = 0
        local now = GetTime()
        for _, b in ipairs(self.icons) do
            local d = b.data
            if b:IsShown() and d and d.duration > 0 and d.expires - now < 0.3 then
                d.expires = now + d.duration
                Fill(b, d, S(kind))
            end
        end
    end)
    previews[kind] = p
    return p
end
local function ShowPreview(kind, on)
    local s = S(kind)
    local p = previews[kind]
    if not (on and s.enabled) then
        if p then p:Hide() end
        return
    end
    p = PreviewFrame(kind)
    local g = Geometry(s)
    p:ClearAllPoints()
    p:SetPoint(s.point[1], UIParent, s.point[2], s.point[3], s.point[4])
    p:SetSize(g.w, g.h)
    p:SetScale(s.scale)
    local list, now = SAMPLES[kind], GetTime()
    local n = math.min(#list, s.max, g.perLine * g.lines)
    for i = 1, n do
        local b = p.icons[i]
        if not b then
            b = NewIcon(p)
            b:EnableMouse(false)
            b:SetScript("OnEnter", nil)
            b:SetScript("OnClick", nil)
            p.icons[i] = b
        end
        Dress(b, s)
        local line = math.floor((i - 1) / g.perLine)
        local col = (i - 1) % g.perLine
        b:ClearAllPoints()
        b:SetPoint(g.point, p, g.point, col * g.x + line * g.wx, col * g.y + line * g.wy)
        local x = list[i]
        Fill(b, { icon = x[1], count = x[2], duration = x[3], expires = x[3] > 0 and (now + x[3] * x[4]) or 0,
            dispel = x[5], order = i }, s)
    end
    for i = n + 1, #p.icons do
        p.icons[i].data = nil
        p.icons[i]:Hide()
    end
    p:Show()
end

function PA.SetUnlocked(on)
    for kind, m in pairs(movers) do m:SetShown(on and S(kind).enabled and true or false) end
    for kind in pairs(KINDS) do
        ShowPreview(kind, on)
        -- the real icons out of sight while the examples show
        local c = engineBars[kind]
        local real = (c and c.hufHolder) or bars[kind]
        if real then real:SetAlpha((on and S(kind).enabled) and 0 or 1) end
    end
end

function PA.Report(add)
    for _, kind in ipairs({ "buffs", "debuffs" }) do
        local s, bar = S(kind), bars[kind]
        local n = 0
        for _ in pairs(engineButtons[kind]) do n = n + 1 end
        add(("aura bar %s: enabled=%s %s shown=%s icons=%d grow=%s max=%d %dx%d size=%d"):format(kind,
            tostring(s.enabled), engineBars[kind] and "game container" or "HUF icons",
            tostring(bar and bar:IsShown()), engineBars[kind] and n or (bar and bar.count or 0),
            s.grow, s.max, s.columns, s.rows, s.size))
    end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event)
    if not (HUFDB and ns.db) then return end
    if event == "UNIT_AURA" then
        PA.Update("buffs")
        PA.Update("debuffs")
    else
        PA.Update("buffs")
    end
end)
pcall(ev.RegisterUnitEvent, ev, "UNIT_AURA", "player")
pcall(ev.RegisterUnitEvent, ev, "UNIT_INVENTORY_CHANGED", "player")
pcall(ev.RegisterEvent, ev, "WEAPON_ENCHANT_CHANGED")
-- weapon enchants come and go without an event on some clients
C_Timer.NewTicker(2, function()
    if HUFDB and ns.db and S("buffs").enabled and GetWeaponEnchantInfo then
        local ok, hasMain, _, _, _, hasOff = pcall(GetWeaponEnchantInfo)
        local state = ok and (tostring(hasMain) .. tostring(hasOff)) or ""
        if state ~= PA.weaponState then
            PA.weaponState = state
            PA.Update("buffs")
        end
    end
end)

ns.OnLogin(PA.Apply)
ns.OnRefresh(PA.Apply)
