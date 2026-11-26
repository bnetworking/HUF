-- HUF: action bars (General > Action Bars).
--
-- The game's own action buttons go into HUF's bars: ActionButton1-12 (bar 1),
-- MultiBarBottomLeft / BottomRight / Right / Left / MultiBar5-7 buttons (bars 2-8),
-- the stance and pet buttons. Keeping the game's buttons keeps everything they do:
-- key bindings (the game's ACTIONBUTTON / MULTIACTIONBAR bindings call these very
-- buttons), cooldowns, range, usable colours, drag and drop, macros, flyouts.
-- HUF only places them, sizes them (SetScale, so the art keeps its proportions) and
-- gives them a flat look: square icon, 1 px border, dark slot.
--
-- Which actions a button shows: each button's own "actionpage" attribute (the game's
-- CalculateAction reads it). Bars 2-8 have a fixed page (6, 5, 3, 4, 13, 14, 15 - the
-- game's own). Bar 1 pages like the game's: a secure state driver on the bar picks the
-- page (Shift + wheel pages 2-6, stances / forms / stealth through the bonus bars,
-- mind control) and hands it to its buttons (ChildUpdate) - in combat too.
--
-- Blizzard's bars a HUF bar replaces are parked under a hidden parent (out of combat).
-- When Blizzard code puts the buttons back in its own layout (UpdateGridLayout), HUF
-- places them again. Everything that moves or sizes a button waits until combat ends.
--
-- Off (the default): nothing is touched. A bar switched off after HUF took its buttons
-- gets them back with a reload.
-- ns.db.actionBars = { enabled, bars = { [key] = { enabled, buttons, perRow, size,
--   spacing, point, mouseover, hideHotkey, hideMacro } }, border, borderAccent,
--   borderColor, slotAlpha }

local _, ns = ...

local AB = {}
ns.ActionBars = AB

local BARS = {
    { key = "MainBar", label = "Action Bar 1", prefix = "ActionButton", count = 12, blizz = { "MainActionBar", "MainMenuBar" }, main = true },
    { key = "Bar2", label = "Action Bar 2", prefix = "MultiBarBottomLeftButton", count = 12, blizz = { "MultiBarBottomLeft" }, page = 6 },
    { key = "Bar3", label = "Action Bar 3", prefix = "MultiBarBottomRightButton", count = 12, blizz = { "MultiBarBottomRight" }, page = 5 },
    { key = "Bar4", label = "Action Bar 4", prefix = "MultiBarRightButton", count = 12, blizz = { "MultiBarRight" }, page = 3 },
    { key = "Bar5", label = "Action Bar 5", prefix = "MultiBarLeftButton", count = 12, blizz = { "MultiBarLeft" }, page = 4 },
    { key = "Bar6", label = "Action Bar 6", prefix = "MultiBar5Button", count = 12, blizz = { "MultiBar5" }, page = 13 },
    { key = "Bar7", label = "Action Bar 7", prefix = "MultiBar6Button", count = 12, blizz = { "MultiBar6" }, page = 14 },
    { key = "Bar8", label = "Action Bar 8", prefix = "MultiBar7Button", count = 12, blizz = { "MultiBar7" }, page = 15 },
    -- bars 9 and 10 (EllesmereUI's extra bars, action pages 2 and 10): the game has no buttons for
    -- them, so they borrow bar 7's / bar 8's while that bar is off in HUF; their keys are HUF's own
    -- (override bindings, from the EllesmereUI import or the settings)
    { key = "Bar9", label = "Action Bar 9", prefix = "MultiBar6Button", count = 12, blizz = { "MultiBar6" }, page = 2, lender = "Bar7", bind = "EUI_BAR9_BUTTON" },
    { key = "Bar10", label = "Action Bar 10", prefix = "MultiBar7Button", count = 12, blizz = { "MultiBar7" }, page = 10, lender = "Bar8", bind = "EUI_BAR10_BUTTON" },
    { key = "StanceBar", label = "Stance Bar", prefix = "StanceButton", count = 10, blizz = { "StanceBar", "StanceBarFrame" }, stance = true },
    { key = "PetBar", label = "Pet Bar", prefix = "PetActionButton", count = 10, blizz = { "PetActionBar", "PetActionBarFrame" }, pet = true },
}
AB.BARS = BARS
local BY_KEY = {}
for _, b in ipairs(BARS) do BY_KEY[b.key] = b end
AB.BY = BY_KEY

-- bar 1's page, as the game picks it: Shift + wheel (pages 2-6) first, then the bonus bars
-- (warrior stances, druid forms, rogue stealth, ...: pages 7-10), mind control (12)
local MAIN_PAGING = "[possessbar]12;[bonusbar:5]11;[actionbar:2]2;[actionbar:3]3;[actionbar:4]4;[actionbar:5]5;[actionbar:6]6;"
    .. "[bonusbar:1]7;[bonusbar:2]8;[bonusbar:3]9;[bonusbar:4]10;1"

-- frames that must never end up hidden with Blizzard's main bar (they live in it on some UIs)
local KEEP = { "MicroMenuContainer", "MicroMenu", "BagsBar", "MainMenuBarBackpackButton",
    "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer", "StatusTrackingBarManager" }

local function DB() return ns.db and ns.db.actionBars end
local function S(key) local d = DB() return d and d.bars and d.bars[key] end

local hidden = CreateFrame("Frame", nil, UIParent)
hidden:Hide()

local frames = {}      -- key -> HUF bar frame
local taken = {}       -- key -> true: the game's buttons are in HUF's bar (until a reload)
local skinned = {}     -- button -> parts
local stats = { layouts = 0, relaid = 0, parked = 0, kept = 0, deferred = 0 }

local function Buttons(info)
    local list = {}
    for i = 1, info.count do
        local b = _G[info.prefix .. i]
        if b then list[#list + 1] = b end
    end
    return list
end

local function Contains(frame, child)
    local p = child and child.GetParent and child:GetParent()
    local n = 0
    while p and n < 20 do
        if p == frame then return true end
        p = p:GetParent()
        n = n + 1
    end
    return false
end

---------------------------------------------------------------------------
-- Blizzard's bars
---------------------------------------------------------------------------
local parked = {}
local function Park(frame)
    if parked[frame] then return end
    for _, name in ipairs(KEEP) do
        local k = _G[name]
        if k and Contains(frame, k) then
            -- its micro menu / bags / XP bar live in it: only its own art goes
            stats.kept = stats.kept + 1
            for _, part in ipairs({ "EndCaps", "BorderArt", "ActionBarPageNumber", "Background", "ArtFrame" }) do
                local t = frame[part]
                if type(t) == "table" and t.Hide then pcall(t.Hide, t) end
            end
            parked[frame] = "art"
            return
        end
    end
    parked[frame] = true
    frame:SetParent(hidden)
    stats.parked = stats.parked + 1
    -- Edit Mode or Blizzard code may give it another parent: park it again (next frame)
    hooksecurefunc(frame, "SetParent", function(self, parent)
        if parent ~= hidden then
            C_Timer.After(0, function() ns.RunOOC("ab:park", function() if self:GetParent() ~= hidden then self:SetParent(hidden) end end) end)
        end
    end)
end

---------------------------------------------------------------------------
-- Look
---------------------------------------------------------------------------
-- the game's own button art: away (alpha 0, so the game setting it again changes nothing)
function AB.HideArt(b)
    local nt = b.GetNormalTexture and b:GetNormalTexture()
    if nt then nt:SetAlpha(0) end
    for _, k in ipairs({ "SlotArt", "SlotBackground", "Border", "Background", "FloatingBG", "IconBorder" }) do
        local t = b[k]
        if type(t) == "table" and t.SetAlpha then t:SetAlpha(0) end
    end
    local fb = _G[(b:GetName() or "") .. "FloatingBG"]
    if fb then fb:SetAlpha(0) end
end

local function Skin(b, scale, gap)
    local d = DB()
    local p = skinned[b]
    if not p then
        p = {}
        skinned[b] = p
        local icon = b.icon or b.Icon or _G[(b:GetName() or "") .. "Icon"]
        p.icon = icon
        if icon then
            if b.IconMask and icon.RemoveMaskTexture then pcall(icon.RemoveMaskTexture, icon, b.IconMask) end
        end
        -- the game draws its button art again (empty slot backgrounds after showing the
        -- grid, ...): hidden again right after
        if b.UpdateButtonArt then hooksecurefunc(b, "UpdateButtonArt", function(self) if AB.HideArt then AB.HideArt(self) end end) end
        -- the slot behind the icon: flat and dark
        p.bg = b:CreateTexture(nil, "BACKGROUND", nil, -8)
        p.bg:SetAllPoints(b)
        p.border = ns.UI.Border(b, 0, 0, 0, 1)
        for _, t in ipairs(p.border.edges) do t:SetDrawLayer("OVERLAY", 7) end
        p.hotkey = b.HotKey or _G[(b:GetName() or "") .. "HotKey"]
        p.name = b.Name or _G[(b:GetName() or "") .. "Name"]
    end
    -- the game's round frame art and the slot pictures: away (the game sets the art
    -- again now and then: alpha stays)
    AB.HideArt(b)
    if p.icon then
        local z = d.iconZoom or 0.055
        p.icon:SetTexCoord(z, 1 - z, z, 1 - z)
    end
    -- the slot: see-through black (EllesmereUI's: black at 60 %)
    p.bg:SetColorTexture(0, 0, 0, d.slotAlpha or 0.6)
    -- the border: one screen pixel whatever the button's scale
    local px = (PixelUtil and PixelUtil.GetNearestPixelSize) and PixelUtil.GetNearestPixelSize(1, b:GetEffectiveScale(), 1) or (1 / (scale or 1))
    local size = (d.border or 1) * px
    local e = p.border.edges
    -- "Fill the gaps": the border reaches out over half the spacing on each side, so two
    -- neighbours' borders meet in one solid line (EllesmereUI's grid); off: a 1 px border
    -- inside the button and see-through gaps
    local g = (d.fillGaps ~= false and (gap or 0) > 0) and ((gap / 2) / (scale or 1)) or 0
    if d.fillGaps ~= false and (gap or 0) > 0 then size = size + g end
    e[1]:ClearAllPoints(); e[1]:SetPoint("TOPLEFT", b, "TOPLEFT", -g, g); e[1]:SetPoint("TOPRIGHT", b, "TOPRIGHT", g, g)
    e[2]:ClearAllPoints(); e[2]:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", -g, -g); e[2]:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", g, -g)
    e[3]:ClearAllPoints(); e[3]:SetPoint("TOPLEFT", b, "TOPLEFT", -g, g); e[3]:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", -g, -g)
    e[4]:ClearAllPoints(); e[4]:SetPoint("TOPRIGHT", b, "TOPRIGHT", g, g); e[4]:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", g, -g)
    e[1]:SetHeight(size); e[2]:SetHeight(size); e[3]:SetWidth(size); e[4]:SetWidth(size)
    p.border:SetShown((d.border or 1) > 0)
    local c = d.borderAccent and { r = ns.ACCENT[1], g = ns.ACCENT[2], b = ns.ACCENT[3] } or d.borderColor or { r = 0, g = 0, b = 0 }
    p.border:SetColor(c.r, c.g, c.b, 1)
end

-- the key: white and outlined, top right (empty slots too, as EllesmereUI); the stack count bottom right
local function Font() return (ns.FontPath and ns.FontPath("GLOBAL")) or STANDARD_TEXT_FONT end
local function PlaceTexts(b)
    local p = skinned[b]
    if not (p and p.hotkey) then return end
    local d = DB()
    p.hotkey:ClearAllPoints()
    p.hotkey:SetPoint("TOPRIGHT", b, "TOPRIGHT", -2, -2)
    p.hotkey:SetJustifyH("RIGHT")
    -- a borrowed bar's own key (bars 9 / 10): the game's button doesn't know it
    if b.hufKey then p.hotkey:SetText(GetBindingText and GetBindingText(b.hufKey, true) or b.hufKey) p.hotkey:Show() end
    local c = d.keyColor or { r = 1, g = 1, b = 1 }
    p.hotkey:SetTextColor(c.r, c.g, c.b)
end

local function Texts(b, s)
    local p = skinned[b]
    if not p then return end
    local d = DB()
    local scale = b:GetScale() or 1
    if p.hotkey then
        -- sizes in the bar's units: the button itself is scaled
        p.hotkey:SetFont(Font(), (d.keySize or 12) / scale, "OUTLINE")
        p.hotkey:SetAlpha(s.hideHotkey and 0 or 1)
        if not p.hotkeyHooked and b.UpdateHotkeys then
            p.hotkeyHooked = true
            hooksecurefunc(b, "UpdateHotkeys", function(self) PlaceTexts(self) end)
        end
        PlaceTexts(b)
    end
    local count = b.Count or _G[(b:GetName() or "") .. "Count"]
    if count then
        count:SetFont(Font(), (d.countSize or 14) / scale, "OUTLINE")
        count:ClearAllPoints()
        count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
    end
    if p.name then p.name:SetAlpha(s.hideMacro and 0 or 1) end
end

---------------------------------------------------------------------------
-- Layout (out of combat only)
---------------------------------------------------------------------------
-- unlock mode: the stance and pet bars show even without forms / a pet, so they can be placed
local previewing = false

local function Shown(info, list)
    if info.stance and not previewing then
        local n = GetNumShapeshiftForms and GetNumShapeshiftForms() or 0
        return math.min(n, #list)
    end
    return #list
end

local function Layout(info)
    local s, f = S(info.key), frames[info.key]
    if not (s and f and taken[info.key]) then return end
    if InCombatLockdown() then stats.deferred = stats.deferred + 1 ns.RunOOC("ab:layout", AB.Apply) return end
    stats.layouts = stats.layouts + 1
    local list = Buttons(info)
    local n = math.max(1, math.min(s.buttons or info.count, Shown(info, list)))
    local per = math.max(1, math.min(s.perRow or 12, n))
    local rows = math.ceil(n / per)
    local size, gap = s.size or 36, s.spacing or 2
    for i, b in ipairs(list) do
        local base = b.hufBase or b:GetWidth()
        if not b.hufBase and base and base > 0 then b.hufBase = base end
        base = b.hufBase or 36
        local scale = size / base
        b:SetScale(scale)
        b:ClearAllPoints()
        if i <= n then
            local col = (i - 1) % per
            local row = math.floor((i - 1) / per)
            if s.rowsUp then
                -- the first row at the bottom, new rows above it (EllesmereUI's "grow up")
                b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", col * (size + gap) / scale, row * (size + gap) / scale)
            else
                b:SetPoint("TOPLEFT", f, "TOPLEFT", col * (size + gap) / scale, -row * (size + gap) / scale)
            end
            if info.stance or info.pet then b:Show() end
        else
            -- past the chosen count: kept out of sight (the game still owns its key binding)
            b:SetPoint("TOPLEFT", f, "TOPLEFT", -10000, 10000)
        end
        Skin(b, scale, gap)
        Texts(b, s)
    end
    f:SetSize(per * size + (per - 1) * gap, rows * size + (rows - 1) * gap)
    f.per, f.rows, f.count = per, rows, n
    -- the gaps between the buttons: the slot colour too (EllesmereUI's dark grid), or see-through
    -- (the gaps: each button's border reaches over them, Skin)
    f:ClearAllPoints()
    local pt = s.point or { "BOTTOM", "BOTTOM", 0, 40 }
    f:SetPoint(pt[1], UIParent, pt[2], pt[3], pt[4])
end

---------------------------------------------------------------------------
-- Bars
---------------------------------------------------------------------------
local function BarFrame(info)
    local f = frames[info.key]
    if f then return f end
    f = CreateFrame("Frame", "HUFActionBar" .. info.key, UIParent, "SecureHandlerStateTemplate")
    f:SetSize(1, 1)
    f:SetFrameStrata("LOW")
    f:SetClampedToScreen(true)
    f.info = info
    frames[info.key] = f
    if info.main then
        -- the page for every button: ChildUpdate reaches each button's _childupdate-actionpage
        f:SetAttribute("_onstate-page", [[
            self:SetAttribute("actionpage", newstate)
            control:ChildUpdate("actionpage", newstate)
        ]])
    end
    -- unlock mode: HUF's mover box, snapping and guides
    ns.RegisterMover("HUF_AB_" .. info.key, {
        label = info.label,
        frame = f,
        preview = (info.stance or info.pet) and function(on)
            ns.RunOOC("ab:preview:" .. info.key, function()
                previewing = on and true or false
                if info.pet then
                    if on then UnregisterStateDriver(f, "visibility")
                    else RegisterStateDriver(f, "visibility", "[@pet,exists,nopossessbar]show;hide") end
                end
                if taken[info.key] then Layout(info) Visible(info) end
            end)
        end or nil,
        shown = function() return taken[info.key] and S(info.key).enabled end,
        save = function(fr)
            local s = S(info.key)
            s.point = { "BOTTOMLEFT", "BOTTOMLEFT", math.floor(fr:GetLeft() + 0.5), math.floor(fr:GetBottom() + 0.5) }
        end,
        settings = function() if ns.OpenConfigTab then ns.OpenConfigTab("actionbars", info.key) end end,
        get = function() local s = S(info.key) return s and s.point end,
        set = function(v) local s = S(info.key) if s and type(v) == "table" then s.point = v AB.Apply() end end,
        -- unlock mode's corner grips: the grid closest to the dragged box, the buttons keep
        -- their size (drag it tall and narrow and the bar turns vertical); Shift + drag: size
        resize = {
            get = function() return f:GetWidth(), f:GetHeight() end,
            set = function(w, h)
                local s = S(info.key)
                local n = math.max(1, math.min(s.buttons or info.count, f.count or info.count))
                local gap, size = s.spacing or 2, s.size or 36
                local best, bestD
                for per = 1, n do
                    local rows = math.ceil(n / per)
                    -- only grids without a half-empty last row (12: 1, 2, 3, 4, 6, 12 per row)
                    if per * rows - n < per then
                        local bw, bh = per * size + (per - 1) * gap, rows * size + (rows - 1) * gap
                        local dd = math.abs(bw - w) + math.abs(bh - h)
                        if not bestD or dd < bestD then best, bestD = per, dd end
                    end
                end
                if not best or best == s.perRow then return end
                s.perRow = best
                Layout(info)
            end,
            -- Shift + drag: the button size only (rows and columns stay)
            scale = {
                get = function() return S(info.key).size or 36 end,
                set = function(v)
                    S(info.key).size = math.max(16, math.min(64, math.floor(v + 0.5)))
                    Layout(info)
                end,
            },
        },
    })
    return f
end

local function Take(info)
    if taken[info.key] then return true end
    local f = BarFrame(info)
    local list = Buttons(info)
    if #list == 0 then return false end
    for _, b in ipairs(list) do
        b:SetParent(f)
        if info.main then
            b:SetAttribute("_childupdate-actionpage", [[ self:SetAttribute("actionpage", message) ]])
        elseif info.page then
            b:SetAttribute("actionpage", info.page)
        end
    end
    if info.main then
        RegisterStateDriver(f, "page", MAIN_PAGING)
        local page = SecureCmdOptionParse and SecureCmdOptionParse(MAIN_PAGING) or "1"
        f:SetAttribute("actionpage", tonumber(page) or 1)
        for _, b in ipairs(list) do b:SetAttribute("actionpage", tonumber(page) or 1) end
    end
    if info.pet then
        RegisterStateDriver(f, "visibility", "[@pet,exists,nopossessbar]show;hide")
    end
    -- Blizzard's own bar goes away; its layout calls put the buttons back in ours
    for _, name in ipairs(info.blizz) do
        local bz = _G[name]
        if bz then
            Park(bz)
            for _, m in ipairs({ "UpdateGridLayout", "UpdateButtonLayout", "Layout", "Update", "UpdateState" }) do
                if type(bz[m]) == "function" and not (bz.hufHooked and bz.hufHooked[m]) then
                    bz.hufHooked = bz.hufHooked or {}
                    bz.hufHooked[m] = true
                    hooksecurefunc(bz, m, function()
                        stats.relaid = stats.relaid + 1
                        C_Timer.After(0, function() Layout(info) end)
                    end)
                end
            end
        end
    end
    taken[info.key] = true
    return true
end

-- bars 9 / 10: their keys (override bindings on HUF's bar, the game's own bindings stay)
local function BindKeys(info)
    local f, s = frames[info.key], S(info.key)
    if not (f and s and info.bind) then return end
    ClearOverrideBindings(f)
    local list = Buttons(info)
    for i, b in ipairs(list) do
        local key = type(s.keys) == "table" and s.keys[i] or nil
        b.hufKey = (type(key) == "string" and key ~= "") and key or nil
        if b.hufKey then SetOverrideBindingClick(f, false, b.hufKey, b:GetName(), "LeftButton") end
        PlaceTexts(b)
    end
end

-- a borrowing bar (9 / 10) runs only while the bar it borrows from is off
local function Allowed(info)
    if info.lender then
        local l = S(info.lender)
        return not (l and l.enabled) and not taken[info.lender]
    end
    -- a lender whose buttons a borrowing bar already holds waits for a reload
    for _, o in ipairs(BARS) do
        if o.lender == info.key and taken[o.key] then return false end
    end
    return true
end
AB.Allowed = function(key) local info = BY_KEY[key] return info and Allowed(info) end

local function Visible(info)
    local f = frames[info.key]
    if not f then return end
    if previewing and (info.stance or info.pet) then f:Show() return end
    if info.pet then return end   -- the pet bar: its state driver
    if info.stance then
        local n = GetNumShapeshiftForms and GetNumShapeshiftForms() or 0
        f:SetShown(n > 0)
    else
        f:Show()
    end
end

function AB.Apply()
    local d = DB()
    if not (d and d.enabled) then return end
    if InCombatLockdown() then stats.deferred = stats.deferred + 1 ns.RunOOC("ab:apply", AB.Apply) return end
    for _, info in ipairs(BARS) do
        local s = S(info.key)
        if s and s.enabled and Allowed(info) then
            local ok, err = pcall(Take, info)
            if not ok then ns.LogError("action bar " .. info.key, err) end
            if taken[info.key] then
                Layout(info)
                Visible(info)
                if info.bind then BindKeys(info) end
            end
        end
    end
    AB.Fade()
end

---------------------------------------------------------------------------
-- Mouseover: a bar shows while the mouse is over it (or an action is on the cursor)
---------------------------------------------------------------------------
local fadeTicker
function AB.Fade()
    local any = false
    for key, f in pairs(frames) do
        local s = S(key)
        if s and s.mouseover and taken[key] then any = true else f:SetAlpha(1) end
    end
    if any and not fadeTicker then
        fadeTicker = C_Timer.NewTicker(0.1, function()
            local drag = GetCursorInfo and GetCursorInfo() ~= nil
            for key, f in pairs(frames) do
                local s = S(key)
                if s and s.mouseover and taken[key] then
                    f:SetAlpha((drag or f:IsMouseOver()) and 1 or 0)
                end
            end
        end)
    elseif not any and fadeTicker then
        fadeTicker:Cancel()
        fadeTicker = nil
    end
end

-- forms learned / changed: the stance bar's count and visibility
-- keys changed or an action placed: the key text again (the game resets it)
local slotEv = CreateFrame("Frame")
slotEv:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
slotEv:RegisterEvent("UPDATE_BINDINGS")
slotEv:SetScript("OnEvent", function()
    if not (DB() and DB().enabled) then return end
    for b in pairs(skinned) do PlaceTexts(b) end
end)

local ev = CreateFrame("Frame")
ev:RegisterEvent("UPDATE_SHAPESHIFT_FORMS")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function()
    if not (DB() and DB().enabled) then return end
    ns.RunOOC("ab:stance", function()
        local info = BY_KEY.StanceBar
        if taken.StanceBar then Layout(info) Visible(info) end
    end)
end)

---------------------------------------------------------------------------
-- EllesmereUI's action bars -> HUF's (same bar keys: MainBar, Bar2-8, StanceBar, PetBar)
---------------------------------------------------------------------------
local EUI_FOLDER = "EllesmereUIActionBars"

local function Copy(t)
    if type(t) ~= "table" then return t end
    local o = {}
    for k, v in pairs(t) do o[k] = Copy(v) end
    return o
end

-- Ellesmere's action bar settings: its loaded module's, else the copy in its active profile
local function EllesmereLive()
    local EUI = _G.EllesmereUI
    if type(EUI) == "table" and type(EUI.SnapshotAllAddons) == "function" then
        local ok, data = pcall(EUI.SnapshotAllAddons)
        local a = ok and type(data) == "table" and type(data.addons) == "table" and data.addons[EUI_FOLDER]
        if type(a) == "table" and type(a.bars) == "table" then return a end
    end
    local db = _G.EllesmereUIDB
    local prof = type(db) == "table" and type(db.profiles) == "table" and db.profiles[db.activeProfile or "Default"]
    local a = type(prof) == "table" and type(prof.addons) == "table" and prof.addons[EUI_FOLDER]
    if type(a) == "table" and type(a.bars) == "table" then return a end
    return nil
end

-- the keys bound to EllesmereUI's bar 9 / 10 buttons (its key binding commands exist while it is loaded)
local function EllesmereKeys()
    local out, any = {}, false
    for _, info in ipairs(BARS) do
        if info.bind then
            local k = {}
            for i = 1, info.count do
                local key = GetBindingKey and GetBindingKey(info.bind .. i)
                k[i] = key or ""
                if key then any = true end
            end
            out[info.key] = k
        end
    end
    return any and out or nil
end

-- while EllesmereUI is on, HUF keeps a copy of the parts it imports (bars and places), so
-- the import still works after EllesmereUI is switched off (its saved settings only load with it)
local function KeepCopy()
    local a = EllesmereLive()
    if not (a and HUFDB) then return end
    local bars = {}
    for key in pairs(BY_KEY) do bars[key] = Copy(a.bars[key]) end
    for _, key in ipairs({ "XPBar", "RepBar", "MicroBar", "BagBar", "QueueStatus" }) do bars[key] = Copy(a.bars[key]) end
    local old = HUFDB.ellesmereActionBars
    HUFDB.ellesmereActionBars = { time = time(), bars = bars, barPositions = Copy(a.barPositions),
        _keys = EllesmereKeys() or (type(old) == "table" and old._keys) or nil }
end

function AB.EllesmereSource()
    local a = EllesmereLive()
    if a then
        local src = {}
        for k, v in pairs(a) do src[k] = v end
        src._keys = EllesmereKeys() or (HUFDB and type(HUFDB.ellesmereActionBars) == "table" and HUFDB.ellesmereActionBars._keys) or nil
        return src, "EllesmereUI"
    end
    local c = HUFDB and HUFDB.ellesmereActionBars
    if type(c) == "table" and type(c.bars) == "table" then
        return c, ("the copy HUF kept on %s"):format(date("%Y-%m-%d %H:%M", c.time or 0))
    end
    return nil
end

local function Num(v, d) return type(v) == "number" and v or d end

-- Ellesmere's settings (src: its EllesmereUIActionBars table) into an actionBars table
function AB.ConvertEllesmere(src, out)
    local n = 0
    for _, info in ipairs(BARS) do
        local eb = type(src.bars) == "table" and src.bars[info.key]
        local s = out.bars[info.key]
        if type(eb) == "table" and type(s) == "table" then
            n = n + 1
            s.enabled = eb.enabled ~= false and not eb.alwaysHidden
            -- Ellesmere uses its override counts first (what its bar shows)
            s.buttons = math.max(1, math.min(info.count, math.floor(Num(eb.overrideNumIcons, Num(eb.numIcons, info.count)) + 0.5)))
            local rows = math.max(1, math.floor(Num(eb.overrideNumRows, Num(eb.numRows, 1)) + 0.5))
            if eb.orientation == "vertical" then
                -- a vertical bar: its rows count is the number of columns
                s.perRow = math.max(1, math.min(s.buttons, rows))
                s.rowsUp = false
            else
                s.perRow = math.max(1, math.ceil(s.buttons / rows))
                local grow = type(eb.growDirection) == "string" and eb.growDirection:upper() or "UP"
                s.rowsUp = (grow == "UP" or grow == "CENTER")
            end
            s.size = math.max(16, math.min(64, math.floor(Num(eb.buttonWidth, s.size or 36) + 0.5)))
            s.spacing = math.max(0, math.min(20, math.floor(Num(eb.buttonPadding, s.spacing or 2) + 0.5)))
            s.mouseover = eb.mouseoverEnabled and true or false
            s.hideHotkey = eb.hideKeybind and true or false
            s.hideMacro = eb.hideMacroText and true or false
            local p = type(src.barPositions) == "table" and src.barPositions[info.key]
            if type(p) == "table" and type(p.x) == "number" and type(p.y) == "number" then
                s.point = { p.point or "CENTER", p.relPoint or "CENTER", math.floor(p.x + 0.5), math.floor(p.y + 0.5) }
            end
        end
    end
    -- XP / reputation bars, micro menu, bag bar, queue button (ExtraBars.lua)
    local x = out.extra
    if type(x) == "table" and type(src.bars) == "table" then
        local pos = type(src.barPositions) == "table" and src.barPositions or {}
        local function Place(t, ek)
            local p = pos[ek]
            if type(p) == "table" and type(p.x) == "number" and type(p.y) == "number" then
                t.point = { p.point or "CENTER", p.relPoint or "CENTER", math.floor(p.x + 0.5), math.floor(p.y + 0.5) }
            end
        end
        for hk, ek in pairs({ xp = "XPBar", rep = "RepBar" }) do
            local eb, t = src.bars[ek], x[hk]
            if type(eb) == "table" and type(t) == "table" then
                n = n + 1
                t.enabled = not eb.alwaysHidden
                t.width = math.max(50, math.floor(Num(eb.width, t.width) + 0.5))
                t.height = math.max(2, math.floor(Num(eb.height, t.height) + 0.5))
                t.textSize = math.max(6, math.floor(Num(eb.textSize, t.textSize) + 0.5))
                t.mouseover = eb.mouseoverEnabled and true or false
                Place(t, ek)
            end
        end
        for hk, ek in pairs({ micro = "MicroBar", bags = "BagBar", queue = "QueueStatus" }) do
            local eb, t = src.bars[ek], x[hk]
            if type(eb) == "table" and type(t) == "table" then
                n = n + 1
                t.enabled = true
                t.hidden = eb.alwaysHidden and true or false
                t.mouseover = eb.mouseoverEnabled and true or false
                Place(t, ek)
            end
        end
    end

    -- bars 9 / 10: the keys bound to EllesmereUI's buttons for them
    for _, info in ipairs(BARS) do
        local keys = info.bind and type(src._keys) == "table" and src._keys[info.key]
        if type(keys) == "table" and out.bars[info.key] then
            local k = {}
            for i = 1, info.count do k[i] = type(keys[i]) == "string" and keys[i] or "" end
            out.bars[info.key].keys = k
        end
    end
    local main = type(src.bars) == "table" and src.bars.MainBar
    if type(main) == "table" then
        out.fillGaps = false      -- EllesmereUI: a thin border on each button, see-through gaps
        if type(src.iconZoom) == "number" then out.iconZoom = math.max(0, math.min(0.3, src.iconZoom / 100)) end
        if type(src.slotBgOpacity) == "number" then out.slotAlpha = math.max(0, math.min(1, src.slotBgOpacity / 100)) end
        out.keySize = math.max(6, math.min(24, math.floor(Num(main.keybindFontSize, 12) + 0.5)))
        out.countSize = math.max(6, math.min(24, math.floor(Num(main.countFontSize, 14) + 0.5)))
        local kc = main.keybindFontColor
        if type(kc) == "table" and type(kc.r) == "number" then out.keyColor = { r = kc.r, g = kc.g, b = kc.b } end
        out.border = main.borderEnabled == false and 0 or math.max(0, math.min(3, math.floor(Num(main.borderSize, 1) + 0.5)))
        local c = main.borderColor
        if type(c) == "table" and type(c.r) == "number" then
            out.borderColor = { r = c.r, g = c.g, b = c.b }
            out.borderAccent = false
        end
    end
    return n
end

-- the button on the Action Bars page: into the active profile, switched on
function AB.ImportEllesmere()
    local src, from = AB.EllesmereSource()
    if not src then
        return false, "No EllesmereUI action bar settings found: switch EllesmereUI on once (HUF then keeps a copy), or use an EllesmereUI profile string in General > Profiles."
    end
    local n = AB.ConvertEllesmere(src, DB())
    if n == 0 then return false, "EllesmereUI's settings have no action bars." end
    DB().enabled = true
    AB.Apply()
    local IsLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
    local both = IsLoaded and IsLoaded(EUI_FOLDER)
    return true, ("%d bars taken from %s.%s"):format(n, from,
        both and " Switch EllesmereUI Action Bars off (AddOns list) and reload, or both bars show." or "")
end

ns.OnLogin(function()
    pcall(KeepCopy)
    local IsLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
    if DB() and DB().enabled and IsLoaded and IsLoaded(EUI_FOLDER) then
        ns.Print("EllesmereUI Action Bars is on too, so the action bars show twice. Switch one of them off (HUF: /huf > Action Bars).")
    end
end)
ns.OnLogin(AB.Apply)
ns.OnRefresh(AB.Apply)

function AB.Taken(key) return taken[key] and true or false end

function AB.Report(add)
    local d = DB() or {}
    local list = {}
    for _, info in ipairs(BARS) do
        if taken[info.key] then list[#list + 1] = info.key .. "=" .. #Buttons(info) end
    end
    add(("action bars: on=%s taken=%s layouts=%d relaid=%d parked=%d kept=%d deferred=%d"):format(tostring(d.enabled),
        #list > 0 and table.concat(list, ",") or "none", stats.layouts, stats.relaid, stats.parked, stats.kept, stats.deferred))
end
