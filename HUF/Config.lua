-- HUF: configuration window (/huf). Same layout and look as MMT's window:
-- navigation on the left (GENERAL pages, then one entry per frame with its
-- on/off state), the selected page on the right.

local _, ns = ...
local UI = ns.UI
local A = UI.ACCENT

local WIDTH, HEIGHT, NAV = 880, 620, 150
local NAV_ROW, NAV_HEAD, NAV_TOP = 26, 22, -58
local NAV_VIEW = HEIGHT + NAV_TOP - 92     -- height of the page list (above the unlock button)
local SCALE_MIN, SCALE_MAX, SCALE_STEP = 0.6, 2.0, 0.05
ns.PAGE_W, ns.PAGE_H = WIDTH - NAV - 32, HEIGHT - 56

local window
local pages, order = {}, {}
local current
ns.configPages, ns.ConfigOrder = pages, order     -- the settings search reads them (Search.lua)

-- section: "general", "frames" (PRIMARY FRAMES), "utility" (a tab of the Utility
-- Frames page, not in the list) or "hidden" (built elsewhere, e.g. a window);
-- isOn(): nil = no on/off state
local TITLES = { targettarget = "Target of Target", damagemeter = "Damage Meter" }
function ns.RegisterPage(key, title, section, build, isOn)
    pages[key] = { key = key, title = TITLES[key] or title, section = section, build = build, isOn = isOn }
    order[#order + 1] = key
end

-- the order in the list (others after these, in the order they were registered)
local NAV_ORDER = {
    general = { "general", "utility", "damagemeter", "clickcast", "profiles", "help" },
    frames = { "player", "target", "targettarget", "pet", "focus", "party", "raid", "nameplates" },
}
local function Ordered(section)
    local out, seen = {}, {}
    for _, k in ipairs(NAV_ORDER[section] or {}) do
        if pages[k] and pages[k].section == section then out[#out + 1] = k seen[k] = true end
    end
    for _, k in ipairs(order) do
        if pages[k].section == section and not seen[k] then out[#out + 1] = k end
    end
    return out
end

-- the Utility Frames tabs, in this order; their old page keys still open them
local UTILITY = { { "bags", "Bags" }, { "chat", "Chat" }, { "minimap", "Minimap" }, { "questlog", "Quest Log" }, { "aurabars", "De-/Buff Bar" }, { "tooltips", "Tooltips" } }
local UTIL_OF = {}
for _, t in ipairs(UTILITY) do UTIL_OF[t[1]] = true end
local UTIL_TOP = 28

local function RefreshPage(page)
    if not page or not page.frame then return end
    if page.frame.OnRefresh then pcall(page.frame.OnRefresh) end
    for _, w in ipairs(page.frame.widgets) do w.Refresh() end
end

local function RefreshNav()
    if not window then return end
    for _, tab in ipairs(window.tabs) do tab.Update() end
    for _, wd in ipairs(window.navWidgets) do wd.Refresh() end
end

function ns.RefreshConfig()
    if window and window:IsShown() then
        if window.ApplyLook then window.ApplyLook() end
        RefreshPage(pages[current])
        RefreshNav()
    end
end
ns.OnRefresh(function() ns.RefreshConfig() end)
ns.Listen("PROFILE_CHANGED", function() ns.RefreshConfig() end)

-- a page's frame (built the first time it is needed; hidden until selected)
local function BuildPage(page)
    if page.frame then return page.frame end
    -- a Utility Frames tab lives in that page; a hidden one is built elsewhere
    if page.section == "utility" then
        if pages.utility then BuildPage(pages.utility) end
        return page.frame
    end
    if page.section == "hidden" then return nil end
    local frame = CreateFrame("Frame", nil, window)
    frame:SetPoint("TOPLEFT", NAV + 16, -44)
    frame:SetSize(ns.PAGE_W, ns.PAGE_H)
    frame.widgets = {}
    frame:Hide()
    page.build(frame)
    page.frame = frame
    return frame
end
ns.ConfigBuildPage = BuildPage

local function Select(key)
    if not pages[key] then key = "general" end
    current = key
    ns.Log("config", "page %s", key)
    for k, page in pairs(pages) do
        if page.section ~= "utility" and page.section ~= "hidden" then
            local selected = (k == key)
            if selected and not page.frame then BuildPage(page) end
            if page.frame then page.frame:SetShown(selected) end
        end
    end
    window.pageTitle:SetText(pages[key].title)
    RefreshPage(pages[key])
    RefreshNav()
    if window.ShowInNav then window.ShowInNav(key) end
end

---------------------------------------------------------------------------
-- Navigation
---------------------------------------------------------------------------
local function Tab(parent, page)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(NAV, NAV_ROW)
    local bg = UI.Fill(b, 1, 1, 1, 0)
    local bar = b:CreateTexture(nil, "ARTWORK")
    bar:SetColorTexture(A[1], A[2], A[3], 1)
    bar:SetPoint("TOPLEFT"); bar:SetPoint("BOTTOMLEFT")
    bar:SetWidth(2)
    local label = UI.Label(b, page.title, "GameFontNormal")
    label:SetPoint("LEFT", 16, 0)
    local state = UI.Label(b, "")
    state:SetPoint("RIGHT", -10, 0)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.03)
    b.Update = function()
        local selected = (current == page.key)
        bar:SetShown(selected)
        bg:SetColorTexture(1, 1, 1, selected and 0.06 or 0)
        if page.isOn and not page.isOn() then
            label:SetTextColor(0.4, 0.4, 0.4)
            state:SetText("off")
            state:SetTextColor(0.4, 0.4, 0.4)
        else
            if selected then label:SetTextColor(1, 1, 1) else label:SetTextColor(0.65, 0.65, 0.65) end
            state:SetText("")
        end
    end
    b:SetScript("OnClick", function() Select(page.key) end)
    return b
end

local function Header(parent, text)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(NAV, NAV_HEAD)
    local l = UI.Label(f, text)
    l:SetPoint("TOPLEFT", 16, -4)
    l:SetTextColor(A[1], A[2], A[3], 0.8)
    return f
end

local function Build()
    local w = CreateFrame("Frame", "HUFConfigFrame", UIParent)
    w:SetSize(WIDTH, HEIGHT)
    w:SetPoint("CENTER")
    w:SetFrameStrata("DIALOG")
    -- in front of other addons' settings windows when shown or clicked (two
    -- windows on one strata otherwise mix their parts)
    w:SetToplevel(true)
    w:SetClampedToScreen(true)
    w:SetMovable(true)
    w:EnableMouse(true)
    w:RegisterForDrag("LeftButton")
    w:SetScript("OnDragStart", w.StartMoving)
    w:SetScript("OnDragStop", w.StopMovingOrSizing)
    w:Hide()
    UI.CloseOnEscape(w)
    w.tabs = {}

    UI.Fill(w, 0.03, 0.03, 0.04, 0.96)
    -- background picture (General > Settings window), under everything
    w.art = w:CreateTexture(nil, "BACKGROUND", nil, 1)
    w.art:SetPoint("TOPLEFT", 1, -1)
    w.art:SetPoint("BOTTOMRIGHT", -1, 1)
    -- a thin accent line along the top
    w.topLine = w:CreateTexture(nil, "ARTWORK")
    w.topLine:SetPoint("TOPLEFT", 1, -1)
    w.topLine:SetPoint("TOPRIGHT", -1, -1)
    w.topLine:SetHeight(1)
    UI.Border(w, 0.22, 0.22, 0.24, 1)

    local nav = CreateFrame("Frame", nil, w)
    nav:SetPoint("TOPLEFT", 1, -1)
    nav:SetPoint("BOTTOMLEFT", 1, 1)
    nav:SetWidth(NAV)
    UI.Fill(nav, 1, 1, 1, 0.025)
    local divider = w:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(1, 1, 1, 0.06)
    divider:SetPoint("TOPLEFT", nav, "TOPRIGHT")
    divider:SetPoint("BOTTOMLEFT", nav, "BOTTOMRIGHT")
    divider:SetWidth(1)

    local logo = nav:CreateTexture(nil, "ARTWORK")
    logo:SetSize(36, 36)
    logo:SetPoint("TOPLEFT", 10, -8)
    logo:SetTexture(ns.LOGO)
    local title = UI.Label(nav, "HUF", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 50, -14)
    title:SetTextColor(A[1], A[2], A[3])
    local sub = UI.Label(nav, "Hivemind Unitframes")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    sub:SetTextColor(0.6, 0.6, 0.6)

    -- page list: as many entries as fit, the mouse wheel scrolls (as MMT's window)
    local items = {}
    for si, section in ipairs({ { "general", "GENERAL" }, { "frames", "PRIMARY FRAMES" } }) do
        items[#items + 1] = { kind = "head", frame = Header(nav, section[2]), height = NAV_HEAD + (si > 1 and 6 or 0) }
        for _, key in ipairs(Ordered(section[1])) do
            local page = pages[key]
            do
                local tab = Tab(nav, page)
                tab.target = key
                w.tabs[#w.tabs + 1] = tab
                items[#items + 1] = { kind = "tab", frame = tab, height = NAV_ROW }
            end
        end
    end
    -- scroll position marker and arrows, only while the list is longer than the view
    local track = nav:CreateTexture(nil, "ARTWORK")
    track:SetColorTexture(1, 1, 1, 0.05)
    track:SetWidth(2)
    track:SetPoint("TOPRIGHT", nav, "TOPRIGHT", -2, NAV_TOP)
    track:SetHeight(NAV_VIEW)
    local thumb = nav:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(A[1], A[2], A[3], 0.6)
    thumb:SetWidth(2)
    local arrowUp = UI.ScrollArrow(nav, "UP", function() nav:GetScript("OnMouseWheel")(nav, 1) end)
    arrowUp:SetPoint("TOP", nav, "TOP", 0, NAV_TOP + 2)
    local arrowDown = UI.ScrollArrow(nav, "DOWN", function() nav:GetScript("OnMouseWheel")(nav, -1) end)
    arrowDown:SetPoint("TOP", nav, "TOP", 0, NAV_TOP - NAV_VIEW - 2)

    local offset = 0   -- entries scrolled away at the top
    local function Fit(from)       -- last entry that fits after `from`
        local used, last = 0, from
        for i = from + 1, #items do
            if used + items[i].height > NAV_VIEW then break end
            used = used + items[i].height
            last = i
        end
        return last
    end
    local function MaxOffset()
        for k = 0, #items do if Fit(k) >= #items then return k end end
        return #items
    end
    local function LayoutNav()
        local maxOffset = MaxOffset()
        offset = math.max(0, math.min(offset, maxOffset))
        local last = Fit(offset)
        local y = NAV_TOP
        for i, it in ipairs(items) do
            if i > offset and i <= last then
                it.frame:ClearAllPoints()
                -- a section header after the first sits a little lower (6 px gap above it)
                local gap = (it.kind == "head" and i > 1 and i > offset + 1) and 6 or 0
                it.frame:SetPoint("TOPLEFT", nav, "TOPLEFT", 0, y - gap)
                it.frame:Show()
                y = y - it.height
            else
                it.frame:Hide()
            end
        end
        local scrolls = maxOffset > 0
        track:SetShown(scrolls)
        thumb:SetShown(scrolls)
        arrowUp:SetShown(offset > 0)
        arrowDown:SetShown(offset < maxOffset)
        if scrolls then
            local size = math.max(16, NAV_VIEW * (#items - maxOffset) / #items)
            thumb:SetHeight(size)
            thumb:ClearAllPoints()
            thumb:SetPoint("TOPRIGHT", nav, "TOPRIGHT", -2, NAV_TOP - (NAV_VIEW - size) * offset / maxOffset)
        end
    end
    -- scroll so a page's entry is in view
    w.ShowInNav = function(key)
        for i, it in ipairs(items) do
            if it.kind == "tab" and it.frame.target == key then
                if i <= offset then
                    offset = i - 1
                    if offset > 0 and items[offset].kind == "head" then offset = offset - 1 end
                else
                    while Fit(offset) < i and offset < i - 1 do offset = offset + 1 end
                end
                break
            end
        end
        LayoutNav()
    end
    nav:EnableMouseWheel(true)
    nav:SetScript("OnMouseWheel", function(_, delta)
        offset = offset - delta
        LayoutNav()
    end)
    LayoutNav()

    -- footer: unlock, window scale, version
    nav.widgets = {}
    local unlock = UI.Button(nav, NAV - 24, "Unlock frames", function() ns.Movers.Toggle() end)
    unlock:SetPoint("BOTTOMLEFT", 12, 56)
    UI.Tooltip(unlock, "Unlock frames", "Shows a preview of every frame that is on. Drag a preview to move the frame, right-click it for its settings. Also /huf unlock.")
    table.insert(nav.widgets, { Refresh = function()
        unlock.label:SetText(ns.unlocked and "Lock frames" or "Unlock frames")
        if ns.unlocked then unlock.label:SetTextColor(A[1], A[2], A[3]) else unlock.label:SetTextColor(1, 1, 1) end
    end })

    local version = UI.Label(nav, "v" .. ns.version)
    version:SetPoint("BOTTOMLEFT", 16, 12)
    version:SetTextColor(0.4, 0.4, 0.4)
    local scaleLabel = UI.Label(nav, "")
    scaleLabel:SetPoint("BOTTOMLEFT", 16, 32)
    scaleLabel:SetTextColor(0.6, 0.6, 0.6)
    local plus = UI.TextButton(nav, "+", function() ns.SetConfigScale(ns.ConfigScale() + SCALE_STEP) end, 18)
    plus:SetPoint("BOTTOMRIGHT", -10, 28)
    local minus = UI.TextButton(nav, "-", function() ns.SetConfigScale(ns.ConfigScale() - SCALE_STEP) end, 18)
    minus:SetPoint("RIGHT", plus, "LEFT", -2, 0)
    for _, b in ipairs({ plus, minus }) do
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        local click = b:GetScript("OnClick")
        b:SetScript("OnClick", function(self, button)
            if button == "RightButton" then ns.SetConfigScale(1) else click(self, button) end
        end)
        b:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Window scale")
            GameTooltip:AddLine("Size of this settings window. Right-click to reset to 100%. Also /huf scale <percent>.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        b:HookScript("OnLeave", function() GameTooltip:Hide() end)
    end
    table.insert(nav.widgets, { Refresh = function()
        scaleLabel:SetText(("Scale %d%%"):format(math.floor(ns.ConfigScale() * 100 + 0.5)))
    end })
    w.navWidgets = nav.widgets
    w:SetScale(ns.ConfigScale())

    w.pageTitle = UI.Label(w, "", "GameFontNormalLarge")
    w.pageTitle:SetPoint("TOPLEFT", NAV + 16, -14)
    local close = UI.TextButton(w, "x", function() w:Hide() end, 20)
    close:SetPoint("TOPRIGHT", -8, -8)
    if ns.BuildConfigSearch then ns.BuildConfigSearch(w) end

    function w.ApplyLook()
        ns.Frame.SetBackground(w.art, ns.db.global.configBg, { r = 1, g = 1, b = 1 }, 0.55)
        w.topLine:SetColorTexture(A[1], A[2], A[3], 0.8)
    end
    w:SetScript("OnShow", function()
        w:Raise()
        w.ApplyLook()
        Select(current or "general")
    end)
    w:SetScript("OnHide", function() w:SetFrameStrata("DIALOG") end)
    return w
end

---------------------------------------------------------------------------
-- Window scale (account-wide)
---------------------------------------------------------------------------
function ns.ConfigScale()
    return (HUFDB and tonumber(HUFDB.configScale)) or 1
end

function ns.SetConfigScale(v)
    v = math.floor(math.max(SCALE_MIN, math.min(SCALE_MAX, v)) * 20 + 0.5) / 20
    HUFDB.configScale = v
    if window then
        window:SetScale(v)
        RefreshNav()
    end
    return v
end

-- key: page key ("general", "player", "raid", ...); open: never close
-- the settings search: open a page (the window open)
function ns.ConfigSelect(key)
    if window and window:IsShown() then Select(key) end
end

-- not in combat: settings changes can touch secure frames (and a reload is
-- refused), so the window stays closed while fighting and opens after
local reopen   -- page to open when combat ends (false: none)
-- unlock mode puts the settings window aside and brings it back after
function ns.ConfigShown() return window and window:IsShown() or false end
function ns.HideConfig() if window then window:Hide() end end

-- a page opened on one of its tabs (a page that offers page.OpenTab); the
-- Utility Frames tabs answer to their old page keys
function ns.OpenConfigTab(key, tab)
    if UTIL_OF[key] then
        ns.ToggleConfig("utility", true)
        local p = pages.utility
        if p and p.frame and p.frame.OpenTab then pcall(p.frame.OpenTab, key, tab) end
        return
    end
    ns.ToggleConfig(key, true)
    local p = pages[key]
    if tab and p and p.frame and p.frame.OpenTab then pcall(p.frame.OpenTab, tab) end
end

function ns.ToggleConfig(key, open)
    if key and UTIL_OF[key] then
        if InCombatLockdown() then return ns.ToggleConfig("utility", open) end
        ns.OpenConfigTab(key)
        return
    end
    if InCombatLockdown() then
        if not (window and window:IsShown()) then
            reopen = key or current or "general"
            ns.Print("The settings open when the fight is over.")
        end
        return
    end
    window = window or Build()
    if key and pages[key] then
        current = key
        if window:IsShown() then Select(key) return end
    end
    if open then window:Show() else window:SetShown(not window:IsShown()) end
end

---------------------------------------------------------------------------
-- Game options entry (Esc > Options > AddOns > HUF)
---------------------------------------------------------------------------
ns.OnLogin(function()
    if not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
    local panel = CreateFrame("Frame")
    local logo = panel:CreateTexture(nil, "ARTWORK")
    logo:SetSize(48, 48)
    logo:SetPoint("TOPLEFT", 12, -10)
    logo:SetTexture(ns.LOGO)
    local t = UI.Label(panel, "HUF - Hivemind Unitframes", "GameFontNormalLarge")
    t:SetPoint("TOPLEFT", 68, -22)
    local open = UI.Button(panel, 160, "Open settings", function()
        window = window or Build()
        window:SetFrameStrata("FULLSCREEN_DIALOG")
        window:Show()
    end)
    open:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -12)
    local category = Settings.RegisterCanvasLayoutCategory(panel, "HUF")
    Settings.RegisterAddOnCategory(category)
end)

---------------------------------------------------------------------------
-- Slash command
---------------------------------------------------------------------------
-- combat starts: the settings and their dialogs close (back after the fight)
ns.On("PLAYER_REGEN_DISABLED", function()
    if window and window:IsShown() then
        reopen = current or "general"
        window:Hide()
        ns.Print("Settings closed for the fight; they open again when it's over.")
    end
    for _, name in ipairs({ "HUFEllesmereImportFrame", "HUFConfirmFrame" }) do
        local f = _G[name]
        if f and f:IsShown() then f:Hide() end
    end
end)
ns.On("PLAYER_REGEN_ENABLED", function()
    if reopen then
        local key = reopen
        reopen = false
        ns.ToggleConfig(key, true)
    end
end)

-- /rl = /reload, only while no other addon has it (EllesmereUI makes the same one, with
-- the same check). A slash command runs inside the Enter key press, so the reload is allowed.
if not SlashCmdList["RL"] then
    SlashCmdList["RL"] = function() ReloadUI() end
    SLASH_RL1 = "/rl"
end

SLASH_HUF1 = "/huf"
SlashCmdList.HUF = function(msg)
    local raw = ns.Trim(msg)
    local cmd, arg = raw:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    ns.Log("config", "/huf %s", raw)
    if not ns.ready then ns.Print("HUF hasn't finished loading. If this stays, send a debug report (/huf debug report).") if cmd ~= "debug" then return end end
    if cmd == "" or cmd == "config" then
        ns.ToggleConfig()
    elseif cmd == "unlock" or cmd == "move" or cmd == "test" then
        ns.Movers.SetUnlocked(true)
    elseif cmd == "lock" then
        ns.Movers.SetUnlocked(false)
    elseif ns.UNIT_BY_KEY[cmd] then
        ns.ToggleConfig(cmd, true)
    elseif cmd == "scale" then
        local pct = tonumber((arg or ""):match("^(%d+)"))
        if pct then
            local v = ns.SetConfigScale(pct / 100)
            ns.Print("Settings window scale: %d%%.", math.floor(v * 100 + 0.5))
        else
            ns.Print("Use /huf scale <percent>, e.g. /huf scale 130 (60 to 200).")
        end
    elseif cmd == "debug" or cmd == "help" or cmd == "status" then
        ns.HandleDebugCommand(cmd == "status" and "report" or (cmd == "help" and "help" or arg))
    elseif cmd == "rec" or cmd == "record" then
        local a = (arg or ""):lower()
        if a == "now" then ns.Recorder.Now() ns.Print("Snapshot written to the log.")
        else
            local on = (a == "on") or (a ~= "off" and not ns.Recorder.DB().enabled)
            ns.Recorder.SetEnabled(on)
            ns.Print("Data recorder %s.", on and "on" or "off")
        end
        if ns.RefreshConfig then ns.RefreshConfig() end
    elseif cmd == "meter" or cmd == "dm" then
        if ns.DamageMeter then ns.DamageMeter.Toggle() end
    elseif cmd == "mmt" then
        local st = ns.Bridge.Status()
        ns.Print("MMT %s%s, privacy: %s, team: %d, HUF uses it: %s, privacy interface: v%s (HUF knows v%d).",
            st.loaded and "loaded" or "not loaded", st.version and (" (v" .. st.version .. ")") or "",
            ns.Bridge.ModeText(st.mode), st.teamSize, st.active and "yes" or "no",
            tostring(st.api or "-"), st.apiExpected)
    elseif cmd == "reset" then
        ns.ResetProfile()
        ns.Print("Profile \"%s\" reset to defaults.", ns.CurrentProfileName())
    else
        ns.Print("/huf - open settings")
        ns.Print("/huf unlock | lock - move frames (with previews)")
        ns.Print("/huf <frame> - settings of a frame (player, target)")
        ns.Print("/huf mmt - state of the link to MMT")
        ns.Print("/huf scale <percent> - size of the settings window")
        ns.Print("/huf reset - reset the active profile")
        ns.Print("/huf help - help and debug tools")
        ns.Print("/huf debug - debug log on/off (report, log, clear, chat)")
        ns.Print("/huf rec [on|off|now] - data recorder (names, values, hidden values)")
    end
end

---------------------------------------------------------------------------
-- Utility Frames: Bags, Chat, Minimap, Quest Log, De-/Buff Bar as tabs
---------------------------------------------------------------------------
ns.RegisterPage("utility", "Utility Frames", "general", function(page)
    local tabs, subs, strip = {}, {}, nil
    for _, t in ipairs(UTILITY) do if pages[t[1]] then tabs[#tabs + 1] = t end end
    local function Show(k)
        for n, f in pairs(subs) do f:SetShown(n == k) end
        strip:Select(k)
        page.tab = k
    end
    strip = UI.SubTabs(page, tabs, Show)
    strip:SetPoint("TOPLEFT", 0, 4)
    strip:SetPoint("TOPRIGHT", 0, 4)
    -- each tab is the old page, built into a frame under the strip (all at once,
    -- so the settings search finds them)
    local fullH = ns.PAGE_H
    for _, t in ipairs(tabs) do
        local f = CreateFrame("Frame", nil, page)
        f:SetPoint("TOPLEFT", 0, -UTIL_TOP)
        f:SetSize(ns.PAGE_W, fullH - UTIL_TOP)
        ns.PAGE_H = fullH - UTIL_TOP
        local ok, err = pcall(pages[t[1]].build, f)
        ns.PAGE_H = fullH
        if not ok then ns.Log("config", "utility tab %s: %s", t[1], tostring(err)) end
        pages[t[1]].frame = f
        f:Hide()
        subs[t[1]] = f
    end
    if strip.Bind then strip:Bind(subs, Show) end
    page.OnRefresh = function()
        for _, f in pairs(subs) do
            if f.OnRefresh then pcall(f.OnRefresh) end
            -- a tab that keeps its own widget list (the Minimap page does)
            if f.widgets then for _, w in ipairs(f.widgets) do pcall(w.Refresh) end end
        end
    end
    page.OpenTab = function(k, inner)
        if not subs[k] then return end
        Show(k)
        if inner and subs[k].OpenTab then pcall(subs[k].OpenTab, inner) end
    end
    if tabs[1] then Show(tabs[1][1]) end
end)

-- not built yet
local function Later(key, title, text)
    ns.RegisterPage(key, title, "frames", function(page)
        local l = UI.Label(page, text, "GameFontNormal")
        l:SetPoint("TOPLEFT", 0, -4)
        l:SetTextColor(0.6, 0.6, 0.6)
    end)
end
Later("focus", "Focus Target", "The focus target frame comes in a later version.")
