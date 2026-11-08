-- Offline welcome test: lua Tests/Welcome.lua from the repo root.
-- Stubs the client, loads Core.lua as on a fresh account and on a later login, and checks the welcome line and
-- the slash commands.

local realPrint = print
local printed = {}
print = function(line) printed[#printed + 1] = line end

C_AddOns = { GetAddOnMetadata = function(name, key)
    assert(name == "EasyMacroIcons" and key == "Title")
    return "Easy Macro Icons"
end }
NORMAL_FONT_COLOR = { WrapTextInColorCode = function(_, text) return "<gold>" .. text .. "</gold>" end }
strtrim = function(text) return (text:gsub("^%s+", ""):gsub("%s+$", "")) end
SlashCmdList = {}

local onLoaded, onLogin
EventUtil = {
    ContinueOnAddOnLoaded = function(name, fn)
        assert(name == "EasyMacroIcons")
        onLoaded = fn
    end,
    ContinueOnPlayerLogin = function(fn) onLogin = fn end,
}

local PREFIX = "<gold>[Easy Macro Icons]</gold>: "
local WELCOME = PREFIX .. "Sets any macro's icon by icon ID, even icons the macro window does not list. Open the "
    .. "macro window with /macro and right-click a macro to set, copy or paste its icon. "
    .. "Type /emi help for the commands."
local HELP = PREFIX .. "Right-click a macro in the macro window to set, copy or paste its icon. Type /emi intro to "
    .. "see the welcome line and the tip again, or /emi help for this list."

-- Loads the addon with these saved variables, then fires its ADDON_LOADED and PLAYER_LOGIN. Returns the lines
-- printed at load and at login, and the addon table.
local function login(savedVariables)
    EasyMacroIconsDB = savedVariables
    local ns = {}
    assert(loadfile("Core.lua"))("EasyMacroIcons", ns)
    for k in pairs(printed) do printed[k] = nil end
    onLoaded()
    local atLoad = #printed
    onLogin()
    return atLoad, #printed, ns
end

-- The account's first load: nothing at ADDON_LOADED, exactly one welcome line at login.
local atLoad, atLogin, ns = login(nil)
assert(atLoad == 0, "the first load printed")
assert(atLogin == 1 and printed[1] == WELCOME, "welcome line: " .. tostring(printed[1]))
assert(ns.firstRun and EasyMacroIconsDB == ns.db, "first run not marked or saved table not created")

-- A later login or /reload on the same account prints nothing.
atLoad, atLogin = login({})
assert(atLoad == 0 and atLogin == 0, "a later login printed")
atLoad, atLogin, ns = login({ tipSeen = true })
assert(atLoad == 0 and atLogin == 0 and ns.db.tipSeen, "a later login printed or lost the saved state")

-- Both names reach the same handler.
assert(SLASH_EASYMACROICONS1 == "/easymacroicons" and SLASH_EASYMACROICONS2 == "/emi", "slash names")
local function slash(message)
    for k in pairs(printed) do printed[k] = nil end
    SlashCmdList.EASYMACROICONS(message)
    return printed
end

-- Without a window, the bare command, help and ? all print the one help line.
for _, word in ipairs({ "", "help", "?", "  HELP " }) do
    local lines = slash(word)
    assert(#lines == 1 and lines[1] == HELP, ("/emi %s: %s"):format(word, tostring(lines[1])))
end

-- intro prints the welcome line now and brings the tip back.
local lines = slash("intro")
assert(#lines == 1 and lines[1] == WELCOME and ns.db.tipSeen == nil, "intro")

-- Any other word prints the hint and nothing else.
lines = slash("minimap")
assert(#lines == 1 and lines[1] == PREFIX .. "Unknown command. Type /emi help for the list.", "unknown command")

realPrint("Welcome: all checks passed.")
