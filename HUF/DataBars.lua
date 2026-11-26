-- HUF: data bars. For now one: the minimap data bar, a strip under (or over)
-- the minimap, as wide as the map: friends online and guild members online
-- (a click opens the friends list / the guild window). The tracking button
-- can sit on its left end (Minimap: tracking at "Below, left").

local _, ns = ...
local DB = {}
ns.DataBars = DB

local function S() return ns.db.dataBars.minimap end

local bar
local blocks = {}

-- the game's own art, drawn from its sheet so it can be cropped. trim: the
-- share of the art's width kept (micro menu art has a wide empty border, which
-- at 10 px leaves only a smudge); the height is cut to keep it square. Sets
-- tex.aspect (width / height of what is shown). A plain file where the client
-- has no such atlas.
local function SetIcon(tex, atlas, file, trim, shift)
    local info = atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)
    local sheet = info and (info.file or info.filename)
    if sheet and info.width and info.width > 0 and info.height and info.height > 0 then
        local l, r, t, b = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
        local aspect = info.width / info.height
        if trim then
            local sy = math.min(1, trim * aspect)        -- the same pixels both ways
            -- shift: the picture is off the art's centre (a share of its width)
            local cx, cy = (l + r) / 2 + (r - l) * (shift or 0), (t + b) / 2
            local hw, hh = (r - l) * trim / 2, (b - t) * sy / 2
            l, r, t, b = cx - hw, cx + hw, cy - hh, cy + hh
            aspect = 1
        end
        tex:SetTexture(sheet)
        tex:SetTexCoord(l, r, t, b)
        tex.aspect = aspect
    else
        tex:SetTexture(file)
        tex:SetTexCoord(0, 1, 0, 1)
        tex.aspect = 1
    end
end

local function FriendsOnline()
    local n = 0
    if C_FriendList and C_FriendList.GetNumOnlineFriends then
        local ok, v = pcall(C_FriendList.GetNumOnlineFriends)
        if ok and type(v) == "number" then n = n + v end
    end
    if BNGetNumFriends then
        local ok, _, online = pcall(BNGetNumFriends)
        if ok and type(online) == "number" then n = n + online end
    end
    return n
end

local function GuildOnline()
    if not (IsInGuild and IsInGuild()) then return nil end
    local ok, _, online = pcall(GetNumGuildMembers)
    return ok and type(online) == "number" and online or 0
end

-- the icons' colour: flat (the art greyed, then tinted) or the art's own;
-- the accent while the mouse is on it
local function IconColor(b, hover)
    local s = S()
    local mode = s.iconColor or "MONO"
    b.icon:SetDesaturated(mode ~= "GAME" or hover)
    if hover then
        local a = ns.ACCENT
        b.icon:SetVertexColor(a[1], a[2], a[3])
    elseif mode == "GAME" then
        b.icon:SetVertexColor(1, 1, 1)
    elseif mode == "CLASS" then
        local _, cls = UnitClass("player")
        local c = cls and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
        b.icon:SetVertexColor(c and c.r or 1, c and c.g or 1, c and c.b or 1)
    elseif mode == "ACCENT" then
        local a = ns.ACCENT
        b.icon:SetVertexColor(a[1], a[2], a[3])
    elseif mode == "CUSTOM" and s.iconCustom then
        b.icon:SetVertexColor(s.iconCustom.r, s.iconCustom.g, s.iconCustom.b)
    else
        b.icon:SetVertexColor(0.85, 0.85, 0.88)
    end
end

local BLOCKS = {
    { key = "friends", title = "Friends online", atlas = "socialqueuing-icon-group",
      file = "Interface\\FriendsFrame\\UI-Toast-FriendOnlineIcon", count = FriendsOnline,
      click = function() if ToggleFriendsFrame then ToggleFriendsFrame() end end },
    { key = "guild", title = "Guild members online", atlas = "UI-HUD-MicroMenu-GuildCommunities-Up", trim = 0.62, shift = 0.05,
      file = "Interface\\GossipFrame\\TabardGossipIcon", count = GuildOnline,
      click = function()
          if ToggleGuildFrame then ToggleGuildFrame()
          elseif ToggleCommunitiesFrame then ToggleCommunitiesFrame() end
      end },
}

local function Build()
    if bar then return end
    bar = CreateFrame("Frame", "HUF_MinimapDataBar", UIParent)
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar.border = ns.UI.Border(bar, 0, 0, 0, 1)
    -- the tracking button's slot at the left end (Minimap places it there)
    bar.slot = CreateFrame("Frame", nil, bar)
    bar.slot.bg = bar.slot:CreateTexture(nil, "BACKGROUND", nil, 1)
    bar.slot.bg:SetAllPoints()
    bar.slot.bg:SetColorTexture(1, 1, 1, 0.04)
    bar.slot.line = bar.slot:CreateTexture(nil, "ARTWORK")
    bar.slot.line:SetPoint("TOPRIGHT")
    bar.slot.line:SetPoint("BOTTOMRIGHT")
    bar.slot.line:SetWidth(1)
    bar.slot.line:SetColorTexture(0, 0, 0, 1)
    for _, info in ipairs(BLOCKS) do
        local b = CreateFrame("Button", nil, bar)
        b.info = info
        b.icon = b:CreateTexture(nil, "ARTWORK")
        SetIcon(b.icon, info.atlas, info.file, info.trim, info.shift)
        b.text = b:CreateFontString(nil, "OVERLAY")
        b:RegisterForClicks("LeftButtonUp")
        b:SetScript("OnClick", function() info.click() end)
        b:SetScript("OnEnter", function(self)
            IconColor(self, true)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(info.title)
            GameTooltip:AddLine(tostring(info.count() or 0), 1, 1, 1)
            GameTooltip:AddLine("Click to open", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function(self) IconColor(self) GameTooltip:Hide() end)
        blocks[info.key] = b
    end
    bar:Hide()
end

-- the tracking button sits on the bar's end: Minimap's tracking at
-- "Below, left" (bar under the map) or "Above, left" (bar over it)
function DB.TrackingSlot()
    local s = S()
    if not (bar and bar:IsShown() and s.enabled) then return nil end
    local t = ns.db.minimap and ns.db.minimap.icons and ns.db.minimap.icons.tracking
    if not t or t.mode == "NEVER" then return nil end
    local want = (s.position == "ABOVE") and "ABOVE_LEFT" or "BELOW_LEFT"
    if t.pos ~= want then return nil end
    return bar.slot
end

-- the counts (and which blocks show: no guild, no guild block)
function DB.Update()
    if not (bar and bar:IsShown()) then return end
    local s = S()
    local shown = {}
    for _, info in ipairs(BLOCKS) do
        local b = blocks[info.key]
        local n = info.count()
        local on = s[info.key] ~= false and n ~= nil
        b:SetShown(on)
        if on then
            b.text:SetText(tostring(n))
            shown[#shown + 1] = b
        end
    end
    -- the blocks side by side, centred: icon, then the count (SIDE), or the
    -- count above a small icon (STACK)
    local stack = s.layout == "STACK"
    -- STACK: the icon takes ~60% of the bar; the count sits tight on top (a
    -- font string has empty room under its digits, so it may overlap a little)
    local size = stack and math.max(8, math.floor(s.height * 0.6 + 0.5)) or math.max(8, s.height - 6)
    local widths, total = {}, 0
    for i, b in ipairs(shown) do
        local iw = math.floor(size * (b.icon.aspect or 1) + 0.5)
        b.icon:SetSize(iw, size)
        b.icon:ClearAllPoints()
        b.text:ClearAllPoints()
        local w
        if stack then
            b.icon:SetPoint("BOTTOM", b, "BOTTOM", 0, 1)
            b.text:SetPoint("BOTTOM", b.icon, "TOP", 0, -1)
            w = math.max(iw, b.text:GetStringWidth() or 0)
        else
            b.icon:SetPoint("LEFT", b, "LEFT", 0, 0)
            b.text:SetPoint("LEFT", b.icon, "RIGHT", 2, 0)
            w = iw + 2 + math.max(6, b.text:GetStringWidth() or 0)
        end
        widths[i] = math.ceil(w)
        if (widths[i] - iw) % 2 == 1 then widths[i] = widths[i] + 1 end   -- the icon on a whole pixel
        total = total + w + (i > 1 and s.spacing or 0)
    end
    -- the tracking slot takes the left end; the counts centre in the rest
    local slot = DB.TrackingSlot()
    local slotW = slot and s.height or 0
    bar.slot:SetShown(slot ~= nil)
    if slot then
        bar.slot:ClearAllPoints()
        bar.slot:SetPoint("TOPLEFT")
        bar.slot:SetPoint("BOTTOMLEFT")
        bar.slot:SetWidth(slotW)
    end
    local x = math.floor(-total / 2 + slotW / 2 + 0.5)
    for i, b in ipairs(shown) do
        b:ClearAllPoints()
        b:SetSize(widths[i], s.height)
        b:SetPoint("LEFT", bar, "CENTER", x, 0)
        x = x + widths[i] + s.spacing
    end
end

function DB.Apply()
    local s = S()
    if not s.enabled or not Minimap then
        if bar then bar:Hide() end
        return
    end
    Build()
    -- under (or over) the map, as wide as it is, outside its border
    -- as wide as the map's border (drawn outside the map); touching the map,
    -- the bar's own line lies on the map's bottom line (one line, not two)
    local mm = ns.db.minimap
    local mb = mm and mm.enabled and mm.borderSize or 0
    local bs = s.borderSize or 0
    local edge = mb + (s.gap or 0)
    if (s.gap or 0) == 0 and mb > 0 and bs > 0 then edge = mb - math.min(mb, bs) end
    local holder = Minimap:GetParent() or UIParent
    bar:SetParent(holder)
    bar:SetFrameStrata(Minimap:GetFrameStrata())
    bar:SetFrameLevel(Minimap:GetFrameLevel() + 4)      -- under HUF's minimap icons (tracking on its end)
    bar:ClearAllPoints()
    if s.position == "ABOVE" then
        bar:SetPoint("BOTTOMLEFT", Minimap, "TOPLEFT", -mb, edge)
        bar:SetPoint("BOTTOMRIGHT", Minimap, "TOPRIGHT", mb, edge)
    else
        bar:SetPoint("TOPLEFT", Minimap, "BOTTOMLEFT", -mb, -edge)
        bar:SetPoint("TOPRIGHT", Minimap, "BOTTOMRIGHT", mb, -edge)
    end
    -- the bar's line as thick as set (top, bottom, left, right)
    local e = bar.border.edges
    e[1]:SetHeight(math.max(1, bs)); e[2]:SetHeight(math.max(1, bs))
    e[3]:SetWidth(math.max(1, bs)); e[4]:SetWidth(math.max(1, bs))
    bar:SetHeight(s.height)
    local c = s.bgColor
    bar.bg:SetColorTexture(c.r, c.g, c.b, s.bgAlpha)
    bar.border:SetShown((s.borderSize or 0) > 0)
    for _, b in pairs(blocks) do
        ns.ApplyFont(b.text, "GLOBAL", s.fontSize, "GLOBAL")
        IconColor(b)
    end
    bar:Show()
    DB.Update()
    -- the tracking button follows (into the slot or out of it)
    if ns.Minimap and ns.Minimap.PlaceIcons then ns.Minimap.PlaceIcons() end
end

local function Soon()
    if DB.pending then return end
    DB.pending = true
    C_Timer.After(0.5, function() DB.pending = false DB.Update() end)
end
for _, e in ipairs({ "FRIENDLIST_UPDATE", "BN_FRIEND_ACCOUNT_ONLINE", "BN_FRIEND_ACCOUNT_OFFLINE",
                     "GUILD_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE" }) do
    ns.On(e, Soon)
end
ns.OnLogin(function()
    DB.Apply()
    if C_FriendList and C_FriendList.ShowFriends then pcall(C_FriendList.ShowFriends) end
    if IsInGuild and IsInGuild() and C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end
    -- the minimap is laid out after login: follow it
    C_Timer.After(1, DB.Apply)
end)
ns.OnRefresh(function() if ns.ready then DB.Apply() end end)

---------------------------------------------------------------------------
-- Free data bars: any number, anywhere on screen, each with its own blocks
-- (DataBarBlocks.lua). Drag them in unlock mode.
---------------------------------------------------------------------------
local BL = ns.DataBlocks
local A = ns.ACCENT

DB.BAR_DEFAULTS = {
    enabled = true, name = "Bar",
    point = "CENTER", relPoint = "CENTER", x = 0, y = -200,
    width = 400, height = 22,
    look = "FLAT",              -- FLAT (solid colour, a line around it) | SOFT (dark, see-through, faded ends)
    bgColor = { r = 0.067, g = 0.067, b = 0.067 }, bgAlpha = 0.95, softAlpha = 0.5,
    borderSize = 1,
    visibility = "ALWAYS",      -- ALWAYS | COMBAT | NOCOMBAT | HOVER | NEVER
    sizing = "AUTO",            -- AUTO (as wide as each block's content; one block fills the rest) | EVEN
    fontSize = 12,
    blocks = {},
}

local recs = {}         -- [bar cfg] = { frame, blocks = { block frames }, pool }
local movers = {}

local function Bars() return ns.db.dataBars.bars end

-- the colour of an icon by its block's setting; the accent under the mouse
local function PaintIcon(b, hover)
    local c = b.cfg
    b.icon:SetDesaturated(c.iconColor ~= "GAME" or hover)
    if hover then b.icon:SetVertexColor(A[1], A[2], A[3]) return end
    if c.iconColor == "GAME" then b.icon:SetVertexColor(1, 1, 1) return end
    local r, g, bl = BL.Tint(c.iconColor, c.iconCustom)
    if r then b.icon:SetVertexColor(r, g, bl) else b.icon:SetVertexColor(0.85, 0.85, 0.88) end
end

local function SetBlockIcon(b, ic)
    if not ic or b.iconKey == ic then return end
    b.iconKey = ic
    BL.SetIcon(b.icon, ic.atlas, ic.file, ic.trim, ic.shift, ic.coords)
end

-- the block's text and colour; true when its width may have changed
local function UpdateBlock(b)
    local def = BL.TYPES[b.cfg.type]
    if not def then return false end
    if def.IconFor then SetBlockIcon(b, def.IconFor(b)) end
    if b.useMeter then
        local ok, v, r, g, bl = pcall(def.Bar, b)
        if ok then
            b.meter:SetValue(v or 0)
            b.meter:SetStatusBarColor(r or 1, g or 1, bl or 1)
        end
        b.text:SetText("")
        return false
    end
    local ok, text, r, g, bl = pcall(def.Text, b)
    if not ok then text = "" end
    text = text or ""
    local old = b.text:GetText() or ""
    b.text:SetText(text)
    local mode = b.cfg.textColor
    if mode == "DYNAMIC" and r then
        b.text:SetTextColor(r, g, bl)
    else
        local tr, tg, tb = BL.Tint(mode, b.cfg.textCustom)
        b.text:SetTextColor(tr or 1, tg or 1, tb or 1)
    end
    return old ~= text
end

local function BuildBlock(parent)
    local b = CreateFrame("Button", nil, parent)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    -- measures the steady width (see ContentWidth)
    b.ruler = b:CreateFontString(nil, "OVERLAY")
    b.ruler:Hide()
    -- a bar instead of the text (the audio block's "bar" style)
    b.meter = CreateFrame("StatusBar", nil, b)
    b.meter:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    b.meter:SetMinMaxValues(0, 1)
    b.meter.bg = b.meter:CreateTexture(nil, "BACKGROUND")
    b.meter.bg:SetAllPoints()
    b.meter.bg:SetColorTexture(0, 0, 0, 0.5)
    b.meter:Hide()
    b.text = b:CreateFontString(nil, "OVERLAY")
    b.text:SetWordWrap(false)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnEnter", function(self)
        if self.cfg.showIcon then PaintIcon(self, true) end
        local def = BL.TYPES[self.cfg.type]
        if def and def.Tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            pcall(def.Tooltip, self, GameTooltip)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function(self)
        if self.cfg.showIcon then PaintIcon(self) end
        GameTooltip:Hide()
    end)
    b:SetScript("OnClick", function(self, button)
        local def = BL.TYPES[self.cfg.type]
        if def and def.Click then pcall(def.Click, self, button) end
        if UpdateBlock(self) then DB.LayoutBar(self.barCfg) end
    end)
    b:SetScript("OnMouseWheel", function(self, delta)
        local def = BL.TYPES[self.cfg.type]
        if def and def.Wheel then pcall(def.Wheel, self, delta) end
        UpdateBlock(self)
    end)
    return b
end

-- the block's content: icon, then the text
-- A number block's width comes from its text with every digit an 8 (at
-- least `steady` digits, like EllesmereUI): it only changes when the number
-- gains a digit, so the blocks after it don't move with every new value.
local function TextWidth(b)
    local txt = b.text:GetText() or ""
    if txt == "" then return 0 end
    local def = BL.TYPES[b.cfg.type]
    local n = def and def.steady
    if not n then return b.text:GetStringWidth() or 0 end
    b.ruler:SetText((txt:gsub("%d+", function(d) return ("8"):rep(math.max(n, #d)) end)))
    return math.max(b.ruler:GetStringWidth() or 0, b.text:GetStringWidth() or 0)
end
local function ContentWidth(b)
    local w = 0
    if b.cfg.showIcon then w = b.iconW end
    if b.useMeter then return math.ceil(w + (w > 0 and 4 or 0) + b.meterW) end
    local tw = TextWidth(b)
    if tw > 0 then w = w + (w > 0 and 3 or 0) + tw end
    return math.ceil(w)
end

function DB.LayoutBar(cfg)
    local rec = recs[cfg]
    if not rec then return end
    local W, H = cfg.width, cfg.height
    local list = rec.blocks
    local n = #list
    if n == 0 then return end
    local even = cfg.sizing == "EVEN"
    -- a block with a width of its own (cfg.width > 0, set by dragging its edge while
    -- arranging) keeps exactly that width and never fills the rest
    local function Fixed(b) return (tonumber(b.cfg.width) or 0) > 0 end
    local widths, fillAt, sum = {}, nil, 0
    for i, b in ipairs(list) do
        if b.cfg.fill and not Fixed(b) then fillAt = i end
    end
    if not fillAt then
        for i = n, 1, -1 do if not Fixed(list[i]) then fillAt = i break end end
    end
    for i, b in ipairs(list) do
        local pads = even and 0 or (b.cfg.padL + b.cfg.padR)
        widths[i] = Fixed(b) and b.cfg.width or (ContentWidth(b) + pads)
        if i ~= fillAt then sum = sum + widths[i] end
    end
    -- a block kept in the middle (cfg.center): its text at the bar's middle,
    -- the blocks before it from the left edge, the ones after it from the
    -- right edge, so nothing moves when another block's text gets longer
    local centerAt
    if not even then
        for i, b in ipairs(list) do if b.cfg.center then centerAt = i end end
    end
    local xs = {}
    if even then
        -- the blocks without a width of their own share what the others leave
        local fixedSum, free = 0, 0
        for _, b in ipairs(list) do if Fixed(b) then fixedSum = fixedSum + b.cfg.width else free = free + 1 end end
        for i, b in ipairs(list) do
            if not Fixed(b) then widths[i] = math.max(1, (W - fixedSum) / math.max(1, free)) end
        end
    elseif centerAt then
        local cb = list[centerAt]
        local cStart = Fixed(cb) and math.floor((W - cb.cfg.width) / 2 + 0.5)
            or math.floor(W / 2 - ContentWidth(cb) / 2 - cb.cfg.padL + 0.5)
        local cEnd = cStart + widths[centerAt]
        xs[centerAt] = cStart
        -- the left side: packed from 0, its fill block (if any) takes the slack
        local lsum, lfill = 0, nil
        for i = 1, centerAt - 1 do
            if list[i].cfg.fill then lfill = i else lsum = lsum + widths[i] end
        end
        if lfill and not Fixed(list[lfill]) then widths[lfill] = math.max(widths[lfill], cStart - lsum) end
        local x = 0
        for i = 1, centerAt - 1 do xs[i] = x x = x + widths[i] end
        -- the right side: packed to the right edge, its fill block takes the slack
        local rsum, rfill = 0, nil
        for i = centerAt + 1, n do
            if list[i].cfg.fill then rfill = i else rsum = rsum + widths[i] end
        end
        if rfill and not Fixed(list[rfill]) then widths[rfill] = math.max(widths[rfill], W - cEnd - rsum) end
        x = W
        for i = n, centerAt + 1, -1 do x = x - widths[i] xs[i] = x end
    elseif fillAt then
        widths[fillAt] = math.max(widths[fillAt], W - sum)
    end
    local x = 0
    for i, b in ipairs(list) do
        local cw = widths[i]
        if xs[i] then x = xs[i] end
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", rec.frame, "TOPLEFT", math.floor(x + 0.5), 0)
        b:SetSize(math.max(1, math.floor(cw + 0.5)), H)
        -- the content inside its cell
        local padL, padR = even and 0 or b.cfg.padL, even and 0 or b.cfg.padR
        local content = ContentWidth(b)
        local left
        if b.cfg.align == "LEFT" then left = padL
        elseif b.cfg.align == "RIGHT" then left = cw - padR - content
        else left = padL + (cw - padL - padR - content) / 2 end
        left = math.floor(left + 0.5)
        b.icon:ClearAllPoints()
        b.text:ClearAllPoints()
        b.meter:ClearAllPoints()
        if b.cfg.showIcon then
            b.icon:SetPoint("LEFT", b, "LEFT", left, 0)
            b.text:SetPoint("LEFT", b.icon, "RIGHT", 3, 0)
            b.meter:SetPoint("LEFT", b.icon, "RIGHT", 4, 0)
        else
            b.text:SetPoint("LEFT", b, "LEFT", left, 0)
            b.meter:SetPoint("LEFT", b, "LEFT", left, 0)
        end
        x = x + cw
    end
end

local function Fade(t, a, reverse)
    t:SetColorTexture(1, 1, 1, 1)
    local from, to = 0, a
    if reverse then from, to = a, 0 end
    local ok = CreateColor and pcall(t.SetGradient, t, "HORIZONTAL", CreateColor(0, 0, 0, from), CreateColor(0, 0, 0, to))
    if not ok and t.SetGradientAlpha then
        t:SetGradientAlpha("HORIZONTAL", 0, 0, 0, from, 0, 0, 0, to)
    end
    t:Show()
end

local EUI_ART = "Interface\\AddOns\\EllesmereUI\\media\\modern_blizz.png"
-- the picture cropped to fill the bar without stretching (its useful part:
-- u 0.25-1, v 0-0.75 of a 561 x 433 image)
local function ArtCoords(t, w, h)
    local L, R, T, Bm, aspect = 0.25, 1, 0, 0.75, 561 / 433
    if not (w and h) or w == 0 or h == 0 then return end
    local fa = w / h
    if fa > aspect then
        local vis = (Bm - T) * (aspect / fa)
        local trim = ((Bm - T) - vis) / 2
        t:SetTexCoord(L, R, T + trim, Bm - trim)
    else
        local vis = (R - L) * (fa / aspect)
        local trim = ((R - L) - vis) / 2
        t:SetTexCoord(L + trim, R - trim, T, Bm)
    end
end

local function ApplyLook(rec, cfg)
    local f = rec.frame
    local c = cfg.bgColor
    f.bg:ClearAllPoints()
    local art = cfg.look == "EUI" and ns.ellesmere
    f.art:SetShown(art and true or false)
    f.overlay:SetShown(art and true or false)
    if art then
        f.art:SetTexture(EUI_ART)
        ArtCoords(f.art, cfg.width, cfg.height)
        f.art:SetAlpha(cfg.artOpacity or 1)
        f.overlay:SetColorTexture(0, 0, 0, cfg.softAlpha or 0.5)
        f.overlay:SetAlpha(cfg.artOpacity or 1)
        f.bg:Hide()
        f.fadeL:Hide(); f.fadeR:Hide()
    else
        f.bg:Show()
    end
    if art then
        -- (the edge below)
    elseif cfg.look == "SOFT" or cfg.look == "EUI" then
        -- dark, see-through, its ends faded out
        local a = cfg.softAlpha or 0.5
        local fw = math.floor(cfg.width * 0.12 + 0.5)
        f.fadeL:SetWidth(fw); f.fadeR:SetWidth(fw)
        Fade(f.fadeL, a, false)
        Fade(f.fadeR, a, true)
        f.bg:SetColorTexture(0, 0, 0, a)
        f.bg:SetPoint("TOPLEFT", f.fadeL, "TOPRIGHT")
        f.bg:SetPoint("BOTTOMRIGHT", f.fadeR, "BOTTOMLEFT")
    else
        f.bg:SetColorTexture(c.r, c.g, c.b, cfg.bgAlpha)
        f.bg:SetAllPoints()
        f.fadeL:Hide(); f.fadeR:Hide()
    end
    local bs = cfg.borderSize or 0
    f.border:SetShown(bs > 0)
    f.border:SetColor(0, 0, 0, art and 0.8 or 1)
    -- the edge in real screen pixels (bs of them), like EllesmereUI: a UI
    -- unit can be 2 pixels at a small UI scale
    local px = 1
    local _, ph = GetPhysicalScreenSize and GetPhysicalScreenSize()
    local es = f:GetEffectiveScale()
    if ph and ph > 0 and es and es > 0 then px = 768 / (ph * es) end
    local t = math.max(1, bs) * px
    local e = f.border.edges
    for i = 1, 4 do
        if e[i].SetSnapToPixelGrid then e[i]:SetSnapToPixelGrid(false) e[i]:SetTexelSnappingBias(0) end
    end
    e[1]:SetHeight(t); e[2]:SetHeight(t)
    e[3]:SetWidth(t); e[4]:SetWidth(t)
end

local function BarFrame(cfg)
    local rec = recs[cfg]
    if rec then return rec end
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetFrameStrata("LOW")
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.fadeL = f:CreateTexture(nil, "BACKGROUND")
    f.fadeL:SetPoint("TOPLEFT"); f.fadeL:SetPoint("BOTTOMLEFT")
    f.fadeR = f:CreateTexture(nil, "BACKGROUND")
    f.fadeR:SetPoint("TOPRIGHT"); f.fadeR:SetPoint("BOTTOMRIGHT")
    f.border = ns.UI.Border(f, 0, 0, 0, 1)
    -- look EUI: EllesmereUI's background picture (from its folder, when
    -- installed) under a black overlay
    f.art = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    f.art:SetAllPoints()
    f.art:Hide()
    f.overlay = f:CreateTexture(nil, "BACKGROUND", nil, -7)
    f.overlay:SetAllPoints()
    f.overlay:Hide()
    rec = { frame = f, blocks = {}, pool = {} }
    recs[cfg] = rec
    return rec
end

local function Wanted(cfg, rec)
    local v = cfg.visibility
    if v == "NEVER" then return false end
    if v == "COMBAT" then return UnitAffectingCombat("player") and true or false end
    if v == "NOCOMBAT" then return not UnitAffectingCombat("player") end
    if v == "HOVER" then return rec.frame:IsMouseOver() and true or false end
    return true
end

local hoverDriver
function DB.UpdateVisibility()
    local anyHover = false
    for cfg, rec in pairs(recs) do
        if rec.frame:IsShown() then
            rec.frame:SetAlpha((ns.unlocked or DB.arranging or Wanted(cfg, rec)) and 1 or 0)
            if cfg.visibility == "HOVER" then anyHover = true end
        end
    end
    if anyHover and not hoverDriver then
        hoverDriver = CreateFrame("Frame")
        hoverDriver.t = 0
        hoverDriver:SetScript("OnUpdate", function(self, el)
            self.t = self.t + el
            if self.t < 0.1 then return end
            self.t = 0
            DB.UpdateVisibility()
        end)
    end
    if hoverDriver then hoverDriver:SetShown(anyHover) end
end

function DB.ApplyBar(cfg)
    ns.FillDefaults(cfg, DB.BAR_DEFAULTS)
    local rec = BarFrame(cfg)
    local f = rec.frame
    if not cfg.enabled or cfg.visibility == "NEVER" then f:Hide() return end
    f:ClearAllPoints()
    f:SetPoint(cfg.point, UIParent, cfg.relPoint, cfg.x, cfg.y)
    f:SetSize(cfg.width, cfg.height)
    ApplyLook(rec, cfg)
    -- the blocks (frames reused)
    for _, b in ipairs(rec.blocks) do b:Hide() rec.pool[#rec.pool + 1] = b end
    wipe(rec.blocks)
    for _, bc in ipairs(cfg.blocks) do
        local def = BL.TYPES[bc.type]
        if def then
            BL.Fill(bc)
            local b = table.remove(rec.pool) or BuildBlock(f)
            b.cfg, b.barCfg = bc, cfg
            local size = math.max(6, math.floor(cfg.fontSize * bc.scale / 100 + 0.5))
            ns.ApplyFont(b.text, "GLOBAL", size, "GLOBAL")
            ns.ApplyFont(b.ruler, "GLOBAL", size, "GLOBAL")
            b.iconKey = nil
            SetBlockIcon(b, def.IconFor and def.IconFor(b) or def.icon)
            b.iconW = math.floor((size + 2) * (b.icon.aspect or 1) + 0.5)
            b.icon:SetSize(b.iconW, size + 2)
            b.icon:SetShown(bc.showIcon)
            b.useMeter = def.Bar ~= nil and bc.settings.style == "BAR"
            b.meterW = math.floor(size * 5 + 0.5)
            b.meter:SetSize(b.meterW, math.max(3, math.floor(size * 0.45 + 0.5)))
            b.meter:SetShown(b.useMeter)
            PaintIcon(b)
            b:EnableMouseWheel(def.Wheel ~= nil)
            UpdateBlock(b)
            b:Show()
            rec.blocks[#rec.blocks + 1] = b
        end
    end
    f:Show()
    DB.LayoutBar(cfg)
    if DB.arranging and DB.Grabs then DB.Grabs(cfg) end
end

-- /run HUF.DataBars.PrintEdges(): left / right / bottom / top of the chat
-- panel and its strip, the meter windows and the data bars (UIParent units)
function DB.PrintEdges()
    local function P(name, f)
        if not (f and f.GetLeft and f:GetLeft()) then return end
        local k = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
        print(("%s: %.1f .. %.1f  (w %.1f)  bottom %.1f top %.1f"):format(name, f:GetLeft() * k, f:GetRight() * k,
            (f:GetRight() - f:GetLeft()) * k, f:GetBottom() * k, f:GetTop() * k))
    end
    P("chat panel", _G.HUF_ChatPanel)
    P("chat strip", _G.HUF_ChatButtons and _G.HUF_ChatButtons.strip)
    P("chat window", _G.ChatFrame1)
    for i = 1, 6 do P("meter " .. i, _G[i == 1 and "HUF_DamageMeter" or ("HUF_DamageMeter" .. i)]) end
    for cfg, rec in pairs(recs) do P("bar " .. tostring(cfg.name), rec.frame) end
end

function DB.ApplyBars()
    local live = {}
    for _, cfg in ipairs(Bars()) do
        live[cfg] = true
        DB.ApplyBar(cfg)
    end
    -- bars that were deleted (or belong to another profile)
    for cfg, rec in pairs(recs) do
        if not live[cfg] then rec.frame:Hide() recs[cfg] = nil end
    end
    DB.UpdateVisibility()
    if ns.unlocked then DB.SetUnlocked(true) end
end

-- a new bar (from the settings page), a little under the screen's centre
function DB.NewBar()
    local cfg = ns.CopyTable(DB.BAR_DEFAULTS)
    cfg.name = "Bar " .. (#Bars() + 1)
    cfg.y = -200 - 30 * #Bars()
    cfg.blocks = { BL.New("fps"), BL.New("ms"), BL.New("clock") }
    cfg.blocks[3].fill = true
    table.insert(Bars(), cfg)
    return cfg
end

-- every block's text: each second (the ticking ones) and on their events
local function Tick(onlyType)
    for cfg, rec in pairs(recs) do
        if rec.frame:IsShown() then
            local moved = false
            for _, b in ipairs(rec.blocks) do
                local def = BL.TYPES[b.cfg.type]
                if def and ((onlyType == nil and def.tick) or onlyType == b.cfg.type) then
                    if UpdateBlock(b) then moved = true end
                end
            end
            if moved then DB.LayoutBar(cfg) end
        end
    end
end
for key, def in pairs(BL.TYPES) do
    for _, e in ipairs(def.events or {}) do
        pcall(ns.On, e, function() C_Timer.After(0.1, function() Tick(key) end) end)   -- an event this client lacks: skipped
    end
end
ns.On("PLAYER_REGEN_DISABLED", function() DB.UpdateVisibility() end)
ns.On("PLAYER_REGEN_ENABLED", function() DB.UpdateVisibility() end)

---------------------------------------------------------------------------
-- Unlock mode: a mover on each bar
---------------------------------------------------------------------------
local function Mover(cfg)
    local m = movers[cfg]
    if m then return m end
    m = CreateFrame("Button", nil, UIParent)
    if ns.Snap then ns.Snap.Register(m) end
    m:SetFrameStrata("DIALOG")
    m:SetMovable(true)
    m:SetClampedToScreen(true)
    m:EnableMouse(true)
    m:RegisterForDrag("LeftButton")
    ns.UI.Fill(m, A[1], A[2], A[3], 0.25)
    ns.UI.Border(m, A[1], A[2], A[3], 1)
    m.label = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    m.label:SetPoint("BOTTOM", m, "TOP", 0, 2)
    m:SetScript("OnDragStart", function(self) ns.Snap.StartDrag(self) end)
    m:SetScript("OnDragStop", function(self)
        ns.Snap.StopDrag(self)
        local sx, sy = self:GetCenter()
        local ux, uy = UIParent:GetCenter()
        if not (sx and ux) then return end
        local k = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
        cfg.point, cfg.relPoint = "CENTER", "CENTER"
        cfg.x = math.floor((sx * k - ux) + 0.5)
        cfg.y = math.floor((sy * k - uy) + 0.5)
        DB.ApplyBar(cfg)
        DB.SetUnlocked(true)
    end)
    m:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(cfg.name or "Data bar")
        GameTooltip:AddLine("Drag to move. Settings: Utility Frames > Minimap > Data bar > Advanced Settings.", 1, 1, 1)
        GameTooltip:Show()
    end)
    m:SetScript("OnLeave", function() GameTooltip:Hide() end)
    movers[cfg] = m
    return m
end

function DB.SetUnlocked(on)
    for cfg, m in pairs(movers) do
        if not recs[cfg] then m:Hide() movers[cfg] = nil end
    end
    for cfg, rec in pairs(recs) do
        local f = rec.frame
        if on and f:IsShown() then
            local m = Mover(cfg)
            m.label:SetText(cfg.name or "Data bar")
            m:ClearAllPoints()
            m:SetAllPoints(f)
            m:Show()
        elseif movers[cfg] then
            movers[cfg]:Hide()
        end
    end
    DB.UpdateVisibility()
end

---------------------------------------------------------------------------
-- Arranging blocks (the Data Bars page's "Arrange blocks", /huf blocks): every block gets a
-- handle; drag one along its bar or onto another data bar - an accent line shows where it
-- lands - and drop it there. Dropped anywhere else: it stays where it was. A small panel with
-- "Done" ends it (as MMT's lock / unlock). Blocks don't take clicks meanwhile.
---------------------------------------------------------------------------
DB.arranging = false
local grabs = {}           -- [block frame] = its handle
local panel, ghost, marker
local drag                 -- { b = block frame, cfg = its bar }

-- the bar under the cursor and where in it (index among its blocks, the dragged one left out)
local function DropAt()
    for cfg, rec in pairs(recs) do
        local f = rec.frame
        if f:IsShown() and f:IsMouseOver(4, -4, -4, 4) then
            local x = GetCursorPosition() / f:GetEffectiveScale()
            local at, n, lineX = 1, 0, f:GetLeft()
            for _, b in ipairs(rec.blocks) do
                if not (drag and b == drag.b) then
                    n = n + 1
                    local cx = b:GetCenter()
                    if cx and x > cx then at, lineX = n + 1, b:GetRight() end
                end
            end
            return cfg, rec, at, lineX
        end
    end
end

local function Marker(rec, x)
    if not marker then
        marker = CreateFrame("Frame", nil, UIParent)
        marker:SetFrameStrata("TOOLTIP")
        local t = marker:CreateTexture(nil, "OVERLAY")
        t:SetAllPoints()
        t:SetColorTexture(A[1], A[2], A[3], 1)
    end
    if not rec then marker:Hide() return end
    local f = rec.frame
    marker:SetParent(f)
    marker:SetFrameStrata("TOOLTIP")
    marker:ClearAllPoints()
    marker:SetSize(2, f:GetHeight() + 6)
    marker:SetPoint("CENTER", f, "BOTTOMLEFT", (x or f:GetLeft()) - f:GetLeft(), f:GetHeight() / 2)
    marker:Show()
end

local function Ghost(b)
    if not ghost then
        ghost = CreateFrame("Frame", nil, UIParent)
        ghost:SetFrameStrata("TOOLTIP")
        ns.UI.Fill(ghost, 0.05, 0.05, 0.06, 0.9)
        ns.UI.Border(ghost, A[1], A[2], A[3], 1)
        ghost.text = ghost:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        ghost.text:SetPoint("CENTER")
    end
    local def = BL.TYPES[b.cfg.type]
    ghost.text:SetText(def and def.title or b.cfg.type)
    ghost:SetSize(math.max(60, ghost.text:GetStringWidth() + 16), 20)
    ghost:Show()
end

local function EndDrag(drop)
    local d = drag
    drag = nil
    if ghost then ghost:Hide() ghost:SetScript("OnUpdate", nil) end
    Marker(nil)
    if not d then return end
    d.b:SetAlpha(1)
    if not drop then return end
    local toCfg, _, at = DropAt()
    if not toCfg then return end
    -- out of its bar, into the new place
    local from = d.cfg.blocks
    for i, bc in ipairs(from) do
        if bc == d.b.cfg then table.remove(from, i) break end
    end
    at = math.max(1, math.min(at, #toCfg.blocks + 1))
    table.insert(toCfg.blocks, at, d.b.cfg)
    DB.ApplyBar(d.cfg)
    if toCfg ~= d.cfg then DB.ApplyBar(toCfg) end
    if ns.RefreshConfig then ns.RefreshConfig() end
end

local function Grab(b)
    local g = grabs[b]
    if not g then
        g = CreateFrame("Button", nil, b)
        g:SetAllPoints(b)
        g:SetFrameLevel(b:GetFrameLevel() + 10)
        g.fill = ns.UI.Fill(g, A[1], A[2], A[3], 0.12)
        ns.UI.Border(g, A[1], A[2], A[3], 0.9)
        g:RegisterForDrag("LeftButton")
        g:SetScript("OnEnter", function(self)
            local def = BL.TYPES[self:GetParent().cfg.type]
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(def and def.title or "Block")
            GameTooltip:AddLine("Drag it along the bar or onto another data bar.", 1, 1, 1)
            GameTooltip:Show()
        end)
        g:SetScript("OnLeave", function() GameTooltip:Hide() end)
        g:SetScript("OnDragStart", function(self)
            local blk = self:GetParent()
            GameTooltip:Hide()
            drag = { b = blk, cfg = blk.barCfg }
            blk:SetAlpha(0.35)
            Ghost(blk)
            ghost:SetScript("OnUpdate", function(gh)
                local x, y = GetCursorPosition()
                local s = UIParent:GetEffectiveScale()
                gh:ClearAllPoints()
                gh:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / s, y / s + 14)
                local _, rec, _, lx = DropAt()
                Marker(rec, lx)
            end)
        end)
        g:SetScript("OnDragStop", function() EndDrag(true) end)
        -- its right edge: drag = width (the block's side padding), Shift + drag = text size
        local e = CreateFrame("Button", nil, g)
        e:SetWidth(8)
        e:SetPoint("TOPRIGHT", 4, 0)
        e:SetPoint("BOTTOMRIGHT", 4, 0)
        e:SetFrameLevel(g:GetFrameLevel() + 2)
        local bar = e:CreateTexture(nil, "OVERLAY")
        bar:SetPoint("TOP", 0, -2)
        bar:SetPoint("BOTTOM", 0, 2)
        bar:SetWidth(2)
        bar:SetColorTexture(A[1], A[2], A[3], 0.9)
        e:SetScript("OnEnter", function(self)
            bar:SetWidth(4)
            local even = self:GetParent():GetParent().barCfg.sizing == "EVEN"
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Resize")
            GameTooltip:AddLine("Drag: the block's width.", 1, 1, 1)
            GameTooltip:AddLine("Shift + drag: its text size.", 1, 1, 1)
            GameTooltip:AddLine("Right-click: automatic width again.", 1, 1, 1)
            GameTooltip:Show()
        end)
        e:SetScript("OnLeave", function() bar:SetWidth(2) GameTooltip:Hide() end)
        e:SetScript("OnMouseDown", function(self, button)
            local blk = self:GetParent():GetParent()
            if button == "RightButton" then
                blk.cfg.width = 0
                DB.LayoutBar(blk.barCfg)
                return
            end
            if button ~= "LeftButton" then return end
            local bc, cfg = blk.cfg, blk.barCfg
            local x0 = GetCursorPosition() / blk:GetEffectiveScale()
            local st = { bc = bc, cfg = cfg, x0 = x0, w = blk:GetWidth(), scale = bc.scale or 100,
                text = IsShiftKeyDown(), s = blk:GetEffectiveScale() }
            self:SetScript("OnUpdate", function()
                local dx = GetCursorPosition() / st.s - st.x0
                if st.text then
                    local v = math.max(50, math.min(300, math.floor(st.scale + dx + 0.5)))
                    if v ~= st.bc.scale then st.bc.scale = v DB.ApplyBar(st.cfg) end
                    GameTooltip:SetOwner(self, "ANCHOR_TOP") GameTooltip:SetText(("Text size %d%%"):format(v)) GameTooltip:Show()
                else
                    local w = math.max(10, math.min(800, math.floor(st.w + dx + 0.5)))
                    if w ~= st.bc.width then
                        st.bc.width = w
                        DB.LayoutBar(st.cfg)
                    end
                    GameTooltip:SetOwner(self, "ANCHOR_TOP") GameTooltip:SetText(("Width %d"):format(w)) GameTooltip:Show()
                end
            end)
        end)
        e:SetScript("OnMouseUp", function(self)
            self:SetScript("OnUpdate", nil)
            GameTooltip:Hide()
            if ns.RefreshConfig then ns.RefreshConfig() end
        end)
        g.edge = e
        grabs[b] = g
    end
    g:Show()
    return g
end

-- handles on a bar's blocks (after ApplyBar rebuilt them)
function DB.Grabs(cfg)
    local rec = recs[cfg]
    if not rec then return end
    for _, b in ipairs(rec.blocks) do Grab(b) end
end

local function Panel()
    if panel then return panel end
    panel = CreateFrame("Frame", "HUF_ArrangeBlocks", UIParent)
    panel:SetSize(400, 128)
    panel:SetPoint("TOP", 0, -110)
    panel:SetFrameStrata("DIALOG")
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    ns.UI.Fill(panel, 0.05, 0.05, 0.06, 0.96)
    ns.UI.Border(panel, 0.2, 0.2, 0.22, 1)
    -- an accent line along the top, the title under it
    local top = panel:CreateTexture(nil, "ARTWORK")
    top:SetPoint("TOPLEFT", 1, -1)
    top:SetPoint("TOPRIGHT", -1, -1)
    top:SetHeight(2)
    top:SetColorTexture(A[1], A[2], A[3], 1)
    local icon = panel:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("TOPLEFT", 12, -12)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Gear_01")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local t = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    t:SetText("Arrange data bar blocks")
    t:SetTextColor(A[1], A[2], A[3])
    local close = ns.UI.Button(panel, 22, "x", function() DB.SetArranging(false) end)
    close:SetPoint("TOPRIGHT", -8, -10)
    local hints = {
        "|cffffd100Drag a block|r along its bar, or onto another data bar.",
        "|cffffd100Drag its right edge|r: its width.   |cffffd100Shift + drag|r: its text size.",
        "The accent line shows where a block will land.",
    }
    local prev
    for i, h in ipairs(hints) do
        local s = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        s:SetPoint("TOPLEFT", prev or icon, "BOTTOMLEFT", 0, i == 1 and -10 or -4)
        s:SetPoint("RIGHT", panel, "RIGHT", -12, 0)
        s:SetJustifyH("LEFT")
        s:SetText(h)
        prev = s
    end
    local done = ns.UI.Button(panel, 90, "Done", function() DB.SetArranging(false) end)
    done:SetPoint("BOTTOMRIGHT", -10, 10)
    local set = ns.UI.Button(panel, 130, "Data bar settings", function()
        DB.SetArranging(false)
        if ns.OpenConfigTab then ns.OpenConfigTab("databars", "blocks") end
    end)
    set:SetPoint("RIGHT", done, "LEFT", -8, 0)
    panel:Hide()
    return panel
end

function DB.SetArranging(on)
    on = on and true or false
    if drag then EndDrag(false) end
    DB.arranging = on
    for b, g in pairs(grabs) do g:SetShown(on and b:IsShown()) end
    if on then
        for cfg, rec in pairs(recs) do
            -- hidden by its visibility setting: shown while arranging
            if cfg.enabled and cfg.visibility ~= "NEVER" then rec.frame:Show() end
            DB.Grabs(cfg)
        end
    end
    Panel():SetShown(on)
    DB.UpdateVisibility()
end
function DB.ToggleArranging() DB.SetArranging(not DB.arranging) end

ns.OnLogin(function()
    DB.ApplyBars()
    C_Timer.NewTicker(1, function() Tick() end)
end)
ns.OnRefresh(function() if ns.ready then DB.ApplyBars() end end)
