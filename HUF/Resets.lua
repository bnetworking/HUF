-- HUF: tell the group when you reset instances (General > Frames & Features,
-- setting resets.announce). Only the one who resets gets the game's lines
-- "<instance> has been reset." / "Cannot reset <instance>. ..." (localized
-- INSTANCE_RESET_* strings); HUF gathers the lines of one reset (several
-- instances at once give several lines) and posts one message for those reset
-- and one for those that could not be, in instance / raid / party chat.
-- Nothing is said outside a group.
local _, ns = ...

local function Cfg() return ns.db and ns.db.resets end

-- a format string ("%s has been reset.") as a pattern with one capture
local function Pattern(fmt)
    if type(fmt) ~= "string" or fmt == "" then return nil end
    local parts, i = {}, 1
    while true do
        local s, e = fmt:find("%%%d?%$?[sd]", i)
        parts[#parts + 1] = (fmt:sub(i, s and s - 1):gsub("[%^%$%(%)%.%[%]%*%+%-%?%%]", "%%%0"))
        if not s then break end
        parts[#parts + 1] = "(.-)"
        i = e + 1
    end
    return "^" .. table.concat(parts) .. "$"
end

-- failure lines: the key and why, said in the group
local FAILED = {
    { "INSTANCE_RESET_FAILED", "players still inside the instance" },
    { "INSTANCE_RESET_FAILED_OFFLINE", "players offline in the group" },
    { "INSTANCE_RESET_FAILED_ZONING", "someone is zoning into it" },
}
local pats
local function Patterns()
    if pats then return pats end
    pats = { ok = Pattern(_G.INSTANCE_RESET_SUCCESS), failed = {} }
    for _, f in ipairs(FAILED) do
        local p = Pattern(_G[f[1]])
        if p then pats.failed[#pats.failed + 1] = { pat = p, why = f[2] } end
    end
    return pats
end

local function Channel()
    if LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
    return nil
end

local function Say(text)
    local ch = Channel()
    if not ch then return end
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if send then pcall(send, text, ch) end
end

local reset, failed, pending = {}, {}, false
local function Flush()
    pending = false
    if #reset > 0 then Say("Instance reset: " .. table.concat(reset, ", ") .. ".") end
    for _, f in ipairs(failed) do Say(("Could not reset %s: %s."):format(f[1], f[2])) end
    reset, failed = {}, {}
end
local function Later()
    if pending then return end
    pending = true
    C_Timer.After(0.5, Flush)        -- the game's own lines first, all of one reset together
end

local function OnSystem(text)
    local c = Cfg()
    if not (c and c.announce) then return end
    if type(text) ~= "string" or ns.IsSecret(text) or not Channel() then return end
    local p = Patterns()
    local name = p.ok and text:match(p.ok)
    if name then
        reset[#reset + 1] = name
        Later()
        return
    end
    for _, f in ipairs(p.failed) do
        local n = text:match(f.pat)
        if n then
            failed[#failed + 1] = { n, f.why }
            Later()
            return
        end
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("CHAT_MSG_SYSTEM")
events:SetScript("OnEvent", function(_, _, text)
    local ok, err = pcall(OnSystem, text)
    if not ok and ns.Log then ns.Log("resets", "%s", tostring(err)) end
end)
