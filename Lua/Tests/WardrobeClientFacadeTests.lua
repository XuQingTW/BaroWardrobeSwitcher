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

local activationCount = 0
local attachmentVisibilityCalls = 0
local lastForceHideMask = nil
local lastForceShowMask = nil
local activationCharacterIds = {}
local activeCharacterIds = {}
local capturedIdentifierByCharacterId = {}
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
    CaptureFashionPrefab = function(character, identifier)
        prefabCaptureCount = prefabCaptureCount + 1
        capturedIdentifierByCharacterId[characterId(character)] = tostring(identifier)
        return 1
    end,
    CaptureEmptyFashion = function() return true end,
    SetFashionSlots = function() return true end,
    SetAttachmentVisibility = function(_, forceHideMask, forceShowMask)
        attachmentVisibilityCalls = attachmentVisibilityCalls + 1
        lastForceHideMask = forceHideMask
        lastForceShowMask = forceShowMask
        return true
    end,
    ActivateFashionVisual = function(character)
        activationCount = activationCount + 1
        local id = characterId(character)
        activationCharacterIds[#activationCharacterIds + 1] = id
        activeCharacterIds[id] = true
        return true
    end,
    ClearCharacter = function(character)
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
local function vector(x, y)
    return { X = x, Y = y }
end

LuaUserData = {
    CreateStatic = function(name)
        if name == "BaroWardrobeSwitcher.WardrobePersistence" then return persistence end
        if name == "BaroWardrobeSwitcher.VisualOverride" then return visualOverride end
        if name == "Barotrauma.GameMain" then
            return {
                GameSession = {
                    DataPath = gameSessionDataPath,
                    IsRunning = true,
                    RoundEnding = false
                }
            }
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
local function newNetworkBuffer(name)
    local values, readIndex = {}, 1
    local buffer = { name = name, LengthBits = 0, BitPosition = 0 }
    local function bitLength(kind, value)
        if kind == "u16" then return 16 end
        if kind == "u32" then return 32 end
        if kind == "byte" then return 8 end
        if kind == "bool" then return 1 end
        if kind == "string" then return 16 + #(tostring(value or "")) * 8 end
        return 0
    end
    local function write(kind, value)
        values[#values + 1] = { kind = kind, value = value }
        buffer.LengthBits = buffer.LengthBits + bitLength(kind, value)
    end
    local function read(kind)
        local entry = assert(values[readIndex], "read beyond network test buffer")
        assert(entry.kind == kind, "expected " .. kind .. ", got " .. tostring(entry.kind))
        readIndex = readIndex + 1
        buffer.BitPosition = buffer.BitPosition + bitLength(kind, entry.value)
        return entry.value
    end
    buffer.WriteUInt16 = function(value) write("u16", value) end
    buffer.ReadUInt16 = function() return read("u16") end
    buffer.WriteUInt32 = function(value) write("u32", value) end
    buffer.ReadUInt32 = function() return read("u32") end
    buffer.WriteByte = function(value) write("byte", value) end
    buffer.ReadByte = function() return read("byte") end
    buffer.WriteBoolean = function(value) write("bool", value) end
    buffer.ReadBoolean = function() return read("bool") end
    buffer.WriteString = function(value) write("string", value) end
    buffer.ReadString = function() return read("string") end
    buffer.FinalizeForTransport = function()
        buffer.LengthBits = math.ceil(buffer.LengthBits / 8) * 8
        return buffer
    end
    return buffer
end
Networking = {
    Receive = function(name, handler) networkHandlers[name] = handler end,
    Start = function(name) return newNetworkBuffer(name) end,
    Send = function(message)
        message.FinalizeForTransport()
        networkSent[#networkSent + 1] = message
    end
}
Game = { IsMultiplayer = false }
Character = { Controlled = nil, CharacterList = {} }
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
    "captured=true|active=false|auto=false|hidehair=false|Head=existinghelmet,"
profiles[profileStorageKey(campaignStorageKey, stableCharacterProfileKey("Twin NPC"))] =
    "captured=true|active=false|auto=true|hidehair=false|Head=twinhelmet,"
profiles[profileStorageKey(campaignStorageKey, stableCharacterProfileKey("No Stable ID"))] =
    "captured=true|active=false|auto=true|hidehair=false|Head=unstablehelmet,"

assert(dofile(clientPath) == nil)
assert(loadCalls == 0, "single-player profiles should load only after a campaign character exists")

local player = makeCharacter(42, 100, "Player Tester", false)
local npc = makeCharacter(43, 200, "NPC Tester", true)
local existingNpc = makeCharacter(44, 300, "Existing NPC", true)
Character.CharacterList = { player, npc, existingNpc }
Character.Controlled = player
openPanel = true
assert(type(hooks.think) == "function", "client think hook was not registered")
hooks.think()
assert(loadCalls >= 2, "single-player crew profiles were not loaded during the one-shot crew scan")
local importedPlayerProfileKey =
    profileStorageKey(campaignStorageKey, stableCharacterProfileKey("Player Tester"))
assert(profiles[importedPlayerProfileKey] ~= nil and
    profiles[importedPlayerProfileKey]:find("Head=helmet,", 1, true) ~= nil,
    "the legacy client look was not imported into the first controlled profile")
assert(activationCount == 0 and prefabCaptureCount == 0,
    "an imported legacy look activated before the player manually applied it")

local appearanceLayersButton = buttons["Appearance Layers..."]
assert(appearanceLayersButton ~= nil and appearanceLayersButton.Enabled ~= false,
    "Appearance Layers should be enabled when a saved look exists")
assert(type(appearanceLayersButton.OnClicked) == "function",
    "Appearance Layers callback was not installed")
appearanceLayersButton.OnClicked()
local hideStandardHairButton = buttons["Hide Standard Hair"]
assert(hideStandardHairButton ~= nil and
    type(hideStandardHairButton.OnClicked) == "function",
    "Hide Standard Hair preset was not installed")
hideStandardHairButton.OnClicked()

assert(saveCalls == 1, "attachment visibility did not persist to the current character profile")
assert(lastSaved ~= nil and
    lastSaved:find("schema=3", 1, true) ~= nil and
    lastSaved:find("hidehair=true", 1, true) ~= nil and
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

-- Default-off transfer: switching through a no-controlled frame must not leak
-- the player's active look onto an unconfigured NPC.
Character.Controlled = nil
hooks.think()
Character.Controlled = npc
hooks.think()
assert(activationCount == 1,
    "the default-off transfer setting leaked the player's look onto an NPC; activations=" ..
    tostring(activationCount) ..
    ", ids=" ..
    table.concat(activationCharacterIds, ",") ..
    ", log=" ..
    table.concat(messages, " || "))

Character.Controlled = nil
hooks.think()
Character.Controlled = player
hooks.think()
enableTransferButton.OnClicked()
assert(transferEnabled, "appearance-transfer setting was not persisted")

Character.Controlled = nil
hooks.think()
Character.Controlled = npc
hooks.think()
assert(activationCount == 2,
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
assert(activationCount == 3, "NPC clear/reapply did not reactivate the renderer")
assert(prefabCaptureCount == 2,
    "clear/reapply discarded the reusable renderer session and rebuilt from the prefab")

-- An existing inactive profile must win over transfer and remain inactive until
-- explicitly applied.
Character.Controlled = nil
hooks.think()
Character.Controlled = existingNpc
hooks.think()
assert(activationCount == 3,
    "appearance transfer overwrote or activated an existing NPC profile")
local existingProfileKey =
    profileStorageKey(campaignStorageKey, stableCharacterProfileKey("Existing NPC"))
assert(profiles[existingProfileKey] ~= nil and
    profiles[existingProfileKey]:find("existinghelmet", 1, true) ~= nil,
    "appearance transfer replaced an existing NPC profile")
applyButton.OnClicked()
assert(activationCount == 4,
    "manual apply did not activate the existing NPC profile")
assert(capturedIdentifierByCharacterId[44] == "existinghelmet",
    "the existing NPC profile did not use its own saved appearance")
assert(activeCharacterIds[43] == true and activeCharacterIds[44] == true,
    "two NPCs could not keep different active wardrobe sessions")

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
assert(activationCount == 6,
    "active NPC looks were not independently restored in the next scene")
assert(prefabCaptureCount == 5,
    "replacement NPCs incorrectly reused renderer sessions from the previous scene")
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
local npcProfileKey =
    profileStorageKey(campaignStorageKey, stableCharacterProfileKey("NPC Tester"))
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
assert(activationCount == 7,
    "forgotten or ambiguous NPC profiles were incorrectly restored")
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
assert(activationCount == 8,
    "campaign-less player profile did not apply; activations=" ..
    tostring(activationCount))
Character.Controlled = nil
hooks.think()
Character.Controlled = memoryNpc
for _ = 1, 15 do hooks.think() end
assert(activationCount == 9,
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
hooks.roundStart()
for _ = 1, 15 do hooks.think() end

local serverHello = newNetworkBuffer(WardrobeCore.NET.V2_HELLO)
assert(WardrobeCore.writeServerHello(
    serverHello,
    0,
    WardrobeCore.CAPABILITY.AttachmentVisibility
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

-- Accepted commands also finish asynchronously. The open panel must rebuild
-- after the acknowledgement instead of preserving its pending-state buttons.
buttons["Save Current Outfit"].OnClicked()
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

print = originalPrint
print("Wardrobe client facade tests passed")
