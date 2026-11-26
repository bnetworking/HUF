-- HUF: settings page for the damage meter (GENERAL > Damage Meter).

local _, ns = ...
local UI = ns.UI
local COL_W, COL2_X = 330, 366

local function D() return ns.db.damageMeter end
-- the window whose settings the page shows (the dropdown at the top)
local sel = 1
local function Win()
    local list = D().windows or {}
    if sel > #list or sel > (D().windowCount or 1) then sel = 1 end
    return list[sel]
end
local function PW(k) return ns.DamageMeter and ns.DamageMeter.PER_WINDOW and ns.DamageMeter.PER_WINDOW[k] end
-- per-window keys: the selected window's own value, else the shared one; a
-- change goes to that window only. Meter-wide keys: the shared settings.
local function Opt(k)
    return function()
        local w = PW(k) and Win()
        if w and w[k] ~= nil then return w[k] end
        return D()[k]
    end, function(v)
        local w = PW(k) and Win()
        if w then w[k] = v else D()[k] = v end
    end
end

local TYPE_NAMES = { DamageDone = "Damage done", HealingDone = "Healing done", DamageTaken = "Damage taken",
    AvoidableDamageTaken = "Avoidable damage", EnemyDamageTaken = "Enemy damage taken", Interrupts = "Interrupts",
    Dispels = "Dispels", Deaths = "Deaths", Threat = "Threat" }
local function WindowChoices()
    if ns.DamageMeter and ns.DamageMeter.EnsureWindows then ns.DamageMeter.EnsureWindows() end
    local l = {}
    for i = 1, (D().windowCount or 1) do
        local w = D().windows and D().windows[i]
        local t = w and (TYPE_NAMES[w.meterType] or w.meterType) or ""
        l[#l + 1] = { value = i, text = ("Window %d%s"):format(i, t ~= "" and (" (" .. t .. ")") or "") }
    end
    return l
end

-- every window takes the selected window's size and look
local function ApplyToAll()
    local src = Win()
    if not src then return end
    local n = 0
    for i = 1, (D().windowCount or 1) do
        local w = D().windows[i]
        if w and i ~= sel then
            for k in pairs(ns.DamageMeter.PER_WINDOW) do
                local v = src[k]
                if v == nil then v = D()[k] end
                w[k] = type(v) == "table" and ns.CopyTable(v) or v
            end
            n = n + 1
        end
    end
    ns.Log("config", "damage meter: window %d's settings to %d other windows", sel, n)
    ns.Refresh()
end

local function Fonts()
    local l = { { value = "GLOBAL", text = "HUF Global Font" } }
    for _, f in ipairs(ns.fonts) do l[#l + 1] = { value = f.name, text = f.name } end
    return l
end
local function Textures()
    local l = {}
    for _, t in ipairs(ns.textures) do l[#l + 1] = { value = t.name, text = t.name } end
    return l
end

local TILE_W, GAP, TOP = 344, 10, -58

-- two widgets side by side in one row of a column
local function Pair(col, parent, a, b, h)
    h = h or 38
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(col.width, h)
    local half = (col.width - 12) / 2
    for i, w in ipairs({ a, b }) do
        if w then
            w:SetParent(row)
            w:ClearAllPoints()
            w:SetPoint("TOPLEFT", row, "TOPLEFT", i == 1 and 0 or (half + 12), 0)
            w:SetWidth(half)
        end
    end
    col:Add(row, h)
    return row
end

-- the selected window shows threat?
local function IsThreat()
    local w = Win()
    return w and w.meterType == "Threat" or false
end

local function Tiles(page)
    local H = ns.PAGE_H + TOP
    local half = (TILE_W - 16 - 12) / 2
    local gated = {}

    -- General ---------------------------------------------------------------
    local G_H = 262
    local gt, G = ns.ConfigTile(page, 0, TOP, TILE_W, G_H, "General", "Interface\\Icons\\INV_Misc_Gear_01")
    local gl, sl = Opt("locked")
    G:Check("Lock Frame", gl, sl, "No dragging by the title bar (unlock mode still moves it).")
    local gShow, sShow = Opt("show")
    G:Cycle("Show", {
        { value = "ALWAYS", text = "Always" },
        { value = "GROUP", text = "In a group" },
        { value = "INSTANCE", text = "In instances" },
        { value = "COMBAT", text = "In combat" },
    }, gShow, sShow, "When this window shows. While these settings are open or in unlock mode every window shows, so you can move and change them.")
    local gp, sp = Opt("threatPets")
    gated[#gated + 1] = G:Check("Threat: Show Pets", gp, sp, "Pets in the threat list too. Only for a window that shows threat.")
    local gc, sc = Opt("threatColors")
    gated[#gated + 1] = G:Check("Threat: Bars in Threat Colours", gc, sc, "Grey, yellow, orange and red (has aggro) like the game's threat warning. Only for a window that shows threat.")
    local gf, sf = Opt("fadeOOC")
    local gfa, sfa = Opt("fadeAlpha")
    G:Check("Reduce Opacity out of combat", gf, sf, "This window at the opacity below while out of combat; fully visible under the mouse.")
    local fadeSlider = G:Slider("Opacity out of combat", 0, 100, 5, function() return math.floor((gfa() or 0) * 100 + 0.5) end,
        function(v) sfa(v / 100) end, "%d%%")
    fadeSlider.EnableInput()
    gated[#gated + 1] = { w = fadeSlider, on = function() return gf() and true or false end }
    local gk, sk = Opt("breakdownInline")
    G:Check("Data-Breakdown inside the window", gk, sk, "Clicking a name shows its spells in the same window; right-clicking the names shows the list of meters to pick one. < or a right-click goes back to the names. Off: the breakdown in a panel beside the window.")
    local gn, sn = Opt("nameHover")
    G:Check("Hovering name: Show the top abilities", gn, sn, "A box beside the window with the player's spells while the mouse is on the name. A click still opens the whole breakdown.")

    -- Window Size -----------------------------------------------------------
    local W_Y = TOP - G_H - GAP
    local wt, W = ns.ConfigTile(page, 0, W_Y, TILE_W, H - G_H - GAP, "Window Size", "Interface\\Icons\\INV_Misc_Spyglass_03")
    local gw, sw = Opt("width")
    local gr, sr = Opt("rows")
    local grh, srh = Opt("rowHeight")
    local gg, sg = Opt("rowGap")
    local gth = Opt("titleHeight")
    -- the frame's height comes from the rows: changing it changes the rows
    local function FrameH() return (gth() or 20) + gr() * (grh() + gg()) + 2 end
    Pair(W, wt,
        UI.Slider(wt, half, "Frame Width", 120, 500, 1, gw, sw).EnableInput(),
        UI.Slider(wt, half, "Frame Height", 40, 800, 1, FrameH, function(v)
            sr(math.max(1, math.min(40, math.floor((v - (gth() or 20) - 2) / (grh() + gg()) + 0.5))))
        end).EnableInput())
    Pair(W, wt,
        UI.Slider(wt, half, "Rows", 1, 40, 1, gr, sr).EnableInput(),
        UI.Slider(wt, half, "Row Height", 10, 40, 1, grh, srh).EnableInput())
    local gsc, ssc = Opt("scale")
    Pair(W, wt,
        UI.Slider(wt, half, "Row Padding", 0, 6, 1, gg, sg).EnableInput(),
        UI.Slider(wt, half, "Scale", 50, 200, 5, function() return math.floor((gsc() or 1) * 100 + 0.5) end,
            function(v) ssc(v / 100) end, "%d%%").EnableInput())
    W:Note("Frame Height follows the rows: a new height sets the rows that fit.")

    -- Bars & Text -----------------------------------------------------------
    local bt, B = ns.ConfigTile(page, TILE_W + GAP, TOP, TILE_W, H, "Bars & Text", "Interface\\Icons\\INV_Misc_Note_01")
    local function Dd(text, choices, k, tip)
        local g, st = Opt(k)
        return UI.Dropdown(bt, half, text, choices, g, st, tip)
    end
    local function Sl(text, a, b, step, k, fmt)
        local g, st = Opt(k)
        return UI.Slider(bt, half, text, a, b, step, g, st, fmt)
    end
    local function Ck(text, k, tip)
        local g, st = Opt(k)
        return UI.Check(bt, half, text, g, st, tip)
    end
    local function Cl(text, k)
        local g, st = Opt(k)
        return UI.Color(bt, half, text, g, st)
    end
    Pair(B, bt, Dd("Texture", Textures, "texture"), Dd("Colour", {
        { value = "CLASS", text = "Class" }, { value = "ACCENT", text = "Accent" }, { value = "STATIC", text = "Static" },
    }, "colorMode"), UI.ROW + 4)
    Pair(B, bt, Cl("Static colour", "color"), Dd("Icons", {
        { value = "NONE", text = "None" }, { value = "CLASS", text = "Class" }, { value = "SPEC", text = "Spec" },
    }, "icons", "An icon before each bar: the class, or the spec (the talent tree with the most points; HUF inspects your group for it out of combat, the class icon until it knows)."), UI.ROW + 4)
    Pair(B, bt, Sl("Background opacity", 0, 1, 0.05, "bgAlpha", "%.2f"), Sl("Empty bar opacity", 0, 1, 0.05, "barBgAlpha", "%.2f"))
    Pair(B, bt, Sl("Bar border", 0, 3, 1, "rowBorder"), Sl("Text size", 6, 20, 1, "fontSize"))
    local gfo, sfo = Opt("font")
    B:Cycle("Font", Fonts, gfo, sfo)
    local gou, sou = Opt("outline")
    B:Cycle("Outline", {
        { value = "GLOBAL", text = "HUF Global Outline" }, { value = "NONE", text = "None" },
        { value = "OUTLINE", text = "Thin" }, { value = "THICKOUTLINE", text = "Thick" },
    }, gou, sou)
    local gnu, snu = Opt("numbers")
    B:Cycle("Numbers", {
        { value = "BOTH", text = "Total (per second)" }, { value = "BAR", text = "Total | per second" },
        { value = "TOTAL", text = "Total" }, { value = "PERSECOND", text = "Per second" },
    }, gnu, snu)
    local th = UI.Label(bt, "Title bar")
    th:SetTextColor(UI.ACCENT[1], UI.ACCENT[2], UI.ACCENT[3])
    B:Add(th, 20)
    Pair(B, bt, Sl("Title bar height", 12, 30, 1, "titleHeight"), Sl("Title text size", 6, 20, 1, "titleSize"))
    Pair(B, bt, Cl("Title colour", "titleColor"), Sl("Icon size", 10, 32, 1, "titleIconSize"))
    Pair(B, bt, Ck("Rank before the name", "showRank"), Ck("Title accent line", "titleLine", "An accent-coloured line under the title bar."), UI.ROW + 2)
    Pair(B, bt, Ck("Fight in the accent colour", "titleAccent"),
        Ck("Type and fight as icons", "titleIcons", "The meter type's name at the left, icon buttons for the meter type and the fight at the right (their names in the tooltips)."), UI.ROW + 2)
    Pair(B, bt, Ck("Muted icons", "titleIconsMuted", "Grey and dimmed to fit the dark title bar; the accent colour under the mouse. Off: the icons in their own colours."), nil, UI.ROW + 2)

    table.insert(page.widgets, { Refresh = function()
        local threat = D().enabled and IsThreat()
        for _, w in ipairs(gated) do
            if type(w) == "table" and w.on then UI.SetActive(w.w, D().enabled and w.on())
            else UI.SetActive(w, threat) end
        end
    end })
end

ns.RegisterPage("damagemeter", "Damage meter", "general", function(page)
    -- open page: hidden threat windows show (DM.Editing), closed: hidden again
    page:HookScript("OnShow", function() if ns.DamageMeter then ns.DamageMeter.Apply() end end)
    page:HookScript("OnHide", function() if ns.DamageMeter then C_Timer.After(0, ns.DamageMeter.Apply) end end)
    local on = UI.Check(page, 260, "Use HUF's damage meter", function() return D().enabled end,
        function(v) D().enabled = v end, "The game's own meter data in HUF windows, with privacy names; the game's own meter window is switched off meanwhile. Also /huf meter.")
    on:SetPoint("TOPLEFT", 0, 4)
    -- which window the settings below change
    local pick = UI.Dropdown(page, 330, "Settings of", WindowChoices, function() return sel end, function(v)
        sel = v
        ns.RefreshConfig()
    end, "Each damage meter window has its own settings. New windows: + in a window's title bar; x closes one.")
    pick:SetPoint("TOPLEFT", 0, -22)
    table.insert(page.widgets, pick)
    local all = UI.Button(page, 220, "Apply settings to all frames", function()
        UI.Confirm(("Give every damage meter window the settings of window %d?"):format(sel), "Apply", ApplyToAll, "Cancel")
    end)
    all:SetPoint("LEFT", pick, "RIGHT", 16, 0)
    UI.Tooltip(all, "Apply settings to all frames", "Copies the chosen window's settings (General, Window Size, Bars & Text) to every other window. Their meter type, fight and place stay their own.")
    table.insert(page.widgets, { Refresh = function() UI.SetActive(all, (D().windowCount or 1) > 1) end })
    Tiles(page)
end, function() return ns.db.damageMeter.enabled end)
