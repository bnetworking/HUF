-- HUF: tooltip settings (GENERAL > Utility Frames > Tooltips).

local _, ns = ...
local UI = ns.UI
local COL_W, COL2_X = 330, 366

local function T() return ns.db.tooltip end
-- getter and setter as two single values (a pair cut short by a following
-- argument loses its setter)
local function G(k) return function() return T()[k] end end
local function S(k) return function(v) T()[k] = v end end

ns.RegisterPage("tooltips", "Tooltips", "utility", function(page)
    local L = UI.Column(page, 0, 0, COL_W)
    L:Header("Tooltips").hufNoGate = true
    local master = L:Check("Use HUF's tooltip settings", G("enabled"), function(v)
        T().enabled = v
        if not v then ns.AskReload("The game's own tooltip place and colours come back after a reload.") end
    end, "Place, extra lines and colours of the game's tooltips. Off: the game's own (after a reload).")
    master.hufNoGate = true
    -- everything else waits for the switch (registered first: the border
    -- colour's own greying below runs after it)
    UI.Gate(page, master, function() return T().enabled end)
    L:Cycle("Show tooltip at", {
        { value = "CURSOR_LEFT", text = "Cursor Left" },
        { value = "CURSOR_RIGHT", text = "Cursor Right" },
        { value = "FIXED", text = "Fixed" },
    }, G("anchor"), S("anchor"), "Next to the mouse pointer, or always at one place. The fixed place can be moved in unlock mode (box \"Tooltip (fixed place)\").")
    L:Check("In combat, show at the fixed location", G("combatFixed"), S("combatFixed"),
        "While in combat the tooltip goes to the fixed place, out of the way of the fight; out of combat it follows the setting above.")
    L:Check("Show target's target", G("targetOfTarget"), S("targetOfTarget"),
        "A line with what the unit under the mouse is targeting (\">> You <<\" when it is you; players in privacy names and class colours).")
    L:Check("Player title", G("title"), S("title"),
        "Show a player's title (e.g. \"Private\", \"the Explorer\") with the name. Off: the name alone.")
    L:Check("Show spell ID", G("spellID"), S("spellID"), "The spell's ID under spells and buffs / debuffs.")

    local R = UI.Column(page, COL2_X, 0, COL_W)
    R:Header("Look")
    R:Color("Background Colour", G("bgColor"), S("bgColor"))
    local ga = function() return math.floor((T().bgAlpha or 0.85) * 100 + 0.5) end
    local opacity = R:Slider("Background Opacity", 0, 100, 5, ga, function(v) T().bgAlpha = v / 100 end, "%d%%")
    opacity.EnableInput()
    R:Cycle("Border", { { value = "ACCENT", text = "Accent colour" }, { value = "CUSTOM", text = "Own colour" },
        { value = "NONE", text = "No border" } },
        G("border"), S("border"), "The tooltip's edge in HUF's accent colour, a colour of your own, or no edge at all.")
    local bc = R:Color("Border Colour", G("borderColor"), S("borderColor"))
    table.insert(page.widgets, { Refresh = function()
        UI.SetActive(bc, T().enabled and T().border == "CUSTOM")
    end })
end)
