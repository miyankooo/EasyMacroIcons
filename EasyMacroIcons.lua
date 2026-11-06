-- Right-click a macro in Blizzard's macro window to set its icon by file ID, picked from a grid filtered by ID.
local _, ns = ...
local UI = LibStub("LibNativeUI-1.0")

local TITLE = "Easy Macro Icons"
local STRIDE = 9
local ROWS = 5
local ICON = 36   -- SelectorButtonTemplate's size, Blizzard_SelectorUI.xml

local dialog, subject, box, grid, hint
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

-- The icon Okay would set: the grid pick, else the typed ID.
local function chosenIcon()
    return picked or tonumber(box:GetText())
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
    local query = box:GetText()
    wipe(shown)
    for _, id in ipairs(allIcons) do
        if query == "" or tostring(id):find(query, 1, true) then
            shown[#shown + 1] = id
        end
    end
    picked = nil
    grid:SetSelectedIndex(nil)
    grid:SetSelectionsArray(shown)

    if query == "" then
        hint:SetText(("Type part of an icon ID to filter %d icons."):format(#allIcons))
    elseif #shown == 0 then
        hint:SetText("No listed icon matches. Okay still sets the typed ID.")
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

local function build()
    dialog = UI.CreateDialog({ name = "EasyMacroIconsDialog", title = TITLE, width = 480, parent = MacroFrame })
    subject = dialog:AddText("title", "")
    dialog:AddText("body", "Icon ID", UI.Space.tight)

    box = UI.CreateSearchBox(dialog, UI.Size.input, "EasyMacroIconsSearchBox")
    box:SetNumeric(true)
    box:SetMaxLetters(10)
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

local function open(button)
    local index = MacroFrame:GetMacroDataIndex(button:GetElementData())
    if not GetMacroInfo(index) then return end
    if not allIcons then loadIcons() end
    if not dialog then build() end
    macroIndex = index
    dialog:Show()
    box:SetText("")
    refreshGrid()
    box:SetFocus()
end

-- Macro buttons only register left clicks, so a right click never selects one. OnMouseUp sees every button.
-- The selector's ScrollBox creates its buttons lazily; its callback runs through secureexecuterange, and
-- HookScript leaves Blizzard's own scripts untouched, so nothing in the macro window is tainted.
local function hookButton(_, button, _, new)
    if not new then return end
    button:HookScript("OnMouseUp", function(self, mouseButton)
        if mouseButton == "RightButton" and self:IsMouseOver() then open(self) end
    end)
end

EventUtil.ContinueOnAddOnLoaded("Blizzard_MacroUI", function()
    MacroFrame.MacroSelector.ScrollBox:RegisterCallback(ScrollBoxListMixin.Event.OnAcquiredFrame, hookButton, ns)
end)
