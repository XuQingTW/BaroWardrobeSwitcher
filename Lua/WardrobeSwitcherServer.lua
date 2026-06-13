local MOD_NAME = "Baro Wardrobe Switcher"
local NET_SAVE_REQUEST = "barowardrobeswitcher.save"
local NET_APPLY_REQUEST = "barowardrobeswitcher.apply"
local NET_CLEAR_REQUEST = "barowardrobeswitcher.clear"
local NET_FORGET_REQUEST = "barowardrobeswitcher.forget"
local NET_LOOK_APPLY = "barowardrobeswitcher.look.apply"
local NET_LOOK_CLEAR = "barowardrobeswitcher.look.clear"

if not SERVER then return end

local CharacterInventory = nil
pcall(function()
    CharacterInventory = LuaUserData.CreateStatic("Barotrauma.CharacterInventory", true)
end)
local Client = nil
pcall(function()
    Client = LuaUserData.CreateStatic("Barotrauma.Networking.Client", true)
end)
local GameMain = nil
pcall(function()
    GameMain = LuaUserData.CreateStatic("Barotrauma.GameMain", true)
end)
local Environment = nil
pcall(function()
    Environment = LuaUserData.CreateStatic("System.Environment", true)
end)
local Directory = nil
pcall(function()
    Directory = LuaUserData.CreateStatic("System.IO.Directory", true)
end)

local slots = {
    { key = "Head", label = "Head", slot = InvSlotType.Head },
    { key = "Headset", label = "Headset", slot = InvSlotType.Headset },
    { key = "InnerClothes", label = "Inner", slot = InvSlotType.InnerClothes },
    { key = "OuterClothes", label = "Outer", slot = InvSlotType.OuterClothes },
    { key = "Bag", label = "Bag", slot = InvSlotType.Bag },
    { key = "HealthInterface", label = "Health", slot = InvSlotType.HealthInterface }
}

local savedLooksByCharacterId = {}
local activeLooksByCharacterId = {}
local savedLooksByClientKey = {}
local activeLooksByClientKey = {}
local savedLookSessionByClientKey = {}
local legacySavedLookByClientKey = {}
local activeCharacterIdByClientKey = {}
local ownerKeyByCharacterId = {}
local lastSyncedCharacterByClientKey = {}
local lastSyncedLookSignatureByClientKey = {}
local lastSyncAttemptTickByClientKey = {}
local syncAttemptsByClientKey = {}
local clientCharacter
local broadcastClear
local serverTick = 0
local lastServerSessionKey = nil

local ServerSyncRetryTicks = 30
local ServerSyncMaxAttempts = 10
local ServerSyncHeartbeatTicks = 300

local function log(message)
    local line = "[" .. MOD_NAME .. "] " .. tostring(message)
    if LuaCsLogger ~= nil and LuaCsLogger.Log ~= nil then
        LuaCsLogger.Log(line)
    else
        print(line)
    end
end

local function getEnvironmentVariable(name)
    if Environment ~= nil then
        local ok, value = pcall(function()
            return Environment.GetEnvironmentVariable(name)
        end)
        if ok and value ~= nil and tostring(value) ~= "" then
            return tostring(value)
        end
    end
    if os ~= nil and os.getenv ~= nil then
        local value = os.getenv(name)
        if value ~= nil and tostring(value) ~= "" then
            return tostring(value)
        end
    end
    return nil
end

local function persistentDirectory()
    local localAppData = getEnvironmentVariable("LOCALAPPDATA") or getEnvironmentVariable("APPDATA")
    if localAppData ~= nil then
        return tostring(localAppData):gsub("\\", "/") .. "/Daedalic Entertainment GmbH/Barotrauma/ModData/BaroWardrobeSwitcher"
    end
    local home = getEnvironmentVariable("HOME")
    if home ~= nil then
        return tostring(home):gsub("\\", "/") .. "/.local/share/Daedalic Entertainment GmbH/Barotrauma/ModData/BaroWardrobeSwitcher"
    end
    return "./Daedalic Entertainment GmbH/Barotrauma/ModData/BaroWardrobeSwitcher"
end

local function persistentPath()
    return persistentDirectory() .. "/ServerLooks.txt"
end

local function ensurePersistentDirectory()
    if Directory == nil then return false end
    local ok = pcall(function()
        Directory.CreateDirectory(persistentDirectory())
    end)
    return ok == true
end

local function userDataMember(object, name)
    if object == nil or name == nil then return nil end
    local ok, value = pcall(function()
        return object[name]
    end)
    if ok then return value end
    return nil
end

local function trimIdentityValue(value)
    if value == nil then return nil end
    local text = tostring(value):match("^%s*(.-)%s*$")
    local lowered = text ~= nil and text:lower() or nil
    if text == nil or text == "" or lowered == "nil" or lowered == "null" then return nil end
    return text
end

local function stableIdentityValue(value)
    local text = trimIdentityValue(value)
    if text == nil then return nil end
    if text:match("^0+$") then return nil end
    return text
end

local function prefixedClientKey(prefix, value)
    local text = stableIdentityValue(value)
    if text == nil then return nil end
    return prefix .. ":" .. text
end

local function isPersistentClientKey(key)
    local prefix = tostring(key or ""):match("^([%a_][%w_%-]*):")
    return prefix == "steam" or prefix == "account"
end

local function normalizePersistentClientKey(rawKey)
    local text = stableIdentityValue(rawKey)
    if text == nil then return nil, true end

    local prefix, value = text:match("^([%a_][%w_%-]*):(.*)$")
    if prefix ~= nil then
        prefix = prefix:lower()
        value = stableIdentityValue(value)
        if value == nil then return nil, true end
        if prefix == "steam" or prefix == "account" then
            return prefix .. ":" .. value, false
        end
        return nil, true
    end

    if text:match("^%d+$") then
        return "steam:" .. text, true
    end

    return nil, true
end

local function normalizedSessionValue(value)
    local text = trimIdentityValue(value)
    if text == nil then return nil end
    return text:gsub("\\", "/")
end

local function firstSessionValue(object, names)
    for _, name in ipairs(names) do
        local value = normalizedSessionValue(userDataMember(object, name))
        if value ~= nil then return value end
    end
    return nil
end

local function currentServerSessionKey()
    if GameMain == nil then return nil end
    local session = userDataMember(GameMain, "GameSession")
    if session == nil then return nil end

    local direct = firstSessionValue(session, { "SavePath", "SaveFilePath", "SaveFile", "FilePath" })
    if direct ~= nil then return "session:" .. direct end

    local gameMode = userDataMember(session, "GameMode")
    local fromGameMode = firstSessionValue(gameMode, { "SavePath", "SaveFilePath", "SaveFile", "FilePath" })
    if fromGameMode ~= nil then return "gamemode:" .. fromGameMode end

    local campaign = userDataMember(session, "Campaign") or userDataMember(gameMode, "Campaign")
    local fromCampaign = firstSessionValue(campaign, { "SavePath", "SaveFilePath", "SaveFile", "FilePath", "CampaignID", "Identifier" })
    if fromCampaign ~= nil then return "campaign:" .. fromCampaign end

    return nil
end

local function itemName(item)
    if item == nil then return "" end
    local prefab = item.Prefab
    if prefab == nil then return tostring(item) end
    if prefab.Name ~= nil then return tostring(prefab.Name) end
    if prefab.Identifier ~= nil then return tostring(prefab.Identifier) end
    return tostring(item)
end

local function itemIdentifier(item)
    if item == nil or item.Prefab == nil or item.Prefab.Identifier == nil then return "" end
    return tostring(item.Prefab.Identifier)
end

local function isIgnoredWardrobeItem(item)
    local identifier = itemIdentifier(item)
    return identifier == "genesplicer" or identifier == "advancedgenesplicer"
end

local function itemEntityId(item)
    if item == nil then return 0 end
    local ok, id = pcall(function()
        return item.ID
    end)
    if ok and id ~= nil then return id end
    return 0
end

local function characterEntityId(character)
    if character == nil then return 0 end
    local ok, id = pcall(function()
        return character.ID
    end)
    if ok and id ~= nil then return id end
    return 0
end

local function persistentClientKey(client)
    if client == nil then return nil end
    local candidates = {
        { prefix = "steam", getter = function() return client.SteamID end },
        { prefix = "account", getter = function() return client.AccountId end },
        { prefix = "account", getter = function() return client.AccountID end },
        { prefix = "account", getter = function() return client.AccountInfo ~= nil and client.AccountInfo.AccountId or nil end }
    }
    for _, candidate in ipairs(candidates) do
        local ok, value = pcall(candidate.getter)
        if ok then
            local key = prefixedClientKey(candidate.prefix, value)
            if key ~= nil then return key end
        end
    end
    return nil
end

local function runtimeClientKey(client)
    if client == nil then return nil end
    local connection = userDataMember(client, "Connection")
    local candidates = {
        { prefix = "runtime_session", getter = function() return userDataMember(client, "SessionId") or userDataMember(client, "SessionID") end },
        { prefix = "runtime_id", getter = function() return userDataMember(client, "ID") or userDataMember(client, "Id") end },
        { prefix = "runtime_endpoint", getter = function()
            return userDataMember(connection, "EndpointString") or
                userDataMember(connection, "EndPointString") or
                userDataMember(connection, "RemoteEndPoint") or
                userDataMember(connection, "EndPoint") or
                userDataMember(connection, "Address")
        end },
        { prefix = "runtime_name", getter = function() return userDataMember(client, "Name") end }
    }
    for _, candidate in ipairs(candidates) do
        local ok, value = pcall(candidate.getter)
        if ok then
            local key = prefixedClientKey(candidate.prefix, value)
            if key ~= nil then return key end
        end
    end
    return nil
end

local function clientKey(client)
    return persistentClientKey(client) or runtimeClientKey(client)
end

local function getSlotItem(character, slot)
    if character == nil or character.Inventory == nil then return nil end
    local ok, result = pcall(function()
        return character.Inventory.GetItemInLimbSlot(slot)
    end)
    if ok then return result end

    local slotIndex = nil
    pcall(function()
        slotIndex = character.Inventory.FindLimbSlot(slot)
    end)
    if slotIndex == nil or slotIndex < 0 then return nil end

    ok, result = pcall(function()
        return character.Inventory.GetItemAtSlot(slotIndex)
    end)
    if ok then return result end

    ok, result = pcall(function()
        return character.Inventory.GetItemAt(slotIndex)
    end)
    if ok then return result end

    return nil
end

local function isInSlot(character, item, slot)
    if character == nil or character.Inventory == nil or item == nil then return false end
    local ok, result = pcall(function()
        return character.Inventory.IsInLimbSlot(item, slot)
    end)
    if ok then return result == true end
    return getSlotItem(character, slot) == item
end

local function isInAnyWearableSlot(character, item)
    if character == nil or item == nil then return false end
    for _, entry in ipairs(slots) do
        if isInSlot(character, item, entry.slot) then return true end
    end
    return false
end

local function unequipItem(character, item)
    if character == nil or item == nil then return true end

    local function isClear()
        return not isInAnyWearableSlot(character, item)
    end

    local function moveToInventoryAndValidate()
        if character.Inventory == nil or CharacterInventory == nil then return false end
        local ok, result = pcall(function()
            return character.Inventory.TryPutItem(item, character, CharacterInventory.AnySlot, true, true)
        end)
        return ok and result == true and isClear()
    end

    pcall(function()
        item.Unequip(character)
    end)
    if isClear() then return true end

    if moveToInventoryAndValidate() then return true end

    pcall(function()
        item.Unequip(character)
    end)
    if isClear() then return true end

    pcall(function()
        item.Drop(character)
    end)
    return isClear()
end

local function buildLookState(character)
    local state = {
        characterId = characterEntityId(character),
        slots = {}
    }

    for _, entry in ipairs(slots) do
        local item = getSlotItem(character, entry.slot)
        if item ~= nil and not isIgnoredWardrobeItem(item) then
            state.slots[entry.key] = {
                itemId = itemEntityId(item),
                identifier = itemIdentifier(item),
                name = itemName(item)
            }
        else
            state.slots[entry.key] = nil
        end
    end

    return state
end

local function escape(value)
    local text = tostring(value or "")
    text = text:gsub("%%", "%%25"):gsub("|", "%%7C"):gsub(",", "%%2C"):gsub("=", "%%3D"):gsub("\n", "%%0A"):gsub("\r", "%%0D")
    return text
end

local function unescape(value)
    local text = tostring(value or "")
    text = text:gsub("%%0D", "\r"):gsub("%%0A", "\n"):gsub("%%3D", "="):gsub("%%2C", ","):gsub("%%7C", "|"):gsub("%%25", "%%")
    return text
end

local function cloneStateForCharacter(state, character)
    local cloned = {
        characterId = characterEntityId(character),
        slots = {}
    }
    for _, entry in ipairs(slots) do
        local slotState = state ~= nil and state.slots ~= nil and state.slots[entry.key] or nil
        if slotState ~= nil then
            local item = getSlotItem(character, entry.slot)
            cloned.slots[entry.key] = {
                itemId = item ~= nil and itemIdentifier(item) == slotState.identifier and itemEntityId(item) or (slotState.itemId or 0),
                identifier = slotState.identifier or "",
                name = slotState.name or ""
            }
        end
    end
    return cloned
end

local function lookStateSignature(state)
    local parts = { "character=" .. tostring(state ~= nil and state.characterId or 0) }
    for _, entry in ipairs(slots) do
        local slotState = state ~= nil and state.slots ~= nil and state.slots[entry.key] or nil
        if slotState ~= nil then
            parts[#parts + 1] =
                entry.key ..
                "=" ..
                tostring(slotState.identifier or "") ..
                "#" ..
                tostring(tonumber(slotState.itemId) or 0)
        else
            parts[#parts + 1] = entry.key .. "=-"
        end
    end
    return table.concat(parts, ";")
end

local function savedLookBelongsToCurrentSession(key)
    if key == nil then return false end
    if not isPersistentClientKey(key) then return true end
    if legacySavedLookByClientKey[key] == true then return false end
    local savedSessionKey = savedLookSessionByClientKey[key]
    if savedSessionKey == nil then return true end
    local sessionKey = currentServerSessionKey()
    return sessionKey ~= nil and savedSessionKey == sessionKey
end

local function persistLooks()
    ensurePersistentDirectory()
    local path = persistentPath()
    local file = io.open(path, "w")
    if file == nil then
        log("Could not write persistent wardrobe data to " .. tostring(path) .. ".")
        return
    end
    for key, state in pairs(savedLooksByClientKey) do
        if isPersistentClientKey(key) then
            local isLegacy = legacySavedLookByClientKey[key] == true
            local sessionKey = isLegacy and nil or (savedLookSessionByClientKey[key] or currentServerSessionKey())
            local active = not isLegacy and activeLooksByClientKey[key] == true and savedLookBelongsToCurrentSession(key)
            local parts = { "key=" .. escape(key), "active=" .. tostring(active) }
            if sessionKey ~= nil then
                parts[#parts + 1] = "session=" .. escape(sessionKey)
            end
            for _, entry in ipairs(slots) do
                local slotState = state.slots[entry.key]
                if slotState ~= nil then
                    parts[#parts + 1] = entry.key .. "=" .. escape(slotState.identifier or "") .. "," .. escape(slotState.name or "")
                end
            end
            file:write(table.concat(parts, "|") .. "\n")
        end
    end
    file:close()
end

local function loadPersistentLooksFromPath(path)
    local file = io.open(path, "r")
    if file == nil then return false end
    for line in file:lines() do
        local key = nil
        local sessionKey = nil
        local state = { characterId = 0, slots = {} }
        local active = false
        for part in tostring(line):gmatch("[^|]+") do
            local name, value = part:match("^([^=]+)=(.*)$")
            if name == "key" then
                key = unescape(value)
            elseif name == "active" then
                active = value == "true"
            elseif name == "session" then
                sessionKey = normalizedSessionValue(unescape(value))
            elseif name ~= nil then
                local identifier, displayName = tostring(value):match("^([^,]*),(.*)$")
                if identifier ~= nil then
                    state.slots[name] = {
                        itemId = 0,
                        identifier = unescape(identifier),
                        name = unescape(displayName or "")
                    }
                end
            end
        end
        local normalizedKey, legacyKey = normalizePersistentClientKey(key)
        if normalizedKey ~= nil then
            savedLooksByClientKey[normalizedKey] = state
            savedLookSessionByClientKey[normalizedKey] = sessionKey
            legacySavedLookByClientKey[normalizedKey] = legacyKey == true or sessionKey == nil
            activeLooksByClientKey[normalizedKey] =
                active == true and
                legacyKey ~= true and
                sessionKey ~= nil and
                sessionKey == currentServerSessionKey()
        end
    end
    file:close()
    return true
end

local function loadPersistentLooks()
    if loadPersistentLooksFromPath(persistentPath()) then return end
    if loadPersistentLooksFromPath("PersistentLooks.txt") then
        persistLooks()
    end
end

local function writeLookState(message, state)
    message.WriteUInt16(state.characterId or 0)
    for _, entry in ipairs(slots) do
        local slotState = state.slots[entry.key]
        message.WriteBoolean(slotState ~= nil)
        if slotState ~= nil then
            message.WriteUInt16(slotState.itemId or 0)
            message.WriteString(slotState.identifier or "")
            message.WriteString(slotState.name or "")
        end
    end
end

local function readApplyLookPayload(message, character)
    if message == nil then return nil end
    local ok, state = pcall(function()
        if message.ReadBoolean() ~= true then return nil end
        local payload = {
            characterId = characterEntityId(character),
            slots = {}
        }
        for _, entry in ipairs(slots) do
            if message.ReadBoolean() then
                local itemId = tonumber(message.ReadUInt16()) or 0
                local identifier = tostring(message.ReadString() or "")
                local name = tostring(message.ReadString() or "")
                if identifier ~= "" then
                    payload.slots[entry.key] = {
                        itemId = itemId,
                        identifier = identifier,
                        name = name
                    }
                end
            end
        end
        return payload
    end)
    if ok then return state end
    return nil
end

local function broadcastLookState(state)
    local message = Networking.Start(NET_LOOK_APPLY)
    writeLookState(message, state)
    Networking.Send(message, nil)
end

local function sendLookState(client, state)
    if client == nil or client.Connection == nil then return end
    local message = Networking.Start(NET_LOOK_APPLY)
    writeLookState(message, state)
    Networking.Send(message, client.Connection)
end

local function addConnectedClient(clients, seen, client)
    if client == nil or seen[client] then return end
    seen[client] = true
    clients[#clients + 1] = client
end

local function collectConnectedClientsFrom(source, clients, seen)
    if source == nil then return end

    local ok = pcall(function()
        for client in source do
            addConnectedClient(clients, seen, client)
        end
    end)
    if ok then return end

    ok = pcall(function()
        for _, client in pairs(source) do
            addConnectedClient(clients, seen, client)
        end
    end)
    if ok then return end

    pcall(function()
        local count = tonumber(source.Count)
        if count == nil then return end
        for index = 0, count - 1 do
            addConnectedClient(clients, seen, source[index])
        end
    end)
end

local function serverFromGameMain()
    if GameMain == nil then return nil end
    local ok, server = pcall(function()
        return GameMain.Server
    end)
    if ok then return server end
    return nil
end

local function serverFromGame()
    local ok, server = pcall(function()
        return Game ~= nil and Game.Server or nil
    end)
    if ok then return server end
    return nil
end

local function connectedClients()
    local clients = {}
    local seen = {}

    if Client ~= nil and Client.ClientList ~= nil then
        collectConnectedClientsFrom(Client.ClientList, clients, seen)
    end

    local gameMainServer = serverFromGameMain()
    if gameMainServer ~= nil then
        collectConnectedClientsFrom(gameMainServer.ConnectedClients, clients, seen)
    end

    local gameServer = serverFromGame()
    if gameServer ~= nil then
        collectConnectedClientsFrom(gameServer.ConnectedClients, clients, seen)
    end

    return clients
end

local function recordSyncAttempt(key, state, resetAttempts)
    if key == nil or state == nil then return end
    lastSyncedCharacterByClientKey[key] = state.characterId
    lastSyncedLookSignatureByClientKey[key] = lookStateSignature(state)
    lastSyncAttemptTickByClientKey[key] = serverTick
    if resetAttempts then
        syncAttemptsByClientKey[key] = 0
    end
    syncAttemptsByClientKey[key] = (syncAttemptsByClientKey[key] or 0) + 1
end

local function clearClientSyncState(key)
    if key == nil then return end
    lastSyncedCharacterByClientKey[key] = nil
    lastSyncedLookSignatureByClientKey[key] = nil
    lastSyncAttemptTickByClientKey[key] = nil
    syncAttemptsByClientKey[key] = nil
end

local function normalizedCharacterId(characterId)
    local id = tonumber(characterId) or 0
    if id <= 0 then return nil end
    return id
end

local function clearActiveCharacterId(characterId, shouldBroadcast, excludedClient)
    local id = normalizedCharacterId(characterId)
    if id == nil then return end

    local wasActive = activeLooksByCharacterId[id] == true
    local ownerKey = ownerKeyByCharacterId[id]

    activeLooksByCharacterId[id] = false
    savedLooksByCharacterId[id] = nil
    ownerKeyByCharacterId[id] = nil

    if ownerKey ~= nil and activeCharacterIdByClientKey[ownerKey] == id then
        activeCharacterIdByClientKey[ownerKey] = nil
    end

    if shouldBroadcast and (wasActive or ownerKey ~= nil) and broadcastClear ~= nil then
        broadcastClear(id, excludedClient)
    end
end

local function markActiveClientCharacter(key, characterId, state, shouldBroadcastClears, excludedClient)
    local id = normalizedCharacterId(characterId)
    if id == nil or state == nil then return end

    if key ~= nil then
        local previousId = activeCharacterIdByClientKey[key] or lastSyncedCharacterByClientKey[key]
        if previousId ~= nil and tonumber(previousId) ~= id then
            clearActiveCharacterId(previousId, shouldBroadcastClears, excludedClient)
        end

        local previousOwnerKey = ownerKeyByCharacterId[id]
        if previousOwnerKey ~= nil and previousOwnerKey ~= key then
            activeLooksByClientKey[previousOwnerKey] = false
            activeCharacterIdByClientKey[previousOwnerKey] = nil
            clearClientSyncState(previousOwnerKey)
            clearActiveCharacterId(id, shouldBroadcastClears, excludedClient)
        end

        activeCharacterIdByClientKey[key] = id
        ownerKeyByCharacterId[id] = key
    end

    savedLooksByCharacterId[id] = state
    activeLooksByCharacterId[id] = true
end

local function broadcastSyncedLookState(key, state, resetAttempts)
    broadcastLookState(state)
    recordSyncAttempt(key, state, resetAttempts)
end

local function syncActiveClientLook(client, force)
    local character = clientCharacter(client)
    local key = clientKey(client)
    if character == nil or key == nil then return end
    local state = savedLooksByClientKey[key]
    if state == nil or activeLooksByClientKey[key] ~= true then return end
    if not savedLookBelongsToCurrentSession(key) then
        activeLooksByClientKey[key] = false
        clearClientSyncState(key)
        return
    end

    local characterId = characterEntityId(character)
    if characterId <= 0 then return end

    local characterState = cloneStateForCharacter(state, character)
    markActiveClientCharacter(key, characterId, characterState, true, nil)

    local signature = lookStateSignature(characterState)
    local sameState =
        lastSyncedCharacterByClientKey[key] == characterId and
        lastSyncedLookSignatureByClientKey[key] == signature
    local lastAttemptTick = lastSyncAttemptTickByClientKey[key] or 0
    local attempts = syncAttemptsByClientKey[key] or 0
    local retryDue =
        sameState and
        attempts < ServerSyncMaxAttempts and
        serverTick - lastAttemptTick >= ServerSyncRetryTicks
    local heartbeatDue =
        sameState and
        serverTick - lastAttemptTick >= ServerSyncHeartbeatTicks

    if sameState and not force and not retryDue and not heartbeatDue then return end

    broadcastSyncedLookState(key, characterState, force or not sameState or heartbeatDue)
end

local function syncAllActiveClientLooks(force)
    for _, client in ipairs(connectedClients()) do
        syncActiveClientLook(client, force == true)
    end
end

local function clearRuntimeActiveLookState()
    savedLooksByCharacterId = {}
    activeLooksByCharacterId = {}
    activeCharacterIdByClientKey = {}
    ownerKeyByCharacterId = {}
    lastSyncedCharacterByClientKey = {}
    lastSyncedLookSignatureByClientKey = {}
    lastSyncAttemptTickByClientKey = {}
    syncAttemptsByClientKey = {}
end

local function deactivatePersistentActiveLooks()
    for key in pairs(activeLooksByClientKey) do
        activeLooksByClientKey[key] = false
    end
end

local function handleServerSessionChange()
    local sessionKey = currentServerSessionKey()
    if sessionKey == nil then return end
    if lastServerSessionKey == nil then
        lastServerSessionKey = sessionKey
        return
    end
    if sessionKey == lastServerSessionKey then return end

    lastServerSessionKey = sessionKey
    clearRuntimeActiveLookState()
    deactivatePersistentActiveLooks()
    persistLooks()
    log("Detected a new game session; deactivated persistent wardrobe looks.")
end

local function sendClearState(client, characterId)
    if client == nil or client.Connection == nil then return end
    local message = Networking.Start(NET_LOOK_CLEAR)
    message.WriteUInt16(characterId or 0)
    Networking.Send(message, client.Connection)
end

broadcastClear = function(characterId, excludedClient)
    if excludedClient == nil then
        local message = Networking.Start(NET_LOOK_CLEAR)
        message.WriteUInt16(characterId or 0)
        Networking.Send(message, nil)
        return
    end

    for _, client in ipairs(connectedClients()) do
        if client ~= excludedClient then
            sendClearState(client, characterId)
        end
    end
end

clientCharacter = function(client)
    if client == nil then return nil end
    local ok, character = pcall(function()
        return client.Character
    end)
    if ok then return character end
    return nil
end

local function deactivateClientLook(client, deleteSaved, excludedClient)
    local character = clientCharacter(client)
    local characterId = characterEntityId(character)
    local key = clientKey(client)
    local clientWasActive = key ~= nil and activeLooksByClientKey[key] == true
    local previousCharacterId = key ~= nil and (activeCharacterIdByClientKey[key] or lastSyncedCharacterByClientKey[key]) or nil
    local characterIds = {}

    if previousCharacterId ~= nil and tonumber(previousCharacterId) ~= nil and tonumber(previousCharacterId) > 0 then
        characterIds[tonumber(previousCharacterId)] = true
    end
    if characterId > 0 then
        characterIds[characterId] = true
    end

    if key ~= nil then
        activeLooksByClientKey[key] = false
        activeCharacterIdByClientKey[key] = nil
        clearClientSyncState(key)
        if deleteSaved then
            savedLooksByClientKey[key] = nil
            savedLookSessionByClientKey[key] = nil
            legacySavedLookByClientKey[key] = nil
        end
    end

    for id in pairs(characterIds) do
        clearActiveCharacterId(id, clientWasActive or deleteSaved or activeLooksByCharacterId[id] == true, excludedClient)
    end

    return characterId, key
end

Networking.Receive(NET_SAVE_REQUEST, function(_, client)
    local character = clientCharacter(client)
    if character == nil then return end

    local state = buildLookState(character)
    if state.characterId <= 0 then return end
    local key = clientKey(client)

    deactivateClientLook(client, false, client)

    if key ~= nil then
        savedLooksByClientKey[key] = cloneStateForCharacter(state, character)
        savedLookSessionByClientKey[key] = currentServerSessionKey()
        legacySavedLookByClientKey[key] = false
        activeLooksByClientKey[key] = false
    else
        savedLooksByCharacterId[state.characterId] = state
        activeLooksByCharacterId[state.characterId] = false
    end

    local processedItems = {}
    local removedItems = 0
    for _, entry in ipairs(slots) do
        local item = getSlotItem(character, entry.slot)
        if item ~= nil and not isIgnoredWardrobeItem(item) and not processedItems[item] then
            processedItems[item] = true
            if unequipItem(character, item) then
                removedItems = removedItems + 1
            end
        end
    end

    log("Saved multiplayer wardrobe for " .. tostring(character.Name) .. "; server removed " .. tostring(removedItems) .. " item(s).")
    persistLooks()
end)

Networking.Receive(NET_APPLY_REQUEST, function(message, client)
    local character = clientCharacter(client)
    if character == nil then return end

    local characterId = characterEntityId(character)
    local key = clientKey(client)
    local payloadState = readApplyLookPayload(message, character)
    local state = payloadState or (key ~= nil and savedLooksByClientKey[key] or savedLooksByCharacterId[characterId])
    if state == nil then return end
    -- Explicit apply requests restore saved looks from any campaign session;
    -- the session gate only limits server-initiated auto-resurrection.

    local characterState = cloneStateForCharacter(state, character)
    markActiveClientCharacter(key, characterId, characterState, true, nil)
    if key ~= nil then
        savedLooksByClientKey[key] = cloneStateForCharacter(state, character)
        if isPersistentClientKey(key) then
            savedLookSessionByClientKey[key] = currentServerSessionKey()
            legacySavedLookByClientKey[key] = false
        else
            savedLookSessionByClientKey[key] = nil
            legacySavedLookByClientKey[key] = nil
        end
        activeLooksByClientKey[key] = true
    end
    broadcastSyncedLookState(key, characterState, true)
    persistLooks()
end)

Networking.Receive(NET_CLEAR_REQUEST, function(_, client)
    deactivateClientLook(client, false, nil)
    persistLooks()
end)

Networking.Receive(NET_FORGET_REQUEST, function(_, client)
    deactivateClientLook(client, true, nil)
    persistLooks()
end)

Hook.Add("client.connected", "barowardrobeswitcher.sync-connected", function(connectedClient)
    local connectedCharacter = clientCharacter(connectedClient)
    local syncedCharacterId = connectedCharacter ~= nil and characterEntityId(connectedCharacter) or nil

    syncActiveClientLook(connectedClient, true)
    syncAllActiveClientLooks(true)

    for characterId, state in pairs(savedLooksByCharacterId) do
        if activeLooksByCharacterId[characterId] == true and characterId ~= syncedCharacterId then
            sendLookState(connectedClient, state)
        end
    end
end)

Hook.Add("roundStart", "barowardrobeswitcher.sync-round-start", function()
    syncAllActiveClientLooks(true)
end)

Hook.Add("roundEnd", "barowardrobeswitcher.server-cleanup", function()
    clearRuntimeActiveLookState()
end)

Hook.Add("think", "barowardrobeswitcher.persistent-sync", function()
    serverTick = serverTick + 1
    handleServerSessionChange()
    syncAllActiveClientLooks(false)
end)

loadPersistentLooks()
log("Server sync loaded. Persistent path: " .. tostring(persistentPath()))
