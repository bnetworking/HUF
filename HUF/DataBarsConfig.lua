-- HUF: settings for the data bars - their own page in the General list (General > Data
-- Bars): the free bars anywhere on the screen, the blocks on them, and the minimap data bar.

local _, ns = ...
local UI = ns.UI
local DB = ns.DataBars
local BL = ns.DataBlocks
local COL_W, COL2_X = 330, 366

local function D() return ns.db.dataBars.minimap end
local function Opt(k) return function() return D()[k] end, function(v) D()[k] = v end end

local TOP = -104     -- under the page's description, switch and tab strip
local function SubFrame(page)
    local f = CreateFrame("Frame", nil, page)
    f:SetPoint("TOPLEFT", 0, TOP - 16)
    f:SetSize(ns.PAGE_W, ns.PAGE_H + TOP - 16)
    return f
end

---------------------------------------------------------------------------
-- The selected bar and block
---------------------------------------------------------------------------
local selBar, selBlock = 1, 1
local function List() return ns.db.dataBars.bars end
local function Bar()
    local l = List()
    if not l[selBar] then selBar = math.max(1, #l) end
    return l[selBar]
end
local function Block()
    local b = Bar()
    if not b then return nil end
    if not b.blocks[selBlock] then selBlock = math.max(1, #b.blocks) end
    return b.blocks[selBlock]
end
-- bar / block / block setting fields; the defaults while there is none
local function BOpt(k)
    return function() local b = Bar() if b then return b[k] end return DB.BAR_DEFAULTS[k] end,
           function(v) local b = Bar() if b then b[k] = v end end
end
local NEW = BL.New("fps")
local function KOpt(k)
    return function() local c = Block() if c then return c[k] end return NEW[k] end,
           function(v) local c = Block() if c then c[k] = v end end
end
local function SOpt(k)
    return function() local c = Block() return c and c.settings[k] end,
           function(v) local c = Block() if c then c.settings[k] = v end end
end
local function Changed()
    ns.Refresh()
    if ns.RefreshConfig then ns.RefreshConfig() end
end

local function BarChoices()
    local l = {}
    for i, b in ipairs(List()) do l[#l + 1] = { value = i, text = b.name or ("Bar " .. i) } end
    return l
end
local function BlockChoices()
    local l = {}
    local b = Bar()
    for i, c in ipairs(b and b.blocks or {}) do
        local def = BL.TYPES[c.type]
        l[#l + 1] = { value = i, text = i .. ". " .. (def and def.title or c.type) }
    end
    return l
end
local function PickBar(col)
    col:Cycle("Bar", BarChoices, function() return Bar() and selBar end,
        function(v) selBar, selBlock = v, 1 if ns.RefreshConfig then ns.RefreshConfig() end end)
end

---------------------------------------------------------------------------
-- Minimap > Data bar: the minimap data bar
---------------------------------------------------------------------------
function ns.DataBarsTab(f)
    local on = UI.Check(f, 300, "Minimap data bar", function() return D().enabled end,
        function(v) D().enabled = v end, "A strip under the minimap with friends and guild members online.")
    on:SetPoint("TOPLEFT", 0, 0)
    local L = UI.Column(f, 0, -28, COL_W)
    L:Header("Minimap data bar")
    L:Cycle("Place", {
        { value = "BELOW", text = "Under the map" },
        { value = "ABOVE", text = "Over the map" },
    }, Opt("position"))
    L:Slider("Height", 14, 40, 1, Opt("height"))
    L:Slider("Space to the map", 0, 10, 1, Opt("gap"))
    L:Color("Background colour", Opt("bgColor"))
    L:Slider("Background opacity", 0, 1, 0.05, function() return D().bgAlpha end, function(v) D().bgAlpha = v end, "%.2f")
    L:Slider("Line around it", 0, 2, 1, Opt("borderSize"))

    local R = UI.Column(f, COL2_X, -28, COL_W)
    R:Header("What it shows")
    local gf, sf = Opt("friends")
    R:Check("Friends online", gf, sf, "Click: the friends list.")
    local gg, sg = Opt("guild")
    R:Check("Guild members online", gg, sg, "Click: the guild window. Not shown outside a guild.")
    R:Cycle("Layout", {
        { value = "SIDE", text = "Icon, then the count" },
        { value = "STACK", text = "Count above a small icon" },
    }, Opt("layout"))
    R:Cycle("Icon colour", {
        { value = "MONO", text = "Flat grey" },
        { value = "GAME", text = "The game's colours" },
        { value = "CLASS", text = "Class colour" },
        { value = "ACCENT", text = "Accent colour" },
        { value = "CUSTOM", text = "Own colour" },
    }, Opt("iconColor"))
    R:Color("Own icon colour", Opt("iconCustom"))
    R:Slider("Text size", 8, 20, 1, Opt("fontSize"))
    R:Slider("Space between them", 0, 40, 1, Opt("spacing"))
    R:Note("The tracking button sits on the bar's left end when Minimap > Icons > Tracking is at \"Below, left\".")
    R:Space(6)
    R:Note("The other data bars (anywhere on the screen) and their blocks: the Bars and Blocks tabs.")
    -- everything here waits for the data bar switch
    -- (and for the Data Bars switch: the page gate greys the tab, this one must not light it up again)
    UI.Gate(f, on, function() return ns.db.dataBars.enabled and D().enabled end)
end

---------------------------------------------------------------------------
-- Tab: the bars
---------------------------------------------------------------------------
local function BarsPage(f)
    local L = UI.Column(f, 0, 0, COL_W)
    PickBar(L)
    L:Button("Arrange blocks (drag them on the bars)", function()
        DB.SetArranging(true)
        if ns.HideConfig then ns.HideConfig() end
    end)
    L:Button("New bar", function()
        DB.NewBar()
        selBar, selBlock = #List(), 1
        Changed()
    end)
    L:Button("Delete this bar", function()
        local b = Bar()
        if not b then return end
        UI.Confirm("Delete the bar \"" .. (b.name or "Bar") .. "\"?", "Delete", function()
            table.remove(List(), selBar)
            selBar, selBlock = math.max(1, selBar - 1), 1
            -- the last bar gone: the feature goes off (the minimap bar keeps it on)
            if #List() == 0 and not D().enabled then DB.SetEnabled(false) end
            Changed()
        end, "Keep it")
    end)
    L:Header("This bar")
    L:Check("On", BOpt("enabled"))
    L:Cycle("Shows", {
        { value = "ALWAYS", text = "Always" },
        { value = "COMBAT", text = "In combat" },
        { value = "NOCOMBAT", text = "Out of combat" },
        { value = "HOVER", text = "On mouseover" },
        { value = "NEVER", text = "Never" },
    }, BOpt("visibility"))
    L:Slider("Width", 40, 2400, 1, BOpt("width"))
    L:Slider("Height", 10, 60, 1, BOpt("height"))
    L:Slider("Text size", 6, 24, 1, BOpt("fontSize"))
    L:Note("Move it in unlock mode (drag the bar).")

    local R = UI.Column(f, COL2_X, 0, COL_W)
    R:Header("Look")
    R:Cycle("Look", {
        { value = "FLAT", text = "Solid" },
        { value = "SOFT", text = "Soft (see-through, faded ends)" },
        { value = "EUI", text = "EllesmereUI's background (when installed)" },
    }, BOpt("look"))
    R:Color("Background colour (solid)", BOpt("bgColor"))
    local ga, sa = BOpt("bgAlpha")
    R:Slider("Background opacity (solid)", 0, 1, 0.05, ga, sa, "%.2f")
    local gs, ss = BOpt("softAlpha")
    R:Slider("Darkness (soft / EllesmereUI)", 0, 1, 0.05, gs, ss, "%.2f")
    R:Slider("Line around it", 0, 2, 1, BOpt("borderSize"))
    R:Header("Blocks")
    R:Cycle("Spacing", {
        { value = "AUTO", text = "By their content" },
        { value = "EVEN", text = "Even" },
    }, BOpt("sizing"))
    R:Note("By their content: each block is as wide as its text plus the space before and after it; one block (the last, or the one set to fill) takes the rest of the bar.")
end

---------------------------------------------------------------------------
-- Tab: the blocks on a bar
---------------------------------------------------------------------------
local TEXT_COLOURS = {
    { value = "WHITE", text = "White" },
    { value = "DYNAMIC", text = "By its value" },
    { value = "CLASS", text = "Class colour" },
    { value = "ACCENT", text = "Accent colour" },
    { value = "CUSTOM", text = "Own colour" },
}
local ICON_COLOURS = {
    { value = "MONO", text = "Flat grey" },
    { value = "GAME", text = "The game's colours" },
    { value = "CLASS", text = "Class colour" },
    { value = "ACCENT", text = "Accent colour" },
    { value = "CUSTOM", text = "Own colour" },
}

-- the options of one block type
local TYPE_OPTIONS = {
    ms = function(C)
        C:Cycle("Latency", {
            { value = "HOME", text = "Home" },
            { value = "WORLD", text = "World" },
            { value = "HIGHER", text = "The higher one" },
        }, SOpt("latency"))
    end,
    clock = function(C)
        C:Check("24-hour", SOpt("twentyFour"))
        C:Check("Local time", SOpt("localTime"))
        C:Note("Off: the realm's time.")
    end,
    gold = function(C)
        C:Check("Silver and copper", SOpt("showSmall"))
        C:Check("Coin icons", SOpt("coinIcons"))
        local g, s = SOpt("coinColor")
        C:Check("Coloured g / s / c", g, s, "Without coin icons: the letters in the coins' colours.")
        local ga, sa = SOpt("abbreviate")
        C:Check("Short (12.3k)", ga, sa)
    end,
    audio = function(C)
        local l = {}
        for _, k in ipairs(BL.CHANNEL_ORDER) do l[#l + 1] = { value = k, text = BL.CHANNELS[k].name } end
        C:Cycle("Volume of", l, SOpt("channel"))
        C:Cycle("Show as", { { value = "TEXT", text = "Text (63%)" }, { value = "BAR", text = "A bar" } }, SOpt("style"))
    end,
    bags = function(C)
        C:Cycle("Show", { { value = "FREE", text = "Free slots (12)" }, { value = "USED", text = "Used / all (68/80)" },
            { value = "BOTH", text = "Free / all (12 / 80)" } }, SOpt("show"))
    end,
    location = function(C)
        local g, s = SOpt("subzone")
        C:Check("Subzone", g, s, "The part of the zone you are in (Goldshire) when there is one; off: the zone.")
    end,
    xprep = function(C)
        C:Cycle("Show", { { value = "AUTO", text = "XP, at the top level reputation" }, { value = "XP", text = "XP" },
            { value = "REP", text = "Reputation" } }, SOpt("show"))
    end,
    currency = function(C)
        C:Cycle("Currency", function()
            local l = { { value = "", text = "The first one you have" } }
            for _, c in ipairs(BL.Currencies()) do l[#l + 1] = { value = c.name, text = c.name } end
            return l
        end, SOpt("name"))
    end,
    profession = function(C)
        C:Cycle("Profession", { { value = 1, text = "The first" }, { value = 2, text = "The second" } }, SOpt("which"))
    end,
    stat = function(C)
        local l = {}
        for _, s in ipairs(BL.STATS) do l[#l + 1] = { value = s.key, text = s.name } end
        C:Cycle("Stat", l, SOpt("stat"))
        C:Note("Right-click the block: the next stat.")
    end,
    combat = function(C)
        local g, s = SOpt("onlyInCombat")
        C:Check("Only in combat", g, s, "Out of combat the block is empty.")
        local gt, st = SOpt("timer")
        C:Check("Fight timer", gt, st, "How long the fight has lasted.")
    end,
}

local function BlocksPage(f)
    local L = UI.Column(f, 0, 0, COL_W)
    PickBar(L)
    L:Button("Arrange blocks (drag them on the bars)", function()
        DB.SetArranging(true)
        if ns.HideConfig then ns.HideConfig() end
    end)
    L:Cycle("Block", BlockChoices, function() return Block() and selBlock end,
        function(v) selBlock = v if ns.RefreshConfig then ns.RefreshConfig() end end)
    L:Button("Add a block", function(self)
        local b = Bar()
        if not b then ns.Print("Make a bar first (Bars tab).") return end
        UI.OpenList(self, BL.Choices(), nil, function(v)
            table.insert(b.blocks, BL.New(v))
            selBlock = #b.blocks
            Changed()
        end)
    end)
    L:Button("Move it left", function()
        local b = Bar()
        if not (b and b.blocks[selBlock] and selBlock > 1) then return end
        b.blocks[selBlock], b.blocks[selBlock - 1] = b.blocks[selBlock - 1], b.blocks[selBlock]
        selBlock = selBlock - 1
        Changed()
    end)
    L:Button("Move it right", function()
        local b = Bar()
        if not (b and b.blocks[selBlock + 1]) then return end
        b.blocks[selBlock], b.blocks[selBlock + 1] = b.blocks[selBlock + 1], b.blocks[selBlock]
        selBlock = selBlock + 1
        Changed()
    end)
    L:Button("Remove it", function()
        local b = Bar()
        if not (b and b.blocks[selBlock]) then return end
        table.remove(b.blocks, selBlock)
        selBlock = math.max(1, selBlock - 1)
        Changed()
    end)
    L:Header("This block")
    L:Slider("Size (%)", 50, 200, 5, KOpt("scale"))
    L:Check("Icon", KOpt("showIcon"))
    L:Cycle("Inside its space", {
        { value = "LEFT", text = "Left" },
        { value = "CENTER", text = "Centre" },
        { value = "RIGHT", text = "Right" },
    }, KOpt("align"))
    L:Slider("Space before", 0, 80, 1, KOpt("padL"))
    L:Slider("Space after", 0, 80, 1, KOpt("padR"))
    local gf, sf = KOpt("fill")
    L:Check("Takes the rest of the bar", function() return gf() end, function(v)
        local b = Bar()
        if b and v then for _, c in ipairs(b.blocks) do c.fill = false end end
        sf(v)
    end, "With spacing by content. Without one set, the last block does.")
    local gc, sc = KOpt("center")
    L:Check("Keep in the middle of the bar", function() return gc() end, function(v)
        local b = Bar()
        if b and v then for _, c in ipairs(b.blocks) do c.center = false end end
        sc(v)
    end, "With spacing by content: its text stays at the bar's middle; the blocks before it start at the left edge, the ones after it end at the right edge, so nothing moves when another block's text gets longer (an FPS number, say).")

    local R = UI.Column(f, COL2_X, 0, COL_W)
    R:Header("Colours")
    R:Cycle("Text colour", TEXT_COLOURS, KOpt("textColor"))
    R:Color("Own text colour", KOpt("textCustom"))
    R:Cycle("Icon colour", ICON_COLOURS, KOpt("iconColor"))
    R:Color("Own icon colour", KOpt("iconCustom"))
    R:Note("By its value: FPS and latency green to red, durability by how worn, combat red / green, audio red when muted.")
    R:Header("Its own options")
    -- one set per type, in the same place; the selected block's shows
    local y = R.y
    local sets = {}
    for key, build in pairs(TYPE_OPTIONS) do
        local sf2 = CreateFrame("Frame", nil, f)
        sf2:SetAllPoints(f)
        build(UI.Column(sf2, COL2_X, y, COL_W))
        sets[key] = sf2
    end
    local none = CreateFrame("Frame", nil, f)
    none:SetAllPoints(f)
    UI.Column(none, COL2_X, y, COL_W):Note("None for this block.")
    f.ShowTypeOptions = function()
        local c = Block()
        local t = c and c.type
        for key, s in pairs(sets) do s:SetShown(key == t) end
        none:SetShown(not sets[t])
    end
end

ns.RegisterPage("databars", "Data Bars", "general", function(page)
    local tabs = { { "bars", "Bars" }, { "blocks", "Blocks" }, { "minimap", "Minimap bar" } }
    local subs, strip = {}, nil
    local function Show(k)
        for n, sf in pairs(subs) do sf:SetShown(n == k) end
        strip:Select(k)
    end
    -- what a data bar is, and the feature's own switch (everything else waits for it)
    local intro = UI.Label(page, "A Data Bar is a small piece of information you can put anywhere on your screen. You can have multiple data bars.")
    intro:SetPoint("TOPLEFT", 0, -22)
    intro:SetWidth(ns.PAGE_W)
    intro:SetJustifyH("LEFT")
    intro:SetTextColor(0.75, 0.75, 0.75)
    intro.hufNoGate = true
    local master = UI.Check(page, 300, "Use Data Bars", function() return ns.db.dataBars.enabled end, function(v)
        DB.SetEnabled(v)
        selBar, selBlock = 1, 1
        Changed()
    end, "Off: no data bar shows (also not the minimap bar) and these settings are greyed out. On: with no bar yet, HUF makes the first one with FPS, latency and your team's gold (MMT).")
    master:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -6)   -- the line may wrap
    master.hufNoGate = true
    UI.Gate(page, master, function() return ns.db.dataBars.enabled end)
    strip = UI.SubTabs(page, tabs, Show)
    strip:SetPoint("TOPLEFT", 0, -80)
    strip:SetPoint("TOPRIGHT", 0, -80)
    subs.bars = SubFrame(page); BarsPage(subs.bars)
    subs.blocks = SubFrame(page); BlocksPage(subs.blocks)
    subs.minimap = SubFrame(page); ns.DataBarsTab(subs.minimap)
    strip:Bind(subs, Show)
    Show("bars")
    page.OpenTab = function(k) if subs[k] then Show(k) end end   -- ns.OpenConfigTab("databars", "minimap")
    page.OnRefresh = function() subs.blocks.ShowTypeOptions() end
    subs.blocks.ShowTypeOptions()
end, function()
    if not ns.db.dataBars.enabled then return false end
    if ns.db.dataBars.minimap.enabled then return true end
    for _, b in ipairs(ns.db.dataBars.bars) do if b.enabled then return true end end
    return false
end)

-- the old Advanced Settings window: now the Data Bars page
function ns.ShowDataBarsWindow() if ns.OpenConfigTab then ns.OpenConfigTab("databars", "bars") end end
