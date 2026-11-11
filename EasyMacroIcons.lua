-- Right-click a macro in Blizzard's macro window for a menu: set its icon from a grid filtered by ID, copy and
-- paste icons between macros, or copy the link to Wowhead's WoW Forever icon library to look an ID up.
local addonName, ns = ...

local WOWHEAD_ICONS = "https://www.wowhead.com/forever/icons"
local STRIDE = 9
local ROWS = 5
local ICON_BUTTON = 36   -- SelectorButtonTemplate's size, Blizzard_SelectorUI.xml

-- Sizes on the 4 px grid.
local TIGHT = 4           -- label to control, hint under a field
local GAP = 8             -- between related controls, heading to body
local ICON = 16           -- inline icons
local SCROLL_GUTTER = 24  -- right margin a scroll frame leaves for its bar

-- InputBoxTemplate's art height and its left cap outside the box (Shared/InputBox/InputBoxTemplates.xml:47-49).
local EDIT_BOX_HEIGHT = 20
local EDIT_BOX_CAP = 5

-- Long enough for the client to finish the copy before the edit box goes away.
local CLOSE_DELAY = 0.2

-- macOS copies only with Cmd, so Ctrl there must not close the dialog or report a copy.
local COPY_KEY = IsMacClient() and "Cmd" or "Ctrl"
local copyModifier = IsMacClient() and IsMetaKeyDown or IsControlKeyDown

local dialog, subject, box, grid, hint
local linkDialog, linkBox
local macroIndex, picked
local copiedIcon   -- Copy Icon keeps it for Paste Icon until /reload; the system clipboard is out of reach.
local allIcons, shown = nil, {}

-- Text in a font role: GameFontNormal (heading, gold), GameFontHighlight (body, white), GameFontDisable (muted,
-- grey), GameFontNormalLarge (title, 16 px, a dialog's subject line only).
local function CreateText(parent, fontObject, layer)
    local text = parent:CreateFontString(nil, layer or "ARTWORK")
    text:SetFontObject(fontObject or GameFontHighlight)
    text:SetJustifyH("LEFT")
    return text
end

-- A GameTooltip owned by the hovered frame, filled with Blizzard's GameTooltip_* line helpers. A frame whose
-- template already sets OnEnter gets HookScript instead.
local function AttachTooltip(frame, fill, anchor)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, anchor or "ANCHOR_RIGHT")
        fill(GameTooltip, self)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", GameTooltip_Hide)
end

-- Rounds a length derived from text up to the 4 px grid.
local function Snap(length)
    return math.ceil(length / 4) * 4
end

-- A content button one row (24) tall. Without a width it fits its label the way UIPanelButtonTemplate's FitToText
-- does (text plus 40, SecureUIPanelTemplates.xml:42), at least 64, rounded up to 8 so neighbours share widths.
local function CreateButton(parent, label, width)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetText(label)
    width = width or math.max(64, math.ceil((button:GetTextWidth() + 40) / 8) * 8)
    button:SetSize(width, 24)
    return button
end

-- InputBoxTemplate draws its left cap 5 px outside the box (InputBoxTemplates.xml:49), so the caller indents the
-- box by 5 to line the art up with the column.
local function CreateEditBox(parent, width)
    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetSize(width or 160, 20)
    box:SetAutoFocus(false)
    box:SetFontObject(GameFontHighlight)
    return box
end

-- SearchBoxTemplate types and hints in 10 px fonts; both move to the 12 px roles, the hint keeping its grey.
local function CreateSearchBox(parent, width, name)
    local box = CreateFrame("EditBox", name, parent, "SearchBoxTemplate")
    box:SetSize(width or 160, 20)
    box:SetAutoFocus(false)
    box:SetFontObject(GameFontHighlight)
    local r, g, b = box.Instructions:GetTextColor()
    box.Instructions:SetFontObject(GameFontDisable)
    box.Instructions:SetTextColor(r, g, b)
    return box
end

-- Blizzard's own icon picker grid, as the macro book's icon picker: ScrollBoxSelectorTemplate with its
-- SelectorButtonTemplate buttons. setup(button, index, icon) sets the icon and its tooltip.
local function CreateIconGrid(parent, setup)
    local grid = CreateFrame("Frame", nil, parent, "ScrollBoxSelectorTemplate")
    grid:SetSetupCallback(setup)
    return grid
end

-- Restores a saved position, or centres the frame.
local function RestorePosition(frame, position)
    frame:ClearAllPoints()
    if position and position.point then
        frame:SetPoint(position.point, UIParent, position.relPoint or position.point, position.x or 0, position.y or 0)
    else
        frame:SetPoint("CENTER")
    end
end

-- Windows and dialogs: toplevel, clamped, dragged with the left button, closed by Escape through UISpecialFrames,
-- never UIPanelWindows, so they never drive Blizzard's panel layout.
local function MakeMovable(frame, name, strata, position)
    frame:SetFrameStrata(strata)
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if position then
            local point, _, relPoint, x, y = self:GetPoint(1)
            position.point, position.relPoint, position.x, position.y = point, relPoint, x, y
        end
    end)
    RestorePosition(frame, position)
    frame:Hide()
    tinsert(UISpecialFrames, name)
end

-- A dialog in Blizzard's dialog chrome: DialogBorderTemplate, DialogHeaderTemplate with the title and
-- UIPanelCloseButton 2 px in from the corner (Blizzard_Channels/Mainline/CreateChannelPopup.xml:72). Width is a
-- multiple of 8 from 400 to 480. Add content top to bottom with AddText and AddField, then call Fit.
local DIALOG_SIDE, DIALOG_TOP, SECTION_GAP = 20, 40, 24
local function CreateDialog(name, title, width, parent, position)
    local dialog = CreateFrame("Frame", name, parent or UIParent)
    dialog:SetSize(width, DIALOG_TOP + DIALOG_SIDE)
    dialog.contentWidth = width - 2 * DIALOG_SIDE
    dialog.contentHeight = 0
    dialog.buttons = {}
    dialog.Border = CreateFrame("Frame", nil, dialog, "DialogBorderTemplate")
    dialog.Header = CreateFrame("Frame", nil, dialog, "DialogHeaderTemplate")
    dialog.Header:Setup(title)
    -- UIPanelCloseButton_OnClick goes through HideUIPanel, which refuses insecure callers in combat.
    dialog.CloseButton = CreateFrame("Button", nil, dialog, "UIPanelCloseButton")
    dialog.CloseButton:SetPoint("TOPRIGHT", -2, -2)
    dialog.CloseButton:SetScript("OnClick", function() dialog:Hide() end)

    -- Places a widget the caller sized in the content column below everything added so far; indent covers native
    -- art, 5 for an edit box, 8 for a dropdown. The gap defaults to 8; AddText passes a section break.
    function dialog:AddField(region, height, gap, indent)
        if self.hasContent then self.contentHeight = self.contentHeight + (gap or 8) end
        self.hasContent = true
        region:SetPoint("TOPLEFT", self, "TOPLEFT", DIALOG_SIDE + (indent or 0), -(DIALOG_TOP + self.contentHeight))
        self.contentHeight = self.contentHeight + height
    end

    -- Wrapped text across the column, never less than one line, so text filled in later keeps its line.
    function dialog:AddText(fontObject, text, gap)
        local line = CreateText(self, fontObject)
        line:SetWidth(self.contentWidth)
        line:SetWordWrap(true)
        line:SetText(text or "")
        local _, lineHeight = fontObject:GetFont()
        local height = math.ceil(math.max(line:GetStringHeight(), lineHeight))
        line:SetHeight(height)
        self:AddField(line, height, gap or SECTION_GAP)
        return line
    end

    -- A 24 px fit-to-text button in the bottom-right corner; later ones chain leftwards 8 apart.
    function dialog:AddButton(label, onClick)
        local button = CreateButton(self, label)
        local previous = self.buttons[#self.buttons]
        if previous then
            button:SetPoint("RIGHT", previous, "LEFT", -8, 0)
        else
            button:SetPoint("BOTTOMRIGHT", -DIALOG_SIDE, DIALOG_SIDE)
        end
        button:SetScript("OnClick", onClick)
        self.buttons[#self.buttons + 1] = button
        return button
    end

    -- 40 top, the content, a section break and the button row if there are buttons, 20 bottom, on the grid.
    function dialog:Fit()
        local height = DIALOG_TOP + self.contentHeight + DIALOG_SIDE
        if #self.buttons > 0 then height = height + SECTION_GAP + 24 end
        self:SetHeight(Snap(height))
    end

    MakeMovable(dialog, name, "DIALOG", position)
    return dialog
end

-- Every icon the macro window's picker offers, as file IDs in its order, each once. Loose icons come as
-- file names without an ID (IconDataProvider.lua), so an ID search cannot match them and they are left out.
local function loadIcons()
    local raw, seen = {}, {}
    GetMacroIcons(raw)
    GetMacroItemIcons(raw)
    allIcons = {}
    for _, icon in ipairs(raw) do
        local id = tonumber(icon)
        if id and not seen[id] then
            seen[id] = true
            allIcons[#allIcons + 1] = id
        end
    end
end

-- The digits to search for: from a pasted Wowhead icon link, else the typed digits. nil for anything else.
local function typedDigits()
    local text = box:GetText()
    return text:match("icon=(%d+)") or text:match("^%s*(%d*)%s*$")
end

-- The icon Okay would set: the grid pick, else the typed or pasted ID.
local function chosenIcon()
    return picked or tonumber(typedDigits() or "")
end

-- The subject line shows the macro's name behind the icon it would get, else behind its current one.
local function refreshSubject()
    local name, current = GetMacroInfo(macroIndex)
    if not name then
        dialog:Hide()
        return
    end
    subject:SetText(CreateSimpleTextureMarkup(chosenIcon() or current, ICON, ICON) .. " " .. name)
end

local function refreshGrid()
    local query = typedDigits()
    wipe(shown)
    if query then
        for _, id in ipairs(allIcons) do
            if query == "" or tostring(id):find(query, 1, true) then
                shown[#shown + 1] = id
            end
        end
    end
    picked = nil
    grid:SetSelectedIndex(nil)
    grid:SetSelectionsArray(shown)

    if not query then
        hint:SetText("Type digits, or paste an icon link from Wowhead.")
    elseif query == "" then
        hint:SetText(("Type part of an icon ID to filter %d icons, or paste an icon ID or Wowhead icon link."):format(#allIcons))
    elseif #shown == 0 then
        hint:SetText("No listed icon matches. Okay still sets this ID.")
    else
        hint:SetText(("%d icons match."):format(#shown))
    end
    refreshSubject()
end

-- Sets a macro's icon and says so when the game refuses it. Returns false only when combat blocks the change,
-- which shows as the game's own red error text, as a refused click does.
local function setIcon(index, id)
    local name = GetMacroInfo(index)
    if not (id and name) then return true end
    if InCombatLockdown() then
        UIErrorsFrame:AddExternalErrorMessage("Macros change only out of combat.")
        return false
    end
    -- The name is passed again on purpose: Forever kept the old icon when it was nil.
    local newIndex = EditMacro(index, name, id)
    local _, icon = GetMacroInfo(newIndex or index)
    if icon ~= id then
        ns.Print(("The game kept the old icon, so %d may not exist on this client."):format(id))
    end
    return true
end

local function apply()
    local id = chosenIcon()
    if not id then return end
    if setIcon(macroIndex, id) then dialog:Hide() end
end

local function fillIconTooltip(tooltip, button)
    GameTooltip_SetTitle(tooltip, ("Icon ID %d"):format(button.iconID))
end

-- The grid is Blizzard's own icon picker grid, ScrollBoxSelectorTemplate with SelectorButtonTemplate.
local function setupButton(button, _, icon)
    button:SetIconTexture(icon)
    button.iconID = icon
    if not button.hasTooltip then
        button.hasTooltip = true
        AttachTooltip(button, fillIconTooltip)
    end
end

local function buildIconDialog()
    dialog = CreateDialog(addonName .. "Dialog", ns.title, 480, MacroFrame)
    subject = dialog:AddText(GameFontNormalLarge, "")
    dialog:AddText(GameFontHighlight, "Icon ID", TIGHT)

    box = CreateSearchBox(dialog, dialog.contentWidth - EDIT_BOX_CAP, addonName .. "SearchBox")
    box.Instructions:SetText("Icon ID or Wowhead icon link")
    box:SetMaxLetters(256)
    dialog:AddField(box, EDIT_BOX_HEIGHT, TIGHT, EDIT_BOX_CAP)

    local padding, spacing = TIGHT, GAP
    grid = CreateIconGrid(dialog, setupButton)
    -- Wide enough for STRIDE buttons plus the template's scroll bar, so no row gap is wasted.
    grid:SetSize(STRIDE * ICON_BUTTON + (STRIDE - 1) * spacing + 2 * padding + SCROLL_GUTTER,
        ROWS * ICON_BUTTON + (ROWS - 1) * spacing + 2 * padding)
    grid:SetCustomStride(STRIDE)
    grid:SetCustomPadding(padding, padding, padding, padding, spacing, spacing)
    grid:SetSelectedCallback(function(_, icon)
        picked = icon
        refreshSubject()
    end)
    dialog:AddField(grid, grid:GetHeight(), GAP)

    hint = dialog:AddText(GameFontDisable, "", TIGHT)
    dialog:AddButton(CANCEL, function() dialog:Hide() end)
    dialog:AddButton(OKAY, apply)
    dialog:Fit()

    -- HookScript keeps SearchBoxTemplate's own handler, which shows its hint text and clear button.
    box:HookScript("OnTextChanged", refreshGrid)
    box:SetScript("OnEnterPressed", apply)
    box:SetScript("OnEscapePressed", function() dialog:Hide() end)
end

local function openIconDialog(index)
    if not GetMacroInfo(index) then return end
    if not allIcons then loadIcons() end
    if not dialog then buildIconDialog() end
    if linkDialog then linkDialog:Hide() end
    macroIndex = index
    -- Opens beside the macro window like Blizzard's own icon picker (MacroPopupFrame, TOPLEFT to TOPRIGHT).
    -- Dragging still moves it; the next open puts it back beside the window.
    dialog:ClearAllPoints()
    dialog:SetPoint("TOPLEFT", MacroFrame, "TOPRIGHT", 0, 0)
    dialog:Show()
    box:SetText("")
    refreshGrid()
    box:SetFocus()
end

-- Player Armory Link's copy dialog: the whole link, always selected; one copy keypress copies it, closes the
-- dialog and confirms in the error frame. Reads top to bottom: what it links to, what to do, the link, then
-- where the icon ID is.
local function buildLinkDialog()
    linkDialog = CreateDialog(addonName .. "LinkDialog", ns.title, 480, MacroFrame, { point = "CENTER", y = 140 })
    linkDialog:AddText(GameFontNormalLarge, "Wowhead Icon Library")
    linkDialog:AddText(GameFontHighlight, "Press " .. COPY_KEY .. "+C to copy the link, then paste it into your browser.", GAP)

    linkBox = CreateEditBox(linkDialog, linkDialog.contentWidth - EDIT_BOX_CAP)
    linkBox:SetScript("OnEscapePressed", function() linkDialog:Hide() end)
    linkBox:SetScript("OnEnterPressed", EditBox_HighlightText)
    -- A click places the cursor and drops the selection, so the whole link is selected again.
    linkBox:SetScript("OnMouseUp", EditBox_HighlightText)
    -- Reverts any edit so the link stays intact and fully selected.
    linkBox:SetScript("OnTextChanged", function(self, userInput)
        if userInput and self:GetText() ~= WOWHEAD_ICONS then
            self:SetText(WOWHEAD_ICONS)
            self:HighlightText()
        end
    end)
    linkBox:SetScript("OnKeyDown", function(self, key)
        if not (key == "C" and copyModifier()) then return end
        -- Selects the whole link before the client copies, so the copy is never empty.
        self:HighlightText()
        C_Timer.After(CLOSE_DELAY, function()
            linkDialog:Hide()
            UIErrorsFrame:AddMessage("Wowhead link copied to clipboard.", GREEN_FONT_COLOR:GetRGB())
        end)
    end)
    linkDialog:AddField(linkBox, EDIT_BOX_HEIGHT, TIGHT, EDIT_BOX_CAP)

    linkDialog:AddText(GameFontDisable, "Open an icon there. Its ID is the number after icon= in the address. "
        .. "Then right-click the macro, pick Set Icon and type the ID or paste the address.", GAP)
    linkDialog:Fit()
end

local function openLinkDialog()
    if not linkDialog then buildLinkDialog() end
    if dialog then dialog:Hide() end
    linkBox:SetText(WOWHEAD_ICONS)
    linkBox:SetCursorPosition(0)
    linkDialog:Show()
    linkBox:SetFocus()
    linkBox:HighlightText()
end

-- The one help tip: Blizzard's yellow callout beside the macro list, pointing left at it from the right, the side
-- with room, since the macro window opens at the left edge of the screen (UIPanelWindows area "left",
-- Blizzard_MacroUI.lua:2). It is an own HelpTipTemplate frame, never HelpTip:Show, which takes a frame from
-- Blizzard's shared pool and taints the help tips Blizzard shows later. Closing it or opening a macro's menu marks
-- it seen for the account, and /emi intro clears that.
local TIP_TEXT = "Right-click a macro here to set, copy or paste its icon."
local retireTip

-- The yellow help tip, plus a third return that hides the tip without marking it seen, for Blizzard's own icon
-- picker, which opens where the tip stands.
local function AttachTip(target, text, targetPoint, relativeRegion)
    local tip
    local info = {
        text = text,
        buttonStyle = HelpTip.ButtonStyle.Close,
        targetPoint = targetPoint,
        onAcknowledgeCallback = function() ns.db.tipSeen = true end,
    }
    local function ShowTip()
        if ns.db.tipSeen or (tip and tip:IsShown()) then return end
        if not tip then
            tip = CreateFrame("Frame", nil, target, "HelpTipTemplate")
            tip.width = HelpTip.width
            tip:SetWidth(tip.width)
        end
        tip:Reset()
        tip:Init(target, info, relativeRegion or target)
        tip:Show()
    end
    target:HookScript("OnShow", ShowTip)
    if target:IsVisible() then ShowTip() end

    -- The player used the feature: the tip goes for good, shown or not.
    local function Retire()
        if tip and tip.info then tip:Acknowledge() else ns.db.tipSeen = true end
    end

    local function HideTip()
        if tip and tip:IsShown() then tip:Hide() end
    end
    return ShowTip, Retire, HideTip
end

-- A menu entry's tooltip, through the menu's own SetTooltip: its label as the title, what it does, and for a
-- disabled entry why, as an error line the way Blizzard's dungeon finder explains its disabled choices.
local function setEntryTooltip(entry, title, text, reason)
    entry:SetTooltip(function(tooltip)
        GameTooltip_SetTitle(tooltip, title)
        GameTooltip_AddNormalLine(tooltip, text)
        if reason then GameTooltip_AddErrorLine(tooltip, reason) end
    end)
end

local function openMenu(button)
    local index = MacroFrame:GetMacroDataIndex(button:GetElementData())
    local name, icon = GetMacroInfo(index)
    if not name then return end
    icon = tonumber(icon)
    -- Opening a macro's menu is the feature the tip points to.
    retireTip()
    MenuUtil.CreateContextMenu(button, function(_, root)
        root:CreateTitle(name)
        local set = root:CreateButton("Set Icon", function() openIconDialog(index) end)
        setEntryTooltip(set, "Set Icon", "Sets this macro's icon by icon ID. Type part of an ID to filter the "
            .. "macro window's icons, or paste any ID or a Wowhead icon link.")
        local copy = root:CreateButton("Copy Icon", function()
            copiedIcon = icon
            UIErrorsFrame:AddMessage(("Icon %d copied."):format(icon), GREEN_FONT_COLOR:GetRGB())
        end)
        copy:SetEnabled(icon ~= nil)
        setEntryTooltip(copy, "Copy Icon", "Keeps this macro's icon for Paste Icon on another macro.",
            not icon and "This macro's icon has no icon ID." or nil)
        -- The entry shows the copied icon and its ID, so it is clear what a paste sets.
        local pasteLabel = copiedIcon
            and ("Paste Icon %s %d"):format(CreateSimpleTextureMarkup(copiedIcon, ICON, ICON), copiedIcon)
            or "Paste Icon"
        local paste = root:CreateButton(pasteLabel, function() setIcon(index, copiedIcon) end)
        paste:SetEnabled(copiedIcon ~= nil and copiedIcon ~= icon)
        setEntryTooltip(paste, "Paste Icon", "Gives this macro the icon you copied with Copy Icon.",
            not copiedIcon and "Copy an icon from a macro first."
            or copiedIcon == icon and "This macro already has that icon." or nil)
        local link = root:CreateButton("Wowhead Link", openLinkDialog)
        setEntryTooltip(link, "Wowhead Link", "Shows the link to Wowhead's WoW Forever icon library, "
            .. "to look up an icon's ID.")
    end)
end

-- Macro buttons only register left clicks, so a right click never selects one. OnMouseUp sees every button.
-- The selector's ScrollBox creates its buttons lazily; its callback runs through secureexecuterange, and
-- HookScript leaves Blizzard's own scripts untouched, so nothing in the macro window is tainted.
local function hookButton(_, button, _, new)
    if not new then return end
    button:HookScript("OnMouseUp", function(self, mouseButton)
        if mouseButton == "RightButton" and self:IsMouseOver() then openMenu(self) end
    end)
end

EventUtil.ContinueOnAddOnLoaded("Blizzard_MacroUI", function()
    local list = MacroFrame.MacroSelector
    list.ScrollBox:RegisterCallback(ScrollBoxListMixin.Event.OnAcquiredFrame, hookButton, ns)
    local showTip, hideTip
    showTip, retireTip, hideTip = AttachTip(list, TIP_TEXT, HelpTip.Point.RightEdgeCenter)
    -- /emi intro brings the tip back at once while the macro window is open, else at its next open.
    function ns.ShowTip()
        if list:IsVisible() then showTip() end
    end
    -- Blizzard's own icon picker (Change Name/Icon) opens where the tip stands, so the tip makes way for it.
    MacroPopupFrame:HookScript("OnShow", hideTip)
end)
