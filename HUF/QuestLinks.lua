-- HUF: clickable quest links in chat (Utility Frames > Quest Log,
-- "Clickable Quest-Links in Chat") and linking quests from the quest log.
--
-- Formats (the same ones Questie uses, so links work both ways):
--   * the game's own quest link |Hquest:<id>:<level>|h[Title]|h - every
--     client can receive it; HUF sends this one (GetQuestLink),
--   * Questie's plain text "[[<level>] Title (<id>)]" / "[Title (<id>)]" -
--     sent when the game gives no link (a quest not in your log); Questie
--     users and HUF users turn it into a link.
-- Incoming chat lines: a message event filter gives quest links the quest
-- difficulty colour, the level and a small quest icon, and turns Questie's
-- plain text into a link. A click opens HUF's quest window (title, status,
-- description, objectives; with Questie: who starts / ends it, where).
-- Clicks come through LinkUtil.RegisterLinkHandler (as Questie does on
-- Forever): replacing ItemRefTooltip:SetHyperlink taints every link click.
-- A link type takes only one handler: with Questie on for this character, its own
-- handler for "quest" / "questie" stays (HUF registering first made Questie's
-- registration fail: "attempted to register a duplicate link handler for 'quest'"),
-- so clicks open Questie's tooltip; the colours, levels and plain-text links stay HUF's.
-- Modified clicks (shift: link again, ctrl) stay the game's.

local _, ns = ...
local UI = ns.UI

local QK = {}
ns.QuestLinks = QK

local QUEST_ICON = "|TInterface\\GossipFrame\\AvailableQuestIcon:0:0:0:0|t"
local CQ = C_QuestLog or {}

local function On() return ns.db and ns.db.questLog.chatLinks ~= false end

local function Safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local r = { pcall(fn, ...) }
    if r[1] then return unpack(r, 2) end
end

local function Hex(c) return ("|cff%02x%02x%02x"):format(math.floor(c.r * 255), math.floor(c.g * 255), math.floor(c.b * 255)) end
local function LevelHex(level)
    local c = (tonumber(level) or 0) > 0 and ns.LevelColor and ns.LevelColor(tonumber(level))
    return c and Hex(c) or "|cffffd100"
end

---------------------------------------------------------------------------
-- Questie (General > Addon Support: "Use Questie's quest data")
---------------------------------------------------------------------------
local function QuestieReady()
    if ns.db and ns.db.global.questie == false then return false end
    return type(_G.QuestieLoader) == "table" and type(_G.Questie) == "table" and _G.Questie.started and true or false
end
QK.QuestieLoaded = function()
    local IsLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
    return (IsLoaded and IsLoaded("Questie")) and true or false
end
local function Module(name)
    local ok, m = pcall(_G.QuestieLoader.ImportModule, _G.QuestieLoader, name)
    return ok and m or nil
end
-- { name, level, minLevel, desc = {lines}, objectives = {texts}, starter, starterZone, finisher, finisherZone, zone }
local function QuestieData(id)
    if not QuestieReady() then return nil end
    local DB = Module("QuestieDB")
    if not (DB and DB.GetQuest) then return nil end
    local ok, q = pcall(DB.GetQuest, id)
    if not ok or type(q) ~= "table" then return nil end
    local TU = Module("TrackerUtils")
    local function Zone(zid)
        if not (TU and TU.GetZoneNameByID and zid and zid ~= 0) then return nil end
        local okz, n = pcall(TU.GetZoneNameByID, TU, zid)
        return okz and n or nil
    end
    local function Who(t)
        if type(t) ~= "table" then return nil end
        local function From(getter, ids)
            if type(ids) ~= "table" or not ids[1] or not (DB[getter]) then return nil end
            local okn, o = pcall(DB[getter], DB, ids[1])
            if okn and type(o) == "table" then return o.name, Zone(o.zoneID) end
        end
        local n, z = From("GetNPC", t.NPC)
        if not n then n, z = From("GetObject", t.GameObject) end
        if not n then n, z = From("GetItem", t.Item) end
        return n, z or Zone(q.zoneOrSort)
    end
    local d = { name = q.name, level = q.level, minLevel = q.requiredLevel, desc = {}, objectives = {} }
    local Lib = Module("QuestieLib")
    if Lib and Lib.GetEffectiveQuestLevel then
        local okl, lv = pcall(Lib.GetEffectiveQuestLevel, id)
        if okl and tonumber(lv) then d.level = lv end
    end
    if type(q.Description) == "table" then
        for _, line in ipairs(q.Description) do if type(line) == "string" and line ~= "" then d.desc[#d.desc + 1] = line end end
    end
    if type(q.ObjectiveData) == "table" then
        for _, o in ipairs(q.ObjectiveData) do
            if type(o) == "table" and type(o.Text) == "string" then d.objectives[#d.objectives + 1] = o.Text end
        end
    end
    d.starter, d.starterZone = Who(q.Starts)
    d.finisher, d.finisherZone = Who(q.Finisher)
    if q.zoneOrSort and q.zoneOrSort > 0 then d.zone = Zone(q.zoneOrSort) end
    return d
end

---------------------------------------------------------------------------
-- Linking a quest into chat
---------------------------------------------------------------------------
local function LogInfo(id)
    local idx = CQ.GetLogIndexForQuestID and Safe(CQ.GetLogIndexForQuestID, id)
    local info = idx and CQ.GetInfo and Safe(CQ.GetInfo, idx)
    return type(info) == "table" and info or nil, idx
end

-- the text to put into the chat line for a quest
function QK.LinkText(id, title, level)
    id = tonumber(id)
    if not id then return nil end
    local link = Safe(_G.GetQuestLink, id)
    if type(link) == "string" and link:find("|Hquest:") then return link end
    local info = LogInfo(id)
    title = title or (info and info.title) or Safe(CQ.GetTitleForQuestID, id)
    level = level or (info and info.level)
    if not title then
        local q = QuestieData(id)
        title, level = q and q.name, level or (q and q.level)
    end
    if not title then return nil end
    -- Questie's plain format: Questie and HUF users turn it into a link
    if tonumber(level) and tonumber(level) > 0 then
        return ("[[%d] %s (%d)]"):format(level, title, id)
    end
    return ("[%s (%d)]"):format(title, id)
end

-- into the chat line being typed (or a new one)
function QK.Insert(id, title, level)
    local text = QK.LinkText(id, title, level)
    if not text then return false end
    if ChatEdit_InsertLink and ChatEdit_InsertLink(text) then return true end
    if ChatFrame_OpenChat then ChatFrame_OpenChat(text) return true end
    return false
end
function QK.Typing()
    return ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow() and true or false
end

---------------------------------------------------------------------------
-- Incoming chat lines
---------------------------------------------------------------------------
local function Styled(id, level, title)
    local lv = tonumber(level) or 0
    if lv <= 0 then
        local info = LogInfo(tonumber(id))
        lv = info and info.level or 0
        if lv <= 0 then
            local q = QuestieData(tonumber(id))
            lv = q and tonumber(q.level) or 0
        end
    end
    local shown = title
    if lv > 0 and not title:find("^%[%d") then shown = ("[%d] %s"):format(lv, title) end
    return ("%s%s|Hquest:%s:%d|h[%s]|h|r"):format(QUEST_ICON, LevelHex(lv), id, lv, shown)
end

local function Transform(msg)
    -- the game's links (any colour code before them)
    msg = msg:gsub("|c%x%x%x%x%x%x%x%x|Hquest:(%d+):(%-?%d+)([^|]*)|h%[(.-)%]|h|r", function(id, level, _, title)
        return Styled(id, level, title)
    end)
    -- Questie's plain text, outside links: [[38] Title (1234)] and [Title (1234)]
    msg = msg:gsub("%[%[(%d+)[^%]]-%] ([^%[%]|]-) %((%d+)%)%]", function(level, title, id)
        return Styled(id, level, title)
    end)
    msg = msg:gsub("%[([^%[%]|]-) %((%d+)%)%]", function(title, id)
        return Styled(id, 0, title)
    end)
    return msg
end
QK.Transform = Transform

local function Filter(_, _, msg, ...)
    if not On() or type(msg) ~= "string" or ns.IsSecret(msg) then return false end
    if not (msg:find("|Hquest:", 1, true) or msg:find("%(%d+%)%]")) then return false end
    local ok, out = pcall(Transform, msg)
    if not ok then ns.LogError("questlinks", out) return false end
    if out == msg then return false end
    return false, out, ...
end

local EVENTS = {
    "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
    "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER", "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM",
    "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM", "CHAT_MSG_CHANNEL",
}

---------------------------------------------------------------------------
-- The quest window
---------------------------------------------------------------------------
local win, shownID, shownLevel, shownTitle
local W, PAD = 330, 10

local function Status(id)
    local on = CQ.IsOnQuest and Safe(CQ.IsOnQuest, id)
    if on then
        if CQ.IsComplete and Safe(CQ.IsComplete, id) then return "|cff40ff40You are on this quest: ready to turn in.|r" end
        return "|cff40ff40You are on this quest.|r"
    end
    if CQ.IsQuestFlaggedCompleted and Safe(CQ.IsQuestFlaggedCompleted, id) then
        return "|cff40ff40You have completed this quest.|r"
    end
    return "|cffffd100You have not done this quest.|r"
end

-- description and objectives of a quest in your log (needs it selected)
local function LogTexts(id)
    local _, idx = LogInfo(id)
    if not idx then return nil end
    local before = CQ.GetSelectedQuest and Safe(CQ.GetSelectedQuest)
    if CQ.SetSelectedQuest then Safe(CQ.SetSelectedQuest, id) end
    local desc, obj = Safe(GetQuestLogQuestText, idx)
    if not desc then desc, obj = Safe(GetQuestLogQuestText) end
    if before and CQ.SetSelectedQuest then Safe(CQ.SetSelectedQuest, before) end
    return desc, obj
end

local function Objectives(id)
    local list = {}
    local objs = CQ.GetQuestObjectives and Safe(CQ.GetQuestObjectives, id)
    if type(objs) == "table" then
        for _, o in ipairs(objs) do
            if type(o) == "table" and type(o.text) == "string" and o.text ~= "" then
                list[#list + 1] = (o.finished and "|cff9d9d9d" or "|cffffffff") .. "- " .. o.text .. "|r"
            end
        end
    end
    return list
end

-- the game's quest tooltip lines (first line = the title), as a fallback text
local function TooltipLines(id, level)
    local data = C_TooltipInfo and C_TooltipInfo.GetHyperlink and Safe(C_TooltipInfo.GetHyperlink, ("quest:%d:%d"):format(id, tonumber(level) or 0))
    local out = {}
    if type(data) == "table" and type(data.lines) == "table" then
        for i = 2, #data.lines do
            local t = data.lines[i].leftText
            if type(t) == "string" and t ~= "" and not ns.IsSecret(t) then out[#out + 1] = t end
        end
    end
    return out
end

local function Build()
    win = CreateFrame("Frame", "HUF_QuestLinkWindow", UIParent)
    win:SetSize(W, 200)
    win:SetPoint("CENTER", 0, 80)
    win:SetFrameStrata("DIALOG")
    win:SetToplevel(true)
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:SetMovable(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    UI.Fill(win, 0.05, 0.05, 0.06, 0.96)
    local A = UI.ACCENT
    UI.Border(win, A[1], A[2], A[3], 0.9)
    win.title = win:CreateFontString(nil, "OVERLAY")
    ns.ApplyFont(win.title, "GLOBAL", 15, "GLOBAL")
    win.title:SetPoint("TOPLEFT", PAD, -PAD)
    win.title:SetPoint("TOPRIGHT", -34, -PAD)
    win.title:SetJustifyH("LEFT")
    win.title:SetWordWrap(true)
    local close = UI.Button(win, 22, "x", function() win:Hide() end)
    close:SetPoint("TOPRIGHT", -6, -6)
    win.body = win:CreateFontString(nil, "OVERLAY")
    ns.ApplyFont(win.body, "GLOBAL", 12, "GLOBAL")
    win.body:SetPoint("TOPLEFT", win.title, "BOTTOMLEFT", 0, -6)
    win.body:SetWidth(W - 2 * PAD)
    win.body:SetJustifyH("LEFT")
    win.body:SetJustifyV("TOP")
    win.body:SetWordWrap(true)
    win.body:SetSpacing(2)
    local bw = (W - 2 * PAD - 8) / 2
    win.link = UI.Button(win, bw, "Link in chat", function() if shownID then QK.Insert(shownID, shownTitle, shownLevel) end end)
    win.link:SetPoint("BOTTOMLEFT", PAD, PAD)
    UI.Tooltip(win.link, "Link in chat", "Puts the quest into the chat line you are typing (or opens one).")
    win.open = UI.Button(win, bw, "Open in quest log", function()
        if not shownID then return end
        if ns.QuestLog and ns.QuestLog.IsEnabled() then ns.QuestLog.Show(shownID)
        elseif QuestMapFrame_OpenToQuestDetails then pcall(QuestMapFrame_OpenToQuestDetails, shownID) end
    end)
    win.open:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    win.source = win:CreateFontString(nil, "OVERLAY")
    ns.ApplyFont(win.source, "GLOBAL", 10, "GLOBAL")
    win.source:SetPoint("BOTTOMLEFT", win.link, "TOPLEFT", 0, 4)
    win.source:SetTextColor(0.55, 0.55, 0.55)
    UI.CloseOnEscape(win)
    win:Hide()
end

local function Section(lines, head, list)
    if not list or #list == 0 then return end
    lines[#lines + 1] = " "
    lines[#lines + 1] = "|cffffd100" .. head .. "|r"
    for _, l in ipairs(list) do lines[#lines + 1] = l end
end

local function Draw()
    if not (win and shownID) then return end
    local id = shownID
    local info = LogInfo(id)
    local q = QuestieData(id)
    local title = (info and info.title) or Safe(CQ.GetTitleForQuestID, id) or (q and q.name) or shownTitle or ("Quest " .. id)
    local level = (info and info.level) or tonumber(shownLevel)
    if not level or level <= 0 then level = q and tonumber(q.level) or 0 end
    shownTitle, shownLevel = title, level

    local tags = {}
    if ns.QuestLog and ns.QuestLog.IsElite and ns.QuestLog.IsElite(id) then tags[#tags + 1] = "Elite" end
    if info and (info.suggestedGroup or 0) > 1 then tags[#tags + 1] = "Group " .. info.suggestedGroup end
    win.title:SetText(("%s%s%s|r%s"):format(LevelHex(level), level > 0 and ("[" .. level .. "] ") or "", title,
        #tags > 0 and ("  |cff9d9d9d" .. table.concat(tags, ", ") .. "|r") or ""))

    local lines = { Status(id) }
    if q and tonumber(q.minLevel) and q.minLevel > 0 then lines[#lines + 1] = "|cff9d9d9dRequires level " .. q.minLevel .. "|r" end
    -- the text: your log, else Questie, else the game's tooltip
    local desc, objText = LogTexts(id)
    local descList = {}
    if desc and desc ~= "" then descList[1] = "|cffffffff" .. desc .. "|r"
    elseif q and #q.desc > 0 then for _, l in ipairs(q.desc) do descList[#descList + 1] = "|cffffffff" .. l .. "|r" end end
    local objs = Objectives(id)
    if #objs == 0 and q then for _, o in ipairs(q.objectives) do objs[#objs + 1] = "|cffffffff- " .. o .. "|r" end end
    if objText and objText ~= "" then table.insert(objs, 1, "|cffdddddd" .. objText .. "|r") end
    if #descList == 0 and #objs == 0 then
        for _, l in ipairs(TooltipLines(id, level)) do objs[#objs + 1] = "|cffffffff" .. l .. "|r" end
    end
    Section(lines, "Objectives", objs)
    Section(lines, "Description", descList)
    if q then
        local who = {}
        if q.starter then who[#who + 1] = "Started by: |cffffffff" .. q.starter .. "|r" .. (q.starterZone and (" (" .. q.starterZone .. ")") or "") end
        if q.finisher then who[#who + 1] = "Ended by: |cffffffff" .. q.finisher .. "|r" .. (q.finisherZone and (" (" .. q.finisherZone .. ")") or "") end
        Section(lines, "Where", who)
    end
    if #objs == 0 and #descList == 0 and not q then
        lines[#lines + 1] = " "
        lines[#lines + 1] = "|cff9d9d9dNo details yet: the game is still loading this quest.|r"
    end
    win.body:SetText(table.concat(lines, "\n"))
    win.source:SetText(q and "Quest data: Questie" or "")
    UI.SetActive(win.open, info ~= nil)
    local h = PAD + win.title:GetStringHeight() + 6 + win.body:GetStringHeight() + 14 + (q and 14 or 0) + 22 + PAD
    win:SetHeight(math.min(math.max(h, 120), 600))
end

function QK.Show(id, level, title)
    id = tonumber(id)
    if not id then return end
    if not win then Build() end
    if win:IsShown() and shownID == id then win:Hide() return end   -- a second click closes it
    shownID, shownLevel, shownTitle = id, level, title
    if CQ.RequestLoadQuestByID and not (Safe(_G.HaveQuestData, id)) then Safe(CQ.RequestLoadQuestByID, id) end
    Draw()
    win:Show()
end

---------------------------------------------------------------------------
-- Clicks
---------------------------------------------------------------------------
local function ParseLink(link)
    if type(link) ~= "string" then return nil end
    local id, level = link:match("^quest:(%d+):?(%-?%d*)")
    if not id then id = link:match("^questie:(%d+)") end
    return tonumber(id), tonumber(level)
end

local function Handler(link, text)
    local LPR = _G.LinkProcessorResponse or {}
    if not On() or IsModifiedClick() then return LPR.Unhandled end
    local id, level = ParseLink(link)
    if not id then return LPR.Unhandled end
    local title = type(text) == "string" and not ns.IsSecret(text) and text:match("%[(.-)%]|h") or nil
    if title then title = title:gsub("^%[%d+%+?%] ", "") end
    QK.Show(id, level, title)
    return LPR.Handled
end

-- Questie switched on for this character (it loads after HUF, so not loaded yet here)
local function QuestieEnabled()
    if QK.QuestieLoaded() then return true end
    local A = C_AddOns or {}
    local GetState = A.GetAddOnEnableState or GetAddOnEnableState
    if not GetState then return false end
    local who = UnitName and UnitName("player")
    -- C_AddOns takes (addon, character), the old global (character, addon): ask both ways
    local ok1, a = pcall(GetState, "Questie", who)
    local ok2, b = pcall(GetState, who, "Questie")
    a = ok1 and tonumber(a) or 0
    b = ok2 and tonumber(b) or 0
    return math.max(a, b) > 0
end

local installed = false
local function Install()
    if installed then return end
    installed = true
    for _, ev in ipairs(EVENTS) do
        if ChatFrame_AddMessageEventFilter then ChatFrame_AddMessageEventFilter(ev, Filter) end
    end
    if QuestieEnabled() then
        QK.path = "Questie"   -- its link handler takes the clicks
    elseif LinkUtil and LinkUtil.RegisterLinkHandler and _G.LinkProcessorResponse then
        LinkUtil.RegisterLinkHandler("quest", Handler)
        LinkUtil.RegisterLinkHandler("questie", Handler)
        QK.path = "LinkUtil"
    else
        -- older clients: after the game's own handling (its tooltip shows too)
        hooksecurefunc("SetItemRef", function(link, text)
            if not On() or IsModifiedClick() then return end
            local id, level = ParseLink(link)
            if not id then return end
            if ItemRefTooltip and ItemRefTooltip:IsShown() then ItemRefTooltip:Hide() end
            QK.Show(id, level)
        end)
        QK.path = "SetItemRef"
    end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:SetScript("OnEvent", function(self, event, arg)
    if event == "ADDON_LOADED" and arg == "HUF" then
        Install()
        pcall(self.RegisterEvent, self, "QUEST_DATA_LOAD_RESULT")
        pcall(self.RegisterEvent, self, "QUEST_LOG_UPDATE")
    elseif event == "QUEST_DATA_LOAD_RESULT" then
        if win and win:IsShown() and tonumber(arg) == shownID then Draw() end
    elseif event == "QUEST_LOG_UPDATE" then
        if win and win:IsShown() then Draw() end
    end
end)

function QK.Report(add)
    add(("quest links: on=%s path=%s questie loaded=%s used=%s"):format(tostring(On()), tostring(QK.path),
        tostring(QK.QuestieLoaded()), tostring(QuestieReady())))
end
