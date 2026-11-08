-- The addon's title and its one chat helper.
local addonName, ns = ...

ns.title = C_AddOns.GetAddOnMetadata(addonName, "Title")

-- Every chat line reads "[Easy Macro Icons]: Sentence.": the bracketed title in the gold of Blizzard's own chat
-- links (ItemRef.lua), the rest in the chat frame's own colour.
function ns.Print(message)
    print(NORMAL_FONT_COLOR:WrapTextInColorCode("[" .. ns.title .. "]") .. ": " .. message)
end

-- The account's saved state: tipSeen once the macro list tip is closed or a macro's menu opened.
EventUtil.ContinueOnAddOnLoaded(addonName, function()
    EasyMacroIconsDB = EasyMacroIconsDB or {}
    ns.db = EasyMacroIconsDB
end)
