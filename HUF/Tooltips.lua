-- HUF: the game's tooltips (GENERAL > Utility Frames > Tooltips).
-- Where they show (at the cursor, left or right of it, or a fixed place that
-- can be moved in unlock mode; optionally fixed while in combat), an extra
-- line with the unit's target, the player's title on or off, spell IDs, and
-- the background / border colours.
-- Taint rules: only hooksecurefunc / HookScript and TooltipDataProcessor
-- post-calls; forbidden tooltips are left alone; secret values are never
-- read, only passed on.
-- ns.db.tooltip = { enabled, anchor CURSOR_LEFT | CURSOR_RIGHT | FIXED, combatFixed,
--   targetOfTarget, title, spellID, bgColor, bgAlpha, border ACCENT | CUSTOM | NONE,
--   borderColor, point }

local _, ns = ...
local UI = ns.UI

local TT = {}
ns.Tooltips = TT

local function C() return ns.db and ns.db.tooltip end
local function On() local c = C() return c and c.enabled end
local function Plain(v) return v ~= nil and not ns.IsSecret(v) end

-- the tooltips that get HUF's colours
local STYLED = { "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2",
                 "ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2", "EmbeddedItemTooltip" }

---------------------------------------------------------------------------
-- Colours
---------------------------------------------------------------------------
local function Style(tt)
    if not (On() and tt and tt.NineSlice) then return end
    if tt.IsForbidden and tt:IsForbidden() then return end
    local c = C()
    local bg = c.bgColor
    pcall(tt.NineSlice.SetCenterColor, tt.NineSlice, bg.r, bg.g, bg.b, c.bgAlpha or 0.85)
    local r, g, b, a = 0, 0, 0, 0                -- NONE: the edge pieces fully transparent
    if c.border == "CUSTOM" then r, g, b, a = c.borderColor.r, c.borderColor.g, c.borderColor.b, 1
    elseif c.border ~= "NONE" then r, g, b, a = UI.ACCENT[1], UI.ACCENT[2], UI.ACCENT[3], 1 end
    pcall(tt.NineSlice.SetBorderColor, tt.NineSlice, r, g, b, a)
end
TT.Style = Style

---------------------------------------------------------------------------
-- Place
---------------------------------------------------------------------------
local anchorBox      -- the fixed place (unlock mode box)
function TT.FixedFrame()
    if not anchorBox then
        anchorBox = CreateFrame("Frame", "HUF_TooltipAnchor", UIParent)
        anchorBox:SetSize(220, 90)
        anchorBox:Hide()
    end
    local p = C().point
    anchorBox:ClearAllPoints()
    anchorBox:SetPoint(p[1], UIParent, p[2], p[3] or 0, p[4] or 0)
    return anchorBox
end

local function Fixed()
    local c = C()
    if c.anchor == "FIXED" then return true end
    return c.combatFixed and InCombatLockdown() or false
end

local function Place(tt, parent)
    if not On() or (tt.IsForbidden and tt:IsForbidden()) then return end
    local c = C()
    if Fixed() then
        local box = TT.FixedFrame()
        tt:ClearAllPoints()
        tt:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, 0)
    elseif c.anchor == "CURSOR_LEFT" then
        tt:SetOwner(parent, "ANCHOR_CURSOR_LEFT", -10, 10)
    else
        tt:SetOwner(parent, "ANCHOR_CURSOR_RIGHT", 10, 10)
    end
end

---------------------------------------------------------------------------
-- Lines: target of the unit, title, spell ID
---------------------------------------------------------------------------
local function ClassHex(unit)
    local ok, _, class = pcall(UnitClass, unit)
    local cc = ok and Plain(class) and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if cc then return ("|cff%02x%02x%02x"):format(math.floor(cc.r * 255), math.floor(cc.g * 255), math.floor(cc.b * 255)) end
    return "|cffffffff"
end

local function TargetLine(tt, unit)
    local tu = unit .. "target"
    local ok, exists = pcall(UnitExists, tu)
    if not (ok and exists and Plain(exists)) then return end
    local me = select(2, pcall(UnitIsUnit, tu, "player"))
    local name
    if me == true then
        name = "|cffff4040>> " .. (YOU or "You") .. " <<|r"
    else
        local isPlayer = select(2, pcall(UnitIsPlayer, tu))
        local shown = isPlayer == true and ns.NameText and ns.NameText(tu) or nil
        if not shown then
            local okn, n = pcall(UnitName, tu)
            shown = okn and Plain(n) and n or nil
        end
        if not shown then return end
        name = (isPlayer == true and ClassHex(tu) or "|cffffffff") .. shown .. "|r"
    end
    tt:AddLine((TARGET or "Target") .. ": " .. name, 1, 0.82, 0)
end

-- the title around the name: remove it, or add it when the game left it out
local function TitleLine(tt, unit)
    local okp, isPlayer = pcall(UnitIsPlayer, unit)
    if not (okp and isPlayer == true) then return end
    local line = _G[tt:GetName() .. "TextLeft1"]
    if not line then return end
    local text = line:GetText()
    local ok1, first, last = pcall(UnitName, unit)
    local ok2, pvp = pcall(UnitPVPName, unit)
    if not (ok1 and ok2 and Plain(text) and Plain(first) and Plain(pvp) and pvp ~= "") then return end
    local full = (Plain(last) and last ~= "") and (first .. " " .. last) or first
    local esc = full:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
    local s, e = pvp:find(esc)
    if not s then esc = first:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0") s, e = pvp:find(esc) end
    if not s then return end
    local before, after = pvp:sub(1, s - 1), pvp:sub(e + 1)
    if before == "" and after == "" then return end   -- no title
    local function Esc(x) return (x:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")) end
    local has = (before ~= "" and text:find(Esc(before), 1)) or (after ~= "" and text:find(Esc(after), 1))
    if C().title then
        if not has then line:SetText(before .. text .. after) end
    elseif has then
        local t = text
        if before ~= "" then t = t:gsub(Esc(before), "", 1) end
        if after ~= "" then t = t:gsub(Esc(after), "", 1) end
        line:SetText(t)
    end
end

local function OnUnit(tt)
    if tt ~= GameTooltip or not On() or tt:IsForbidden() then return end
    local ok, _, unit = pcall(tt.GetUnit, tt)
    if not (ok and Plain(unit)) then return end
    pcall(TitleLine, tt, unit)
    if C().targetOfTarget then pcall(TargetLine, tt, unit) end
end

local function OnSpell(tt, data)
    if not (On() and C().spellID) or (tt.IsForbidden and tt:IsForbidden()) then return end
    local id = type(data) == "table" and data.id
    if not (Plain(id) and type(id) == "number") then return end
    if tt.hufSpellID == id and tt:IsShown() then return end   -- once per tooltip
    tt.hufSpellID = id
    tt:AddLine(("|cff9d9d9dSpell ID:|r |cffffffff%d|r"):format(id))
    tt:Show()
end

---------------------------------------------------------------------------
-- Hooks (once, the first time the tooltips are on)
---------------------------------------------------------------------------
local hooked = false
local function Hook()
    if hooked then return end
    hooked = true
    if type(GameTooltip_SetDefaultAnchor) == "function" then
        hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tt, parent) pcall(Place, tt, parent) end)
    end
    if type(SharedTooltip_SetBackdropStyle) == "function" then
        hooksecurefunc("SharedTooltip_SetBackdropStyle", function(tt) Style(tt) end)
    end
    for _, n in ipairs(STYLED) do
        local tt = _G[n]
        if tt and tt.HookScript then
            tt:HookScript("OnShow", Style)
            tt:HookScript("OnTooltipCleared", function(self) self.hufSpellID = nil end)
        end
    end
    local TDP = TooltipDataProcessor
    local T = Enum and Enum.TooltipDataType
    if TDP and TDP.AddTooltipPostCall and T then
        if T.Unit then TDP.AddTooltipPostCall(T.Unit, OnUnit) end
        for _, k in ipairs({ "Spell", "UnitAura", "Totem", "Macro" }) do
            if T[k] then TDP.AddTooltipPostCall(T[k], OnSpell) end
        end
    end
end

function TT.Apply()
    if not ns.db then return end
    if On() then Hook() end
    if anchorBox then TT.FixedFrame() end
    for _, n in ipairs(STYLED) do local tt = _G[n] if tt and tt:IsShown() then Style(tt) end end
end

ns.OnLogin(TT.Apply)
ns.OnRefresh(TT.Apply)
-- in combat: the next tooltip goes to the fixed place (nothing to redo here)
