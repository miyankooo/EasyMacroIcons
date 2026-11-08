-- The addon's title, its one chat helper, its saved state, the welcome line and the slash commands.
local addonName, ns = ...

ns.title = C_AddOns.GetAddOnMetadata(addonName, "Title")

-- Every chat line reads "[Easy Macro Icons]: Sentence.": the bracketed title in the gold of Blizzard's own chat
-- links (ItemRef.lua), the rest in the chat frame's own colour.
function ns.Print(message)
    print(NORMAL_FONT_COLOR:WrapTextInColorCode("[" .. ns.title .. "]") .. ": " .. message)
end

-- The addon has no window or settings page, so the welcome line carries no link: it says what the addon does and
-- where to start.
local WELCOME = "Sets any macro's icon by icon ID, even icons the macro window does not list. Open the macro window "
    .. "with /macro and right-click a macro to set, copy or paste its icon. Type /emi help for every command."

local HELP = "Right-click a macro in the macro window to set, copy or paste its icon. Type /emi intro to see the "
    .. "welcome line and the tip again, or /emi help for this list."

-- The account's saved state: tipSeen once the macro list tip is closed or a macro's menu opened. An absent table
-- marks the account's first load with the addon.
EventUtil.ContinueOnAddOnLoaded(addonName, function()
    ns.firstRun = EasyMacroIconsDB == nil
    EasyMacroIconsDB = EasyMacroIconsDB or {}
    ns.db = EasyMacroIconsDB
end)

-- The welcome line waits for login, so it lands after the client's own load lines.
EventUtil.ContinueOnPlayerLogin(function()
    if ns.firstRun then ns.Print(WELCOME) end
end)

-- /emi intro: the welcome line now, and the macro list tip again the next time the macro window opens.
function ns.ReplayIntro()
    ns.db.tipSeen = nil
    ns.Print(WELCOME)
end

-- One long command and one short alias. Without a window or settings page to open, the bare command prints the
-- help line; intro replays the onboarding, and any other word prints the hint.
SLASH_EASYMACROICONS1, SLASH_EASYMACROICONS2 = "/easymacroicons", "/emi"
SlashCmdList.EASYMACROICONS = function(message)
    local command = strtrim(message or ""):lower()
    if command == "" or command == "help" or command == "?" then
        ns.Print(HELP)
    elseif command == "intro" then
        ns.ReplayIntro()
    else
        ns.Print("Unknown command. Type /emi help for the list.")
    end
end
