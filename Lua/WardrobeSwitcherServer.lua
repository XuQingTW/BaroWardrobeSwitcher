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

local function log(message)
    local line = "[" .. MOD_NAME .. "] " .. tostring(message)
    if LuaCsLogger ~= nil and LuaCsLogger.Log ~= nil then
        LuaCsLogger.Log(line)
    else
        print(line)
    end
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

local function broadcastClear(characterId)
    local message = Networking.Start(NET_LOOK_CLEAR)
    message.WriteUInt16(characterId or 0)
    Networking.Send(message, nil)
end

local function clientCharacter(client)
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

    savedLooksByCharacterId[state.characterId] = state
    activeLooksByCharacterId[state.characterId] = false

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
end)

Networking.Receive(NET_APPLY_REQUEST, function(_, client)
    local character = clientCharacter(client)
    if character == nil then return end

    local characterId = characterEntityId(character)
    local state = savedLooksByCharacterId[characterId]
    if state == nil then return end

    activeLooksByCharacterId[characterId] = true
    broadcastLookState(state)
end)

Networking.Receive(NET_CLEAR_REQUEST, function(_, client)
    local character = clientCharacter(client)
    if character == nil then return end

    local characterId = characterEntityId(character)
    activeLooksByCharacterId[characterId] = false
    broadcastClear(characterId)
end)

Hook.Add("client.connected", "barowardrobeswitcher.sync-connected", function(connectedClient)
    for characterId, state in pairs(savedLooksByCharacterId) do
        if activeLooksByCharacterId[characterId] == true then
            sendLookState(connectedClient, state)
        end
    end
end)

Hook.Add("roundEnd", "barowardrobeswitcher.server-cleanup", function()
    savedLooksByCharacterId = {}
    activeLooksByCharacterId = {}
end)

log("Server sync loaded.")
