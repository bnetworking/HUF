-- HUF: the bars around the action bars (General > Action Bars > XP & reputation /
-- Menu, bags & queue). Settings: ns.db.actionBars.extra (they go along with the action
-- bars in the profile and in the EllesmereUI import).
--
-- XP and reputation: HUF's own bars (flat, 1 px border) - XP with the rested part in a
-- second colour, the watched faction in its standing's colour; the numbers always, on
-- mouseover or never, and a tooltip. While one of them is on, the game's own XP /
-- reputation bars (the status tracking bars) are parked under a hidden parent.
-- Micro menu, bag bar, queue button (the looking-for-group eye): the game's own frames,
-- held by a HUF frame - moved in unlock mode, scaled, faded until the mouse is over them,
-- or hidden. When Edit Mode or the game anchors them again, HUF puts them back.
-- Every part is on by default, but only while HUF's action bars are on (General > Action
-- Bars); each can be switched off. Off: the part is not touched.

local _, ns = ...

local EB = {}
ns.ExtraBars = EB

local function E() local d = ns.db and ns.db.actionBars return d and d.extra end
local function On() local d = ns.db and ns.db.actionBars return d and d.enabled end
local function S(key) local e = E() return e and e[key] end

local hidden = CreateFrame("Frame", nil, UIParent)
hidden:Hide()

local A = ns.ACCENT or { 0.31, 0.70, 1.00 }
local XP_COLOR = { 0.58, 0.39, 0.85 }       -- XP (purple)
local RESTED_COLOR = { 0.0, 0.44, 0.87 }    -- the rested part ahead of it (blue)

local function Fmt(n)
    n = tonumber(n) or 0
    if n >= 1e6 then return ("%.1fm"):format(n / 1e6) end
    if n >= 1e4 then return ("%.1fk"):format(n / 1e3) end
    return tostring(math.floor(n + 0.5))
end

local function Plain(v) return v ~= nil and not (ns.IsSecret and ns.IsSecret(v)) end

---------------------------------------------------------------------------
-- XP and reputation bars
---------------------------------------------------------------------------
local bars = {}

local function NewBar(key, label)
    local f = CreateFrame("Frame", "HUF" .. key .. "Bar", UIParent)
    f:SetFrameStrata("LOW")
    f:SetClampedToScreen(true)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(0.05, 0.05, 0.06, 0.85)
    f.rest = CreateFrame("StatusBar", nil, f)
    f.rest:SetAllPoints()
    f.rest:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    f.rest:SetMinMaxValues(0, 1)
    f.bar = CreateFrame("StatusBar", nil, f)
    f.bar:SetAllPoints()
    f.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    f.bar:SetMinMaxValues(0, 1)
    f.border = ns.UI.Border(f, 0, 0, 0, 1)
    for _, t in ipairs(f.border.edges) do t:SetDrawLayer("OVERLAY", 7) end
    f.text = f.bar:CreateFontString(nil, "OVERLAY")
    f.text:SetPoint("CENTER")
    f:EnableMouse(true)
    f:SetScript("OnEnter", function(self)
        self.hover = true
        EB.Update(key)
        if self.Tip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            self:Tip(GameTooltip)
            GameTooltip:Show()
        end
    end)
    f:SetScript("OnLeave", function(self)
        self.hover = false
        EB.Update(key)
        GameTooltip:Hide()
    end)
    bars[key] = f
    ns.RegisterMover("HUF_" .. key .. "Bar", {
        label = label,
        frame = f,
        shown = function() local s = S(key) return s and s.enabled end,
        save = function(fr)
            S(key).point = { "BOTTOMLEFT", "BOTTOMLEFT", math.floor(fr:GetLeft() + 0.5), math.floor(fr:GetBottom() + 0.5) }
        end,
        settings = function() if ns.OpenConfigTab then ns.OpenConfigTab("actionbars", "data") end end,
        get = function() local s = S(key) return s and s.point end,
        set = function(v) local s = S(key) if s and type(v) == "table" then s.point = v EB.Apply() end end,
        resize = {   -- unlock mode's corner grips: width and height
            get = function() local s = S(key) return s.width or 400, s.height or 10 end,
            set = function(w, h)
                local s = S(key)
                s.width = math.max(50, math.min(1600, math.floor(w + 0.5)))
                s.height = math.max(2, math.min(40, math.floor(h + 0.5)))
                EB.Apply()
            end,
        },
    })
    return f
end

-- what each bar shows: value, max, rested (XP only), colour, text, tooltip lines; nil = nothing to show
local function XPData()
    local max = UnitXPMax("player")
    local maxLevel = (GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion()) or (GetMaxPlayerLevel and GetMaxPlayerLevel()) or 60
    if S("xp").hideMaxLevel ~= false and UnitLevel("player") >= maxLevel then return nil end
    local cur, rested = UnitXP("player"), GetXPExhaustion() or 0
    if not (Plain(cur) and Plain(max)) or max <= 0 then return nil end
    local pct = cur / max * 100
    local text = ("%s / %s (%.1f%%)"):format(Fmt(cur), Fmt(max), pct)
    if rested > 0 then text = text .. (" | rested %.0f%%"):format(rested / max * 100) end
    return cur, max, rested, XP_COLOR, text, {
        { ("Level %d"):format(UnitLevel("player")), 1, 0.82, 0 },
        { ("XP: %d / %d (%.1f%%)"):format(cur, max, pct), 1, 1, 1 },
        { ("To level: %d"):format(max - cur), 1, 1, 1 },
        rested > 0 and { ("Rested: %d (%.0f%% of a level)"):format(rested, rested / max * 100), RESTED_COLOR[1], RESTED_COLOR[2] + 0.3, 1 } or nil,
    }
end

local function RepData()
    local name, standing, minV, maxV, value
    if C_Reputation and C_Reputation.GetWatchedFactionData then
        local d = C_Reputation.GetWatchedFactionData()
        if d then name, standing, minV, maxV, value = d.name, d.reaction, d.currentReactionThreshold, d.nextReactionThreshold, d.currentStanding end
    elseif GetWatchedFactionInfo then
        name, standing, minV, maxV, value = GetWatchedFactionInfo()
    end
    if not name or not (Plain(value) and Plain(minV) and Plain(maxV)) then return nil end
    local cur, max = value - minV, math.max(1, maxV - minV)
    local c = FACTION_BAR_COLORS and FACTION_BAR_COLORS[standing] or { r = 0, g = 0.6, b = 0.1 }
    local label = _G["FACTION_STANDING_LABEL" .. tostring(standing)] or ""
    local text = ("%s: %s / %s (%s)"):format(name, Fmt(cur), Fmt(max), label)
    return cur, max, 0, { c.r, c.g, c.b }, text, {
        { name, 1, 0.82, 0 },
        { ("%s: %d / %d"):format(label, cur, max), c.r, c.g, c.b },
    }
end

local DATA = { xp = XPData, rep = RepData }

function EB.Update(key)
    local f, s = bars[key], S(key)
    if not (f and s and s.enabled and On()) then return end
    local cur, max, rested, color, text, tip = DATA[key]()
    if not cur then f:Hide() return end
    f:Show()
    f.bar:SetMinMaxValues(0, max)
    f.bar:SetValue(cur)
    f.bar:SetStatusBarColor(color[1], color[2], color[3], 1)
    f.rest:SetShown(rested > 0)
    if rested > 0 then
        f.rest:SetMinMaxValues(0, max)
        f.rest:SetValue(math.min(max, cur + rested))
        f.rest:SetStatusBarColor(RESTED_COLOR[1], RESTED_COLOR[2], RESTED_COLOR[3], 0.55)
    end
    f.text:SetText(text)
    local show = s.text == "ALWAYS" or (s.text == "MOUSEOVER" and f.hover)
    f.text:SetShown(show and true or false)
    f:SetAlpha((not s.mouseover or f.hover) and 1 or 0)
    f.Tip = function(_, tt) for _, l in ipairs(tip) do if l then tt:AddLine(l[1], l[2], l[3], l[4]) end end end
end

local function ApplyDataBar(key, label)
    local s = S(key)
    local f = bars[key]
    if not (s and s.enabled) then
        if f then f:Hide() end
        return
    end
    f = f or NewBar(key, label)
    f:SetSize(s.width or 400, s.height or 10)
    f:ClearAllPoints()
    local p = s.point or { "BOTTOM", "BOTTOM", 0, 4 }
    f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    local font = ns.FontPath and ns.FontPath("GLOBAL") or STANDARD_TEXT_FONT
    f.text:SetFont(font, s.textSize or 11, "OUTLINE")
    local d = ns.db.actionBars
    local c = d.borderAccent and { r = A[1], g = A[2], b = A[3] } or d.borderColor or { r = 0, g = 0, b = 0 }
    f.border:SetColor(c.r, c.g, c.b, 1)
    f.border:SetShown((d.border or 1) > 0)
    EB.Update(key)
end

---------------------------------------------------------------------------
-- The game's frames: micro menu, bag bar, queue button
---------------------------------------------------------------------------
local HELD = {
    micro = { label = "Micro menu", names = { "MicroMenuContainer", "MicroButtonAndBagsBar" } },
    bags = { label = "Bag bar", names = { "BagsBar", "MainMenuBarBackpackButton" } },
    queue = { label = "Queue button", names = { "QueueStatusButton", "QueueStatusMinimapButton", "MiniMapLFGFrame" } },
}
local holders, placing = {}, false

local function Target(key)
    for _, n in ipairs(HELD[key].names) do
        local f = _G[n]
        if type(f) == "table" and f.SetPoint then return f, n end
    end
end

local function Seat(key)
    local h, f = holders[key], Target(key)
    if not (h and f) then return end
    if f:IsProtected() and InCombatLockdown() then ns.RunOOC("eb:" .. key, function() Seat(key) end) return end
    local s = S(key)
    placing = true
    f:SetParent(s.hidden and hidden or h)
    f:ClearAllPoints()
    f:SetPoint("CENTER", h, "CENTER", 0, 0)
    f:SetScale(s.scale or 1)
    placing = false
    local w, hh = f:GetWidth() or 0, f:GetHeight() or 0
    h:SetSize(math.max(20, w * (s.scale or 1)), math.max(20, hh * (s.scale or 1)))
end

local function Hold(key)
    local f = Target(key)
    if not f then return nil end
    local h = holders[key]
    if h then return h end
    h = CreateFrame("Frame", "HUFHolder_" .. key, UIParent)
    h:SetFrameStrata("MEDIUM")
    h:SetClampedToScreen(true)
    holders[key] = h
    local s = S(key)
    if not s.point then
        -- first time: where the game had it, so nothing jumps
        local x, y = f:GetCenter()
        local sc = (f:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
        if x and y then s.point = { "CENTER", "BOTTOMLEFT", math.floor(x * sc + 0.5), math.floor(y * sc + 0.5) } end
    end
    -- Edit Mode / the game anchoring it again: back into the holder (next frame)
    hooksecurefunc(f, "SetPoint", function()
        if placing then return end
        C_Timer.After(0, function() Seat(key) end)
    end)
    ns.RegisterMover("HUF_Held_" .. key, {
        label = HELD[key].label,
        frame = h,
        shown = function() local t = S(key) return t and t.enabled and not t.hidden end,
        save = function(fr)
            S(key).point = { "BOTTOMLEFT", "BOTTOMLEFT", math.floor(fr:GetLeft() + 0.5), math.floor(fr:GetBottom() + 0.5) }
        end,
        settings = function() if ns.OpenConfigTab then ns.OpenConfigTab("actionbars", "menus") end end,
        get = function() local t = S(key) return t and t.point end,
        set = function(v) local t = S(key) if t and type(v) == "table" then t.point = v EB.Apply() end end,
        resize = {   -- unlock mode's corner grips: its scale (the game's frame keeps its shape)
            get = function() return h:GetWidth(), h:GetHeight() end,
            set = function(w)
                local f = Target(key)
                local base = f and f:GetWidth() or 0
                if base <= 0 then return end
                S(key).scale = math.max(0.5, math.min(2, w / base))
                Seat(key)
            end,
            scale = {   -- Shift + drag: the same, its scale
                get = function() return S(key).scale or 1 end,
                set = function(v) S(key).scale = math.max(0.5, math.min(2, math.floor(v * 100 + 0.5) / 100)) Seat(key) end,
            },
        },
    })
    return h
end

local function ApplyHeld(key)
    local s = S(key)
    if not (s and s.enabled) then return end
    local h = Hold(key)
    if not h then return end
    h:ClearAllPoints()
    local p = s.point or { "CENTER", "CENTER", 0, 0 }
    h:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    Seat(key)
end

-- mouseover fading of the held frames (and the data bars' own fading through EB.Update)
local fadeTicker
local function Fade()
    local any = false
    for key, h in pairs(holders) do
        local s = S(key)
        if s and s.enabled and s.mouseover and not s.hidden then any = true else h:SetAlpha(1) end
    end
    if any and not fadeTicker then
        fadeTicker = C_Timer.NewTicker(0.1, function()
            for key, h in pairs(holders) do
                local s = S(key)
                if s and s.enabled and s.mouseover and not s.hidden then h:SetAlpha(h:IsMouseOver() and 1 or 0) end
            end
        end)
    elseif not any and fadeTicker then
        fadeTicker:Cancel()
        fadeTicker = nil
    end
end

---------------------------------------------------------------------------
-- The game's XP / reputation bars: parked while HUF's are on
---------------------------------------------------------------------------
local STATUS = { "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer", "StatusTrackingBarManager",
    "MainMenuExpBar", "ReputationWatchBar", "MainMenuBarMaxLevelBar" }
local parkedStatus = {}
local function ParkStatus()
    for _, n in ipairs(STATUS) do
        local f = _G[n]
        if type(f) == "table" and f.SetParent and not parkedStatus[f] then
            parkedStatus[f] = true
            ns.RunOOC("eb:status:" .. n, function() f:SetParent(hidden) end)
            hooksecurefunc(f, "SetParent", function(self, parent)
                if parent ~= hidden then C_Timer.After(0, function() ns.RunOOC("eb:status:" .. n, function() self:SetParent(hidden) end) end) end
            end)
        end
    end
end

function EB.Apply()
    local e = E()
    if not e or not ns.db.actionBars.enabled then return end
    ApplyDataBar("xp", "XP bar")
    ApplyDataBar("rep", "Reputation bar")
    if (e.xp.enabled or e.rep.enabled) and e.hideBlizzardStatus ~= false then ParkStatus() end
    for key in pairs(HELD) do
        local ok, err = pcall(ApplyHeld, key)
        if not ok then ns.LogError("held " .. key, err) end
    end
    Fade()
end

function EB.Available(key) return Target(key) ~= nil end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION", "PLAYER_LEVEL_UP", "UPDATE_FACTION", "PLAYER_ENTERING_WORLD" }) do
    ev:RegisterEvent(e)
end
ev:SetScript("OnEvent", function(_, event)
    if not E() then return end
    EB.Update("xp")
    EB.Update("rep")
    if event == "PLAYER_ENTERING_WORLD" then C_Timer.After(1, EB.Apply) end
end)

ns.OnLogin(EB.Apply)
ns.OnRefresh(EB.Apply)

function EB.Report(add)
    local e = E() or {}
    local parts = {}
    for _, k in ipairs({ "xp", "rep", "micro", "bags", "queue" }) do
        local s = e[k] or {}
        local _, n = (HELD[k] and Target(k))
        parts[#parts + 1] = ("%s=%s%s"):format(k, s.enabled and "on" or "off", n and ("(" .. n .. ")") or "")
    end
    add("extra bars: " .. table.concat(parts, " "))
end
