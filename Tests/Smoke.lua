-- Offline smoke test: lua Tests/Smoke.lua from the repo root.
-- Stubs the client and LibNativeUI, loads the addon, right-clicks a macro button, filters and sets an icon.

local printed, edits = {}, {}
local macros = { [121] = { "COOK", 134400, "#showtooltip" } }
local accepts = true

local function newFrame()
    local f = { scripts = {}, hooks = {}, text = "", shown = false }
    function f:SetScript(k, fn) self.scripts[k] = fn end
    function f:HookScript(k, fn) self.hooks[k] = fn end
    function f:SetText(t)
        self.text = t
        if self.hooks.OnTextChanged then self.hooks.OnTextChanged(self) end
    end
    function f:GetText() return self.text end
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    function f:GetHeight() return self.height end
    function f:SetSize(w, h) self.width, self.height = w, h end
    for _, k in ipairs({ "SetNumeric", "SetMaxLetters", "SetFocus", "SetCustomStride", "SetCustomPadding" }) do
        f[k] = function() end
    end
    return f
end

local dialog = newFrame()
dialog.buttons, dialog.contentWidth = {}, 440
function dialog:AddText() return newFrame() end
function dialog:AddField() end
function dialog:AddButton(label, fn) self.buttons[label] = fn end
function dialog:Fit() end

local box, grid
LibStub = function()
    return {
        Size = { icon = 16, input = 160 }, Space = { tight = 4, gap = 8 }, Native = { inputHeight = 20, inputArt = 5 },
        ScrollGutter = function() return 24 end,
        Print = function(_, msg) printed[#printed + 1] = msg end,
        ShowTooltip = function() end,
        CreateDialog = function() return dialog end,
        CreateSearchBox = function() box = newFrame(); return box end,
    }
end
CreateFrame = function(_, _, _, template)
    assert(template == "ScrollBoxSelectorTemplate")
    grid = newFrame()
    function grid:SetSetupCallback(fn) self.setup = fn end
    function grid:SetSelectedCallback(fn) self.selected = fn end
    function grid:SetSelectionsArray(a) self.items = a end
    function grid:SetSelectedIndex(i) self.index = i end
    return grid
end
OKAY, CANCEL = "Okay", "Cancel"
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
CreateSimpleTextureMarkup = function(icon) return "|T" .. icon .. "|t" end
InCombatLockdown = function() return false end
GetMacroIcons = function(t) for _, v in ipairs({ 134400, "loose_name", 135808, 7808148 }) do t[#t + 1] = v end end
GetMacroItemIcons = function(t) for _, v in ipairs({ 133971, 134400 }) do t[#t + 1] = v end end
GetMacroInfo = function(i) local m = macros[i]; if m then return m[1], m[2], m[3] end end
EditMacro = function(i, name, icon)
    edits[#edits + 1] = { i, name, icon }
    if accepts then macros[i][2] = icon end
    return i
end

local callback
ScrollBoxListMixin = { Event = { OnAcquiredFrame = "OnAcquiredFrame" } }
MacroFrame = {
    macroBase = 120,
    GetMacroDataIndex = function(self, index) return self.macroBase + index end,
    MacroSelector = { ScrollBox = { RegisterCallback = function(_, _, fn, owner) callback = function(...) fn(owner, ...) end end } },
}
EventUtil = { ContinueOnAddOnLoaded = function(name, fn) assert(name == "Blizzard_MacroUI"); fn() end }

assert(loadfile("EasyMacroIcons.lua"))("EasyMacroIcons", {})
assert(callback, "no acquire callback")

local button = newFrame()
button.GetElementData = function() return 1 end
button.IsMouseOver = function() return true end
callback(button, 1, true)

button.hooks.OnMouseUp(button, "LeftButton")
assert(not dialog.shown, "left click opened the dialog")
button.hooks.OnMouseUp(button, "RightButton")
assert(dialog.shown, "right click did not open the dialog")
assert(#grid.items == 4, "icons not loaded once each without loose names: " .. #grid.items)

-- Filtering by part of the ID, then picking from the grid.
box:SetText("80")
assert(#grid.items == 2 and grid.items[1] == 135808 and grid.items[2] == 7808148, "filter by part of the ID")
grid.selected(2, 7808148)
box.scripts.OnEnterPressed(box)
assert(edits[1][1] == 121 and edits[1][2] == "COOK" and edits[1][3] == 7808148, "wrong EditMacro call")
assert(not dialog.shown and #printed == 0)

-- A typed ID outside the list still applies, and a refused one warns.
accepts = false
button.hooks.OnMouseUp(button, "RightButton")
assert(#grid.items == 4, "reopening did not reset the filter")
box:SetText("99999")
assert(#grid.items == 0)
dialog.buttons.Okay()
assert(edits[2][3] == 99999 and #printed == 1 and printed[1]:find("kept the old icon"), "no warning for a refused icon")

-- Typing after a pick drops the pick.
button.hooks.OnMouseUp(button, "RightButton")
grid.selected(1, 134400)
box:SetText("1339")
dialog.buttons.Okay()
assert(edits[3][3] == 1339, "a stale grid pick was applied")

macros[121] = nil
button.hooks.OnMouseUp(button, "RightButton")
assert(#edits == 3, "an empty slot opened the dialog")

print("Smoke: all checks passed.")
