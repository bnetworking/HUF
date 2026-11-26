-- HUF: the pages of the configuration window.
-- GENERAL: General, Names & MMT, Profiles, Help. FRAMES: one page per frame
-- with sub pages: Frame, Health bar, Power bar, Texts, Debuffs, Buffs.

local _, ns = ...
local UI = ns.UI
local A = UI.ACCENT
local COL_W = 330
local COL2_X = 366
local TOP = -36

local function U(key) return ns.db.units[key] end

-- getter / setter pair for field `k` of the table tbl() returns
local function Opt(tbl, k)
    return function() return tbl()[k] end,
           function(v) tbl()[k] = v end
end

local function FontChoices(withGlobal)
    local l = {}
    if withGlobal then l[1] = { value = "GLOBAL", text = "HUF Global Font" } end
    local blizz, eui = {}, {}
    for _, f in ipairs(ns.fonts) do
        if f.ellesmere then eui[#eui + 1] = f else blizz[#blizz + 1] = f end
    end
    for _, f in ipairs(blizz) do l[#l + 1] = { value = f.name, text = f.name } end
    if #eui > 0 then
        l[#l + 1] = { header = true, text = "EllesmereUI" }
        for _, f in ipairs(eui) do l[#l + 1] = { value = f.name, text = f.name } end
    end
    return l
end

local function TextureChoices()
    local l, eui = {}, {}
    for _, t in ipairs(ns.textures) do
        if t.ellesmere then eui[#eui + 1] = t else l[#l + 1] = { value = t.name, text = t.name } end
    end
    if #eui > 0 then
        l[#l + 1] = { header = true, text = "EllesmereUI" }
        for _, t in ipairs(eui) do l[#l + 1] = { value = t.name, text = t.name } end
    end
    return l
end
ns.TextureChoices = TextureChoices

local function BackgroundChoices()
    local l = {}
    for _, b in ipairs(ns.backgrounds) do l[#l + 1] = { value = b.name, text = b.name } end
    return l
end

local OUTLINES = {
    { value = "NONE", text = "None" },
    { value = "OUTLINE", text = "Thin" },
    { value = "THICKOUTLINE", text = "Thick" },
    { value = "MONOCHROME,OUTLINE", text = "Mono" },
}
local OUTLINES_G = { { value = "GLOBAL", text = "HUF Global Outline" } }
for _, o in ipairs(OUTLINES) do OUTLINES_G[#OUTLINES_G + 1] = o end
ns.FontChoices, ns.OUTLINES_G = FontChoices, OUTLINES_G

---------------------------------------------------------------------------
-- GENERAL: three tiles (as MMT's settings): Look and Feel, Frames & Features,
-- Addon Support
---------------------------------------------------------------------------
local TILE_W, TILE_GAP = 344, 10
local function Tile(parent, x, y, w, h, title, icon)
    local t = CreateFrame("Frame", nil, parent)
    t:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    t:SetSize(w, h)
    UI.Fill(t, A[1], A[2], A[3], 0.04)
    UI.Border(t, A[1], A[2], A[3], 0.30)
    local ic = t:CreateTexture(nil, "ARTWORK")
    ic:SetTexture(icon)
    ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    ic:SetSize(22, 22)
    ic:SetPoint("TOPLEFT", 8, -7)
    local label = UI.Label(t, title, "GameFontNormalLarge")
    label:SetPoint("LEFT", ic, "RIGHT", 8, 0)
    label:SetTextColor(A[1], A[2], A[3])
    local line = t:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(A[1], A[2], A[3], 0.35)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", 8, -34)
    line:SetPoint("TOPRIGHT", -8, -34)
    return t, UI.Column(t, 8, -42, w - 16)
end
ns.ConfigTile = Tile

-- every unit frame text back to the HUF global font and outline
local function OverwriteFrameFonts()
    local n = 0
    local function Walk(t)
        for k, v in pairs(t) do
            if type(v) == "table" then Walk(v) end
        end
        if t.font ~= nil and t.font ~= "GLOBAL" then t.font = "GLOBAL" n = n + 1 end
        if t.outline ~= nil and t.outline ~= "GLOBAL" then t.outline = "GLOBAL" n = n + 1 end
    end
    for _, u in pairs(ns.db.units) do if type(u) == "table" then Walk(u) end end
    ns.Refresh()
    ns.Print("Every unit frame text uses the HUF global font now (%d settings changed).", n)
end

-- the list of the game's windows that can be moved, with a reset each
local resetWin
local function ResetWindows()
    local W = ns.Windows
    if not resetWin then
        local f = CreateFrame("Frame", "HUF_ResetWindows", UIParent)
        f:SetSize(340, 440)
        f:SetPoint("CENTER", 0, 20)
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:SetToplevel(true)
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        UI.Fill(f, 0.05, 0.05, 0.06, 0.97)
        UI.Border(f, A[1], A[2], A[3], 0.9)
        local title = UI.Label(f, "Reset frames", "GameFontNormal")
        title:SetPoint("TOPLEFT", 12, -10)
        title:SetTextColor(A[1], A[2], A[3])
        local close = UI.Button(f, 22, "x", function() f:Hide() end)
        close:SetPoint("TOPRIGHT", -6, -6)
        local note = UI.Label(f, "Moved windows go back where the game puts them.")
        note:SetPoint("TOPLEFT", 12, -30)
        note:SetTextColor(0.6, 0.6, 0.6)
        local sf = CreateFrame("ScrollFrame", nil, f)
        sf:SetPoint("TOPLEFT", 10, -52)
        sf:SetPoint("BOTTOMRIGHT", -10, 46)
        local child = CreateFrame("Frame", nil, sf)
        child:SetSize(320, 10)
        sf:SetScrollChild(child)
        sf:EnableMouseWheel(true)
        sf:SetScript("OnMouseWheel", function(self, d)
            local max = math.max(0, child:GetHeight() - self:GetHeight())
            self:SetVerticalScroll(math.max(0, math.min(max, self:GetVerticalScroll() - d * 40)))
        end)
        f.child, f.rows = child, {}
        local all = UI.Button(f, 140, "Reset all", function()
            W.ResetAll()
            f.Fill()
        end)
        all:SetPoint("BOTTOM", 0, 12)
        f.Fill = function()
            local names = W.List()
            for i, name in ipairs(names) do
                local r = f.rows[i]
                if not r then
                    r = CreateFrame("Frame", nil, child)
                    r:SetSize(316, 24)
                    r:SetPoint("TOPLEFT", 0, -(i - 1) * 26)
                    if i % 2 == 0 then UI.Fill(r, 1, 1, 1, 0.03) end
                    r.label = UI.Label(r, "")
                    r.label:SetPoint("LEFT", 6, 0)
                    r.state = UI.Label(r, "")
                    r.state:SetPoint("RIGHT", -86, 0)
                    r.btn = UI.Button(r, 76, "Reset", function()
                        W.Reset(r.name)
                        f.Fill()
                    end)
                    r.btn:SetPoint("RIGHT", -2, 0)
                    f.rows[i] = r
                end
                r.name = name
                r.label:SetText(W.Pretty(name))
                local moved = W.IsMoved(name)
                r.state:SetText(moved and "moved" or "")
                r.state:SetTextColor(A[1], A[2], A[3])
                UI.SetActive(r.btn, moved)
                r:Show()
            end
            for i = #names + 1, #f.rows do f.rows[i]:Hide() end
            child:SetHeight(math.max(10, #names * 26))
        end
        UI.CloseOnEscape(f)
        resetWin = f
    end
    resetWin.Fill()
    resetWin:Show()
end
ns.ShowResetWindows = ResetWindows

ns.RegisterPage("general", "General", "general", function(page)
    local G = function() return ns.db.global end
    local P = function() return ns.db.privacy end
    local H = ns.PAGE_H
    local X2 = TILE_W + TILE_GAP

    -- Look and Feel ---------------------------------------------------------
    local LOOK_H = 296
    local _, L = Tile(page, 0, 0, TILE_W, LOOK_H, "Look and Feel", "Interface\\Icons\\INV_Misc_Ribbon_01")
    L:Cycle("Accent colour", ns.ACCENTS, function() return G().accent end, function(v)
        G().accent = v
        ns.ApplyAccent()
        ns.AskReload("The settings window takes the new accent colour fully after a reload.")
    end, "Used by the settings window and by every bar colour set to \"accent\" (the default health gradients).")
    L:Color("Custom accent", function() return G().accentColor end, function(c)
        G().accentColor = c
        if G().accent == "CUSTOM" then ns.ApplyAccent() end
    end)
    L:Cycle("Settings background", BackgroundChoices, Opt(G, "configBg"))
    L:Cycle("HUF Global Font", function() return FontChoices(false) end, Opt(G, "font"),
        "The font every HUF text uses whose own font is set to \"HUF Global Font\".")
    L:Cycle("Font Outline", OUTLINES, Opt(G, "outline"))
    L:Check("Text Shadow", Opt(G, "shadow"))
    L:Button("Overwrite individual frame font settings", function()
        UI.Confirm("Set the font and outline of every unit frame text back to the HUF global font?", "Overwrite", OverwriteFrameFonts)
    end)
    L:Space(14)
    local ga, sa = Opt(G, "abbreviate")
    L:Check("Short numbers (12.3k)", ga, sa, "Health and power values as 12.3k instead of 12345.")
    local gs, ss = Opt(G, "statusText")
    L:Check("Show Dead, Ghost or Offline instead of health", gs, ss)
    local gx, sx = Opt(G, "shortenTexts")
    L:Check("Avoid overlapping texts", gx, sx,
        "When an object, like the player health bar, has a text set on the left side (like the name) and one on the right side (like %HP) it may happen that they clip into each other. Enabling this option will avoid this by truncating texts if necessary.")
    -- Loot Feed (LootFeedConfig.lua) -----------------------------------------
    local LOOT_Y = -(LOOK_H + TILE_GAP)
    ns.BuildLootFeedTile(page, 0, LOOT_Y, TILE_W, H + LOOT_Y)

    -- Frames & Features -----------------------------------------------------
    local FF_H = 310
    local ff, F = Tile(page, X2, 0, TILE_W, FF_H, "Frames & Features", "Interface\\Icons\\INV_Misc_Gear_01")
    local gh, sh = Opt(G, "hideBlizzard")
    F:Check("Hide Blizzard's frames HUF replaces", gh, function(v)
        sh(v)
        if not v then ns.AskReload("Blizzard's frames come back after a reload.") end
    end, "Hides Blizzard's player, target and target-of-target frames while HUF's are on.")
    local gr, sr = Opt(G, "hideRaidManager")
    F:Check("Hide Blizzard's raid / party manager", gr, function(v)
        sr(v)
        if not v then ns.AskReload("The raid / party manager comes back after a reload.") end
    end, "The panel on the left edge of the screen in a group (marks, ready check, roles).")
    -- windows: the two switches narrower, the reset button beside them
    local Win = function() return ns.db.windows end
    local shiftBox
    local move = UI.Check(ff, F.width - 112, "Allow all windows to move", function() return Win().enabled end, function(v)
        Win().enabled = v
        if v then ns.Windows.Apply() else ns.AskReload("The windows stay where they are until a reload.") end
        UI.SetActive(shiftBox, v)
    end, "Drag the game's windows (character, spellbook, professions, quests, map, mail, merchant, bank, friends, guild, ...) by an empty part; their places are remembered. Shift + right-click on a window puts it back."
        .. (ns.Windows.Other() and " ForeverMove is enabled: it moves the windows, so HUF leaves them alone." or ""))
    F:Add(move, UI.ROW)
    shiftBox = UI.Check(ff, F.width - 128, "Only while Shift is held", function() return Win().shift end,
        function(v) Win().shift = v end, "Drag with Shift held, so a window doesn't move by accident.")
    F:Add(shiftBox, UI.ROW, 16)
    local reset = UI.Button(ff, 104, "Reset frames", ResetWindows)
    reset:SetPoint("TOPRIGHT", move, "TOPRIGHT", 112, -10)
    table.insert(page.widgets, { Refresh = function() UI.SetActive(shiftBox, Win().enabled) end })
    -- the menu bar's reminder boxes (Reminders.lua)
    F:Space(4)
    local remLabel = UI.Label(ff, "Hide the menu bar's reminders:")
    F:Add(remLabel, 18)
    local Rem = function() return G().hideReminders end
    local remRow = CreateFrame("Frame", nil, ff)
    remRow:SetSize(F.width, UI.ROW)
    local REM = {
        { "talents", "Talents", "\"You have unspent Talent points.\" at the talents button." },
        { "legacy", "Legacy", "The unspent Legacy points box at the Legacy button." },
        { "other", "Everything else", "Every other box at a menu bar button (new mounts / pets / toys, tips, ...)." },
    }
    local cw = { 84, 84, F.width - 168 }
    local rx = 16
    for i, r in ipairs(REM) do
        local cb = UI.Check(remRow, cw[i], r[2], function() return Rem()[r[1]] end, function(v) Rem()[r[1]] = v end,
            r[3] .. " The box is closed as soon as the game shows it; the game itself is not changed.")
        cb:SetPoint("LEFT", remRow, "LEFT", rx - 16, 0)
        rx = rx + cw[i]
    end
    F:Add(remRow, UI.ROW, 16)
    -- instance resets (Resets.lua)
    F:Check("Tell the group when I reset instances", function() return ns.db.resets.announce end,
        function(v) ns.db.resets.announce = v end,
        "After you reset instances, HUF says in group chat (instance, raid or party) which were reset, or which could not be and why (players still inside, offline or zoning in). Only the one who resets says it; nothing outside a group.")
    F:Check("Button in the game menu (Esc)", function() return G().gameMenuButton ~= false end,
        function(v) G().gameMenuButton = v if ns.RelayoutGameMenu then ns.RelayoutGameMenu() end end,
        "A HUF button below the game menu (Esc) opens these settings.")

    -- UI scale (UIScale.lua): below the game's 0.64, like EllesmereUI; the switch
    -- with a small slider to its right, the pixel perfect button under them
    local US = ns.UIScale
    local U = function() return ns.db.uiScale end
    local scaleRow = CreateFrame("Frame", nil, ff)
    scaleRow:SetSize(F.width, 34)
    local scaleSlider
    local useScale = UI.Check(scaleRow, 160, "Use HUF's UI scale", function() return U().enabled end, function(v)
        U().enabled = v
        if v then US.Apply()
        elseif not US.Restore() then ns.AskReload("The game's own UI scale comes back after a reload.") end
    end, "Sets the scale of the whole interface itself, from 0.40 to 1.15 - the game's own UI Scale stops at 0.64. Off: the game's UI Scale (Esc > Options) as before."
        .. (US.EllesmereOwns() and "\n\nEllesmereUI is loaded and sets the scale itself, so HUF leaves it alone while EllesmereUI is on." or ""))
    useScale:SetPoint("LEFT", scaleRow, "LEFT", 0, -4)
    -- drag: steps of 0.01; the box takes any value typed (0.5333 ...)
    scaleSlider = UI.Slider(scaleRow, 150, "Scale", US.MIN, US.MAX, 0.01, function() return US.Clamp(U().scale) end, function(v)
        U().scale = US.Clamp(v)
        US.ApplySoon()
    end, "%.4f")
    scaleSlider.EnableInput(0.0001)
    scaleSlider:SetPoint("TOPRIGHT", scaleRow, "TOPRIGHT", 0, 0)
    F:Add(scaleRow, 36)
    F:Button("Pixel perfect for this screen", function()
        local v = US.PixelPerfect()
        if not v then return end
        U().scale = US.Clamp(v)
        if scaleSlider and scaleSlider.Refresh then scaleSlider.Refresh() end
        US.Apply()
        ns.Print("UI scale %.4f (768 / %d screen lines)%s.", U().scale, select(2, GetPhysicalScreenSize()),
            U().enabled and "" or " - tick \"Use HUF's UI scale\" to use it")
    end)

    -- Addon Support ---------------------------------------------------------
    local AS_Y = -(FF_H + TILE_GAP)
    local as, S = Tile(page, X2, AS_Y, TILE_W, H + AS_Y, "Addon Support", "Interface\\Icons\\INV_Misc_Book_09")
    local mmtLoaded = function() return type(_G.MMT) == "table" end
    local mmtCheck, privCheck, nameDrop
    local function Deps()
        local allowed = G().mmt ~= false
        UI.SetActive(mmtCheck, mmtLoaded())
        UI.SetActive(privCheck, mmtLoaded() and allowed)
        local mmtNames = mmtLoaded() and allowed and P().mmt ~= "NEVER"
        UI.SetActive(nameDrop, not mmtNames)
    end
    mmtCheck = S:Check("Allow MMT interaction", function() return G().mmt ~= false end, function(v)
        G().mmt = v
        Deps()
        ns.RefreshNames()
        ns.AskReload(v and "HUF links up with MMT after a reload." or "HUF lets go of MMT completely after a reload.")
    end, "HUF works together with MMT (Manage My Team): its privacy names, its team (\"my group\" in the dispel settings) and its windows in HUF's unlock mode. Off: HUF ignores MMT.")
    privCheck = S:Check("Use MMT privacy setting for names", function() return P().mmt ~= "NEVER" end, function(v)
        P().mmt = v and "ALWAYS" or "NEVER"
        Deps()
        ns.RefreshNames()
    end, "Your MMT team's characters show the name MMT > Team > Privacy chooses (First name, Last name, Class X, Slot X).")
    local gm, sm = Opt(P, "mode")
    nameDrop = S:Cycle("Names show players as", {
        { value = "FIRST", text = "First name" },
        { value = "LAST",  text = "Last name" },
        { value = "FULL",  text = "Full name" },
        { value = "CLASS", text = "Class X (group)" },
        { value = "SLOT",  text = "Slot X (group)" },
    }, gm, function(v) sm(v) ns.RefreshNames() end,
        "For texts using [name]. [name:first], [name:last] and [name:full] always show that part. Class X and Slot X number the members of your group; players outside it show their first name. NPC names are never changed.")
    local status = UI.Label(as, "")
    status:SetJustifyH("LEFT")
    status:SetWidth(S.width)
    S:Add(status, 34)
    S:Space(6)
    local qCheck = S:Check("Use Questie's quest data", function() return G().questie ~= false end, function(v) G().questie = v end,
        "When Questie is installed, HUF's quest window (a click on a quest link in chat) adds Questie's data: description, objectives, who starts and ends the quest, and where.")
    local gc, sc = Opt(G, "clickCast")
    S:Check("Register for click-casting addons (Clique)", gc, function(v)
        sc(v)
        ns.AskReload("Click-casting addons see the change after a reload.")
    end, "Registers HUF's frames for click-casting addons like Clique.")
    table.insert(page.widgets, { Refresh = function()
        Deps()
        UI.SetActive(qCheck, ns.QuestLinks and ns.QuestLinks.QuestieLoaded() or false)
        local st = ns.Bridge.Status()
        if not mmtLoaded() then
            status:SetText("|cffaaaaaaMMT is not installed or not enabled.|r")
        elseif G().mmt == false then
            status:SetText("|cffaaaaaaMMT is loaded; HUF ignores it.|r")
        else
            local line = ("MMT%s loaded, team: %d characters."):format(st.version and (" " .. st.version) or "", st.teamSize or 0)
            if st.apiState == "newer" then line = line .. "\n|cffff8040MMT is newer than this HUF knows: HUF may need an update.|r" end
            status:SetText(line)
        end
    end })
end)

-- Profiles
---------------------------------------------------------------------------
ns.RegisterPage("profiles", "Profiles", "general", function(page)
    local L = UI.Column(page, 0, 0, COL_W)
    L:Header("Profile")
    L:Note("Profiles are account-wide. Each character picks the one it uses.")
    L:Cycle("Active profile", function()
        local l = {}
        for _, n in ipairs(ns.ProfileNames()) do l[#l + 1] = { value = n, text = n } end
        return l
    end, function() return ns.CurrentProfileName() end, function(v)
        if v == ns.CurrentProfileName() then return end
        ns.SetProfile(v)
        ns.AskReload(("Profile \"%s\" is active. "):format(v) .. "Some parts (the quest log, the bag window, the minimap, ...) only switch over fully after a reload.")
    end)

    local status = UI.Label(page, "")
    local box = UI.EditBox(page, COL_W - 90, "new profile name", function(text, self)
        text = ns.Trim(text)
        if text == "" then return end
        ns.SetProfile(text)
        self:SetText("")
        self:ClearFocus()
        status:SetText(("Profile \"%s\" is active."):format(text))
        ns.AskReload(("Profile \"%s\" is active. "):format(text) .. "Some parts (the quest log, the bag window, the minimap, ...) only switch over fully after a reload.")
    end)
    L:Add(box, 0)
    local create = UI.Button(page, 84, "Create", function()
        local text = ns.Trim(box:GetText())
        if text == "" then return end
        ns.SetProfile(text)
        box:SetText("")
        box:ClearFocus()
        status:SetText(("Profile \"%s\" is active."):format(text))
        ns.AskReload(("Profile \"%s\" is active. "):format(text) .. "Some parts (the quest log, the bag window, the minimap, ...) only switch over fully after a reload.")
    end)
    create:SetPoint("TOPLEFT", box, "TOPRIGHT", 6, 0)
    L:Space(UI.ROW + 4)
    L:Note("A new profile starts with the default settings.")

    L:Header("Copy and delete")
    L:Cycle("Copy settings from", function()
        local l = {}
        for _, n in ipairs(ns.ProfileNames()) do
            if n ~= ns.CurrentProfileName() then l[#l + 1] = { value = n, text = n } end
        end
        return l
    end, function() return nil end, function(v)
        UI.Confirm(("Replace every setting of \"%s\" with the settings of \"%s\"?"):format(ns.CurrentProfileName(), v), "Copy",
            function() ns.CopyProfile(v) status:SetText(("Copied from \"%s\"."):format(v)) end)
    end)
    L:Cycle("Delete profile", function()
        local l = {}
        for _, n in ipairs(ns.ProfileNames()) do
            if n ~= ns.CurrentProfileName() then l[#l + 1] = { value = n, text = n } end
        end
        return l
    end, function() return nil end, function(v)
        UI.Confirm(("Delete the profile \"%s\"? Characters using it switch to \"Default\"."):format(v), "Delete",
            function() if ns.DeleteProfile(v) then status:SetText(("Deleted \"%s\"."):format(v)) ns.RefreshConfig() end end)
    end)
    L:Button("Reset active profile", function()
        UI.Confirm(("Reset every setting of \"%s\" to the defaults?"):format(ns.CurrentProfileName()), "Reset",
            function() ns.ResetProfile() status:SetText("Reset to defaults.") end)
    end)
    L:Space(4)
    L:Add(status)
    status:SetTextColor(0.6, 0.6, 0.6)

    -- export / import as text (copy & paste, e.g. to another account)
    local R = UI.Column(page, COL2_X, 0, COL_W)
    R:Header("Export and import")
    R:Note("Export: every setting of the active profile as one line of text, with this character's click-cast bindings, the game's chat settings and colours and the damage number settings. Copy it (Ctrl+A, Ctrl+C) and paste it into HUF on another account or PC (Ctrl+V), then Import.")
    local area = UI.TextArea(page, COL_W, 170)
    if area.edit.SetMaxLetters then area.edit:SetMaxLetters(0) end
    R:Add(area, 178)
    local msg = UI.Label(page, "")
    msg:SetWidth(COL_W)
    msg:SetJustifyH("LEFT")
    msg:SetWordWrap(true)
    msg:SetTextColor(0.6, 0.6, 0.6)
    local exp = UI.Button(page, (COL_W - 6) / 2, "Export", function()
        local ok, text = pcall(ns.ExportProfile)
        if not ok then msg:SetText("Export failed: " .. tostring(text)) return end
        area.edit:SetText(text)
        area.edit:SetFocus()
        area.edit:HighlightText()
        msg:SetText(("Profile \"%s\" exported (%d characters). Copy it with Ctrl+C."):format(ns.CurrentProfileName(), #text))
    end)
    R:Add(exp, 0)
    -- EllesmereUI's frames (from a string or its live settings) -> HUF's
    -- the import window: which frames to show (ticked as in Ellesmere; a
    -- frame Ellesmere has off can be turned on), and while EllesmereUI
    -- Nameplates is loaded, whether to turn it off (two plates otherwise)
    local dlg
    local MAX_ROWS, MAX_EXTRA = 20, 6
    local function ImportWindow()
        if dlg then return dlg end
        local f = CreateFrame("Frame", "HUFEllesmereImportFrame", UIParent)
        f:SetWidth(400)
        f:SetPoint("TOP", 0, -140)
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:EnableMouse(true)
        UI.Fill(f, 0.05, 0.05, 0.06, 0.96)
        UI.Border(f, ns.ACCENT[1], ns.ACCENT[2], ns.ACCENT[3], 0.6)
        f.text = UI.Label(f, "")
        f.text:SetPoint("TOPLEFT", 16, -16)
        f.text:SetPoint("TOPRIGHT", -16, -16)
        f.text:SetJustifyH("LEFT")
        f.rows, f.extras = {}, {}
        local function NewRow()
            local row = { on = false }
            row.check = UI.Check(f, 368, "", function() return row.on end, function(v) row.on = v end)
            return row
        end
        for i = 1, MAX_ROWS do f.rows[i] = NewRow() end
        for i = 1, MAX_EXTRA do f.extras[i] = NewRow() end
        local function Accept()
            local fn = f.onAccept
            f.onAccept = nil
            if fn then fn() end      -- first: it may ask for a reload
            f:Hide()
        end
        f.accept = UI.Button(f, 116, "Import", Accept)
        f.accept:SetPoint("BOTTOMLEFT", 16, 14)
        -- every listed part off (then pick the few to import), or on again
        f.all = UI.Button(f, 116, "Untick all", function()
            local any = false
            for _, row in ipairs(f.rows) do
                if row.part and row.on then any = true end
            end
            for _, row in ipairs(f.rows) do
                if row.part then
                    row.on = not any
                    row.check.Refresh()
                end
            end
            f.all.label:SetText(any and "Tick all" or "Untick all")
        end)
        f.all:SetPoint("BOTTOM", 0, 14)
        f.cancel = UI.Button(f, 116, "Cancel", function() f:Hide() end)
        f.cancel:SetPoint("BOTTOMRIGHT", -16, 14)
        f:SetScript("OnHide", function() f.onAccept = nil end)
        UI.CloseOnEscape(f)
        f:Hide()
        dlg = f
        return f
    end

    -- parts: { title, tbl (.enabled), on, why, folder (the EllesmereUI module
    -- drawing the same thing, offered to be turned off while it is loaded) }
    -- src: { name (shown), base (the new profile's name), merge (t, parts, chosen) -> profile }
    local ELLESMERE = { name = "EllesmereUI", base = "EllesmereUI", merge = function(...) return ns.MergeEllesmere(...) end }
    local function EllesmereImport(ok, t, notes, what, parts, src)
        if not ok then msg:SetText("|cffff6060" .. t .. "|r") return end
        src = src or ELLESMERE
        parts = parts or {}
        local list = table.concat(what, ", "):gsub(", ([^,]*)$", " and %1")
        local f = ImportWindow()
        f.text:SetText(("A new profile: a copy of \"%s\" with the ticked parts from %s.\nYour profile stays as it is (Active profile switches back)."):format(ns.CurrentProfileName(), src.name))
        local y = -52
        local function Place(row)
            row.check:ClearAllPoints()
            row.check:SetPoint("TOPLEFT", 16, y)
            row.check.Refresh()
            row.check:Show()
            y = y - (UI.ROW - 2)
        end
        f.all.label:SetText("Untick all")
        for i, row in ipairs(f.rows) do
            local part = parts[i]
            row.part = part
            if part then
                row.on = true
                row.check.label:SetText(part.on and part.title
                    or (part.title .. "  |cff888888(" .. part.why .. ": imported as off)|r"))
                Place(row)
            else
                row.check:Hide()
            end
        end
        -- an EllesmereUI module drawing the same thing: offer to turn it off
        y = y - 8
        local loaded = C_AddOns and C_AddOns.IsAddOnLoaded
        local n = 0
        for _, part in ipairs(parts) do
            if part.folder and loaded and loaded(part.folder) and C_AddOns.DisableAddOn and n < MAX_EXTRA then
                n = n + 1
                local row = f.extras[n]
                row.part, row.on = part, true
                row.check.label:SetText(("Turn off %s (reloads)"):format(part.module or part.folder))
                Place(row)
            end
        end
        for i = n + 1, MAX_EXTRA do
            f.extras[i].part = nil
            f.extras[i].check:Hide()
        end
        f:SetHeight(-y + 64)
        f.onAccept = function()
            -- the parts to import (a module is turned off only for those)
            local chosen, names, taken = {}, {}, {}
            for i, row in ipairs(f.rows) do
                if row.part and row.on then
                    chosen[i] = true
                    taken[row.part] = true
                    names[#names + 1] = row.part.title:lower()
                end
            end
            if #names == 0 then
                msg:SetText("Nothing ticked: nothing imported.")
                return
            end
            -- a module to turn off needs a reload. The game allows it only from
            -- a click and only when asked first thing in it; the client
            -- reloads once this click's code is done, so the import below
            -- still runs and is saved. In combat: ask again after the fight.
            local reload = false
            for _, row in ipairs(f.extras) do
                if row.part and taken[row.part] and row.check:IsShown() and row.on then reload = true end
            end
            local fight = InCombatLockdown()
            if reload and not fight then ReloadUI() end
            list = table.concat(names, ", "):gsub(", ([^,]*)$", " and %1")
            local newName = ns.ImportProfileAsNew(src.base, src.merge(t, parts, chosen))
            area.edit:SetText("")
            msg:SetText(("%s: %s imported into the new profile \"%s\"%s"):format(src.name, list, newName,
                #notes > 0 and " (details in chat)." or "."))
            ns.Print("Import: a new profile \"%s\" (your old one is still there: Profiles > Active profile).", newName)
            for _, line in ipairs(notes) do ns.Print("Ellesmere import: %s", line) end
            for _, row in ipairs(f.extras) do
                local part = row.part
                if part and taken[part] and row.check:IsShown() then
                    if row.on then
                        pcall(C_AddOns.DisableAddOn, part.folder, UnitName("player"))
                    elseif part.tbl.enabled then
                        ns.Print("%s is still on next to HUF's %s: both draw it.", part.module or part.folder, part.title:lower())
                    end
                end
            end
            if reload and fight then
                ns.Print("A reload has to wait for the end of the fight.")
                ns.RunOOC("reload", function()
                    UI.Confirm("Reload now to finish turning the EllesmereUI module off?", "Reload", ReloadUI, "Later")
                end)
            elseif not reload then
                -- everything drawn and switched on as imported (the quest log, the bag window, ...)
                ns.AskReload(("Imported into the new profile \"%s\". Everything is fully in place after a reload."):format(newName))
            end
        end
        f:Show()
    end
    local imp = UI.Button(page, (COL_W - 6) / 2, "Import", function()
        local text = area.edit:GetText()
        if ns.IsEllesmereText(text) then
            EllesmereImport(ns.ReadEllesmereText(text))
            return
        end
        local ok, t = ns.ReadProfileText(text)
        if not ok then msg:SetText("|cffff6060" .. t .. "|r") return end
        -- the same window: tick what to take, into a new profile
        local parts = ns.ProfileParts(t)
        local names = {}
        for _, p in ipairs(parts) do names[#names + 1] = p.title:lower() end
        EllesmereImport(true, t, {}, names, parts,
            { name = "the imported text", base = "Imported", merge = ns.MergeParts })
    end)
    imp:SetPoint("TOPLEFT", exp, "TOPRIGHT", 6, 0)
    R:Space(UI.ROW + 4)
    if _G.EllesmereUI and ns.ReadEllesmereLive then
        R:Button("Import from EllesmereUI (its current settings)", function()
            EllesmereImport(ns.ReadEllesmereLive())
        end)
    end
    R:Add(msg, 40)
    R:Note("An import (a HUF text or EllesmereUI) goes into a new profile, \"Imported\" or \"EllesmereUI\", with only the parts you tick; click-cast bindings go to the character you import on. Kept chat lines are not exported.")
    if _G.EllesmereUI then R:Note("EllesmereUI: \"Import from EllesmereUI\" or an EllesmereUI string (!EUI_...) in the box: its unit frames (player, target, target of target, pet, with the font), nameplates and damage meter replace HUF's; group frames stay. Close to Ellesmere's look, not identical.") end
end)

---------------------------------------------------------------------------
-- FRAMES: one page per frame
---------------------------------------------------------------------------
local function SubFrame(page)
    local f = CreateFrame("Frame", nil, page)
    f:SetPoint("TOPLEFT", 0, TOP - 16)
    f:SetSize(ns.PAGE_W, ns.PAGE_H + TOP - 16)
    return f
end

-- Frame: size, position, background, portrait
local function FramePage(f, key)
    local S = function() return U(key) end
    local P = function() return U(key).portrait end
    local L = UI.Column(f, 0, 0, COL_W)
    L:Header("Size")
    L:Slider("Width", 60, 400, 1, Opt(S, "width"))
    L:Slider("Height", 10, 80, 1, Opt(S, "height"))
    L:Slider("Scale", 0.5, 2, 0.05, function() return S().scale end, function(v) S().scale = v end, "%.2f")
    L:Slider("Opacity", 0.1, 1, 0.05, function() return S().alpha end, function(v) S().alpha = v end, "%.2f")
    if ns.UNIT_BY_KEY[key].group then
        L:Slider("Padding (this orientation)", -10, 80, 1,
            function()
                local o = S().group
                return ns.Group.Growth(o).dx ~= 0 and (o.spacingH or 2) or o.spacing
            end, function(v)
                local o = S().group
                if ns.Group.Growth(o).dx ~= 0 then o.spacingH = v else o.spacing = v end
            end)
    end
    L:Header("Position")
    if not ns.UNIT_BY_KEY[key].group then
        L:Cycle("Anchored to", function()
            local l = { { value = "SCREEN", text = "Screen" } }
            for _, u in ipairs(ns.UNITS) do
                if u.key ~= key and U(u.key).anchorTo ~= key then l[#l + 1] = { value = u.key, text = u.title .. " frame" } end
            end
            return l
        end, function() return S().anchorTo or "SCREEN" end, function(v)
            local s = S()
            if v == s.anchorTo then return end
            s.anchorTo = v
            if v == "SCREEN" then
                -- stay where it is now, measured from the bottom left of the screen
                local f = ns.singles and ns.singles[key]
                local l, b = f and f:GetLeft(), f and f:GetBottom()
                s.point = (l and b) and { "BOTTOMLEFT", "BOTTOMLEFT", math.floor(l + 0.5), math.floor(b + 0.5) }
                    or { "CENTER", "CENTER", 0, 0 }
            else
                s.point = { "TOPLEFT", "BOTTOMLEFT", 0, -5 }
            end
            ns.RefreshConfig()
        end)
        local POINTS = {}
        for _, a in ipairs(ns.ANCHORS) do POINTS[#POINTS + 1] = { value = a, text = ns.ANCHOR_TEXT[a] } end
        L:Cycle("Point of this frame", POINTS, function() return S().point[1] end, function(v) S().point[1] = v end)
        L:Cycle("Point it attaches to", POINTS, function() return S().point[2] end, function(v) S().point[2] = v end)
    end
    L:Slider("Horizontal offset", -2000, 2000, 1, function() return S().point[3] end, function(v) S().point[3] = v end)
    L:Slider("Vertical offset", -1200, 1200, 1, function() return S().point[4] end, function(v) S().point[4] = v end)
    L:Button("Reset position", function()
        S().point = ns.CopyTable(ns.DEFAULTS.units[key].point)
        S().anchorTo = ns.DEFAULTS.units[key].anchorTo
        ns.Refresh(true)
        ns.RefreshConfig()
    end)
    L:Note(ns.UNIT_BY_KEY[key].group
        and "Or drag the group: Unlock frames (/huf unlock). The position is the first member's top left corner. Shown in a group, hidden alone and in a raid (raid frames come later); changes wait until combat ends."
        or "Or drag the frame: Unlock frames (bottom left, /huf unlock).")

    local R = UI.Column(f, COL2_X, 0, COL_W)
    if ns.UNIT_BY_KEY[key].group then
        local O = function() return U(key).group end
        R:Header("Group")
        local gp, sp = Opt(O, "showPlayer")
        R:Check("Show myself in the group", gp, sp)
        R:Cycle("Orientation", {
            { value = "DOWN", text = "Vertical - top to bottom" },
            { value = "UP", text = "Vertical - bottom to top" },
            { value = "RIGHT", text = "Horizontal - left to right" },
            { value = "LEFT", text = "Horizontal - right to left" },
        }, function() return select(2, ns.Group.Growth(O())) end, function(v) O().orientation = v if ns.RefreshConfig then ns.RefreshConfig() end end)
        R:Cycle("Sort members by", {
            { value = "NAME", text = "Name (alphabetical)" },
            { value = "INDEX", text = "Blizzard's party order" },
            { value = "CLASS", text = "Class" },
        }, Opt(O, "sort"))
        local gr, sr = Opt(O, "range")
        R:Check("Fade members out of range", gr, sr, "Members farther than about 40 yards get the opacity below (the game's range check; works while it is secret too).")
        R:Slider("Out of range opacity", 0.05, 1, 0.05, function() return O().rangeAlpha end,
            function(v) O().rangeAlpha = v end, "%.2f")
    end
    R:Header("Frame background")
    R:Cycle("Picture", BackgroundChoices, Opt(S, "frameBg"))
    R:Color("Colour", Opt(S, "frameBgColor"))
    R:Slider("Opacity", 0, 1, 0.05, function() return S().frameBgAlpha end, function(v) S().frameBgAlpha = v end, "%.2f")
    R:Slider("Reaches past the frame", 0, 12, 1, Opt(S, "framePad"))
    R:Header("Portrait")
    R:Check("Show a portrait", Opt(P, "enabled"))
    R:Cycle("Kind", {
        { value = "3D", text = "3D model" },
        { value = "2D", text = "Picture" },
        { value = "CLASS", text = "Class icon" },
    }, Opt(P, "mode"))
    R:Cycle("Side", { { value = "LEFT", text = "Left" }, { value = "RIGHT", text = "Right" } }, Opt(P, "side"))
    R:Slider("Border", 0, 3, 0.5, function() return P().borderSize end, function(v) P().borderSize = v end, "%.1f")
    local gt, st = Opt(S, "tooltip")
    R:Check("Unit tooltip on mouseover", gt, st)
end

-- Health bar / Power bar
local function BarPage(f, key, which)
    local B = function() return U(key)[which] end
    local L = UI.Column(f, 0, 0, COL_W)
    L:Header(which == "power" and "Power bar (mana, energy, rage)" or "Health bar")
    if which == "power" then
        L:Check("Show the power bar", Opt(B, "enabled"))
        L:Slider("Height", 2, 30, 1, Opt(B, "size"))
        L:Slider("Gap to the health bar", 0, 10, 1, Opt(B, "gap"))
        local gd, sd = Opt(B, "divider")
        L:Check("Line between health and power", gd, sd, "With no gap: a border line between the two bars. Off: one border around both, as EllesmereUI draws it.")
    end
    L:Cycle("Bar texture", TextureChoices, Opt(B, "texture"))
    L:Check("Fill from the right", Opt(B, "reverse"))
    L:Header("Colour")
    L:Cycle("Colour by", {
        { value = "STATIC", text = "Static colour" },
        { value = "GRADIENT", text = "Gradient (2 colours)" },
        { value = "CLASS", text = "Class colour" },
        { value = "STATUS", text = "Status (>75% / >40% / below)" },
        { value = "TYPE", text = "Type (health green, mana blue ...)" },
    }, Opt(B, "colorMode"))
    L:Color("Static colour", Opt(B, "color"))
    L:Color("Gradient: left", Opt(B, "gradStart"))
    L:Check("Left: accent colour", Opt(B, "gradStartAccent"))
    L:Color("Gradient: right", Opt(B, "gradEnd"))
    L:Check("Right: accent colour", Opt(B, "gradEndAccent"))
    if which == "health" then
        local HP = function() return U(key).healPred end
        L:Header("Incoming heals")
        local ge, se = Opt(HP, "enabled")
        L:Check("Show incoming heals", ge, se, "Heals on their way to this unit (yours and others'), as a semi-transparent bar after the filled part.")
        L:Color("Colour", Opt(HP, "color"))
        L:Slider("Opacity", 0.1, 1, 0.05, function() return HP().alpha end, function(v) HP().alpha = v end, "%.2f")
        L:Slider("Past the bar's end (overheal)", 0, 100, 5, function() return HP().overheal end,
            function(v) HP().overheal = v end, "%d%%")
    end

    local R = UI.Column(f, COL2_X, 0, COL_W)
    R:Header("Status colours")
    R:Color("Above 75%", Opt(B, "high"))
    R:Color("Above 40%", Opt(B, "mid"))
    R:Color("40% and below", Opt(B, "low"))
    local gn, sn = Opt(B, "npcReaction")
    R:Check("NPCs in reaction colours (class)", gn, sn, "With \"Class colour\": hostile red, neutral yellow, friendly green. Off: NPCs use the static colour.")
    if which == "health" then R:Check("Grey when dead, offline or tapped", Opt(B, "deadGray")) end
    R:Header("Background (empty part)")
    R:Cycle("Picture", BackgroundChoices, Opt(B, "bgTexture"))
    R:Color("Colour", Opt(B, "bgColor"))
    R:Slider("Opacity", 0, 1, 0.05, function() return B().bgAlpha end, function(v) B().bgAlpha = v end, "%.2f")
    R:Header("Border")
    R:Slider("Size", 0, 3, 0.5, function() return B().borderSize end, function(v) B().borderSize = v end, "%.1f")
    R:Color("Colour", Opt(B, "borderColor"))
end

-- Texts: 9 anchors per bar
local SHORT = { TOPLEFT = "TL", TOP = "T", TOPRIGHT = "TR", LEFT = "L", CENTER = "C", RIGHT = "R",
    BOTTOMLEFT = "BL", BOTTOM = "B", BOTTOMRIGHT = "BR" }

-- getTexts (optional): the texts table to edit (raid frames: groups / main tanks / pets)
local function TextsPage(f, key, page, getTexts)
    local Tx = getTexts or function() return U(key).texts end
    local bar, anchor = "health", nil
    -- default selection: the first anchor with text on the health bar
    for _, a in ipairs(ns.ANCHORS) do
        if not anchor and Tx().health[a].text ~= "" then anchor = a end
    end
    anchor = anchor or "CENTER"
    local T = function() return Tx()[bar][anchor] end

    local L = UI.Column(f, 0, 0, COL_W)
    L:Cycle("Bar", {
        { value = "health", text = "Health bar" },
        { value = "power", text = "Power bar" },
    }, function() return bar end, function(v) bar = v end)
    L:Header("Anchor")

    -- 3 x 3 grid: the bar's anchors; lit = has text, outlined = selected
    local grid = CreateFrame("Frame", nil, f)
    grid:SetSize(COL_W, 72)
    UI.Fill(grid, 0.08, 0.08, 0.09, 0.9)
    UI.Border(grid, 0.22, 0.22, 0.24, 1)
    local cells = {}
    local CW, CH = (COL_W - 16) / 3, 20
    for i, a in ipairs(ns.ANCHORS) do
        local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
        local b = CreateFrame("Button", nil, grid)
        b:SetSize(CW - 4, CH)
        b:SetPoint("TOPLEFT", 8 + col * CW, -6 - row * (CH + 2))
        b.fill = UI.Fill(b, 1, 1, 1, 0.04)
        b.sel = UI.Border(b, A[1], A[2], A[3], 1)
        b.label = UI.Label(b, ns.ANCHOR_TEXT[a])
        b.label:SetPoint("CENTER")
        b:SetScript("OnClick", function()
            anchor = a
            ns.Log("config", "text anchor %s %s", bar, a)
            ns.RefreshConfig()
        end)
        UI.Tooltip(b, ns.ANCHOR_TEXT[a], "Click to edit the text at this anchor.")
        cells[a] = b
    end
    L:Add(grid, 80)
    table.insert(page.widgets, { Refresh = function()
        for a, b in pairs(cells) do
            local used = Tx()[bar][a].text ~= ""
            b.fill:SetColorTexture(A[1], A[2], A[3], used and 0.35 or 0.04)
            if b.sel.SetShown then b.sel:SetShown(a == anchor) end
            if used then b.label:SetTextColor(1, 1, 1) else b.label:SetTextColor(0.5, 0.5, 0.5) end
        end
    end })

    local head = L:Header("Text")
    local box = UI.EditBox(f, COL_W, "empty: no text here")
    box:SetScript("OnTextChanged", function(self, user)
        if self.UpdatePlaceholder then self:UpdatePlaceholder() end
        if user then
            T().text = self:GetText()
            ns.Refresh()
        end
    end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    L:Add(box, UI.ROW + 4)
    table.insert(page.widgets, { Refresh = function()
        if not box:HasFocus() then box:SetText(T().text or "") end
        box:UpdatePlaceholder()
        if head and head.SetText then head:SetText(("Text: %s, %s"):format(bar == "health" and "health bar" or "power bar", ns.ANCHOR_TEXT[anchor]:lower())) end
    end })
    L:Cycle("Insert value", ns.TAGS, function() return nil end, function(v)
        local t = T().text or ""
        if t ~= "" and not t:find("%s$") then t = t .. " " end
        T().text = t .. v
    end)
    L:Button("Clear this text", function() T().text = "" ns.Refresh() ns.RefreshConfig() end)
    L:Note("Values in [ ] are filled in, everything else shows as typed. Example: [levelclass:color] | [name] shows \"55E | Northshire Guard\".")

    local R = UI.Column(f, COL2_X, 0, COL_W)
    R:Header("Look")
    R:Cycle("Font", function() return FontChoices(true) end, Opt(T, "font"))
    R:Slider("Size", 6, 40, 1, Opt(T, "size"))
    R:Cycle("Outline", OUTLINES_G, Opt(T, "outline"))
    R:Cycle("Colour", {
        { value = "WHITE", text = "White" },
        { value = "CLASS", text = "Class / reaction" },
        { value = "ACCENT", text = "Accent colour" },
        { value = "CUSTOM", text = "Custom" },
        { value = "STATUS", text = "Health status (>75% / >40% / below)" },
    }, Opt(T, "colorMode"))
    R:Color("Custom colour", Opt(T, "color"))
    local gf, sf = Opt(T, "hideFull")
    R:Check("Status: hide at full health", gf, sf, "With \"Health status\": the text is invisible while the unit has full health (e.g. missing health would show 0). The status colours are the health bar's.")
    R:Header("Offset")
    R:Slider("Horizontal (X)", -150, 150, 1, Opt(T, "x"))
    R:Slider("Vertical (Y)", -80, 80, 1, Opt(T, "y"))
end
ns.TextsPage = TextsPage

-- Debuffs / Buffs: one tab each. Left: what shows and how it looks;
-- right: where it goes.
local AURA_POSITIONS = {
    { value = "BELOW_LEFT", text = "Below, from the left" },
    { value = "BELOW_CENTER", text = "Below, centred" },
    { value = "BELOW_RIGHT", text = "Below, from the right" },
    { value = "ABOVE_LEFT", text = "Above, from the left" },
    { value = "ABOVE_CENTER", text = "Above, centred" },
    { value = "ABOVE_RIGHT", text = "Above, from the right" },
    { value = "LEFT", text = "Left of the frame" },
    { value = "RIGHT", text = "Right of the frame" },
    { value = "INSIDE_TOPLEFT", text = "Inside, top left" },
    { value = "INSIDE_TOP", text = "Inside, top centre" },
    { value = "INSIDE_TOPRIGHT", text = "Inside, top right" },
    { value = "INSIDE_LEFT", text = "Inside, left" },
    { value = "INSIDE_CENTER", text = "Inside, centre" },
    { value = "INSIDE_RIGHT", text = "Inside, right" },
    { value = "INSIDE_BOTTOMLEFT", text = "Inside, bottom left" },
    { value = "INSIDE_BOTTOM", text = "Inside, bottom centre" },
    { value = "INSIDE_BOTTOMRIGHT", text = "Inside, bottom right" },
}
local AURA_GROW = {
    { value = "AUTO", text = "Away from the position" },
    { value = "RIGHT", text = "To the right" },
    { value = "LEFT", text = "To the left" },
}
local DEBUFF_FILTERS = {
    { value = "ALL", text = "All debuffs" },
    { value = "RAID", text = "Important (Blizzard's raid frames)" },
    { value = "DISPELLABLE", text = "Only ones I can dispel" },
    { value = "TEAM", text = "Ones my group can dispel" },
    { value = "AUTO_TEAM", text = "My group (MMT team) or me" },
    { value = "CC", text = "Only crowd control" },
}
local BUFF_FILTERS = {
    { value = "ALL", text = "All buffs" },
    { value = "RAID", text = "Important (Blizzard's raid frames)" },
    { value = "DEFENSIVE", text = "Only defensives and externals" },
    { value = "CANCELABLE", text = "Only ones that can be cancelled" },
    { value = "PURGE", text = "Only ones that can be dispelled or stolen" },
    { value = "TEAM_PURGE", text = "Ones my group can purge or steal" },
    { value = "AUTO_PURGE", text = "Purgeable: my group (MMT team) or me" },
    { value = "IMPORTANT_PURGE", text = "Important ones and dispellable ones" },
}
local BUFF_MARKS = {
    { value = "OFF", text = "No" },
    { value = "EDGE", text = "Edge in the type's colour" },
    { value = "GLOW", text = "Golden glow, like a spell that lights up" },
}
local function AuraPage(f, key, which)
    local T = function() return U(key)[which] end
    local debuffs = which == "debuffs"
    local L = UI.Column(f, 0, 0, COL_W)
    L:Header(debuffs and "Which debuffs" or "Which buffs")
    L:Check("Show " .. which, Opt(T, "enabled"))
    local gm, sm = Opt(T, "mine")
    L:Check("Only mine", gm, sm, debuffs and "Only the debuffs you cast." or "Only the buffs you cast.")
    L:Cycle("Filter", debuffs and DEBUFF_FILTERS or BUFF_FILTERS, Opt(T, "filter"))
    if debuffs then
        L:Note("\"Ones my group can dispel\": every debuff someone in your group (with MMT: your team) can remove, from their class and healer role.")
    else
        L:Note("For enemies. \"Ones my group can purge or steal\": a shaman from 12 (Purge), a priest from 18 (Dispel Magic), a warlock with a Felhunter, a hunter from 60 (enrages), a mage from 70 (Spellsteal); you by your spellbook.")
    end
    if debuffs then
        local gc, sc = Opt(T, "ccFirst")
        L:Check("Crowd control first", gc, sc, "Stuns, fears and the like lead the row.")
        local gs, ss = Opt(T, "hideSated")
        L:Check("Hide Sated and Exhaustion", gs, ss, "The debuffs Bloodlust and Heroism leave behind.")
        L:Header("Edge round the frame")
        L:Cycle("When the unit has a debuff", {
            { value = "OFF", text = "No edge" },
            { value = "AUTO", text = "My group (MMT team) or me" },
            { value = "MINE", text = "That I can dispel" },
            { value = "TEAM", text = "That my group can dispel" },
        }, Opt(T, "debuffEdge"))
        L:Slider("Edge size", 1, 6, 1, Opt(T, "dispelEdgeSize"))
        L:Note("In the debuff type's colour: magic blue, curse purple, disease brown, poison green. The game colours it, so it works in every fight.")
    end
    L:Header("Look")
    L:Slider("Icon size", 8, 40, 1, Opt(T, "size"))
    L:Slider("Edge around the icon", 0, 4, 1, Opt(T, "borderSize"))
    if debuffs then
        local gd, sd = Opt(T, "dispelBorder")
        L:Check("Edge in the debuff type's colour", gd, sd, "Magic blue, curse purple, disease brown, poison green, bleed red. Needs an edge of 1 or more.")
        local gg, sg = Opt(T, "glow")
        L:Check("Golden glow on dispellable debuffs", gg, sg, "With the filters \"Ones I can dispel\", \"Ones my group can dispel\" or \"My group (MMT team) or me\": every debuff shown can be removed and glows like a spell that lights up. The type's edge stays when it is on.")
    else
        L:Cycle("Mark buffs by type", BUFF_MARKS, Opt(T, "mark"))
        L:Slider("Glow size (% of the icon)", 100, 250, 5, Opt(T, "glowSize"))
        L:Slider("Removable buffs' size (%)", 100, 200, 5, Opt(T, "purgeSize"))
        L:Note("With the three purge filters: the buffs that can be removed get the mark (the golden glow on every one) and this size.")
    end
    L:Slider("Stack number size", 6, 16, 1, Opt(T, "countSize"))
    local gt, st = Opt(T, "timer")
    L:Check("Time left as a dark sweep", gt, st)
    local gx, sx = Opt(T, "timerText")
    L:Check("Time left as numbers", gx, sx)
    L:Slider("Time size (0: automatic)", 0, 20, 1, Opt(T, "timerSize"))

    local R = UI.Column(f, COL2_X, 0, COL_W)
    R:Header("Place")
    R:Cycle("Position", AURA_POSITIONS, Opt(T, "position"))
    R:Cycle("Growth", AURA_GROW, Opt(T, "grow"))
    R:Slider("Icons per row", 1, 12, 1, Opt(T, "perRow"))
    R:Slider("Rows", 1, 6, 1, Opt(T, "rows"))
    R:Slider("Space between icons", 0, 8, 1, Opt(T, "gap"))
    R:Slider("Distance to the frame's edge", 0, 20, 1, Opt(T, "offset"))
    R:Slider("Horizontal offset", -200, 200, 1, Opt(T, "x"))
    R:Slider("Vertical offset", -200, 200, 1, Opt(T, "y"))
    R:Note("Unlock frames to see where the icons go. They fill a row, then start the next one.")
    if key == "player" and not debuffs then
        local S = function() return U(key) end
        R:Header("Blizzard")
        local L2 = R
        local gb = function() return S().hideBlizzardAuras end
        L2:Check("Hide Blizzard's buff and debuff icons", gb, function(v)
            S().hideBlizzardAuras = v
            if v then
                if ns.Units then ns.Units.HideBlizzardAuras() end
            else
                ns.AskReload("Blizzard's buff and debuff icons come back after a reload.")
            end
        end, "The icons at the top right of the screen. HUF's own icons on the player frame replace them.")
    end
end

-- Cast bar: on the line between health and power bar
local function CastPage(f, key)
    local C = function() return U(key).castBar end
    local L = UI.Column(f, 0, 0, COL_W)
    L:Header("Cast bar")
    L:Check("Show the cast bar", Opt(C, "enabled"))
    L:Slider("Height", 1, 20, 1, Opt(C, "height"))
    L:Slider("Horizontal offset", -100, 100, 1, Opt(C, "x"))
    L:Slider("Vertical offset", -40, 40, 1, Opt(C, "y"))
    L:Cycle("Bar texture", TextureChoices, Opt(C, "texture"))
    L:Color("Colour", Opt(C, "color"))
    L:Slider("Background opacity", 0, 1, 0.05, function() return C().bgAlpha end, function(v) C().bgAlpha = v end, "%.2f")
    L:Slider("Border", 0, 3, 0.5, function() return C().borderSize end, function(v) C().borderSize = v end, "%.1f")
    L:Note("Sits on the line between the health and the power bar (the bottom of the health bar).")

    local R = UI.Column(f, COL2_X, 0, COL_W)
    R:Header("Spell icon")
    R:Check("Show the spell icon", Opt(C, "icon"))
    R:Slider("Icon size", 4, 40, 1, Opt(C, "iconSize"))
    R:Header("Spell name")
    R:Check("Show the spell name", Opt(C, "text"))
    R:Cycle("Font", function() return FontChoices(true) end, Opt(C, "font"))
    R:Slider("Size", 6, 20, 1, Opt(C, "fontSize"))
    R:Cycle("Outline", OUTLINES_G, Opt(C, "outline"))
    R:Cycle("Aligned", {
        { value = "LEFT", text = "Left" }, { value = "CENTER", text = "Center" }, { value = "RIGHT", text = "Right" },
    }, Opt(C, "textAlign"))
    R:Header("Interrupts")
    local gi, si = Opt(C, "interrupt")
    R:Check("Show interrupts", gi, si, "The bar turns red for a moment when someone interrupts the cast (with the spell name on: \"Interrupted!\").")
    R:Color("Colour", Opt(C, "interruptColor"))
end

-- Pet happiness (hunter pets)
local function HappinessPage(f, key)
    local C = function() return U(key).happiness end
    local L = UI.Column(f, 0, 0, COL_W)
    L:Header("Happiness")
    local ge, se = Opt(C, "enabled")
    L:Check("Show the pet's happiness", ge, se, "Hunter pets: happy, content or unhappy, on the right side of the health bar.")
    L:Cycle("Shown as", { { value = "ICON", text = "Icon (the game's faces)" }, { value = "TEXT", text = "Text (Happy / Content / Unhappy)" } },
        Opt(C, "mode"))
    L:Slider("Size", 6, 32, 1, Opt(C, "size"))
    L:Slider("Horizontal offset", -100, 100, 1, Opt(C, "x"))
    L:Slider("Vertical offset", -40, 40, 1, Opt(C, "y"))
end

-- Combo points (target frame)
local function ComboPage(f, key)
    local C = function() return U(key).combo end
    local L = UI.Column(f, 0, 0, COL_W)
    L:Header("Combo points")
    local ge, se = Opt(C, "enabled")
    L:Check("Show combo points", ge, se, "Rogues, and druids in cat form: a row of points at the target frame.")
    local gh, sh = Opt(C, "hideEmpty")
    L:Check("Hide with no points", gh, sh, "Only where the game lets addons read the number. Where it can't: after a target change the points stay hidden until you gain one.")
    L:Cycle("Position", ns.Combo.POSITIONS, Opt(C, "pos"))
    L:Slider("Horizontal offset", -200, 200, 1, Opt(C, "x"))
    L:Slider("Vertical offset", -100, 100, 1, Opt(C, "y"))
    local R = UI.Column(f, COL2_X, 0, COL_W)
    R:Header("Look")
    R:Slider("Width (0: the frame's width)", 0, 400, 1, Opt(C, "width"))
    R:Slider("Height", 2, 20, 1, Opt(C, "height"))
    R:Slider("Space between points", 0, 10, 1, Opt(C, "gap"))
    R:Color("Colour", Opt(C, "color"))
    R:Slider("Background opacity", 0, 1, 0.05, function() return C().bgAlpha end, function(v) C().bgAlpha = v end, "%.2f")
    R:Note("The nameplate's combo points: Nameplates > Combo points.")
end

local function UnitPage(key)
    return function(page)
        local info = ns.UNIT_BY_KEY[key]
        local on = UI.Check(page, 220, info.group and "Show the group frames" or ("Show the " .. info.title:lower() .. " frame"),
            function() return U(key).enabled end,
            function(v)
                U(key).enabled = v
                if v and ns.Units then ns.Units.HideBlizzard() end
                if not v and ns.db.global.hideBlizzard then ns.AskReload("Blizzard's frame comes back after a reload.") end
            end)
        on:SetPoint("TOPLEFT", 0, 4)
        local copy = UI.Dropdown(page, 200, "Copy look from", function()
            local l = {}
            for _, u in ipairs(ns.FRAME_KEYS) do
                if u.key ~= key then l[#l + 1] = { value = u.key, text = u.title } end
            end
            return l
        end, function() return nil end, function(v)
            UI.Confirm(("Copy the look of the %s frame to the %s frame? Position, texts and on/off stay."):format(
                ns.UNIT_BY_KEY[v].title, info.title), "Copy", function() ns.CopyUnitSettings(v, key) end)
        end)
        copy:SetPoint("TOPLEFT", 280, 4)
        local reset = UI.Button(page, 100, "Reset frame", function()
            UI.Confirm(("Reset every setting of the %s frame (not its position)?"):format(info.title), "Reset",
                function() ns.ResetUnit(key) end)
        end)
        reset:SetPoint("TOPRIGHT", 0, 4)

        local tabs = {
            { "frame", "Frame" }, { "health", "Health bar" }, { "power", "Power bar" }, { "texts", "Texts" },
        }
        if not info.noAuras then
            tabs[#tabs + 1] = { "debuffs", "Debuffs" }
            tabs[#tabs + 1] = { "buffs", "Buffs" }
        end
        if not info.polled then tabs[#tabs + 1] = { "cast", "Cast bar" } end
        if key == "target" then tabs[#tabs + 1] = { "combo", "Combo points" } end
        if key == "pet" then tabs[#tabs + 1] = { "happy", "Happiness" } end
        local subs = {}
        local strip
        local function Show(k)
            for name, sf in pairs(subs) do sf:SetShown(name == k) end
            strip:Select(k)
        end
        strip = UI.SubTabs(page, tabs, function(k) Show(k) end)
        strip:SetPoint("TOPLEFT", 0, -22)
        strip:SetPoint("TOPRIGHT", 0, -22)
        subs.frame = SubFrame(page); FramePage(subs.frame, key)
        subs.health = SubFrame(page); BarPage(subs.health, key, "health")
        subs.power = SubFrame(page); BarPage(subs.power, key, "power")
        subs.texts = SubFrame(page); TextsPage(subs.texts, key, page)
        if not info.noAuras then
            subs.debuffs = SubFrame(page); AuraPage(subs.debuffs, key, "debuffs")
            subs.buffs = SubFrame(page); AuraPage(subs.buffs, key, "buffs")
        end
        if not info.polled then subs.cast = SubFrame(page); CastPage(subs.cast, key) end
        if key == "target" then subs.combo = SubFrame(page); ComboPage(subs.combo, key) end
        if key == "pet" then subs.happy = SubFrame(page); HappinessPage(subs.happy, key) end
        strip:Bind(subs, Show)
        Show("frame")
    end
end

for _, info in ipairs(ns.FRAME_KEYS) do
    ns.RegisterPage(info.key, info.title, "frames", UnitPage(info.key),
        function() return ns.db.units[info.key].enabled end)
end
