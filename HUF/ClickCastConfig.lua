-- HUF: settings page for click-casting (GENERAL > Click-cast).
-- One row per binding: spell (typed or picked from the spellbook), key or
-- mouse button (press it), when it works, remove.

local _, ns = ...
local UI = ns.UI
local A = UI.ACCENT
local CC = ns.ClickCast

local ROWS = 11
local ROW_H = UI.ROW + 6

---------------------------------------------------------------------------
-- Key capture: press a key, click a mouse button or turn the wheel
---------------------------------------------------------------------------
local capture
local MODIFIER_KEYS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
                        LMETA = true, RMETA = true }

local function Capture(onKey)
    if not capture then
        local c = CreateFrame("Button", "HUFKeyCapture", UIParent)
        c:SetAllPoints(UIParent)
        c:SetFrameStrata("FULLSCREEN_DIALOG")
        c:EnableMouse(true)
        c:EnableMouseWheel(true)
        c:EnableKeyboard(true)
        c:RegisterForClicks("AnyUp")
        UI.Fill(c, 0, 0, 0, 0.55)
        local box = CreateFrame("Frame", nil, c)
        box:SetSize(420, 86)
        box:SetPoint("CENTER")
        UI.Fill(box, 0.07, 0.07, 0.08, 0.98)
        UI.Border(box, A[1], A[2], A[3], 0.8)
        local t = UI.Label(box, "Press a key or click a mouse button", "GameFontNormal")
        t:SetPoint("TOP", 0, -16)
        local n = UI.Label(box, "Hold Shift, Ctrl or Alt for a combination. The wheel works too. Esc cancels.")
        n:SetPoint("TOP", t, "BOTTOM", 0, -10)
        n:SetTextColor(0.7, 0.7, 0.7)
        local function Done(base)
            c:Hide()
            if base and c.onKey then
                c.onKey(CC.MakeKey(base, IsAltKeyDown(), IsControlKeyDown(), IsShiftKeyDown()))
            end
        end
        c:SetScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then Done(nil) return end
            if MODIFIER_KEYS[key] then return end
            Done(key)
        end)
        c:SetScript("OnMouseDown", function(self, button) Done(CC.MouseKey(button)) end)
        c:SetScript("OnMouseWheel", function(self, delta) Done(delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN") end)
        if c.SetPropagateKeyboardInput then pcall(c.SetPropagateKeyboardInput, c, false) end
        c:Hide()
        capture = c
    end
    capture.onKey = onKey
    capture:Show()
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------
ns.RegisterPage("clickcast", "Click-Casting", "general", function(page)
    local offset = 0

    local on = UI.Check(page, 300, "Click-casting on HUF's frames",
        function() return CC.Data().enabled end,
        function(v) CC.Data().enabled = v CC.Apply() end,
        "Off: plain clicks again (left targets, right opens the menu).")
    on:SetPoint("TOPLEFT", 0, 4)
    local note = UI.Label(page, "")
    note:SetPoint("TOPLEFT", 0, -22)
    note:SetWidth(ns.PAGE_W)
    note:SetJustifyH("LEFT")
    note:SetTextColor(0.65, 0.65, 0.65)
    note:SetText("Over a HUF frame (player, target, target of target, group), the key or mouse button casts the spell on that unit, like a [@mouseover] macro. " ..
        "Keys only count while the mouse is over a frame. These bindings belong to this character.")
    note:SetWordWrap(true)

    -- column titles
    local TOP = -62
    local X_SPELL, W_SPELL = 0, 210
    local X_BOOK, W_BOOK = 214, 96
    local X_KEY, W_KEY = 318, 170
    local X_WHEN, W_WHEN = 494, 150
    local X_DEL = 650
    local function Title(text, x)
        local fs = UI.Label(page, text)
        fs:SetPoint("TOPLEFT", x, TOP)
        fs:SetTextColor(A[1], A[2], A[3])
    end
    Title("Spell", X_SPELL); Title("Key or mouse button", X_KEY); Title("Works", X_WHEN)

    local list = CreateFrame("Frame", nil, page)
    list:SetPoint("TOPLEFT", 0, TOP - 18)
    list:SetSize(ns.PAGE_W, ROWS * ROW_H)
    list:EnableMouseWheel(true)
    local empty = UI.Label(list, "No bindings yet: Add binding (below).")
    empty:SetPoint("TOPLEFT", 4, -6)
    empty:SetTextColor(0.5, 0.5, 0.5)

    local rows = {}
    local function Entry(r) return CC.Bindings()[r.index] end
    local Render

    for i = 1, ROWS do
        local r = CreateFrame("Frame", nil, list)
        r:SetSize(ns.PAGE_W, ROW_H)
        r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
        r.spell = UI.EditBox(r, W_SPELL, "spell name")
        r.spell:SetPoint("LEFT", X_SPELL, 0)
        r.spell:SetScript("OnTextChanged", function(self, user)
            self:UpdatePlaceholder()
            local e = Entry(r)
            if user and e then e.spell = self:GetText() end
        end)
        local function Commit(self)
            self:ClearFocus()
            CC.Apply()
        end
        r.spell:SetScript("OnEnterPressed", Commit)
        r.spell:HookScript("OnEditFocusLost", function() CC.Apply() end)

        r.book = UI.Dropdown(r, W_BOOK, "Book", function() return CC.Spells() end, function() return nil end, function(v)
            local e = Entry(r)
            if e then e.spell = v end
            CC.Apply()
            Render()
        end)
        r.book:SetPoint("LEFT", X_BOOK, 0)
        r.book.Refresh = function() r.book.valueLabel:SetText("") end

        r.key = UI.Button(r, W_KEY, "", function()
            Capture(function(key)
                local e = Entry(r)
                if not e then return end
                e.key = key
                ns.Log("config", "click-cast key %s for %s", key, tostring(e.spell))
                CC.Apply()
                Render()
            end)
        end)
        r.key:SetPoint("LEFT", X_KEY, 0)
        UI.Tooltip(r.key, "Key or mouse button", "Click, then press the key or click the mouse button (with Shift, Ctrl, Alt if you like).")

        r.when = UI.Dropdown(r, W_WHEN, "", CC.WHEN, function()
            local e = Entry(r)
            return e and e.when or "BOTH"
        end, function(v)
            local e = Entry(r)
            if e then e.when = v end
            CC.Apply()
        end)
        r.when:SetPoint("LEFT", X_WHEN, 0)

        r.del = UI.TextButton(r, "x", function()
            CC.Remove(r.index)
            Render()
        end)
        r.del:SetPoint("LEFT", X_DEL, 0)
        UI.Tooltip(r.del, "Remove this binding")
        rows[i] = r
    end

    -- the same key twice: the later rows of that key only count for the other combat state
    local function Duplicates()
        local seen, dup = {}, {}
        for i, b in ipairs(CC.Bindings()) do
            if b.key and b.key ~= "" then
                local k = b.key .. "|" .. (b.when == "BOTH" and "ANY" or b.when)
                if seen[k] or (b.when ~= "BOTH" and seen[b.key .. "|ANY"]) then dup[i] = true end
                seen[k] = true
            end
        end
        return dup
    end

    Render = function()
        local data = CC.Bindings()
        offset = math.max(0, math.min(offset, #data - ROWS))
        local dup = Duplicates()
        for i, r in ipairs(rows) do
            local idx = i + offset
            local e = data[idx]
            r.index = idx
            if e then
                if not r.spell:HasFocus() then r.spell:SetText(e.spell or "") end
                r.spell:UpdatePlaceholder()
                local kt = CC.KeyText(e.key)
                r.key.label:SetText(dup[idx] and ("|cffff6060" .. kt .. "|r") or kt)
                r.when.Refresh()
                r:Show()
            else
                r:Hide()
            end
        end
        empty:SetShown(#data == 0)
    end
    list:SetScript("OnMouseWheel", function(_, delta)
        offset = offset - delta
        Render()
    end)

    local add = UI.Button(page, 140, "Add binding", function()
        local n = CC.Add()
        offset = math.max(0, n - ROWS)
        Render()
    end)
    add:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 0, -8)
    local hint = UI.Label(page, "")
    hint:SetPoint("LEFT", add, "RIGHT", 12, 0)
    hint:SetWidth(ns.PAGE_W - 160)
    hint:SetJustifyH("LEFT")
    hint:SetWordWrap(true)
    hint:SetTextColor(0.6, 0.6, 0.6)
    hint:SetText("One key can hold two spells: one for in combat, one for out of combat. A binding on plain left or right click replaces targeting or the menu. Changes made in combat apply when it ends. Scroll the list with the mouse wheel.")

    table.insert(page.widgets, { Refresh = Render })
end)
