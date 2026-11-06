-- Right-click a macro in Blizzard's macro window for a menu: set its icon from a grid filtered by ID, or copy
-- the link to Wowhead's WoW Forever icon library to look an ID up.
local addonName, ns = ...
local UI = LibStub("LibNativeUI-1.0")

local TITLE = "Easy Macro Icons"
local WOWHEAD_ICONS = "https://www.wowhead.com/forever/icons"
local STRIDE = 9
local ROWS = 5
local ICON = 36   -- SelectorButtonTemplate's size, Blizzard_SelectorUI.xml

-- macOS copies only with Cmd, so Ctrl there must not report a copy.
local COPY_KEY = IsMacClient() and "Cmd" or "Ctrl"
local copyModifier = IsMacClient() and IsMetaKeyDown or IsControlKeyDown

local dialog, subject, box, grid, hint
local linkDialog, linkBox
local macroIndex, picked
local allIcons, shown = nil, {}

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
    subject:SetText(CreateSimpleTextureMarkup(chosenIcon() or current, UI.Size.icon, UI.Size.icon) .. " " .. name)
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

local function apply()
    local id = chosenIcon()
    local name = GetMacroInfo(macroIndex)
    if not (id and name) then return end
    if InCombatLockdown() then
        UI.Print(TITLE, "Macros change only out of combat.")
        return
    end
    -- The name is passed again on purpose: Forever kept the old icon when it was nil.
    local index = EditMacro(macroIndex, name, id)
    local _, icon = GetMacroInfo(index or macroIndex)
    if icon ~= id then
        UI.Print(TITLE, ("The game kept the old icon, so %d may not exist on this client."):format(id))
    end
    dialog:Hide()
end

local function showIconTooltip(button)
    UI.ShowTooltip(button, function(tooltip)
        GameTooltip_SetTitle(tooltip, ("Icon ID %d"):format(button.iconID))
    end)
end

-- The grid is Blizzard's own icon picker grid, ScrollBoxSelectorTemplate with SelectorButtonTemplate.
local function setupButton(button, _, icon)
    button:SetIconTexture(icon)
    button.iconID = icon
    if not button.hasTooltip then
        button.hasTooltip = true
        button:SetScript("OnEnter", showIconTooltip)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
end

local function buildIconDialog()
    dialog = UI.CreateDialog({ name = addonName .. "Dialog", title = TITLE, width = 480, parent = MacroFrame })
    subject = dialog:AddText("title", "")
    dialog:AddText("body", "Icon ID", UI.Space.tight)

    box = UI.CreateSearchBox(dialog, dialog.contentWidth - UI.Native.inputArt, addonName .. "SearchBox")
    box.Instructions:SetText("Icon ID or Wowhead icon link")
    box:SetMaxLetters(256)
    dialog:AddField(box, UI.Native.inputHeight, UI.Space.tight, UI.Native.inputArt)

    local padding, spacing = UI.Space.tight, UI.Space.gap
    grid = CreateFrame("Frame", nil, dialog, "ScrollBoxSelectorTemplate")
    -- Wide enough for STRIDE buttons plus the template's scroll bar, so no row gap is wasted.
    grid:SetSize(STRIDE * ICON + (STRIDE - 1) * spacing + 2 * padding + UI.ScrollGutter(),
        ROWS * ICON + (ROWS - 1) * spacing + 2 * padding)
    grid:SetCustomStride(STRIDE)
    grid:SetCustomPadding(padding, padding, padding, padding, spacing, spacing)
    grid:SetSetupCallback(setupButton)
    grid:SetSelectedCallback(function(_, icon)
        picked = icon
        refreshSubject()
    end)
    dialog:AddField(grid, grid:GetHeight(), UI.Space.gap)

    hint = dialog:AddText("muted", "", UI.Space.tight)
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
    dialog:Show()
    box:SetText("")
    refreshGrid()
    box:SetFocus()
end

-- The link box follows Player Armory Link's copy dialog: always the whole link, selected, and a copy is
-- confirmed in the error frame. It stays open, so Set Icon is one click away after the lookup.
local function buildLinkDialog()
    linkDialog = UI.CreateDialog({ name = addonName .. "LinkDialog", title = TITLE, width = 480, parent = MacroFrame })
    linkDialog:AddText("title", "Wowhead Icon Library")
    linkDialog:AddText("body", "Press " .. COPY_KEY .. "+C to copy the link, then paste it into your browser.", UI.Space.gap)

    linkBox = UI.CreateEditBox(linkDialog, linkDialog.contentWidth - UI.Native.inputArt)
    linkBox:SetScript("OnEscapePressed", function() linkDialog:Hide() end)
    linkBox:SetScript("OnEnterPressed", EditBox_HighlightText)
    linkBox:SetScript("OnMouseUp", EditBox_HighlightText)
    linkBox:SetScript("OnTextChanged", function(self, userInput)
        if userInput and self:GetText() ~= WOWHEAD_ICONS then
            self:SetText(WOWHEAD_ICONS)
            self:HighlightText()
        end
    end)
    linkBox:SetScript("OnKeyDown", function(self, key)
        if key == "C" and copyModifier() then
            -- Selects the whole link before the client copies, so the copy is never empty.
            self:HighlightText()
            UIErrorsFrame:AddMessage("Wowhead link copied to clipboard.", GREEN_FONT_COLOR:GetRGB())
        end
    end)
    linkDialog:AddField(linkBox, UI.Native.inputHeight, UI.Space.tight, UI.Native.inputArt)

    linkDialog:AddSection("Find the Icon ID",
        "Search the library and open an icon. Its ID is the number after icon= in the address, "
        .. "such as 7808148 in wowhead.com/forever/icon=7808148.")
    linkDialog:AddSection("Set the Icon",
        "Click Set Icon, then type the ID or paste the whole icon link. "
        .. "Later, right-click the macro and pick Set Icon.")

    linkDialog:AddButton(CANCEL, function() linkDialog:Hide() end)
    linkDialog:AddButton("Set Icon", function() openIconDialog(linkDialog.macroIndex) end)
    linkDialog:Fit()
end

local function openLinkDialog(index)
    if not linkDialog then buildLinkDialog() end
    if dialog then dialog:Hide() end
    linkDialog.macroIndex = index
    linkBox:SetText(WOWHEAD_ICONS)
    linkBox:SetCursorPosition(0)
    linkDialog:Show()
    linkBox:SetFocus()
    linkBox:HighlightText()
end

local function openMenu(button)
    local index = MacroFrame:GetMacroDataIndex(button:GetElementData())
    local name = GetMacroInfo(index)
    if not name then return end
    MenuUtil.CreateContextMenu(button, function(_, root)
        root:CreateTitle(name)
        root:CreateButton("Set Icon", function() openIconDialog(index) end)
        root:CreateButton("Copy Wowhead Icon Link", function() openLinkDialog(index) end)
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
    MacroFrame.MacroSelector.ScrollBox:RegisterCallback(ScrollBoxListMixin.Event.OnAcquiredFrame, hookButton, ns)
end)
