-- HUF: import an EllesmereUI profile: a string ("!EUI_...") or its current
-- settings in the game.
--
-- A string is read with EllesmereUI's own decoder (EllesmereUI has to be
-- loaded), so nothing is run: it is only parsed. What becomes HUF settings:
--   * Unit Frames (player, target, target of target, pet): size, position,
--     power bar, portrait, texts, buffs / debuffs, texture, colours, border,
--     font, incoming heals (Heal Prediction), power colours
--   * Nameplates: bar, texts, NPC colours, cast bar, debuffs
--   * Damage Meters: its windows (up to 5), look, when it shows
-- Everything else of the active HUF profile (group frames, accent, privacy
-- ...) stays as it is. The result looks close to Ellesmere's, not
-- pixel-identical: what HUF has no setting for is left out and listed after
-- the import.
--
-- Keep it complete: when HUF gets a feature EllesmereUI also has (a frame,
-- an option, a module like the damage meter), map its Ellesmere settings
-- here too, so an import keeps bringing everything over.

local _, ns = ...

local EUI_PREFIX = "!EUI_"
local UF_FOLDER = "EllesmereUIUnitFrames"
local NP_FOLDER = "EllesmereUINameplates"
local DM_FOLDER = "EllesmereUIDamageMeters"
local RF_FOLDER = "EllesmereUIRaidFrames"

-- HUF frame key -> Ellesmere settings key
local UNIT_KEYS = { player = "player", target = "target", targettarget = "targettarget", pet = "pet" }

-- Ellesmere's defaults for the keys read here (a profile only stores what
-- differs, WoW Forever values). Per unit, then shared.
local EUI_DEFAULTS = {
    player = {
        frameWidth = 181, healthHeight = 46, powerHeight = 6, powerPosition = "below",
        healthClassColored = true, showPortrait = true, portraitSide = "left",
        leftTextContent = "name", rightTextContent = "perhp",
        showBuffs = false, buffAnchor = "topleft", debuffAnchor = "none", maxDebuffs = 10,
    },
    target = {
        frameWidth = 181, healthHeight = 46, powerHeight = 6, powerPosition = "below",
        healthClassColored = true, showPortrait = true, portraitSide = "right",
        leftTextContent = "levelname", rightTextContent = "perhp",
        showBuffs = true, buffAnchor = "topleft", debuffAnchor = "bottomleft", maxDebuffs = 20,
    },
    targettarget = {
        frameWidth = 101, healthHeight = 25, powerPosition = "none",
        healthClassColored = false, showPortrait = false, portraitSide = "left",
        leftTextContent = "name", rightTextContent = "none",
        showBuffs = false, debuffAnchor = "none",
    },
    pet = {
        frameWidth = 101, healthHeight = 25, powerHeight = 6, powerPosition = "below",
        healthClassColored = false, showPortrait = false, portraitSide = "left",
        leftTextContent = "name", rightTextContent = "none",
        showBuffs = false, debuffAnchor = "none",
    },
    shared = {
        powerHeight = 6, powerPercentText = "none", powerTextFormat = "perpp", powerPercentSize = 9,
        portraitStyle = "attached", portraitMode = "2d",
        centerTextContent = "none", textSize = 12,
        maxBuffs = 4, buffSize = 22, debuffSize = 22,
        buffOffsetX = 0, buffOffsetY = 0, debuffOffsetX = 0, debuffOffsetY = 0,
        borderSize = 1, borderColor = { r = 0, g = 0, b = 0 },
        customBgColor = { r = 0.067, g = 0.067, b = 0.067 },
    },
}
local EUI_POSITIONS = {
    player = { point = "CENTER", relPoint = "CENTER", x = -317, y = -193.5 },
    target = { point = "CENTER", relPoint = "CENTER", x = 317, y = -201 },
    pet = { point = "CENTER", relPoint = "CENTER", x = -300, y = -260 },
    targettarget = { point = "CENTER", relPoint = "CENTER", x = 383, y = -152.5 },
}

-- Ellesmere text contents -> HUF text templates (nil: HUF has no such value)
local CONTENT = {
    name = "[name]",
    levelname = "[level] | [name]",
    namelevel = "[name] | [level]",
    level = "[level]",
    both = "[hp] | [hp%]",
    bothdash = "[hp] - [hp%]",
    perhpnum = "[hp%] | [hp]",
    perhpnumdash = "[hp%] - [hp]",
    curhpshort = "[hp]",
    healthshort = "[hp]",
    curmaxhp = "[hp] / [hp:max]",
    perhp = "[hp%]",
    perhpnosign = "[hp%]",
    perpp = "[mp%]",
    curpp = "[mp]",
    curmaxpp = "[mp] / [mp:max]",
    curhp_curpp = "[hp] | [mp]",
    perhp_perpp = "[hp%] | [mp%]",
}
local POWER_CONTENT = {
    perpp = "[mp%]", curpp = "[mp]", curmaxpp = "[mp] / [mp:max]", both = "[mp] | [mp%]", smart = "[mp]",
}

-- Ellesmere's raid frame debuff spots (on the health bar)
local RF_DEBUFF_POS = {
    topleft = "INSIDE_TOPLEFT", top = "INSIDE_TOP", topright = "INSIDE_TOPRIGHT",
    left = "INSIDE_LEFT", center = "INSIDE_CENTER", right = "INSIDE_RIGHT",
    bottomleft = "INSIDE_BOTTOMLEFT", bottom = "INSIDE_BOTTOM", bottomright = "INSIDE_BOTTOMRIGHT",
}

local AURA_POS = {
    topleft = "ABOVE_LEFT", topright = "ABOVE_RIGHT",
    bottomleft = "BELOW_LEFT", bottomright = "BELOW_RIGHT",
    left = "LEFT", right = "RIGHT",
}

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function Num(v, d) if type(v) == "number" then return v end return d end
local function Color(c, d)
    if type(c) == "table" and type(c.r) == "number" then
        return { r = c.r, g = Num(c.g, 0), b = Num(c.b, 0) }
    end
    return ns.CopyTable(d)
end

-- one setting of an Ellesmere unit, its default when the profile has none
local function Getter(s, key)
    local d1, d2 = EUI_DEFAULTS[key] or {}, EUI_DEFAULTS.shared
    return function(k)
        local v = s[k]
        if v == nil then v = d1[k] end
        if v == nil then v = d2[k] end
        return v
    end
end

local function NewAnchor(text, size)
    return {
        text = text or "", font = "GLOBAL", size = size or 12, outline = "GLOBAL",
        colorMode = "WHITE", color = { r = 1, g = 1, b = 1 }, hideFull = false, x = 0, y = 0,
    }
end
local function EmptyTexts()
    local t = {}
    for _, a in ipairs(ns.ANCHORS) do t[a] = NewAnchor("", 12) end
    return t
end

-- HUF's name of an EllesmereUI bar texture (its file in EllesmereUI's folder)
local function TextureName(key)
    if key == nil or key == "none" then return "Flat" end
    if type(key) ~= "string" then return nil end
    local tail = ("textures\\" .. key):lower()
    for _, e in ipairs(ns.textures) do
        local p = type(e.path) == "string" and e.path:lower()
        if p and (p:sub(-#tail) == tail or p:sub(-#tail - 4) == tail .. ".tga") then return e.name end
    end
    -- a SharedMedia texture HUF also lists under the same name
    for _, e in ipairs(ns.textures) do
        if e.name == key then return e.name end
    end
    return nil
end

-- each note once (the texture note comes from every frame)
local function Unique(notes)
    local seen, list = {}, {}
    for _, n in ipairs(notes) do
        if not seen[n] then seen[n] = true list[#list + 1] = n end
    end
    return list
end

local function FontName(name)
    if type(name) ~= "string" then return nil end
    if name == "__blizzard" then return "Friz Quadrata" end
    local found
    for _, f in ipairs(ns.fonts) do
        if f.name == name or f.name == name .. " (EUI)" then
            -- the EllesmereUI copy first: that is the file Ellesmere draws with
            if f.ellesmere or not found then found = f.name end
        end
    end
    return found
end

---------------------------------------------------------------------------
-- Reading the string
---------------------------------------------------------------------------
function ns.IsEllesmereText(text)
    text = ns.Trim(text or "")
    return text:sub(1, #EUI_PREFIX) == EUI_PREFIX
end

-- the profile data of a decoded payload (a full-account string carries profiles)
local function ProfileOf(payload)
    local data = type(payload) == "table" and payload.data
    if type(data) ~= "table" then return nil end
    if type(data.addons) == "table" then return data end
    if type(data.profiles) == "table" then
        local name = data.activeProfile or payload.profileName or "Default"
        local p = data.profiles[name]
        if type(p) ~= "table" then
            for _, any in pairs(data.profiles) do if type(any) == "table" then p = any break end end
        end
        if type(p) == "table" then
            -- account-wide fonts live at the data root in that format
            if p.fonts == nil and type(data.fonts) == "table" then p.fonts = data.fonts end
            return p
        end
    end
    return nil
end

-- ok, Ellesmere's profile data (addons, fonts ...) or ok=false, error text
local function Decode(text)
    text = ns.Trim(text or "")
    local EUI = _G.EllesmereUI
    if type(EUI) ~= "table" or type(EUI.DecodeImportString) ~= "function" then
        return false, "EllesmereUI has to be loaded to read its strings (HUF uses its decoder)."
    end
    local ok, payload, err = pcall(EUI.DecodeImportString, text)
    if not ok then return false, "EllesmereUI could not read the text: " .. tostring(payload) end
    if not payload then return false, "EllesmereUI: " .. tostring(err or "could not read the text") end
    local prof = ProfileOf(payload)
    local uf = prof and prof.addons and prof.addons[UF_FOLDER]
    local np = prof and prof.addons and prof.addons[NP_FOLDER]
    local dm = prof and prof.addons and prof.addons[DM_FOLDER]
    if type(uf) ~= "table" and type(np) ~= "table" and type(dm) ~= "table" then
        return false, "This EllesmereUI string has no Unit Frames, Nameplates or Damage Meters settings (export it with them ticked)."
    end
    return true, prof, type(uf) == "table" and uf or nil, type(np) == "table" and np or nil,
        type(dm) == "table" and dm or nil
end

---------------------------------------------------------------------------
-- Converting one frame
---------------------------------------------------------------------------
local function ConvertUnit(key, s, uf, u, notes)
    local G = Getter(s, key)
    local title = ns.UNIT_BY_KEY[key].title

    -- shown or not (frameSource "eui" / "blizzard" / "hidden", or the older enabledFrames flag)
    local src = type(uf.frameSource) == "table" and uf.frameSource[key]
    if src == nil and type(uf.enabledFrames) == "table" and uf.enabledFrames[key] == false then src = "hidden" end
    -- Blizzard's frame or none in Ellesmere: HUF's off (the import window can turn it on)
    u.enabled = (src == nil or src == "eui")

    -- power bar
    local pPos = G("powerPosition")
    local pH = Num(G("powerHeight"), 6)
    local power = pPos ~= "none" and pH > 0
    u.power.enabled = power
    u.power.size = math.max(1, math.floor(pH + 0.5))
    u.power.gap = 0
    u.power.divider = false         -- one border around health and power, as Ellesmere draws it
    if power and pPos ~= "below" then
        notes[#notes + 1] = ("%s: power bar \"%s\" is drawn below the health bar."):format(title, tostring(pPos))
    end

    -- size: Ellesmere's width is the bars', an attached portrait comes on top
    local hH = Num(G("healthHeight"), 30)
    local H = math.floor(hH + (power and pH or 0) + 0.5)
    local W = Num(G("frameWidth"), 175)
    u.height = math.max(4, H)

    -- portrait
    local style = G("portraitStyle")
    local por = G("showPortrait") and style ~= "none"
    u.portrait.enabled = por and true or false
    if por then
        local mode = G("portraitMode")
        if s.portraitMode == nil and type(uf.portraitMode) == "string" then mode = uf.portraitMode end
        u.portrait.mode = (mode == "3d" and "3D") or (mode == "class" and "CLASS") or "2D"
        u.portrait.side = (G("portraitSide") == "right") and "RIGHT" or "LEFT"
        u.portrait.gap = 0
        W = W + u.height
        if style == "detached" then
            notes[#notes + 1] = title .. ": the detached portrait is attached to the frame."
        end
    end
    -- Ellesmere draws its border inside the frame's size, HUF around the bars
    local inset = 2 * math.max(0, Num(G("borderSize"), 1))
    u.width = math.floor(W - inset + 0.5)
    u.height = math.max(4, u.height - inset)

    -- position (centre of the screen based, like Ellesmere's)
    local pos = type(uf.positions) == "table" and uf.positions[key] or EUI_POSITIONS[key]
    if type(pos) == "table" then
        u.anchorTo = "SCREEN"
        u.point = { pos.point or "CENTER", pos.relPoint or pos.point or "CENTER",
                    math.floor(Num(pos.x, 0) + 0.5), math.floor(Num(pos.y, 0) + 0.5) }
    end

    -- bars: texture, colours, border
    -- the frame's own texture first, as Ellesmere draws it (health and power alike)
    local texKey = s.healthBarTexture or uf.healthBarTexture
    local tex = TextureName(texKey)
    if not tex then
        notes[#notes + 1] = ("Bar texture \"%s\" is not known to HUF: Flat instead."):format(tostring(texKey))
        tex = "Flat"
    end
    local bSize = Num(G("borderSize"), 1)
    local bColor = Color(G("borderColor"), { r = 0, g = 0, b = 0 })
    local bg = Color(G("customBgColor"), { r = 0.067, g = 0.067, b = 0.067 })
    for _, which in ipairs({ "health", "power" }) do
        local b = u[which]
        b.texture = tex
        b.borderSize = math.floor(bSize + 0.5)
        b.borderColor = ns.CopyTable(bColor)
        b.borderAlpha = 1
        b.bgTexture = "Plain"
        b.bgColor = ns.CopyTable(bg)
        b.bgAlpha = 1
    end
    local h = u.health
    if G("healthClassColored") or not (type(s.customFillColor) == "table" or uf.darkTheme) then
        h.colorMode = "CLASS"
        h.npcReaction = true
    else
        h.colorMode = "STATIC"
        h.color = uf.darkTheme and not s.customFillColor and { r = 0.067, g = 0.067, b = 0.067 }
            or Color(s.customFillColor, h.color)
    end
    if s.bgClassColored then notes[#notes + 1] = title .. ": class coloured background is a plain colour." end
    -- incoming heals: Ellesmere's Heal Prediction (player and target only)
    if type(u.healPred) == "table" then
        if key == "player" or key == "target" then
            u.healPred.enabled = s.healPrediction == true
            u.healPred.color = Color(s.healPredColor, { r = 102 / 255, g = 243 / 255, b = 102 / 255 })
            u.healPred.alpha = Num(s.healPredOpacity, 60) / 100
            u.healPred.overheal = Num(s.healPredOverheal, 0)
        else
            u.healPred.enabled = false
        end
    end

    -- power fill: Ellesmere's power colours by type (the import sets them
    -- globally), a custom fill with "power colour" off, or the class colour
    if s.powerPercentPowerColor == false then
        u.power.colorMode = "STATIC"
        u.power.color = Color(s.customPowerFillColor, { r = 0, g = 0, b = 1 })
    elseif s.powerClassColored then
        u.power.colorMode = "CLASS"
    else
        u.power.colorMode = "TYPE"
    end

    -- texts on the health bar: left / center / right, and the extra text
    -- (its own alignment). Ellesmere sets them 5 px in from the bar's edge
    -- (HUF 2) and centres them vertically; an extra text whose spot is taken
    -- goes to the bottom (or top) anchor, moved to the same place.
    local texts = EmptyTexts()
    local base = Num(G("textSize"), 12)
    local barH = math.max(1, H - (power and pH or 0))
    local function Slot(p, anchor)
        local content = G(p .. "TextContent")
        if not content or content == "none" then return end
        local tpl = CONTENT[content]
        if not tpl then
            notes[#notes + 1] = ("%s: %s text \"%s\" has no HUF value, left out."):format(title, p, tostring(content))
            return
        end
        local size = Num(s[p .. "TextSize"], base)
        local a = NewAnchor(tpl, size)
        a.x, a.y = Num(s[p .. "TextX"], 0), Num(s[p .. "TextY"], 0)
        if texts[anchor].text ~= "" then
            -- spot taken: bottom anchor (text bottom at the bar's bottom), else top
            local side = anchor == "CENTER" and "" or anchor
            local bottom, top = "BOTTOM" .. side, "TOP" .. side
            if texts[bottom].text == "" then
                anchor, a.y = bottom, a.y + barH / 2 - size / 2
            elseif texts[top].text == "" then
                anchor, a.y = top, a.y - barH / 2 + size / 2
            else
                notes[#notes + 1] = ("%s: no free spot for the %s text, left out."):format(title, p)
                return
            end
        end
        if anchor:find("LEFT") then a.x = a.x + 3 elseif anchor:find("RIGHT") then a.x = a.x - 3 end
        a.y = math.floor(a.y + 0.5)
        if s[p .. "TextClassColor"] then
            a.colorMode = "CLASS"
        elseif type(s[p .. "TextColorR"]) == "number" then
            a.colorMode = "CUSTOM"
            a.color = { r = s[p .. "TextColorR"], g = Num(s[p .. "TextColorG"], 1), b = Num(s[p .. "TextColorB"], 1) }
            if a.color.r == 1 and a.color.g == 1 and a.color.b == 1 then a.colorMode = "WHITE" end
        end
        texts[anchor] = a
    end
    Slot("left", "LEFT")
    Slot("center", "CENTER")
    Slot("right", "RIGHT")
    local align = G("extraTextAlign")
    Slot("extra", (align == "right" and "RIGHT") or (align == "center" and "CENTER") or "LEFT")
    u.texts.health = texts

    -- power text
    local ptexts = EmptyTexts()
    local ppos = G("powerPercentText")
    if power and ppos and ppos ~= "none" then
        local tpl = POWER_CONTENT[G("powerTextFormat") or "perpp"]
        if tpl then
            local anchor = (ppos == "left" and "LEFT") or (ppos == "right" and "RIGHT") or "CENTER"
            local a = NewAnchor(tpl, Num(G("powerPercentSize"), 9))
            a.x, a.y = Num(s.powerPercentX, 0), Num(s.powerPercentY, 0)
            ptexts[anchor] = a
        else
            notes[#notes + 1] = title .. ": custom power text left out."
        end
    end
    u.texts.power = ptexts

    -- buffs / debuffs (the pet has none in HUF)
    if not ns.UNIT_BY_KEY[key].noAuras and u.buffs and u.debuffs then
        local barW = u.width - (por and u.height or 0)
        local function Row(r, on, anchor, max, size, ox, oy)
            r.enabled = on and AURA_POS[anchor] ~= nil
            if not r.enabled then return end
            r.position = AURA_POS[anchor]
            r.size = math.max(8, math.floor(size + 0.5))
            r.gap = 1
            max = math.max(1, math.floor(max))
            local fit = math.max(1, math.floor((barW + r.gap) / (r.size + r.gap)))
            if r.position == "LEFT" or r.position == "RIGHT" then fit = max end
            r.perRow = math.min(max, fit)
            r.rows = math.max(1, math.ceil(max / r.perRow))
            r.offset = 1
            r.x, r.y = ox, oy
        end
        Row(u.buffs, G("showBuffs"), G("buffAnchor"), Num(G("maxBuffs"), 4), Num(G("buffSize"), 22),
            Num(G("buffOffsetX"), 0), Num(G("buffOffsetY"), 0))
        u.buffs.timer = true
        u.buffs.countSize = math.floor(Num(s.buffStackTextSize, u.buffs.countSize) + 0.5)
        u.buffs.timerText = s.buffShowCooldownText and true or false
        u.buffs.timerSize = Num(s.buffCooldownTextSize, 0)
        Row(u.debuffs, true, G("debuffAnchor"), Num(G("maxDebuffs"), 10), Num(G("debuffSize"), 22),
            Num(G("debuffOffsetX"), 0), Num(G("debuffOffsetY"), 0))
        u.debuffs.mine = s.onlyPlayerDebuffs and true or false
        u.debuffs.timer = true
        u.debuffs.countSize = math.floor(Num(s.debuffStackTextSize, u.debuffs.countSize) + 0.5)
        u.debuffs.timerText = s.debuffShowCooldownText and true or false
        u.debuffs.timerSize = Num(s.debuffCooldownTextSize, 0)
    end
    return src
end

---------------------------------------------------------------------------
-- Nameplates (EllesmereUINameplates)
---------------------------------------------------------------------------
local NP_SLOTS = { { "textSlotTop", "ABOVE" }, { "textSlotLeft", "LEFT" }, { "textSlotCenter", "CENTER" }, { "textSlotRight", "RIGHT" } }
local NP_DEFAULTS = {
    healthBarWidth = 6, healthBarHeight = 17, healthBarTexture = "none",
    showBorder = true, borderSize = 1, borderColor = { r = 0.067, g = 0.067, b = 0.067 },
    textSlotTop = "enemyName", textSlotLeft = "level", textSlotCenter = "none", textSlotRight = "healthPercent",
    textSlotTopSize = 12, textSlotLeftSize = 10, textSlotCenterSize = 10, textSlotRightSize = 10,
    textSlotTopYOffset = 3,
    castBarHeight = 17, castNameSize = 10, castBar = { r = 0.70, g = 0.40, b = 0.90 },
    debuffIconSize = 26, maxDebuffs = 5, debuffSpacing = 2,
    friendlyNameOnly = true, nameplateYOffset = 0,
}
local NP_HEALTH = { healthPercent = "[hp%]", healthPercentNoSign = "[hp%:nosign]", healthNumber = "[hp]" }

local function FontByPath(path)
    if type(path) ~= "string" then return nil end
    local want = path:lower():gsub("/", "\\")
    for _, f in ipairs(ns.fonts) do
        if type(f.path) == "string" and f.path:lower() == want then return f.name end
    end
    return nil
end

local function ConvertNameplates(s, n, notes)
    local function G(k) local v = s[k] if v == nil then v = NP_DEFAULTS[k] end return v end
    n.enabled = true
    n.width = math.floor(150 + Num(G("healthBarWidth"), 6) + 0.5)
    n.height = math.max(2, math.floor(Num(G("healthBarHeight"), 17) + 0.5))
    local texKey = G("healthBarTexture")
    n.texture = (texKey == "blizzard" and "Blizzard") or TextureName(texKey) or "Flat"
    n.borderSize = G("showBorder") and Num(G("borderSize"), 1) or 0
    n.borderColor = Color(G("borderColor"), { r = 0.067, g = 0.067, b = 0.067 })
    n.colorMode = "CLASS"
    n.tappedGray = true
    -- Ellesmere colours hostile mobs with its "enemy" colour, darkened out of combat
    n.reactionColors = "CUSTOM"
    n.hostileColor = Color(s.enemyInCombat, { r = 0.80, g = 0.137, b = 0.137 })
    n.neutralColor = Color(s.neutral, { r = 0.81, g = 0.72, b = 0.19 })
    n.friendlyColor = Color(s.friendlyNPCColor, { r = 0, g = 1, b = 0 })
    local dim = s.darkenEnemiesOOC
    if dim == nil then dim = true end
    n.dimOutOfCombat = dim and true or false
    n.yOffset = math.floor(Num(G("nameplateYOffset"), 0) + 0.5)
    n.font = FontByPath(s.font) or FontName(s.font) or "GLOBAL"

    -- texts: the slot holding the name decides where it goes
    local nameSlot, nameEl, levelSlot, hpSlot, hpEl
    for _, sl in ipairs(NP_SLOTS) do
        local el = G(sl[1])
        if el == "enemyName" or el == "levelName" or el == "nameLevel" then
            if not nameSlot then nameSlot, nameEl = sl, el end
        elseif el == "level" then
            levelSlot = sl
        elseif NP_HEALTH[el] then
            if not hpSlot then hpSlot, hpEl = sl, el end
        elseif el and el ~= "none" then
            notes[#notes + 1] = ("Nameplates: text \"%s\" has no HUF value, left out."):format(tostring(el))
        end
    end
    if nameSlot then
        n.mode = "NAME_BAR"
        n.namePosition = nameSlot[2] == "RIGHT" and "LEFT" or nameSlot[2]
        n.fontSize = math.floor(Num(G(nameSlot[1] .. "Size"), 11) + 0.5)
        n.showLevel = nameEl ~= "enemyName" or levelSlot ~= nil
        n.levelSep = nameEl == "enemyName" and " " or " | "
        if nameEl == "nameLevel" then notes[#notes + 1] = "Nameplates: the level comes before the name in HUF." end
        if nameEl == "enemyName" and levelSlot then notes[#notes + 1] = "Nameplates: the level is shown before the name." end
        if n.namePosition == "ABOVE" then n.nameGap = math.floor(Num(G("textSlotTopYOffset"), 3) + 0.5) end
        if s[nameSlot[1] .. "ClassColor"] or (nameSlot[1] == "textSlotTop" and s.enemyNameTextReactionColor) then
            n.nameColor = "REACTION"
        else
            local c = s[nameSlot[1] .. "Color"]
            if type(c) == "table" and type(c.r) == "number" and not (c.r == 1 and c.g == 1 and c.b == 1) then
                n.nameColor, n.nameCustom = "CUSTOM", Color(c, { r = 1, g = 1, b = 1 })
            else
                n.nameColor = "WHITE"
            end
        end
    else
        n.mode = "BAR"
    end
    n.showHealth = hpSlot ~= nil
    if hpSlot then
        n.healthTag = NP_HEALTH[hpEl]
        n.healthSize = math.floor(Num(G(hpSlot[1] .. "Size"), 10) + 0.5)
        if hpSlot[2] ~= "RIGHT" then notes[#notes + 1] = "Nameplates: the health text is on the right of the bar." end
    end
    n.friendlyMode = G("friendlyNameOnly") and "NAME" or "SAME"
    -- stacking: Ellesmere sets the game's switch (enemies on, friendly off by default)
    n.stackEnemies = (s.stackingEnabled ~= false) and "ON" or "OFF"
    n.stackFriendly = (s.stackingFriendly == true) and "ON" or "OFF"
    n.stackSpacing = math.floor(Num(s.stackSpacingScale, 100) + 0.5)
    -- friendly names: Ellesmere's own size, level and colour (name-only:
    -- class colour with "Class Color Friendly", on by default)
    n.friendlyFontSize = math.floor(Num(s.friendlyNameSize, 15) + 0.5)
    n.friendlyLevel = s.friendlyShowLevel and "SHOW" or "HIDE"
    local classFriendly
    if G("friendlyNameOnly") then classFriendly = s.classColorFriendly ~= false
    else classFriendly = s.friendlyNameClassColor == true end
    n.friendlyNameColor = classFriendly and "REACTION" or "WHITE"

    -- cast bar and debuffs
    n.castHeight = math.max(2, math.floor(Num(G("castBarHeight"), 17) + 0.5))
    n.castFontSize = math.floor(Num(G("castNameSize"), 10) + 0.5)
    n.castColor = Color(G("castBar"), n.castColor)
    n.castIcon = true
    n.auraSize = math.max(8, math.floor(Num(G("debuffIconSize"), 26) + 0.5))
    n.auraMax = math.max(1, math.floor(Num(G("maxDebuffs"), 5)))
    n.auraGap = math.floor(Num(G("debuffSpacing"), 2) + 0.5)
    n.auraTimer = true
    n.auraTimerSize = math.floor(Num(s.auraDurationTextSize, 11) + 0.5)
    -- enemy buffs: Ellesmere's buff slot (off: "none") and its enemy buff
    -- filter (WoW Forever default: all); its dispel glow becomes the type edge
    n.showBuffs = (s.buffSlot or "left") ~= "none"
    local bm = s.npEnemyBuffFilter or "showall"
    n.buffFilter = (bm == "dispellable" and "PURGE") or (bm == "important" and "IMPORTANT_PURGE") or "ALL"
    n.buffMark = s.dispelGlow == true and "GLOW" or "OFF"
    n.auraTooltips = s.showAuraTooltips == true
    -- threat colours on the bar (Ellesmere's default on WoW Forever: always)
    local tmode = s.threatColorMode or "always"
    if s.threatColorHealth == false or tmode == "never" then n.threatBar = "OFF"
    elseif tmode == "instances" then n.threatBar = "INSTANCES"
    else n.threatBar = "ALWAYS" end
    local function TC(key, r, g, b) return Color(s[key], { r = r, g = g, b = b }) end
    n.threatDpsSafeOn = s.dpsNoAggroEnabled == true
    n.threatDpsSafe = TC("dpsNoAggro", 0.35, 0.75, 0.35)
    n.threatDpsNear = TC("dpsNearAggro", 0.81, 0.72, 0.19)
    n.threatDpsAggro = TC("dpsHasAggro", 1.00, 0.50, 0.00)
    n.threatTankHoldOn = s.tankHasAggroEnabled == true or s.classicTankAggro == true
    n.threatTankHold = TC("tankHasAggro", 0.05, 0.82, 0.62)
    n.threatTankLosing = TC("tankLosingAggro", 0.81, 0.72, 0.19)
    n.threatTankLost = TC("tankNoAggro", 1.00, 0.22, 0.17)
    n.threatOffTankOn = s.offTankAggroEnabled ~= false
    n.threatOffTank = TC("offTankAggro", 0.188, 0.761, 0.812)
    if s.threatColorBorder == true or s.threatColorName == true then
        notes[#notes + 1] = "Nameplates: HUF shows threat colours on the bar only (Ellesmere: also on the border or name)."
    end
    notes[#notes + 1] = "Nameplates: Ellesmere's caster and mini-boss colours are not in HUF."
end

---------------------------------------------------------------------------
-- Damage meter (EllesmereUIDamageMeters): its first window -> HUF's meter
---------------------------------------------------------------------------
local DM_SHOW = { always = "ALWAYS", in_party = "GROUP", in_raid = "GROUP" }
local DM_NUMBERS = { [0] = "PERSECOND", [1] = "TOTAL", [2] = "BOTH", [3] = "BAR" }

local function ConvertDamageMeter(addon, m, notes)
    local c = type(addon.dm) == "table" and addon.dm or addon
    local function G(k, d) local v = c[k] if v == nil then return d end return v end
    local list = type(c.windows) == "table" and c.windows or {}
    local w = type(list[1]) == "table" and list[1] or {}
    m.enabled = true
    m.hideBlizzard = true
    m.nameHover = G("showHoverTooltip", true) ~= false

    -- a window's place: unlock format { point, relPoint, x, y } or the older
    -- { x, y } (its top left from the screen's bottom left: taken as its
    -- bottom left, h below, so windows of other heights keep their bottoms)
    local function Point(pos, h)
        if type(pos) ~= "table" then return nil end
        local p1, p2 = pos.point or pos[1], pos.relPoint or pos[2]
        local x, y = pos.x or pos[3], pos.y or pos[4]
        if type(p1) == "string" and type(x) == "number" and type(y) == "number" then
            return { p1, type(p2) == "string" and p2 or p1, math.floor(x + 0.5), math.floor(y + 0.5) }
        elseif type(pos.x) == "number" and type(pos.y) == "number" then
            return { "BOTTOMLEFT", "BOTTOMLEFT", math.floor(pos.x + 0.5), math.floor(pos.y - h + 0.5) }
        end
        return nil
    end
    -- a window's meter type, when HUF has it (Ellesmere stores the game's enum
    -- number, or "threat" for its WoW Forever threat view)
    local function HasType(key)
        for _, t in ipairs((ns.DamageMeter and ns.DamageMeter.TYPES) or {}) do
            if t.key == key then return true end
        end
        return false
    end
    local function MeterType(cur)
        if cur == "threat" then return HasType("Threat") and "Threat" or nil end
        if type(cur) ~= "number" or not (Enum and type(Enum.DamageMeterType) == "table") then return nil end
        for key, v in pairs(Enum.DamageMeterType) do
            if v == cur then
                for _, t in ipairs((ns.DamageMeter and ns.DamageMeter.TYPES) or {}) do
                    if t.key == key then return key end
                end
            end
        end
        return nil
    end

    -- the windows: each its own meter type and place (HUF: up to 5)
    local count = math.max(1, math.min(5, math.floor(Num(G("windowCount"), 1))))
    if Num(G("windowCount"), 1) > 5 then
        notes[#notes + 1] = "Damage meter: HUF has up to 5 windows; the first 5 of Ellesmere's are taken."
    end
    -- rows of a window from its height (Ellesmere's has the title bar in it).
    -- Ellesmere draws a bar's border inside the bar, HUF around it: with a
    -- border the bar is 2 x border lower and the gap 2 x border wider, so the
    -- rows keep their spacing and neighbouring borders fall on one line.
    local rb = math.max(0, math.floor(Num(G("borderSize"), 0) + 0.5))
    local barH, spacing = Num(G("barHeight"), 18), Num(G("barSpacing"), 2)
    local rowHeight = math.max(8, math.floor(barH - 2 * rb + 0.5))
    local rowGap = math.max(0, math.floor(spacing + 2 * rb + 0.5))
    local function RowsFor(h)
        local body = h - Num(G("hdrHeight"), 22)
        return math.max(1, math.min(40, math.floor((body + rowGap) / (rowHeight + rowGap))))
    end
    local windows = {}
    for i = 1, count do
        local e = type(list[i]) == "table" and list[i] or {}
        local h = Num(e.height, 150)
        local before = windows[i - 1]
        local point = Point(e.position, h)
            or (before and { before.point[1], before.point[2], before.point[3] - Num(w.width, 375) - 8, before.point[4] })
            or ns.CopyTable(m.point)
        -- each window its own height (HUF: windows[i].rows over the shared rows)
        windows[i] = { meterType = MeterType(e.curDMType) or "DamageDone", session = "CURRENT", point = point,
                       rows = RowsFor(h),
                       -- each its own width too (Ellesmere's can differ by a pixel)
                       width = type(e.width) == "number" and math.floor(e.width + 0.5) or nil }
    end
    m.windows, m.windowCount = windows, count
    m.point = ns.CopyTable(windows[1].point)
    m.meterType, m.session = windows[1].meterType, "CURRENT"

    -- width: shared by HUF's windows, Ellesmere's first one's
    m.width = math.max(100, math.floor(Num(w.width, 375) + 0.5))
    m.rowHeight, m.rowGap = rowHeight, rowGap
    m.rows = windows[1].rows
    m.locked = w.locked and true or false
    for i = 2, count do
        local e = list[i]
        if type(e) == "table" and math.abs(Num(e.width, m.width) - m.width) > 4 then
            notes[#notes + 1] = "Damage meter: HUF's windows share one width; the first window's is taken."
            break
        end
    end

    -- look
    m.texture = TextureName(G("barTexture", "atrocity")) or "Flat"
    m.bgColor = { r = Num(G("bgR"), 0), g = Num(G("bgG"), 0), b = Num(G("bgB"), 0) }
    m.windowBorder = Num(G("windowBorderSize"), 0) > 0
    m.titleHeight = math.max(12, math.min(30, math.floor(Num(G("hdrHeight"), 22) + 0.5)))
    m.titleColor = Color(G("hdrBgColor"), { r = 0x1B / 255, g = 0x1B / 255, b = 0x1B / 255 })
    m.titleAlpha = Num(G("hdrBgAlpha"), 1)
    m.titleLine = Num(G("hdrBottomBorderSize"), 0) > 0 or G("hdrBottomSeparator", false) == true
    m.titleAccent = G("hdrTextUseAccent", true) and true or false
    m.titleIcons = true                 -- Ellesmere's title bar has icon buttons
    m.titleIconsMuted = true            -- single-coloured there too
    -- Ellesmere's header icons are thin glyphs that may be larger than its
    -- bar; HUF's are square spell icons: inside the title bar
    m.titleIconSize = math.max(10, math.min(m.titleHeight - 2, math.floor(Num(G("hdrIconSize"), 22) + 0.5)))
    m.icons = (G("iconStyle", "spec") ~= "none") and "CLASS" or "NONE"
    m.rowBorder = rb
    m.barBgColor = { r = Num(G("barBgR"), 0), g = Num(G("barBgG"), 0), b = Num(G("barBgB"), 0) }
    m.barBgAlpha = Num(G("barBgAlpha"), 0)
    if G("showClassColor", true) then
        m.colorMode = "CLASS"
    elseif G("barColorUseAccent", true) then
        m.colorMode = "ACCENT"
    else
        m.colorMode = "STATIC"
        m.color = Color(G("barColor"), m.color)
    end
    m.bgAlpha = Num(G("bgAlpha"), 0.75)
    m.fontSize = math.floor(Num(G("leftFontSize"), Num(G("fontSize"), 11)) + 0.5)
    m.titleSize = math.floor(Num(G("hdrFontSize"), 11) + 0.5)
    m.numbers = DM_NUMBERS[G("numberFormat", 2)] or "BOTH"

    -- when it shows. Ellesmere doesn't fade out of combat: HUF's fading off,
    -- except for "in combat" / "mouseover" (out of combat invisible, the
    -- mouse brings it back)
    local vis = G("visibility", "always")
    m.show = "ALWAYS"
    m.fadeOOC = false
    if w.hideOutOfInstance then
        m.show = "INSTANCE"
    elseif DM_SHOW[vis] then
        m.show = DM_SHOW[vis]
    elseif vis == "in_combat" or vis == "mouseover" then
        m.fadeOOC, m.fadeAlpha = true, 0
        if vis == "mouseover" then
            notes[#notes + 1] = "Damage meter: \"mouseover\" becomes invisible out of combat (shown in combat and under the mouse)."
        end
    else
        notes[#notes + 1] = ("Damage meter: \"%s\" visibility is not in HUF, it shows always."):format(tostring(vis))
    end
end

---------------------------------------------------------------------------
-- Group frames (EllesmereUIRaidFrames: its party size, raid look)
---------------------------------------------------------------------------
local GROWTH = { DOWN = "DOWN", UP = "UP", RIGHT = "RIGHT", LEFT = "LEFT" }
local RF_SPOT = { topleft = "TOPLEFT", top = "TOP", topright = "TOPRIGHT", left = "LEFT", center = "CENTER",
    right = "RIGHT", bottomleft = "BOTTOMLEFT", bottom = "BOTTOM", bottomright = "BOTTOMRIGHT" }
local RF_HP = { percent = "[hp%]", number = "[hp]" }
local RF_MP = { percent = "[mp%]", percentNoSign = "[mp%]", number = "[mp]", numberPercent = "[mp] | [mp%]", percentNumber = "[mp%] | [mp]" }
local function ConvertGroup(rf, g, notes)
    -- party frames read Ellesmere's party_<key> where it set one apart from
    -- the raid's, else the raid's
    local function G(k, d)
        local v = rf["party_" .. k]
        if v == nil then v = rf[k] end
        if v == nil then return d end
        return v
    end
    local bs = math.max(0, math.floor(Num(G("borderSize"), 1) + 0.5))
    g.enabled = true
    g.width = math.max(40, math.floor(Num(G("partyFrameWidth"), Num(G("frameWidth"), 125)) - 2 * bs + 0.5))
    g.height = math.max(10, math.floor(Num(G("partyFrameHeight"), Num(G("frameHeight"), 60)) - 2 * bs + 0.5))
    local power = G("showPowerBar", true) and true or false
    g.power.enabled = power
    g.power.size = math.max(1, math.floor(Num(G("powerHeight"), 4) + 0.5))
    g.power.gap = 0
    g.power.divider = false
    local tex = TextureName(G("healthBarTexture", "atrocity")) or "Flat"
    local bg = Color(G("customBgColor"), { r = 17 / 255, g = 17 / 255, b = 17 / 255 })
    for _, which in ipairs({ "health", "power" }) do
        local b = g[which]
        b.texture = tex
        b.borderSize = bs
        b.borderColor = Color(G("borderColor"), { r = 0, g = 0, b = 0 })
        b.bgTexture, b.bgColor, b.bgAlpha = "Plain", ns.CopyTable(bg), 1
    end
    local mode = G("healthColorMode", "class")
    if mode == "class" or mode == "classReactive" then
        g.health.colorMode = "CLASS"
    else
        g.health.colorMode = "STATIC"
        g.health.color = Color(G("customFillColor"), { r = 37 / 255, g = 193 / 255, b = 29 / 255 })
        if mode ~= "custom" then notes[#notes + 1] = ("Group: health colour \"%s\" is a static colour in HUF."):format(tostring(mode)) end
    end
    if type(g.healPred) == "table" then g.healPred.enabled = G("healPrediction", false) == true end
    -- texts: Ellesmere's name (with the level before it), health and power
    -- texts over the frame; HUF's own group texts go
    local th, tp = EmptyTexts(), EmptyTexts()
    local function Put(set, spot, tpl, size, cm, col, x, y)
        local anchor = RF_SPOT[spot or "center"] or "CENTER"
        if set[anchor].text ~= "" then return end
        local a = NewAnchor(tpl, math.floor(Num(size, 10) + 0.5))
        a.x, a.y = math.floor(Num(x, 0) + 0.5), math.floor(Num(y, 0) + 0.5)
        if cm == "class" then a.colorMode = "CLASS"
        elseif cm == "accent" then a.colorMode = "ACCENT"
        elseif type(col) == "table" and not (col.r == 1 and col.g == 1 and col.b == 1) then
            a.colorMode, a.color = "CUSTOM", Color(col, { r = 1, g = 1, b = 1 })
        end
        set[anchor] = a
    end
    local lvl = G("levelTextPosition", "name")
    local nameTpl = (lvl == "name" and "[level] [name]") or (lvl == "nameDiv" and "[level] | [name]") or "[name]"
    Put(th, G("namePosition", "topleft"), nameTpl, G("nameSize", 10), G("nameColorMode", "custom"), G("nameCustomColor"),
        G("nameOffsetX"), G("nameOffsetY"))
    if RF_SPOT[lvl] then Put(th, lvl, "[level]", G("levelTextSize", 10), "custom", nil, G("levelTextOffsetX"), G("levelTextOffsetY")) end
    local hp = RF_HP[G("healthTextMode", "none")]
    if hp then
        Put(th, G("healthTextPosition", "center"), hp, G("healthTextSize", 9), G("healthTextColorMode", "custom"),
            G("healthTextCustomColor"), G("healthTextOffsetX"), G("healthTextOffsetY"))
    end
    local mp = RF_MP[G("powerTextMode", "none")]
    if mp and power then
        Put(tp, G("powerTextPosition", "bottom"), mp, G("powerTextSize", 8), G("powerTextColorMode", "custom"),
            G("powerTextCustomColor"), G("powerTextOffsetX"), G("powerTextOffsetY"))
    end
    g.texts.health, g.texts.power = th, tp
    -- debuffs: on the health bar, where Ellesmere puts them, filtered as its
    -- Debuff Manager filters them
    local d = g.debuffs
    if d then
        local pos = tostring(G("debuffPosition", "bottomright"))
        local grow = G("debuffGrowDirection", "LEFT")
        d.position = RF_DEBUFF_POS[pos] or "INSIDE_BOTTOMRIGHT"
        d.grow = "AUTO"
        if grow == "CENTER" then
            d.position = (pos:find("top") and "INSIDE_TOP") or (pos:find("bottom") and "INSIDE_BOTTOM") or "INSIDE_CENTER"
        elseif grow == "LEFT" or grow == "RIGHT" then
            local p = ns.Frame.AURA_POS[d.position]
            if p and p[4] ~= grow then d.grow = grow end
        else
            notes[#notes + 1] = "Group: debuffs grow sideways in HUF (Ellesmere: up or down)."
        end
        d.offset = 0
        d.x = math.floor(Num(G("debuffOffsetX"), 0) + 0.5)
        d.y = math.floor(Num(G("debuffOffsetY"), 0) + 0.5)
        -- HUF's frame includes the power bar: lift bottom rows onto the health bar
        if power and d.position:find("BOTTOM") then d.y = d.y + g.power.size + (g.power.gap or 0) end
        d.size = math.max(8, math.floor(Num(G("debuffSize"), 18) + 0.5))
        d.gap = math.max(0, math.floor(Num(G("debuffSpacing"), 1) + 0.5))
        local cap = math.max(1, math.floor(Num(G("debuffCap"), 3) + 0.5))
        local per = math.max(1, math.floor(Num(G("debuffPerRow"), 5) + 0.5))
        d.perRow = math.min(per, cap)
        d.rows = math.min(6, math.ceil(cap / d.perRow))
        d.borderSize = math.max(0, math.floor(Num(G("debuffBorderSize"), 1) + 0.5))
        d.dispelBorder = true
        -- Ellesmere's dispel border round the frame (size 0: off)
        local db = math.floor(Num(G("dispelBorderSize"), 0) + 0.5)
        d.debuffEdge = db > 0 and "AUTO" or "OFF"
        if db > 0 then d.dispelEdgeSize = math.min(6, db) end
        d.countSize = math.max(6, math.floor(Num(G("debuffStacksTextSize"), 8) + 0.5))
        d.timer = G("debuffShowSwipe", true) ~= false
        d.timerText = G("debuffShowDurText", false) == true
        d.timerSize = math.floor(Num(G("debuffDurTextSize"), 0) + 0.5)
        d.hideSated = G("hideLustDebuff", true) ~= false
        d.mine = false
        d.enabled = true
        -- filters: the Debuff Manager, or the older preset before it
        local dm = rf.dmDebuff
        local filter, cc = "ALL", true
        if type(dm) == "table" then
            local neg = type(dm.neg) == "table" and dm.neg or {}
            if dm.all ~= false then
                cc = not neg.cc
                local hid = {}
                for _, k in ipairs({ "boss", "role", "priority", "raid", "raidcombat", "dispel", "nonplayer" }) do
                    if neg[k] then hid[#hid + 1] = k end
                end
                if #hid > 0 then
                    notes[#notes + 1] = "Group: HUF shows all debuffs; Ellesmere hid these kinds: " .. table.concat(hid, ", ") .. "."
                end
            else
                cc = dm.cc == true
                if dm.dispel then filter = (dm.dispelMode == "typed") and "TEAM" or "DISPELLABLE"
                elseif dm.raid or dm.raidcombat then filter = "RAID"
                elseif cc then filter, cc = "CC", false
                else filter = nil end
                local other = {}
                for _, k in ipairs({ "boss", "role", "priority", "nonplayer" }) do
                    if dm[k] then other[#other + 1] = k end
                end
                if filter == nil and #other > 0 then filter = "RAID" end
                if #other > 0 then
                    notes[#notes + 1] = ("Group: Ellesmere's debuff kinds %s are not in HUF; it shows the %s debuffs."):format(
                        table.concat(other, ", "), filter == "RAID" and "important" or "picked")
                end
                if filter == "TEAM" then
                    notes[#notes + 1] = "Group: Ellesmere's \"any dispel type\" debuffs become HUF's \"Ones my group can dispel\"."
                end
            end
            if type(dm.tiles) == "table" and next(dm.tiles) then
                notes[#notes + 1] = "Group: Ellesmere's extra debuff spots (Debuff Manager tiles) are not in HUF."
            end
        else
            local preset = G("debuffFilter", "all")
            if preset == "raid" then filter = "RAID"
            elseif preset == "dispellable" then filter = "DISPELLABLE"
            elseif preset == "none" then filter = nil end
        end
        if filter then d.filter, d.ccFirst = filter, cc and true or false
        else d.enabled = false end
    end
    -- buffs: Ellesmere shows them only as its buff indicators (none set by
    -- default); debuffs stay
    local ind = G("bmIndicators")
    local anyInd = false
    if type(ind) == "table" then for _, list in pairs(ind) do if type(list) == "table" and next(list) then anyInd = true end end end
    if g.buffs then g.buffs.enabled = anyInd end
    if anyInd then notes[#notes + 1] = "Group: Ellesmere's buff indicators become HUF's buff row (your HoTs)." end
    if G("powerShowForDPS", false) == false and power then
        notes[#notes + 1] = "Group: HUF shows the power bar for every role (Ellesmere: healers and tanks)."
    end
    if G("roleIconStyle", "modern") ~= "none" then notes[#notes + 1] = "Group: HUF has no role icons." end

    g.group = g.group or {}
    -- party direction: down (or up), sideways with \"horizontal\"
    local horiz, flip = G("partyHorizontal", false) == true, G("partyFlipGrowth", false) == true
    g.group.orientation = horiz and (flip and "LEFT" or "RIGHT") or (flip and "UP" or "DOWN")
    g.group.spacing = math.max(0, math.floor(Num(rf.partyCellSpacing, Num(G("cellSpacing"), -1)) + 2 * bs + 0.5))
    g.group.spacingH = g.group.spacing

    -- place: the first member's top left (HUF's point), border inside as
    -- Ellesmere draws it. From the screen when Ellesmere's party header shows,
    -- else from its saved place of the 5-slot party block (partyUnlockPos)
    local fw, fh = Num(G("partyFrameWidth"), 125), Num(G("partyFrameHeight"), 60)
    local hdr = _G.ERFPartyHeader
    local ui = UIParent:GetEffectiveScale()
    local left, top = hdr and hdr:IsVisible() and hdr:GetLeft(), hdr and hdr:IsVisible() and hdr:GetTop()
    if left and top and ui and ui > 0 then
        local es = hdr:GetEffectiveScale()
        g.anchorTo = "SCREEN"
        g.point = { "TOPLEFT", "BOTTOMLEFT", math.floor(left * es / ui + bs + 0.5), math.floor(top * es / ui - bs + 0.5) }
    else
        local pos = rf.partyUnlockPos
        if type(pos) == "table" and type(pos.x) == "number" and type(pos.y) == "number" then
            local gap = Num(rf.partyCellSpacing, Num(G("cellSpacing"), -1))
            local bw = horiz and (5 * fw + 4 * gap) or fw
            local bh = horiz and fh or (5 * fh + 4 * gap)
            local pt = pos.point or "CENTER"
            -- the anchor point's place in the block, from its top left
            local ox = (pt:find("LEFT") and 0) or (pt:find("RIGHT") and bw) or bw / 2
            local oy = (pt:find("TOP") and 0) or (pt:find("BOTTOM") and -bh) or -bh / 2
            g.anchorTo = "SCREEN"
            g.point = { "TOPLEFT", pos.relPoint or pt, math.floor(pos.x - ox + bs + 0.5), math.floor(pos.y - oy - bs + 0.5) }
        end
    end
    g.group.sort = (G("sortMode", "ROLE") == "INDEX") and "INDEX" or "NAME"
    g.group.showPlayer = true
end

---------------------------------------------------------------------------
-- Minimap (EllesmereUIMinimap)
---------------------------------------------------------------------------
local MM_FOLDER = "EllesmereUIMinimap"
-- Ellesmere's position keys -> HUF's (inside the map, or above / below it)
local MM_POS = {
    belowMap = "BELOW", aboveMap = "ABOVE", topLeft = "TOPLEFT", top = "TOP", topRight = "TOPRIGHT",
    left = "LEFT", right = "RIGHT", bottomLeft = "BOTTOMLEFT", bottom = "BOTTOM", bottomRight = "BOTTOMRIGHT",
    center = "CENTER",
}
local MM_CORNER = { TOPLEFT = "TOPLEFT", TOPRIGHT = "TOPRIGHT", BOTTOMLEFT = "BOTTOMLEFT", BOTTOMRIGHT = "BOTTOMRIGHT",
    TOP = "TOP", BOTTOM = "BOTTOM", LEFT = "LEFT", RIGHT = "RIGHT" }

local function ConvertMinimap(addon, m, notes)
    local p = type(addon.minimap) == "table" and addon.minimap or addon
    local function G(k, d) local v = p[k] if v == nil then return d end return v end
    m.enabled = true
    m.shape = (G("shape", "square") == "square") and "SQUARE" or "ROUND"
    m.size = math.max(80, math.floor(Num(G("mapSize"), 140) + 0.5))
    local pos = G("position")
    if type(pos) == "table" and type(pos.x) == "number" and type(pos.y) == "number" then
        m.point = { pos.point or "CENTER", pos.relPoint or pos.point or "CENTER", math.floor(pos.x + 0.5), math.floor(pos.y + 0.5) }
    end
    -- border: Ellesmere's, no shade around the map
    m.borderSize = math.max(0, math.floor(Num(G("borderSize"), 1) + 0.5))
    m.borderAccent = false
    if G("useClassColor", false) or G("borderUseClassColor", false) then
        local cc = ns.ClassColor(select(2, UnitClass("player")))
        if cc then m.borderColor = { r = cc.r, g = cc.g, b = cc.b } end
    elseif type(G("borderColor")) == "table" then
        m.borderColor = Color(G("borderColor"), { r = 0, g = 0, b = 0 })
    else
        m.borderColor = { r = Num(G("borderR"), 0), g = Num(G("borderG"), 0), b = Num(G("borderB"), 0) }
    end
    m.shade = 0
    m.mouseZoom = G("scrollZoom", true) and true or false
    m.zoomReset = math.max(0, math.floor(Num(G("zoomResetSeconds"), 0) + 0.5))
    m.rotate = G("rotateMinimap", false) and "ON" or "OFF"
    -- when it shows
    local VIS = { always = "ALWAYS", in_combat = "COMBAT", out_of_combat = "NOCOMBAT", mouseover = "HOVER" }
    local vis = G("visibility", "always")
    m.visibility = VIS[vis] or "ALWAYS"
    if not VIS[vis] then notes[#notes + 1] = ("Minimap: visibility \"%s\" is not in HUF, it shows always."):format(tostring(vis)) end
    m.opacity = math.max(0.1, math.min(1, Num(G("opacity"), 100) / 100))
    m.onlyInstances = G("visOnlyInstances", false) and true or false
    m.hideMounted = G("visHideMounted", false) and true or false
    -- Ellesmere's map texts: a soft shadow, not a hard outline (HUF's general
    -- shadow setting draws it), a little see-through
    m.outline = "NONE"
    m.textAlpha = 0.9

    -- texts: Ellesmere's size 10 x its scale; "edge" = just outside the map
    -- Ellesmere keeps its texts 6 px in from the map's edges (4, and 2 more
    -- past its square rim), then adds the offset they were dragged to
    -- (<off>OffsetX / Y, in the text's scale)
    local INSET = 6
    local function Place(t, mode, posKey, scale, base, off)
        if mode == "none" then t.mode = "NEVER" return end
        t.mode = (mode == "hover" or mode == "mouseover") and "HOVER" or "ALWAYS"
        local hp = MM_POS[posKey or "top"] or "TOP"
        if mode == "edge" then hp = (posKey == "bottom" or posKey == "belowMap") and "BELOW" or "ABOVE" end
        local x, y = 0, 0
        if hp ~= "BELOW" and hp ~= "ABOVE" and hp ~= "CENTER" then
            if hp:find("LEFT") then x = INSET elseif hp:find("RIGHT") then x = -INSET end
            if hp:find("TOP") then y = -INSET elseif hp:find("BOTTOM") then y = INSET end
        end
        local sc = Num(scale, 1)
        if off then
            x = x + Num(G(off .. "OffsetX"), 0) * sc
            y = y + Num(G(off .. "OffsetY"), 0) * sc
        end
        t.pos, t.x, t.y = hp, math.floor(x + 0.5), math.floor(y + 0.5)
        t.size = math.max(6, math.floor(Num(base, 10) * Num(scale, 1.15) + 0.5))
    end
    -- the older settings carry zoneInside / clockInside instead of the modes
    local clockMode = G("clockMode") or ((G("showClock") == false) and "none") or ((G("clockInside") == false) and "edge" or "inside")
    local locMode = G("locationMode") or ((G("hideZoneText") == true) and "none") or (G("zoneInside") and "inside" or "edge")
    local tx = m.texts
    Place(tx.zone, locMode, G("locationPosition", "bottom"), G("locationScale", 1.15), nil, "location")
    tx.zone.color = G("zoneReactiveColor", false) and "ZONE" or "WHITE"
    tx.zone.sub = G("zoneShowSubZone", false) and true or false
    Place(tx.clock, clockMode, G("clockPosition", "top"), G("clockScale", 1.15), nil, "clock")
    tx.clock.format = (G("clockFormat", "12h") == "24h") and "24" or "12"
    local cMode = G("coordsMode") or (G("coordsBelow") and "always") or "always"
    if G("showCoords") == false and G("coordsMode") == nil and not G("coordsBelow") then cMode = "none" end
    Place(tx.coords, cMode, G("coordsPosition") or (G("coordsBelow") and "belowMap") or "topLeft", G("coordsScale", 1), nil, "coordsBelow")
    tx.coords.decimals = math.floor(Num(G("coordPrecision"), 0))
    Place(tx.system, G("showFPS", false) and "always" or "none", G("fpsPosition", "bottomLeft"), G("fpsScale", 1), Num(G("fpsTextSize"), 12), "fps")
    local lms, wms = G("fpsShowLocalMS", true), G("fpsShowWorldMS", false)
    tx.system.show = (lms or wms) and "BOTH" or "FPS"
    tx.system.latency = (lms and wms and "HIGHER") or (wms and "WORLD") or "HOME"

    -- the game's icons Ellesmere hides; the others keep HUF's places
    local ic = m.icons
    local function Off(key, hide) if hide and ic[key] then ic[key].mode = "NEVER" end end
    Off("zoom", G("hideZoomButtons", false))
    Off("tracking", G("hideTrackingButton", false))
    Off("calendar", G("hideGameTime", false))
    Off("mail", G("hideMail", false))
    Off("crafting", G("hideCraftingOrder", false))
    Off("difficulty", G("hideRaidDifficulty", false))
    local mp = MM_CORNER[G("mailPosition", "button")]
    if mp and ic.mail and ic.mail.mode ~= "NEVER" then ic.mail.pos, ic.mail.x, ic.mail.y = mp, 0, 0 end
    -- Ellesmere's difficulty text: HUF's difficulty text (the game's icon stays as set above)
    if tx.difficulty then
        if G("diffTextEnabled", false) then
            tx.difficulty.mode = "ALWAYS"
            tx.difficulty.pos = MM_POS[G("diffTextPosition", "topLeft")] or "TOPLEFT"
            local dp = tx.difficulty.pos
            local ix = dp:find("LEFT") and INSET or dp:find("RIGHT") and -INSET or 0
            local iy = dp:find("TOP") and -INSET or dp:find("BOTTOM") and INSET or 0
            tx.difficulty.x = math.floor(ix + Num(G("diffTextOffsetX"), 0) + 0.5)
            tx.difficulty.y = math.floor(iy + Num(G("diffTextOffsetY"), 0) + 0.5)
            tx.difficulty.size = math.floor(Num(G("diffTextSize"), 12) + 0.5)
            tx.difficulty.color = G("diffTextAccent", false) and "ACCENT" or "WHITE"
        else
            tx.difficulty.mode = "NEVER"
        end
    end

    -- Ellesmere's element row (tracking) under the map's left edge, its
    -- button flyout in the map's lower left
    if ic.tracking and ic.tracking.mode ~= "NEVER" then
        ic.tracking.mode, ic.tracking.pos, ic.tracking.x, ic.tracking.y = "ALWAYS", "BELOW_LEFT", 0, -(m.borderSize + 1)
    end
    if ic.addonbar then
        ic.addonbar.mode, ic.addonbar.pos, ic.addonbar.y = "ALWAYS", "OUTSIDE_LEFT_BOTTOM", 0
        ic.addonbar.x = -(4 + math.floor(Num(G("btnRowDistance"), 0) + 0.5))      -- Ellesmere's row distance
    end

    -- addon buttons: Ellesmere gathers them in its flyout; HUF's addon bar
    if not G("hideAddonButtons", false) then
        m.addonBar = true
        m.barIconSize = math.max(16, math.floor(Num(G("addonBtnSize"), 24) + 0.5))
        -- Ellesmere's flyout: a grid, 4 wide, square buttons on dark backgrounds
        m.barLayout = G("flyoutAsList", false) and "LIST" or "GRID"
        local GROW = { auto = "AUTO", up = "UP", down = "DOWN", left = "LEFT", right = "RIGHT" }
        m.barGrow = GROW[G("flyoutGrowDir", "auto")] or "AUTO"
        m.barColumns = 4
        m.barSquare = G("btnBackgrounds", true) and true or false
    else
        m.addonBar, m.buttonMode = false, "NEVER"
    end
    -- the buttons Ellesmere keeps out of its flyout: pinned by the bag, in its order
    local ung = G("ungroupedButtons")
    if type(ung) == "table" then
        m.pinOrder = m.pinOrder or {}
        for name, place in pairs(ung) do
            if type(name) == "string" and name ~= "EllesmereUIMinimapButton" then
                m.buttons[name] = "PIN"
                m.pinOrder[name] = Num(place, 99)
            end
        end
        m.pinGrow = "UP"
        m.pinGap = 4 + math.floor(Num(G("btnRowSpacing"), 0) + 0.5)   -- room between the buttons (+ Ellesmere's spacing)
    end
end

-- Ellesmere's "Minimap Companion" data bar (EllesmereUIDataBars) -> HUF's
-- minimap data bar: on, height, background; its micro menu's social / guild
local DB_FOLDER = "EllesmereUIDataBars"
local function ConvertDataBar(addon, d, notes)
    local found
    for _, b in pairs(type(addon.bars) == "table" and addon.bars or {}) do
        if type(b) == "table" and (b.name == "Minimap Companion") then found = b end
    end
    if not found then return false end
    d.enabled = true
    d.position = "BELOW"
    d.height = math.max(14, math.floor(Num(found.thickness, 24) + 0.5))
    local th = type(found.theme) == "table" and found.theme or {}
    local mc = type(th.modernColor) == "table" and th.modernColor
    if mc then
        d.bgColor = Color(mc, d.bgColor)
        d.bgAlpha = Num(mc.a, 0.95)
    end
    d.borderSize = found.hideBorder and 0 or 1
    local social, guild = false, false
    for _, blk in pairs(type(found.blocks) == "table" and found.blocks or {}) do
        if type(blk) == "table" and blk.type == "micromenu" then
            local st = type(blk.settings) == "table" and blk.settings or {}
            social = social or st.social == true
            guild = guild or st.guild == true
            -- its icon colour: class / accent / own; otherwise HUF's flat grey
            if blk.useIconClassColor then d.iconColor = "CLASS"
            elseif blk.useIconAccentColor then d.iconColor = "ACCENT"
            elseif not blk.useIconDefaultColor and type(blk.iconColor) == "table" then
                d.iconColor, d.iconCustom = "CUSTOM", Color(blk.iconColor, d.iconCustom)
            else d.iconColor = "MONO" end
        end
    end
    d.friends, d.guild = social, guild
    d.layout = "STACK"                  -- Ellesmere's micro menu: the count above the icon
    d.fontSize = 11
    notes[#notes + 1] = "Minimap data bar: hide Ellesmere's Minimap Companion bar in its Data Bars (its other bars stay)."
    return true
end


-- Ellesmere's other data bars (not the Minimap Companion): one HUF bar each,
-- with the blocks HUF has. Returns the bars; the block types left out go in
-- the notes.
local DB_VIS = { always = "ALWAYS", in_combat = "COMBAT", out_of_combat = "NOCOMBAT", mouseover = "HOVER", never = "NEVER" }
local function BlockColors(blk, c)
    if blk.useClassColor then c.textColor = "CLASS"
    elseif blk.useAccentColor then c.textColor = "ACCENT"
    elseif blk.useDynamicColor then c.textColor = "DYNAMIC"
    elseif type(blk.color) == "table" then c.textColor, c.textCustom = "CUSTOM", Color(blk.color, c.textCustom)
    else c.textColor = "WHITE" end
    if blk.useIconClassColor then c.iconColor = "CLASS"
    elseif blk.useIconAccentColor then c.iconColor = "ACCENT"
    elseif not blk.useIconDefaultColor and type(blk.iconColor) == "table" then
        c.iconColor, c.iconCustom = "CUSTOM", Color(blk.iconColor, c.iconCustom)
    else c.iconColor = "MONO" end
end
-- adds the block's HUF block(s) to out; returns its type when HUF has none
local function ConvertBlock(blk, bar, out)
    local BL = ns.DataBlocks
    local st = type(blk.settings) == "table" and blk.settings or {}
    local function Add(key)
        local c = BL.New(key)
        c.scale = math.floor(Num(blk.scale, 100) + 0.5)
        local al = blk.align
        c.align = (al == "LEFT" or al == "RIGHT") and al or "CENTER"
        local base = Num(blk.contentGap, 10)
        c.padL = math.floor(Num(blk.contentGapL, base) + 0.5)
        c.padR = math.floor(Num(blk.contentGapR, base) + 0.5)
        c.fill = bar.fillBlockId ~= nil and blk.id == bar.fillBlockId
        c.center = bar.centerBlockId ~= nil and blk.id == bar.centerBlockId
        BlockColors(blk, c)
        if st.showIcon ~= nil then c.showIcon = st.showIcon and true or false end
        out[#out + 1] = c
        return c
    end
    local t = blk.type
    if t == "fps" or t == "durability" then
        Add(t)
    elseif t == "ms" then
        local c = Add("ms")
        local m = st.latencyMode
        c.settings.latency = (m == "world" and "WORLD") or ((m == "both" or m == "higher") and "HIGHER") or "HOME"
    elseif t == "clock" then
        local c = Add("clock")
        -- Ellesmere's clock text is 22 where the others are 13
        c.scale = math.floor(c.scale * 22 / 13 + 0.5)
        c.settings.twentyFour = st.twentyFour ~= false
        c.settings.localTime = st.localTime ~= false
    elseif t == "gold" then
        local c = Add("gold")
        c.settings.showSmall = st.showSmall and true or false
        c.settings.coinIcons = st.coinIcons and true or false
        c.settings.coinColor = blk.useCoinColor and true or false
        c.settings.abbreviate = st.abbreviate and true or false
        c.showIcon = false
    elseif t == "audio" then
        local c = Add("audio")
        local ch = st.channel or "master"
        c.settings.channel = BL.CHANNELS[ch] and ch or "master"
        c.settings.style = "BAR"            -- Ellesmere shows the volume as a bar
    elseif t == "combat" then
        local c = Add("combat")
        c.settings.onlyInCombat = st.onlyInCombat and true or false
        if c.textColor == "WHITE" then c.textColor = "DYNAMIC" end
    elseif t == "micromenu" then
        if st.social then Add("friends") end
        if st.guild then Add("guild") end
        if not (st.social or st.guild) then return t end
    else
        return t
    end
end
local function ConvertBars(addon, notes)
    local bars, skipped, seen = {}, {}, {}
    for _, b in ipairs(type(addon.bars) == "table" and addon.bars or {}) do
        if type(b) == "table" and b.name ~= "Minimap Companion" then
            if b.orientation == "V" then
                notes[#notes + 1] = ("Data bar \"%s\": upright bars are not in HUF yet; left out."):format(tostring(b.name))
            else
                local c = ns.CopyTable(ns.DataBars.BAR_DEFAULTS)
                c.name = tostring(b.name or ("Bar " .. (#bars + 1)))
                c.enabled = true
                c.visibility = DB_VIS[b.visibility] or "ALWAYS"
                local sp = type(b.savedPos) == "table" and b.savedPos or {}
                c.point, c.relPoint = sp.point or "CENTER", sp.relPoint or sp.point or "CENTER"
                c.x, c.y = math.floor(Num(sp.x, 0) + 0.5), math.floor(Num(sp.y, 0) + 0.5)
                if b.lengthMode == "full" then c.width = math.floor(UIParent:GetWidth() + 0.5)
                else c.width = math.floor(Num(b.length, 400) + 0.5) end
                c.height = math.max(10, math.floor(Num(b.thickness, 22) + 0.5))
                local th = type(b.theme) == "table" and b.theme or {}
                if th.style == "modern" then
                    c.look = "FLAT"
                    local mc = type(th.modernColor) == "table" and th.modernColor
                    if mc then c.bgColor, c.bgAlpha = Color(mc, c.bgColor), Num(mc.a, 0.95) end
                else
                    -- Ellesmere's own background art (HUF draws it from EllesmereUI's folder)
                    c.look = "EUI"
                    c.softAlpha = Num(th.euiAlpha, 0.5)
                    c.artOpacity = Num(th.euiOpacity, 1)
                end
                c.borderSize = b.hideBorder and 0 or 1
                c.sizing = (b.sizingMode == "even") and "EVEN" or "AUTO"
                -- Ellesmere's block text is 13 at 100 % (its clock 22: see the clock block)
                c.fontSize = math.max(6, math.floor(13 * Num(b.fontScale, 100) / 100 + 0.5))
                c.blocks = {}
                for _, blk in ipairs(type(b.blocks) == "table" and b.blocks or {}) do
                    if type(blk) == "table" then
                        local left = ConvertBlock(blk, b, c.blocks)
                        if left and not seen[left] then seen[left] = true skipped[#skipped + 1] = left end
                    end
                end
                bars[#bars + 1] = c
            end
        end
    end
    if #skipped > 0 then
        notes[#notes + 1] = "Data bars: blocks not in HUF yet, left out: " .. table.concat(skipped, ", ") .. "."
    end
    return bars
end

---------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------
-- prof: Ellesmere profile data (addons, fonts); uf / np its Unit Frames /
-- Nameplates settings (nil: not there)
-- npOn: false when Ellesmere's nameplates are off (not loaded)
-- parts: what the import turns on or off, for the import window:
--   { title, tbl (its settings: .enabled), on, why (Ellesmere's state when off) }
---------------------------------------------------------------------------
-- Chat (EllesmereUIChat): its panel look, tabs, sidebar buttons, fading,
-- input line, short channel names, class colours and kept history
---------------------------------------------------------------------------
local CHAT_FOLDER = "EllesmereUIChat"
local function ConvertChat(addon, c, notes, prof)
    local p = type(addon.chat) == "table" and addon.chat or addon
    local function G(k, d) local v = p[k] if v == nil then return d end return v end
    c.enabled = G("enabled", true) ~= false
    c.look = "PANEL"
    c.bgColor = { r = Num(G("bgR"), 0.03), g = Num(G("bgG"), 0.045), b = Num(G("bgB"), 0.05) }
    c.bgAlpha = Num(G("bgAlpha"), 0.65)
    c.fontSize = math.max(8, math.min(24, math.floor(Num(G("chatFontSize", G("fontSize")), 12) + 0.5)))
    -- Ellesmere's chat font: the Chat page's own, else the chat entry of its
    -- per-module fonts, else Ellesmere's global one (the same for the outline)
    local fonts = type(prof) == "table" and type(prof.fonts) == "table" and prof.fonts or {}
    local entry = {}
    for _, e in ipairs(type(fonts.moduleFonts) == "table" and fonts.moduleFonts or {}) do
        if type(e) == "table" and e.folder == CHAT_FOLDER then entry = e end
    end
    local fname = G("font", "__global")
    if fname == "__global" then fname = entry.font end
    if fname == nil or fname == "__global" then fname = fonts.global or "Expressway" end
    c.font = FontName(fname) or "GLOBAL"
    if c.font == "GLOBAL" and fname then
        notes[#notes + 1] = ("Chat: font \"%s\" is not known to HUF: HUF's general font."):format(tostring(fname))
    end
    local om = G("outlineMode", "__global")
    if om == "__global" then om = entry.outline end
    if om == nil or om == "__global" then om = fonts.outlineMode or "none" end
    c.outline = (om == "outline" and "OUTLINE") or (om == "thick" and "THICKOUTLINE") or "NONE"
    c.tabFontSize = math.max(8, math.min(18, math.floor(Num(G("tabFontSize"), 11) + 0.5)))
    local tc = G("tabFontColor")
    c.tabTextAlpha = type(tc) == "table" and Num(tc.a, 0.65) or 0.65
    c.tabUnderline = G("activeUnderline", true) ~= false
    c.tabUnderlineAccent = (G("activeUnderlineColorMode", "accent") == "accent")
    c.tabUnderlineColor = Color(G("activeUnderlineColor"), c.tabUnderlineColor or { r = 0.05, g = 0.82, b = 0.61 })
    -- the panel's edge: only when Ellesmere draws one (foreverBorder belongs to
    -- its bronze WoW Forever style, not to the EllesmereUI look)
    local edge = G("panelBorderThickness", "none") ~= "none"
    c.panelBorderColor = Color(G("panelBorderColor"), { r = 1, g = 1, b = 1 })
    c.panelBorderAlpha = edge and Num(G("panelBorderOpacity"), 0.18) or 0
    local thick = G("panelBorderThickness", "none")
    c.panelBorderSize = (thick == "thick" and 2) or (thick == "thicker" and 3) or 1
    -- tabs
    c.tabHeight = math.max(14, math.min(32, math.floor(Num(G("tabHeight"), 24) - 2 + 0.5)))
    c.tabTextColor = Color(G("tabFontColorActive"), { r = 1, g = 1, b = 1 })
    local tb, tba = G("tabBackgroundColor"), G("tabBackgroundColorActive")
    c.tabBg = Color(type(tba) == "table" and tba or tb, { r = 0.03, g = 0.045, b = 0.05 })
    c.tabBgAlpha = type(tb) == "table" and Num(tb.a, 0.44) or 0.44
    c.tabBgActiveAlpha = type(tba) == "table" and Num(tba.a, 0.65) or 0.65

    c.tabActiveEdge = G("activeTabBorder", true) ~= false and G("tabBorderThickness", "none") ~= "none"
    -- the sidebar
    c.stripJoined = G("sidebarSeparate", false) ~= true
    c.stripGap = math.max(0, math.min(30, math.floor(Num(G("sidebarSeparateSpacing"), 8) + 0.5)))
    c.stripBg = G("hideSidebarBg", false) ~= true
    c.iconAccent = G("iconUseAccent", false) == true
    c.iconColor = { r = Num(G("iconR"), 1), g = Num(G("iconG"), 1), b = Num(G("iconB"), 1) }
    c.iconSize = math.max(14, math.min(32, math.floor(22 * Num(G("sidebarIconScale"), 1) + 0.5)))
    c.iconGap = math.max(0, math.min(16, math.floor(Num(G("sidebarIconSpacing"), 10) + 0.5)))
    c.stripWidth = math.max(30, math.min(100, math.floor(Num(G("sidebarWidth"), 40) + 0.5)))
    -- the sidebar's buttons
    c.buttons.copy = G("showCopy", true) ~= false
    c.buttons.social = G("showFriends", true) ~= false
    c.buttons.guild = G("showGuild", false) == true
    c.buttons.channels = G("showVoice", false) == true
    c.buttons.chatmenu = G("showChatMenu", false) == true
    c.buttons.bottom = G("showScroll", true) ~= false
    c.buttons.settings = G("showSettings", true) ~= false
    c.buttonSide = G("sidebarRight", false) == true and "RIGHT" or "LEFT"
    c.buttonX, c.buttonY = 0, 0
    c.hideStock = true
    -- Ellesmere fades the whole chat when idle; HUF fades the buttons
    c.fade = G("idleFadeEnabled", true) ~= false
    c.fadeDelay = math.max(1, math.min(30, math.floor(Num(G("idleFadeDelay"), 15) + 0.5)))
    c.fadeAlpha = math.max(0, math.min(1, 1 - Num(G("idleFadeStrength"), 40) / 100))
    c.fadeWhole = true
    -- Ellesmere's panel: 10 past the chat's sides; below it 6 (input on top,
    -- over the chat's top lines) or room for the input line under the text
    c.panelPadX = 10
    if G("inputOnTop", false) == true then
        c.inputPos, c.panelPadBottom = "INSIDE_TOP", 6
    else
        c.inputPos, c.panelPadBottom = "BELOW", 34
    end
    c.inputOffset = 0
    c.abbreviate = G("abbreviateChannels", true) ~= false
    c.classColors = G("classColorNames", true) ~= false
    c.history = G("persistChatHistory", true) ~= false
    c.historyLines = math.max(100, math.min(2000, math.floor(Num(G("persistChatHistoryMaxLines"), 100) / 100 + 0.5) * 100))
    -- where the chat sits and its size: Ellesmere's chat running now = the
    -- window as it is on screen (exact); else what Ellesmere saved
    local pos, size = G("chatPosition"), G("chatSize")
    local live = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(CHAT_FOLDER)
    local cf = _G.ChatFrame1
    local l, b = live and cf and cf:GetLeft(), live and cf and cf:GetBottom()
    if l and b then
        c.position = { point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT", x = math.floor(l + 0.5), y = math.floor(b + 0.5),
                       w = math.floor(cf:GetWidth() + 0.5), h = math.floor(cf:GetHeight() + 0.5) }
    elseif type(pos) == "table" and type(pos.x) == "number" and type(pos.y) == "number" then
        c.position = { point = pos.point or "BOTTOMLEFT", relPoint = pos.relPoint or pos.point or "BOTTOMLEFT",
                       x = math.floor(pos.x + 0.5), y = math.floor(pos.y + 0.5) }
        if type(size) == "table" and type(size.w) == "number" and type(size.h) == "number" then
            c.position.w, c.position.h = math.floor(size.w + 0.5), math.floor(size.h + 0.5)
        end
    end
    -- timestamps: the game's own setting, written once at the next login / reload
    local ts = G("timestampFormat")
    if type(ts) == "string" and ts ~= "" then c.timestamps = ts end
end

local UNIT_ORDER = { "player", "target", "targettarget", "pet" }
local function Convert(prof, uf, np, npOn, dm, dmOn)
    local out = ns.CopyTable(ns.db)
    ns.FillDefaults(out, ns.DEFAULTS)
    local notes, what, parts = {}, {}, {}

    if uf then what[#what + 1] = "unit frames" end
    for _, hufKey in ipairs(uf and UNIT_ORDER or {}) do
        local s = uf[UNIT_KEYS[hufKey]]
        if type(s) ~= "table" then s = {} end
        if hufKey == "targettarget" and next(s) == nil and type(uf.totPet) == "table" then s = uf.totPet end
        local u = out.units[hufKey]
        local okC, src = pcall(ConvertUnit, hufKey, s, uf, u, notes)
        if not okC then return false, ("Could not convert the %s frame: %s"):format(hufKey, tostring(src)) end
        parts[#parts + 1] = { title = ns.UNIT_BY_KEY[hufKey].title, tbl = u, on = u.enabled,
            path = { "units", hufKey }, unit = true,
            why = (src == "blizzard" and "Blizzard's frame in Ellesmere") or "off in Ellesmere" }
    end
    if np then
        local okN, err = pcall(ConvertNameplates, np, out.nameplates, notes)
        if not okN then return false, "Could not convert the nameplates: " .. tostring(err) end
        what[#what + 1] = "nameplates"
        out.nameplates.enabled = npOn ~= false
        parts[#parts + 1] = { title = "Nameplates", tbl = out.nameplates, on = out.nameplates.enabled, path = { "nameplates" },
            why = "EllesmereUI Nameplates is off", folder = NP_FOLDER, module = "EllesmereUI Nameplates" }
    end
    local mmA = prof and prof.addons and prof.addons[MM_FOLDER]
    if type(mmA) == "table" and type(out.minimap) == "table" then
        local okM, err = pcall(ConvertMinimap, mmA, out.minimap, notes)
        if not okM then return false, "Could not convert the minimap: " .. tostring(err) end
        what[#what + 1] = "minimap"
        parts[#parts + 1] = { title = "Minimap", tbl = out.minimap, on = true, path = { "minimap" },
            why = "off in Ellesmere", folder = MM_FOLDER, module = "EllesmereUI Minimap" }
    end
    local dbA = prof and prof.addons and prof.addons[DB_FOLDER]
    if type(dbA) == "table" and type(out.dataBars) == "table" and out.dataBars.minimap then
        local okB, res = pcall(ConvertDataBar, dbA, out.dataBars.minimap, notes)
        if not okB then return false, "Could not convert the data bar: " .. tostring(res) end
        if res then
            what[#what + 1] = "minimap data bar"
            parts[#parts + 1] = { title = "Minimap data bar", tbl = out.dataBars.minimap, on = true, why = "off in Ellesmere",
                path = { "dataBars", "minimap" } }
        end
        local okF, bars = pcall(ConvertBars, dbA, notes)
        if not okF then return false, "Could not convert the data bars: " .. tostring(bars) end
        if #bars > 0 then
            out.dataBars.bars = bars
            what[#what + 1] = "data bars"
            for i, b in ipairs(bars) do
                local last = i == #bars
                parts[#parts + 1] = { title = "Data bar: " .. b.name, tbl = b, on = true, why = "off in Ellesmere", bar = true,
                    folder = last and DB_FOLDER or nil, module = last and "EllesmereUI Data Bars" or nil }
            end
        end
    end
    local chA = prof and prof.addons and prof.addons[CHAT_FOLDER]
    if type(chA) == "table" and type(out.chat) == "table" then
        local okC, err = pcall(ConvertChat, chA, out.chat, notes, prof)
        if not okC then return false, "Could not convert the chat: " .. tostring(err) end
        what[#what + 1] = "chat"
        parts[#parts + 1] = { title = "Chat", tbl = out.chat, on = out.chat.enabled, path = { "chat" },
            why = "off in Ellesmere", folder = CHAT_FOLDER, module = "EllesmereUI Chat" }
    end
    local rf = prof and prof.addons and prof.addons[RF_FOLDER]
    if type(rf) == "table" and out.units.party then
        local okG, err = pcall(ConvertGroup, rf, out.units.party, notes)
        if not okG then return false, "Could not convert the group frames: " .. tostring(err) end
        what[#what + 1] = "group frames"
        parts[#parts + 1] = { title = "Group frames", tbl = out.units.party, on = true, path = { "units", "party" }, unit = true,
            why = "off in Ellesmere", folder = RF_FOLDER, module = "EllesmereUI Raid Frames" }
    end
    if dm and type(out.damageMeter) == "table" then
        local okD, err = pcall(ConvertDamageMeter, dm, out.damageMeter, notes)
        if not okD then return false, "Could not convert the damage meter: " .. tostring(err) end
        what[#what + 1] = "damage meter"
        out.damageMeter.enabled = dmOn ~= false
        parts[#parts + 1] = { title = "Damage meter", tbl = out.damageMeter, on = out.damageMeter.enabled, path = { "damageMeter" },
            why = "EllesmereUI Damage Meters is off", folder = DM_FOLDER, module = "EllesmereUI Damage Meters" }
    end

    -- Ellesmere's instance reset announce (Quality of Life, kept outside its
    -- profiles: ReadEllesmereLive passes it on) -> HUF's resets.announce
    local ra = prof and (prof._hufResetAnnounce or prof.instanceResetAnnounce)
    if ra == true and type(out.resets) == "table" then
        out.resets.announce = true
        what[#what + 1] = "instance reset announce"
        parts[#parts + 1] = { title = "Instance reset announce", tbl = out.resets, on = true, path = { "resets" } }
    end

    -- UI scale: EllesmereUI's own (account-wide, EllesmereUIDB.ppUIScale - not in its profile strings)
    local edb = _G.EllesmereUIDB
    local pp = type(edb) == "table" and tonumber(edb.ppUIScale)
    if pp and ns.UIScale and type(out.uiScale) == "table" then
        out.uiScale.enabled = true
        out.uiScale.scale = ns.UIScale.Clamp(pp)
        what[#what + 1] = "UI scale"
        parts[#parts + 1] = { title = ("UI scale (%.2f)"):format(out.uiScale.scale), tbl = out.uiScale, on = true,
            path = { "uiScale" }, why = "Ellesmere's UI scale" }
        notes[#notes + 1] = "UI scale: HUF uses it once EllesmereUI is off (while it is on, EllesmereUI sets the scale)."
    end

    -- action bars (ActionBars.lua; the same bar keys)
    local abA = prof and prof.addons and prof.addons["EllesmereUIActionBars"]
    if type(abA) == "table" and type(abA.bars) == "table" and ns.ActionBars and type(out.actionBars) == "table" then
        local okA, n = pcall(ns.ActionBars.ConvertEllesmere, abA, out.actionBars)
        if not okA then return false, "Could not convert the action bars: " .. tostring(n) end
        if n > 0 then
            out.actionBars.enabled = true
            what[#what + 1] = "action bars"
            parts[#parts + 1] = { title = "Action bars", tbl = out.actionBars, on = true, path = { "actionBars" },
                why = "off in Ellesmere", folder = "EllesmereUIActionBars", module = "EllesmereUI Action Bars" }
        end
    end

    -- font and outline (Ellesmere's Unit Frames font, else its global one)
    if not uf then return true, out, Unique(notes), what, parts end

    -- Ellesmere cuts a left text short next to a right text
    out.global.shortenTexts = true

    -- power colours by type: Ellesmere's palette (its defaults + the profile's own)
    local EUI = _G.EllesmereUI
    local defaults = type(EUI) == "table" and type(EUI.DEFAULT_POWER_COLORS) == "table" and EUI.DEFAULT_POWER_COLORS or {}
    local own = type(prof.customColors) == "table" and type(prof.customColors.power) == "table" and prof.customColors.power or {}
    local any = false
    for _, k in ipairs({ "MANA", "RAGE", "ENERGY", "FOCUS", "RUNIC_POWER" }) do
        local c = own[k] or defaults[k]
        if type(c) == "table" and type(c.r) == "number" then
            out.global.customPower[k] = Color(c, out.global.customPower[k])
            any = true
        end
    end
    if any then out.global.powerColors = "CUSTOM" end
    local fonts = type(prof.fonts) == "table" and prof.fonts or {}
    local fontName, outline = fonts.global, fonts.outlineMode
    for _, e in ipairs(type(fonts.moduleFonts) == "table" and fonts.moduleFonts or {}) do
        if type(e) == "table" and e.folder == UF_FOLDER then
            if type(e.font) == "string" and e.font ~= "__global" then fontName = e.font end
            if type(e.outline) == "string" and e.outline ~= "__global" then outline = e.outline end
        end
    end
    local f = FontName(fontName or "Expressway")
    if f then out.global.font = f
    elseif fontName then notes[#notes + 1] = ("Font \"%s\" is not known to HUF: kept %s."):format(fontName, out.global.font) end
    outline = outline or "shadow"
    if outline == "outline" then out.global.outline, out.global.shadow = "OUTLINE", false
    elseif outline == "thick" then out.global.outline, out.global.shadow = "THICKOUTLINE", false
    elseif outline == "shadow" then out.global.outline, out.global.shadow = "NONE", true
    else out.global.outline, out.global.shadow = "NONE", false end

    -- frames that point at an imported frame keep working; a frame that is
    -- anchored to one turned off goes back to the screen
    for _, u in pairs(out.units) do
        if u.anchorTo and u.anchorTo ~= "SCREEN" and out.units[u.anchorTo] and not out.units[u.anchorTo].enabled then
            u.anchorTo = "SCREEN"
            u.point = { "CENTER", "CENTER", 0, -200 }
        end
    end

    if type(uf.focus) == "table" or type(uf.boss) == "table" then
        notes[#notes + 1] = "Focus and boss frames: HUF has none, left out."
    end
    return true, out, Unique(notes), what, parts
end

-- The profile to import: the active one, with only the ticked parts taken
-- from the converted one (out). Unticked parts stay exactly as they are. The
-- general font, outline, shortened texts and power colours come along only
-- with unit or group frames.
local GLOBAL_KEYS = { "font", "outline", "shadow", "shortenTexts", "powerColors", "customPower" }
function ns.MergeEllesmere(out, parts, chosen)
    local final = ns.CopyTable(ns.db)
    local bars, anyUnit = {}, false
    for i, part in ipairs(parts) do
        if chosen[i] then
            if part.bar then
                bars[#bars + 1] = ns.CopyTable(part.tbl)
            elseif part.path then
                local t = final
                for j = 1, #part.path - 1 do
                    local k = part.path[j]
                    if type(t[k]) ~= "table" then t[k] = {} end
                    t = t[k]
                end
                t[part.path[#part.path]] = ns.CopyTable(part.tbl)
                if part.unit then anyUnit = true end
            end
        end
    end
    if #bars > 0 and type(final.dataBars) == "table" then final.dataBars.bars = bars end
    if anyUnit and type(out.global) == "table" then
        for _, k in ipairs(GLOBAL_KEYS) do
            local v = out.global[k]
            final.global[k] = type(v) == "table" and ns.CopyTable(v) or v
        end
    end
    -- a frame anchored to one that is off goes back to the screen
    for _, u in pairs(final.units or {}) do
        if type(u) == "table" and u.anchorTo and u.anchorTo ~= "SCREEN" and final.units[u.anchorTo]
           and not final.units[u.anchorTo].enabled then
            u.anchorTo = "SCREEN"
            u.point = { "CENTER", "CENTER", 0, -200 }
        end
    end
    if out._extra then final._extra = out._extra end
    return final
end

-- ok, a whole HUF profile (the active one with Ellesmere's frames), notes,
-- what was taken ({ "unit frames", "nameplates" }) or ok=false, error text
function ns.ReadEllesmereText(text)
    local ok, prof, uf, np, dm = Decode(text)
    if not ok then return false, prof end
    return Convert(prof, uf, np, nil, dm)
end

-- the same from EllesmereUI's current settings in this game (no string):
-- the loaded modules' live settings, else what its active profile stored
function ns.ReadEllesmereLive()
    local EUI = _G.EllesmereUI
    if type(EUI) ~= "table" or type(EUI.SnapshotAllAddons) ~= "function" then
        return false, "EllesmereUI is not loaded."
    end
    local okS, data = pcall(EUI.SnapshotAllAddons)
    if not okS or type(data) ~= "table" then return false, "Could not read EllesmereUI's settings: " .. tostring(data) end
    data.addons = type(data.addons) == "table" and data.addons or {}
    local db = _G.EllesmereUIDB
    if type(db) == "table" then data._hufResetAnnounce = db.instanceResetAnnounce end
    local stored = type(db) == "table" and type(db.profiles) == "table" and db.profiles[db.activeProfile or "Default"]
    local saved = type(stored) == "table" and type(stored.addons) == "table" and stored.addons or {}
    -- only loaded modules are in the snapshot: from the stored copy = Ellesmere has them off
    local npOn = data.addons[NP_FOLDER] ~= nil
    local dmOn = data.addons[DM_FOLDER] ~= nil
    -- a module that is off is not in the snapshot: its settings from the
    -- profile's stored copy (every part reads data.addons)
    for folder, v in pairs(saved) do
        if data.addons[folder] == nil and type(v) == "table" then data.addons[folder] = v end
    end
    local uf = data.addons[UF_FOLDER] or saved[UF_FOLDER]
    local np = data.addons[NP_FOLDER] or saved[NP_FOLDER]
    local dm = data.addons[DM_FOLDER] or saved[DM_FOLDER]
    if type(uf) ~= "table" and type(np) ~= "table" and type(dm) ~= "table" then
        return false, "EllesmereUI has no Unit Frames, Nameplates or Damage Meters settings here."
    end
    return Convert(data, type(uf) == "table" and uf or nil, type(np) == "table" and np or nil, npOn,
        type(dm) == "table" and dm or nil, dmOn)
end

-- EllesmereUI's nameplates and HUF's both on: two plates on every unit
ns.OnLogin(function()
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(NP_FOLDER)
    if loaded and ns.db.nameplates.enabled then
        ns.Print("EllesmereUI Nameplates is on too, so every unit gets two nameplates. Turn off one of them (HUF: /huf > Nameplates).")
    end
end)
