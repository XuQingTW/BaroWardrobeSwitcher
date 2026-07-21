-- Black-box contract tests for the event-driven server authority adapter.
local function candidates(relative)
    local result = { relative, "../" .. relative, "../../" .. relative }
    if debug ~= nil and debug.getinfo ~= nil then
        local source = debug.getinfo(1, "S").source
        local file = source:sub(1, 1) == "@" and source:sub(2) or source
        local directory = file:match("^(.*[/\\])") or ""
        table.insert(result, 1, directory .. "../../" .. relative)
    end
    return result
end

local function loadFirst(paths, requireTable)
    for _, path in ipairs(paths) do
        local ok, value = pcall(dofile, path)
        if ok and (not requireTable or type(value) == "table") then return value end
    end
    error("could not load " .. tostring(paths[1]))
end

local Core = loadFirst(candidates("Lua/WardrobeCore.lua"), true)

SERVER = true
InvSlotType = {
    Head = 1,
    Headset = 2,
    InnerClothes = 3,
    OuterClothes = 4,
    Bag = 5,
    HealthInterface = 6
}
local connectedClients = {}
local memoryFiles = {}
local failReplace = false
local failOverwriteMove = false
local storageRoot = "/local/Daedalic Entertainment GmbH/Barotrauma/ModData/BaroWardrobeSwitcher"
local MemoryFile = {
    Exists = function(path) return memoryFiles[tostring(path)] ~= nil end,
    ReadAllText = function(path)
        local value = memoryFiles[tostring(path)]
        if value == nil then error("file not found") end
        return value
    end,
    WriteAllText = function(path, value) memoryFiles[tostring(path)] = tostring(value) end,
    AppendAllText = function(path, value)
        path = tostring(path)
        memoryFiles[path] = tostring(memoryFiles[path] or "") .. tostring(value)
    end,
    Delete = function(path) memoryFiles[tostring(path)] = nil end,
    Copy = function(source, destination, overwrite)
        source, destination = tostring(source), tostring(destination)
        if memoryFiles[source] == nil then error("source missing") end
        if memoryFiles[destination] ~= nil and overwrite ~= true then error("destination exists") end
        memoryFiles[destination] = memoryFiles[source]
    end,
    Move = function(source, destination, overwrite)
        source, destination = tostring(source), tostring(destination)
        if memoryFiles[source] == nil then error("source missing") end
        if memoryFiles[destination] ~= nil then
            if overwrite ~= true then error("destination exists") end
            if failOverwriteMove then error("synthetic overwrite failure") end
        end
        memoryFiles[destination] = memoryFiles[source]
        memoryFiles[source] = nil
    end,
    Replace = function(source, destination, backup)
        source, destination, backup = tostring(source), tostring(destination), tostring(backup)
        if failReplace then error("synthetic replace failure") end
        if memoryFiles[source] == nil or memoryFiles[destination] == nil then error("replace input missing") end
        memoryFiles[backup] = memoryFiles[destination]
        memoryFiles[destination] = memoryFiles[source]
        memoryFiles[source] = nil
    end
}
local fakeWearableElement = {
    GetAttributeString = function(name, defaultValue)
        if tostring(name):lower() == "slots" then return "Head" end
        return defaultValue
    end
}
local fakeHelmetPrefab = {
    Identifier = "helmet",
    Name = "Canonical Helmet",
    ConfigElement = {
        GetChildElement = function(name)
            if tostring(name):lower() == "wearable" then return fakeWearableElement end
            return nil
        end
    }
}
LuaUserData = {
    CreateStatic = function(name)
        if name == "Barotrauma.ItemPrefab" then
            return { Prefabs = { helmet = fakeHelmetPrefab } }
        end
        if name == "Barotrauma.Networking.Client" then
            return { ClientList = connectedClients }
        end
        if name == "System.Environment" then
            return { GetFolderPath = function() return "/local" end }
        end
        if name == "System.IO.Directory" then
            return { CreateDirectory = function() return true end }
        end
        if name == "System.IO.File" then return MemoryFile end
        return nil
    end
}
LuaCsLogger = { Log = function() end, LogError = function() end }

local function newBuffer(name)
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
        local entry = values[readIndex]
        assert(entry ~= nil, "read beyond test buffer")
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
    handlers = {},
    sent = {},
    Receive = function(name, handler) Networking.handlers[name] = handler end,
    Start = function(name) return newBuffer(name) end,
    Send = function(message, connection)
        message.FinalizeForTransport()
        Networking.sent[#Networking.sent + 1] = { message = message, connection = connection }
    end
}
Hook = {
    handlers = {},
    Add = function(name, _, handler) Hook.handlers[name] = handler end
}

loadFirst(candidates("Lua/WardrobeSwitcherServer.lua"), false)
local serverLogPath = storageRoot .. "/WardrobeServer.log"
assert(memoryFiles[serverLogPath] ~= nil and
       memoryFiles[serverLogPath]:find("Server authority", 1, true) ~= nil,
    "server diagnostics were not written to the dedicated file log")

local handlerCount = 0
for _ in pairs(Networking.handlers) do handlerCount = handlerCount + 1 end
assert(handlerCount == 6, "server must register four v1 and two v2 receivers")
assert(Hook.handlers.think == nil, "server authority must not install a think heartbeat")

local client = { Connection = {}, Character = { ID = 42, Name = "Tester" } }
connectedClients[1] = client
local hello = newBuffer()
assert(Core.writeClientHello(hello, "client-session"))
Networking.handlers[Core.NET.V2_HELLO](hello, client)
local serverHello = assert(Core.readServerHello(Networking.sent[#Networking.sent].message))
assert(serverHello.revision == 0)

local function sendCommand(command, targetClient)
    targetClient = targetClient or client
    local message = newBuffer()
    assert(Core.writeCommand(message, command))
    message.FinalizeForTransport()
    Networking.handlers[Core.NET.V2_COMMAND](message, targetClient)
    local sent = Networking.sent[#Networking.sent]
    assert(sent.message.name == Core.NET.V2_ACK)
    return assert(Core.readAck(sent.message))
end

local function lastSentMessage(name, connection)
    for index = #Networking.sent, 1, -1 do
        local sent = Networking.sent[index]
        if sent.message.name == name and
            (connection == nil or sent.connection == connection) then
            return sent.message
        end
    end
    return nil
end

local clear = {
    clientSessionId = "client-session",
    operationId = "op-clear",
    baseRevision = 0,
    kind = Core.COMMAND.Clear
}
local first = sendCommand(clear)
assert(first.accepted and first.revision == 1)
local duplicate = sendCommand(clear)
assert(duplicate.accepted and duplicate.revision == 1, "duplicate command must be idempotent")

local malformedLook = newBuffer()
malformedLook.WriteUInt16(Core.PROTOCOL_VERSION)
malformedLook.WriteString("client-session")
malformedLook.WriteString("op-malformed-look")
malformedLook.WriteUInt32(1)
malformedLook.WriteString(Core.COMMAND.Save)
malformedLook.WriteBoolean(true)
malformedLook.WriteUInt16(99)
Networking.handlers[Core.NET.V2_COMMAND](malformedLook, client)
local malformedAck = assert(Core.readAck(Networking.sent[#Networking.sent].message))
assert(not malformedAck.accepted and malformedAck.reason == "malformed_look" and malformedAck.revision == 1,
    "a declared but invalid v2 look must be rejected without changing revision")

local canonicalApply = sendCommand({
    clientSessionId = "client-session",
    operationId = "op-canonical-apply",
    baseRevision = 1,
    kind = Core.COMMAND.Apply,
    look = assert(Core.newLook(true, true, { Head = "helmet" }))
})
assert(canonicalApply.accepted and canonicalApply.revision == 2,
    "server must accept a valid wearable identifier for its declared slot")

local canonicalStateMessage = Networking.sent[#Networking.sent - 1].message
assert(canonicalStateMessage.name == Core.NET.V2_STATE, "apply must broadcast canonical state before its ack")
local canonicalState = assert(Core.readState(canonicalStateMessage))
assert(canonicalState.active and canonicalState.look.slots.Head == "helmet" and canonicalState.look.hideHair,
    "server canonical state must retain only the stable identifier and user intent")

local clearAfterApply = sendCommand({
    clientSessionId = "client-session",
    operationId = "op-clear-after-apply",
    baseRevision = 2,
    kind = Core.COMMAND.Clear
})
assert(clearAfterApply.accepted and clearAfterApply.revision == 3)

local storedApply = sendCommand({
    clientSessionId = "client-session",
    operationId = "op-stored-apply",
    baseRevision = 3,
    kind = Core.COMMAND.Apply
})
assert(storedApply.accepted and storedApply.revision == 4,
    "apply without an imported look must use the canonical server-stored look")

local respawnedCharacter = { ID = 43, Name = "Tester Respawned" }
client.Character = respawnedCharacter
local beforeCharacterRebind = #Networking.sent
Hook.handlers["character.created"](respawnedCharacter)
assert(#Networking.sent > beforeCharacterRebind,
    "an active session must publish state when its client receives a replacement character")
local reboundState = assert(Core.readState(Networking.sent[#Networking.sent].message))
assert(reboundState.active and reboundState.revision == 4 and reboundState.characterId == 43,
    "character replacement must rebind the active look without changing revision")

-- A slower client can finish loading after round start missed another active
-- player's Character assignment. Its hello must rebuild the authoritative
-- runtime entry and return that player's saved active look with the new ID.
do
    Hook.handlers.roundEnd()
    client.Character = nil
    Hook.handlers.roundStart()
    client.Character = { ID = 143, Name = "Tester Next Round" }
    local lateClient = { Connection = {}, Character = { ID = 144, Name = "Late Player" } }
    connectedClients[2] = lateClient
    local sentBeforeLateHello = #Networking.sent
    local lateHello = newBuffer()
    assert(Core.writeClientHello(lateHello, "late-client-session"))
    Networking.handlers[Core.NET.V2_HELLO](lateHello, lateClient)
    local lateStates = {}
    for index = sentBeforeLateHello + 1, #Networking.sent do
        local sent = Networking.sent[index]
        if sent.connection == lateClient.Connection and sent.message.name == Core.NET.V2_STATE then
            lateStates[#lateStates + 1] = assert(Core.readState(sent.message))
        end
    end
    assert(#lateStates == 1, "a player without a saved look received an unexpected own state")
    local lateSnapshot = lateStates[1]
    assert(lateSnapshot.active and lateSnapshot.revision == 4 and
        lateSnapshot.characterId == 143 and lateSnapshot.look.slots.Head == "helmet",
        "a late client did not receive the active next-round wardrobe snapshot")

    local sentBeforeOwnHello = #Networking.sent
    local ownHello = newBuffer()
    assert(Core.writeClientHello(ownHello, "client-session"))
    Networking.handlers[Core.NET.V2_HELLO](ownHello, client)
    local ownSnapshot = nil
    for index = sentBeforeOwnHello + 1, #Networking.sent do
        local sent = Networking.sent[index]
        if sent.connection == client.Connection and sent.message.name == Core.NET.V2_STATE then
            local state = assert(Core.readState(sent.message))
            if state.characterId == 143 then ownSnapshot = state end
        end
    end
    assert(ownSnapshot ~= nil and ownSnapshot.active and ownSnapshot.revision == 4,
        "a ready client did not receive its own saved active wardrobe snapshot")

    local lateApply = sendCommand({
        clientSessionId = "late-client-session",
        operationId = "late-client-apply",
        baseRevision = 0,
        kind = Core.COMMAND.Apply,
        look = assert(Core.newLook(true, false, { Head = "helmet" }))
    }, lateClient)
    assert(lateApply.accepted and lateApply.revision == 1)

    local sentBeforeReadyHello = #Networking.sent
    local readyHello = newBuffer()
    assert(Core.writeClientHello(readyHello, "late-client-session"))
    Networking.handlers[Core.NET.V2_HELLO](readyHello, lateClient)
    local announcedToExistingClient = nil
    for index = sentBeforeReadyHello + 1, #Networking.sent do
        local sent = Networking.sent[index]
        if sent.connection == client.Connection and sent.message.name == Core.NET.V2_STATE then
            local state = assert(Core.readState(sent.message))
            if state.characterId == 144 then announcedToExistingClient = state end
        end
    end
    assert(announcedToExistingClient ~= nil and announcedToExistingClient.active and
        announcedToExistingClient.revision == 1 and
        announcedToExistingClient.look.slots.Head == "helmet",
        "a ready late client did not reannounce its active look to an existing client")

    Hook.handlers["client.disconnected"](lateClient)
    connectedClients[2] = nil
end

local clearStoredApply = sendCommand({
    clientSessionId = "client-session",
    operationId = "op-clear-stored-apply",
    baseRevision = 4,
    kind = Core.COMMAND.Clear
})
assert(clearStoredApply.accepted and clearStoredApply.revision == 5)

do
    local observer = { Connection = {}, Character = { ID = 145, Name = "Inactive Observer" } }
    connectedClients[2] = observer
    local sentBeforeObserverHello = #Networking.sent
    local observerHello = newBuffer()
    assert(Core.writeClientHello(observerHello, "inactive-observer-session"))
    Networking.handlers[Core.NET.V2_HELLO](observerHello, observer)
    for index = sentBeforeObserverHello + 1, #Networking.sent do
        local sent = Networking.sent[index]
        assert(sent.connection ~= observer.Connection or sent.message.name ~= Core.NET.V2_STATE,
            "a saved-but-cleared look was incorrectly activated for another client")
    end
    connectedClients[2] = nil
end

local look = assert(Core.newLook(true, false, { Head = "helmet" }))
local stale = sendCommand({
    clientSessionId = "client-session",
    operationId = "op-late-apply",
    baseRevision = 4,
    kind = Core.COMMAND.Apply,
    look = look
})
assert(not stale.accepted and stale.reason == "stale_revision" and stale.revision == 5,
    "clear must win over a late apply")

local malformed = newBuffer()
malformed.WriteUInt16(Core.PROTOCOL_VERSION)
malformed.WriteString("client-session")
malformed.WriteString("op-malformed")
malformed.WriteUInt32(5)
malformed.WriteString(Core.COMMAND.Apply)
malformed.WriteBoolean(true)
malformed.WriteUInt16(Core.LOOK_SCHEMA_VERSION)
malformed.WriteBoolean(true)
malformed.WriteBoolean(false)
malformed.WriteUInt16(1)
malformed.WriteString("Unknown")
malformed.WriteString("x")
Networking.handlers[Core.NET.V2_COMMAND](malformed, client)
local rejected = assert(Core.readAck(Networking.sent[#Networking.sent].message))
assert(not rejected.accepted and rejected.reason == "malformed_look" and rejected.revision == 5)

local oversized = newBuffer()
oversized.WriteUInt16(Core.PROTOCOL_VERSION)
oversized.WriteString("client-session")
oversized.WriteString("op-oversized")
oversized.WriteUInt32(5)
oversized.WriteString(Core.COMMAND.Apply)
oversized.WriteBoolean(true)
oversized.WriteUInt16(Core.LOOK_SCHEMA_VERSION)
oversized.WriteBoolean(true)
oversized.WriteBoolean(false)
oversized.WriteUInt16(1)
oversized.WriteString("Head")
oversized.WriteString(string.rep("x", Core.LIMITS.MAX_IDENTIFIER_BYTES + 1))
Networking.handlers[Core.NET.V2_COMMAND](oversized, client)
local oversizedAck = assert(Core.readAck(Networking.sent[#Networking.sent].message))
assert(not oversizedAck.accepted and oversizedAck.reason == "malformed_look" and oversizedAck.revision == 5)

local hardOversized = newBuffer()
hardOversized.LengthBytes = Core.LIMITS.MAX_PAYLOAD_BYTES + 1
local sentBeforeHardLimit = #Networking.sent
Networking.handlers[Core.NET.V2_COMMAND](hardOversized, client)
assert(#Networking.sent == sentBeforeHardLimit,
    "a command over the wire-size limit must be rejected before any state or ack mutation")
local afterHardLimit = sendCommand({
    clientSessionId = "client-session",
    operationId = "op-after-hard-limit",
    baseRevision = 5,
    kind = Core.COMMAND.Apply
})
assert(afterHardLimit.accepted and afterHardLimit.revision == 6,
    "oversized rejection must leave the previous revision unchanged")

local beforeLegacyDowngrade = #Networking.sent
Networking.handlers[Core.NET.V1_CLEAR_REQUEST](newBuffer(), client)
assert(#Networking.sent == beforeLegacyDowngrade,
    "a connection that negotiated v2 must not downgrade through a legacy command")
local afterDowngradeAttempt = sendCommand({
    clientSessionId = "client-session",
    operationId = "op-after-downgrade-attempt",
    baseRevision = 6,
    kind = Core.COMMAND.Apply
})
assert(afterDowngradeAttempt.accepted and afterDowngradeAttempt.revision == 7,
    "ignored v1 downgrade must not mutate the v2 session revision")

local visibilityClient = {
    Connection = {},
    Character = { ID = 74, Name = "Visibility" }
}
connectedClients[#connectedClients + 1] = visibilityClient
local visibilityHello = newBuffer()
assert(Core.writeClientHello(visibilityHello, "visibility-session"))
Networking.handlers[Core.NET.V2_HELLO](visibilityHello, visibilityClient)
local visibilityServerHello =
    assert(Core.readServerHello(lastSentMessage(Core.NET.V2_HELLO, visibilityClient.Connection)))
assert(visibilityServerHello.capabilities == Core.CAPABILITY.AttachmentVisibility,
    "new server hello must advertise full attachment visibility synchronization")

local visibilityApply = sendCommand({
    clientSessionId = "visibility-session",
    operationId = "visibility-apply",
    baseRevision = 0,
    kind = Core.COMMAND.Apply,
    look = assert(Core.newLook(true, false, { Head = "helmet" }))
}, visibilityClient)
assert(visibilityApply.accepted and visibilityApply.revision == 1)

local requestedVisibility = {
    Hair = "show",
    Beard = "hide",
    Moustache = "auto",
    FaceAttachment = "show"
}
local visibilityAck = sendCommand({
    clientSessionId = "visibility-session",
    operationId = "visibility-active-update",
    baseRevision = 1,
    kind = Core.COMMAND.Visibility,
    -- This identifier is intentionally invalid. The visibility command must
    -- ignore all client-supplied equipment slots and merge only the four-layer policy.
    look = assert(Core.newLook(true, false, { Head = "not-a-real-prefab" }, requestedVisibility))
}, visibilityClient)
assert(visibilityAck.accepted and visibilityAck.revision == 2)
local activeVisibilityState = assert(Core.readState(
    lastSentMessage(Core.NET.V2_STATE, visibilityClient.Connection)))
assert(activeVisibilityState.active and
       activeVisibilityState.look.slots.Head == "helmet" and
       activeVisibilityState.look.attachmentVisibility.Hair == "show" and
       activeVisibilityState.look.attachmentVisibility.Beard == "hide" and
       activeVisibilityState.look.attachmentVisibility.FaceAttachment == "show",
    "visibility command must retain authoritative slots and broadcast the merged active policy")

local visibilityClear = sendCommand({
    clientSessionId = "visibility-session",
    operationId = "visibility-clear",
    baseRevision = 2,
    kind = Core.COMMAND.Clear
}, visibilityClient)
assert(visibilityClear.accepted and visibilityClear.revision == 3)
local inactiveVisibilityAck = sendCommand({
    clientSessionId = "visibility-session",
    operationId = "visibility-inactive-update",
    baseRevision = 3,
    kind = Core.COMMAND.Visibility,
    look = assert(Core.newLook(
        true,
        false,
        { Head = "also-not-authoritative" },
        Core.attachmentVisibilityFromLegacy(false)
    ))
}, visibilityClient)
assert(inactiveVisibilityAck.accepted and inactiveVisibilityAck.revision == 4)
local inactiveVisibilityState = assert(Core.readState(
    lastSentMessage(Core.NET.V2_STATE, visibilityClient.Connection)))
assert(not inactiveVisibilityState.active and
       inactiveVisibilityState.look.slots.Head == "helmet" and
       inactiveVisibilityState.look.attachmentVisibility.Hair == "auto",
    "inactive visibility command must return the updated authoritative saved look")

local overlappingVisibility = newBuffer()
overlappingVisibility.WriteUInt16(Core.PROTOCOL_VERSION)
overlappingVisibility.WriteString("visibility-session")
overlappingVisibility.WriteString("visibility-overlap")
overlappingVisibility.WriteUInt32(4)
overlappingVisibility.WriteString(Core.COMMAND.Visibility)
overlappingVisibility.WriteBoolean(true)
overlappingVisibility.WriteUInt16(Core.LOOK_SCHEMA_VERSION)
overlappingVisibility.WriteBoolean(true)
overlappingVisibility.WriteBoolean(false)
overlappingVisibility.WriteUInt16(0)
overlappingVisibility.WriteByte(Core.LOOK_EXTENSION_MARKER)
overlappingVisibility.WriteByte(Core.LOOK_EXTENSION_VERSION)
overlappingVisibility.WriteByte(0x01)
overlappingVisibility.WriteByte(0x01)
Networking.handlers[Core.NET.V2_COMMAND](overlappingVisibility, visibilityClient)
local overlappingVisibilityAck =
    assert(Core.readAck(Networking.sent[#Networking.sent].message))
assert(not overlappingVisibilityAck.accepted and
       overlappingVisibilityAck.reason == "malformed_look" and
       overlappingVisibilityAck.revision == 4,
    "overlapping visibility masks must be rejected without changing revision")

local noLookClient = {
    Connection = {},
    Character = { ID = 73, Name = "No Look" }
}
connectedClients[#connectedClients + 1] = noLookClient
local noLookHello = newBuffer()
assert(Core.writeClientHello(noLookHello, "no-look-session"))
Networking.handlers[Core.NET.V2_HELLO](noLookHello, noLookClient)
local noLookVisibility = sendCommand({
    clientSessionId = "no-look-session",
    operationId = "visibility-without-look",
    baseRevision = 0,
    kind = Core.COMMAND.Visibility,
    look = assert(Core.newLook(true, false, {}, requestedVisibility))
}, noLookClient)
assert(not noLookVisibility.accepted and noLookVisibility.reason == "look_unavailable",
    "visibility command must not create an authoritative look from client-supplied slots")

local limitedClient = { Connection = {}, Character = { ID = 75, Name = "Limited" } }
connectedClients[#connectedClients + 1] = limitedClient
local limitedHello = newBuffer()
assert(Core.writeClientHello(limitedHello, "limited-session"))
Networking.handlers[Core.NET.V2_HELLO](limitedHello, limitedClient)
for index = 1, Core.LIMITS.MAX_SEEN_OPERATIONS do
    local limitedResult = sendCommand({
        clientSessionId = "limited-session",
        operationId = "limited-" .. tostring(index),
        baseRevision = 1,
        kind = Core.COMMAND.Apply
    }, limitedClient)
    assert(not limitedResult.accepted and limitedResult.reason == "stale_revision" and limitedResult.revision == 0)
end
local operationLimit = sendCommand({
    clientSessionId = "limited-session",
    operationId = "limited-overflow",
    baseRevision = 0,
    kind = Core.COMMAND.Clear
}, limitedClient)
assert(not operationLimit.accepted and operationLimit.reason == "operation_limit_reached" and
       operationLimit.revision == 0,
    "a full dedupe cache must reject unknown operations without mutation")
local repeatedOperationLimit = sendCommand({
    clientSessionId = "limited-session",
    operationId = "limited-overflow",
    baseRevision = 0,
    kind = Core.COMMAND.Clear
}, limitedClient)
assert(not repeatedOperationLimit.accepted and repeatedOperationLimit.reason == operationLimit.reason and
       repeatedOperationLimit.revision == operationLimit.revision,
    "operation-limit rejection must itself be stable across retries")
local oldDuplicateAfterLimit = sendCommand({
    clientSessionId = "limited-session",
    operationId = "limited-1",
    baseRevision = 1,
    kind = Core.COMMAND.Apply
}, limitedClient)
assert(not oldDuplicateAfterLimit.accepted and oldDuplicateAfterLimit.reason == "stale_revision" and
       oldDuplicateAfterLimit.revision == 0,
    "filling the dedupe cache must not evict an earlier operation result")

local legacyClient = { Connection = {}, Character = { ID = 77, Name = "Legacy" } }
connectedClients[2] = legacyClient
Networking.handlers[Core.NET.V1_SAVE_REQUEST](newBuffer(), legacyClient)
local legacyApply = newBuffer()
legacyApply.WriteBoolean(false) -- v1 bridge selects the server-stored captured look
Networking.handlers[Core.NET.V1_APPLY_REQUEST](legacyApply, legacyClient)
local legacyState = assert(lastSentMessage(Core.NET.V1_LOOK_APPLY, legacyClient.Connection))
assert(legacyState.name == Core.NET.V1_LOOK_APPLY, "v1 client must receive the original look.apply message")
assert(legacyState.ReadUInt16() == 77)
for _ = 1, #Core.SLOT_KEYS do assert(legacyState.ReadBoolean() == false) end

Networking.handlers[Core.NET.V1_CLEAR_REQUEST](newBuffer(), legacyClient)
local legacyClear = assert(lastSentMessage(Core.NET.V1_LOOK_CLEAR, legacyClient.Connection))
assert(legacyClear.name == Core.NET.V1_LOOK_CLEAR and legacyClear.ReadUInt16() == 77,
    "v1 clear must keep its original wire layout")

local stuckItem = {
    Prefab = fakeHelmetPrefab,
    Unequip = function() end,
    Drop = function() end,
    Equip = function() end
}
local stuckSlots = { [InvSlotType.Head] = stuckItem }
local stuckClient = {
    Connection = {},
    Character = {
        ID = 78,
        Name = "Stuck",
        Inventory = {
            GetItemInLimbSlot = function(slot) return stuckSlots[slot] end,
            IsInLimbSlot = function(item, slot) return stuckSlots[slot] == item end
        }
    }
}
connectedClients[#connectedClients + 1] = stuckClient
local stuckHello = newBuffer()
assert(Core.writeClientHello(stuckHello, "stuck-session"))
Networking.handlers[Core.NET.V2_HELLO](stuckHello, stuckClient)
local stuckSave = sendCommand({
    clientSessionId = "stuck-session",
    operationId = "stuck-save",
    baseRevision = 0,
    kind = Core.COMMAND.Save
}, stuckClient)
assert(not stuckSave.accepted and stuckSave.reason == "unequip_failed" and stuckSave.revision == 0,
    "a failed authoritative unequip must reject Save without advancing revision")
assert(stuckSlots[InvSlotType.Head] == stuckItem,
    "a failed authoritative unequip must preserve the equipped item")

local stableAccount = { StringRepresentation = "stable-account" }
local stableClient = {
    Connection = {},
    Character = { ID = 88, Name = "Stable" },
    AccountId = {
        IsSome = function() return true end,
        TryUnwrap = function() return true, stableAccount end
    }
}
connectedClients[3] = stableClient
local stableHello = newBuffer()
assert(Core.writeClientHello(stableHello, "stable-session"))
Networking.handlers[Core.NET.V2_HELLO](stableHello, stableClient)

local stableSave = sendCommand({
    clientSessionId = "stable-session",
    operationId = "stable-save",
    baseRevision = 0,
    kind = Core.COMMAND.Save
}, stableClient)
assert(stableSave.accepted and stableSave.revision == 1)
local serverJsonPath = storageRoot .. "/ServerLooks.json"
local persistedAfterSave = assert(memoryFiles[serverJsonPath])
assert(persistedAfterSave:find('{"schemaVersion":3', 1, true) == 1)
assert(persistedAfterSave:find('"attachmentVisibility"', 1, true) ~= nil and
       persistedAfterSave:find('"hideHair"', 1, true) == nil,
    "server persistence v3 must store the complete visibility policy without authoritative hideHair")
assert(persistedAfterSave:find('"accountId":"stable-account"', 1, true) ~= nil,
    "stable AccountId must be the persistence key")
assert(persistedAfterSave:find('"itemId"', 1, true) == nil and persistedAfterSave:find('"name"', 1, true) == nil,
    "server persistence must not contain runtime ids or display names")

Hook.handlers["client.disconnected"](stableClient)
local stableReconnected = {
    Connection = {},
    Character = { ID = 89, Name = "Stable Reconnected" },
    AccountId = stableClient.AccountId
}
connectedClients[3] = stableReconnected
local reconnectHello = newBuffer()
assert(Core.writeClientHello(reconnectHello, "stable-session"))
local beforeReconnectHello = #Networking.sent
Networking.handlers[Core.NET.V2_HELLO](reconnectHello, stableReconnected)
local reconnectResponse = assert(Core.readServerHello(Networking.sent[beforeReconnectHello + 1].message))
assert(reconnectResponse.revision == 1)

local duplicateAfterReconnect = newBuffer()
assert(Core.writeCommand(duplicateAfterReconnect, {
    clientSessionId = "stable-session",
    operationId = "stable-save",
    baseRevision = 0,
    kind = Core.COMMAND.Save
}))
local beforeReconnectDuplicate = #Networking.sent
Networking.handlers[Core.NET.V2_COMMAND](duplicateAfterReconnect, stableReconnected)
local reconnectDuplicateAck = assert(Core.readAck(Networking.sent[beforeReconnectDuplicate + 1].message))
assert(reconnectDuplicateAck.accepted and reconnectDuplicateAck.revision == 1,
    "a stable account reconnecting with the same client session must receive the original operation result")

failReplace = true
failOverwriteMove = true
local failedClear = sendCommand({
    clientSessionId = "stable-session",
    operationId = "stable-clear-fails",
    baseRevision = 1,
    kind = Core.COMMAND.Clear
}, stableReconnected)
assert(not failedClear.accepted and failedClear.reason == "persistence_failed" and failedClear.revision == 1)
assert(memoryFiles[serverJsonPath] == persistedAfterSave,
    "atomic replacement failure must preserve the prior server document")
failReplace = false
failOverwriteMove = false

local stableForget = sendCommand({
    clientSessionId = "stable-session",
    operationId = "stable-forget",
    baseRevision = 1,
    kind = Core.COMMAND.Forget
}, stableReconnected)
assert(stableForget.accepted and stableForget.revision == 2)
assert(memoryFiles[serverJsonPath]:find("stable-account", 1, true) == nil)

local beforeAnonymousSave = memoryFiles[serverJsonPath]
local anonymousClient = { Connection = {}, Character = { ID = 99, Name = "Anonymous" } }
connectedClients[4] = anonymousClient
local anonymousHello = newBuffer()
assert(Core.writeClientHello(anonymousHello, "anonymous-session"))
Networking.handlers[Core.NET.V2_HELLO](anonymousHello, anonymousClient)
local anonymousSave = sendCommand({
    clientSessionId = "anonymous-session",
    operationId = "anonymous-save",
    baseRevision = 0,
    kind = Core.COMMAND.Save
}, anonymousClient)
assert(anonymousSave.accepted)
assert(memoryFiles[serverJsonPath] == beforeAnonymousSave,
    "anonymous session state must not cause a persistence write")

memoryFiles[storageRoot .. "/ServerLooks.txt.v1.bak"] =
    "key=account:stable-account|active=false|Head=helmet,Old Helmet\n"
loadFirst(candidates("Lua/WardrobeSwitcherServer.lua"), false)
local reloadedHello = newBuffer()
assert(Core.writeClientHello(reloadedHello, "stable-session-reloaded"))
Networking.handlers[Core.NET.V2_HELLO](reloadedHello, stableClient)
local reloadedState = assert(Core.readServerHello(Networking.sent[#Networking.sent].message))
assert(reloadedState.revision == 0,
    "a retained v1 backup must not resurrect a forgotten look when valid current persistence exists")

memoryFiles[serverJsonPath] = '{"schemaVersion":2,"records":['
memoryFiles[storageRoot .. "/ServerLooks.txt"] =
    "key=account:stale-account|active=true|Head=helmet,Stale Helmet\n"
loadFirst(candidates("Lua/WardrobeSwitcherServer.lua"), false)
local corruptGuard = assert(memoryFiles[serverJsonPath])
assert(corruptGuard:find('"schemaVersion":3', 1, true) ~= nil and
       corruptGuard:find('"records":[]', 1, true) ~= nil and
       corruptGuard:find("stale-account", 1, true) == nil,
    "truncated persistence must be replaced with an empty durable v3 tombstone")
assert(memoryFiles[storageRoot .. "/ServerLooks.txt"] ~= nil,
    "a stale legacy source must not be imported in the same startup as corrupt-primary quarantine")
local quarantinedJson = false
for path in pairs(memoryFiles) do
    if path:find("ServerLooks.json.", 1, true) and path:sub(-8) == ".corrupt" then quarantinedJson = true end
end
assert(quarantinedJson, "truncated persistence must receive a timestamped .corrupt name")

loadFirst(candidates("Lua/WardrobeSwitcherServer.lua"), false)
assert(memoryFiles[serverJsonPath]:find("stale-account", 1, true) == nil,
    "the corruption tombstone must prevent stale legacy import on later restarts")

local function quarantinedPersistenceContains(fragment)
    for path, contents in pairs(memoryFiles) do
        if path:find("ServerLooks.json.", 1, true) and
            path:sub(-8) == ".corrupt" and
            tostring(contents):find(fragment, 1, true) ~= nil then
            return true
        end
    end
    return false
end

memoryFiles[storageRoot .. "/ServerLooks.txt"] = nil
memoryFiles[serverJsonPath] =
    '{"schemaVersion":3,"records":[{"accountId":"missing-visibility-account",' ..
    '"revision":1,"active":false,"sessionKey":null,"look":{"schemaVersion":2,' ..
    '"captured":true,"slots":{"Head":"helmet"}}}],"pendingLegacySteamRecords":[],' ..
    '"migratedLegacySteamIds":[]}'
loadFirst(candidates("Lua/WardrobeSwitcherServer.lua"), false)
assert(memoryFiles[serverJsonPath]:find('"records":[]', 1, true) ~= nil and
       memoryFiles[serverJsonPath]:find("missing-visibility-account", 1, true) == nil,
    "server persistence v3 without attachmentVisibility must be quarantined")
assert(quarantinedPersistenceContains("missing-visibility-account"),
    "missing v3 attachmentVisibility did not preserve quarantine evidence")

memoryFiles[serverJsonPath] =
    '{"schemaVersion":2,"records":[{"accountId":"missing-hidehair-account",' ..
    '"revision":1,"active":false,"sessionKey":null,"look":{"schemaVersion":2,' ..
    '"captured":true,"slots":{"Head":"helmet"}}}],"pendingLegacySteamRecords":[],' ..
    '"migratedLegacySteamIds":[]}'
loadFirst(candidates("Lua/WardrobeSwitcherServer.lua"), false)
assert(memoryFiles[serverJsonPath]:find('"records":[]', 1, true) ~= nil and
       memoryFiles[serverJsonPath]:find("missing-hidehair-account", 1, true) == nil,
    "noncanonical server persistence v2 without hideHair must be quarantined")
assert(quarantinedPersistenceContains("missing-hidehair-account"),
    "missing v2 hideHair did not preserve quarantine evidence")

memoryFiles[serverJsonPath] = nil
memoryFiles[storageRoot .. "/ServerLooks.txt"] =
    "key=account:stable-account|active=false|Head=truncated-without-comma\n"
loadFirst(candidates("Lua/WardrobeSwitcherServer.lua"), false)
assert(memoryFiles[storageRoot .. "/ServerLooks.txt"] == nil,
    "truncated legacy persistence must be quarantined rather than migrated")
local quarantinedLegacy = false
for path in pairs(memoryFiles) do
    if path:find("ServerLooks.txt.", 1, true) and path:sub(-8) == ".corrupt" then quarantinedLegacy = true end
end
assert(quarantinedLegacy)

memoryFiles[storageRoot .. "/ServerLooks.txt"] =
    "key=steam:123|active=false|Head=helmet,Legacy Helmet\n"
loadFirst(candidates("Lua/WardrobeSwitcherServer.lua"), false)
local pendingMigrationJson = assert(memoryFiles[serverJsonPath])
assert(pendingMigrationJson:find('"pendingLegacySteamRecords"', 1, true) ~= nil and
       pendingMigrationJson:find('"steamId":"123"', 1, true) ~= nil,
    "unmapped legacy Steam records must survive the first v3 rewrite")

loadFirst(candidates("Lua/WardrobeSwitcherServer.lua"), false)
local migratedAccount = { StringRepresentation = "migrated-account" }
local migratingClient = {
    Connection = {},
    Character = { ID = 111, Name = "Migrating" },
    SteamID = "123",
    AccountId = {
        IsSome = function() return true end,
        TryUnwrap = function() return true, migratedAccount end
    }
}
connectedClients[5] = migratingClient
local migrationHello = newBuffer()
assert(Core.writeClientHello(migrationHello, "migration-session"))
local beforeMigrationHello = #Networking.sent
Networking.handlers[Core.NET.V2_HELLO](migrationHello, migratingClient)
local migrationResponse = assert(Core.readServerHello(Networking.sent[beforeMigrationHello + 1].message))
assert(migrationResponse.revision == 1)
local migratedJson = assert(memoryFiles[serverJsonPath])
assert(migratedJson:find('"accountId":"migrated-account"', 1, true) ~= nil and
       migratedJson:find('"steamId":"123"', 1, true) == nil,
    "reconnecting legacy user must be atomically re-keyed to Client.AccountId")

loadFirst(candidates("Lua/WardrobeSwitcherServer.lua"), false)
local afterRestartHello = newBuffer()
assert(Core.writeClientHello(afterRestartHello, "migration-session-after-restart"))
local beforeRestartHello = #Networking.sent
Networking.handlers[Core.NET.V2_HELLO](afterRestartHello, migratingClient)
local afterRestartResponse = assert(Core.readServerHello(Networking.sent[beforeRestartHello + 1].message))
assert(afterRestartResponse.revision == 1,
    "AccountId-migrated wardrobe must remain available after another server restart")

memoryFiles[storageRoot .. "/ServerLooks.txt"] = nil
memoryFiles[serverJsonPath] =
    '{"schemaVersion":2,"records":[{"accountId":"max-account","revision":4294967295,' ..
    '"active":false,"sessionKey":null,"look":{"schemaVersion":2,"captured":true,' ..
    '"hideHair":false,"slots":{"Head":"helmet"}}}],"pendingLegacySteamRecords":[],' ..
    '"migratedLegacySteamIds":[]}'
loadFirst(candidates("Lua/WardrobeSwitcherServer.lua"), false)
assert(memoryFiles[serverJsonPath]:find('"schemaVersion":3', 1, true) ~= nil and
       memoryFiles[serverJsonPath]:find('"attachmentVisibility"', 1, true) ~= nil,
    "valid server persistence v2 must migrate to v3")
assert(memoryFiles[serverJsonPath .. ".v2.bak"] ~= nil,
    "server persistence v2 migration must preserve a .v2.bak source")
local maxAccount = { StringRepresentation = "max-account" }
local maxClient = {
    Connection = {},
    Character = { ID = 120, Name = "Revision Max" },
    AccountId = {
        IsSome = function() return true end,
        TryUnwrap = function() return true, maxAccount end
    }
}
connectedClients[#connectedClients + 1] = maxClient
local maxHello = newBuffer()
assert(Core.writeClientHello(maxHello, "max-session"))
Networking.handlers[Core.NET.V2_HELLO](maxHello, maxClient)
local persistedAtRevisionMax = memoryFiles[serverJsonPath]
local beforeRevisionExhausted = #Networking.sent
local exhausted = sendCommand({
    clientSessionId = "max-session",
    operationId = "max-clear",
    baseRevision = Core.LIMITS.MAX_UINT32,
    kind = Core.COMMAND.Clear
}, maxClient)
assert(not exhausted.accepted and exhausted.reason == "revision_exhausted" and
       exhausted.revision == Core.LIMITS.MAX_UINT32,
    "UInt32 revision exhaustion must reject mutation instead of reusing a revision")
assert(#Networking.sent == beforeRevisionExhausted + 1 and memoryFiles[serverJsonPath] == persistedAtRevisionMax,
    "revision exhaustion must not persist or broadcast a mutation")

print("Wardrobe server authority tests passed")
