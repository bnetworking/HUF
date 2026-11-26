-- HUF: UI scale (General > Look and Feel > "Use HUF's UI scale").
-- The game's own UI Scale stops at 0.64; HUF sets UIParent's scale itself (as EllesmereUI
-- does), so it goes from 0.40 to 1.15. "Pixel perfect" is 768 / the screen's height in
-- pixels (0.5333 at 1440 lines, 0.7111 at 1080).
-- Off (the default): HUF never touches the scale, the game's own setting stays.
-- The game sets UIParent's scale again at login and whenever its own UI Scale changes
-- (UI_SCALE_CHANGED, DISPLAY_SIZE_CHANGED): HUF puts its value back each time. A scale
-- change in combat waits until the fight is over.
-- EllesmereUI sets the same scale: while it is loaded with a scale of its own, HUF leaves
-- it to EllesmereUI (two addons setting it would take turns). Its value is importable
-- (General > Profiles > Import from EllesmereUI).
-- ns.db.uiScale = { enabled, scale }

local _, ns = ...

local US = {}
ns.UIScale = US

US.MIN, US.MAX = 0.40, 1.15

local function S() return ns.db and ns.db.uiScale end

-- EllesmereUI loaded and setting a scale of its own
function US.EllesmereOwns()
    local IsLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
    if not (IsLoaded and IsLoaded("EllesmereUI")) then return false end
    local db = _G.EllesmereUIDB
    return type(db) == "table" and type(db.ppUIScale) == "number"
end

function US.PixelPerfect()
    local _, h = GetPhysicalScreenSize()
    if type(h) ~= "number" or h <= 0 then return nil end
    return 768 / h
end

function US.Clamp(v)
    v = tonumber(v) or 1
    return math.max(US.MIN, math.min(US.MAX, v))
end

local pending = false
function US.Apply()
    local s = S()
    if not (s and s.enabled) or US.EllesmereOwns() then return false end
    if InCombatLockdown() then pending = true return false end
    pending = false
    local v = US.Clamp(s.scale)
    if math.abs((UIParent:GetScale() or 0) - v) > 0.0001 then UIParent:SetScale(v) end
    return true
end

-- switched off: the game's own UI Scale back. Returns false when only a reload gives it
-- back exactly (the game's "Use UI Scale" off: its scale then depends on the screen)
function US.Restore()
    if InCombatLockdown() then return false end
    local useCVar = GetCVarBool and GetCVarBool("useUiScale")
    local v = useCVar and tonumber(GetCVar and GetCVar("uiScale")) or nil
    if not v then return false end
    UIParent:SetScale(v)
    return true
end

-- the slider: applied a moment after the last change (the settings window shrinks with it)
local soon
function US.ApplySoon()
    if soon then soon:Cancel() end
    soon = C_Timer.NewTimer(0.4, function() soon = nil US.Apply() end)
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("UI_SCALE_CHANGED")
f:RegisterEvent("DISPLAY_SIZE_CHANGED")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        if pending then US.Apply() end
        return
    end
    if not ns.db then return end
    US.Apply()
    if event == "PLAYER_ENTERING_WORLD" then
        -- the game may set its scale once more while loading on slow machines
        C_Timer.After(2, US.Apply)
        C_Timer.After(5, US.Apply)
    end
end)

function US.Report(add)
    local s = S() or {}
    add(("ui scale: on=%s scale=%s now=%.4f pixel perfect=%s ellesmere=%s"):format(tostring(s.enabled), tostring(s.scale),
        UIParent:GetScale() or 0, tostring(US.PixelPerfect()), tostring(US.EllesmereOwns())))
end
