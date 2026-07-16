local testDirectory = ""
if debug ~= nil and debug.getinfo ~= nil then
    local source = debug.getinfo(1, "S").source
    local testFile = source:sub(1, 1) == "@" and source:sub(2) or source
    testDirectory = testFile:match("^(.*[/\\])") or ""
end

local function loadFirst(candidates)
    for _, candidate in ipairs(candidates) do
        local ok, loaded = pcall(dofile, candidate)
        if ok then return loaded, candidate end
    end
    return nil, nil
end

local corePathCandidates = {
    "Lua/WardrobeCore.lua",
    testDirectory .. "../WardrobeCore.lua",
    "../WardrobeCore.lua",
    "WardrobeCore.lua"
}
local loadedCore = loadFirst(corePathCandidates)
WardrobeCore = assert(loadedCore, "could not load Lua/WardrobeCore.lua")

local clientPathCandidates = {
    "Lua/WardrobeSwitcher.lua",
    testDirectory .. "../WardrobeSwitcher.lua",
    "../WardrobeSwitcher.lua",
    "WardrobeSwitcher.lua"
}
local clientPath = nil
for _, candidate in ipairs(clientPathCandidates) do
    local file = io.open(candidate, "r")
    if file ~= nil then
        file:close()
        clientPath = candidate
        break
    end
end
assert(clientPath ~= nil, "could not locate Lua/WardrobeSwitcher.lua")
SERVER = false
CLIENT = true
InvSlotType = {
    Head = "Head",
    Headset = "Headset",
    InnerClothes = "InnerClothes",
    OuterClothes = "OuterClothes",
    Bag = "Bag",
    HealthInterface = "HealthInterface"
}

local messages = {}
local originalPrint = print
print = function(...)
    local values = {}
    for index = 1, select("#", ...) do
        values[#values + 1] = tostring(select(index, ...))
    end
    messages[#messages + 1] = table.concat(values, " ")
end

local loadCalls = 0
local saveCalls = 0
local lastSaved = nil
local persistence = {
    GetVersion = function() return WardrobeCore.MOD_VERSION end,
    GetLastError = function() return "" end,
    GetClientLookPath = function() return "sessionless/ClientLook.json" end,
    ClientLookFileExists = function() return true end,
    LoadClientLook = function()
        loadCalls = loadCalls + 1
        return "captured=true|active=false|auto=false|hidehair=false|Head=helmet,"
    end,
    SaveClientLook = function(encoded)
        saveCalls = saveCalls + 1
        lastSaved = tostring(encoded)
        return true
    end,
    ClearClientLook = function() return true end
}

local activationCount = 0
local prefabCaptureCount = 0
local reuseCheckCount = 0
local reusableCharacters = {}
local transactionCharacter = nil
local function characterId(character)
    return character ~= nil and tonumber(character.ID) or nil
end
local visualOverride = {
    GetVersion = function() return WardrobeCore.MOD_VERSION end,
    IsReady = function() return true end,
    GetReadinessStatus = function()
        return "ready; capabilities(renderer=True,animation=True,statusSound=True,itemSound=True)"
    end,
    GetCharacterDebugStatus = function() return "test" end,
    BeginFashionTransaction = function(character)
        transactionCharacter = character
        return true
    end,
    AbortFashionTransaction = function()
        transactionCharacter = nil
        return true
    end,
    CommitFashionTransaction = function()
        local id = characterId(transactionCharacter)
        if id ~= nil then reusableCharacters[id] = true end
        transactionCharacter = nil
        return true
    end,
    CanReuseCapturedFashion = function(character)
        reuseCheckCount = reuseCheckCount + 1
        return reusableCharacters[characterId(character)] == true
    end,
    CaptureFashionPrefab = function()
        prefabCaptureCount = prefabCaptureCount + 1
        return 1
    end,
    CaptureEmptyFashion = function() return true end,
    SetFashionSlots = function() return true end,
    SetHideHair = function() return true end,
    ActivateFashionVisual = function()
        activationCount = activationCount + 1
        return true
    end,
    ClearCharacter = function(character)
        local id = characterId(character)
        if id ~= nil then reusableCharacters[id] = nil end
        return true
    end,
    ClearAll = function()
        reusableCharacters = {}
        transactionCharacter = nil
        return true
    end,
    RestoreCharacterItemVisuals = function() return true end,
    RestoreItemVisuals = function() return true end,
    PruneStaleCharacters = function() return true end
}

local function vector(x, y)
    return { X = x, Y = y }
end

LuaUserData = {
    CreateStatic = function(name)
        if name == "BaroWardrobeSwitcher.WardrobePersistence" then return persistence end
        if name == "BaroWardrobeSwitcher.VisualOverride" then return visualOverride end
        if name == "Microsoft.Xna.Framework.Vector2" then return vector end
        if name == "Microsoft.Xna.Framework.Color" then
            return { White = {}, Cyan = {} }
        end
        return nil
    end,
    CreateEnumTable = function() return {} end,
    RegisterType = function() return true end
}

local hooks = {}
Hook = {
    Add = function(name, _, callback)
        hooks[name] = callback
    end
}
Networking = {
    Receive = function() end
}
Character = { Controlled = nil }
ChatMessageType = {
    ServerMessageBoxInGame = "ServerMessageBoxInGame",
    MessageBox = "MessageBox"
}
Keys = { F8 = "F8" }
local openPanel = false
PlayerInput = {
    KeyHit = function()
        local result = openPanel
        openPanel = false
        return result
    end
}

local buttons = {}
local function widget()
    return {
        RectTransform = {},
        Remove = function() end,
        AddToGUIUpdateList = function() end
    }
end
GUI = {
    Anchor = { Center = "Center" },
    RectTransform = function() return {} end,
    Frame = function() return widget() end,
    LayoutGroup = function() return widget() end,
    TextBlock = function()
        return widget()
    end,
    Button = function(_, text)
        local button = widget()
        button.Enabled = true
        buttons[tostring(text)] = button
        return button
    end
}

assert(dofile(clientPath) == nil)
assert(loadCalls == 1, "client persistence was not loaded without a game session key")

local restored = false
for _, message in ipairs(messages) do
    if message:find("Loaded persistent client wardrobe look from C# persistence.", 1, true) then
        restored = true
        break
    end
end
assert(restored, "portable client look was rejected when no game session key was available")

Character.Controlled = {
    ID = 42,
    Name = "Sessionless Tester",
    Inventory = {
        GetItemInLimbSlot = function() return nil end
    }
}
openPanel = true
assert(type(hooks.think) == "function", "client think hook was not registered")
hooks.think()

local hideHairButton = buttons["Hide Hair"]
assert(hideHairButton ~= nil and hideHairButton.Enabled ~= false,
    "Hide Hair should be enabled when a saved look exists")
assert(type(hideHairButton.OnClicked) == "function", "Hide Hair callback was not installed")
hideHairButton.OnClicked()

assert(saveCalls == 1, "Hide Hair did not persist in a sessionless game mode")
assert(lastSaved ~= nil and lastSaved:find("hidehair=true", 1, true) ~= nil,
    "Hide Hair persistence did not store the updated intent")

local applyButton = buttons["Apply Saved Look"]
assert(applyButton ~= nil and type(applyButton.OnClicked) == "function",
    "Apply Saved Look callback was not installed")
local clearButton = buttons["Clear Look"]
assert(clearButton ~= nil and type(clearButton.OnClicked) == "function",
    "Clear Look callback was not installed")

assert(type(hooks.roundEnd) == "function", "roundEnd hook was not registered")
hooks.roundEnd()
Character.Controlled = nil
hooks.think()
Character.Controlled = {
    ID = 43,
    Name = "Replacement Tester",
    Inventory = {
        GetItemInLimbSlot = function() return nil end
    }
}
hooks.think()
assert(activationCount == 0,
    "a saved but inactive look was incorrectly applied to the replacement character")

-- Simulate the atomically committed session produced by a successful local save.
-- The first apply and a clear/reapply on the same character must use that exact
-- renderer session without rebuilding from the active prefab.
reusableCharacters[43] = true
applyButton.OnClicked()
assert(activationCount == 1, "manual apply did not activate the renderer")
assert(prefabCaptureCount == 0,
    "same-character apply rebuilt the look instead of reusing the committed renderer session")

clearButton.OnClicked()
applyButton.OnClicked()
assert(activationCount == 2, "clear/reapply did not reactivate the renderer")
assert(prefabCaptureCount == 0,
    "clear/reapply discarded the reusable renderer session and rebuilt from the prefab")

hooks.roundEnd()
Character.Controlled = nil
hooks.think()
Character.Controlled = {
    ID = 44,
    Name = "Active Replacement Tester",
    Inventory = {
        GetItemInLimbSlot = function() return nil end
    }
}
hooks.think()
assert(activationCount == 3,
    "an active look was not reapplied exactly once to the replacement character")
assert(prefabCaptureCount == 1,
    "a replacement character incorrectly reused the previous character's renderer session")
assert(reuseCheckCount >= 3,
    "local render effects did not query renderer-session reuse before choosing prefab capture")

clearButton.OnClicked()
hooks.roundEnd()
Character.Controlled = nil
hooks.think()
Character.Controlled = {
    ID = 45,
    Name = "Cleared Replacement Tester",
    Inventory = {
        GetItemInLimbSlot = function() return nil end
    }
}
hooks.think()
assert(activationCount == 3,
    "a manually cleared look was incorrectly reapplied to the replacement character")

print = originalPrint
print("Wardrobe client facade tests passed")
