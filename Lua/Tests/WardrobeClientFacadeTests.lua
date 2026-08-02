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
local clientSourceFile = assert(io.open(clientPath, "r"))
local clientSource = clientSourceFile:read("*a")
clientSourceFile:close()
for _, forbidden in ipairs({
    "local savedLook =", "local savedLookCaptured =", "local activeLook =",
    "local autoApplyLook =", "local hideHair =", "local attachmentVisibility =",
    "applyReducerProjection"
}) do
    assert(not clientSource:find(forbidden, 1, true), "facade state mirror returned: " .. forbidden)
end
local captureStart = assert(clientSource:find(
    "function Helpers.captureFashionPayloadFromLook",
    1,
    true
))
local captureEnd = assert(clientSource:find(
    "function Helpers.applyCapturedFashionToCharacterEquipment",
    captureStart,
    true
))
local captureSource = clientSource:sub(captureStart, captureEnd - 1)
assert(captureSource:find("savedColor == nil", 1, true) ~= nil,
    "a colorless saved look could incorrectly reuse a live item")
assert(captureSource:find("Helpers.findItemByIdentifier(character", 1, true) == nil,
    "saved-look capture must not select the first matching inventory prefab")
assert(captureSource:find('.. "@" .. tostring(color or "base")', 1, true) ~= nil,
    "prefab fallback dedupe must include the packed color")
assert(clientSource:find("color = Helpers.itemSpriteColor(item)", 1, true) ~= nil,
    "client visual snapshots must capture Item.SpriteColor.PackedValue")

local equipmentRefreshStart = assert(clientSource:find(
    "function Helpers.refreshActiveLookIfNeeded",
    1,
    true
))
local equipmentRefreshEnd = assert(clientSource:find(
    "function Helpers.autoApplySavedLookIfNeeded",
    equipmentRefreshStart,
    true
))
local equipmentRefreshSource = clientSource:sub(equipmentRefreshStart, equipmentRefreshEnd - 1)
assert(equipmentRefreshSource:find("Helpers.applyCapturedFashionToCharacterEquipment", 1, true) ~= nil and
       equipmentRefreshSource:find("lastEquipmentSignature = signature", 1, true) ~= nil,
    "equipment changes must refresh the existing renderer session locally")
assert(equipmentRefreshSource:find("applyFashionToCurrentEquipment", 1, true) == nil and
       equipmentRefreshSource:find("dispatchReducer", 1, true) == nil,
    "equipment-only refresh must not persist or send a wardrobe Apply command")

local equipmentApplyStart = assert(clientSource:find(
    "function Helpers.applyCapturedFashionToCharacterEquipment",
    1,
    true
))
local equipmentApplyEnd = assert(clientSource:find(
    "function Helpers.applyNetworkLook",
    equipmentApplyStart,
    true
))
local equipmentApplySource = clientSource:sub(equipmentApplyStart, equipmentApplyEnd - 1)
assert(equipmentApplySource:find("local seenEquippedItems = {}", 1, true) ~= nil and
       equipmentApplySource:find("local seenEquippedItemIds = {}", 1, true) ~= nil and
       equipmentApplySource:find("seenEquippedItemIds[equippedId]", 1, true) ~= nil,
    "a multi-slot item must be registered once even when LuaCs returns distinct proxies")
assert(clientSource:find("Helpers.removeVisualOverrideFromItem(character, item)", 1, true) ~= nil and
       clientSource:find("VisualOverride.RemoveFashionItemVisual(character, item)", 1, true) ~= nil,
    "unequipped observer items must release their sound and animation suppression references")
assert(clientSource:find("Helpers.isManagedEquippedItem(character, item)", 1, true) ~= nil,
    "observer equipment registration must be limited to the six managed clothing slots")
assert(clientSource:find("bridge.GetPanelKeyName()", 1, true) ~= nil and
       clientSource:find("return PlayerInput.KeyHit(key)", 1, true) ~= nil and
       clientSource:find('if key == nil then return "F8", Keys.F8 end', 1, true) ~= nil and
       clientSource:find('panelKeyText("notice.open_panel")', 1, true) ~= nil,
    "the configurable panel key must drive both input and the round-start notice")
assert(clientSource:find("local CONFIG", 1, true) == nil,
    "the obsolete source-edited panel key config must not shadow Mod Gameplay Settings")
assert(clientSource:find("function Helpers.singlePlayerSelectableCharacters()", 1, true) ~= nil and
       clientSource:find('Helpers.userDataMember(character, "IsBot") == true', 1, true) ~= nil and
       clientSource:find("NET_V2_TARGET_COMMAND", 1, true) ~= nil and
       clientSource:find("serverSupportsCrewTargeting()", 1, true) ~= nil and
       clientSource:find('tr("button.next_page")', 1, true) ~= nil and
       clientSource:find("GUI.ListBox(", 1, true) ~= nil and
       clientSource:find("(tutorialExpanded and 0.58 or 0.46)", 1, true) ~= nil,
    "the compact scrollable two-page panel and bot-only wardrobe target selector are missing")

local settingsFile = nil
for _, candidate in ipairs({
    "Config/SettingsClient.xml",
    testDirectory .. "../../Config/SettingsClient.xml",
    "../../Config/SettingsClient.xml"
}) do
    settingsFile = io.open(candidate, "r")
    if settingsFile ~= nil then break end
end
local settingsXml = assert(settingsFile, "could not load Config/SettingsClient.xml"):read("*a")
settingsFile:close()
assert(settingsXml:find("<Settings>", 1, true) ~= nil and
       settingsXml:find('Name="PanelKey" Type="string" Value="F8"', 1, true) ~= nil,
    "the Mod Gameplay Settings panel key must default to F8")

local localizedText = {}
local textFile = nil
for _, candidate in ipairs({ "Texts.xml", testDirectory .. "../../Texts.xml", "../../Texts.xml" }) do
    textFile = io.open(candidate, "r")
    if textFile ~= nil then break end
end
local textXml = assert(textFile, "could not load Texts.xml"):read("*a")
textFile:close()
for tag, value in textXml:gmatch("<([^>]+)>([^<]*)</[^>]+>") do
    if tag:find("barowardrobeswitcher.", 1, true) == 1 then
        localizedText[tag] = value:gsub("&#10;", "\n")
    end
end
TextManager = {
    ContainsTag = function(tag) return localizedText[tostring(tag)] ~= nil end,
    Get = function(tag) return localizedText[tostring(tag)] end
}
assert(TextManager.ContainsTag("barowardrobeswitcher.button.save"))
assert(TextManager.ContainsTag("barowardrobeswitcher.button.animation_fashion"))
assert(TextManager.ContainsTag("barowardrobeswitcher.button.animation_equipment"))
assert(TextManager.ContainsTag("barowardrobeswitcher.button.next_page"))
assert(TextManager.ContainsTag("barowardrobeswitcher.panel.target_character"))
assert(not TextManager.ContainsTag("barowardrobeswitcher.button.hide_hair"))
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
local loggedMessages = {}
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
local lastSavedProfileKey = nil
local transferEnabled = false
local importedCampaigns = {}
local profiles = {}
local function profileStorageKey(campaignKey, characterKey)
    return tostring(campaignKey) .. "\n" .. tostring(characterKey)
end
local campaignStorageKey = "campaign:campaign-a.save"
local function stableCharacterProfileKey(name)
    return tostring(#name) .. ":" .. name .. "|5:human|0:|0:"
end
local persistence = {
    GetVersion = function() return WardrobeCore.MOD_VERSION end,
    GetLastError = function() return "" end,
    GetClientLookPath = function() return "sessionless/ClientLook.json" end,
    GetSinglePlayerProfilesPath = function() return "campaign/SinglePlayerProfiles.json" end,
    GetSinglePlayerTransferEnabled = function() return transferEnabled end,
    SetSinglePlayerTransferEnabled = function(enabled)
        transferEnabled = enabled == true
        return true
    end,
    TryImportLegacyClientLook = function(campaignKey, characterKey)
        if importedCampaigns[campaignKey] then return false end
        importedCampaigns[campaignKey] = true
        profiles[profileStorageKey(campaignKey, characterKey)] =
            "captured=true|active=false|auto=false|hidehair=false|Head=helmet,"
        return true
    end,
    LoadSinglePlayerProfile = function(campaignKey, characterKey)
        loadCalls = loadCalls + 1
        return profiles[profileStorageKey(campaignKey, characterKey)] or ""
    end,
    SaveSinglePlayerProfile = function(campaignKey, characterKey, _, encoded)
        saveCalls = saveCalls + 1
        lastSaved = tostring(encoded)
        lastSavedProfileKey = tostring(characterKey)
        profiles[profileStorageKey(campaignKey, characterKey)] = tostring(encoded)
        return true
    end,
    DeleteSinglePlayerProfile = function(campaignKey, characterKey)
        profiles[profileStorageKey(campaignKey, characterKey)] = nil
        return true
    end,
    ClientLookFileExists = function() return true end,
    LoadClientLook = function()
        return "captured=true|active=false|auto=false|hidehair=false|Head=helmet,"
    end,
    SaveClientLook = function(encoded)
        saveCalls = saveCalls + 1
        lastSaved = tostring(encoded)
        return true
    end,
    ClearClientLook = function() return true end
}
local fileLogger = {
    GetPath = function() return "sessionless/WardrobeClient.log" end,
    Write = function(level, message)
        loggedMessages[#loggedMessages + 1] = tostring(level) .. ":" .. tostring(message)
        return true
    end
}

local activationCount = 0
local activationAttempts = 0
local activationFailuresRemaining = 0
local clearAttempts = 0
local clearFailuresRemaining = 0
local visualOverrideReady = true
local configuredPanelKey = "F7"
local attachmentVisibilityCalls = 0
local lastForceHideMask = nil
local lastForceShowMask = nil
local movementAnimationCalls = 0
local lastUseFashionMovementAnimations = nil
local movementAnimationByCharacterId = {}
local activationCharacterIds = {}
local activeCharacterIds = {}
local capturedIdentifierByCharacterId = {}
local capturedPrefabKeysByCharacterId = {}
local lastEmptyCaptureCharacterId = nil
local prefabCaptureCount = 0
local reuseCheckCount = 0
local fashionSlotCalls = 0
local equipmentRegistrationCalls = 0
local equipmentRemovalCalls = 0
local reusableCharacters = {}
local transactionCharacter = nil
local function characterId(character)
    return character ~= nil and tonumber(character.ID) or nil
end
local visualOverride = {
    GetVersion = function() return WardrobeCore.MOD_VERSION end,
    GetPanelKeyName = function() return configuredPanelKey end,
    IsReady = function() return visualOverrideReady end,
    GetReadinessStatus = function()
        return visualOverrideReady and
            "ready; capabilities(renderer=True,animation=True,statusSound=True,itemSound=True)" or
            "loading"
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
    CaptureFashionPrefab = function(character, identifier, packedColor)
        prefabCaptureCount = prefabCaptureCount + 1
        capturedIdentifierByCharacterId[characterId(character)] = tostring(identifier)
        local id = characterId(character)
        capturedPrefabKeysByCharacterId[id] = capturedPrefabKeysByCharacterId[id] or {}
        capturedPrefabKeysByCharacterId[id][#capturedPrefabKeysByCharacterId[id] + 1] =
            tostring(identifier) .. "@" .. tostring(packedColor or "base")
        return 1
    end,
    CaptureEmptyFashion = function(character)
        lastEmptyCaptureCharacterId = characterId(character)
        return true
    end,
    SetFashionSlots = function()
        fashionSlotCalls = fashionSlotCalls + 1
        return true
    end,
    SetAttachmentVisibility = function(_, forceHideMask, forceShowMask)
        attachmentVisibilityCalls = attachmentVisibilityCalls + 1
        lastForceHideMask = forceHideMask
        lastForceShowMask = forceShowMask
        return true
    end,
    SetUseFashionMovementAnimations = function(character, enabled)
        movementAnimationCalls = movementAnimationCalls + 1
        lastUseFashionMovementAnimations = enabled == true
        movementAnimationByCharacterId[characterId(character)] = enabled == true
        return true
    end,
    ApplyFashionItemVisual = function()
        equipmentRegistrationCalls = equipmentRegistrationCalls + 1
        return true
    end,
    RemoveFashionItemVisual = function()
        equipmentRemovalCalls = equipmentRemovalCalls + 1
        return true
    end,
    ActivateFashionVisual = function(character)
        activationAttempts = activationAttempts + 1
        if activationFailuresRemaining > 0 then
            activationFailuresRemaining = activationFailuresRemaining - 1
            return false
        end
        activationCount = activationCount + 1
        local id = characterId(character)
        activationCharacterIds[#activationCharacterIds + 1] = id
        activeCharacterIds[id] = true
        return true
    end,
    ClearCharacter = function(character)
        clearAttempts = clearAttempts + 1
        if clearFailuresRemaining > 0 then
            clearFailuresRemaining = clearFailuresRemaining - 1
            error("synthetic clear failure")
        end
        local id = characterId(character)
        if id ~= nil then
            reusableCharacters[id] = nil
            activeCharacterIds[id] = nil
        end
        return true
    end,
    ClearAll = function()
        reusableCharacters = {}
        activeCharacterIds = {}
        transactionCharacter = nil
        return true
    end,
    RestoreCharacterItemVisuals = function(character)
        activeCharacterIds[characterId(character)] = nil
        return true
    end,
    RestoreItemVisuals = function(character)
        activeCharacterIds[characterId(character)] = nil
        return true
    end,
    PruneStaleCharacters = function() return true end
}

local gameSessionDataPath = { SavePath = "campaign-a.save" }
local gameMain = {
    GameSession = {
        DataPath = gameSessionDataPath,
        IsRunning = true,
        RoundEnding = false
    }
}
local function vector(x, y)
    return { X = x, Y = y }
end

LuaUserData = {
    CreateStatic = function(name)
        if name == "Barotrauma.TextManager" then return TextManager end
        if name == "BaroWardrobeSwitcher.WardrobePersistence" then return persistence end
        if name == "BaroWardrobeSwitcher.WardrobeFileLogger" then return fileLogger end
        if name == "BaroWardrobeSwitcher.VisualOverride" then return visualOverride end
        if name == "Barotrauma.Entity" then
            return {
                FindEntityByID = function(id)
                    for _, character in ipairs(Character.CharacterList or {}) do
                        if tonumber(character.ID) == tonumber(id) then return character end
                    end
                    return nil
                end
            }
        end
        if name == "Barotrauma.GameMain" then
            return gameMain
        end
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
local networkHandlers = {}
local networkSent = {}
local newNetworkBuffer = assert(loadFirst({
    "Lua/Tests/TestBuffer.lua",
    testDirectory .. "TestBuffer.lua",
    "TestBuffer.lua"
}))

Networking = {
    Receive = function(name, handler) networkHandlers[name] = handler end,
    Start = function(name) return newNetworkBuffer(name) end,
    Send = function(message)
        message.FinalizeForTransport()
        networkSent[#networkSent + 1] = message
    end
}
Game = { IsMultiplayer = false }
local testTime = 0
Timer = { GetTime = function() return testTime end }
Character = { Controlled = nil, CharacterList = {} }
ChatMessageType = {
    ServerMessageBoxInGame = "ServerMessageBoxInGame",
    MessageBox = "MessageBox"
}
Keys = { F7 = "F7", F8 = "F8" }
local openPanel = false
local lastPanelKey = nil
PlayerInput = {
    KeyHit = function(key)
        lastPanelKey = key
        local result = openPanel
        openPanel = false
        return result
    end
}

local buttons = {}
local visibleButtons = {}
local removedWidgets = 0
local liveOverlayRoots = 0
local visibleTexts = {}
local function widget(onRemove)
    local removed = false
    local result = {
        RectTransform = {},
        AddToGUIUpdateList = function() end
    }
    if onRemove ~= nil then
        result.RemoveFromGUIUpdateList = function(alsoChildren)
            assert(alsoChildren == true, "overlay removal must include child controls")
            if removed then return end
            removed = true
            removedWidgets = removedWidgets + 1
            onRemove()
        end
    end
    return result
end
GUI = {
    Anchor = { Center = "Center" },
    RectTransform = function() return {} end,
    Frame = function(_, style)
        if style == nil then
            visibleTexts = {}
            visibleButtons = {}
            liveOverlayRoots = liveOverlayRoots + 1
            return widget(function()
                liveOverlayRoots = liveOverlayRoots - 1
                visibleTexts = {}
                visibleButtons = {}
            end)
        end
        return widget()
    end,
    LayoutGroup = function() return widget() end,
    ListBox = function()
        return { Content = widget() }
    end,
    TextBlock = function(_, text)
        visibleTexts[#visibleTexts + 1] = tostring(text)
        return widget()
    end,
    Button = function(_, text)
        local button = widget()
        button.Enabled = true
        buttons[tostring(text)] = button
        visibleButtons[tostring(text)] = true
        return button
    end
}

local function makeCharacter(entityId, infoId, name, isBot)
    return {
        ID = entityId,
        Name = name,
        IsHuman = true,
        IsOnPlayerTeam = true,
        IsBot = isBot == true,
        Info = {
            ID = infoId,
            Name = name,
            OriginalName = name,
            SpeciesName = "human",
            HumanPrefabIds = { Item1 = "", Item2 = "" }
        },
        Inventory = {
            GetItemInLimbSlot = function() return nil end
        }
    }
end

profiles[profileStorageKey(campaignStorageKey, stableCharacterProfileKey("Existing NPC"))] =
    "captured=true|active=false|auto=false|hidehair=false|fashionMovement=false|Head=existinghelmet,"
profiles[profileStorageKey(campaignStorageKey, stableCharacterProfileKey("A Target NPC"))] =
    "captured=true|active=false|auto=false|hidehair=false|fashionMovement=true|Head=targethelmet,"
profiles[profileStorageKey(campaignStorageKey, stableCharacterProfileKey("Twin NPC"))] =
    "captured=true|active=false|auto=true|hidehair=false|Head=twinhelmet,"
profiles[profileStorageKey(campaignStorageKey, stableCharacterProfileKey("No Stable ID"))] =
    "captured=true|active=false|auto=true|hidehair=false|Head=unstablehelmet,"

assert(dofile(clientPath) == nil)
assert(loadCalls == 0, "single-player profiles should load only after a campaign character exists")

local function hasVisibleText(expected)
    for _, text in ipairs(visibleTexts) do
        if text == expected then return true end
    end
    return false
end

local function hasVisibleButton(expected)
    return visibleButtons[expected] == true
end

local function hasLoggedText(expected)
    for _, text in ipairs(loggedMessages) do
        if text:find(expected, 1, true) ~= nil then return true end
    end
    return false
end

local player = makeCharacter(42, 100, "Player Tester", false)
local npc = makeCharacter(43, 200, "NPC Tester", true)
local existingNpc = makeCharacter(44, 300, "Existing NPC", true)
local selectorNpc = makeCharacter(50, 900, "A Target NPC", true)
local otherPlayer = makeCharacter(45, 400, "Other Player", false)
local enemyBot = makeCharacter(46, 500, "Enemy Bot", true)
enemyBot.IsOnPlayerTeam = false
local nonHumanBot = makeCharacter(47, 600, "Nonhuman Bot", true)
nonHumanBot.IsHuman = false
local removedBot = makeCharacter(48, 700, "Removed Bot", true)
removedBot.Removed = true
local deadBot = makeCharacter(49, 800, "Dead Bot", true)
deadBot.IsDead = true
Character.CharacterList = {
    player, npc, existingNpc, selectorNpc, otherPlayer, enemyBot, nonHumanBot, removedBot, deadBot
}
Character.Controlled = player
openPanel = true
assert(type(hooks.think) == "function", "client think hook was not registered")
hooks.think()
assert(lastPanelKey == Keys.F7, "the Mod Gameplay Settings panel key was not checked")
assert(hasLoggedText("Wardrobe control panel can be opened by pressing F7."),
    "the round-start notice did not display the configured panel key")
assert(liveOverlayRoots == 1, "the initial wardrobe panel did not own exactly one overlay root")
assert(loadCalls >= 2, "single-player crew profiles were not loaded during the one-shot crew scan")
local importedPlayerProfileKey =
    profileStorageKey(campaignStorageKey, stableCharacterProfileKey("Player Tester"))
assert(profiles[importedPlayerProfileKey] ~= nil and
    profiles[importedPlayerProfileKey]:find("Head=helmet,", 1, true) ~= nil,
    "the legacy client look was not imported into the first controlled profile")
assert(activationCount == 0 and prefabCaptureCount == 0,
    "an imported legacy look activated before the player manually applied it")

local tutorialText = assert(localizedText["barowardrobeswitcher.panel.tutorial"]):gsub("{key}", "F7")
local _, tutorialLineBreaks = tutorialText:gsub("\n", "")
assert(tutorialLineBreaks == 4, "the new-player guide must render as five short lines")
assert(hasVisibleText(tutorialText), "the new-player guide was not expanded by default")
local hideTutorialButton = buttons["Hide New Player Guide"]
assert(hideTutorialButton ~= nil and type(hideTutorialButton.OnClicked) == "function",
    "the expanded guide did not expose its collapse control")
local removesBeforeHideTutorial = removedWidgets
hideTutorialButton.OnClicked()
assert(removedWidgets == removesBeforeHideTutorial and hasVisibleText(tutorialText),
    "collapsing the guide rebuilt the overlay inside its click callback")
hooks.think()
assert(removedWidgets == removesBeforeHideTutorial + 1 and liveOverlayRoots == 1,
    "collapsing the guide did not replace exactly one overlay on the next tick")
assert(not hasVisibleText(tutorialText), "the collapsed guide text remained visible")

local showTutorialButton = buttons["Show New Player Guide"]
assert(showTutorialButton ~= nil and type(showTutorialButton.OnClicked) == "function",
    "the collapsed guide did not expose its expand control")
local removesBeforeShowTutorial = removedWidgets
showTutorialButton.OnClicked()
assert(removedWidgets == removesBeforeShowTutorial and not hasVisibleText(tutorialText),
    "expanding the guide rebuilt the overlay inside its click callback")
hooks.think()
assert(removedWidgets == removesBeforeShowTutorial + 1 and liveOverlayRoots == 1,
    "expanding the guide did not replace exactly one overlay on the next tick")
assert(hasVisibleText(tutorialText), "the expanded guide text did not return")

assert(hasVisibleButton("Appearance Layers...") and hasVisibleButton("Forget Saved Look") and
       not hasVisibleButton("Movement: Fashion Priority") and not hasVisibleButton("Diagnostics"),
    "the main page did not separate appearance actions from movement and diagnostics")
local playerTargetButton = buttons["Wardrobe target: Player Tester"]
assert(playerTargetButton ~= nil and type(playerTargetButton.OnClicked) == "function",
    "the main page did not expose its single-player crew selector")
local removesBeforeTargetChange = removedWidgets
playerTargetButton.OnClicked()
assert(removedWidgets == removesBeforeTargetChange,
    "changing the wardrobe target rebuilt the overlay inside its click callback")
hooks.think()
assert(removedWidgets == removesBeforeTargetChange + 1 and liveOverlayRoots == 1 and
       hasVisibleButton("Wardrobe target: A Target NPC"),
    "the crew selector did not bind the first eligible bot on the next tick")
buttons["Save Current Outfit"].OnClicked()
hooks.think()
assert(lastEmptyCaptureCharacterId == selectorNpc.ID and
       lastSavedProfileKey == stableCharacterProfileKey("A Target NPC"),
    "Save did not capture and persist the selected bot's own wardrobe profile")

local nextPageButton = buttons["Next Page"]
assert(nextPageButton ~= nil and type(nextPageButton.OnClicked) == "function",
    "the main page did not expose its Next Page control")
local removesBeforeNextPage = removedWidgets
nextPageButton.OnClicked()
assert(removedWidgets == removesBeforeNextPage,
    "Next Page removed the active overlay from inside its click callback")
hooks.think()
assert(removedWidgets == removesBeforeNextPage + 1 and liveOverlayRoots == 1,
    "Next Page did not replace exactly one overlay on the next tick")
assert(not hasVisibleButton("Appearance Layers...") and
       hasVisibleButton("Movement: Fashion Priority") and hasVisibleButton("Diagnostics"),
    "page two did not contain only movement and diagnostic controls")
local fashionMovementButton = buttons["Movement: Fashion Priority"]
assert(fashionMovementButton ~= nil and type(fashionMovementButton.OnClicked) == "function",
    "page two did not expose the default fashion-priority movement setting")
local removesBeforeEquipmentMovement = removedWidgets
local savesBeforeEquipmentMovement = saveCalls
local movementCallsBeforeEquipmentMovement = movementAnimationCalls
fashionMovementButton.OnClicked()
assert(removedWidgets == removesBeforeEquipmentMovement,
    "changing the movement source rebuilt the overlay inside its click callback")
hooks.think()
assert(removedWidgets == removesBeforeEquipmentMovement + 1 and liveOverlayRoots == 1,
    "changing to equipped movement did not replace exactly one overlay on the next tick")
assert(movementAnimationCalls == movementCallsBeforeEquipmentMovement,
    "an inactive saved look tried to update a renderer session")
assert(saveCalls == savesBeforeEquipmentMovement + 1 and
       lastSaved:find("fashionMovement=false", 1, true) ~= nil,
    "the equipped-gear movement choice was not persisted through the reducer")
local equipmentMovementButton = buttons["Movement: Equipped Gear"]
assert(equipmentMovementButton ~= nil and type(equipmentMovementButton.OnClicked) == "function",
    "the equipped-gear movement choice did not update its button label")
local removesBeforeFashionMovement = removedWidgets
equipmentMovementButton.OnClicked()
assert(removedWidgets == removesBeforeFashionMovement,
    "restoring fashion movement rebuilt the overlay inside its click callback")
hooks.think()
assert(removedWidgets == removesBeforeFashionMovement + 1 and liveOverlayRoots == 1,
    "restoring fashion movement did not replace exactly one overlay on the next tick")
assert(movementAnimationCalls == movementCallsBeforeEquipmentMovement,
    "restoring an inactive saved look tried to update a renderer session")
assert(saveCalls == savesBeforeEquipmentMovement + 2 and
       lastSaved:find("fashionMovement=true", 1, true) ~= nil and
       lastSavedProfileKey == stableCharacterProfileKey("A Target NPC"),
    "the selected bot's movement choice was not persisted to its own profile")

local pageBackButton = buttons["Back"]
assert(pageBackButton ~= nil and type(pageBackButton.OnClicked) == "function",
    "page two did not expose its Back control")
local removesBeforePageBack = removedWidgets
pageBackButton.OnClicked()
assert(removedWidgets == removesBeforePageBack,
    "Back removed page two from inside its click callback")
hooks.think()
assert(removedWidgets == removesBeforePageBack + 1 and liveOverlayRoots == 1 and
       hasVisibleButton("Appearance Layers...") and not hasVisibleButton("Diagnostics"),
    "Back did not return to the main page on the next tick")

buttons["Wardrobe target: A Target NPC"].OnClicked()
hooks.think()
assert(hasVisibleButton("Wardrobe target: Existing NPC"),
    "the crew selector did not advance to the next eligible bot")
buttons["Wardrobe target: Existing NPC"].OnClicked()
hooks.think()
assert(hasVisibleButton("Wardrobe target: NPC Tester"),
    "the crew selector did not advance to the second eligible bot")
buttons["Wardrobe target: NPC Tester"].OnClicked()
hooks.think()
assert(hasVisibleButton("Wardrobe target: Player Tester") and Character.Controlled == player,
    "the crew selector included a real, enemy, nonhuman, dead, or removed character")
buttons["Wardrobe target: Player Tester"].OnClicked()
hooks.think()
selectorNpc.Removed = true
hooks.think()
assert(hasVisibleButton("Wardrobe target: Player Tester"),
    "an unavailable selected bot did not safely fall back to the controlled character")
selectorNpc.Removed = false

local appearanceLayersButton = buttons["Appearance Layers..."]
assert(appearanceLayersButton ~= nil and appearanceLayersButton.Enabled ~= false,
    "Appearance Layers should be enabled when a saved look exists")
assert(type(appearanceLayersButton.OnClicked) == "function",
    "Appearance Layers callback was not installed")
local removesBeforeAppearanceLayers = removedWidgets
appearanceLayersButton.OnClicked()
assert(removedWidgets == removesBeforeAppearanceLayers,
    "Appearance Layers removed the active overlay from inside its click callback")
hooks.think()
assert(removedWidgets == removesBeforeAppearanceLayers + 1,
    "Appearance Layers did not replace the main overlay on the next tick")
assert(liveOverlayRoots == 1, "Appearance Layers left the main overlay root alive")
local hideStandardHairButton = buttons["Hide Standard Hair"]
assert(hideStandardHairButton ~= nil and
    type(hideStandardHairButton.OnClicked) == "function",
    "Hide Standard Hair preset was not installed")
local savesBeforeAttachmentVisibility = saveCalls
hideStandardHairButton.OnClicked()
hooks.think()

assert(saveCalls == savesBeforeAttachmentVisibility + 1 and
       lastSavedProfileKey == stableCharacterProfileKey("Player Tester"),
    "attachment visibility did not persist to the controlled character profile")
assert(lastSaved ~= nil and
    lastSaved:find("schema=4", 1, true) ~= nil and
    lastSaved:find("hidehair=true", 1, true) ~= nil and
    lastSaved:find("fashionMovement=true", 1, true) ~= nil and
    lastSaved:find("visibilityHair=hide", 1, true) ~= nil and
    lastSaved:find("visibilityFaceAttachment=auto", 1, true) ~= nil,
    "attachment visibility persistence did not store the complete policy")

local applyButton = buttons["Apply Saved Look"]
assert(applyButton ~= nil and type(applyButton.OnClicked) == "function",
    "Apply Saved Look callback was not installed")
local saveButton = buttons["Save Current Outfit"]
assert(saveButton ~= nil and type(saveButton.OnClicked) == "function",
    "Save Current Outfit callback was not installed")
local clearButton = buttons["Clear Look"]
assert(clearButton ~= nil and type(clearButton.OnClicked) == "function",
    "Clear Look callback was not installed")
local forgetButton = buttons["Forget Saved Look"]
assert(forgetButton ~= nil and type(forgetButton.OnClicked) == "function",
    "Forget Saved Look callback was not installed")
local enableTransferButton = buttons["Enable Appearance Transfer"]
assert(enableTransferButton ~= nil and type(enableTransferButton.OnClicked) == "function",
    "single-player appearance-transfer toggle was not installed")

applyButton.OnClicked()
assert(activationCount == 1, "manual apply did not activate the player profile")
assert(prefabCaptureCount == 1,
    "a persisted player profile did not rebuild its renderer payload from the prefab")
assert(lastForceHideMask == 0x07 and lastForceShowMask == 0,
    "Hide Standard Hair did not project to the expected renderer masks")

-- Changing real equipment under an active look refreshes only the existing
-- local renderer session. Distinct Lua proxies for the same runtime item must
-- still be registered once when that item occupies multiple managed slots.
local playerEquipment = {}
player.Inventory.GetItemInLimbSlot = function(slot)
    return playerEquipment[slot]
end
local sharedProxyA = { ID = 700, Name = "Shared Gear", Prefab = { Identifier = "sharedgear" } }
local sharedProxyB = { ID = 700, Name = "Shared Gear", Prefab = { Identifier = "sharedgear" } }
playerEquipment[InvSlotType.Head] = sharedProxyA
playerEquipment[InvSlotType.OuterClothes] = sharedProxyB
local equipmentNetworkBefore = #networkSent
local equipmentSavesBefore = saveCalls
local equipmentCapturesBefore = prefabCaptureCount
local equipmentSlotsBefore = fashionSlotCalls
local equipmentRegistrationsBefore = equipmentRegistrationCalls
local equipmentActivationsBefore = activationAttempts
hooks.think()
assert(#networkSent == equipmentNetworkBefore and saveCalls == equipmentSavesBefore and
       prefabCaptureCount == equipmentCapturesBefore,
    "equipment-only refresh sent a command, persisted, or recaptured the saved look")
assert(fashionSlotCalls == equipmentSlotsBefore + 1 and
       equipmentRegistrationCalls == equipmentRegistrationsBefore + 1 and
       activationAttempts == equipmentActivationsBefore + 1,
    "equipment-only refresh did not batch one item registration and one final activation")

local observerEquipment = {}
npc.Inventory.GetItemInLimbSlot = function(slot)
    return observerEquipment[slot]
end
local observerGear = { ID = 701, Name = "Observer Gear", Prefab = { Identifier = "observergear" } }
local observerRegistrationsBefore = equipmentRegistrationCalls
hooks["item.equip"](observerGear, npc)
assert(equipmentRegistrationCalls == observerRegistrationsBefore,
    "observer hook registered an item outside the managed clothing slots")
observerEquipment[InvSlotType.Head] = observerGear
hooks["item.equip"](observerGear, npc)
assert(equipmentRegistrationCalls == observerRegistrationsBefore + 1,
    "observer managed clothing did not register local suppression")
local observerRemovalsBefore = equipmentRemovalCalls
observerEquipment[InvSlotType.Head] = nil
hooks["item.unequip"](observerGear, npc)
assert(equipmentRemovalCalls == observerRemovalsBefore + 1,
    "observer unequip did not release stale suppression references")

-- The fixture's activationCount tracks calls, while the real C# active-session
-- fast path returns without a second activation. Keep the older transition
-- assertions on their original baseline; activationAttempts above owns this case.
activationCount = activationCount - 1
table.remove(activationCharacterIds)

local hairLayerButton = buttons["Hair — Hide"]
assert(hairLayerButton ~= nil and type(hairLayerButton.OnClicked) == "function",
    "Hair visibility layer button was not installed")
local callsBeforeHairShow = attachmentVisibilityCalls
hairLayerButton.OnClicked()
assert(attachmentVisibilityCalls == callsBeforeHairShow + 1 and
       lastForceHideMask == 0x06 and lastForceShowMask == 0x01,
    "active Hair=Show did not preview with ForceShow taking priority")
assert(lastSaved:find("hidehair=false", 1, true) ~= nil and
       lastSaved:find("visibilityHair=show", 1, true) ~= nil and
       lastSaved:find("visibilityBeard=hide", 1, true) ~= nil,
    "active layer update did not persist the complete policy")

-- A direct controlled-character swap must keep the previous crew member's
-- renderer without leaking its look onto an unconfigured NPC.
Character.Controlled = npc
hooks.think()
assert(activationCount == 1,
    "the default-off transfer setting leaked the player's look onto an NPC; activations=" ..
    tostring(activationCount) ..
    ", ids=" ..
    table.concat(activationCharacterIds, ",") ..
    ", log=" ..
    table.concat(messages, " || "))
assert(activeCharacterIds[player.ID] == true and activeCharacterIds[npc.ID] ~= true,
    "a direct controlled-character swap cleared the previous crew member or leaked onto the new one")
local npcProfileKey =
    profileStorageKey(campaignStorageKey, stableCharacterProfileKey("NPC Tester"))
assert(profiles[npcProfileKey] == nil,
    "CharacterLost persisted the previous character's look into the new character profile")

Character.Controlled = nil
hooks.think()
Character.Controlled = player
hooks.think()
assert(activationCount == 2,
    "CharacterReady/RestoreLook did not rebuild the player's active reducer state")
enableTransferButton.OnClicked()
assert(transferEnabled, "appearance-transfer setting was not persisted")

Character.Controlled = nil
hooks.think()
assert(activeCharacterIds[player.ID] == true,
    "a transient no-controlled-character frame cleared the previous crew member")
Character.Controlled = npc
hooks.think()
assert(activationCount == 3,
    "enabled transfer did not fill the unconfigured NPC profile; activations=" ..
    tostring(activationCount) ..
    ", transfer=" ..
    tostring(transferEnabled))
assert(prefabCaptureCount == 2,
    "transferred NPC look did not build an NPC-owned renderer session")
assert(lastSaved ~= nil and lastSaved:find("auto=true", 1, true) ~= nil,
    "successful transferred look was not persisted for the target NPC")

-- Clear/reapply on the same NPC must reuse its committed renderer session.
clearButton.OnClicked()
applyButton.OnClicked()
assert(activationCount == 4, "NPC clear/reapply did not reactivate the renderer")
assert(prefabCaptureCount == 2,
    "clear/reapply discarded the reusable renderer session and rebuilt from the prefab")

-- An existing inactive profile must win over transfer and remain inactive until
-- explicitly applied.
Character.Controlled = nil
hooks.think()
buttons = {}
Character.Controlled = existingNpc
hooks.think()
hooks.think()
assert(activationCount == 4,
    "appearance transfer overwrote or activated an existing NPC profile")
local existingNpcBackButton = buttons["Back"]
assert(existingNpcBackButton ~= nil and type(existingNpcBackButton.OnClicked) == "function",
    "the attachment panel did not expose its Back action")
existingNpcBackButton.OnClicked()
buttons = {}
hooks.think()
local existingNextPageButton = buttons["Next Page"]
assert(existingNextPageButton ~= nil and type(existingNextPageButton.OnClicked) == "function",
    "the existing NPC main page did not expose Next Page")
existingNextPageButton.OnClicked()
buttons = {}
hooks.think()
assert(buttons["Movement: Equipped Gear"] ~= nil,
    "the single-player panel did not prefer the saved look's movement source")
buttons["Back"].OnClicked()
buttons = {}
hooks.think()
applyButton = buttons["Apply Saved Look"]
local existingProfileKey =
    profileStorageKey(campaignStorageKey, stableCharacterProfileKey("Existing NPC"))
assert(profiles[existingProfileKey] ~= nil and
    profiles[existingProfileKey]:find("existinghelmet", 1, true) ~= nil,
    "appearance transfer replaced an existing NPC profile")
applyButton.OnClicked()
assert(activationCount == 5,
    "manual apply did not activate the existing NPC profile")
assert(capturedIdentifierByCharacterId[44] == "existinghelmet",
    "the existing NPC profile did not use its own saved appearance")
assert(movementAnimationByCharacterId[44] == false,
    "the existing NPC profile did not apply its equipped-gear movement source")
assert(activeCharacterIds[43] == true and activeCharacterIds[44] == true,
    "switching crew did not preserve both independently active appearances")

-- Clear only the player before the scene transition. Both NPC profiles remain
-- active and should restore independently in the replacement scene.
Character.Controlled = nil
hooks.think()
Character.Controlled = player
hooks.think()
clearButton.OnClicked()
Character.Controlled = nil
hooks.think()
Character.Controlled = npc
hooks.think()

assert(type(hooks.roundEnd) == "function", "roundEnd hook was not registered")
assert(type(hooks.roundStart) == "function", "roundStart hook was not registered")
hooks.roundEnd()
local playerNextScene = makeCharacter(142, 100, "Player Tester", false)
local npcNextScene = makeCharacter(143, 200, "NPC Tester", true)
local existingNextScene = makeCharacter(144, 300, "Existing NPC", true)
Character.CharacterList = { playerNextScene, npcNextScene, existingNextScene }
Character.Controlled = playerNextScene
hooks.roundStart()
for _ = 1, 15 do hooks.think() end
assert(activationCount == 9,
    "active NPC looks were not independently restored in the next scene; activations=" ..
    tostring(activationCount))
assert(prefabCaptureCount == 5,
    "replacement NPCs incorrectly reused renderer sessions from the previous scene; captures=" ..
    tostring(prefabCaptureCount))
assert(capturedIdentifierByCharacterId[143] == "helmet",
    "the transferred NPC profile restored the wrong appearance")
assert(capturedIdentifierByCharacterId[144] == "existinghelmet",
    "the existing NPC profile restored the wrong appearance")
assert(activeCharacterIds[143] == true and activeCharacterIds[144] == true,
    "NPC profiles did not remain simultaneously active after scene restoration")
assert(reuseCheckCount >= 3,
    "local render effects did not query renderer-session reuse before choosing prefab capture")

Character.Controlled = nil
hooks.think()
Character.Controlled = npcNextScene
hooks.think()
clearButton.OnClicked()
forgetButton.OnClicked()
assert(activeCharacterIds[144] == true,
    "clearing or forgetting one NPC removed another NPC's active appearance")
assert(profiles[npcProfileKey] == nil,
    "Forget Saved Look did not delete only the current NPC profile")
assert(profiles[existingProfileKey] ~= nil,
    "Forget Saved Look deleted another NPC profile")

hooks.roundEnd()
local playerFinalScene = makeCharacter(242, 100, "Player Tester", false)
local npcFinalScene = makeCharacter(243, 200, "NPC Tester", true)
local existingFinalScene = makeCharacter(244, 300, "Existing NPC", true)
local twinA = makeCharacter(245, 400, "Twin NPC", true)
local twinB = makeCharacter(246, 401, "Twin NPC", true)
local missingStableId = makeCharacter(247, nil, "No Stable ID", true)
Character.CharacterList = {
    playerFinalScene,
    npcFinalScene,
    existingFinalScene,
    twinA,
    twinB,
    missingStableId
}
Character.Controlled = playerFinalScene
hooks.roundStart()
for _ = 1, 15 do hooks.think() end
assert(activationCount == 10,
    "forgotten or ambiguous NPC profiles were incorrectly restored; activations=" ..
    tostring(activationCount))
assert(activeCharacterIds[244] == true,
    "an unaffected NPC profile did not restore in the final scene")
assert(activeCharacterIds[243] ~= true,
    "a forgotten NPC profile was restored in a later scene")
assert(activeCharacterIds[245] ~= true and activeCharacterIds[246] ~= true,
    "an ambiguous character fingerprint did not fail closed")
assert(activeCharacterIds[247] ~= true,
    "a character without Character.Info.ID did not fail closed")

-- Without a campaign save path, profiles remain usable in memory but no
-- character profile is written to SinglePlayerProfiles.json.
hooks.roundEnd()
gameSessionDataPath.SavePath = nil
local memoryPlayer = makeCharacter(342, 500, "Memory Player", false)
local memoryNpc = makeCharacter(343, 501, "Memory NPC", true)
Character.CharacterList = { memoryPlayer, memoryNpc }
Character.Controlled = memoryPlayer
hooks.roundStart()
hooks.think()
local savesBeforeMemoryProfile = saveCalls
saveButton.OnClicked()
applyButton.OnClicked()
assert(activationCount == 11,
    "campaign-less player profile did not apply; activations=" ..
    tostring(activationCount))
Character.Controlled = nil
hooks.think()
Character.Controlled = memoryNpc
for _ = 1, 15 do hooks.think() end
assert(activationCount == 12,
    "campaign-less in-memory profiles did not apply and transfer during the session; activations=" ..
    tostring(activationCount) ..
    ", ids=" ..
    table.concat(activationCharacterIds, ","))
assert(saveCalls == savesBeforeMemoryProfile,
    "a campaign-less single-player profile was incorrectly written to disk")

-- A deterministic multiplayer rejection must not make auto-apply enqueue the
-- same command every think tick. Manual Apply remains available for retries.
hooks.roundEnd()
persistence.LoadClientLook = function()
    return "captured=true|active=true|auto=true|hidehair=false|Head=helmet,"
end
Game.IsMultiplayer = true
local multiplayerPlayer = makeCharacter(920, 920, "Multiplayer Player", false)
local multiplayerBot = makeCharacter(921, 921, "Multiplayer Bot", true)
local multiplayerHuman = makeCharacter(922, 922, "Multiplayer Human", false)
local multiplayerEnemy = makeCharacter(923, 923, "Multiplayer Enemy", true)
multiplayerEnemy.IsOnPlayerTeam = false
Character.Controlled = multiplayerPlayer
Character.CharacterList = {
    multiplayerPlayer, multiplayerBot, multiplayerHuman, multiplayerEnemy
}
hooks.roundStart()
for _ = 1, 15 do hooks.think() end

local serverHello = newNetworkBuffer(WardrobeCore.NET.V2_HELLO)
assert(WardrobeCore.writeServerHello(
    serverHello,
    0,
    WardrobeCore.CAPABILITY.AttachmentVisibility +
        WardrobeCore.CAPABILITY.MovementAnimationSource +
        WardrobeCore.CAPABILITY.CrewTargeting
))
serverHello.FinalizeForTransport()
assert(type(networkHandlers[WardrobeCore.NET.V2_HELLO]) == "function")
networkHandlers[WardrobeCore.NET.V2_HELLO](serverHello)

openPanel = true
hooks.think()
assert(buttons["Save Current Outfit"].Enabled == false,
    "multiplayer controls must stay disabled while a command is awaiting acknowledgement")

local sentApply = nil
for index = #networkSent, 1, -1 do
    if networkSent[index].name == WardrobeCore.NET.V2_COMMAND then
        sentApply = networkSent[index]
        break
    end
end
assert(sentApply ~= nil, "multiplayer auto-apply command was not sent")
local decodedApply = assert(WardrobeCore.readCommand(sentApply))
assert(decodedApply.kind == WardrobeCore.COMMAND.Apply)

local rejectedAck = newNetworkBuffer(WardrobeCore.NET.V2_ACK)
assert(WardrobeCore.writeAck(rejectedAck, {
    operationId = decodedApply.operationId,
    accepted = false,
    revision = 0,
    reason = "malformed_look"
}))
rejectedAck.FinalizeForTransport()
networkHandlers[WardrobeCore.NET.V2_ACK](rejectedAck)

local applyCountAfterRejection = 0
for _, message in ipairs(networkSent) do
    if message.name == WardrobeCore.NET.V2_COMMAND then
        applyCountAfterRejection = applyCountAfterRejection + 1
    end
end
for _ = 1, 10 do hooks.think() end
local finalApplyCount = 0
for _, message in ipairs(networkSent) do
    if message.name == WardrobeCore.NET.V2_COMMAND then
        finalApplyCount = finalApplyCount + 1
    end
end
assert(finalApplyCount == applyCountAfterRejection,
    "a rejected multiplayer auto-apply was queued again without a state change")
assert(buttons["Save Current Outfit"].Enabled ~= false,
    "multiplayer controls did not refresh after a rejected acknowledgement")

local multiplayerNextPageButton = buttons["Next Page"]
assert(multiplayerNextPageButton ~= nil and type(multiplayerNextPageButton.OnClicked) == "function")
multiplayerNextPageButton.OnClicked()
hooks.think()
local multiplayerMovementButton = buttons["Movement: Fashion Priority"]
assert(multiplayerMovementButton ~= nil and type(multiplayerMovementButton.OnClicked) == "function")
multiplayerMovementButton.OnClicked()
hooks.think()
local movementCommand = assert(WardrobeCore.readCommand(networkSent[#networkSent]))
assert(movementCommand.kind == WardrobeCore.COMMAND.Animation and
       movementCommand.look.useFashionMovementAnimations == false,
    "multiplayer movement toggle did not send its authoritative animation command")
local rejectedMovementAck = newNetworkBuffer(WardrobeCore.NET.V2_ACK)
assert(WardrobeCore.writeAck(rejectedMovementAck, {
    operationId = movementCommand.operationId,
    accepted = false,
    revision = 0,
    reason = "synthetic rejection"
}))
rejectedMovementAck.FinalizeForTransport()
networkHandlers[WardrobeCore.NET.V2_ACK](rejectedMovementAck)
hooks.think()
buttons["Back"].OnClicked()
hooks.think()

-- Accepted commands also finish asynchronously. The open panel must rebuild
-- after the acknowledgement instead of preserving its pending-state buttons.
buttons["Save Current Outfit"].OnClicked()
hooks.think()
assert(buttons["Save Current Outfit"].Enabled == false,
    "multiplayer controls were not disabled while Save was pending")
local sentSave = networkSent[#networkSent]
assert(sentSave ~= nil and sentSave.name == WardrobeCore.NET.V2_COMMAND)
local decodedSave = assert(WardrobeCore.readCommand(sentSave))
assert(decodedSave.kind == WardrobeCore.COMMAND.Save)
local acceptedAck = newNetworkBuffer(WardrobeCore.NET.V2_ACK)
assert(WardrobeCore.writeAck(acceptedAck, {
    operationId = decodedSave.operationId,
    accepted = true,
    revision = 1,
    reason = ""
}))
acceptedAck.FinalizeForTransport()
networkHandlers[WardrobeCore.NET.V2_ACK](acceptedAck)
hooks.think()
assert(buttons["Save Current Outfit"].Enabled ~= false,
    "multiplayer controls did not refresh after an accepted acknowledgement")
assert(buttons["Apply Saved Look"].Enabled ~= false,
    "Apply stayed disabled after multiplayer Save completed")

-- Apply remains serialized after its ACK until the authoritative state arrives.
-- If that state is lost, the retained idempotent command must time out and
-- release the controls instead of leaving ApplyPending forever.
buttons["Apply Saved Look"].OnClicked()
hooks.think()
assert(buttons["Save Current Outfit"].Enabled == false,
    "multiplayer controls were not disabled while Apply awaited server state")
local timedApplyMessage = networkSent[#networkSent]
assert(timedApplyMessage ~= nil and timedApplyMessage.name == WardrobeCore.NET.V2_COMMAND)
local timedApply = assert(WardrobeCore.readCommand(timedApplyMessage))
assert(timedApply.kind == WardrobeCore.COMMAND.Apply)
local timedApplyAck = newNetworkBuffer(WardrobeCore.NET.V2_ACK)
assert(WardrobeCore.writeAck(timedApplyAck, {
    operationId = timedApply.operationId,
    accepted = true,
    revision = 2,
    reason = ""
}))
timedApplyAck.FinalizeForTransport()
networkHandlers[WardrobeCore.NET.V2_ACK](timedApplyAck)
hooks.think()
assert(buttons["Save Current Outfit"].Enabled == false,
    "accepted Apply unlocked before its authoritative state arrived")
for _ = 1, 5 do
    testTime = testTime + 1
    hooks.think()
end
assert(buttons["Save Current Outfit"].Enabled ~= false,
    "Apply ACK without state did not time out and release the controls")

-- A delayed state must complete the retained command, and the server's normal
-- state-before-ACK ordering must not create a new false wait afterward.
buttons["Apply Saved Look"].OnClicked()
hooks.think()
local delayedStateCommand = assert(WardrobeCore.readCommand(networkSent[#networkSent]))
local delayedStateAck = newNetworkBuffer(WardrobeCore.NET.V2_ACK)
assert(WardrobeCore.writeAck(delayedStateAck, {
    operationId = delayedStateCommand.operationId,
    accepted = true,
    revision = 3,
    reason = ""
}))
delayedStateAck.FinalizeForTransport()
networkHandlers[WardrobeCore.NET.V2_ACK](delayedStateAck)
local delayedState = newNetworkBuffer(WardrobeCore.NET.V2_STATE)
assert(WardrobeCore.writeState(delayedState, {
    revision = 3,
    characterId = Character.Controlled.ID,
    active = true,
    look = delayedStateCommand.look
}))
delayedState.FinalizeForTransport()
networkHandlers[WardrobeCore.NET.V2_STATE](delayedState)
hooks.think()
assert(buttons["Save Current Outfit"].Enabled ~= false,
    "authoritative Apply state did not release the controls")
local sentAfterDelayedState = #networkSent
testTime = testTime + 6
hooks.think()
assert(#networkSent == sentAfterDelayedState,
    "completed Apply kept retrying after its delayed state arrived")

buttons["Apply Saved Look"].OnClicked()
hooks.think()
local stateFirstCommand = assert(WardrobeCore.readCommand(networkSent[#networkSent]))
local stateFirst = newNetworkBuffer(WardrobeCore.NET.V2_STATE)
assert(WardrobeCore.writeState(stateFirst, {
    revision = 4,
    characterId = Character.Controlled.ID,
    active = true,
    look = stateFirstCommand.look
}))
stateFirst.FinalizeForTransport()
networkHandlers[WardrobeCore.NET.V2_STATE](stateFirst)
local stateFirstAck = newNetworkBuffer(WardrobeCore.NET.V2_ACK)
assert(WardrobeCore.writeAck(stateFirstAck, {
    operationId = stateFirstCommand.operationId,
    accepted = true,
    revision = 4,
    reason = ""
}))
stateFirstAck.FinalizeForTransport()
networkHandlers[WardrobeCore.NET.V2_ACK](stateFirstAck)
hooks.think()
local sentAfterStateFirst = #networkSent
testTime = testTime + 6
hooks.think()
assert(#networkSent == sentAfterStateFirst,
    "state-before-ACK Apply was incorrectly retained for retry")

-- A matching but stale ACK must not discard the only timeout owner. Simulate
-- the communication-control mod blocking every retry and verify bounded exit.
buttons["Apply Saved Look"].OnClicked()
hooks.think()
local staleApplyCommand = assert(WardrobeCore.readCommand(networkSent[#networkSent]))
local staleApplyAck = newNetworkBuffer(WardrobeCore.NET.V2_ACK)
assert(WardrobeCore.writeAck(staleApplyAck, {
    operationId = staleApplyCommand.operationId,
    accepted = true,
    revision = 3,
    reason = ""
}))
staleApplyAck.FinalizeForTransport()
networkHandlers[WardrobeCore.NET.V2_ACK](staleApplyAck)
local workingSend = Networking.Send
Networking.Send = function() error("simulated blocked retry") end
for _ = 1, 5 do
    testTime = testTime + 1
    hooks.think()
end
Networking.Send = workingSend
assert(buttons["Save Current Outfit"].Enabled ~= false,
    "a stale Apply ACK discarded its timeout owner and left the controls disabled")

local closeButton = buttons["Close"]
assert(closeButton ~= nil and type(closeButton.OnClicked) == "function",
    "Close callback was not installed")
local removesBeforeClose = removedWidgets
closeButton.OnClicked()
assert(removedWidgets == removesBeforeClose,
    "Close removed the active overlay from inside its click callback")
hooks.think()
assert(removedWidgets == removesBeforeClose + 1,
    "Close did not release the overlay on the next tick")
assert(liveOverlayRoots == 0, "Close left an overlay root alive")

-- A round snapshot can arrive long before a slow client creates the remote
-- Character. Revisioned v2 state is authoritative for the whole round and must
-- survive beyond the old 300-tick timeout.
do
    local function deliverState(state)
        local message = newNetworkBuffer(WardrobeCore.NET.V2_STATE)
        assert(WardrobeCore.writeState(message, state))
        message.FinalizeForTransport()
        networkHandlers[WardrobeCore.NET.V2_STATE](message)
    end

    local remoteId = 901
    local remoteColor = 0x7F1122FF
    local remoteLook = assert(WardrobeCore.newLook(
        true,
        false,
        { Head = "helmet", InnerClothes = "helmet" },
        nil,
        { Head = remoteColor, InnerClothes = remoteColor + 1 },
        false
    ))
    local beforeLateEntity = activationCount
    deliverState({ revision = 10, characterId = remoteId, active = true, look = remoteLook })
    for _ = 1, 320 do hooks.think() end
    assert(activationCount == beforeLateEntity,
        "a snapshot rendered before its remote Character existed")

    Character.CharacterList[#Character.CharacterList + 1] =
        makeCharacter(remoteId, remoteId, "Early Player", false)
    for _ = 1, 30 do hooks.think() end
    assert(activationCount == beforeLateEntity + 1 and activeCharacterIds[remoteId] == true,
        "a retained snapshot was not applied when the late Character appeared")
    assert(capturedIdentifierByCharacterId[remoteId] == "helmet",
        "the late Character received the wrong wardrobe look")
    assert(movementAnimationByCharacterId[remoteId] == false,
        "the late Character did not receive equipped-gear movement from the server snapshot")
    local remoteKeys = capturedPrefabKeysByCharacterId[remoteId] or {}
    assert(#remoteKeys == 2 and
           remoteKeys[1] == "helmet@" .. tostring(remoteColor) and
           remoteKeys[2] == "helmet@" .. tostring(remoteColor + 1),
        "same-prefab fallbacks with different colors were merged or recolored")

    local updatedMovementLook = assert(WardrobeCore.copyLook(remoteLook))
    updatedMovementLook.useFashionMovementAnimations = true
    local beforeMovementOnlyUpdate = activationCount
    deliverState({ revision = 11, characterId = remoteId, active = true, look = updatedMovementLook })
    assert(activationCount == beforeMovementOnlyUpdate + 1 and
           movementAnimationByCharacterId[remoteId] == true,
        "an animation-only state update was deduplicated or not applied")

    local afterApply = activationCount
    deliverState({ revision = 11, characterId = remoteId, active = true, look = updatedMovementLook })
    deliverState({ revision = 10, characterId = remoteId, active = false, look = remoteLook })
    assert(activationCount == afterApply and activeCharacterIds[remoteId] == true,
        "duplicate or stale state replaced the accepted remote look")
    deliverState({ revision = 12, characterId = remoteId, active = false, look = updatedMovementLook })
    deliverState({ revision = 11, characterId = remoteId, active = true, look = updatedMovementLook })
    assert(activationCount == afterApply and activeCharacterIds[remoteId] ~= true,
        "an out-of-order state resurrected a newer cleared look")

    -- Authoritative render work waits for C# readiness without spending its
    -- three actual attempts, then retries temporary apply/clear failures.
    visualOverrideReady = false
    local attemptsBeforeReadiness = activationAttempts
    deliverState({ revision = 13, characterId = remoteId, active = true, look = updatedMovementLook })
    for _ = 1, 90 do hooks.think() end
    assert(activationAttempts == attemptsBeforeReadiness,
        "renderer readiness polling consumed an apply attempt")
    visualOverrideReady = true
    for _ = 1, 30 do hooks.think() end
    assert(activationAttempts == attemptsBeforeReadiness + 1 and activeCharacterIds[remoteId] == true,
        "a ready renderer did not consume the retained authoritative apply")

    local retryApplyLook = assert(WardrobeCore.copyLook(updatedMovementLook))
    retryApplyLook.useFashionMovementAnimations = false
    activationFailuresRemaining = 2
    local attemptsBeforeApplyRetry = activationAttempts
    deliverState({ revision = 14, characterId = remoteId, active = true, look = retryApplyLook })
    for _ = 1, 60 do hooks.think() end
    assert(activationAttempts == attemptsBeforeApplyRetry + 3 and
           movementAnimationByCharacterId[remoteId] == false,
        "a temporary authoritative apply failure did not succeed on the third attempt")

    clearFailuresRemaining = 2
    local attemptsBeforeClearRetry = clearAttempts
    deliverState({ revision = 15, characterId = remoteId, active = false, look = retryApplyLook })
    for _ = 1, 60 do hooks.think() end
    assert(clearAttempts == attemptsBeforeClearRetry + 3 and activeCharacterIds[remoteId] ~= true,
        "a temporary authoritative clear failure did not succeed on the third attempt")

    local notReadyClearId = 904
    Character.CharacterList[#Character.CharacterList + 1] =
        makeCharacter(notReadyClearId, notReadyClearId, "Clear While Loading", false)
    deliverState({ revision = 1, characterId = notReadyClearId, active = true, look = retryApplyLook })
    visualOverrideReady = false
    local attemptsBeforeNotReadyClear = clearAttempts
    deliverState({ revision = 2, characterId = notReadyClearId, active = false, look = retryApplyLook })
    assert(clearAttempts == attemptsBeforeNotReadyClear + 1 and
           activeCharacterIds[notReadyClearId] ~= true,
        "an authoritative clear waited for renderer readiness")

    visualOverrideReady = false
    local supersededLook = assert(WardrobeCore.newLook(true, false, { Head = "supersededhelmet" }))
    local latestLook = assert(WardrobeCore.newLook(true, false, { Head = "latesthelmet" }))
    deliverState({ revision = 16, characterId = remoteId, active = true, look = supersededLook })
    deliverState({ revision = 17, characterId = remoteId, active = true, look = latestLook })
    visualOverrideReady = true
    for _ = 1, 30 do hooks.think() end
    assert(capturedIdentifierByCharacterId[remoteId] == "latesthelmet",
        "an older pending authoritative apply replaced the latest revision")

    activationFailuresRemaining = 3
    local attemptsBeforeBoundedFailure = activationAttempts
    local exhaustedLook = assert(WardrobeCore.newLook(true, false, { Head = "exhaustedhelmet" }))
    deliverState({ revision = 18, characterId = remoteId, active = true, look = exhaustedLook })
    for _ = 1, 120 do hooks.think() end
    assert(activationAttempts == attemptsBeforeBoundedFailure + 3,
        "authoritative apply retries were not bounded to three actual attempts")
    deliverState({ revision = 19, characterId = remoteId, active = false, look = exhaustedLook })

    local helloBeforeRound = nil
    local helloCountBeforeRound = 0
    for _, message in ipairs(networkSent) do
        if message.name == WardrobeCore.NET.V2_HELLO then
            helloBeforeRound = message
            helloCountBeforeRound = helloCountBeforeRound + 1
        end
    end
    assert(helloBeforeRound ~= nil, "initial v2 hello was not sent")
    local initialSessionId = assert(WardrobeCore.readClientHello(helloBeforeRound)).clientSessionId
    hooks.roundEnd()
    Character.Controlled = nil
    hooks.roundStart()
    local helloCountBeforeCharacterReady = 0
    for _, message in ipairs(networkSent) do
        if message.name == WardrobeCore.NET.V2_HELLO then
            helloCountBeforeCharacterReady = helloCountBeforeCharacterReady + 1
        end
    end
    assert(helloCountBeforeCharacterReady == helloCountBeforeRound,
        "round start requested a wardrobe snapshot before the controlled Character was ready")

    local nextRoundCharacter = makeCharacter(902, 902, "Late Local Player", false)
    Character.Controlled = nextRoundCharacter
    Character.CharacterList[#Character.CharacterList + 1] = nextRoundCharacter
    hooks.think()
    local helloAfterRound = nil
    local helloCountAfterRound = 0
    for _, message in ipairs(networkSent) do
        if message.name == WardrobeCore.NET.V2_HELLO then
            helloAfterRound = message
            helloCountAfterRound = helloCountAfterRound + 1
        end
    end
    assert(helloCountAfterRound == helloCountBeforeRound + 1,
        "a ready controlled Character did not request exactly one fresh state snapshot")
    assert(assert(WardrobeCore.readClientHello(helloAfterRound)).clientSessionId == initialSessionId,
        "round snapshot request replaced the negotiated client session")

    local beforeDeferredV2 = activationCount
    local nextRoundLook = assert(WardrobeCore.newLook(
        true,
        false,
        { Head = "helmet" },
        nil,
        nil,
        false
    ))
    local staleRoundLook = assert(WardrobeCore.newLook(
        true,
        false,
        { Head = "stalegatehelmet" },
        nil,
        nil,
        true
    ))
    deliverState({ revision = 20, characterId = nextRoundCharacter.ID, active = true, look = nextRoundLook })
    deliverState({ revision = 19, characterId = nextRoundCharacter.ID, active = true, look = staleRoundLook })
    assert(activationCount == beforeDeferredV2,
        "a v2 round-start snapshot bypassed the initial equipment gate")
    for _ = 1, 15 do hooks.think() end
    assert(activationCount == beforeDeferredV2 + 1,
        "a deferred v2 round-start snapshot was not applied exactly once")
    assert(capturedIdentifierByCharacterId[nextRoundCharacter.ID] == "helmet" and
           movementAnimationByCharacterId[nextRoundCharacter.ID] == false,
        "a stale round-start state replaced the newest deferred state")
    deliverState({ revision = 20, characterId = nextRoundCharacter.ID, active = true, look = nextRoundLook })
    deliverState({ revision = 19, characterId = nextRoundCharacter.ID, active = true, look = nextRoundLook })
    assert(activationCount == beforeDeferredV2 + 1,
        "duplicate or stale deferred v2 state rendered again")

    local controlledRetryLook = assert(WardrobeCore.newLook(
        true,
        false,
        { Head = "controlledretryhelmet" },
        nil,
        nil,
        false
    ))
    activationFailuresRemaining = 1
    deliverState({
        revision = 22,
        characterId = nextRoundCharacter.ID,
        active = true,
        look = controlledRetryLook
    })
    deliverState({
        revision = 21,
        characterId = nextRoundCharacter.ID,
        active = true,
        look = nextRoundLook
    })
    for _ = 1, 30 do hooks.think() end
    assert(capturedIdentifierByCharacterId[nextRoundCharacter.ID] == "controlledretryhelmet",
        "a stale same-kind apply cancelled the newer controlled-character retry")

    clearFailuresRemaining = 1
    local controlledClearAttempts = clearAttempts
    deliverState({
        revision = 24,
        characterId = nextRoundCharacter.ID,
        active = false,
        look = controlledRetryLook
    })
    deliverState({
        revision = 23,
        characterId = nextRoundCharacter.ID,
        active = false,
        look = controlledRetryLook
    })
    for _ = 1, 30 do hooks.think() end
    assert(clearAttempts == controlledClearAttempts + 2 and
           activeCharacterIds[nextRoundCharacter.ID] ~= true,
        "a stale same-kind clear cancelled the newer controlled-character retry")

    openPanel = true
    hooks.think()
    local multiplayerTargetButton = buttons["Wardrobe target: Late Local Player"]
    assert(multiplayerTargetButton ~= nil and type(multiplayerTargetButton.OnClicked) == "function" and
        hasVisibleText("Multiplayer uses one saved look per player; this selects who the actions affect."),
        "crew-target capable multiplayer did not expose its shared-look target selector")
    multiplayerTargetButton.OnClicked()
    hooks.think()
    assert(hasVisibleButton("Wardrobe target: Multiplayer Bot"),
        "multiplayer selector included a player or enemy before the friendly bot")
    buttons["Apply Saved Look"].OnClicked()
    hooks.think()
    local targetedApplyMessage = networkSent[#networkSent]
    assert(targetedApplyMessage ~= nil and
        targetedApplyMessage.name == WardrobeCore.NET.V2_TARGET_COMMAND,
        "selected multiplayer bot used the self-only command channel")
    local targetedApply = assert(WardrobeCore.readTargetCommand(targetedApplyMessage))
    assert(targetedApply.kind == WardrobeCore.COMMAND.Apply and
        targetedApply.targetCharacterId == multiplayerBot.ID,
        "multiplayer Apply did not freeze the selected bot entity ID")
    assert(buttons["Wardrobe target: Multiplayer Bot"].Enabled == false,
        "multiplayer target selector stayed enabled while a command was pending")
    local rejectedTargetApplyAck = newNetworkBuffer(WardrobeCore.NET.V2_ACK)
    assert(WardrobeCore.writeAck(rejectedTargetApplyAck, {
        operationId = targetedApply.operationId,
        accepted = false,
        revision = 24,
        reason = "synthetic target rejection"
    }))
    rejectedTargetApplyAck.FinalizeForTransport()
    networkHandlers[WardrobeCore.NET.V2_ACK](rejectedTargetApplyAck)
    hooks.think()
    buttons["Wardrobe target: Multiplayer Bot"].OnClicked()
    hooks.think()
    assert(hasVisibleButton("Wardrobe target: Late Local Player"),
        "multiplayer selector did not return from the only eligible bot to the player")

    -- Capabilities are independent. A relay may expose animation sync without
    -- attachment visibility; the animation command and false setting must survive.
    local movementOnlyHello = newNetworkBuffer(WardrobeCore.NET.V2_HELLO)
    assert(WardrobeCore.writeServerHello(
        movementOnlyHello,
        24,
        WardrobeCore.CAPABILITY.MovementAnimationSource
    ))
    movementOnlyHello.FinalizeForTransport()
    networkHandlers[WardrobeCore.NET.V2_HELLO](movementOnlyHello)
    openPanel = true
    hooks.think()
    local movementOnlyButton = buttons["Movement: Equipped Gear"]
    assert(movementOnlyButton ~= nil and type(movementOnlyButton.OnClicked) == "function",
        "movement-only capability did not expose the authoritative animation control")
    movementOnlyButton.OnClicked()
    hooks.think()
    local movementOnlyCommand = assert(WardrobeCore.readCommand(networkSent[#networkSent]))
    assert(movementOnlyCommand.kind == WardrobeCore.COMMAND.Animation and
           movementOnlyCommand.look.useFashionMovementAnimations == true,
        "movement-only capability rejected or truncated the animation command")
    local movementOnlyRejection = newNetworkBuffer(WardrobeCore.NET.V2_ACK)
    assert(WardrobeCore.writeAck(movementOnlyRejection, {
        operationId = movementOnlyCommand.operationId,
        accepted = false,
        revision = 24,
        reason = "synthetic rejection"
    }))
    movementOnlyRejection.FinalizeForTransport()
    networkHandlers[WardrobeCore.NET.V2_ACK](movementOnlyRejection)
    hooks.think()

    buttons["Save Current Outfit"].OnClicked()
    hooks.think()
    local movementOnlySave = assert(WardrobeCore.readCommand(networkSent[#networkSent]))
    assert(movementOnlySave.kind == WardrobeCore.COMMAND.Save and
           movementOnlySave.look.useFashionMovementAnimations == false,
        "movement-only capability dropped equipped-gear movement from Save")
end

-- Reload an isolated probing client to cover the compatibility bridge. The
-- deferred v1 frame must be consumed once when the same equipment gate opens.
persistence.LoadClientLook = function() return "" end
local v1Character = makeCharacter(903, 903, "Late Legacy Player", false)
Character.Controlled = v1Character
Character.CharacterList = { v1Character }
gameSessionDataPath.SavePath = "p2p-session-a.save"
assert(dofile(clientPath) == nil)
hooks.roundStart()
hooks.think()
local function legacyApplyFrame(characterId)
    local message = newNetworkBuffer(WardrobeCore.NET.V1_LOOK_APPLY)
    message.WriteUInt16(characterId)
    for index = 1, 6 do
        message.WriteBoolean(index == 1)
        if index == 1 then
            message.WriteUInt16(0)
            message.WriteString("helmet")
            message.WriteString("Helmet")
        end
    end
    message.FinalizeForTransport()
    return message
end
local deferredV1 = legacyApplyFrame(v1Character.ID)
local beforeDeferredV1 = activationCount
networkHandlers[WardrobeCore.NET.V1_LOOK_APPLY](deferredV1)
assert(activationCount == beforeDeferredV1,
    "a v1 round-start frame bypassed the initial equipment gate")
for _ = 1, 20 do hooks.think() end
assert(activationCount == beforeDeferredV1 + 1,
    "a deferred v1 round-start frame was not applied exactly once")

hooks.roundStart()
local beforeCancelledV1 = activationCount
networkHandlers[WardrobeCore.NET.V1_LOOK_APPLY](legacyApplyFrame(v1Character.ID))
local cancelledV1 = newNetworkBuffer(WardrobeCore.NET.V1_LOOK_CLEAR)
cancelledV1.WriteUInt16(v1Character.ID)
cancelledV1.FinalizeForTransport()
networkHandlers[WardrobeCore.NET.V1_LOOK_CLEAR](cancelledV1)
for _ = 1, 20 do hooks.think() end
assert(activationCount == beforeCancelledV1 and activeCharacterIds[v1Character.ID] ~= true,
    "a v1 clear did not cancel the deferred round-start apply")

openPanel = true
hooks.think()
assert(buttons["Clear Look"].Enabled ~= false,
    "cancelled deferred round-start look left Clear unbound")
assert(buttons["Save Current Outfit"].Enabled ~= false,
    "cancelled deferred round-start look left Save unbound")
assert(buttons["Apply Saved Look"].Enabled ~= false,
    "cancelled deferred round-start look left Apply unbound")

-- V1 has no ACK, so a missing LOOK_APPLY response needs its own deadline.
buttons["Apply Saved Look"].OnClicked()
hooks.think()
assert(buttons["Save Current Outfit"].Enabled == false,
    "v1 Apply did not enter the expected pending state")
testTime = testTime + 5
hooks.think()
assert(buttons["Save Current Outfit"].Enabled ~= false,
    "a lost v1 LOOK_APPLY response left the wardrobe controls disabled")

-- A normal legacy response clears that deadline; crossing it later must not
-- turn the successfully rendered look into a timeout.
buttons["Apply Saved Look"].OnClicked()
hooks.think()
networkHandlers[WardrobeCore.NET.V1_LOOK_APPLY](legacyApplyFrame(v1Character.ID))
hooks.think()
assert(buttons["Save Current Outfit"].Enabled ~= false,
    "a successful v1 LOOK_APPLY did not release the wardrobe controls")
testTime = testTime + 6
hooks.think()
assert(buttons["Save Current Outfit"].Enabled ~= false,
    "a completed v1 Apply was incorrectly timed out afterward")
openPanel = true
hooks.think()

local function latestClientSessionId()
    for index = #networkSent, 1, -1 do
        if networkSent[index].name == WardrobeCore.NET.V2_HELLO then
            return assert(WardrobeCore.readClientHello(networkSent[index])).clientSessionId
        end
    end
    return nil
end

local function clientHelloCount()
    local count = 0
    for _, message in ipairs(networkSent) do
        if message.name == WardrobeCore.NET.V2_HELLO then count = count + 1 end
    end
    return count
end

-- P2P scene changes can replace GameSession without changing its save path.
-- The accepted look survives, but transport/reducer identity must be rebound.
buttons["Apply Saved Look"].OnClicked()
hooks.think()
openPanel = true
hooks.think()
assert(buttons["Save Current Outfit"].Enabled == false,
    "same-key session regression did not stage a pending F8 command")
local pendingSameKeySessionId = assert(latestClientSessionId())
local helloCountBeforeSameKeyRebind = clientHelloCount()
gameMain.GameSession = {
    DataPath = gameSessionDataPath,
    IsRunning = true,
    RoundEnding = false
}
hooks.roundStart()
hooks.think()
local reboundSameKeySessionId = assert(latestClientSessionId())
assert(clientHelloCount() > helloCountBeforeSameKeyRebind,
    "same-key GameSession replacement did not start a fresh client session")
assert(reboundSameKeySessionId ~= pendingSameKeySessionId,
    "same-key GameSession replacement reused the pending client session")
assert(buttons["Save Current Outfit"].Enabled ~= false and
       buttons["Apply Saved Look"].Enabled ~= false and
       buttons["Clear Look"].Enabled ~= false,
    "same-key GameSession replacement retained the stale F8 command")
for _ = 1, 20 do hooks.think() end
networkHandlers[WardrobeCore.NET.V1_LOOK_APPLY](legacyApplyFrame(v1Character.ID))
hooks.think()
assert(buttons["Save Current Outfit"].Enabled ~= false and
       buttons["Apply Saved Look"].Enabled ~= false and
       buttons["Clear Look"].Enabled ~= false,
    "same-key GameSession replacement left its fresh F8 command disabled")

-- The same transient rebind is required when both old and new sessions have
-- no stable path. Entering the pathless session itself remains a full reset.
persistence.LoadClientLook = function()
    return "captured=true|active=false|auto=false|hidehair=false|Head=helmet,"
end
gameSessionDataPath.SavePath = nil
hooks.roundStart()
hooks.think()
local pathlessSessionId = assert(latestClientSessionId())
assert(pathlessSessionId ~= reboundSameKeySessionId,
    "entering a pathless session reused the previous client session id")
gameMain.GameSession = {
    DataPath = gameSessionDataPath,
    IsRunning = true,
    RoundEnding = false
}
hooks.roundStart()
hooks.think()
local reboundPathlessSessionId = assert(latestClientSessionId())
assert(reboundPathlessSessionId ~= pathlessSessionId,
    "pathless GameSession replacement reused the stale client session id")
openPanel = true
hooks.think()
assert(buttons["Save Current Outfit"].Enabled ~= false and
       buttons["Apply Saved Look"].Enabled ~= false and
       buttons["Clear Look"].Enabled ~= false,
    "pathless GameSession replacement left F8 actions disabled")

-- P2P can replace the game session while retaining the same controlled
-- Character object. A genuinely different stable key still performs the full
-- reset and then binds the fresh reducer to that same Character.
gameSessionDataPath.SavePath = "p2p-session-b.save"
openPanel = true
hooks.think()
assert(buttons["Save Current Outfit"].Enabled ~= false and
       buttons["Apply Saved Look"].Enabled ~= false and
       buttons["Clear Look"].Enabled ~= false,
    "same-character P2P session replacement left F8 actions disabled")

assert(#messages == 0,
    "routine wardrobe diagnostics leaked into the Lua console")
assert(#loggedMessages > 0,
    "routine wardrobe diagnostics were not written through the file logger")

print = originalPrint
print("Wardrobe client facade tests passed")
