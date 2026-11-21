-- HUF: settings page for nameplates (FRAMES > Nameplates).

local _, ns = ...
local UI = ns.UI
local COL_W, COL2_X, TOP = 330, 366, -36

local function N() return ns.db.nameplates end
local function Opt(k) return function() return N()[k] end, function(v) N()[k] = v end end

local MODES = {
    { value = "NAME", text = "Name only" },
    { value = "NAME_BAR", text = "Name + bar" },
    { value = "BAR", text = "Bar only" },
}
local FRIENDLY = { { value = "SAME", text = "Same as enemies" } }
for _, m in ipairs(MODES) do FRIENDLY[#FRIENDLY + 1] = m end

local OUTLINES = {
    { value = "GLOBAL", text = "General outline" },
    { value = "NONE", text = "None" },
    { value = "OUTLINE", text = "Thin" },
    { value = "THICKOUTLINE", text = "Thick" },
    { value = "MONOCHROME,OUTLINE", text = "Mono" },
}

local function Fonts()
    local l = { { value = "GLOBAL", text = "General font" } }
    for _, f in ipairs(ns.fonts) do l[#l + 1] = { value = f.name, text = f.name } end
    return l
end
local function Textures()
    local l = {}
    for _, t in ipairs(ns.textures) do l[#l + 1] = { value = t.name, text = t.name } end
    return l
end
local function Backgrounds()
    local l = {}
    for _, b in ipairs(ns.backgrounds) do l[#l + 1] = { value = b.name, text = b.name } end
    return l
end

local function SubFrame(page)
    local f = CreateFrame("Frame", nil, page)
    f:SetPoint("TOPLEFT", 0, TOP - 16)
    f:SetSize(ns.PAGE_W, ns.PAGE_H + TOP - 16)
    return f
end

local function GeneralPage(f)
    local L = UI.Column(f, 0, 0, COL_W)
    L:Header("Show")
    L:Cycle("Enemies", MODES, Opt("mode"))
    L:Cycle("Friendly units", FRIENDLY, Opt("friendlyMode"))
    L:Cycle("Friendly players in instances", {
        { value = "HIDE", text = "Hide (keeps names private)" },
        { value = "SHOW", text = "Show Blizzard's (real names)" },
    }, Opt("instanceFriends"))
    L:Header("Bar")
    L:Slider("Width", 40, 250, 1, Opt("width"))
    L:Slider("Height", 1, 20, 1, Opt("height"))
    L:Cycle("Bar texture", Textures, Opt("texture"))
    L:Slider("Raise / lower", -40, 40, 1, Opt("yOffset"))
    L:Header("Stacking")
    local STACK = {
        { value = "GAME", text = "Game setting" },
        { value = "ON", text = "Stack (no overlap)" },
        { value = "OFF", text = "Overlap" },
    }
    L:Cycle("Enemies", STACK, Opt("stackEnemies"))
    L:Cycle("Friendly units", STACK, Opt("stackFriendly"))
    L:Slider("Stack spacing %", 50, 200, 5, Opt("stackSpacing"))
    L:Note("In instances the game protects friendly player nameplates: no addon can draw on them or change their names. \"Hide\" switches them and the names above characters off there while names are private (Names & MMT), and back on outside.")

    local R = UI.Column(f, COL2_X, 0, COL_W)
    R:Header("Colour")
    R:Cycle("Colour by", {
        { value = "CLASS", text = "Class / reaction" },
        { value = "STATIC", text = "Static colour" },
        { value = "STATUS", text = "Status (>75% / >40% / below)" },
    }, Opt("colorMode"))
    R:Color("Static colour", Opt("color"))
    R:Check("Grey when tapped by others", Opt("tappedGray"))
    R:Cycle("NPC colours", {
        { value = "GAME", text = "Standard reaction colours" },
        { value = "CUSTOM", text = "My colours (below)" },
    }, Opt("reactionColors"))
    R:Color("Hostile", Opt("hostileColor"))
    R:Color("Neutral", Opt("neutralColor"))
    R:Color("Friendly", Opt("friendlyColor"))
    local gd, sd = Opt("dimOutOfCombat")
    R:Check("Darker while not in combat", gd, sd, "My colours: hostile NPCs that are not fighting are drawn at 60% brightness.")
    R:Header("Background and border")
    R:Cycle("Background", Backgrounds, Opt("bgTexture"))
    R:Color("Background colour", Opt("bgColor"))
    R:Slider("Border", 0, 3, 0.5, function() return N().borderSize end, function(v) N().borderSize = v end, "%.1f")
    R:Color("Border colour", Opt("borderColor"))
    local gt, st = Opt("targetBorder")
    R:Check("Accent border on my target", gt, st)
end

local function NamePage(f)
    local L = UI.Column(f, 0, 0, COL_W)
    L:Header("Name")
    L:Cycle("Font", Fonts, Opt("font"))
    L:Slider("Size", 6, 20, 1, Opt("fontSize"))
    L:Cycle("Outline", OUTLINES, Opt("outline"))
    L:Cycle("Colour", {
        { value = "REACTION", text = "Class / reaction" },
        { value = "WHITE", text = "White" },
        { value = "CUSTOM", text = "Custom" },
    }, Opt("nameColor"))
    L:Color("Custom colour", Opt("nameCustom"))
    L:Slider("Space to the bar", -10, 10, 1, Opt("nameGap"))
    L:Cycle("Position", {
        { value = "ABOVE", text = "Above the bar" },
        { value = "LEFT", text = "In the bar, left" },
        { value = "CENTER", text = "In the bar, centred" },
    }, Opt("namePosition"))
    L:Header("Friendly units")
    L:Slider("Name size (0: as enemies)", 0, 24, 1, Opt("friendlyFontSize"))
    L:Cycle("Level", {
        { value = "SAME", text = "As enemies" },
        { value = "SHOW", text = "Show" },
        { value = "HIDE", text = "Hide" },
    }, Opt("friendlyLevel"))
    L:Cycle("Name colour", {
        { value = "SAME", text = "As enemies" },
        { value = "REACTION", text = "Class / reaction" },
        { value = "WHITE", text = "White" },
    }, Opt("friendlyNameColor"))

    local R = UI.Column(f, COL2_X, 0, COL_W)
    R:Header("Extras")
    local gl, sl = Opt("showLevel")
    R:Check("Show the level", gl, sl, "Level and classification before the name (\"55E Northshire Guard\"), in difficulty colour.")
    local ga, sa = Opt("levelAlways")
    R:Check("Also when the game hides it", ga, sa, "The game hides some mobs' levels from addons (often all but your target). On: the level read earlier for that mob, else the hidden one as it is, without colour.")
    local gh, sh = Opt("showHealth")
    R:Check("Health on the bar", gh, sh)
    R:Cycle("Health text", {
        { value = "[hp%]", text = "Health % (100%)" },
        { value = "[hp%:nosign]", text = "Health % without sign (100)" },
        { value = "[hp]", text = "Health (12.3k)" },
    }, Opt("healthTag"))
    R:Slider("Health text size (0: automatic)", 0, 20, 1, Opt("healthSize"))
    R:Cycle("Between level and name", {
        { value = " ", text = "Space (55E Name)" },
        { value = " | ", text = "Bar (55E | Name)" },
    }, Opt("levelSep"))
    local ge, se = Opt("showElite")
    R:Check("Elite / rare star right of the bar", ge, se, "Gold star: elite. Silver: rare. Silver with a gold ring: rare elite. Red with a gold ring: boss.")
    R:Slider("Star size", 6, 24, 1, Opt("eliteSize"))
    local gq, sq = Opt("showQuest")
    R:Check("Quest progress left of the bar", gq, sq, "For mobs you need for a quest (kills or quest item drops): your progress, e.g. 2/10, like Blizzard's plates show it.")
    R:Color("Quest progress colour", Opt("questColor"))
    if QuestieLoader then
        R:Cycle("Questie icon", {
            { value = "LEFT", text = "Left of the quest progress" },
            { value = "RIGHT", text = "Right of the bar" },
            { value = "QUESTIE", text = "Where Questie puts it" },
        }, Opt("questieIcon"))
    end
    R:Note("Names follow the privacy setting (Names & MMT), so your MMT team shows the way MMT says.")
end

-- the game's damage numbers over units (world text): read and written as the
-- game's own settings (CVars), not kept in a HUF profile. Nameplates are
-- always drawn over them (no addon can change that): larger numbers, or
-- numbers that fall away faster, are covered less.
local function CVarNum(name, default)
    local v = C_CVar and C_CVar.GetCVar and C_CVar.GetCVar(name)
    return tonumber(v) or default
end
local function SetCVarNum(name, v)
    if InCombatLockdown() then ns.Print("Damage numbers: change them out of combat.") return end
    if C_CVar and C_CVar.SetCVar then pcall(C_CVar.SetCVar, name, tostring(v)) end
end
local function CombatTextPage(f)
    local L = UI.Column(f, 0, 0, COL_W)
    L:Header("Damage numbers (game setting)")
    L:Slider("Size", 0.5, 2.5, 0.05, function() return CVarNum("WorldTextScale_v2", 1) end,
        function(v) SetCVarNum("WorldTextScale_v2", v) end, "%.2f")
    L:Slider("Gravity (how fast they fall away)", 0, 2, 0.05, function() return CVarNum("WorldTextGravity_v2", 0.5) end,
        function(v) SetCVarNum("WorldTextGravity_v2", v) end, "%.2f")
    L:Button("Game defaults (1.00 / 0.50)", function()
        SetCVarNum("WorldTextScale_v2", 1)
        SetCVarNum("WorldTextGravity_v2", 0.5)
        ns.RefreshConfig()
    end)
    local R = UI.Column(f, COL2_X, 0, COL_W)
    R:Header("Why they can hide behind plates")
    R:Note("The damage and healing numbers over units are drawn by the game into the world, and every nameplate (Blizzard's too) is drawn over the world: no addon can bring them in front.")
    R:Note("Larger numbers are covered less; with more gravity they leave the plate sooner. Raising the plates (General: Raise / lower) also helps.")
    R:Note("These are the game's own settings for this account, not part of a HUF profile.")
end

local function CastPage(f)
    local L = UI.Column(f, 0, 0, COL_W)
    L:Header("Cast bar")
    L:Check("Show the cast bar", Opt("showCast"))
    L:Slider("Height", 1, 12, 1, Opt("castHeight"))
    L:Slider("Space to the bar", 0, 10, 1, Opt("castGap"))
    L:Color("Colour", Opt("castColor"))
    local R = UI.Column(f, COL2_X, 0, COL_W)
    R:Header("Details")
    R:Check("Spell icon", Opt("castIcon"))
    R:Check("Spell name", Opt("castText"))
    R:Slider("Spell name size", 6, 14, 1, Opt("castFontSize"))
    R:Header("Interrupts")
    local gi, si = Opt("castInterrupt")
    R:Check("Show \"Interrupted!\"", gi, si, "For a moment, when someone interrupts the cast (a kick, a stun). Not when the caster stops it himself.")
    R:Color("Colour", Opt("castInterruptColor"))
    R:Slider("Shown for", 0.5, 3, 0.5, function() return N().castInterruptTime end,
        function(v) N().castInterruptTime = v end, "%.1f s")
end

local function ComboPage(f)
    local L = UI.Column(f, 0, 0, COL_W)
    L:Header("Combo points")
    local gs, ss = Opt("comboShow")
    L:Check("Show combo points", gs, ss, "Rogues, and druids in cat form: a row of points under your target's plate (the cast bar moves down to make room).")
    local gh, sh = Opt("comboHideEmpty")
    L:Check("Hide with no points", gh, sh, "Only where the game lets addons read the number.")
    local R = UI.Column(f, COL2_X, 0, COL_W)
    R:Header("Look")
    R:Slider("Height", 2, 12, 1, Opt("comboHeight"))
    R:Slider("Space between points", 0, 8, 1, Opt("comboGap"))
    R:Slider("Space to the bar", 0, 10, 1, Opt("comboSpace"))
    R:Color("Colour", Opt("comboColor"))
    R:Note("As wide as the bar. The target frame's combo points: Target > Combo points.")
end

local function ThreatPage(f)
    local L = UI.Column(f, 0, 0, COL_W)
    L:Header("Threat")
    L:Cycle("Show", {
        { value = "OFF", text = "Nothing" },
        { value = "PERCENT", text = "Your threat in %" },
        { value = "GLOW", text = "Glow when it is about to switch to you" },
        { value = "BOTH", text = "Both" },
    }, Opt("threatMode"))
    L:Note("Enemies only, on plates with a bar. The glow needs a group or your pet: alone you always hold the mob.")
    L:Header("Percent")
    L:Cycle("Where", { { value = "RIGHT", text = "In the bar, right" }, { value = "LEFT", text = "In the bar, left" },
        { value = "CENTER", text = "In the bar, centre" }, { value = "OUTSIDE", text = "Right of the bar" } }, Opt("threatPos"))
    L:Slider("Size", 6, 16, 1, Opt("threatSize"))
    local gc, sc = Opt("threatColors")
    L:Check("In threat colours (grey, yellow, orange, red)", gc, sc)
    L:Header("Bar colour")
    L:Cycle("Colour the bar by threat", {
        { value = "OFF", text = "Off (its normal colour)" },
        { value = "ALWAYS", text = "Always" },
        { value = "INSTANCES", text = "In dungeons, raids and scenarios" },
    }, Opt("threatBar"))
    L:Note("Only mobs fighting you or your group. You count as a tank with the tank role or spec, in bear form, in defensive stance or with Righteous Fury.")
    L:Header("Damage and healing")
    local dso, dss = Opt("threatDpsSafeOn")
    L:Check("Own colour when it isn't after you", dso, dss, "Off: the bar keeps its normal colour.")
    L:Color("Not after you", Opt("threatDpsSafe"))
    L:Color("About to switch to you", Opt("threatDpsNear"))
    L:Color("Attacks you", Opt("threatDpsAggro"))
    local R = UI.Column(f, COL2_X, 0, COL_W)
    R:Header("Glow")
    R:Slider("Width", 2, 12, 1, Opt("threatGlowSize"))
    R:Color("About to switch to you", Opt("threatGlowColor"))
    local ga, sa = Opt("threatGlowAggro")
    R:Check("Also while it attacks you", ga, sa, "Off: only the warning before it switches (best for damage and healers). On: tanks see which mobs they hold.")
    R:Color("Attacks you", Opt("threatAggroColor"))
    R:Header("Tanking")
    local tho, ths = Opt("threatTankHoldOn")
    R:Check("Own colour while you hold it", tho, ths, "Off: the bar keeps its normal colour.")
    R:Color("You hold it", Opt("threatTankHold"))
    R:Color("Losing it", Opt("threatTankLosing"))
    R:Color("Lost it", Opt("threatTankLost"))
    local oto, ots = Opt("threatOffTankOn")
    R:Check("Own colour when another tank has it", oto, ots, "Group members with the tank role.")
    R:Color("Another tank has it", Opt("threatOffTank"))
end

local function AuraPage(f)
    local L = UI.Column(f, 0, 0, COL_W)
    L:Header("Icons above the name")
    L:Check("Show debuffs", Opt("showDebuffs"))
    local gm, sm = Opt("debuffsMine")
    L:Check("Only my debuffs", gm, sm)
    L:Check("Show buffs", Opt("showBuffs"))
    L:Cycle("Which buffs", {
        { value = "ALL", text = "All" },
        { value = "PURGE", text = "Only ones that can be dispelled or stolen" },
        { value = "IMPORTANT_PURGE", text = "Important ones and dispellable ones" },
    }, Opt("buffFilter"))
    local ge, se = Opt("buffTypeEdge")
    L:Check("Edge in the buff's type colour", ge, se, "Magic blue, so a buff you can purge stands out.")
    L:Note("Dispellable: by anyone, whatever your class (purges, enrages, spell steal). The game checks it itself, so it works in every fight.")
    local R = UI.Column(f, COL2_X, 0, COL_W)
    R:Header("Size")
    R:Slider("Icon size", 6, 30, 1, Opt("auraSize"))
    R:Slider("Icons per row", 1, 10, 1, Opt("auraMax"))
    R:Slider("Rows", 1, 4, 1, Opt("auraRows"))
    R:Slider("Space", 0, 6, 1, Opt("auraGap"))
    local gt, st = Opt("auraTimer")
    R:Check("Time left as numbers", gt, st)
    R:Slider("Time size (0: automatic)", 0, 20, 1, Opt("auraTimerSize"))
    R:Note("Debuffs start at the left, buffs at the right. Shown by the game's own aura display, so they also work where addons may not read auras.")
end

ns.RegisterPage("nameplates", "Nameplates", "frames", function(page)
    local on = UI.Check(page, 260, "Use HUF's nameplates", function() return N().enabled end, function(v)
        N().enabled = v
    end, "Off: Blizzard's nameplates come back.")
    on:SetPoint("TOPLEFT", 0, 4)
    local reset = UI.Button(page, 100, "Reset", function()
        UI.Confirm("Reset every nameplate setting?", "Reset", function()
            ns.db.nameplates = ns.CopyTable(ns.DEFAULTS.nameplates)
            ns.Refresh(true)
        end)
    end)
    reset:SetPoint("TOPRIGHT", 0, 4)
    local tabs = { { "general", "General" }, { "name", "Name & level" }, { "cast", "Cast bar" }, { "combo", "Combo points" }, { "threat", "Threat" }, { "auras", "Buffs & debuffs" }, { "numbers", "Damage numbers" } }
    local subs, strip = {}, nil
    local function Show(k)
        for n, sf in pairs(subs) do sf:SetShown(n == k) end
        strip:Select(k)
    end
    strip = UI.SubTabs(page, tabs, Show)
    strip:SetPoint("TOPLEFT", 0, -22)
    strip:SetPoint("TOPRIGHT", 0, -22)
    subs.general = SubFrame(page); GeneralPage(subs.general)
    subs.name = SubFrame(page); NamePage(subs.name)
    subs.cast = SubFrame(page); CastPage(subs.cast)
    subs.combo = SubFrame(page); ComboPage(subs.combo)
    subs.threat = SubFrame(page); ThreatPage(subs.threat)
    subs.auras = SubFrame(page); AuraPage(subs.auras)
    subs.numbers = SubFrame(page); CombatTextPage(subs.numbers)
    strip:Bind(subs, Show)
    Show("general")
end, function() return ns.db.nameplates.enabled end)
