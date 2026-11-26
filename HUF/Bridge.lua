-- HUF <-> MMT bridge.
--
-- When MMT (Manage My Team) is loaded, HUF shows the characters of your MMT
-- team the way MMT's Team > Privacy setting says ("Catsi", "Purrita",
-- "Druid 1", "Slot 2"). Internally both addons keep using the full real name.
--
-- How it works: MMT's public privacy API, documented at the top of
-- MMT/Privacy.lua (github.com/bnetworking/MMT) with a version number,
-- MMT.PRIVACY_API. HUF is written for version 1:
--   * reads MMT.db.privacy.nameMode / hideOutside, MMT.PrivacyHidesOutside(),
--     MMT.Resolve(name) and MMT.ShownName(key)
--   * hooks MMT.PrivacyChanged (fired by MMT when the setting, the team, the
--     profile or a member's class changes) and MMT's settings refresh, and
--     redraws HUF's names then
--
-- The other direction (HUF's public API, for MMT or any other addon):
--   HUF.API_VERSION                      -> 1
--   HUF.RegisterNameProvider(id, fn)     fn(unit, first, last) -> shown name or nil
--   HUF.RegisterMover(id, spec)          a window of yours in HUF's unlock mode (box, snapping,
--                                        guide lines, grid): spec = { label, frame, save(frame),
--                                        shown(), settings(), get(), set(place), preview(on) } (Movers.lua);
--                                        preview: unlock mode starts / ends (example content); with
--                                        get / set the place goes along in HUF's profile export / import;
--                                        HUF.UnregisterMover(id)
--   HUF.RefreshNames()                   redraw every name on HUF's frames
--   HUF.Refresh()                        re-apply all HUF settings
--   HUF.ToggleConfig([page])             open the settings (/huf)
--   HUF.Bridge.Status()                  table describing the link to MMT

local _, ns = ...

local Bridge = {}
ns.Bridge = Bridge
Bridge.PRIVACY_API = 1          -- the MMT privacy API version HUF is written for

-- General > Addon support > "Allow MMT interaction" off: HUF ignores MMT
-- (no names, no team, no hooks, its windows not in unlock mode)
function Bridge.Allowed() return not (ns.db and ns.db.global.mmt == false) end

function Bridge.MMT()
    if not Bridge.Allowed() then return nil end
    local m = _G.MMT
    if type(m) == "table" and type(m.db) == "table" and type(m.ShownName) == "function" then return m end
    return nil
end

function Bridge.Mode()
    local m = Bridge.MMT()
    local p = m and m.db.privacy
    return p and p.nameMode or nil
end

function Bridge.Active()
    return ns.db and ns.db.privacy.mmt ~= "NEVER" and Bridge.MMT() ~= nil
end

-- MMT team key of a character ("First-Last"), or nil when not in the team
local function TeamKey(m, first, last)
    if type(m.Resolve) ~= "function" then return nil end
    if last then
        return m.Resolve(first .. "-" .. last) or m.Resolve(first .. " " .. last)
    end
    return m.Resolve(first)
end

-- every other member of the group is on the MMT team (MMT loaded, in a
-- group): then "my group" in the automatic dispel / purge settings
function Bridge.GroupIsTeam()
    local m = Bridge.MMT()
    if not m or not (GetNumGroupMembers and IsInGroup and IsInGroup()) then return false end
    local raid = IsInRaid and IsInRaid()
    local n = GetNumGroupMembers() or 0
    local any = false
    for i = 1, raid and n or (n - 1) do
        local unit = (raid and "raid" or "party") .. i
        local okU, me = pcall(UnitIsUnit, unit, "player")
        if not (okU and me == true) then
            local ok, first, last = pcall(UnitName, unit)
            if not ok or type(first) ~= "string" or ns.IsSecret(first) then return false end
            if ns.IsSecret(last) then last = nil end
            local okK, key = pcall(TeamKey, m, first, (last and last ~= "") and last or nil)
            if not (okK and key) then return false end
            any = true
        end
    end
    return any
end

-- the name provider HUF registers for MMT
local function Provider(unit, first, last)
    if not Bridge.Active() then return nil end
    -- "Only when MMT hides names outside MMT too"
    if ns.db.privacy.mmt == "OUTSIDE" then
        local m = Bridge.MMT()
        if not (type(m.PrivacyHidesOutside) == "function" and m.PrivacyHidesOutside()) then return nil end
    end
    -- MMT shows full names: no privacy, HUF's own text settings decide
    if Bridge.Mode() == "FULL" then return nil end
    local m = Bridge.MMT()
    local ok, key = pcall(TeamKey, m, first, last)
    if not ok or not key then return nil end
    local ok2, shown = pcall(m.ShownName, key)
    if ok2 and type(shown) == "string" and shown ~= "" then return shown end
    return nil
end

-- MMT's privacy API version (nil: an MMT from before the API had a number)
function Bridge.API()
    local m = Bridge.MMT()
    local v = m and m.PRIVACY_API
    return type(v) == "number" and v or nil
end

-- "ok", "older" (no version: works as far as it can) or "newer" (MMT changed
-- the API: HUF may need an update)
function Bridge.APIState()
    local v = Bridge.API()
    if not Bridge.MMT() then return nil end
    if not v then return "older" end
    if v == Bridge.PRIVACY_API then return "ok" end
    return v > Bridge.PRIVACY_API and "newer" or "older"
end

function Bridge.Status()
    local m = Bridge.MMT()
    local teamSize = 0
    if m and type(m.db.team) == "table" then
        for _ in pairs(m.db.team) do teamSize = teamSize + 1 end
    end
    return {
        loaded = m ~= nil,
        version = m and m.version or nil,
        mode = Bridge.Mode(),
        hideOutside = m and m.db.privacy and m.db.privacy.hideOutside or false,
        teamSize = teamSize,
        active = Bridge.Active() and true or false,
        api = Bridge.API(),
        apiExpected = Bridge.PRIVACY_API,
        apiState = Bridge.APIState(),
    }
end

local MODE_TEXT = { FIRST = "First name", LAST = "Last name", FULL = "Full name", CLASS = "Class X", SLOT = "Slot X" }
function Bridge.ModeText(mode) return MODE_TEXT[mode or ""] or tostring(mode or "-") end

local hooked = false
local lastMode
-- what HUF's names depend on: MMT's "Show characters by" and "Hide names outside MMT too"
local function Signature()
    local m = Bridge.MMT()
    local p = m and m.db.privacy
    return tostring(p and p.nameMode) .. "/" .. tostring(p and p.hideOutside)
end
local function Changed()
    lastMode = Signature()
    ns.Log("mmt", "MMT changed: privacy %s", lastMode)
    ns.RefreshNames()
    if ns.RefreshConfig then ns.RefreshConfig() end
end

function Bridge.Hook()
    local m = Bridge.MMT()
    if not m or hooked then return end
    hooked = true
    if type(m.PrivacyChanged) == "function" then hooksecurefunc(m, "PrivacyChanged", Changed) end
    -- any MMT setting change: redraw only when the privacy mode differs
    if type(m.OnRefresh) == "function" then
        m.OnRefresh(function() if Signature() ~= lastMode then Changed() end end)
    end
    if type(m.Listen) == "function" then
        m.Listen("TEAM_CHANGED", Changed)
        m.Listen("PROFILE_CHANGED", Changed)
    end
    lastMode = Signature()
    local state, api = Bridge.APIState(), Bridge.API()
    ns.Log("mmt", "MMT bridge: linked (privacy %s, MMT privacy API %s, HUF expects %d: %s)",
        tostring(lastMode), tostring(api), Bridge.PRIVACY_API, tostring(state))
    if state == "newer" then
        ns.Print("MMT's privacy interface is version %d; this HUF knows version %d. Names may not follow MMT until HUF is updated.",
            api, Bridge.PRIVACY_API)
    end
end

ns.RegisterNameProvider("MMT", Provider)

-- MMT may load before or after HUF
ns.On("ADDON_LOADED", function(name) if name == "MMT" then Bridge.Hook() end end)
ns.OnLogin(function() Bridge.Hook() end)
