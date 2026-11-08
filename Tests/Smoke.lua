-- Offline smoke test: lua Tests/Smoke.lua from the repo root.
-- Stubs the client and the Blizzard templates the dialogs are built from, loads the addon, right-clicks a macro
-- button, filters and sets an icon.

local realPrint = print
local printed, edits = {}, {}
print = function(line) printed[#printed + 1] = line end
local macros = { [121] = { "COOK", 134400, "#showtooltip" } }
local accepts = true

local function noop() end

-- A frame or font string with the widget methods the addon and its recipes call.
local function newFrame(template)
    local f = { scripts = {}, hooks = {}, text = "", shown = false, template = template }
    function f:SetScript(k, fn) self.scripts[k] = fn end
    function f:HookScript(k, fn) self.hooks[k] = fn end
    function f:SetText(t)
        self.text = t
        if self.hooks.OnTextChanged then self.hooks.OnTextChanged(self) end
    end
    function f:GetText() return self.text end
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    function f:IsShown() return self.shown end
    function f:SetHeight(h) self.height = h end
    function f:GetHeight() return self.height end
    function f:SetWidth(w) self.width = w end
    function f:SetSize(w, h) self.width, self.height = w, h end
    function f:ClearAllPoints() self.point = nil end
    function f:SetPoint(...) self.point = { ... } end
    function f:GetPoint() return table.unpack(self.point) end
    function f:GetTextWidth() return 7 * #self.text end
    function f:GetStringHeight() return 0 end
    function f:GetTextColor() return 0.35, 0.35, 0.35 end
    function f:CreateFontString() return newFrame() end
    for _, k in ipairs({ "SetFontObject", "SetJustifyH", "SetWordWrap", "SetTextColor", "SetAutoFocus",
        "SetMaxLetters", "SetFocus", "SetCursorPosition", "HighlightText", "SetFrameStrata", "SetToplevel",
        "SetClampedToScreen", "SetMovable", "EnableMouse", "RegisterForDrag", "StartMoving", "StopMovingOrSizing",
        "SetCustomStride", "SetCustomPadding" }) do
        f[k] = noop
    end
    return f
end

local function newFont(size) return { GetFont = function() return "Fonts\\FRIZQT__.TTF", size end } end
GameFontNormalLarge, GameFontHighlight, GameFontDisable = newFont(16), newFont(12), newFont(12)
UIParent, UISpecialFrames, tinsert = newFrame(), {}, table.insert
GameTooltip = newFrame()
function GameTooltip:SetOwner(owner) self.owner = owner end
GameTooltip_SetTitle = function(tooltip, text) tooltip.title = text end
GameTooltip_Hide = noop
C_AddOns = { GetAddOnMetadata = function(name, key)
    assert(name == "EasyMacroIcons" and key == "Title")
    return "Easy Macro Icons"
end }
NORMAL_FONT_COLOR = { WrapTextInColorCode = function(_, text) return "<gold>" .. text .. "</gold>" end }

-- Named frames by name, and the last frame made from each template the test drives.
local named, box, grid, linkBox = {}, nil, nil, nil
CreateFrame = function(_, name, parent, template)
    local f = newFrame(template)
    f.parent = parent
    if name then named[name] = f end
    if template == "DialogHeaderTemplate" then
        function f:Setup(title) self.title = title end
    elseif template == "SearchBoxTemplate" then
        f.Instructions = newFrame()
        box = f
    elseif template == "InputBoxTemplate" then
        linkBox = f
    elseif template == "ScrollBoxSelectorTemplate" then
        function f:SetSetupCallback(fn) self.setup = fn end
        function f:SetSelectedCallback(fn) self.selected = fn end
        function f:SetSelectionsArray(a) self.items = a end
        function f:SetSelectedIndex(i) self.index = i end
        grid = f
    end
    return f
end

-- Clicks the dialog's button with this label.
local function click(dialog, label)
    for _, button in ipairs(dialog.buttons) do
        if button.text == label then return button.scripts.OnClick(button) end
    end
    error("no " .. label .. " button")
end

OKAY, CANCEL = "Okay", "Cancel"
IsMacClient = function() return true end
IsMetaKeyDown = function() return true end
IsControlKeyDown = function() return false end
EditBox_HighlightText = function() end
GREEN_FONT_COLOR = { GetRGB = function() return 0, 1, 0 end }
C_Timer = { After = function(_, fn) fn() end }
local copied = 0
UIErrorsFrame = { AddMessage = function() copied = copied + 1 end }
local menu
MenuUtil = { CreateContextMenu = function(owner, gen)
    menu = { title = nil, items = {}, enabled = {} }
    local root = {}
    function root:CreateTitle(t) menu.title = t end
    function root:CreateButton(label, fn)
        local key = label:match("^Paste Icon") and "Paste Icon" or label
        menu.items[key], menu.enabled[key], menu.labels = fn, true, menu.labels or {}
        menu.labels[key] = label
        return { SetEnabled = function(_, on) menu.enabled[key] = on end }
    end
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

local ns = {}
assert(loadfile("Core.lua"))("EasyMacroIcons", ns)
assert(loadfile("EasyMacroIcons.lua"))("EasyMacroIcons", ns)
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
assert(menu.title == "COOK" and menu.items["Wowhead Link"], "menu entries")
local dialog = named.EasyMacroIconsDialog
assert(dialog.shown, "Set Icon did not open the dialog")
assert(dialog.parent == MacroFrame and dialog.Header.title == "Easy Macro Icons", "dialog chrome")
assert(UISpecialFrames[1] == "EasyMacroIconsDialog", "Escape does not close the dialog")
assert(box.width == 435 and box.point[4] == 25, "search box not indented by its 5 px cap")
assert(grid.width == 420 and grid.height == 220, "grid size changed: " .. grid.width .. " x " .. grid.height)
local iconButton = newFrame("SelectorButtonTemplate")
iconButton.SetIconTexture = noop
grid.setup(iconButton, 1, 7808148)
iconButton.scripts.OnEnter(iconButton)
assert(GameTooltip.owner == iconButton and GameTooltip.title == "Icon ID 7808148", "icon tooltip")
assert(dialog.point and dialog.point[1] == "TOPLEFT" and dialog.point[2] == MacroFrame and dialog.point[3] == "TOPRIGHT",
    "Set Icon dialog not beside the macro window")
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
click(dialog, OKAY)
assert(edits[2][3] == 99999 and #printed == 1, "no warning for a refused icon")
assert(printed[1] == "<gold>[Easy Macro Icons]</gold>: The game kept the old icon, so 99999 may not exist on this client.",
    "chat line not in the shared format: " .. printed[1])

-- Typing after a pick drops the pick.
setIcon()
grid.selected(1, 134400)
box:SetText("1339")
click(dialog, OKAY)
assert(edits[3][3] == 1339, "a stale grid pick was applied")

-- A pasted Wowhead icon link filters by and applies its ID; other text matches nothing.
accepts = true
setIcon()
box:SetText("https://www.wowhead.com/forever/icon=7808148/inv-camelot-camping-welcomingcampfire")
assert(#grid.items == 1 and grid.items[1] == 7808148, "pasted link did not filter")
click(dialog, OKAY)
assert(edits[4][3] == 7808148, "pasted link did not apply")
setIcon()
box:SetText("fish")
assert(#grid.items == 0)
click(dialog, OKAY)
assert(#edits == 4, "text without an ID applied")
dialog:Hide()

-- The link dialog keeps its link, and one copy keypress confirms and closes it, as in Player Armory Link.
button.hooks.OnMouseUp(button, "RightButton")
menu.items["Wowhead Link"]()
local linkDialog = named.EasyMacroIconsLinkDialog
assert(linkDialog.shown and linkBox:GetText() == "https://www.wowhead.com/forever/icons")
linkBox.text = "x"
linkBox.scripts.OnTextChanged(linkBox, true)
assert(linkBox:GetText() == "https://www.wowhead.com/forever/icons", "link was editable")
linkBox.scripts.OnKeyDown(linkBox, "V")
assert(copied == 0 and linkDialog.shown, "another key closed the dialog")
linkBox.scripts.OnKeyDown(linkBox, "C")
assert(copied == 1 and not linkDialog.shown, "copy not confirmed or dialog still open")

-- Copy Icon on one macro, Paste Icon on another.
macros[122] = { "FISH", 134400, "#showtooltip" }
local button2 = newFrame()
button2.GetElementData = function() return 2 end
button2.IsMouseOver = function() return true end
callback(button2, 2, true)
button.hooks.OnMouseUp(button, "RightButton")
assert(menu.enabled["Paste Icon"] == false, "Paste Icon enabled before a copy")
local before = copied
menu.items["Copy Icon"]()
assert(copied == before + 1, "copy not confirmed")
button.hooks.OnMouseUp(button, "RightButton")
assert(menu.enabled["Paste Icon"] == false, "Paste Icon enabled on the macro that already has the icon")
button2.hooks.OnMouseUp(button2, "RightButton")
assert(menu.enabled["Paste Icon"] and menu.labels["Paste Icon"]:find("7808148"), "Paste Icon missing its icon")
local n = #edits
menu.items["Paste Icon"]()
assert(#edits == n + 1 and edits[n + 1][1] == 122 and edits[n + 1][2] == "FISH" and edits[n + 1][3] == 7808148, "paste")
assert(macros[122][2] == 7808148)

macros[121] = nil
menu = nil
button.hooks.OnMouseUp(button, "RightButton")
assert(not menu, "an empty slot opened the menu")

realPrint("Smoke: all checks passed.")
