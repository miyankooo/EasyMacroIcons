-- Right-click a macro in Blizzard's macro window to set its icon by file ID.
local _, ns = ...
local UI = LibStub("LibNativeUI-1.0")

local TITLE = "Easy Macro Icons"

local dialog, subject, box
local macroIndex

-- The subject line shows the macro's name behind the icon it would get: the typed ID, else the current one.
local function refreshSubject()
    local name, current = GetMacroInfo(macroIndex)
    if not name then
        dialog:Hide()
        return
    end
    local icon = tonumber(box:GetText()) or current
    subject:SetText(CreateSimpleTextureMarkup(icon, UI.Size.icon, UI.Size.icon) .. " " .. name)
end

local function apply()
    local id = tonumber(box:GetText())
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

local function build()
    dialog = UI.CreateDialog({ name = "EasyMacroIconsDialog", title = TITLE, width = 400, parent = MacroFrame })
    subject = dialog:AddText("title", "")
    dialog:AddText("body", "Icon ID", UI.Space.tight)
    box = UI.CreateEditBox(dialog, UI.Size.input)
    box:SetNumeric(true)
    box:SetMaxLetters(10)
    dialog:AddField(box, UI.Native.inputHeight, UI.Space.gap, UI.Native.inputArt)
    dialog:AddText("muted", "Find icon IDs on Wowhead's WoW Forever icon pages.", UI.Space.tight)
    dialog:AddButton(CANCEL, function() dialog:Hide() end)
    dialog:AddButton(OKAY, apply)
    dialog:Fit()

    box:SetScript("OnTextChanged", refreshSubject)
    box:SetScript("OnEnterPressed", apply)
    box:SetScript("OnEscapePressed", function() dialog:Hide() end)
end

local function open(button)
    local index = MacroFrame:GetMacroDataIndex(button:GetElementData())
    if not GetMacroInfo(index) then return end
    if not dialog then build() end
    macroIndex = index
    box:SetText("")
    refreshSubject()
    dialog:Show()
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
