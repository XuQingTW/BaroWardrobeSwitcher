local MOD_NAME = "Baro Wardrobe Switcher"
local NET_SAVE_REQUEST = "barowardrobeswitcher.save"
local NET_APPLY_REQUEST = "barowardrobeswitcher.apply"
local NET_CLEAR_REQUEST = "barowardrobeswitcher.clear"
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
local lastSyncedCharacterByClientKey = {}
local clientCharacter

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

local function clientKey(client)
    if client == nil then return nil end
    local candidates = {
        function() return client.SteamID end,
        function() return client.AccountId end,
        function() return client.AccountID end,
        function() return client.AccountInfo ~= nil and client.AccountInfo.AccountId or nil end,
        function() return client.Name end
    }
    for _, getter in ipairs(candidates) do
        local ok, value = pcall(getter)
        if ok and value ~= nil and tostring(value) ~= "" then
            return tostring(value)
        end
    end
    return nil
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

local function persistLooks()
    ensurePersistentDirectory()
    local path = persistentPath()
    local file = io.open(path, "w")
    if file == nil then
        log("Could not write persistent wardrobe data to " .. tostring(path) .. ".")
        return
    end
    for key, state in pairs(savedLooksByClientKey) do
        local parts = { "key=" .. escape(key), "active=" .. tostring(activeLooksByClientKey[key] == true) }
        for _, entry in ipairs(slots) do
            local slotState = state.slots[entry.key]
            if slotState ~= nil then
                parts[#parts + 1] = entry.key .. "=" .. escape(slotState.identifier or "") .. "," .. escape(slotState.name or "")
            end
        end
        file:write(table.concat(parts, "|") .. "\n")
    end
    file:close()
end

local function loadPersistentLooksFromPath(path)
    local file = io.open(path, "r")
    if file == nil then return false end
    for line in file:lines() do
        local key = nil
        local state = { characterId = 0, slots = {} }
        local active = false
        for part in tostring(line):gmatch("[^|]+") do
            local name, value = part:match("^([^=]+)=(.*)$")
            if name == "key" then
                key = unescape(value)
            elseif name == "active" then
                active = value == "true"
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
        if key ~= nil and key ~= "" then
            savedLooksByClientKey[key] = state
            activeLooksByClientKey[key] = active
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

local function syncActiveClientLook(client)
    local character = clientCharacter(client)
    local key = clientKey(client)
    if character == nil or key == nil then return end
    local state = savedLooksByClientKey[key]
    if state == nil or activeLooksByClientKey[key] ~= true then return end

    local characterId = characterEntityId(character)
    if characterId <= 0 or lastSyncedCharacterByClientKey[key] == characterId then return end

    local characterState = cloneStateForCharacter(state, character)
    savedLooksByCharacterId[characterId] = characterState
    activeLooksByCharacterId[characterId] = true
    lastSyncedCharacterByClientKey[key] = characterId
    broadcastLookState(characterState)
end

local function broadcastClear(characterId)
    local message = Networking.Start(NET_LOOK_CLEAR)
    message.WriteUInt16(characterId or 0)
    Networking.Send(message, nil)
end

clientCharacter = function(client)
    if client == nil then return nil end
    local ok, character = pcall(function()
        return client.Character
    end)
    if ok then return character end
    return nil
end

Networking.Receive(NET_SAVE_REQUEST, function(_, client)
    local character = clientCharacter(client)
    if character == nil then return end

    local state = buildLookState(character)
    if state.characterId <= 0 then return end
    local key = clientKey(client)

    savedLooksByCharacterId[state.characterId] = state
    activeLooksByCharacterId[state.characterId] = false
    if key ~= nil then
        savedLooksByClientKey[key] = cloneStateForCharacter(state, character)
        activeLooksByClientKey[key] = false
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

Networking.Receive(NET_APPLY_REQUEST, function(_, client)
    local character = clientCharacter(client)
    if character == nil then return end

    local characterId = characterEntityId(character)
    local key = clientKey(client)
    local state = savedLooksByCharacterId[characterId]
    if state == nil and key ~= nil then
        state = savedLooksByClientKey[key]
    end
    if state == nil then return end

    local characterState = cloneStateForCharacter(state, character)
    savedLooksByCharacterId[characterId] = characterState
    activeLooksByCharacterId[characterId] = true
    if key ~= nil then
        savedLooksByClientKey[key] = state
        activeLooksByClientKey[key] = true
    end
    broadcastLookState(characterState)
    persistLooks()
end)

Networking.Receive(NET_CLEAR_REQUEST, function(_, client)
    local character = clientCharacter(client)
    if character == nil then return end

    local characterId = characterEntityId(character)
    local key = clientKey(client)
    activeLooksByCharacterId[characterId] = false
    if key ~= nil then
        activeLooksByClientKey[key] = false
    end
    broadcastClear(characterId)
    persistLooks()
end)

Hook.Add("client.connected", "barowardrobeswitcher.sync-connected", function(connectedClient)
    local connectedCharacter = clientCharacter(connectedClient)
    local key = clientKey(connectedClient)
    local syncedCharacterId = nil
    if connectedCharacter ~= nil and key ~= nil and savedLooksByClientKey[key] ~= nil and activeLooksByClientKey[key] == true then
        local state = cloneStateForCharacter(savedLooksByClientKey[key], connectedCharacter)
        savedLooksByCharacterId[state.characterId] = state
        activeLooksByCharacterId[state.characterId] = true
        lastSyncedCharacterByClientKey[key] = state.characterId
        syncedCharacterId = state.characterId
        broadcastLookState(state)
    end
    for characterId, state in pairs(savedLooksByCharacterId) do
        if activeLooksByCharacterId[characterId] == true and characterId ~= syncedCharacterId then
            sendLookState(connectedClient, state)
        end
    end
end)

Hook.Add("roundEnd", "barowardrobeswitcher.server-cleanup", function()
    savedLooksByCharacterId = {}
    activeLooksByCharacterId = {}
    lastSyncedCharacterByClientKey = {}
end)

Hook.Add("think", "barowardrobeswitcher.persistent-sync", function()
    if Client == nil or Client.ClientList == nil then return end
    local ok = pcall(function()
        for client in Client.ClientList do
            syncActiveClientLook(client)
        end
    end)
    if ok then return end
    pcall(function()
        for _, client in pairs(Client.ClientList) do
            syncActiveClientLook(client)
        end
    end)
end)

loadPersistentLooks()
log("Server sync loaded. Persistent path: " .. tostring(persistentPath()))
