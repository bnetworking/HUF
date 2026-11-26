-- HUF: settings page for the chat window (GENERAL > Utility Frames > Chat).
-- Tabs: Look, Lines (short channel names, links, history), Buttons, Game
-- settings (the game's own chat options and colours, saved by the game).

local _, ns = ...
local UI = ns.UI
local COL_W, COL2_X, TOP = 330, 366, -36

local function C() return ns.db.chat end
local function Opt(tbl, k) return function() return tbl()[k] end, function(v) tbl()[k] = v end end

local function Fonts()
    local l = { { value = "GLOBAL", text = "HUF Global Font" } }
    for _, f in ipairs(ns.fonts) do l[#l + 1] = { value = f.name, text = f.name } end
    return l
end
local OUTLINES = {
    { value = "GLOBAL", text = "HUF Global Outline" }, { value = "NONE", text = "None" },
    { value = "OUTLINE", text = "Thin" }, { value = "THICKOUTLINE", text = "Thick" },
}

local function SubFrame(page)
    local f = CreateFrame("Frame", nil, page)
    f:SetPoint("TOPLEFT", 0, TOP - 16)
    f:SetSize(ns.PAGE_W, ns.PAGE_H + TOP - 16)
    return f
end

local function LookPage(f)
    local L = UI.Column(f, 0, 0, COL_W)
    L:Header("Text")
    L:Cycle("Font", Fonts, Opt(C, "font"))
    L:Slider("Size", 8, 24, 1, Opt(C, "fontSize"))
    L:Cycle("Outline", OUTLINES, Opt(C, "outline"))
    L:Header("Look")
    L:Cycle("Style", {
        { value = "GAME", text = "The game's window and tabs" },
        { value = "PANEL", text = "A panel, like EllesmereUI" },
    }, function() return C().look end, function(v)
        C().look = v
        if v ~= "PANEL" and ns.Chat and ns.Chat.WasPanel and ns.Chat.WasPanel() then
            ns.AskReload("The game's chat background and scroll bar come back after a reload.")
        end
    end)
    L:Note("Panel: its settings are on the Panel tab.")
    local R = UI.Column(f, COL2_X, 0, COL_W)
    R:Header("Input line")
    R:Cycle("Where", {
        { value = "BELOW", text = "Below the chat" },
        { value = "ABOVE", text = "Above the chat (over the tabs)" },
        { value = "INSIDE_TOP", text = "Inside the chat, at the top" },
        { value = "INSIDE_BOTTOM", text = "Inside the chat, at the bottom" },
    }, Opt(C, "inputPos"))
    R:Slider("Distance", -20, 40, 1, Opt(C, "inputOffset"))
    R:Header("Place")
    R:Button("Keep the chat where it is now", function() if ns.Chat then ns.Chat.KeepPosition() end end)
    R:Button("Back to the game's place", function() if ns.Chat then ns.Chat.GamePosition() end end)
    R:Note("Move the chat with the game's Edit Mode (or the chat tab's lock off), then keep it here: HUF puts it back there, also when Edit Mode moves it. The Ellesmere import brings Ellesmere's place.")
    R:Header("Window background")
    R:Color("Colour", Opt(C, "bgColor"))
    R:Slider("Opacity", 0, 1, 0.05, function() return C().bgAlpha end, function(v) C().bgAlpha = v end, "%.2f")
    R:Note("Every chat window. The game keeps background colour and opacity with each window.")
end

-- one short name: label on the left, a small text box on the right
local abbrRows = {}
local function AbbrRow(col, label, key)
    local row = CreateFrame("Frame", nil, col.parent)
    row:SetSize(col.width, UI.ROW)
    local fs = UI.Label(row, label)
    fs:SetPoint("LEFT", 4, 0)
    local e = UI.EditBox(row, 70, "", function(text, box)
        ns.db.chat.abbr[key] = text
        box:ClearFocus()
        ns.Log("config", "chat short %s = %s", key, text)
    end)
    e:SetPoint("RIGHT", 0, 0)
    e:SetScript("OnEditFocusLost", function(self)
        ns.db.chat.abbr[key] = self:GetText()
        self.UpdatePlaceholder()
    end)
    row.Refresh = function() e:SetText(ns.db.chat.abbr[key] or "") e.UpdatePlaceholder() end
    row.Refresh()
    abbrRows[#abbrRows + 1] = row
    col:Add(row, UI.ROW + 2)
    return row
end

local SHORT = {
    { "CHANNEL", "Numbered channels (%d = number)" }, { "SAY", "Say" }, { "YELL", "Yell" },
    { "PARTY", "Party" }, { "PARTY_LEADER", "Party leader" }, { "GUILD", "Guild" }, { "OFFICER", "Guild officer" },
    { "RAID", "Raid" }, { "RAID_LEADER", "Raid leader" }, { "RAID_WARNING", "Raid warning" },
    { "WHISPER", "Whisper" }, { "INSTANCE_CHAT", "Instance" }, { "INSTANCE_CHAT_LEADER", "Instance leader" },
}

local function LinesPage(f, page)
    local L = UI.Column(f, 0, 0, COL_W)
    L:Header("Short channel names")
    local ga, sa = Opt(C, "abbreviate")
    L:Check("Shorten channel names", ga, sa, "\"[1. General]\" becomes \"[1]\", \"[Party]\" \"[P]\", \"Name says:\" \"[S] Name:\". Not in instance chat lockdown (the game hides those lines from addons).")
    for i = 1, 7 do AbbrRow(L, SHORT[i][2], SHORT[i][1]) end
    local R = UI.Column(f, COL2_X, 0, COL_W)
    R:Space(24)
    for i = 8, #SHORT do AbbrRow(R, SHORT[i][2], SHORT[i][1]) end
    R:Header("Names and links")
    local gc, sc = Opt(C, "classColors")
    R:Check("Names in class colours", gc, function(v)
        sc(v)
        if ns.Chat then ns.Chat.ApplyClassColors(v) end
    end, "The game's own setting for every chat type.")
    local gu, su = Opt(C, "urls")
    R:Check("Web addresses as links", gu, su, "Click one: a box to copy it.")
    local gt, st = Opt(C, "linkTooltips")
    R:Check("Tooltips over item, spell, quest links", gt, st)
    R:Header("History")
    local gh, sh = Opt(C, "history")
    R:Check("Keep chat over reload and logout", gh, sh, "Per character and window; the last lines come back after /reload or the next login.")
    R:Slider("Lines kept", 100, 2000, 100, Opt(C, "historyLines"))
    f:HookScript("OnShow", function() for _, r in ipairs(abbrRows) do r.Refresh() end end)
    R:Button("Clear the kept chat", function()
        UI.Confirm("Clear this character's kept chat?", "Clear", function() if ns.Chat then ns.Chat.ClearHistory() end end)
    end)
end

local function A01(k) return function() return C()[k] end, function(v) C()[k] = v end end
local function PanelPage(f)
    local L = UI.Column(f, 0, 0, COL_W)
    L:Header("Panel")
    L:Note("For the style \"A panel, like EllesmereUI\" (Look tab). Colour and opacity: Look > Window background.")
    L:Color("Edge colour", Opt(C, "panelBorderColor"))
    local ge, se = A01("panelBorderAlpha")
    L:Slider("Edge opacity (0: none)", 0, 1, 0.05, ge, se, "%.2f")
    L:Slider("Edge size", 1, 4, 1, Opt(C, "panelBorderSize"))
    L:Slider("Room left and right of the chat", 0, 30, 1, Opt(C, "panelPadX"))
    L:Slider("Room below the chat", 0, 60, 1, Opt(C, "panelPadBottom"))
    L:Header("Tabs")
    L:Slider("Text size", 8, 18, 1, Opt(C, "tabFontSize"))
    L:Color("Text colour", Opt(C, "tabTextColor"))
    local gt, st = A01("tabTextAlpha")
    L:Slider("Inactive tabs' text opacity", 0.2, 1, 0.05, gt, st, "%.2f")
    L:Slider("Height", 14, 32, 1, Opt(C, "tabHeight"))
    L:Color("Background colour", Opt(C, "tabBg"))
    local gb, sb = A01("tabBgAlpha")
    L:Slider("Inactive tabs' background", 0, 1, 0.05, gb, sb, "%.2f")
    local gba, sba = A01("tabBgActiveAlpha")
    L:Slider("Active tab's background", 0, 1, 0.05, gba, sba, "%.2f")
    local gae, sae = Opt(C, "tabActiveEdge")
    L:Check("Edge round the active tab", gae, sae)
    local R = UI.Column(f, COL2_X, 0, COL_W)
    -- the active tab's line on the right (the left column ran past the page in Utility Frames)
    R:Header("Active tab's line")
    local gu, su = Opt(C, "tabUnderline")
    R:Check("Line under the active tab", gu, su)
    local ga, sa = Opt(C, "tabUnderlineAccent")
    R:Check("Line in the accent colour", ga, sa)
    R:Color("Line colour (accent off)", Opt(C, "tabUnderlineColor"))
    R:Header("Button strip")
    local gj, sj = Opt(C, "stripJoined")
    R:Check("Joined to the panel", gj, sj, "Off: a gap between the strip and the panel.")
    R:Slider("Gap (when apart)", 0, 30, 1, Opt(C, "stripGap"))
    local gsb, ssb = Opt(C, "stripBg")
    R:Check("Background behind the buttons", gsb, ssb)
    R:Color("Icon colour", Opt(C, "iconColor"))
    local gia, sia = Opt(C, "iconAccent")
    R:Check("Icons in the accent colour", gia, sia)
    R:Slider("Icon size", 14, 32, 1, Opt(C, "iconSize"))
    R:Slider("Strip width (0: from the icons)", 0, 100, 1, Opt(C, "stripWidth"))
    R:Slider("Space between icons", 0, 16, 1, Opt(C, "iconGap"))
    R:Note("Which buttons and the side: Buttons tab.")
    R:Header("Fading")
    local gw, sw = Opt(C, "fadeWhole")
    R:Check("Fade the whole chat", gw, sw, "The panel, tabs and text fade too, not only the buttons (when fading is on, Buttons tab). Awake again while the mouse is over the chat, while you type, and when someone writes.")
end

local function ButtonsPage(f)
    local B = function() return ns.db.chat.buttons end
    local L = UI.Column(f, 0, 0, COL_W)
    L:Header("Buttons beside the chat")
    local g1, s1 = Opt(B, "copy")
    L:Check("Copy chat", g1, s1, "A window with the chat text to copy.")
    local g2, s2 = Opt(B, "guild")
    L:Check("Guild (members online)", g2, s2, "Shown only in a guild. Hover: who is online.")
    local g3, s3 = Opt(B, "social")
    L:Check("Friends", g3, s3)
    local g4, s4 = Opt(B, "channels")
    L:Check("Chat channels (the game's button)", g4, s4, "The game's chat channel / voice chat button, moved beside the chat.")
    local g5, s5 = Opt(B, "chatmenu")
    L:Check("Chat menu (the game's button)", g5, s5, "Language, emotes and the chat type to write in, moved beside the chat.")
    local gvm, svm = Opt(B, "voicemute")
    L:Check("Voice chat: mute (the game's button)", gvm, svm, "The game's microphone mute button, moved beside the chat with its own icon (crossed out while muted). Only there while you are in voice chat.")
    local gvd, svd = Opt(B, "voicedeafen")
    L:Check("Voice chat: deafen (the game's button)", gvd, svd, "The game's deafen button (you hear nobody), moved beside the chat with its own icon. Only there while you are in voice chat.")
    local g7, s7 = Opt(B, "bottom")
    L:Check("To the newest line", g7, s7, "Scrolls the chat down to the newest line. With the panel look: at the bottom of the strip.")
    local g8, s8 = Opt(B, "settings")
    L:Check("HUF settings", g8, s8, "Opens HUF's settings on the Chat page.")
    local g6, s6 = Opt(C, "hideStock")
    L:Check("Hide the game's button column", g6, function(v)
        s6(v)
        if not v then ns.AskReload("The game's chat column and Social button come back after a reload.") end
    end, "The empty dark column at the left of the chat windows and the game's Social (quick join) button.")
    L:Header("Fading")
    local gf, sf = Opt(C, "fade")
    L:Check("Fade the buttons", gf, sf, "Full again while the mouse is over the chat or the buttons.")
    L:Slider("Fade to", 0, 1, 0.05, function() return C().fadeAlpha end, function(v) C().fadeAlpha = v end, "%.2f")
    L:Slider("After", 1, 30, 1, function() return C().fadeDelay end, function(v) C().fadeDelay = v end, "%d s")
    local R = UI.Column(f, COL2_X, 0, COL_W)
    R:Header("Place")
    R:Cycle("Side", { { value = "RIGHT", text = "Right of the chat" }, { value = "LEFT", text = "Left of the chat" } },
        Opt(C, "buttonSide"))
    R:Slider("Horizontal offset", -100, 100, 1, Opt(C, "buttonX"))
    R:Slider("Vertical offset", -200, 200, 1, Opt(C, "buttonY"))
end

---------------------------------------------------------------------------
-- The game's own chat settings
---------------------------------------------------------------------------
local function CVarExists(name)
    if C_CVar and C_CVar.GetCVar then return C_CVar.GetCVar(name) ~= nil end
    return GetCVar and GetCVar(name) ~= nil
end
local function GetCV(name) return (C_CVar and C_CVar.GetCVar or GetCVar)(name) end
local function SetCV(name, v)
    local ok = pcall(C_CVar and C_CVar.SetCVar or SetCVar, name, v)
    if ok then ns.Log("config", "CVar %s = %s", name, tostring(v)) end
end
local function CVarBool(name)
    return function() return GetCV(name) == "1" end, function(v) SetCV(name, v and "1" or "0") end
end
local function CVarValue(name)
    return function() return GetCV(name) end, function(v) SetCV(name, v) end
end

local COLOR_TYPES = {
    { "SAY", "Say" }, { "YELL", "Yell" }, { "EMOTE", "Emote" }, { "PARTY", "Party" }, { "PARTY_LEADER", "Party leader" },
    { "RAID", "Raid" }, { "RAID_WARNING", "Raid warning" }, { "GUILD", "Guild" }, { "OFFICER", "Officer" },
    { "WHISPER", "Whisper" }, { "INSTANCE_CHAT", "Instance" }, { "CHANNEL1", "Channel 1" }, { "CHANNEL2", "Channel 2" },
}

local function GamePage(f)
    local L = UI.Column(f, 0, 0, COL_W)
    L:Header("The game's chat settings")
    if CVarExists("chatBubbles") then L:Check("Chat bubbles", CVarBool("chatBubbles")) end
    if CVarExists("chatBubblesParty") then L:Check("Chat bubbles in party", CVarBool("chatBubblesParty")) end
    if CVarExists("showTimestamps") then
        L:Cycle("Timestamps", {
            { value = "none", text = "None" }, { value = "%H:%M ", text = "15:27" },
            { value = "%H:%M:%S ", text = "15:27:32" }, { value = "%I:%M ", text = "03:27" },
            { value = "%I:%M:%S ", text = "03:27:32" }, { value = "%I:%M %p ", text = "03:27 PM" },
            { value = "%I:%M:%S %p ", text = "03:27:32 PM" },
        }, CVarValue("showTimestamps"))
    end
    if CVarExists("chatStyle") then
        L:Cycle("Chat style", { { value = "im", text = "IM style" }, { value = "classic", text = "Classic" } },
            CVarValue("chatStyle"))
    end
    if CVarExists("whisperMode") then
        L:Cycle("New whispers", { { value = "popout", text = "New tab" }, { value = "inline", text = "In the chat" },
            { value = "popout_and_inline", text = "Both" } }, CVarValue("whisperMode"))
    end
    if CVarExists("profanityFilter") then L:Check("Mature language filter", CVarBool("profanityFilter")) end
    if CVarExists("chatMouseScroll") then L:Check("Scroll with the mouse wheel", CVarBool("chatMouseScroll")) end
    L:Note("Saved by the game for this account, not in a HUF profile.")

    local R = UI.Column(f, COL2_X, 0, COL_W)
    R:Header("Colours")
    for _, t in ipairs(COLOR_TYPES) do
        local key = t[1]
        if ChatTypeInfo and ChatTypeInfo[key] and ChangeChatColor then
            R:Color(t[2], function()
                local i = ChatTypeInfo[key]
                return { r = i.r, g = i.g, b = i.b }
            end, function(c) pcall(ChangeChatColor, key, c.r, c.g, c.b) end)
        end
    end
end

ns.RegisterPage("chat", "Chat", "utility", function(page)
    local on = UI.Check(page, 260, "Use HUF's chat changes", function() return C().enabled end,
        function(v)
            C().enabled = v
            if not v then ns.AskReload("The chat is back to normal after a reload.") end
        end, "Look, short channel names, links, history and buttons. Off: the game's chat as it was (after /reload).")
    on:SetPoint("TOPLEFT", 0, 4)
    local tabs = { { "look", "Look" }, { "panel", "Panel" }, { "lines", "Lines" }, { "buttons", "Buttons" }, { "game", "Game settings" } }
    local subs, strip = {}, nil
    local function Show(k)
        for n, sf in pairs(subs) do sf:SetShown(n == k) end
        strip:Select(k)
    end
    strip = UI.SubTabs(page, tabs, Show)
    strip:SetPoint("TOPLEFT", 0, -22)
    strip:SetPoint("TOPRIGHT", 0, -22)
    subs.look = SubFrame(page); LookPage(subs.look)
    subs.panel = SubFrame(page); PanelPage(subs.panel)
    subs.lines = SubFrame(page); LinesPage(subs.lines, page)
    subs.buttons = SubFrame(page); ButtonsPage(subs.buttons)
    subs.game = SubFrame(page); GamePage(subs.game)
    if strip.Bind then strip:Bind(subs, Show) end
    Show("look")
end, function() return ns.db.chat.enabled end)
