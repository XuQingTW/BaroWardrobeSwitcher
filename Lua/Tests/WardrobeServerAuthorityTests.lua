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
Character = { CharacterList = {} }
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
local failPrimaryMove = false
local storageRoot = "/local/Daedalic Entertainment GmbH/Barotrauma/ModData/BaroWardrobeSwitcher"
local MemoryFile = {
    Exists = function(path) return memoryFiles[tostring(path)] ~= nil end,
    Read = function(path)
        local value = memoryFiles[tostring(path)]
        if value == nil then error("file not found") end
        return value
    end,
    Write = function(path, value) memoryFiles[tostring(path)] = tostring(value) end,
    CreateDirectory = function() return true end,
    Delete = function(path) memoryFiles[tostring(path)] = nil end,
    Move = function(...)
        local args = { ... }
        if #args ~= 2 then error("native File.Move accepts exactly two arguments") end
        local source, destination = tostring(args[1]), tostring(args[2])
        if memoryFiles[source] == nil then error("source missing") end
        if failPrimaryMove and source:sub(-4) == ".tmp" and
            destination == storageRoot .. "/ServerLooks.json" then
            error("synthetic primary move failure")
        end
        memoryFiles[destination] = memoryFiles[source]
        memoryFiles[source] = nil
    end
}
File = MemoryFile
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
local gameSessionDataPath = {}
local gameSession = {
    DataPath = gameSessionDataPath,
    GameMode = { Preset = { Identifier = "sandbox" } }
}
Game = {
    SaveFolder = "/local/Daedalic Entertainment GmbH/Barotrauma"
}
local requestedSystemStatic = false
LuaUserData = {
    RegisterType = function(name)
        if tostring(name):find("^System%.") then error("system type access is unavailable") end
    end,
    CreateStatic = function(name)
        if name == "Barotrauma.ItemPrefab" then
            return { Prefabs = { helmet = fakeHelmetPrefab } }
        end
        if name == "Barotrauma.Networking.Client" then
            return { ClientList = connectedClients }
        end
        if name == "Barotrauma.GameMain" then
            return { GameSession = gameSession }
        end
        if name:find("^System%.") then
            requestedSystemStatic = true
            error("system static userdata is unavailable")
        end
        return nil
    end
}
LuaCsLogger = { Log = function() end, LogError = function() end }

local newBuffer = loadFirst(candidates("Lua/Tests/TestBuffer.lua"), false)

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
assert(not requestedSystemStatic,
    "server persistence must use LuaCs native File instead of System.IO userdata")
local serverLogPath = storageRoot .. "/WardrobeServer.log"
assert(memoryFiles[serverLogPath] ~= nil and
       memoryFiles[serverLogPath]:find("Server authority", 1, true) ~= nil,
    "server diagnostics were not written to the dedicated file log")

local handlerCount = 0
for _ in pairs(Networking.handlers) do handlerCount = handlerCount + 1 end
assert(handlerCount == 7, "server must register four v1 and three v2 receivers")
assert(Hook.handlers.think == nil, "server authority must not install a think heartbeat")

local client = { Connection = {}, Character = { ID = 42, Name = "Tester" } }
connectedClients[1] = client
local hello = newBuffer()
assert(Core.writeClientHello(hello, "client-session"))
Networking.handlers[Core.NET.V2_HELLO](hello, client)
local serverHello = assert(Core.readServerHello(Networking.sent[#Networking.sent].message))
assert(serverHello.revision == 0)
assert(serverHello.capabilities == Core.CAPABILITY.AttachmentVisibility +
    Core.CAPABILITY.MovementAnimationSource + Core.CAPABILITY.CrewTargeting +
    Core.CAPABILITY.FootstepSoundSource,
    "server did not advertise all authoritative appearance preferences")

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

local targetOwnerCharacter = {
    ID = 80, Name = "Target Owner", IsHuman = true, IsOnPlayerTeam = true, IsBot = false
}
local friendlyBot = {
    ID = 81, Name = "Friendly Bot", IsHuman = true, IsOnPlayerTeam = true, IsBot = true
}
local enemyBot = {
    ID = 82, Name = "Enemy Bot", IsHuman = true, IsOnPlayerTeam = false, IsBot = true
}
local targetOwner = { Connection = {}, Character = targetOwnerCharacter }
connectedClients[2] = targetOwner
Character.CharacterList = { targetOwnerCharacter, friendlyBot, enemyBot }
local targetHello = newBuffer()
assert(Core.writeClientHello(targetHello, "target-owner-session"))
Networking.handlers[Core.NET.V2_HELLO](targetHello, targetOwner)

local function sendTargetCommand(command, targetClient)
    local message = newBuffer()
    assert(Core.writeTargetCommand(message, command))
    message.FinalizeForTransport()
    local sentBefore = #Networking.sent
    Networking.handlers[Core.NET.V2_TARGET_COMMAND](message, targetClient)
    for index = sentBefore + 1, #Networking.sent do
        if Networking.sent[index].message.name == Core.NET.V2_ACK then
            return assert(Core.readAck(Networking.sent[index].message))
        end
    end
    error("target command did not receive an acknowledgement")
end

local targetLook = assert(Core.newLook(true, false, { Head = "helmet" }))
local targetApply = sendTargetCommand({
    clientSessionId = "target-owner-session",
    operationId = "target-apply",
    baseRevision = 0,
    kind = Core.COMMAND.Apply,
    targetCharacterId = friendlyBot.ID,
    look = targetLook
}, targetOwner)
assert(targetApply.accepted and targetApply.revision == 1,
    "a friendly living human bot was not accepted as a wardrobe target")
local botState = assert(Core.readState(lastSentMessage(Core.NET.V2_STATE, targetOwner.Connection)))
assert(botState.active and botState.characterId == friendlyBot.ID,
    "targeted apply was broadcast for the wrong character")
local duplicateTargetApply = sendTargetCommand({
    clientSessionId = "target-owner-session",
    operationId = "target-apply",
    baseRevision = 0,
    kind = Core.COMMAND.Apply,
    targetCharacterId = friendlyBot.ID,
    look = targetLook
}, targetOwner)
assert(duplicateTargetApply.accepted and duplicateTargetApply.revision == 1,
    "a targeted retry was not idempotent")
local duplicateBotState = assert(Core.readState(
    lastSentMessage(Core.NET.V2_STATE, targetOwner.Connection)))
assert(duplicateBotState.active and duplicateBotState.characterId == friendlyBot.ID,
    "a targeted retry resent state for the owner's player character")

local rejectedEnemy = sendTargetCommand({
    clientSessionId = "target-owner-session",
    operationId = "target-enemy",
    baseRevision = 1,
    kind = Core.COMMAND.Apply,
    targetCharacterId = enemyBot.ID,
    look = targetLook
}, targetOwner)
assert(not rejectedEnemy.accepted and rejectedEnemy.reason == "target_not_permitted" and
    rejectedEnemy.revision == 1, "an enemy bot target mutated server state")

local secondOwnerCharacter = {
    ID = 83, Name = "Second Owner", IsHuman = true, IsOnPlayerTeam = true, IsBot = false
}
local secondOwner = { Connection = {}, Character = secondOwnerCharacter }
connectedClients[3] = secondOwner
Character.CharacterList[#Character.CharacterList + 1] = secondOwnerCharacter
local secondHello = newBuffer()
assert(Core.writeClientHello(secondHello, "second-target-session"))
Networking.handlers[Core.NET.V2_HELLO](secondHello, secondOwner)
local contested = sendTargetCommand({
    clientSessionId = "second-target-session",
    operationId = "target-contested",
    baseRevision = 0,
    kind = Core.COMMAND.Apply,
    targetCharacterId = friendlyBot.ID,
    look = targetLook
}, secondOwner)
assert(not contested.accepted and contested.reason == "target_in_use" and contested.revision == 0,
    "a second player silently stole an active bot target")

local sentBeforeTargetRoundStart = #Networking.sent
Hook.handlers.roundEnd()
Hook.handlers.roundStart()
for index = sentBeforeTargetRoundStart + 1, #Networking.sent do
    local sent = Networking.sent[index]
    if sent.message.name == Core.NET.V2_STATE then
        local state = assert(Core.readState(sent.message))
        assert(state.characterId ~= targetOwnerCharacter.ID,
            "a bot-only active look was rebound to its owner's player character")
    end
end
Hook.handlers["client.disconnected"](secondOwner)
Hook.handlers["client.disconnected"](targetOwner)
table.remove(connectedClients, 3)
table.remove(connectedClients, 2)

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
    look = assert(Core.newLook(
        true,
        true,
        { Head = "helmet" },
        nil,
        { Head = 0x7F0102FF },
        false
    ))
})
assert(canonicalApply.accepted and canonicalApply.revision == 2,
    "server must accept a valid wearable identifier for its declared slot")

local canonicalStateMessage = Networking.sent[#Networking.sent - 1].message
assert(canonicalStateMessage.name == Core.NET.V2_STATE, "apply must broadcast canonical state before its ack")
local canonicalState = assert(Core.readState(canonicalStateMessage))
assert(canonicalState.active and canonicalState.look.slots.Head == "helmet" and
       canonicalState.look.colors.Head == 0x7F0102FF and canonicalState.look.hideHair and
       canonicalState.look.useFashionMovementAnimations == false,
    "server canonical state must retain identifiers, color, visibility, and movement source")

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
        lateSnapshot.characterId == 143 and lateSnapshot.look.slots.Head == "helmet" and
        lateSnapshot.look.useFashionMovementAnimations == false,
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
        announcedToExistingClient.look.slots.Head == "helmet" and
        announcedToExistingClient.look.useFashionMovementAnimations == true,
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
assert(visibilityServerHello.capabilities ==
        Core.CAPABILITY.AttachmentVisibility + Core.CAPABILITY.MovementAnimationSource +
        Core.CAPABILITY.CrewTargeting + Core.CAPABILITY.FootstepSoundSource,
    "new server hello must advertise visibility, movement, crew targeting, and footsteps")

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

local animationAck = sendCommand({
    clientSessionId = "visibility-session",
    operationId = "animation-active-update",
    baseRevision = 2,
    kind = Core.COMMAND.Animation,
    -- Invalid client slots must be ignored just like the visibility policy path.
    look = assert(Core.newLook(
        true,
        false,
        { Head = "not-a-real-prefab" },
        requestedVisibility,
        nil,
        false
    ))
}, visibilityClient)
assert(animationAck.accepted and animationAck.revision == 3)
local activeAnimationState = assert(Core.readState(
    lastSentMessage(Core.NET.V2_STATE, visibilityClient.Connection)))
assert(activeAnimationState.active and
       activeAnimationState.look.slots.Head == "helmet" and
       activeAnimationState.look.attachmentVisibility.Hair == "show" and
       activeAnimationState.look.useFashionMovementAnimations == false,
    "animation command must retain authoritative slots/visibility and broadcast its value")

local footstepAck = sendCommand({
    clientSessionId = "visibility-session",
    operationId = "footstep-active-update",
    baseRevision = 3,
    kind = Core.COMMAND.Footstep,
    -- Client-supplied equipment and other appearance preferences are never authoritative here.
    look = assert(Core.newLook(
        true,
        false,
        { Head = "not-a-real-prefab" },
        Core.attachmentVisibilityFromLegacy(false),
        nil,
        true,
        true
    ))
}, visibilityClient)
assert(footstepAck.accepted and footstepAck.revision == 4)
local activeFootstepState = assert(Core.readState(
    lastSentMessage(Core.NET.V2_STATE, visibilityClient.Connection)))
assert(activeFootstepState.active and
       activeFootstepState.look.slots.Head == "helmet" and
       activeFootstepState.look.attachmentVisibility.Hair == "show" and
       activeFootstepState.look.useFashionMovementAnimations == false and
       activeFootstepState.look.useFashionFootstepSounds == true,
    "footstep command must merge only its authoritative sound-source value")

local visibilityClear = sendCommand({
    clientSessionId = "visibility-session",
    operationId = "visibility-clear",
    baseRevision = 4,
    kind = Core.COMMAND.Clear
}, visibilityClient)
assert(visibilityClear.accepted and visibilityClear.revision == 5)
local inactiveVisibilityAck = sendCommand({
    clientSessionId = "visibility-session",
    operationId = "visibility-inactive-update",
    baseRevision = 5,
    kind = Core.COMMAND.Visibility,
    look = assert(Core.newLook(
        true,
        false,
        { Head = "also-not-authoritative" },
        Core.attachmentVisibilityFromLegacy(false)
    ))
}, visibilityClient)
assert(inactiveVisibilityAck.accepted and inactiveVisibilityAck.revision == 6)
local inactiveVisibilityState = assert(Core.readState(
    lastSentMessage(Core.NET.V2_STATE, visibilityClient.Connection)))
assert(not inactiveVisibilityState.active and
       inactiveVisibilityState.look.slots.Head == "helmet" and
       inactiveVisibilityState.look.attachmentVisibility.Hair == "auto" and
       inactiveVisibilityState.look.useFashionMovementAnimations == false and
       inactiveVisibilityState.look.useFashionFootstepSounds == true,
    "inactive visibility command must preserve movement and footstep sources")

local overlappingVisibility = newBuffer()
overlappingVisibility.WriteUInt16(Core.PROTOCOL_VERSION)
    overlappingVisibility.WriteString("visibility-session")
overlappingVisibility.WriteString("visibility-overlap")
    overlappingVisibility.WriteUInt32(6)
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
    overlappingVisibility.WriteByte(1)
    overlappingVisibility.WriteByte(0)
Networking.handlers[Core.NET.V2_COMMAND](overlappingVisibility, visibilityClient)
local overlappingVisibilityAck =
    assert(Core.readAck(Networking.sent[#Networking.sent].message))
assert(not overlappingVisibilityAck.accepted and
       overlappingVisibilityAck.reason == "malformed_look" and
       overlappingVisibilityAck.revision == 6,
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
local authoritativeColor = 0x7F1122FF
local stableSlots = {}
local stableItem = {
    Prefab = fakeHelmetPrefab,
    SpriteColor = { PackedValue = authoritativeColor }
}
local stableUnequipCalls = 0
stableItem.Unequip = function()
    stableUnequipCalls = stableUnequipCalls + 1
    stableSlots[InvSlotType.Head] = nil
end
stableSlots[InvSlotType.Head] = stableItem
stableClient.Character.Inventory = {
    GetItemInLimbSlot = function(slot) return stableSlots[slot] end,
    IsInLimbSlot = function(item, slot) return stableSlots[slot] == item end
}
connectedClients[3] = stableClient
local stableHello = newBuffer()
assert(Core.writeClientHello(stableHello, "stable-session"))
Networking.handlers[Core.NET.V2_HELLO](stableHello, stableClient)

local serverJsonPath = storageRoot .. "/ServerLooks.json"
failPrimaryMove = true
local failedSavePreflight = sendCommand({
    clientSessionId = "stable-session",
    operationId = "stable-save-preflight-fails",
    baseRevision = 0,
    kind = Core.COMMAND.Save
}, stableClient)
assert(not failedSavePreflight.accepted and failedSavePreflight.reason == "persistence_failed" and
       failedSavePreflight.revision == 0,
    "an unavailable native File backend must reject Save before changing equipment")
assert(stableSlots[InvSlotType.Head] == stableItem and stableUnequipCalls == 0,
    "a persistence preflight failure must not unequip physical gear")
failPrimaryMove = false

local stableSave = sendCommand({
    clientSessionId = "stable-session",
    operationId = "stable-save",
    baseRevision = 0,
    kind = Core.COMMAND.Save,
    look = assert(Core.newLook(
        true,
        false,
        { Head = "helmet" },
        nil,
        { Head = authoritativeColor + 1 }
    ))
}, stableClient)
assert(stableSave.accepted and stableSave.revision == 1)
local persistedAfterSave = assert(memoryFiles[serverJsonPath])
assert(persistedAfterSave:find('{"schemaVersion":5', 1, true) == 1)
assert(persistedAfterSave:find('"attachmentVisibility"', 1, true) ~= nil and
       persistedAfterSave:find('"hideHair"', 1, true) == nil,
    "server persistence v5 must store the complete visibility policy without authoritative hideHair")
assert(persistedAfterSave:find('"useFashionFootstepSounds":false', 1, true) ~= nil,
    "server persistence v5 must store the footstep sound source")
assert(persistedAfterSave:find('"colors":{"Head":' .. tostring(authoritativeColor), 1, true) ~= nil and
       persistedAfterSave:find(tostring(authoritativeColor + 1), 1, true) == nil,
    "server Save must persist the equipped item's authoritative SpriteColor")
assert(persistedAfterSave:find('"accountId":"stable-account"', 1, true) ~= nil,
    "stable AccountId must be the persistence key")
assert(persistedAfterSave:find('"sessionKey":"runtime:', 1, true) ~= nil and
       persistedAfterSave:find(':sandbox"', 1, true) ~= nil,
    "pathless sessions must use a process-scoped game-mode key")
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

failPrimaryMove = true
local failedClear = sendCommand({
    clientSessionId = "stable-session",
    operationId = "stable-clear-fails",
    baseRevision = 1,
    kind = Core.COMMAND.Clear
}, stableReconnected)
assert(not failedClear.accepted and failedClear.reason == "persistence_failed" and failedClear.revision == 1)
assert(memoryFiles[serverJsonPath] == persistedAfterSave,
    "atomic replacement failure must preserve the prior server document")
failPrimaryMove = false

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

local restartAccount = { StringRepresentation = "runtime-restart-account" }
local restartClient = {
    Connection = {},
    Character = { ID = 100, Name = "Runtime Restart" },
    AccountId = {
        IsSome = function() return true end,
        TryUnwrap = function() return true, restartAccount end
    }
}
connectedClients[#connectedClients + 1] = restartClient
local restartHello = newBuffer()
assert(Core.writeClientHello(restartHello, "runtime-before-restart"))
Networking.handlers[Core.NET.V2_HELLO](restartHello, restartClient)
local restartApply = sendCommand({
    clientSessionId = "runtime-before-restart",
    operationId = "runtime-apply",
    baseRevision = 0,
    kind = Core.COMMAND.Apply,
    look = assert(Core.newLook(true, false, { Head = "helmet" }))
}, restartClient)
assert(restartApply.accepted and
       memoryFiles[serverJsonPath]:find('"sessionKey":"runtime:', 1, true) ~= nil)

local beforeRuntimeReload = #Networking.sent
loadFirst(candidates("Lua/WardrobeSwitcherServer.lua"), false)
local afterRuntimeRestartHello = newBuffer()
assert(Core.writeClientHello(afterRuntimeRestartHello, "runtime-after-restart"))
Networking.handlers[Core.NET.V2_HELLO](afterRuntimeRestartHello, restartClient)
for index = beforeRuntimeReload + 1, #Networking.sent do
    local sent = Networking.sent[index]
    if sent.connection == restartClient.Connection and sent.message.name == Core.NET.V2_STATE then
        local state = assert(Core.readState(sent.message))
        assert(state.characterId ~= restartClient.Character.ID or not state.active,
            "a process-scoped pathless key reactivated an old wardrobe after server restart")
    end
end

gameSessionDataPath.SavePath = "campaign-a.save"
Hook.handlers.roundStart()
local campaignAccount = { StringRepresentation = "campaign-path-account" }
local campaignClient = {
    Connection = {},
    Character = { ID = 101, Name = "Campaign Path" },
    AccountId = {
        IsSome = function() return true end,
        TryUnwrap = function() return true, campaignAccount end
    }
}
connectedClients[#connectedClients + 1] = campaignClient
local campaignHello = newBuffer()
assert(Core.writeClientHello(campaignHello, "campaign-path-session"))
Networking.handlers[Core.NET.V2_HELLO](campaignHello, campaignClient)
local campaignApply = sendCommand({
    clientSessionId = "campaign-path-session",
    operationId = "campaign-path-apply",
    baseRevision = 0,
    kind = Core.COMMAND.Apply,
    look = assert(Core.newLook(true, false, { Head = "helmet" }))
}, campaignClient)
assert(campaignApply.accepted and
       memoryFiles[serverJsonPath]:find(
           '"accountId":"campaign-path-account","revision":1,"active":true,"sessionKey":"campaign:campaign-a.save"',
           1,
           true
       ) ~= nil,
    "GameSession.DataPath must take precedence over the runtime session key")
gameSessionDataPath.SavePath = nil

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
assert(corruptGuard:find('"schemaVersion":5', 1, true) ~= nil and
       corruptGuard:find('"records":[]', 1, true) ~= nil and
       corruptGuard:find("stale-account", 1, true) == nil,
    "truncated persistence must be replaced with an empty durable v5 tombstone")
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
    '{"schemaVersion":4,"records":[{"accountId":"missing-colors-account",' ..
    '"revision":1,"active":false,"sessionKey":null,"look":{"schemaVersion":3,' ..
    '"captured":true,"attachmentVisibility":{"Hair":"auto","Beard":"auto",' ..
    '"Moustache":"auto","FaceAttachment":"auto"},"slots":{"Head":"helmet"}}}],' ..
    '"pendingLegacySteamRecords":[],' ..
    '"migratedLegacySteamIds":[]}'
loadFirst(candidates("Lua/WardrobeSwitcherServer.lua"), false)
assert(memoryFiles[serverJsonPath]:find('"records":[]', 1, true) ~= nil and
       memoryFiles[serverJsonPath]:find("missing-colors-account", 1, true) == nil,
    "server persistence v4 without colors must be quarantined")
assert(quarantinedPersistenceContains("missing-colors-account"),
    "missing v4 colors did not preserve quarantine evidence")

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
    '{"schemaVersion":3,"records":[{"accountId":"legacy-v3-account","revision":1,' ..
    '"active":false,"sessionKey":null,"look":{"schemaVersion":2,"captured":true,' ..
    '"attachmentVisibility":{"Hair":"auto","Beard":"auto","Moustache":"auto",' ..
    '"FaceAttachment":"auto"},"slots":{"Head":"helmet"}}}],' ..
    '"pendingLegacySteamRecords":[],"migratedLegacySteamIds":[]}'
loadFirst(candidates("Lua/WardrobeSwitcherServer.lua"), false)
assert(memoryFiles[serverJsonPath]:find('"schemaVersion":5', 1, true) ~= nil and
       memoryFiles[serverJsonPath]:find('"colors":{}', 1, true) ~= nil,
    "valid server persistence v3 must migrate to v5 with missing colors")
assert(memoryFiles[serverJsonPath .. ".v3.bak"] ~= nil,
    "server persistence v3 migration must preserve a .v3.bak source")

memoryFiles[storageRoot .. "/ServerLooks.txt"] = nil
memoryFiles[serverJsonPath] =
    '{"schemaVersion":2,"records":[{"accountId":"max-account","revision":4294967295,' ..
    '"active":false,"sessionKey":null,"look":{"schemaVersion":2,"captured":true,' ..
    '"hideHair":false,"slots":{"Head":"helmet"}}}],"pendingLegacySteamRecords":[],' ..
    '"migratedLegacySteamIds":[]}'
loadFirst(candidates("Lua/WardrobeSwitcherServer.lua"), false)
assert(memoryFiles[serverJsonPath]:find('"schemaVersion":5', 1, true) ~= nil and
       memoryFiles[serverJsonPath]:find('"attachmentVisibility"', 1, true) ~= nil,
    "valid server persistence v2 must migrate to v5")
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

local noKeyAccount = { StringRepresentation = "no-session-key-account" }
local noKeyClient = {
    Connection = {},
    Character = { ID = 121, Name = "No Session Key" },
    AccountId = {
        IsSome = function() return true end,
        TryUnwrap = function() return true, noKeyAccount end
    }
}
connectedClients[#connectedClients + 1] = noKeyClient
local noKeyHello = newBuffer()
assert(Core.writeClientHello(noKeyHello, "no-session-key"))
Networking.handlers[Core.NET.V2_HELLO](noKeyHello, noKeyClient)
local noKeyApply = sendCommand({
    clientSessionId = "no-session-key",
    operationId = "no-session-key-apply",
    baseRevision = 0,
    kind = Core.COMMAND.Apply,
    look = assert(Core.newLook(true, false, { Head = "helmet" }))
}, noKeyClient)
assert(noKeyApply.accepted)

local delayedRoundCallbacks = {}
Timer = {
    Wait = function(callback)
        delayedRoundCallbacks[#delayedRoundCallbacks + 1] = callback
    end
}
Hook.handlers.roundEnd()
gameSession.GameMode.Preset = nil
local sentBeforeMissingKeyRound = #Networking.sent
Hook.handlers.roundStart()
for index = sentBeforeMissingKeyRound + 1, #Networking.sent do
    local sent = Networking.sent[index]
    if sent.message.name == Core.NET.V2_STATE then
        local state = assert(Core.readState(sent.message))
        assert(state.characterId ~= 121 or not state.active,
            "round start restored an active look before the session key was available")
    end
end

noKeyClient.Character = { ID = 122, Name = "No Session Key Rebound" }
local sentBeforeMissingKeyRebind = #Networking.sent
Hook.handlers["character.created"](noKeyClient.Character)
local reboundHello = newBuffer()
assert(Core.writeClientHello(reboundHello, "no-session-key-rebound"))
Networking.handlers[Core.NET.V2_HELLO](reboundHello, noKeyClient)
for index = sentBeforeMissingKeyRebind + 1, #Networking.sent do
    local sent = Networking.sent[index]
    if sent.message.name == Core.NET.V2_STATE then
        local state = assert(Core.readState(sent.message))
        assert(state.characterId ~= 122 or not state.active,
            "character/hello rebind restored an active look without a session key")
    end
end
gameSession.GameMode.Preset = { Identifier = "sandbox" }
local sentBeforeDelayedRecovery = #Networking.sent
local delayedIndex = 1
while delayedIndex <= #delayedRoundCallbacks do
    local callback = delayedRoundCallbacks[delayedIndex]
    delayedIndex = delayedIndex + 1
    callback()
end
local recoveredAfterDelayedKey = false
for index = sentBeforeDelayedRecovery + 1, #Networking.sent do
    local sent = Networking.sent[index]
    if sent.message.name == Core.NET.V2_STATE then
        local state = assert(Core.readState(sent.message))
        if state.characterId == 122 and state.active then
            recoveredAfterDelayedKey = state.revision == noKeyApply.revision
        end
    end
end
assert(recoveredAfterDelayedKey,
    "an active look did not recover after the same round session key became available")

local reconnectRaceAccount = { StringRepresentation = "reconnect-race-account" }
local reconnectRaceAccountId = {
    IsSome = function() return true end,
    TryUnwrap = function() return true, reconnectRaceAccount end
}
local reconnectRaceClient = {
    Connection = {},
    Character = { ID = 130, Name = "Reconnect Race" },
    AccountId = reconnectRaceAccountId
}
connectedClients[#connectedClients + 1] = reconnectRaceClient
local reconnectRaceHello = newBuffer()
assert(Core.writeClientHello(reconnectRaceHello, "reconnect-race-session"))
Networking.handlers[Core.NET.V2_HELLO](reconnectRaceHello, reconnectRaceClient)
local reconnectRaceApply = sendCommand({
    clientSessionId = "reconnect-race-session",
    operationId = "reconnect-race-apply",
    baseRevision = 0,
    kind = Core.COMMAND.Apply,
    look = assert(Core.newLook(true, false, { Head = "helmet" }))
}, reconnectRaceClient)
assert(reconnectRaceApply.accepted)
Hook.handlers["client.disconnected"](reconnectRaceClient)

local reconnectGameSession = gameSession
gameSession = nil
delayedRoundCallbacks = {}
local pendingReconnectClient = {
    Connection = {},
    Character = nil,
    AccountId = reconnectRaceAccountId
}
connectedClients[#connectedClients] = pendingReconnectClient
Hook.handlers["client.connected"](pendingReconnectClient)
Hook.handlers["client.disconnected"](pendingReconnectClient)
assert(memoryFiles[serverJsonPath]:find(
        '"accountId":"reconnect-race-account","revision":1,"active":true', 1, true) ~= nil,
    "disconnecting while reconnect is pending must not erase the durable active intent")

local delayedReconnectClient = {
    Connection = {},
    Character = nil,
    AccountId = reconnectRaceAccountId
}
connectedClients[#connectedClients] = delayedReconnectClient
Hook.handlers["client.connected"](delayedReconnectClient)
delayedReconnectClient.Character = { ID = 131, Name = "Reconnect Race Restored" }
gameSession = reconnectGameSession
local sentBeforeReconnectRecovery = #Networking.sent
local reconnectCallbackIndex = 1
while reconnectCallbackIndex <= #delayedRoundCallbacks do
    local callback = delayedRoundCallbacks[reconnectCallbackIndex]
    reconnectCallbackIndex = reconnectCallbackIndex + 1
    callback()
end
local recoveredReconnectLook = false
for index = sentBeforeReconnectRecovery + 1, #Networking.sent do
    local sent = Networking.sent[index]
    if sent.message.name == Core.NET.V2_STATE then
        local state = assert(Core.readState(sent.message))
        if state.characterId == 131 and state.active then
            recoveredReconnectLook = state.revision == reconnectRaceApply.revision
        end
    end
end
assert(recoveredReconnectLook,
    "an active persisted look did not recover when reconnect initially had no GameSession or Character")

Hook.handlers["client.disconnected"](delayedReconnectClient)
local accountNotReady = {
    IsSome = function() return false end,
    TryUnwrap = function() return false, nil end
}
local lateIdentityClient = {
    Connection = {},
    Character = nil,
    AccountId = accountNotReady
}
connectedClients[#connectedClients] = lateIdentityClient
Hook.handlers["client.connected"](lateIdentityClient)
lateIdentityClient.AccountId = reconnectRaceAccountId
lateIdentityClient.Character = { ID = 132, Name = "Late Account Restored" }
local lateIdentityHello = newBuffer()
assert(Core.writeClientHello(lateIdentityHello, "late-account-session"))
local sentBeforeLateIdentity = #Networking.sent
Networking.handlers[Core.NET.V2_HELLO](lateIdentityHello, lateIdentityClient)
local recoveredLateIdentityLook = false
for index = sentBeforeLateIdentity + 1, #Networking.sent do
    local sent = Networking.sent[index]
    if sent.message.name == Core.NET.V2_STATE then
        local state = assert(Core.readState(sent.message))
        if state.characterId == 132 and state.active then
            recoveredLateIdentityLook = state.revision == reconnectRaceApply.revision
        end
    end
end
assert(recoveredLateIdentityLook,
    "a client cached before AccountId became available did not rebind its persisted look")

local steamFallbackClient = {
    Connection = {},
    Character = { ID = 134, Name = "Listen Host" },
    SteamID = "76561198000000134",
    AccountId = {
        IsSome = function() return false end,
        TryUnwrap = function() return false, nil end
    }
}
connectedClients[#connectedClients + 1] = steamFallbackClient
local steamFallbackHello = newBuffer()
assert(Core.writeClientHello(steamFallbackHello, "steam-fallback-session"))
Networking.handlers[Core.NET.V2_HELLO](steamFallbackHello, steamFallbackClient)
local steamFallbackApply = sendCommand({
    clientSessionId = "steam-fallback-session",
    operationId = "steam-fallback-apply",
    baseRevision = 0,
    kind = Core.COMMAND.Apply,
    look = assert(Core.newLook(true, false, { Head = "helmet" }))
}, steamFallbackClient)
assert(steamFallbackApply.accepted and memoryFiles[serverJsonPath]:find(
        '"accountId":"steam:76561198000000134","revision":1,"active":true', 1, true) ~= nil,
    "a listen host without Client.AccountId did not persist through its stable SteamID")

-- A dedicated server can initialize the mod in a pathless lobby before it
-- loads the selected campaign. The temporary process-scoped runtime key must
-- neither apply the old look in the lobby nor erase the matching campaign
-- intent before roundStart exposes the durable save path.
local restartCampaignJson =
    '{"schemaVersion":5,"records":[{"accountId":"restart-campaign-account",' ..
    '"revision":7,"active":true,"sessionKey":"campaign:restart-campaign.save",' ..
    '"look":{"schemaVersion":4,"captured":true,' ..
    '"useFashionMovementAnimations":true,"useFashionFootstepSounds":false,' ..
    '"attachmentVisibility":{"Hair":"auto","Beard":"auto",' ..
    '"Moustache":"auto","FaceAttachment":"auto"},' ..
    '"slots":{"Head":"helmet"},"colors":{}}}],' ..
    '"pendingLegacySteamRecords":[],"migratedLegacySteamIds":[]}'
memoryFiles[serverJsonPath] = restartCampaignJson
local restartLobbyDataPath = {}
gameSession = {
    DataPath = restartLobbyDataPath,
    GameMode = { Preset = { Identifier = "sandbox" } }
}
connectedClients = {}
local restartCallbacks = {}
Timer = {
    Wait = function(callback)
        restartCallbacks[#restartCallbacks + 1] = callback
    end
}
loadFirst(candidates("Lua/WardrobeSwitcherServer.lua"), false)
local restartCampaignAccount = { StringRepresentation = "restart-campaign-account" }
local restartCampaignClient = {
    Connection = {},
    Character = { ID = 133, Name = "Restarted Campaign" },
    AccountId = {
        IsSome = function() return true end,
        TryUnwrap = function() return true, restartCampaignAccount end
    }
}
connectedClients[1] = restartCampaignClient
Hook.handlers["client.connected"](restartCampaignClient)
local restartCampaignHello = newBuffer()
assert(Core.writeClientHello(restartCampaignHello, "restart-campaign-session"))
local sentBeforeLobbyHello = #Networking.sent
Networking.handlers[Core.NET.V2_HELLO](restartCampaignHello, restartCampaignClient)
for index = sentBeforeLobbyHello + 1, #Networking.sent do
    local sent = Networking.sent[index]
    if sent.message.name == Core.NET.V2_STATE then
        local state = assert(Core.readState(sent.message))
        assert(state.characterId ~= 133 or not state.active,
            "a campaign look was applied while the restarted server was still in its lobby")
    end
end

restartLobbyDataPath.SavePath = "restart-campaign.save"
local sentBeforeRestartedRound = #Networking.sent
Hook.handlers.roundStart()
local restartCallbackIndex = 1
while restartCallbackIndex <= #restartCallbacks do
    local callback = restartCallbacks[restartCallbackIndex]
    restartCallbackIndex = restartCallbackIndex + 1
    callback()
end
local restoredAfterServerRestart = false
for index = sentBeforeRestartedRound + 1, #Networking.sent do
    local sent = Networking.sent[index]
    if sent.message.name == Core.NET.V2_STATE then
        local state = assert(Core.readState(sent.message))
        if state.characterId == 133 and state.active then
            restoredAfterServerRestart = state.revision == 7 and
                state.look.slots.Head == "helmet"
        end
    end
end
assert(restoredAfterServerRestart,
    "a matching campaign look did not survive a full dedicated-server restart: " ..
    tostring(memoryFiles[serverJsonPath]))

restartLobbyDataPath.SavePath = "different-campaign.save"
Hook.handlers.roundStart()
assert(memoryFiles[serverJsonPath]:find(
        '"accountId":"restart-campaign-account","revision":8,"active":false', 1, true) ~= nil,
    "loading a genuinely different campaign retained the previous campaign's active intent")

print("Wardrobe server authority tests passed")
