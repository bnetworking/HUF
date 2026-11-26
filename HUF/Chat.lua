-- HUF: the chat window.
--   * look: font, size, outline, background colour and opacity (the game's
--     own window colour / alpha, so it stays with the window)
--   * short channel names at the start of a line ([1], [2], [S], [P], [G] ...)
--   * URLs as clickable links (a copy box opens), link tooltips on mouseover
--   * class coloured names (the game's own per chat type setting)
--   * chat history kept over /reload and logout (up to 2000 lines a window)
--   * buttons beside the chat: copy, guild (members online), friends, and the
--     game's chat channel and chat menu buttons moved there; they fade out
--   * the input line below or above the chat
--   * the game's chat settings (bubbles, timestamps, style, colours) on one page
--
-- Taint rules (from EllesmereUI's chat engine): never replace a field on a
-- chat frame, never hook FCF_* functions, never reparent Blizzard chat parts.
-- The one hook is a post-hook on each window's AddMessage (hooksecurefunc):
-- it rewrites the line just stored in the window's history buffer and lets
-- the window redraw. Secret lines (chat lockdown in encounters, M+, PvP,
-- instances) are never read or changed: they stay as the game made them.

local _, ns = ...
local Chat = {}
ns.Chat = Chat

local A = ns.ACCENT
local function S() return ns.db.chat end
local function IsSecret(v) return issecretvalue and issecretvalue(v) or false end

local hooked = {}             -- chat frame -> true
local restoring = false

---------------------------------------------------------------------------
-- Chat windows
---------------------------------------------------------------------------
local function Windows()
    local list = {}
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local cf = _G["ChatFrame" .. i]
        if cf then list[#list + 1] = cf end
    end
    -- whisper / pet battle windows the game opens later (ChatFrame11+)
    for i = (NUM_CHAT_WINDOWS or 10) + 1, 40 do
        local cf = _G["ChatFrame" .. i]
        if cf then list[#list + 1] = cf end
    end
    return list
end

local function SelectedWindow()
    if GENERAL_CHAT_DOCK and FCFDock_GetSelectedWindow then
        local ok, cf = pcall(FCFDock_GetSelectedWindow, GENERAL_CHAT_DOCK)
        if ok and cf then return cf end
    end
    return SELECTED_CHAT_FRAME or ChatFrame1
end

local function IsCombatLog(cf)
    return cf == _G.ChatFrame2 or (cf.GetName and cf:GetName() == "ChatFrame2")
end

---------------------------------------------------------------------------
-- Line rewriting: short channel names, URLs
---------------------------------------------------------------------------
-- event (without CHAT_MSG_) -> setting key
local CHANNEL_KEYS = {
    PARTY = "PARTY", PARTY_LEADER = "PARTY_LEADER", PARTY_GUIDE = "PARTY_LEADER",
    GUILD = "GUILD", OFFICER = "OFFICER",
    RAID = "RAID", RAID_LEADER = "RAID_LEADER", RAID_WARNING = "RAID_WARNING",
    INSTANCE_CHAT = "INSTANCE_CHAT", INSTANCE_CHAT_LEADER = "INSTANCE_CHAT_LEADER",
}
-- "%s says: " style templates (the name is a link, the rest plain text)
local SPOKEN = {
    SAY = "CHAT_SAY_GET", YELL = "CHAT_YELL_GET", WHISPER = "CHAT_WHISPER_GET",
    WHISPER_INFORM = "CHAT_WHISPER_INFORM_GET", BN_WHISPER = "CHAT_BN_WHISPER_GET",
    BN_WHISPER_INFORM = "CHAT_BN_WHISPER_INFORM_GET",
}
local SPOKEN_KEY = { SAY = "SAY", YELL = "YELL", WHISPER = "WHISPER", WHISPER_INFORM = "WHISPER",
    BN_WHISPER = "WHISPER", BN_WHISPER_INFORM = "WHISPER" }

local function Abbr(key)
    local a = S().abbr[key]
    if not a or a == "" then return nil end
    return a
end

-- the [Party] / [1. General] link at the start of a line
local function ShortChannel(msg, kind)
    local s, e, target, label = msg:find("|Hchannel:(.-)|h%[(.-)%]|h")
    if not s then return msg end
    local short
    local num = target:match("^channel:(%d+)") or target:match("^(%d+)$")
    if num then
        local fmt = S().abbr.CHANNEL or "%d"
        short = fmt:find("%%d") and fmt:format(tonumber(num)) or num
    else
        local key = (kind and CHANNEL_KEYS[kind]) or CHANNEL_KEYS[target:upper()]
        short = key and Abbr(key)
    end
    if not short then return msg end
    return msg:sub(1, s - 1) .. "|Hchannel:" .. target .. "|h[" .. short .. "]|h" .. msg:sub(e + 1)
end

-- "Name says: text" -> "[S] Name: text"
local function ShortSpoken(msg, kind)
    local tname = SPOKEN[kind]
    local short = tname and Abbr(SPOKEN_KEY[kind])
    local tpl = tname and _G[tname]
    if not (short and type(tpl) == "string") then return msg end
    local before, after = tpl:match("^(.-)%%s(.*)$")
    if not before then return msg end
    -- the name link
    local ls = msg:find("|H[Bb]?[Nn]?player", 1) or msg:find("|HBNplayer", 1, true)
    if not ls then return msg end
    local le = msg:find("|h", msg:find("|h", ls + 2, true) + 2, true)
    if not le then return msg end
    le = le + 1
    local head = msg:sub(1, ls - 1)
    local rest = msg:sub(le + 1)
    -- drop "says" after the name: " says: " -> ": "
    if after ~= "" and rest:sub(1, #after) == after then
        local colon = after:match("(:%s*)$") or ": "
        rest = colon .. rest:sub(#after + 1)
    end
    -- "To " before the name stays (whispers you send)
    local pre = ""
    if before ~= "" and head:sub(-#before) == before then
        pre = before
        head = head:sub(1, -#before - 1)
    end
    return head .. "[" .. short .. "] " .. pre .. msg:sub(ls, le) .. rest
end

-- a web address: a word starting with "scheme://" or "www."
local function WrapWord(word, hex)
    local core, tail = word:match("^(.-)([%.,;:!%?%)%]\"']*)$")
    if not core or core == "" then return word end
    if core:match("^%a[%w+.-]*://[^%s]+$") or core:match("^www%.[%w%-_]+%.%a%a+") then
        return hex .. "|HHUFurl:" .. core .. "|h[" .. core .. "]|h|r" .. tail
    end
    return word
end
local function Links(msg)
    if not (msg:find("://", 1, true) or msg:find("www.", 1, true)) then return msg end
    local hex = ("|cff%02x%02x%02x"):format(A[1] * 255, A[2] * 255, A[3] * 255)
    -- only outside existing links (|H...|h...|h)
    local out, pos = {}, 1
    while true do
        local s = msg:find("|H", pos, true)
        local seg = msg:sub(pos, s and s - 1 or #msg)
        seg = seg:gsub("[^%s|]+", function(w) return WrapWord(w, hex) end)
        out[#out + 1] = seg
        if not s then break end
        local mid = msg:find("|h", s + 2, true)
        local e = mid and msg:find("|h", mid + 2, true)
        if not e then out[#out + 1] = msg:sub(s) break end
        out[#out + 1] = msg:sub(s, e + 1)
        pos = e + 2
    end
    return table.concat(out)
end
Chat.Links, Chat.ShortChannel, Chat.ShortSpoken = Links, ShortChannel, ShortSpoken

function Chat.Transform(msg, event)
    local s = S()
    if type(msg) ~= "string" or IsSecret(msg) then return msg end
    local kind = type(event) == "string" and not IsSecret(event) and event:match("^CHAT_MSG_(.+)$") or nil
    local out = msg
    if s.abbreviate then
        local ok, r = pcall(ShortChannel, out, kind)
        if ok then out = r end
        if kind and SPOKEN[kind] then
            local ok2, r2 = pcall(ShortSpoken, out, kind)
            if ok2 then out = r2 end
        end
    end
    if s.urls then
        local ok, r = pcall(Links, out)
        if ok then out = r end
    end
    return out
end

---------------------------------------------------------------------------
-- History (per character, per window)
---------------------------------------------------------------------------
local function Store()
    HUFDB.chatHistory = HUFDB.chatHistory or {}
    local k = ns.CharKey()
    HUFDB.chatHistory[k] = HUFDB.chatHistory[k] or {}
    return HUFDB.chatHistory[k]
end

local function Remember(cf, msg, r, g, b)
    local s = S()
    if not s.history or restoring or IsCombatLog(cf) then return end
    if type(msg) ~= "string" or IsSecret(msg) then return end
    local id = cf:GetID()
    if not id or id < 1 or id > (NUM_CHAT_WINDOWS or 10) then return end
    local st = Store()
    local list = st[id]
    if not list then list = {} st[id] = list end
    list[#list + 1] = { msg, tonumber(r) and math.floor(r * 100 + 0.5) / 100 or 1,
        tonumber(g) and math.floor(g * 100 + 0.5) / 100 or 1, tonumber(b) and math.floor(b * 100 + 0.5) / 100 or 1 }
    local over = #list - s.historyLines
    if over > 50 then
        local keep = {}
        for i = over + 1, #list do keep[#keep + 1] = list[i] end
        st[id] = keep
    end
end

function Chat.Restore()
    local s = S()
    if not s.history or Chat.restored then return end
    Chat.restored = true
    local st = Store()
    restoring = true
    for id, list in pairs(st) do
        local cf = _G["ChatFrame" .. id]
        if cf and #list > 0 then
            local from = math.max(1, #list - s.historyLines + 1)
            for i = from, #list do
                local l = list[i]
                pcall(cf.AddMessage, cf, l[1], l[2], l[3], l[4])
            end
            pcall(cf.AddMessage, cf, "|cff666666-- earlier chat above --|r", 0.4, 0.4, 0.4)
        end
    end
    restoring = false
end

function Chat.ClearHistory()
    if HUFDB.chatHistory then HUFDB.chatHistory[ns.CharKey()] = nil end
end

---------------------------------------------------------------------------
-- The post-hook
---------------------------------------------------------------------------
local function OnAddMessage(cf, msg, r, g, b, _, _, _, event)
    if not (HUFDB and ns.db) then return end
    local s = S()
    if not s.enabled or IsSecret(msg) or type(msg) ~= "string" then return end
    if restoring then return end
    local shown = msg
    if not IsCombatLog(cf) and (s.abbreviate or s.urls) then
        shown = Chat.Transform(msg, event)
        if shown ~= msg then
            -- the line the window just stored: rewrite it and redraw
            local hb = cf.historyBuffer
            local e = hb and hb.GetEntryAtIndex and hb:GetEntryAtIndex(1)
            if e and type(e.message) == "string" and not IsSecret(e.message) and e.message == msg then
                e.message = shown
                if cf.MarkDisplayDirty then pcall(cf.MarkDisplayDirty, cf)
                elseif cf.RefreshDisplay then pcall(cf.RefreshDisplay, cf) end
            else
                shown = msg
            end
        end
    end
    Remember(cf, shown, r, g, b)
end

local function OnHyperlinkEnter(cf, link)
    if not S().linkTooltips or IsSecret(link) or type(link) ~= "string" then return end
    local t = link:match("^([^:]+)")
    local TYPES = { item = true, spell = true, quest = true, achievement = true, enchant = true, talent = true,
        currency = true, unit = true, trade = true, mount = true, battlepet = true, instancelock = true }
    if not TYPES[t] then return end
    GameTooltip:SetOwner(cf, "ANCHOR_CURSOR")
    if pcall(GameTooltip.SetHyperlink, GameTooltip, link) then GameTooltip:Show() else GameTooltip:Hide() end
    Chat.tipShown = true
end
local function OnHyperlinkLeave()
    if Chat.tipShown then Chat.tipShown = nil GameTooltip:Hide() end
end

local function Hook(cf)
    if hooked[cf] then return end
    hooked[cf] = true
    hooksecurefunc(cf, "AddMessage", OnAddMessage)
    cf:HookScript("OnHyperlinkEnter", OnHyperlinkEnter)
    cf:HookScript("OnHyperlinkLeave", OnHyperlinkLeave)
end

---------------------------------------------------------------------------
-- URL copy box (clicking a HUFurl link)
---------------------------------------------------------------------------
local urlBox
local function ShowURL(url)
    if not urlBox then
        local f = CreateFrame("Frame", "HUF_ChatURL", UIParent)
        f:SetSize(380, 56)
        f:SetPoint("CENTER", 0, 120)
        f:SetFrameStrata("DIALOG")
        f:EnableMouse(true)
        ns.UI.Fill(f, 0.05, 0.05, 0.06, 0.96)
        ns.UI.Border(f, A[1], A[2], A[3], 0.9)
        local t = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        t:SetPoint("TOP", 0, -6)
        t:SetText("Ctrl+C to copy, Esc to close")
        local e = CreateFrame("EditBox", nil, f)
        e:SetFontObject("GameFontHighlight")
        e:SetPoint("BOTTOMLEFT", 10, 8)
        e:SetPoint("BOTTOMRIGHT", -10, 8)
        e:SetHeight(22)
        e:SetAutoFocus(true)
        ns.UI.Fill(e, 0.09, 0.09, 0.10, 1)
        e:SetTextInsets(6, 6, 0, 0)
        e:SetScript("OnEscapePressed", function() f:Hide() end)
        e:SetScript("OnEditFocusLost", function() f:Hide() end)
        e:SetScript("OnTextChanged", function(self, user) if user then self:SetText(f.url) self:HighlightText() end end)
        f.edit = e
        urlBox = f
    end
    urlBox.url = url
    urlBox.edit:SetText(url)
    urlBox:Show()
    urlBox.edit:SetFocus()
    urlBox.edit:HighlightText()
end
hooksecurefunc("SetItemRef", function(link)
    if type(link) ~= "string" or IsSecret(link) then return end
    local url = link:match("^HUFurl:(.+)$")
    if url then ShowURL(url) end
end)

---------------------------------------------------------------------------
-- Copy window
---------------------------------------------------------------------------
local function Plain(text)
    text = text:gsub("|H.-|h(.-)|h", "%1")
    text = text:gsub("|T.-|t", "")
    text = text:gsub("|A.-|a", "")
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|r", "")
    text = text:gsub("|n", "\n")
    text = text:gsub("||", "|")
    return text
end
Chat.Plain = Plain

local copyWin
function Chat.Copy()
    local cf = SelectedWindow()
    local lines = {}
    local n = cf.GetNumMessages and cf:GetNumMessages() or 0
    for i = 1, n do
        local ok, text = pcall(cf.GetMessageInfo, cf, i)
        if ok and type(text) == "string" and not IsSecret(text) then
            local ok2, p = pcall(Plain, text)
            if ok2 then lines[#lines + 1] = p end
        end
    end
    if not copyWin then
        local f = CreateFrame("Frame", "HUF_ChatCopy", UIParent)
        f:SetSize(620, 420)
        f:SetPoint("CENTER")
        -- above the settings window (DIALOG too): it would draw over this one
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:SetToplevel(true)
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        ns.UI.Fill(f, 0.05, 0.05, 0.06, 0.96)
        ns.UI.Border(f, A[1], A[2], A[3], 0.9)
        local t = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        t:SetPoint("TOPLEFT", 10, -8)
        t:SetText("Chat - Ctrl+A, Ctrl+C to copy")
        local close = ns.UI.Button(f, 24, "x", function() f:Hide() end)
        close:SetPoint("TOPRIGHT", -6, -4)
        f.area = ns.UI.TextArea(f, 600, 376)
        f.area:SetPoint("BOTTOM", 0, 8)
        if UISpecialFrames then table.insert(UISpecialFrames, "HUF_ChatCopy") end
        copyWin = f
    end
    local e = copyWin.area.edit or copyWin.area.editBox or copyWin.area.e
    local text = #lines > 0 and table.concat(lines, "\n") or "(no chat lines that can be copied)"
    if e then
        e:SetText(text)
        e:SetFocus()
        e:HighlightText()
        e:SetCursorPosition(#text)
    elseif copyWin.area.SetText then
        copyWin.area:SetText(text)
    end
    copyWin:Show()
    copyWin:Raise()
    -- at the newest line (once the text is laid out)
    local sc = e and e:GetParent()
    if sc and sc.SetVerticalScroll then
        -- the text's height minus what shows, never past the range (scrolling
        -- past the text left the window empty); again once it is laid out
        local function Bottom()
            local want = math.max(0, (e:GetHeight() or 0) - (sc:GetHeight() or 0))
            local range = sc:GetVerticalScrollRange() or 0
            sc:SetVerticalScroll(math.max(0, math.min(want, range)))
        end
        C_Timer.After(0, Bottom)
        C_Timer.After(0.2, Bottom)
    end
end

---------------------------------------------------------------------------
-- Buttons beside the chat
---------------------------------------------------------------------------
local bar
local BUTTONS = {
    { key = "copy", icon = "Interface\\Buttons\\UI-GuildButton-PublicNote-Up", tip = "Copy chat", click = function() Chat.Copy() end },
    { key = "guild", icon = "Interface\\Icons\\INV_Shirt_GuildTabard_01", tip = "Guild", click = function()
        if ToggleGuildFrame then ToggleGuildFrame() elseif ToggleCommunitiesFrame then ToggleCommunitiesFrame() end end },
    { key = "social", icon = "Interface\\FriendsFrame\\UI-Toast-FriendOnlineIcon", tip = "Friends", click = function()
        if ToggleFriendsFrame then ToggleFriendsFrame() end end },
    -- the game's own buttons, moved here: an invisible copy of the real one
    -- lies over HUF's icon and takes the clicks (EllesmereUI's way: the
    -- game's menu opens where the button is)
    { key = "channels", atlas = "chatframe-button-icon-voicechat", icon = "Interface\\ChatFrame\\UI-ChatIcon-ArmoryChat",
      blizzard = "ChatFrameChannelButton", tip = "Chat channels" },
    { key = "chatmenu", icon = "Interface\\ChatFrame\\UI-ChatIcon-Chat-Up", blizzard = "ChatFrameMenuButton",
      tip = "Language, emotes, chat type" },
    -- the game's voice chat mute / deafen buttons: moved here and left VISIBLE (their
    -- icon shows the muted / deafened state); only while the game shows them (in voice chat)
    { key = "voicemute", blizzard = "ChatFrameToggleVoiceMuteButton", visible = true, tip = "Voice chat: mute" },
    { key = "voicedeafen", blizzard = "ChatFrameToggleVoiceDeafenButton", visible = true, tip = "Voice chat: deafen" },
    { key = "settings", icon = "Interface\\Buttons\\UI-OptionsButton", tip = "HUF settings",
      click = function() if ns.ToggleConfig then ns.ToggleConfig("chat", true) end end },
    { key = "bottom", icon = "Interface\\ChatFrame\\UI-ChatIcon-ScrollEnd-Up", tip = "To the newest line",
      click = function()
          local cf = SelectedWindow()
          if cf and cf.ScrollToBottom then cf:ScrollToBottom() end
      end },
}

local function GuildOnline()
    if not (IsInGuild and IsInGuild()) then return nil end
    local ok, total, online = pcall(GetNumGuildMembers)
    if not ok then return 0, 0 end
    return online or 0, total or 0
end

local function GuildTooltip(b)
    GameTooltip:SetOwner(b, "ANCHOR_LEFT")
    local online, total = GuildOnline()
    local name = GetGuildInfo and GetGuildInfo("player")
    GameTooltip:SetText(name or "Guild")
    GameTooltip:AddLine(("%d of %d online"):format(online or 0, total or 0), 0.8, 0.8, 0.8)
    local shown = 0
    for i = 1, total or 0 do
        local ok, full, _, _, level, _, zone, _, _, isOnline, _, classFile = pcall(GetGuildRosterInfo, i)
        if ok and isOnline and type(full) == "string" then
            shown = shown + 1
            if shown > 25 then GameTooltip:AddLine("...", 0.6, 0.6, 0.6) break end
            local n = full:gsub("%-.*$", "")
            n = ns.NameFromString and ns.NameFromString(n) or n
            local c = classFile and ns.ClassColor(classFile)
            GameTooltip:AddDoubleLine(("%s  |cff999999%s|r"):format(n, tostring(level or "")), zone or "",
                c and c.r or 1, c and c.g or 1, c and c.b or 1, 0.7, 0.7, 0.7)
        end
    end
    GameTooltip:AddLine("Click: guild window", 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

local function BuildBar()
    if bar then return end
    bar = CreateFrame("Frame", "HUF_ChatButtons", UIParent)
    bar:SetFrameStrata("LOW")
    bar.buttons = {}
    for _, info in ipairs(BUTTONS) do
        local b = CreateFrame("Button", nil, bar)
        b:SetSize(22, 22)
        b.fill = ns.UI.Fill(b, 0.05, 0.05, 0.06, 0.85)
        b.border = ns.UI.Border(b, 0.2, 0.2, 0.22, 1)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetPoint("TOPLEFT", 3, -3)
        b.icon:SetPoint("BOTTOMRIGHT", -3, 3)
        if not (info.atlas and b.icon.SetAtlas and pcall(b.icon.SetAtlas, b.icon, info.atlas)) and info.icon then
            b.icon:SetTexture(info.icon)
        end
        if info.key == "guild" then b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
        b:RegisterForClicks("LeftButtonUp")
        if info.click then b:SetScript("OnClick", info.click) end
        b.blizzard = info.blizzard
        b.visible = info.visible
        b:SetScript("OnEnter", function(self)
            self.border:SetColor(A[1], A[2], A[3], 1)
            if info.key == "guild" then GuildTooltip(self) return end
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetText(info.tip)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function(self) self.border:SetColor(0.2, 0.2, 0.22, 1) GameTooltip:Hide() end)
        if info.key == "guild" then
            b.count = b:CreateFontString(nil, "OVERLAY")
            ns.ApplyFont(b.count, "GLOBAL", 10, "OUTLINE")
            b.count:SetPoint("BOTTOMRIGHT", 1, -1)
        end
        b.key = info.key
        bar.buttons[#bar.buttons + 1] = b
    end
end

function Chat.UpdateGuildCount()
    if not bar then return end
    for _, b in ipairs(bar.buttons) do
        if b.key == "guild" then
            local online = GuildOnline()
            b.count:SetText(online and tostring(online) or "")
        end
    end
end

-- the game's button over HUF's slot: invisible, mouse on, above the slot
local seated = {}
local function Seat(b, on)
    local real = b.blizzard and _G[b.blizzard]
    if not real then return false end
    if not seated[real] then
        seated[real] = b
        real:HookScript("OnEnter", function()
            local slot = seated[real]
            if slot and slot:IsShown() then slot.border:SetColor(A[1], A[2], A[3], 1) Chat.Wake() end
        end)
        real:HookScript("OnLeave", function()
            local slot = seated[real]
            if slot then slot.border:SetColor(0.2, 0.2, 0.22, 1) end
        end)
    end
    real:ClearAllPoints()
    if on then
        real:SetAllPoints(b)
        if real.SetFixedFrameStrata then real:SetFixedFrameStrata(false) end
        real:SetFrameStrata(bar:GetFrameStrata())
        if real.SetFixedFrameStrata then real:SetFixedFrameStrata(true) end
        if real.SetFixedFrameLevel then real:SetFixedFrameLevel(false) end
        real:SetFrameLevel(b:GetFrameLevel() + 3)
        if real.SetFixedFrameLevel then real:SetFixedFrameLevel(true) end
        if b.visible then
            -- shown as it is (its own icon and state) in HUF's slot; its parent (the
            -- hidden button column) is see-through, so it ignores the parent's alpha
            if real.SetIgnoreParentAlpha then real:SetIgnoreParentAlpha(true) end
            real:SetAlpha(bar:GetAlpha())
            b.icon:Hide()
        else
            real:SetAlpha(0)
        end
        real:EnableMouse(true)
    else
        -- not wanted: hidden away (its place belongs to the game's chat layout)
        real:SetAllPoints(b)
        real:SetAlpha(0)
        real:EnableMouse(false)
    end
    return true
end

-- the bar's alpha (fading), also for the game's buttons shown in it
local function SetBarAlpha(a)
    if not bar then return end
    if math.abs(bar:GetAlpha() - a) > 0.001 then bar:SetAlpha(a) end
    for real, b in pairs(seated) do
        if b.visible and b:IsShown() and bar:IsShown() then real:SetAlpha(a) end
    end
end

-- the voice buttons come and go with voice chat (the game shows / hides them):
-- the strip follows (a slot only while its button is shown)
local watched = {}
local function Watch(real)
    if watched[real] then return end
    watched[real] = true
    local function Again() C_Timer.After(0, function() if Chat.LayoutBar then Chat.LayoutBar() end end) end
    real:HookScript("OnShow", Again)
    real:HookScript("OnHide", Again)
end

local function LayoutBar()
    local s = S()
    BuildBar()
    local cf = ChatFrame1
    if not (s.enabled and cf) then bar:Hide() return end
    local y, n = 0, 0
    for _, b in ipairs(bar.buttons) do
        local on = s.buttons[b.key]
        if b.key == "guild" and not (IsInGuild and IsInGuild()) then on = false end
        if b.blizzard and not _G[b.blizzard] then on = false end
        if on and b.visible then
            local real = _G[b.blizzard]
            Watch(real)
            if not real:IsShown() then on = false end      -- not in voice chat
        end
        b:ClearAllPoints()
        local size = s.iconSize or 22
        if on then
            b:SetSize(size, size)
            b:SetPoint("TOP", bar, "TOP", 0, -y)
            y = y + size + (s.iconGap or 2)
            n = n + 1
            b:Show()
        else
            b:Hide()
        end
    end
    bar:SetSize(s.iconSize or 22, math.max(1, y - (s.iconGap or 2)))
    bar:ClearAllPoints()
    local panel = Chat.PanelOn and Chat.PanelOn() and Chat.Panel and Chat.Panel()
    -- the panel look: plain icons on a strip as tall as the panel
    local ic = s.iconAccent and { r = A[1], g = A[2], b = A[3] } or s.iconColor or { r = 1, g = 1, b = 1 }
    for _, b in ipairs(bar.buttons) do
        b.fill:SetShown(not panel)
        b.border:SetShown(not panel)
        -- the panel look: plain grey-white icons, tinted by the icon colour
        b.icon:SetDesaturated(panel and true or false)
        if panel then b.icon:SetVertexColor(ic.r, ic.g, ic.b) else b.icon:SetVertexColor(1, 1, 1) end
    end
    if not bar.strip then
        bar.strip = CreateFrame("Frame", nil, bar)
        bar.strip:SetFrameLevel(math.max(0, bar:GetFrameLevel() - 1))
        bar.strip.bg = ns.UI.Fill(bar.strip, 0, 0, 0, 0.6)
        bar.strip.border = ns.UI.Border(bar.strip, 1, 1, 1, 0.18)
    end
    local st = bar.strip
    st:ClearAllPoints()
    if panel then
        local gap = (s.stripJoined ~= false and 0 or (s.stripGap or 8)) + (s.buttonX or 0)
        if s.buttonSide == "LEFT" then
            st:SetPoint("TOPRIGHT", panel, "TOPLEFT", -gap, 0)
            st:SetPoint("BOTTOMRIGHT", panel, "BOTTOMLEFT", -gap, 0)
        else
            st:SetPoint("TOPLEFT", panel, "TOPRIGHT", gap, 0)
            st:SetPoint("BOTTOMLEFT", panel, "BOTTOMRIGHT", gap, 0)
        end
        st:SetWidth((s.stripWidth or 0) > 0 and s.stripWidth or ((s.iconSize or 22) + 6))
        bar:SetPoint("TOP", st, "TOP", 0, -6 + (s.buttonY or 0))
        -- "to the newest line" at the strip's bottom
        for _, b in ipairs(bar.buttons) do
            if b.key == "bottom" and b:IsShown() then
                b:ClearAllPoints()
                b:SetPoint("BOTTOM", st, "BOTTOM", 0, 6)
            end
        end
        st.bg:SetColorTexture(s.bgColor.r, s.bgColor.g, s.bgColor.b, s.bgAlpha)
        local bc = s.panelBorderColor or { r = 1, g = 1, b = 1 }
        st.border:SetColor(bc.r, bc.g, bc.b, s.panelBorderAlpha or 0.18)
        st.border:SetShown((s.panelBorderAlpha or 0) > 0 and s.stripBg ~= false)
        st.bg:SetShown(s.stripBg ~= false)
        st:Show()
    else
        st:Hide()
        if s.buttonSide == "LEFT" then
            bar:SetPoint("TOPRIGHT", cf, "TOPLEFT", -6 + (s.buttonX or 0), (s.buttonY or 0))
        else
            bar:SetPoint("TOPLEFT", cf, "TOPRIGHT", 6 + (s.buttonX or 0), (s.buttonY or 0))
        end
    end
    bar:SetShown(n > 0)
    for _, b in ipairs(bar.buttons) do
        if b.blizzard then Seat(b, b:IsShown() and n > 0) end
    end
    Chat.UpdateGuildCount()
    Chat.Wake()
end
Chat.LayoutBar = LayoutBar

---------------------------------------------------------------------------
-- Fading the buttons: down to fadeAlpha after fadeDelay seconds, full again
-- while the mouse is over the chat or the buttons
---------------------------------------------------------------------------
local idle = 0
function Chat.Wake()
    idle = 0
    SetBarAlpha(1)
end

local function MouseOverChat()
    if bar and bar:IsShown() and bar:IsMouseOver(4, -4, -4, 4) then return true end
    -- typing: awake
    for _, cf in ipairs(Windows()) do
        local name = cf.GetName and cf:GetName()
        local eb = name and _G[name .. "EditBox"]
        if eb and eb.HasFocus and eb:HasFocus() then return true end
    end
    local cf = SelectedWindow()
    for _, f in ipairs({ cf, ChatFrame1 }) do
        -- the window with its tabs above and the input line below
        if f and f:IsVisible() and f:IsMouseOver(32, -36, -8, 8) then return true end
    end
    for real in pairs(seated) do
        if real:IsVisible() and real:IsMouseOver() then return true end
    end
    return false
end

C_Timer.NewTicker(0.2, function()
    if not (bar and HUFDB and ns.db) then return end
    local s = S()
    local whole = s.fadeWhole and Chat.SetWholeAlpha
    if not (s.enabled and s.fade) then
        SetBarAlpha(1)
        if Chat.SetWholeAlpha then Chat.SetWholeAlpha(1) end
        return
    end
    if MouseOverChat() then
        idle = 0
        SetBarAlpha(1)
        if Chat.SetWholeAlpha then Chat.SetWholeAlpha(1) end
        return
    end
    idle = idle + 0.2
    if idle >= s.fadeDelay then
        if math.abs(bar:GetAlpha() - s.fadeAlpha) > 0.01 then SetBarAlpha(s.fadeAlpha) end
        if whole then Chat.SetWholeAlpha(s.fadeAlpha) end
    elseif Chat.SetWholeAlpha then
        Chat.SetWholeAlpha(1)
    end
end)

---------------------------------------------------------------------------
-- Input line above or below the chat (plain anchors; never hooks on the box)
---------------------------------------------------------------------------
local placedInput = {}
local function PlaceInput(cf)
    local s = S()
    local name = cf.GetName and cf:GetName()
    local eb = name and _G[name .. "EditBox"]
    if not eb then return end
    local want = s.enabled and s.inputPos or "BELOW"
    if want == "BELOW" and not placedInput[eb] then return end     -- the game's own place
    eb:ClearAllPoints()
    local off = s.inputOffset or 0
    if want == "ABOVE" then
        eb:SetPoint("BOTTOMLEFT", cf, "TOPLEFT", -5, 28 + off)
        eb:SetPoint("BOTTOMRIGHT", cf, "TOPRIGHT", 5, 28 + off)
    elseif want == "INSIDE_TOP" then
        -- over the chat's top lines, right under the tabs (like EllesmereUI)
        eb:SetPoint("TOPLEFT", cf, "TOPLEFT", -5, 5 - off)
        eb:SetPoint("TOPRIGHT", cf, "TOPRIGHT", 5, 5 - off)
    elseif want == "INSIDE_BOTTOM" then
        eb:SetPoint("BOTTOMLEFT", cf, "BOTTOMLEFT", -5, -5 + off)
        eb:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", 5, -5 + off)
    else
        eb:SetPoint("TOPLEFT", cf, "BOTTOMLEFT", -5, -2 - off)
        eb:SetPoint("TOPRIGHT", cf, "BOTTOMRIGHT", 5, -2 - off)
    end
    placedInput[eb] = true
end

---------------------------------------------------------------------------
-- Look
---------------------------------------------------------------------------
local function ApplyLook(cf)
    local s = S()
    local path = ns.FontPath(s.font == "GLOBAL" and ns.db.global.font or s.font)
    local outline = s.outline == "GLOBAL" and ns.db.global.outline or s.outline
    if outline == "NONE" then outline = "" end
    if path then
        pcall(cf.SetFont, cf, path, s.fontSize, outline)
        local name = cf.GetName and cf:GetName()
        local eb = name and _G[name .. "EditBox"]
        if eb then
            pcall(eb.SetFont, eb, path, s.fontSize, outline)
            local hdr = eb.header or _G[name .. "EditBoxHeader"]
            if hdr then pcall(hdr.SetFont, hdr, path, s.fontSize, outline) end
        end
    end
end

local function ApplyBackground(cf)
    local s = S()
    -- the panel look: docked windows have no background of their own (the
    -- panel is behind them)
    local none = false
    if s.look == "PANEL" then
        local dock = _G.GENERAL_CHAT_DOCK
        local list = dock and dock.DOCKED_CHAT_FRAMES
        for _, f in ipairs(type(list) == "table" and list or { ChatFrame1 }) do if f == cf then none = true end end
    end
    if FCF_SetWindowColor then pcall(FCF_SetWindowColor, cf, s.bgColor.r, s.bgColor.g, s.bgColor.b) end
    if FCF_SetWindowAlpha then pcall(FCF_SetWindowAlpha, cf, none and 0 or s.bgAlpha) end
end

-- the game's class colour per chat type
local CLASS_TYPES = { "SAY", "YELL", "EMOTE", "PARTY", "PARTY_LEADER", "RAID", "RAID_LEADER", "RAID_WARNING",
    "GUILD", "OFFICER", "WHISPER", "WHISPER_INFORM", "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER" }
function Chat.ApplyClassColors(on)
    local fn = SetChatColorNameByClass or (C_ChatInfo and C_ChatInfo.SetChatColorNameByClass)
    if not fn then return end
    for _, t in ipairs(CLASS_TYPES) do pcall(fn, t, on) end
    for i = 1, 20 do pcall(fn, "CHANNEL" .. i, on) end
end

-- the game's empty button column beside each window and its Social (quick join)
-- button: ALPHA and mouse only, never SetParent / Hide (EllesmereUI's rule: the dock
-- code moves the column and reads the window's fields, a changed parent taints it).
-- The column's own fades still change its alpha, so its art is emptied too.
local function HideStock(cf)
    local name = cf.GetName and cf:GetName()
    local col = name and _G[name .. "ButtonFrame"]
    if col and not col.hufEmptied then
        col.hufEmptied = true
        col:SetAlpha(0)
        col:EnableMouse(false)
        for _, r in ipairs({ col:GetRegions() }) do
            if r.IsObjectType and r:IsObjectType("Texture") then r:SetTexture("") end
        end
    end
end
local function HideSocial()
    local q = _G.QuickJoinToastButton
    if q then q:SetAlpha(0) q:EnableMouse(false) end
end

---------------------------------------------------------------------------
-- Panel look (option "look" = PANEL, like EllesmereUI's chat): one dark
-- panel behind the docked windows and their tab strip, flat text tabs with
-- a line under the active one, a flat input line, the buttons on a strip of
-- their own. Blizzard's tab strip keeps working as it is and takes every
-- click; only its alpha goes to 0. HUF's tabs are "ghosts": mouse-off
-- frames anchored to the real tabs (never parented to them), and nothing
-- is written to the tabs themselves.
---------------------------------------------------------------------------
local look = { ghosts = {}, boxes = {}, zeroed = {} }
local PAD = 4

local function PanelOn()
    local s = S()
    return s.enabled and s.look == "PANEL"
end
Chat.PanelOn = PanelOn

local function Docked()
    local dock = _G.GENERAL_CHAT_DOCK
    local list = dock and dock.DOCKED_CHAT_FRAMES
    return type(list) == "table" and list or { ChatFrame1 }, dock
end

local function BuildPanel()
    if look.panel then return end
    local p = CreateFrame("Frame", "HUF_ChatPanel", UIParent)
    p:SetFrameStrata("BACKGROUND")
    p:EnableMouse(false)
    p.bg = ns.UI.Fill(p, 0, 0, 0, 0.6)
    p.border = ns.UI.Border(p, 1, 1, 1, 0.18)
    p:Hide()
    look.panel = p
end

-- an edge of n pixels (UI.Border draws 1)
local function EdgeSize(border, n)
    n = math.max(1, n or 1)
    local e = border.edges
    e[1]:SetHeight(n) e[2]:SetHeight(n) e[3]:SetWidth(n) e[4]:SetWidth(n)
end

local function LayoutPanel()
    local s = S()
    BuildPanel()
    local p, cf, gdm = look.panel, ChatFrame1, _G.GeneralDockManager
    if not (PanelOn() and cf) then p:Hide() return end
    -- from the top of the tabs (their bottom + the tab height) to below the chat
    local tab = _G.ChatFrame1Tab
    local tb, ct = tab and tab:GetBottom(), cf:GetTop()
    local top = (tb and ct) and math.floor(tb - ct + (s.tabHeight or 22) + 0.5) or (26 + PAD)
    local pad, padB = s.panelPadX or 10, s.panelPadBottom or 6
    if p.top ~= top or p.pad ~= pad or p.padB ~= padB or not p:GetPoint(1) then
        p:ClearAllPoints()
        p:SetPoint("TOPLEFT", cf, "TOPLEFT", -pad, top)
        p:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", pad, -padB)
        p.top, p.pad, p.padB = top, pad, padB
    end
    p.bg:SetColorTexture(s.bgColor.r, s.bgColor.g, s.bgColor.b, s.bgAlpha)
    local bc = s.panelBorderColor or { r = 1, g = 1, b = 1 }
    p.border:SetColor(bc.r, bc.g, bc.b, s.panelBorderAlpha or 0.18)
    EdgeSize(p.border, s.panelBorderSize)
    p.border:SetShown((s.panelBorderAlpha or 0) > 0)
    p:Show()
end
Chat.Panel = function() return look.panel end

-- one ghost per real tab
local function Ghost(tab)
    local g = look.ghosts[tab]
    if g then return g end
    g = CreateFrame("Frame", nil, UIParent)
    g:EnableMouse(false)
    g.text = g:CreateFontString(nil, "OVERLAY")
    g.text:SetPoint("LEFT", 2, 1)
    g.text:SetPoint("RIGHT", -2, 1)
    g.text:SetJustifyH("CENTER")
    g.text:SetWordWrap(false)
    g.bg = ns.UI.Fill(g, 0, 0, 0, 0)
    g.edge = ns.UI.Border(g, 1, 1, 1, 0.18)
    g.line = g:CreateTexture(nil, "OVERLAY")
    g.line:SetHeight(2)
    g.line:SetPoint("BOTTOMLEFT", 4, 0)
    g.line:SetPoint("BOTTOMRIGHT", -4, 0)
    g:Hide()
    look.ghosts[tab] = g
    return g
end

local function UpdateGhosts()
    local s = S()
    local seen = {}
    if PanelOn() then
        local list, dock = Docked()
        local font = ns.FontPath(s.font == "GLOBAL" and ns.db.global.font or s.font)
        local outline = s.outline == "GLOBAL" and ns.db.global.outline or s.outline
        if outline == "NONE" then outline = "" end
        local uc = s.tabUnderlineAccent ~= false and { r = A[1], g = A[2], b = A[3] }
                   or s.tabUnderlineColor or { r = 1, g = 1, b = 1 }
        for _, cf in ipairs(list) do
            local name = cf.GetName and cf:GetName()
            local tab = name and _G[name .. "Tab"]
            if tab then
                local g = Ghost(tab)
                seen[g] = true
                if not g.placed then
                    g:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 0, 0)
                    g:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", 0, 0)
                    g.placed = true
                end
                if g.h ~= (s.tabHeight or 22) then g:SetHeight(s.tabHeight or 22) g.h = s.tabHeight or 22 end
                g:SetFrameStrata(tab:GetFrameStrata())
                g:SetFrameLevel(tab:GetFrameLevel() + 5)
                if g.font ~= font or g.size ~= s.tabFontSize or g.outline ~= outline then
                    if font then pcall(g.text.SetFont, g.text, font, s.tabFontSize or 12, outline) end
                    g.font, g.size, g.outline = font, s.tabFontSize, outline
                end
                g.text:SetText(tab:GetText() or "")
                local active = dock and dock.selected == cf
                local glow = tab.glow or _G[name .. "TabGlow"]
                local flash = (not active) and glow and glow:IsShown()
                local tc = s.tabTextColor or { r = 1, g = 1, b = 1 }
                if flash then
                    g.text:SetTextColor(A[1], A[2], A[3], 1)
                else
                    g.text:SetTextColor(tc.r, tc.g, tc.b, active and 1 or (s.tabTextAlpha or 0.65))
                end
                local tb = s.tabBg or { r = 0.03, g = 0.045, b = 0.05 }
                g.bg:SetColorTexture(tb.r, tb.g, tb.b, active and (s.tabBgActiveAlpha or 0) or (s.tabBgAlpha or 0))
                local bc = s.panelBorderColor or { r = 1, g = 1, b = 1 }
                g.edge:SetColor(bc.r, bc.g, bc.b, math.max(0.1, s.panelBorderAlpha or 0.18))
                g.edge:SetShown(active and s.tabActiveEdge == true or false)
                g.line:SetColorTexture(uc.r, uc.g, uc.b, 1)
                g.line:SetShown(active and s.tabUnderline ~= false or false)
                g:SetShown(tab:IsShown())
            end
        end
    end
    for _, g in pairs(look.ghosts) do if not seen[g] then g:Hide() end end
end

-- the input line: its textures to alpha 0, a flat box behind it
local function FlatInput(cf, on)
    local name = cf.GetName and cf:GetName()
    local eb = name and _G[name .. "EditBox"]
    if not eb then return end
    if on then
        for _, r in ipairs({ eb:GetRegions() }) do
            if r.IsObjectType and r:IsObjectType("Texture") and r:GetAlpha() > 0 then
                r:SetAlpha(0)
                look.zeroed[r] = eb
            end
        end
    else
        for r, owner in pairs(look.zeroed) do
            if owner == eb then r:SetAlpha(1) look.zeroed[r] = nil end
        end
    end
    local box = look.boxes[eb]
    if not box and on then
        box = CreateFrame("Frame", nil, UIParent)
        box:EnableMouse(false)
        box:SetPoint("TOPLEFT", eb, "TOPLEFT", 4, -3)
        box:SetPoint("BOTTOMRIGHT", eb, "BOTTOMRIGHT", -4, 3)
        box.bg = ns.UI.Fill(box, 0, 0, 0, 0.7)
        box.border = ns.UI.Border(box, 1, 1, 1, 0.18)
        box:Hide()
        look.boxes[eb] = box
    end
    if box then box.want = on end
end

local function UpdateBoxes()
    local s = S()
    local bc = s.panelBorderColor or { r = 1, g = 1, b = 1 }
    for eb, box in pairs(look.boxes) do
        -- only while typing (the classic chat style keeps the line "shown")
        local show = box.want and PanelOn() and eb:IsShown() and eb.HasFocus and eb:HasFocus() or false
        if show then
            box:SetFrameStrata(eb:GetFrameStrata())
            box:SetFrameLevel(math.max(0, eb:GetFrameLevel() - 1))
            local inside = s.inputPos == "INSIDE_TOP" or s.inputPos == "INSIDE_BOTTOM"
            box.bg:SetColorTexture(s.bgColor.r, s.bgColor.g, s.bgColor.b, inside and 1 or math.max(0.5, s.bgAlpha))
            box.border:SetColor(bc.r, bc.g, bc.b, s.panelBorderAlpha or 0.18)
            box.border:SetShown((s.panelBorderAlpha or 0) > 0)
        end
        box:SetShown(show)
    end
end

-- art made see-through: the game's own fades (the window and its scroll
-- bar fade in under the mouse) change alpha, which then shows nothing.
-- One way: the game's look comes back after /reload.
local cleared = {}
local function SeeThrough(fr)
    if not fr or cleared[fr] then return end
    cleared[fr] = true
    for _, r in ipairs({ fr:GetRegions() }) do
        if r.IsObjectType and r:IsObjectType("Texture") then r:SetAlpha(0) end
    end
    for _, ch in ipairs({ fr:GetChildren() }) do
        SeeThrough(ch)
        if ch.EnableMouse and not InCombatLockdown() then pcall(ch.EnableMouse, ch, false) end
    end
end
-- the window's own background pieces (they fade in under the mouse)
local function WindowArt(cf)
    local name = cf.GetName and cf:GetName()
    if not name or cleared[cf] then return end
    cleared[cf] = true
    for _, v in ipairs(type(_G.CHAT_FRAME_TEXTURES) == "table" and _G.CHAT_FRAME_TEXTURES or {}) do
        local t = _G[name .. v]
        if t and t.SetColorTexture then t:SetColorTexture(0, 0, 0, 0) end
    end
end
Chat.WasPanel = function() return next(cleared) ~= nil end

-- the game's scroll bar and "to the bottom" button inside each window: out
-- of sight with the panel (alpha and mouse only; the wheel still scrolls)
local function ScrollParts(cf, hide)
    local name = cf.GetName and cf:GetName()
    for _, part in ipairs({ cf.ScrollBar, cf.ScrollToBottomButton, name and _G[name .. "ScrollToBottomButton"] }) do
        if part and part.SetAlpha then
            if hide then
                SeeThrough(part)
                if part:GetAlpha() ~= 0 then part:SetAlpha(0) end
                if not look.zeroed[part] and part.EnableMouse and not InCombatLockdown() then
                    pcall(part.EnableMouse, part, false)
                end
                look.zeroed[part] = cf
            elseif look.zeroed[part] then
                part:SetAlpha(1)
                if part.EnableMouse and not InCombatLockdown() then pcall(part.EnableMouse, part, true) end
                look.zeroed[part] = nil
            end
        end
    end
end

-- Blizzard's tab strip: invisible, still clickable (alpha only)
local function StockTabs(hide)
    local gdm = _G.GeneralDockManager
    if not gdm then return end
    if hide then
        if gdm:GetAlpha() ~= 0 then gdm:SetAlpha(0) end
        look.tabsHidden = true
    elseif look.tabsHidden then
        gdm:SetAlpha(1)
        look.tabsHidden = nil
    end
end

-- the whole chat faded (fade option "whole chat"): the panel and its parts
-- and the docked windows
local wholeAlpha = 1
function Chat.SetWholeAlpha(a)
    if a == wholeAlpha then return end
    wholeAlpha = a
    if look.panel then look.panel:SetAlpha(a) end
    for _, g in pairs(look.ghosts) do g:SetAlpha(a) end
    for _, b in pairs(look.boxes) do b:SetAlpha(a) end
    for _, cf in ipairs(Docked()) do pcall(cf.SetAlpha, cf, a) end
    local gdm = _G.GeneralDockManager
    if gdm and not look.tabsHidden then gdm:SetAlpha(a) end
end

local function ApplyPanel()
    local on = PanelOn()
    LayoutPanel()
    StockTabs(on)
    for _, cf in ipairs(Windows()) do
        pcall(FlatInput, cf, on)
        pcall(ScrollParts, cf, on)
    end
    UpdateGhosts()
    UpdateBoxes()
end

C_Timer.NewTicker(0.1, function()
    if not (HUFDB and ns.db) then return end
    if PanelOn() then
        StockTabs(true)
        LayoutPanel()
        for _, cf in ipairs(Docked()) do
            pcall(ScrollParts, cf, true)
            pcall(WindowArt, cf)
        end
        UpdateGhosts()
        UpdateBoxes()
    elseif look.panel and look.panel:IsShown() then
        ApplyPanel()
    end
end)

---------------------------------------------------------------------------
-- Where the main chat window sits (option chat.position: { point, relPoint,
-- x, y, w, h }; nil = where the game / Edit Mode puts it). ChatFrame1 is an
-- Edit Mode system: its own SetPoint / ClearAllPoints are Edit Mode's Lua
-- versions, so the frame type's C methods place it. No SetSize: the size is
-- a second anchor. Checked again after Edit Mode layouts and every second
-- (Edit Mode puts it back on its own spot when it applies a layout).
---------------------------------------------------------------------------
local raw = getmetatable(CreateFrame("Frame")).__index
local function EditModeOpen()
    local em = _G.EditModeManagerFrame
    return em and em.IsShown and em:IsShown() or false
end
local function PlaceChat()
    local s = S()
    local pos = s.enabled and s.position
    local cf = ChatFrame1
    if not (type(pos) == "table" and pos.point and cf) or InCombatLockdown() or EditModeOpen() then return end
    local x, y = pos.x or 0, pos.y or 0
    local sized = pos.w and pos.h and pos.point == "BOTTOMLEFT" and pos.relPoint == "BOTTOMLEFT"
    local n = cf:GetNumPoints()
    local p, rel, rp, px, py = cf:GetPoint(1)
    if n == (sized and 2 or 1) and p == pos.point and rel == UIParent and rp == (pos.relPoint or pos.point)
       and math.abs((px or 0) - x) < 0.5 and math.abs((py or 0) - y) < 0.5 then
        return
    end
    raw.ClearAllPoints(cf)
    raw.SetPoint(cf, pos.point, UIParent, pos.relPoint or pos.point, x, y)
    if sized then raw.SetPoint(cf, "TOPRIGHT", UIParent, "BOTTOMLEFT", x + pos.w, y + pos.h) end
end
Chat.PlaceChat = PlaceChat

-- the settings' buttons: keep the chat where it is now / back to the game's
function Chat.KeepPosition()
    local cf = ChatFrame1
    if not cf then return end
    local l, b, w, h = cf:GetLeft(), cf:GetBottom(), cf:GetWidth(), cf:GetHeight()
    if not (l and b) then return end
    S().position = { point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT",
                     x = math.floor(l + 0.5), y = math.floor(b + 0.5),
                     w = math.floor(w + 0.5), h = math.floor(h + 0.5) }
    PlaceChat()
end
function Chat.GamePosition()
    S().position = nil
    ns.AskReload("The chat goes back to the game's (Edit Mode) place after a reload.")
end

-- unlock mode: a box over the chat window to drag it (snaps like the rest);
-- the drop is kept as the chat's place
local chatMover
function Chat.SetUnlocked(on)
    local cf = ChatFrame1
    if not cf then return end
    if not chatMover then
        local m = CreateFrame("Button", nil, UIParent)
        m:SetFrameStrata("DIALOG")
        m:SetMovable(true)
        m:SetClampedToScreen(true)
        m:EnableMouse(true)
        m:RegisterForDrag("LeftButton")
        m:RegisterForClicks("RightButtonUp")
        ns.UI.Fill(m, A[1], A[2], A[3], 0.15)
        ns.UI.Border(m, A[1], A[2], A[3], 0.8)
        m.label = m:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        m.label:SetPoint("CENTER")
        m.label:SetText("Chat")
        m:SetScript("OnDragStart", function(self)
            if InCombatLockdown() then return end
            self.from = { self:GetLeft(), self:GetBottom() }
            ns.Snap.StartDrag(self)
        end)
        m:SetScript("OnDragStop", function(self)
            ns.Snap.StopDrag(self)
            local from = self.from
            self.from = nil
            local k = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
            local l, b = self:GetLeft(), self:GetBottom()
            local cl, cb = cf:GetLeft(), cf:GetBottom()
            if from and from[1] and l and b and cl and cb then
                -- the box covers the panel and its strip: the chat window moves by as much
                local dx, dy = (l - from[1]) * k, (b - from[2]) * k
                S().position = { point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT",
                                 x = math.floor(cl + dx + 0.5), y = math.floor(cb + dy + 0.5),
                                 w = math.floor(cf:GetWidth() + 0.5), h = math.floor(cf:GetHeight() + 0.5) }
                PlaceChat()
            end
            C_Timer.After(0, function() Chat.SetUnlocked(ns.unlocked) end)
        end)
        m:SetScript("OnClick", function() if ns.ToggleConfig then ns.ToggleConfig("chat", true) end end)
        if ns.Snap then ns.Snap.Register(m) end
        chatMover = m
    end
    chatMover:ClearAllPoints()
    -- what you see: the panel and its button strip (panel look), else the window
    local panel = PanelOn() and look.panel
    if panel and panel:IsShown() then
        local st = bar and bar.strip and bar.strip:IsShown() and bar.strip
        local L, R = panel, panel
        if st then
            if S().buttonSide == "LEFT" then L = st else R = st end
        end
        chatMover:SetPoint("TOPLEFT", L, "TOPLEFT")
        chatMover:SetPoint("BOTTOMRIGHT", R, "BOTTOMRIGHT")
    else
        chatMover:SetAllPoints(cf)
    end
    chatMover:SetShown(on and S().enabled and true or false)
end

ns.On("EDIT_MODE_LAYOUTS_UPDATED", function() C_Timer.After(0, PlaceChat) end)
ns.On("PLAYER_ENTERING_WORLD", function() C_Timer.After(1, PlaceChat) end)
C_Timer.NewTicker(1, function() if HUFDB and ns.db then PlaceChat() end end)

---------------------------------------------------------------------------
-- Apply
---------------------------------------------------------------------------
function Chat.Apply(full)
    if not (HUFDB and ns.db) then return end
    local s = S()
    for _, cf in ipairs(Windows()) do
        Hook(cf)
        if s.enabled then
            ApplyLook(cf)
            if full or PanelOn() then ApplyBackground(cf) end
            if s.hideStock then pcall(HideStock, cf) end
        end
        pcall(PlaceInput, cf)
    end
    if s.enabled and s.hideStock then pcall(HideSocial) end
    ApplyPanel()
    LayoutBar()
    PlaceChat()
end

function Chat.Report(add)
    local s = S()
    local n = 0
    for _ in pairs(hooked) do n = n + 1 end
    local st = HUFDB.chatHistory and HUFDB.chatHistory[ns.CharKey()] or {}
    local lines = 0
    for _, l in pairs(st) do lines = lines + #l end
    add(("chat: enabled=%s windows=%d abbreviate=%s urls=%s history=%s (%d stored) classColors=%s buttons=%s"):format(
        tostring(s.enabled), n, tostring(s.abbreviate), tostring(s.urls), tostring(s.history), lines,
        tostring(s.classColors), tostring(bar and bar:IsShown())))
end

-- people writing wake the chat up (the fading)
for _, e in ipairs({ "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_WHISPER", "CHAT_MSG_BN_WHISPER", "CHAT_MSG_PARTY",
                     "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING",
                     "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER" }) do
    pcall(ns.On, e, function() Chat.Wake() end)
end

ns.OnLogin(function()
    local s = S()
    -- timestamps from an import: the game's own setting, written once
    if s.timestamps then
        local set = C_CVar and C_CVar.SetCVar or SetCVar
        if set then pcall(set, "showTimestamps", s.timestamps) end
        s.timestamps = nil
    end
    Chat.Apply(true)
    if s.enabled and s.classColors then Chat.ApplyClassColors(true) end
    if s.enabled then Chat.Restore() end
    if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) elseif GuildRoster then pcall(GuildRoster) end
end)
ns.OnRefresh(function() if HUFDB and ns.db then Chat.Apply(true) end end)
ns.On("UPDATE_CHAT_WINDOWS", function() if HUFDB and ns.db then Chat.Apply(false) end end)
ns.On("UPDATE_FLOATING_CHAT_WINDOWS", function() if HUFDB and ns.db then Chat.Apply(false) end end)
ns.On("GUILD_ROSTER_UPDATE", function() Chat.UpdateGuildCount() end)
ns.On("PLAYER_GUILD_UPDATE", function() if HUFDB and ns.db then LayoutBar() end end)
-- whisper windows open later: hook them as they appear
C_Timer.NewTicker(5, function()
    if not (HUFDB and ns.db) then return end
    for _, cf in ipairs(Windows()) do
        if not hooked[cf] then
            Hook(cf)
            if S().enabled then ApplyLook(cf) end
            pcall(PlaceInput, cf)
        end
    end
    if IsInGuild and IsInGuild() and not Chat.rosterAsked then
        Chat.rosterAsked = true
        C_Timer.After(60, function() Chat.rosterAsked = nil end)
        if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end
    end
end)
