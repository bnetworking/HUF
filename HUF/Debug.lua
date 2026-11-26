-- HUF: debug log and report.
--
-- With the debug log on (Help page or /huf debug), HUF writes what it does
-- into a log: frames made and applied, units assigned, shown / hidden,
-- clicks, setting changes, combat queue, Blizzard frames hidden, MMT link,
-- aura access. Errors and blocked actions are always logged (and announced
-- once in chat). The report (/huf debug report) puts client, settings, the
-- state of every frame and the log into one copyable text.

local _, ns = ...
local IsSecret = ns.IsSecret

local MAX_LINES = 1500           -- kept lines (survive /reload)
local TRIM_STEP = 100            -- the oldest lines go in blocks, not one by one
local MAX_LINE_LEN = 900         -- a longer line is cut (recorder snapshots)
local VIEW_LINES = 400           -- the log window shows the newest lines
local REPORT_LINES = 600         -- the report's log part
local early = {}                 -- lines before the saved variables are loaded

local function DB()
    if not HUFDB then return nil end
    HUFDB.debug = HUFDB.debug or { enabled = false, chat = false, log = {} }
    HUFDB.debug.log = HUFDB.debug.log or {}
    return HUFDB.debug
end

function ns.DebugOn()
    local d = DB()
    return d and d.enabled or false
end

-- plain text for anything (secret values never reach string code)
local function Str(v)
    if IsSecret(v) then return "<secret>" end
    local t = type(v)
    if t == "string" then return v end
    if t == "number" then
        if v == math.floor(v) then return tostring(v) end
        return ("%.2f"):format(v)
    end
    if t == "table" and v.GetName then
        local ok, n = pcall(v.GetName, v)
        return (ok and n and not IsSecret(n)) and n or "<frame>"
    end
    return tostring(v)
end
ns.DebugStr = Str

-- wall clock seconds + milliseconds from one base, so lines never go back
local baseTime, baseUp
local function Stamp()
    local up = GetTime()
    if not baseTime then baseTime, baseUp = time(), up end
    local t = baseTime + (up - baseUp)
    return date("%H:%M:%S", math.floor(t)) .. (".%03d"):format(math.floor((t % 1) * 1000))
end

-- the same line again right after itself: one line with "(xN)"
local lastText, lastCount = nil, 0
local function Add(text)
    if #text > MAX_LINE_LEN then text = text:sub(1, MAX_LINE_LEN) .. (" ...(+%d)"):format(#text - MAX_LINE_LEN) end
    local d = DB()
    if not d then
        early[#early + 1] = Stamp() .. " " .. text
        return
    end
    local log = d.log
    if text == lastText and #log > 0 then
        lastCount = lastCount + 1
        log[#log] = ("%s %s (x%d)"):format(Stamp(), text, lastCount)
        return
    end
    lastText, lastCount = text, 1
    local line = Stamp() .. " " .. text
    log[#log + 1] = line
    local n = #log
    if n > MAX_LINES + TRIM_STEP then
        -- (the game's Lua 5.1 has no table.move: copy by hand)
        local drop = n - MAX_LINES
        for i = 1, MAX_LINES do log[i] = log[i + drop] end
        for i = n, MAX_LINES + 1, -1 do log[i] = nil end
    end
    if d.chat then DEFAULT_CHAT_FRAME:AddMessage("|cff888888HUF " .. line .. "|r") end
end

local args = {}
local function Format(fmt, ...)
    local n = select("#", ...)
    for i = 1, n do args[i] = Str((select(i, ...))) end
    local ok, msg = pcall(string.format, fmt, unpack(args, 1, n))
    for i = 1, n do args[i] = nil end
    if not ok then return tostring(fmt) end
    return msg
end

-- category: short word ("frame", "unit", "click", "config", ...)
function ns.Log(category, fmt, ...)
    if not ns.DebugOn() then return end
    Add("[" .. category .. "] " .. Format(fmt, ...))
end
-- a line that is written whether the debug log is on or not (the recorder)
function ns.LogRaw(category, text)
    Add("[" .. category .. "] " .. text)
end

-- only when the text differs from the last one under the same key
-- (states that are re-checked often: instance names, dispel types ...)
local lastByKey = {}
function ns.LogChanged(key, category, fmt, ...)
    if not ns.DebugOn() then return end
    local msg = Format(fmt, ...)
    if lastByKey[key] == msg then return end
    lastByKey[key] = msg
    Add("[" .. category .. "] " .. msg)
end

-- parts written in the same moment become one line ("; " between them),
-- e.g. every frame's new unit after a group change
local batches, batchOrder, batchQueued = {}, {}, false
local function FlushBatches()
    batchQueued = false
    for _, cat in ipairs(batchOrder) do
        local parts = batches[cat]
        if parts and #parts > 0 then Add("[" .. cat .. "] " .. table.concat(parts, "; ")) end
        batches[cat] = nil
    end
    wipe(batchOrder)
end
function ns.LogBatch(category, fmt, ...)
    if not ns.DebugOn() then return end
    local parts = batches[category]
    if not parts then
        parts = {}
        batches[category] = parts
        batchOrder[#batchOrder + 1] = category
    end
    parts[#parts + 1] = Format(fmt, ...)
    if not batchQueued then
        batchQueued = true
        C_Timer.After(0, FlushBatches)
    end
end
-- older name used all over the code
function ns.Debug(fmt, ...) ns.Log("debug", fmt, ...) end

local announced = {}
-- errors: always logged, announced in chat once per message
function ns.LogError(where, err)
    local msg = Str(err)
    Add("[ERROR] " .. where .. ": " .. msg)
    local key = where .. msg
    if not announced[key] then
        announced[key] = true
        ns.Print("|cffff5555error|r in %s: %s", where, msg)
        ns.Print("Please send me a debug report: /huf help (or /huf debug report).")
    end
end

-- calls fn; an error is logged instead of breaking the caller
function ns.Try(where, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then ns.LogError(where, err) end
    return ok
end

function ns.ClearLog()
    local d = DB()
    if d then d.log = {} end
    announced = {}
    lastText, lastCount = nil, 0
    wipe(lastByKey)
end

function ns.SetDebug(on)
    local d = DB()
    if not d then return end
    d.enabled = on and true or false
    Add("[debug] log " .. (d.enabled and "on" or "off") .. ", HUF " .. ns.version)
    if d.enabled then ns.Log("debug", "client %s", table.concat({ GetBuildInfo() }, " ")) end
end

ns.On("ADDON_LOADED", function(name)
    if name ~= ns.name then return end
    local d = DB()
    for _, line in ipairs(early) do d.log[#d.log + 1] = line end
    early = {}
end)

-- blocked secure actions (HUF touched something protected in combat)
local function Blocked(event, addon, func)
    if addon == ns.name then ns.LogError(event, Str(func)) end
end
ns.On("ADDON_ACTION_BLOCKED", function(addon, func) Blocked("ADDON_ACTION_BLOCKED", addon, func) end)
ns.On("ADDON_ACTION_FORBIDDEN", function(addon, func) Blocked("ADDON_ACTION_FORBIDDEN", addon, func) end)

-- the game's own events, for the order things happened in
-- (with the data recorder on, its own lines name these moments: no second line)
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED", "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "UNIT_PET", "ZONE_CHANGED_NEW_AREA" }) do
    ns.On(e, function(a1)
        if ns.Recorder and ns.Recorder.IsOn and ns.Recorder.IsOn() and e ~= "UNIT_PET" then return end
        ns.LogBatch("event", "%s%s", e, a1 and (" " .. Str(a1)) or "")
    end)
end

---------------------------------------------------------------------------
-- Report
---------------------------------------------------------------------------
local function FramePoint(f)
    local ok, p, rel, rp, x, y = pcall(f.GetPoint, f, 1)
    if not ok or not p then return "no point" end
    return ("%s %s %s %s,%s"):format(Str(p), Str(rel or "UIParent"), Str(rp), Str(x), Str(y))
end

local function FrameLine(f, label)
    if not f then return label .. ": not made" end
    local function G(m, ...) local ok, v = pcall(f[m], f, ...) if ok then return Str(v) end return "?" end
    local parent = f:GetParent()
    return ("%s: shown=%s visible=%s alpha=%s effAlpha=%s scale=%s size=%sx%s strata=%s level=%s protected=%s parent=%s(%s) point=[%s]"):format(
        label, G("IsShown"), G("IsVisible"), G("GetAlpha"), G("GetEffectiveAlpha"), G("GetScale"),
        G("GetWidth"), G("GetHeight"), G("GetFrameStrata"), G("GetFrameLevel"), G("IsProtected"),
        Str(parent), parent and Str(parent:IsVisible()) or "-", FramePoint(f))
end

local function UnitLine(f)
    local unitAttr = f.GetAttribute and f:GetAttribute("unit")
    local u = f.hunit
    local exists = "-"
    if u then
        local ok, v = pcall(UnitExists, u)
        exists = ok and Str(v) or "?"
    end
    local texts = {}
    for _, which in ipairs({ "health", "power" }) do
        local bar = f.bars and f.bars[which]
        for _, a in ipairs(ns.ANCHORS) do
            local fs = bar and bar.texts[a]
            if fs and fs:IsShown() then
                local ok, t = pcall(fs.GetText, fs)
                texts[#texts + 1] = which .. "." .. a .. "='" .. (ok and Str(t) or "?") .. "'"
            end
        end
    end
    return ("    unit attr=%s hunit=%s exists=%s driver=%s hasPower=%s %s"):format(
        Str(unitAttr), Str(u), exists, Str(f.hufWatch), Str(f.hasPower), table.concat(texts, " "))
end

local function Addons()
    local A = C_AddOns or {}
    local num = A.GetNumAddOns or GetNumAddOns
    local info = A.GetAddOnInfo or GetAddOnInfo
    local loaded = A.IsAddOnLoaded or IsAddOnLoaded
    if not (num and info and loaded) then return "?" end
    local list = {}
    for i = 1, num() do
        local name = info(i)
        if name and loaded(name) then list[#list + 1] = name end
    end
    return table.concat(list, ", ")
end

local function Settings(add)
    local g, p = ns.db.global, ns.db.privacy
    add(("global: accent=%s font=%s outline=%s abbreviate=%s statusText=%s hideBlizzard=%s menuMode=%s clickCast=%s ellesmere=%s"):format(
        Str(g.accent), Str(g.font), Str(g.outline), Str(g.abbreviate), Str(g.statusText), Str(g.hideBlizzard),
        Str(g.menuMode), Str(g.clickCast), Str(ns.ellesmere)))
    add(("privacy: mode=%s mmt=%s"):format(Str(p.mode), Str(p.mmt)))
    ns.NameplateSettings(add)
    for _, info in ipairs(ns.FRAME_KEYS) do
        local s = ns.db.units[info.key]
        add(("%s: enabled=%s size=%sx%s scale=%s alpha=%s point=[%s %s %s,%s] anchor=%s portrait=%s/%s%s"):format(
            info.key, Str(s.enabled), Str(s.width), Str(s.height), Str(s.scale), Str(s.alpha),
            Str(s.point[1]), Str(s.point[2]), Str(s.point[3]), Str(s.point[4]), Str(s.anchorTo), Str(s.portrait.enabled), Str(s.portrait.mode),
            s.group and (" group: me=%s %s sort=%s spacing=%s"):format(Str(s.group.showPlayer), Str(s.group.orientation), Str(s.group.sort), Str(s.group.spacing)) or ""))
        for _, which in ipairs({ "health", "power" }) do
            local b = s[which]
            local texts = {}
            for _, a in ipairs(ns.ANCHORS) do
                local t = s.texts[which][a]
                if t.text ~= "" then texts[#texts + 1] = ("%s='%s'(%s)"):format(a, t.text, Str(t.size)) end
            end
            add(("  %s: texture=%s color=%s reverse=%s bg=%s border=%s%s %s"):format(which, Str(b.texture), Str(b.colorMode),
                Str(b.reverse), Str(b.bgTexture), Str(b.borderSize),
                which == "power" and (" enabled=" .. Str(b.enabled) .. " size=" .. Str(b.size)) or "", table.concat(texts, " ")))
        end
    end
end

function ns.NameplateSettings(add)
    local n = ns.db.nameplates
    if not n then return end
    add(("nameplates: enabled=%s mode=%s friendly=%s size=%sx%s texture=%s color=%s font=%s/%s level=%s health=%s cast=%s/%s buffs=%s debuffs=%s(mine=%s) active=%s"):format(
        Str(n.enabled), Str(n.mode), Str(n.friendlyMode), Str(n.width), Str(n.height), Str(n.texture), Str(n.colorMode),
        Str(n.font), Str(n.fontSize), Str(n.showLevel), Str(n.showHealth) .. " quest=" .. Str(n.showQuest) .. " elite=" .. Str(n.showElite), Str(n.showCast), Str(n.castHeight),
        Str(n.showBuffs), Str(n.showDebuffs), Str(n.debuffsMine), Str(ns.Nameplates and ns.Nameplates.Count())))
end

function ns.FrameReport(add)
    for _, info in ipairs(ns.UNITS) do
        local f = ns.singles and ns.singles[info.key]
        add(FrameLine(f, info.key))
        if f then add(UnitLine(f)) end
    end
    if ns.Nameplates then
        for unit, pl in pairs(ns.Nameplates.plates) do
            local okN, nm = pcall(pl.name.GetText, pl.name)
            local okQ, qt = pcall(pl.quest.GetText, pl.quest)
            add(("nameplate %s: mode=%s shown=%s name='%s' quest='%s' cast=%s"):format(unit, Str(pl.mode), Str(pl:IsVisible()),
                okN and Str(nm) or "?", okQ and Str(qt) or "?", Str(pl.cast:IsShown())))
            if ns.Auras then add("  auras read: " .. ns.Auras.ProbeUnit(unit)) end
        end
    end
    if ns.Group then ns.Group.Report(add) end
    if ns.DamageMeter then ns.DamageMeter.Report(add) end
    if ns.Minimap then ns.Minimap.Report(add) end
    if ns.PlayerAuras then ns.PlayerAuras.Report(add) end
    if ns.Chat then ns.Chat.Report(add) end
    if ns.UIScale then ns.UIScale.Report(add) end
    if ns.ActionBars then ns.ActionBars.Report(add) end
    if ns.ExtraBars then ns.ExtraBars.Report(add) end
    if ns.Bags then ns.Bags.Report(add) end
    if ns.Windows then ns.Windows.Report(add) end
    if ns.QuestLog then ns.QuestLog.Report(add) end
    if ns.QuestLinks then ns.QuestLinks.Report(add) end
    if ns.Raid then ns.Raid.Report(add) end
    do
        local api = C_PetInfo and C_PetInfo.GetPetHappiness and "C_PetInfo" or (GetPetHappiness and "global" or "none")
        local okH, h = pcall(function() return (C_PetInfo and C_PetInfo.GetPetHappiness or GetPetHappiness)() end)
        local okU, petUI, hunter = pcall(HasPetUI)
        local pf = ns.singles and ns.singles.pet
        add(("pet happiness: api=%s value=%s petUI=%s/%s icon=%s text=%s"):format(api, tostring(okH and h),
            tostring(okU and petUI), tostring(okU and hunter), tostring(pf and pf.happyIcon and pf.happyIcon:IsShown()),
            tostring(pf and pf.happyText and pf.happyText:IsShown())))
    end
    if ns.ClickCast then ns.ClickCast.Report(add) end
    if ns.Auras then
        for _, l in ipairs(ns.Auras.Report()) do add("auras " .. l) end
        add("  auras read target: " .. ns.Auras.ProbeUnit("target"))
    end
    for _, name in ipairs({ "PlayerFrame", "TargetFrame", "TargetFrameToT", "PetFrame", "PartyFrame", "CompactPartyFrame" }) do
        local f = _G[name]
        if f then add(("blizzard %s: shown=%s visible=%s parent=%s"):format(name, Str(f:IsShown()), Str(f:IsVisible()), Str(f:GetParent()))) end
    end
end

function ns.DebugReport()
    local lines = {}
    local function add(s) lines[#lines + 1] = s end
    add("=== HUF debug report ===")
    add(("HUF %s, client %s, %s"):format(ns.version, table.concat({ GetBuildInfo() }, " "), date("%Y-%m-%d %H:%M:%S")))
    local okC, class = pcall(UnitClass, "player")
    add(("player: level %s %s, combat=%s, group=%s raid=%s members=%s, profile=%s, unlocked=%s, ready=%s"):format(
        Str(UnitLevel("player")), Str(okC and class or "?"), Str(InCombatLockdown()), Str(IsInGroup()), Str(IsInRaid()),
        Str(GetNumGroupMembers()), ns.CurrentProfileName(), Str(ns.unlocked), Str(ns.ready)))
    local st = ns.Bridge and ns.Bridge.Status() or {}
    add(("MMT: loaded=%s version=%s privacy=%s team=%s used=%s privacyAPI=%s (HUF knows %s: %s)"):format(
        Str(st.loaded), Str(st.version), Str(st.mode), Str(st.teamSize), Str(st.active),
        Str(st.api), Str(st.apiExpected), Str(st.apiState)))
    add("addons: " .. Addons())
    add("")
    add("--- settings ---")
    Settings(add)
    add("")
    add("--- frames ---")
    local ok, err = pcall(ns.FrameReport, add)
    if not ok then add("frame report failed: " .. Str(err)) end
    add("")
    -- what the client gives for the units right now (the data recorder's snapshot)
    if ns.Recorder then
        add(("--- units now (data recorder %s) ---"):format(ns.Recorder.DB().enabled and "on" or "off"))
        local list = { "player", "target", "targettarget", "focus", "pet" }
        for i = 1, (IsInRaid() and 0 or (GetNumSubgroupMembers() or 0)) do list[#list + 1] = "party" .. i end
        for _, u in ipairs(list) do
            local okU, line = pcall(ns.Recorder.Snapshot, u)
            add(okU and line or (u .. ": ERR " .. Str(line)))
        end
        add("")
    end
    local d = DB()
    local n = d and #d.log or 0
    local from = math.max(1, n - REPORT_LINES + 1)
    add(("--- log (%d lines%s, debug log %s) ---"):format(n, from > 1 and (", the newest " .. REPORT_LINES .. " here") or "", ns.DebugOn() and "on" or "off"))
    if d then for i = from, n do add(d.log[i]) end end
    return table.concat(lines, "\n")
end

-- the newest lines only: a text box with thousands of long lines stalls the game
function ns.LogText()
    local d = DB()
    if not d or #d.log == 0 then return "(the log is empty)" end
    local n = #d.log
    local from = math.max(1, n - VIEW_LINES + 1)
    local text = table.concat(d.log, "\n", from, n)
    if from > 1 then
        text = ("(the newest %d of %d lines; the debug report has %d)\n"):format(n - from + 1, n, math.min(n, REPORT_LINES)) .. text
    end
    return text
end

-- one snapshot of every frame into the log
function ns.LogFrames(reason)
    if not ns.DebugOn() then return end
    Add("[state] " .. (reason or "frame state"))
    pcall(ns.FrameReport, function(s) Add("[state] " .. s) end)
end
