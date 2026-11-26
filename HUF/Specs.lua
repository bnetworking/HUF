-- HUF: specs (the talent tree with the most points) of you and your group,
-- for the damage meter's spec icons ("Icons: Spec"). HUF works them out
-- itself, MMT is not needed:
--   you            your own talent points (trait tree, else the talent tabs)
--   group members  inspected one at a time, only out of combat, in range,
--                  never while the inspect window is open and not right after
--                  an inspect someone else asked for (the game's window opens
--                  on a matching answer). An answer to anyone's inspect is used.
-- Kept by GUID for the session. ns.Specs.Icon(unit or guid, class) -> icon or nil.

local _, ns = ...
local SP = {}
ns.Specs = SP

local function Plain(v) return v ~= nil and not (issecretvalue and issecretvalue(v)) end
local function Safe(f, ...) if not f then return nil end local ok, a, b, c = pcall(f, ...) if ok then return a, b, c end end

-- the classic talent-tab icons, in talent tree order
local ICONS = {
    WARRIOR = { "Ability_Warrior_SavageBlow", "Ability_Warrior_InnerRage", "Ability_Warrior_DefensiveStance" },
    PALADIN = { "Spell_Holy_HolyBolt", "Spell_Holy_DevotionAura", "Spell_Holy_AuraOfLight" },
    HUNTER  = { "Ability_Hunter_BeastTaming", "Ability_Marksmanship", "Ability_Hunter_SwiftStrike" },
    ROGUE   = { "Ability_Rogue_Eviscerate", "Ability_BackStab", "Ability_Stealth" },
    PRIEST  = { "Spell_Holy_WordFortitude", "Spell_Holy_GuardianSpirit", "Spell_Shadow_ShadowWordPain" },
    SHAMAN  = { "Spell_Nature_Lightning", "Spell_Nature_LightningShield", "Spell_Nature_MagicImmunity" },
    MAGE    = { "Spell_Holy_MagicalSentry", "Spell_Fire_FireBolt02", "Spell_Frost_FrostBolt02" },
    WARLOCK = { "Spell_Shadow_DeathCoil", "Spell_Shadow_Metamorphosis", "Spell_Shadow_RainOfFire" },
    DRUID   = { "Spell_Nature_StarFall", "Ability_Racial_BearForm", "Spell_Nature_HealingTouch" },
}
local NAMES = {
    WARRIOR = { "Arms", "Fury", "Protection" }, PALADIN = { "Holy", "Protection", "Retribution" },
    HUNTER = { "Beast Mastery", "Marksmanship", "Survival" }, ROGUE = { "Assassination", "Combat", "Subtlety" },
    PRIEST = { "Discipline", "Holy", "Shadow" }, SHAMAN = { "Elemental", "Enhancement", "Restoration" },
    MAGE = { "Arcane", "Fire", "Frost" }, WARLOCK = { "Affliction", "Demonology", "Destruction" },
    DRUID = { "Balance", "Feral", "Restoration" },
}

local byGUID = {}      -- guid -> { tree = 1-3, icon = game's icon or nil, t = GetTime() }

---------------------------------------------------------------------------
-- Reading talent points
---------------------------------------------------------------------------
-- the three trees' points from a trait config: its nodes grouped into three
-- columns by their x position (the trees side by side)
local function TraitPoints(configID)
    if not (C_Traits and C_Traits.GetConfigInfo and C_Traits.GetTreeNodes and C_Traits.GetNodeInfo) then return nil end
    local info = Safe(C_Traits.GetConfigInfo, configID)
    local tree = type(info) == "table" and type(info.treeIDs) == "table" and info.treeIDs[1]
    if not tree then return nil end
    local nodes = Safe(C_Traits.GetTreeNodes, tree)
    if type(nodes) ~= "table" then return nil end
    local cols, xs = {}, {}
    for _, id in ipairs(nodes) do
        local node = Safe(C_Traits.GetNodeInfo, configID, id)
        local x = type(node) == "table" and node.posX
        local r = type(node) == "table" and node.ranksPurchased
        if Plain(x) and type(x) == "number" then
            if not cols[x] then cols[x] = 0 xs[#xs + 1] = x end
            if Plain(r) and type(r) == "number" then cols[x] = cols[x] + r end
        end
    end
    if #xs < 3 then return nil end
    table.sort(xs)
    -- the gap between two trees is much wider than between two columns of one tree
    local step
    for i = 2, #xs do
        local gap = xs[i] - xs[i - 1]
        if gap > 0 and (not step or gap < step) then step = gap end
    end
    if not step then return nil end
    local t = { cols[xs[1]] }
    for i = 2, #xs do
        if xs[i] - xs[i - 1] > step * 2 then t[#t + 1] = 0 end
        t[#t] = t[#t] + cols[xs[i]]
    end
    return #t == 3 and t or nil
end
-- the old talent tabs (inspect: the inspected unit's)
local function TabPoints(inspect)
    if not GetTalentTabInfo then return nil end
    local t, any = {}, false
    for tab = 1, 3 do
        local ok, a, _, c, _, e = pcall(GetTalentTabInfo, tab, inspect)
        local spent = ok and (type(a) == "string" and c or e)
        if not Plain(spent) or type(spent) ~= "number" then return nil end
        t[tab] = spent
        if spent > 0 then any = true end
    end
    return any and t or nil
end
local function Most(t)
    if not t then return nil end
    local best, most = nil, 0
    for i = 1, 3 do if (t[i] or 0) > most then best, most = i, t[i] end end
    return best
end

local function OwnTree()
    local cfg = C_ClassTalents and C_ClassTalents.GetActiveConfigID and Safe(C_ClassTalents.GetActiveConfigID)
    local tree = cfg and Most(TraitPoints(cfg))
    return tree or Most(TabPoints(false))
end
local function InspectTree(unit)
    -- the game's spec, if it has one
    if GetInspectSpecialization and GetSpecializationInfoByID then
        local id = Safe(GetInspectSpecialization, unit)
        if Plain(id) and type(id) == "number" and id > 0 then
            local _, _, _, icon = Safe(GetSpecializationInfoByID, id)
            if Plain(icon) and icon then return nil, icon end
        end
    end
    local INSPECT = Constants and Constants.TraitConsts and Constants.TraitConsts.INSPECT_TRAIT_CONFIG_ID
    local tree = INSPECT and Most(TraitPoints(INSPECT))
    return tree or Most(TabPoints(true)), nil
end

local function Store(guid, tree, icon)
    if not (Plain(guid) and (tree or icon)) then return end
    byGUID[guid] = { tree = tree, icon = icon, t = GetTime() }
    if ns.DamageMeter and ns.DamageMeter.Refresh then pcall(ns.DamageMeter.Refresh) end
end
local function UpdateOwn()
    local guid = UnitGUID("player")
    local tree = OwnTree()
    if tree then Store(guid, tree) end
end

---------------------------------------------------------------------------
-- Inspecting the group
---------------------------------------------------------------------------
local wanted = false           -- the meter shows spec icons
local asked, askedAt = nil, 0  -- guid / time of our open inspect
local foreignAt = 0            -- someone else's inspect (you, the window, another addon)
local ours = false
if NotifyInspect then
    hooksecurefunc("NotifyInspect", function() if not ours then foreignAt = GetTime() end end)
end

local function GroupUnits()
    local list = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do list[#list + 1] = "raid" .. i end
    else
        for i = 1, GetNumSubgroupMembers() do list[#list + 1] = "party" .. i end
    end
    return list
end
local function InspectWindowOpen() return _G.InspectFrame and _G.InspectFrame:IsShown() end

local function Next()
    if not wanted or InCombatLockdown() or InspectWindowOpen() then return end
    local now = GetTime()
    if now - foreignAt < 5 then return end
    if asked and now - askedAt < 4 then return end    -- still waiting
    asked = nil
    for _, unit in ipairs(GroupUnits()) do
        local guid = Safe(UnitGUID, unit)
        local have = Plain(guid) and byGUID[guid]
        if Plain(guid) and not UnitIsUnit(unit, "player") and (not have or now - have.t > 600)
           and Safe(UnitIsConnected, unit) and Safe(CanInspect, unit) and Safe(CheckInteractDistance, unit, 1) then
            asked, askedAt = guid, now
            ours = true
            pcall(NotifyInspect, unit)
            ours = false
            return
        end
    end
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event, arg)
    if event == "INSPECT_READY" then
        -- any inspect answer for a group member: read it
        local guid = arg
        if not Plain(guid) then return end
        local unit
        for _, u in ipairs(GroupUnits()) do
            if Safe(UnitGUID, u) == guid then unit = u break end
        end
        if unit then
            local tree, icon = InspectTree(unit)
            Store(guid, tree, icon)
        end
        if guid == asked then
            asked = nil
            -- our own inspect: let go of it (not someone else's)
            if not InspectWindowOpen() and ClearInspectPlayer then pcall(ClearInspectPlayer) end
        end
    elseif event == "PLAYER_LOGIN" or event == "TRAIT_CONFIG_UPDATED" or event == "PLAYER_TALENT_UPDATE"
        or event == "CHARACTER_POINTS_CHANGED" then
        C_Timer.After(1, UpdateOwn)
    end
end)
for _, e in ipairs({ "INSPECT_READY", "PLAYER_LOGIN", "TRAIT_CONFIG_UPDATED", "PLAYER_TALENT_UPDATE",
    "CHARACTER_POINTS_CHANGED" }) do pcall(ev.RegisterEvent, ev, e) end
C_Timer.NewTicker(2, function() pcall(Next) end)

-- the damage meter turns the inspecting on / off (only while it shows spec icons)
function SP.SetWanted(on) wanted = on and true or false end

---------------------------------------------------------------------------
-- Lookup
---------------------------------------------------------------------------
-- icon of a unit's (or GUID's) spec, given its class; nil: not known
function SP.Icon(unitOrGuid, class)
    local guid = unitOrGuid
    if type(unitOrGuid) == "string" and not unitOrGuid:find("%-") then guid = Safe(UnitGUID, unitOrGuid) end
    if not Plain(guid) then return nil end
    local s = byGUID[guid]
    if not s then return nil end
    if s.icon then return s.icon end
    local list = ICONS[class or ""]
    return list and s.tree and ("Interface\\Icons\\" .. list[s.tree]) or nil
end
function SP.Name(guid, class)
    local s = Plain(guid) and byGUID[guid]
    local list = NAMES[class or ""]
    return s and s.tree and list and list[s.tree] or nil
end
function SP.Report(add)
    local n = 0
    for _ in pairs(byGUID) do n = n + 1 end
    local own = byGUID[UnitGUID("player") or ""]
    add(("specs: %d known, own tree=%s, inspecting=%s"):format(n, tostring(own and own.tree), tostring(wanted)))
end
