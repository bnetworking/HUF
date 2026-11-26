-- HUF: hide the game's menu bar reminders (General > Frames & Features).
-- The yellow boxes pointing at a menu bar button ("You have unspent Talent
-- points.", unspent Legacy points, new collection items, ...). The game
-- shows them through MainMenuMicroButton_ShowAlert, on this client as a
-- HelpTip anchored to the button (older clients: an alert frame per button,
-- e.g. TalentMicroButtonAlert). HUF never calls the game's alert functions
-- (that taints them, EllesmereUI's note); it watches with hooksecurefunc and
-- hides the box on the next frame.
-- global.hideReminders = { talents, legacy, other }

local _, ns = ...

local function Cfg() return ns.db and ns.db.global.hideReminders end

-- which switch a reminder belongs to, from its button's (or alert's) name
local function Kind(region)
    local name = region and region.GetName and region:GetName()
    if type(name) ~= "string" then return nil end
    if not (name:find("MicroButton") or name:find("MicroMenu")) then return nil end
    if name:find("Talent") or name:find("PlayerSpells") then return "talents", name end
    if name:find("Legacy") then return "legacy", name end
    return "other", name
end

local function Wanted(kind)
    local c = Cfg()
    return kind and c and c[kind] and true or false
end

-- HelpTip path: hide the box that shows this info
local pending = {}
local function HideTips()
    local pool = HelpTip and HelpTip.framePool
    if not (pool and pool.EnumerateActive) then wipe(pending) return end
    for tip in pool:EnumerateActive() do
        local why = tip.info and pending[tip.info]
        if why and tip:IsShown() then
            tip:Hide()
            ns.Log("reminders", "hid %s reminder at %s", why[1], why[2])
        end
    end
    wipe(pending)
end

local hooked = false
local function Hook()
    if hooked then return end
    hooked = true
    if HelpTip and HelpTip.Show then
        hooksecurefunc(HelpTip, "Show", function(_, parent, info, relativeRegion)
            if type(info) ~= "table" then return end
            local kind, name = Kind(relativeRegion)
            if not kind then kind, name = Kind(parent) end
            if not Wanted(kind) then return end
            pending[info] = { kind, name }
            C_Timer.After(0, HideTips)
        end)
    end
    -- older clients: one alert frame per button
    if type(MainMenuMicroButton_ShowAlert) == "function" then
        hooksecurefunc("MainMenuMicroButton_ShowAlert", function(alert)
            if not (alert and alert.GetObjectType and alert.Hide) then return end
            local name = alert.GetName and alert:GetName() or ""
            if not name:find("Alert") then return end   -- a button: the HelpTip hook has it
            local kind = Kind(alert)
            if not Wanted(kind) then return end
            C_Timer.After(0, function()
                if alert:IsShown() then
                    alert:Hide()
                    ns.Log("reminders", "hid %s reminder %s", kind, name)
                end
            end)
        end)
    end
end

-- boxes already up when a switch is turned on
local function HideOpen()
    local pool = HelpTip and HelpTip.framePool
    if not (pool and pool.EnumerateActive) then return end
    for tip in pool:EnumerateActive() do
        if tip:IsShown() and tip.info then
            local kind, name = Kind(tip.relativeRegion)
            if not kind then kind, name = Kind(tip:GetParent()) end
            if not kind and tip.info.system == "MicroButtons" then kind, name = "other", "MicroButtons" end
            if Wanted(kind) then pending[tip.info] = { kind, name } end
        end
    end
    if next(pending) then HideTips() end
end

local function Apply()
    local c = Cfg()
    if not c then return end
    if c.talents or c.legacy or c.other then
        Hook()
        pcall(HideOpen)
    end
end

ns.OnLogin(Apply)
ns.OnRefresh(Apply)

---------------------------------------------------------------------------
-- Game menu (Esc) buttons, shared by HUF and MMT (whichever loads first
-- sets it up, the newer code version runs it): the buttons sit in the
-- game menu under Shop, below EllesmereUI's buttons when it has them, as
-- wide and high as the menu's own buttons and in their look (EllesmereUI's
-- dark skin when the menu has it). The menu's later buttons move down by as
-- much and the menu grows by as much after every other change to it, so
-- EllesmereUI's own moving and sizing stay as they are.
---------------------------------------------------------------------------
local GAME_MENU_VERSION = 3
local function GameMenuRegistry()
    local menu = _G.GameMenuFrame
    if not menu then return nil end
    local reg = _G.HivemindGameMenu
    if type(reg) ~= "table" then
        reg = { entries = {} }
        _G.HivemindGameMenu = reg
        if menu.Layout then
            hooksecurefunc(menu, "Layout", function() if reg.Layout then pcall(reg.Layout) end end)
        end
    end
    if (reg.version or 0) < GAME_MENU_VERSION then
        reg.version = GAME_MENU_VERSION
        -- the look of the menu's own button `like` on button b
        reg.Style = function(b, like)
            local skinned = like and like.Left and like.Left:GetAlpha() == 0
            if not b.hmInset then
                local inset = CreateFrame("Frame", nil, b)
                inset:SetPoint("TOPLEFT", 2, -2)
                inset:SetPoint("BOTTOMRIGHT", -2, 2)
                inset:SetFrameLevel(b:GetFrameLevel())
                local bg = inset:CreateTexture(nil, "BACKGROUND", nil, -6)
                bg:SetAllPoints()
                bg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
                for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
                    local t = inset:CreateTexture(nil, "BORDER")
                    t:SetColorTexture(0.32, 0.32, 0.32, 1)
                    if side == "TOP" or side == "BOTTOM" then
                        t:SetPoint(side .. "LEFT") t:SetPoint(side .. "RIGHT") t:SetHeight(1)
                    else
                        t:SetPoint("TOP" .. side) t:SetPoint("BOTTOM" .. side) t:SetWidth(1)
                    end
                end
                local hl = b:CreateTexture(nil, "HIGHLIGHT")
                hl:SetAllPoints(inset)
                hl:SetColorTexture(1, 1, 1, 0.1)
                b.hmInset, b.hmHighlight = inset, hl
                -- every texture of the button's own art (pieces, normal / pushed /
                -- highlight / disabled), kept hidden while the menu is skinned
                local art, seen = {}, {}
                local function Take(t)
                    if t and t ~= hl and not seen[t] and t.IsObjectType and t:IsObjectType("Texture") then
                        seen[t] = true
                        art[#art + 1] = t
                        hooksecurefunc(t, "SetAlpha", function(s, a) if b.hmSkinned and a > 0 then s:SetAlpha(0) end end)
                    end
                end
                for _, r in ipairs({ b:GetRegions() }) do Take(r) end
                Take(b:GetNormalTexture()) Take(b:GetPushedTexture())
                Take(b:GetHighlightTexture()) Take(b:GetDisabledTexture())
                b.hmArt = art
            end
            b.hmSkinned = skinned and true or false
            for _, t in ipairs(b.hmArt) do t:SetAlpha(skinned and 0 or 1) end
            local label = b:GetFontString()
            if label then
                label:ClearAllPoints()
                label:SetPoint("CENTER", 0, 0)
            end
            b.hmInset:SetShown(b.hmSkinned)
            b.hmHighlight:SetShown(b.hmSkinned)
            -- the same font and text colour as the menu's button
            local fs, lfs = b:GetFontString(), like and like:GetFontString()
            if fs and lfs then
                local font, size, flags = lfs:GetFont()
                if font then fs:SetFont(font, size or 13, flags or "") end
                local r, g, bl = lfs:GetTextColor()
                if r then fs:SetTextColor(r, g, bl, 1) end
            end
        end
        reg.Layout = function()
            local entries = reg.entries
            if InCombatLockdown() then
                for _, e in ipairs(entries) do e.button:Hide() end
                return
            end
            -- under Shop (else Options), like EllesmereUI's buttons
            local anchor
            if menu.buttonPool and menu.buttonPool.EnumerateActive then
                for b in menu.buttonPool:EnumerateActive() do
                    local t = b:GetText()
                    if t == BLIZZARD_STORE then anchor = b break
                    elseif t == GAMEMENU_OPTIONS then anchor = b end
                end
            end
            if not anchor then
                for _, e in ipairs(entries) do e.button:Hide() end
                return
            end
            -- below EllesmereUI's buttons when they show
            local last, gap = anchor, -12
            for _, name in ipairs({ "EllesmereUI_GameMenuButton", "EllesmereUI_UnlockMenuButton" }) do
                local eb = _G[name]
                if eb and eb:GetParent() == menu and eb:IsShown() then last, gap = eb, -4 end
            end
            table.sort(entries, function(a, b) return a.order < b.order end)
            local w, h = anchor:GetWidth(), anchor:GetHeight()
            if not (w and w > 0) then w, h = 200, 35 end
            local extra = 0
            for _, e in ipairs(entries) do
                local ok, on = true, true
                if e.shown then ok, on = pcall(e.shown) end
                on = ok and on and true or false
                local b = e.button
                b:SetShown(on)
                if on then
                    b:SetSize(w, h)
                    b:ClearAllPoints()
                    b:SetPoint("TOP", last, "BOTTOM", 0, gap)
                    pcall(reg.Style, b, anchor)
                    extra = extra + h - gap
                    last, gap = b, -4
                end
            end
            if extra <= 0 then return end
            -- the menu's own buttons after the anchor move down (by their layout order)
            local idx = anchor.layoutIndex
            if idx then
                for b in menu.buttonPool:EnumerateActive() do
                    if b.layoutIndex and b.layoutIndex > idx then
                        local p, rel, rp, x, y = b:GetPoint(1)
                        if p then
                            b:ClearAllPoints()
                            b:SetPoint(p, rel, rp, x, (y or 0) - extra)
                        end
                    end
                end
            end
            -- the height: once, after every other hook of this layout (EllesmereUI sets its own)
            reg.extra, reg.added = extra, false
            if not reg.pending then
                reg.pending = true
                C_Timer.After(0, function()
                    reg.pending = false
                    if not reg.added and (reg.extra or 0) > 0 then
                        menu:SetHeight(menu:GetHeight() + reg.extra)
                        reg.added = true
                    end
                end)
            end
        end
    end
    return reg
end
-- order: place among the buttons (HUF 1, MMT 2); shown(): the addon's option
local function AddGameMenuButton(order, text, onClick, shown)
    local reg = GameMenuRegistry()
    if not reg then return nil end
    local menu = _G.GameMenuFrame
    local ok, b = pcall(CreateFrame, "Button", nil, menu, "MainMenuFrameButtonTemplate")
    if not ok or not b then b = CreateFrame("Button", nil, menu, "UIPanelButtonTemplate") end
    b:SetText(text)
    b:Hide()
    b:SetScript("OnClick", function()
        if InCombatLockdown() then return end
        HideUIPanel(menu)
        onClick()
    end)
    reg.entries[#reg.entries + 1] = { order = order, button = b, shown = shown }
    return b
end
-- after an option change while the menu is open
local function RelayoutGameMenu()
    local menu = _G.GameMenuFrame
    if menu and menu:IsShown() and menu.Layout then pcall(menu.Layout, menu) end
end

-- HUF's button (General > Frames & Features: "Button in the game menu (Esc)")
ns.OnLogin(function()
    AddGameMenuButton(1, "HUF", function()
        if ns.ToggleConfig then ns.ToggleConfig(nil, true) end
    end, function() return ns.db and ns.db.global.gameMenuButton ~= false end)
end)
function ns.RelayoutGameMenu() RelayoutGameMenu() end
