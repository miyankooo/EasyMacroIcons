-- Offline smoke test: lua Tests/Smoke.lua from the repo root.
-- Stubs the client and LibNativeUI, loads the addon, right-clicks a macro button and sets an icon.

local printed, edits = {}, {}
local macros = { [121] = { "COOK", 134400, "#showtooltip" } }
local accepts = true

local function newFrame()
    local f = { scripts = {}, hooks = {}, text = "", shown = false }
    function f:SetScript(k, fn) self.scripts[k] = fn end
    function f:HookScript(k, fn) self.hooks[k] = fn end
    function f:SetText(t) self.text = t; if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self) end end
    function f:GetText() return self.text end
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    for _, k in ipairs({ "SetNumeric", "SetMaxLetters", "SetFocus" }) do f[k] = function() end end
    return f
end

local dialog = newFrame()
dialog.buttons = {}
function dialog:AddText() return newFrame() end
function dialog:AddField() end
function dialog:AddButton(label, fn) self.buttons[label] = fn end
function dialog:Fit() end

local box
LibStub = function()
    return {
        Size = { icon = 16, input = 160 }, Space = { tight = 4, gap = 8 }, Native = { inputHeight = 20, inputArt = 5 },
        Print = function(_, msg) printed[#printed + 1] = msg end,
        CreateDialog = function() return dialog end,
        CreateEditBox = function() box = newFrame(); return box end,
    }
end
OKAY, CANCEL = "Okay", "Cancel"
CreateSimpleTextureMarkup = function(icon) return "|T" .. icon .. "|t" end
InCombatLockdown = function() return false end
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
    MacroSelector = { ScrollBox = { RegisterCallback = function(_, event, fn, owner) callback = function(...) fn(owner, ...) end end } },
}
EventUtil = { ContinueOnAddOnLoaded = function(name, fn) assert(name == "Blizzard_MacroUI"); fn() end }

assert(loadfile("MacroIconID.lua"))("MacroIconID", {})
assert(callback, "no acquire callback")

local button = newFrame()
button.GetElementData = function() return 1 end
button.IsMouseOver = function() return true end
callback(button, 1, true)

button.hooks.OnMouseUp(button, "LeftButton")
assert(not dialog.shown, "left click opened the dialog")
button.hooks.OnMouseUp(button, "RightButton")
assert(dialog.shown, "right click did not open the dialog")

box:SetText("7808148")
box.scripts.OnEnterPressed(box)
assert(edits[1][1] == 121 and edits[1][2] == "COOK" and edits[1][3] == 7808148, "wrong EditMacro call")
assert(macros[121][2] == 7808148 and not dialog.shown and #printed == 0)

accepts = false
button.hooks.OnMouseUp(button, "RightButton")
box:SetText("1")
dialog.buttons.Okay()
assert(#printed == 1 and printed[1]:find("kept the old icon"), "no warning for a refused icon")

macros[121] = nil
button.hooks.OnMouseUp(button, "RightButton")
assert(#edits == 2, "an empty slot opened the dialog")

print("Smoke: all checks passed.")
