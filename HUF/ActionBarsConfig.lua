-- HUF: settings page for the action bars (General > Action Bars): ActionBars.lua and ExtraBars.lua.
-- Tabs: the action bars (one set of controls; the "Bar" list picks which bar they change),
-- XP & reputation, and the game's micro menu / bag bar / queue button.

local _, ns = ...
local UI = ns.UI
local COL_W, COL2_X, TOP = 330, 366, -36

local sel = "MainBar"

local function SubFrame(page)
    local f = CreateFrame("Frame", nil, page)
    f:SetPoint("TOPLEFT", 0, TOP - 16)
    f:SetSize(ns.PAGE_W, ns.PAGE_H + TOP - 16)
    return f
end

local function Refresh() if ns.RefreshConfig then ns.RefreshConfig() end end

---------------------------------------------------------------------------
-- Action bars
---------------------------------------------------------------------------
local function BarsTab(f)
    local AB = ns.ActionBars
    local D = function() return ns.db.actionBars end
    local B = function() return D().bars[sel] end
    local function Opt(k) return function() return B()[k] end, function(v) B()[k] = v end end
    local function Max() local info = AB.BY[sel] return info and info.count or 12 end

    local L = UI.Column(f, 0, 0, COL_W)
    L:Header("Action bars")
    L:Check("Use HUF's action bars", function() return D().enabled end, function(v)
        D().enabled = v
        if v then AB.Apply() else ns.AskReload("The game's action bars come back after a reload.") end
    end, "The game's own action buttons in HUF's bars: placed and sized by HUF, in a flat look. Key bindings, cooldowns, stances and forms work as before. Off: the game's bars, untouched.")
    local choices = {}
    for _, info in ipairs(AB.BARS) do choices[#choices + 1] = { value = info.key, text = info.label } end
    L:Cycle("Bar", choices, function() return sel end, function(v) sel = v Refresh() end, "Which bar the settings below change.")
    local ge, se = Opt("enabled")
    L:Check("Show this bar", ge, function(v)
        se(v)
        if v then AB.Apply()
        elseif AB.Taken(sel) then ns.AskReload("The game's own bar comes back after a reload.") end
    end, "Off: HUF leaves the game's bar alone (it is back after a reload if HUF had taken it). Bars 9 and 10 (EllesmereUI's extra bars, action slots 13-24 and 109-120) use bar 7's and bar 8's buttons, so each needs that bar off.")
    L:Slider("Buttons", 1, 12, 1, function() return math.min(B().buttons or 12, Max()) end, function(v) B().buttons = math.min(v, Max()) end).EnableInput()
    L:Slider("Buttons per row", 1, 12, 1, Opt("perRow")).EnableInput()
    local gu, su = Opt("rowsUp")
    L:Check("New rows above", gu, su, "The first buttons in the bottom row, the next rows above them (as EllesmereUI). Off: rows go down.")
    L:Slider("Button size", 16, 64, 1, Opt("size")).EnableInput()
    L:Slider("Spacing", 0, 20, 1, Opt("spacing")).EnableInput()
    local gm, sm = Opt("mouseover")
    L:Check("Only on mouseover", gm, function(v) sm(v) AB.Fade() end,
        "The bar shows while the mouse is over it, or while you drag a spell or item.")
    local gh, sh = Opt("hideHotkey")
    L:Check("Hide key bindings", gh, sh)
    local gn, sn = Opt("hideMacro")
    L:Check("Hide macro names", gn, sn)
    local keys = UI.Label(f, "")
    keys:SetWidth(COL_W)
    keys:SetJustifyH("LEFT")
    keys:SetWordWrap(true)
    L:Add(keys, 30)
    keys.Refresh = function()
        local info = AB.BY[sel]
        if not (info and info.bind) then keys:SetText("") return end
        local k, list = B().keys, {}
        for i = 1, 12 do if type(k) == "table" and k[i] and k[i] ~= "" then list[#list + 1] = i .. "=" .. k[i] end end
        local lender = AB.BY[info.lender]
        keys:SetText(("Keys: %s%s"):format(#list > 0 and table.concat(list, ", ") or "none (taken from EllesmereUI by the import)",
            AB.Allowed(sel) and "" or ("\n|cffff8040Needs " .. lender.label .. " off.|r")))
    end
    -- refreshed with the page's widgets (the bar picked changes it)
    local pg = f
    while pg and type(rawget(pg, "widgets")) ~= "table" do pg = pg:GetParent() end
    if pg then table.insert(pg.widgets, keys) end
    L:Note("Move the bars in unlock mode (/huf unlock); right-click a bar's box for its settings. Changes wait until combat ends.")

    local R = UI.Column(f, COL2_X, 0, COL_W)
    R:Header("Look (every bar)")
    R:Slider("Border", 0, 3, 1, function() return D().border end, function(v) D().border = v end)
    R:Check("Border in the accent colour", function() return D().borderAccent end, function(v) D().borderAccent = v end)
    R:Color("Border colour", function() return D().borderColor end, function(c) D().borderColor = c end)
    R:Slider("Icon zoom", 0, 0.3, 0.005, function() return D().iconZoom or 0.055 end, function(v) D().iconZoom = v end, "%.3f")
    R:Slider("Slot background", 0, 1, 0.05, function() return D().slotAlpha end, function(v) D().slotAlpha = v end, "%.2f")
    R:Check("Fill the gaps between buttons", function() return D().fillGaps ~= false end, function(v) D().fillGaps = v end,
        "The borders reach over the spacing, so the lines between the buttons are solid (as EllesmereUI's bars). Off: a thin border on each button and see-through gaps.")
    R:Slider("Key text size", 6, 24, 1, function() return D().keySize end, function(v) D().keySize = v end)
    R:Color("Key text colour", function() return D().keyColor end, function(c) D().keyColor = c end)
    R:Slider("Stack count size", 6, 24, 1, function() return D().countSize end, function(v) D().countSize = v end)
    -- EllesmereUI: only when there is something to import - EllesmereUI itself, or the copy HUF
    -- kept of its action bars while it was on
    local src, from = AB.EllesmereSource()
    if not src then return end
    R:Header("EllesmereUI")
    local msg = UI.Label(f, "")
    msg:SetWidth(COL_W)
    msg:SetJustifyH("LEFT")
    msg:SetWordWrap(true)
    local IsLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
    local live = IsLoaded and IsLoaded("EllesmereUI")
    R:Button(live and "Import EllesmereUI's action bars" or "Import EllesmereUI's action bars (saved copy)", function()
        local ok, text = AB.ImportEllesmere()
        msg:SetText(ok and ("|cff60ff60" .. text .. "|r") or ("|cffff6060" .. text .. "|r"))
        if ok then Refresh() end
    end)
    R:Add(msg, 44)
    local copy = HUFDB and HUFDB.ellesmereActionBars
    R:Note("Every bar (1-10, stance, pet), the XP and reputation bars, micro menu, bag bar and queue button: buttons, rows, size, spacing, place, mouseover, texts, bar 9 / 10 keys. Works while EllesmereUI is on, and from the copy HUF keeps once it is off."
        .. ((copy and copy.time) and ("\nCopy kept: " .. date("%Y-%m-%d %H:%M", copy.time) .. ".") or ""))
end

---------------------------------------------------------------------------
-- XP & reputation
---------------------------------------------------------------------------
local TEXT = { { value = "ALWAYS", text = "Always" }, { value = "MOUSEOVER", text = "On mouseover" }, { value = "NEVER", text = "Never" } }

local function DataColumn(col, key, title)
    local X = function() return ns.db.actionBars.extra[key] end
    local function Opt(k) return function() return X()[k] end, function(v) X()[k] = v end end
    col:Header(title)
    local ge, se = Opt("enabled")
    col:Check("Use HUF's " .. title:lower(), ge, function(v)
        se(v)
        if ns.ExtraBars then ns.ExtraBars.Apply() end
        if not v then ns.AskReload("The game's XP / reputation bars come back after a reload.") end
    end, key == "xp" and "XP with the rested part in a second colour; hidden at the highest level." or "The reputation you watch (Character > Reputation: \"Show as experience bar\"), in its standing's colour.")
    col:Slider("Width", 50, 1600, 1, Opt("width")).EnableInput()
    col:Slider("Height", 2, 40, 1, Opt("height")).EnableInput()
    col:Cycle("Numbers", TEXT, Opt("text"))
    col:Slider("Text size", 6, 24, 1, Opt("textSize"))
    local gm, sm = Opt("mouseover")
    col:Check("Only on mouseover", gm, sm)
    if key == "xp" then
        local gx, sx = Opt("hideMaxLevel")
        col:Check("Hide at the highest level", gx, sx)
    end
end

local function DataTab(f)
    local L = UI.Column(f, 0, 0, COL_W)
    DataColumn(L, "xp", "XP bar")
    local R = UI.Column(f, COL2_X, 0, COL_W)
    DataColumn(R, "rep", "Reputation bar")
    R:Space(8)
    R:Check("Hide the game's XP / reputation bars", function() return ns.db.actionBars.extra.hideBlizzardStatus ~= false end,
        function(v) ns.db.actionBars.extra.hideBlizzardStatus = v if not v then ns.AskReload("The game's bars come back after a reload.") end end,
        "While HUF's XP or reputation bar is on.")
    L:Note("On with HUF's action bars (Action bars tab). Move them in unlock mode (/huf unlock). Border colour: the action bars'.")
end

---------------------------------------------------------------------------
-- Micro menu, bag bar, queue button
---------------------------------------------------------------------------
local function HeldColumn(col, key, title, tip)
    local X = function() return ns.db.actionBars.extra[key] end
    local function Opt(k) return function() return X()[k] end, function(v) X()[k] = v end end
    col:Header(title)
    local avail = ns.ExtraBars and ns.ExtraBars.Available(key)
    local ge, se = Opt("enabled")
    col:Check("Move it with HUF", ge, function(v)
        se(v)
        if ns.ExtraBars then ns.ExtraBars.Apply() end
        if not v then ns.AskReload("The game places it again after a reload.") end
    end, tip .. (avail and "" or " (not found on this client)"))
    col:Slider("Scale", 0.5, 2, 0.05, function() return X().scale end, function(v) X().scale = v end, "%.2f")
    local gm, sm = Opt("mouseover")
    col:Check("Only on mouseover", gm, sm)
    local gh, sh = Opt("hidden")
    col:Check("Hide it", gh, sh)
end

local function MenusTab(f)
    local L = UI.Column(f, 0, 0, COL_W)
    HeldColumn(L, "micro", "Micro menu", "The game's menu buttons (character, spellbook, talents, ...): moved in unlock mode, scaled, faded or hidden.")
    L:Space(8)
    HeldColumn(L, "queue", "Queue button", "The looking-for-group eye.")
    local R = UI.Column(f, COL2_X, 0, COL_W)
    HeldColumn(R, "bags", "Bag bar", "The game's bag buttons.")
    R:Note("On with HUF's action bars (Action bars tab). The first time, each one stays where the game had it; move it in unlock mode (/huf unlock).")
end

ns.RegisterPage("actionbars", "Action Bars", "general", function(page)
    local tabs = { { "bars", "Action bars" }, { "data", "XP & reputation" }, { "menus", "Menu, bags & queue" } }
    local subs, strip = {}, nil
    local function Show(k)
        for n, sf in pairs(subs) do sf:SetShown(n == k) end
        strip:Select(k)
    end
    strip = UI.SubTabs(page, tabs, Show)
    strip:SetPoint("TOPLEFT", 0, -22)
    strip:SetPoint("TOPRIGHT", 0, -22)
    subs.bars = SubFrame(page); BarsTab(subs.bars)
    subs.data = SubFrame(page); DataTab(subs.data)
    subs.menus = SubFrame(page); MenusTab(subs.menus)
    if strip.Bind then strip:Bind(subs, Show) end
    Show("bars")
    -- ns.OpenConfigTab("actionbars", <bar key> | "data" | "menus")
    page.OpenTab = function(key)
        if subs[key] then Show(key) return end
        if ns.ActionBars.BY[key] then sel = key end
        Show("bars")
        Refresh()
    end
end, function() return ns.db.actionBars.enabled end)
