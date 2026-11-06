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

local function newDialog()
    local d = newFrame()
    d.buttons, d.contentWidth = {}, 440
    function d:AddText() return newFrame() end
    function d:AddSection() return newFrame(), newFrame() end
    function d:AddField() end
    function d:AddButton(label, fn) self.buttons[label] = fn end
    function d:Fit() end
    return d
end
local dialogs = {}

local box, grid, linkBox
LibStub = function()
    return {
        Size = { icon = 16, input = 160 }, Space = { tight = 4, gap = 8 }, Native = { inputHeight = 20, inputArt = 5 },
        ScrollGutter = function() return 24 end,
        Print = function(_, msg) printed[#printed + 1] = msg end,
        ShowTooltip = function() end,
        CreateDialog = function(spec) local d = newDialog(); dialogs[spec.name] = d; return d end,
        CreateSearchBox = function() box = newFrame(); box.Instructions = newFrame(); return box end,
        CreateEditBox = function()
            linkBox = newFrame()
            linkBox.SetCursorPosition, linkBox.HighlightText = function() end, function() end
            return linkBox
        end,
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
IsMacClient = function() return true end
IsMetaKeyDown = function() return true end
IsControlKeyDown = function() return false end
EditBox_HighlightText = function() end
GREEN_FONT_COLOR = { GetRGB = function() return 0, 1, 0 end }
local copied = 0
UIErrorsFrame = { AddMessage = function() copied = copied + 1 end }
local menu
MenuUtil = { CreateContextMenu = function(owner, gen)
    menu = { title = nil, items = {} }
    local root = {}
    function root:CreateTitle(t) menu.title = t end
    function root:CreateButton(label, fn) menu.items[label] = fn end
    gen(owner, root)
end }
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

local function setIcon()
    menu = nil
    button.hooks.OnMouseUp(button, "RightButton")
    if menu then menu.items["Set Icon"]() end
end

button.hooks.OnMouseUp(button, "LeftButton")
assert(not menu, "left click opened the menu")
setIcon()
assert(menu.title == "COOK" and menu.items["Copy Wowhead Icon Link"], "menu entries")
local dialog = dialogs.EasyMacroIconsDialog
assert(dialog.shown, "Set Icon did not open the dialog")
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
setIcon()
assert(#grid.items == 4, "reopening did not reset the filter")
box:SetText("99999")
assert(#grid.items == 0)
dialog.buttons.Okay()
assert(edits[2][3] == 99999 and #printed == 1 and printed[1]:find("kept the old icon"), "no warning for a refused icon")

-- Typing after a pick drops the pick.
setIcon()
grid.selected(1, 134400)
box:SetText("1339")
dialog.buttons.Okay()
assert(edits[3][3] == 1339, "a stale grid pick was applied")

-- A pasted Wowhead icon link filters by and applies its ID; other text matches nothing.
accepts = true
setIcon()
box:SetText("https://www.wowhead.com/forever/icon=7808148/inv-camelot-camping-welcomingcampfire")
assert(#grid.items == 1 and grid.items[1] == 7808148, "pasted link did not filter")
dialog.buttons.Okay()
assert(edits[4][3] == 7808148, "pasted link did not apply")
setIcon()
box:SetText("fish")
assert(#grid.items == 0)
dialog.buttons.Okay()
assert(#edits == 4, "text without an ID applied")
dialog:Hide()

-- The link dialog keeps its link, confirms a copy and hands over to Set Icon.
button.hooks.OnMouseUp(button, "RightButton")
menu.items["Copy Wowhead Icon Link"]()
local linkDialog = dialogs.EasyMacroIconsLinkDialog
assert(linkDialog.shown and linkBox:GetText() == "https://www.wowhead.com/forever/icons")
linkBox.text = "x"
linkBox.scripts.OnTextChanged(linkBox, true)
assert(linkBox:GetText() == "https://www.wowhead.com/forever/icons", "link was editable")
linkBox.scripts.OnKeyDown(linkBox, "C")
assert(copied == 1 and linkDialog.shown, "copy not confirmed or dialog closed")
linkDialog.buttons["Set Icon"]()
assert(dialog.shown and not linkDialog.shown, "Set Icon did not switch dialogs")
dialog:Hide()

macros[121] = nil
menu = nil
button.hooks.OnMouseUp(button, "RightButton")
assert(not menu, "an empty slot opened the menu")

print("Smoke: all checks passed.")
