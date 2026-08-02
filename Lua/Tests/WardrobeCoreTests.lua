local coreCandidates = { "Lua/WardrobeCore.lua", "../WardrobeCore.lua", "WardrobeCore.lua" }
local testDirectory = ""
if debug ~= nil and debug.getinfo ~= nil then
    local source = debug.getinfo(1, "S").source
    local testFile = source:sub(1, 1) == "@" and source:sub(2) or source
    testDirectory = testFile:match("^(.*[/\\])") or ""
    table.insert(coreCandidates, 1, testDirectory .. "../WardrobeCore.lua")
end

local Core = nil
for _, candidate in ipairs(coreCandidates) do
    local ok, loaded = pcall(dofile, candidate)
    if ok and type(loaded) == "table" then
        Core = loaded
        break
    end
end
assert(Core ~= nil, "could not load Lua/WardrobeCore.lua")

local newBuffer = nil
for _, candidate in ipairs({
    "Lua/Tests/TestBuffer.lua",
    testDirectory .. "TestBuffer.lua",
    "TestBuffer.lua"
}) do
    local ok, loaded = pcall(dofile, candidate)
    if ok and type(loaded) == "function" then
        newBuffer = loaded
        break
    end
end
assert(newBuffer ~= nil, "could not load Lua/Tests/TestBuffer.lua")

local function tryReadLook(message)
    local ok, look, reason = pcall(Core.readLook, message)
    if not ok then return nil, "malformed look payload: " .. tostring(look) end
    return look, reason
end

local function assertEqual(actual, expected, message)
    assert(actual == expected, (message or "values differ") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end

local emptyLook = assert(Core.newLook(true, false, {}))
assert(Core.hasLook(emptyLook), "captured empty look must be preserved")
assertEqual(emptyLook.useFashionMovementAnimations, true,
    "looks without an animation-source field must keep fashion-priority movement")
assertEqual(emptyLook.useFashionFootstepSounds, false,
    "looks without a footstep-source field must keep equipment footsteps")
assert(Core.validateLook({ schemaVersion = 99, slots = {} }) == nil)
assert(Core.validateLook({ slots = { Unknown = "bad" } }) == nil)
assert(Core.validateLook({ slots = {}, useFashionMovementAnimations = "false" }) == nil)
assert(Core.validateLook({ slots = {}, useFashionFootstepSounds = "true" }) == nil)

local allSlots = {
    Head = "helmet",
    Headset = "headset",
    InnerClothes = "jumpsuit",
    OuterClothes = "divingsuit",
    Bag = "toolbelt",
    HealthInterface = "healthscannerhud"
}
local look = assert(Core.newLook(true, true, allSlots))
local lookBuffer = newBuffer()
assert(Core.writeLook(lookBuffer, look))
local decodedLook = assert(Core.readLook(lookBuffer))
assert(Core.lookEquals(look, decodedLook))
assertEqual(decodedLook.hideHair, true)
assertEqual(decodedLook.useFashionMovementAnimations, true)
assertEqual(decodedLook.useFashionFootstepSounds, false)

local fashionFootstepLook = assert(Core.newLook(
    true,
    true,
    allSlots,
    nil,
    nil,
    true,
    true
))
assert(not Core.lookEquals(look, fashionFootstepLook),
    "footstep sound source must participate in look equality/signatures")
local fashionFootstepBuffer = newBuffer()
assert(Core.writeLook(fashionFootstepBuffer, fashionFootstepLook))
fashionFootstepBuffer.FinalizeForTransport()
assertEqual(assert(Core.readLook(fashionFootstepBuffer)).useFashionFootstepSounds, true,
    "wire look round-trip lost fashion footsteps")

local equippedMovementLook = assert(Core.newLook(
    true,
    true,
    allSlots,
    nil,
    nil,
    false
))
assert(not Core.lookEquals(look, equippedMovementLook),
    "movement animation source must participate in look equality/signatures")
local equippedMovementBuffer = newBuffer()
assert(Core.writeLook(equippedMovementBuffer, equippedMovementLook))
equippedMovementBuffer.FinalizeForTransport()
assertEqual(assert(Core.readLook(equippedMovementBuffer)).useFashionMovementAnimations, false,
    "wire look round-trip lost equipped-gear movement")

local packedRed = 0x7F1122FF
local coloredLook = assert(Core.newLook(
    true,
    false,
    { Head = "helmet", InnerClothes = "jumpsuit" },
    nil,
    { Head = packedRed, InnerClothes = 0 }
))
assertEqual(coloredLook.colors.Head, packedRed)
assertEqual(coloredLook.colors.InnerClothes, 0)
assertEqual(assert(Core.copyLook(coloredLook)).colors.Head, packedRed)
assertEqual(assert(Core.toLegacyLook(coloredLook)).Head.color, packedRed)
local coloredBuffer = newBuffer()
assert(Core.writeLook(coloredBuffer, coloredLook))
coloredBuffer.FinalizeForTransport()
assert(Core.lookEquals(coloredLook, assert(Core.readLook(coloredBuffer))))
local recoloredLook = assert(Core.newLook(
    true,
    false,
    { Head = "helmet", InnerClothes = "jumpsuit" },
    nil,
    { Head = packedRed + 1, InnerClothes = 0 }
))
assert(not Core.lookEquals(coloredLook, recoloredLook),
    "recoloring the same prefab must change look equality/signature")
assert(Core.newLook(true, false, { Head = "helmet" }, nil, { Head = -1 }) == nil)
assert(Core.newLook(true, false, { Head = "helmet" }, nil, { Head = 4294967296 }) == nil)
assert(Core.newLook(true, false, { Head = "helmet" }, nil, { Head = 1.5 }) == nil)
assert(Core.newLook(true, false, {}, nil, { Head = packedRed }) == nil)
assert(Core.newLook(true, false, { Head = "helmet" }, nil, { Unknown = packedRed }) == nil)

local triStateVisibility = {
    Hair = Core.ATTACHMENT_VISIBILITY.Show,
    Beard = Core.ATTACHMENT_VISIBILITY.Hide,
    Moustache = Core.ATTACHMENT_VISIBILITY.Auto,
    FaceAttachment = Core.ATTACHMENT_VISIBILITY.Show
}
local triStateLook = assert(Core.newLook(true, false, { Head = "helmet" }, triStateVisibility))
assertEqual(triStateLook.hideHair, false,
    "legacy hideHair must be false unless Hair/Beard/Moustache are all hidden")
local forceHide, forceShow = Core.attachmentVisibilityMasks(triStateLook.attachmentVisibility)
assertEqual(forceHide, 0x02)
assertEqual(forceShow, 0x09)
local decodedVisibility = assert(Core.attachmentVisibilityFromMasks(forceHide, forceShow))
for _, key in ipairs(Core.ATTACHMENT_KEYS) do
    assertEqual(decodedVisibility[key], triStateVisibility[key], "visibility mask round-trip failed for " .. key)
end
assert(Core.attachmentVisibilityFromMasks(0x10, 0) == nil)
assert(Core.attachmentVisibilityFromMasks(0x01, 0x01) == nil)
assert(Core.validateAttachmentVisibility({
    Hair = "auto",
    Beard = "auto",
    Moustache = "auto"
}) == nil)
assert(Core.validateAttachmentVisibility({
    Hair = "auto",
    Beard = "auto",
    Moustache = "auto",
    FaceAttachment = "auto",
    Unknown = "hide"
}) == nil)
assert(not Core.lookEquals(look, triStateLook),
    "look equality/signature must include all four attachment visibility states")

local triStateBuffer = newBuffer()
assert(Core.writeLook(triStateBuffer, triStateLook))
triStateBuffer.FinalizeForTransport()
local triStateDecoded = assert(Core.readLook(triStateBuffer))
assert(Core.lookEquals(triStateLook, triStateDecoded))

local oldWireLook = newBuffer()
oldWireLook.WriteUInt16(Core.LOOK_SCHEMA_VERSION)
oldWireLook.WriteBoolean(true)
oldWireLook.WriteBoolean(true)
oldWireLook.WriteUInt16(0)
oldWireLook.FinalizeForTransport()
local migratedOldWireLook = assert(Core.readLook(oldWireLook))
assertEqual(migratedOldWireLook.useFashionMovementAnimations, true)
assertEqual(migratedOldWireLook.attachmentVisibility.Hair, "hide")
assertEqual(migratedOldWireLook.attachmentVisibility.Beard, "hide")
assertEqual(migratedOldWireLook.attachmentVisibility.Moustache, "hide")
assertEqual(migratedOldWireLook.attachmentVisibility.FaceAttachment, "auto")

local function lookPrefixBuffer()
    local buffer = newBuffer()
    buffer.WriteUInt16(Core.LOOK_SCHEMA_VERSION)
    buffer.WriteBoolean(true)
    buffer.WriteBoolean(false)
    buffer.WriteUInt16(0)
    return buffer
end

local oldExtensionLook = lookPrefixBuffer()
oldExtensionLook.WriteByte(Core.LOOK_EXTENSION_MARKER)
oldExtensionLook.WriteByte(1)
oldExtensionLook.WriteByte(0)
oldExtensionLook.WriteByte(0)
oldExtensionLook.FinalizeForTransport()
local migratedOldExtensionLook = assert(Core.readLook(oldExtensionLook))
assertEqual(migratedOldExtensionLook.useFashionMovementAnimations, true,
    "v1 look extensions must default to fashion-priority movement")
assertEqual(migratedOldExtensionLook.useFashionFootstepSounds, false,
    "v1 look extensions must default to equipment footsteps")

local movementExtensionLook = lookPrefixBuffer()
movementExtensionLook.WriteByte(Core.LOOK_EXTENSION_MARKER)
movementExtensionLook.WriteByte(2)
movementExtensionLook.WriteByte(0)
movementExtensionLook.WriteByte(0)
movementExtensionLook.WriteByte(0)
movementExtensionLook.FinalizeForTransport()
local migratedMovementExtensionLook = assert(Core.readLook(movementExtensionLook))
assertEqual(migratedMovementExtensionLook.useFashionMovementAnimations, false)
assertEqual(migratedMovementExtensionLook.useFashionFootstepSounds, false,
    "v2 look extensions must default to equipment footsteps")

local invalidAnimationSource = lookPrefixBuffer()
invalidAnimationSource.WriteByte(Core.LOOK_EXTENSION_MARKER)
invalidAnimationSource.WriteByte(Core.LOOK_EXTENSION_VERSION)
invalidAnimationSource.WriteByte(0)
invalidAnimationSource.WriteByte(0)
invalidAnimationSource.WriteByte(2)
invalidAnimationSource.WriteByte(0)
invalidAnimationSource.FinalizeForTransport()
assert(Core.readLook(invalidAnimationSource) == nil)

local invalidFootstepSource = lookPrefixBuffer()
invalidFootstepSource.WriteByte(Core.LOOK_EXTENSION_MARKER)
invalidFootstepSource.WriteByte(Core.LOOK_EXTENSION_VERSION)
invalidFootstepSource.WriteByte(0)
invalidFootstepSource.WriteByte(0)
invalidFootstepSource.WriteByte(1)
invalidFootstepSource.WriteByte(2)
invalidFootstepSource.FinalizeForTransport()
assert(Core.readLook(invalidFootstepSource) == nil)

for byteCount = 1, 3 do
    local partial = lookPrefixBuffer()
    for _ = 1, byteCount do partial.WriteByte(0) end
    partial.FinalizeForTransport()
    local malformed, reason = Core.readLook(partial)
    assert(malformed == nil and tostring(reason):find("extension length", 1, true) ~= nil)
end
local unknownMarker = lookPrefixBuffer()
unknownMarker.WriteByte(0x58)
unknownMarker.WriteByte(Core.LOOK_EXTENSION_VERSION)
unknownMarker.WriteByte(0)
unknownMarker.WriteByte(0)
unknownMarker.FinalizeForTransport()
assert(Core.readLook(unknownMarker) == nil)
local unknownExtensionVersion = lookPrefixBuffer()
unknownExtensionVersion.WriteByte(Core.LOOK_EXTENSION_MARKER)
unknownExtensionVersion.WriteByte(99)
unknownExtensionVersion.WriteByte(0)
unknownExtensionVersion.WriteByte(0)
unknownExtensionVersion.FinalizeForTransport()
assert(Core.readLook(unknownExtensionVersion) == nil)
local unknownMaskBit = lookPrefixBuffer()
unknownMaskBit.WriteByte(Core.LOOK_EXTENSION_MARKER)
unknownMaskBit.WriteByte(Core.LOOK_EXTENSION_VERSION)
unknownMaskBit.WriteByte(0x10)
unknownMaskBit.WriteByte(0)
unknownMaskBit.FinalizeForTransport()
assert(Core.readLook(unknownMaskBit) == nil)
local overlappingMasks = lookPrefixBuffer()
overlappingMasks.WriteByte(Core.LOOK_EXTENSION_MARKER)
overlappingMasks.WriteByte(Core.LOOK_EXTENSION_VERSION)
overlappingMasks.WriteByte(0x01)
overlappingMasks.WriteByte(0x01)
overlappingMasks.FinalizeForTransport()
assert(Core.readLook(overlappingMasks) == nil)

local helloBuffer = newBuffer()
assert(Core.writeServerHello(helloBuffer, 7, Core.CAPABILITY.AttachmentVisibility))
local hello = assert(Core.readServerHello(helloBuffer))
assertEqual(hello.revision, 7)
assertEqual(hello.capabilities, Core.CAPABILITY.AttachmentVisibility)
assert(Core.CAPABILITY.CrewTargeting == 0x04, "crew targeting capability changed unexpectedly")
assert(Core.CAPABILITY.FootstepSoundSource == 0x08,
    "footstep sound-source capability changed unexpectedly")
local oldHelloBuffer = newBuffer()
oldHelloBuffer.WriteUInt16(Core.PROTOCOL_VERSION)
oldHelloBuffer.WriteUInt32(8)
local oldHello = assert(Core.readServerHello(oldHelloBuffer))
assertEqual(oldHello.capabilities, 0)
for byteCount = 1, 2 do
    local partialHello = newBuffer()
    partialHello.WriteUInt16(Core.PROTOCOL_VERSION)
    partialHello.WriteUInt32(0)
    for _ = 1, byteCount do partialHello.WriteByte(0) end
    assert(Core.readServerHello(partialHello) == nil)
end

local command = {
    clientSessionId = "session-1",
    operationId = "session-1:4",
    baseRevision = 3,
    kind = Core.COMMAND.Apply,
    look = look
}
local commandBuffer = newBuffer()
assert(Core.writeCommand(commandBuffer, command))
commandBuffer.FinalizeForTransport()
local decodedCommand = assert(Core.readCommand(commandBuffer))
assertEqual(decodedCommand.operationId, command.operationId)
assertEqual(decodedCommand.baseRevision, 3)
assert(Core.lookEquals(decodedCommand.look, look))

local targetCommand = {
    clientSessionId = "session-1",
    operationId = "session-1:crew",
    baseRevision = 3,
    kind = Core.COMMAND.Apply,
    targetCharacterId = 77,
    look = look
}
local targetCommandBuffer = newBuffer()
assert(Core.writeTargetCommand(targetCommandBuffer, targetCommand))
targetCommandBuffer.FinalizeForTransport()
local decodedTargetCommand = assert(Core.readTargetCommand(targetCommandBuffer))
assertEqual(decodedTargetCommand.targetCharacterId, 77)
assertEqual(decodedTargetCommand.kind, Core.COMMAND.Apply)
assert(Core.lookEquals(decodedTargetCommand.look, look),
    "target command corrupted the look extension")
for _, invalidTarget in ipairs({ 0, -1, 1.5, 65536 }) do
    local invalid = {}
    for key, value in pairs(targetCommand) do invalid[key] = value end
    invalid.targetCharacterId = invalidTarget
    assert(not Core.writeTargetCommand(newBuffer(), invalid),
        "accepted invalid target character ID " .. tostring(invalidTarget))
end

local storedApplyBuffer = newBuffer()
assert(Core.writeCommand(storedApplyBuffer, {
    clientSessionId = "session-1",
    operationId = "session-1:stored",
    baseRevision = 4,
    kind = Core.COMMAND.Apply
}))
local storedApply = assert(Core.readCommand(storedApplyBuffer))
assertEqual(storedApply.kind, Core.COMMAND.Apply)
assert(storedApply.look == nil, "v2 apply may select the server-stored look")

local stateBuffer = newBuffer()
assert(Core.writeState(stateBuffer, { revision = 4, characterId = 42, active = true, look = look }))
stateBuffer.FinalizeForTransport()
local decodedState = assert(Core.readState(stateBuffer))
assertEqual(decodedState.revision, 4)
assertEqual(decodedState.characterId, 42)
assertEqual(decodedState.active, true)

local ackBuffer = newBuffer()
assert(Core.writeAck(ackBuffer, { operationId = "session-1:4", accepted = true, revision = 4, reason = "ok" }))
local decodedAck = assert(Core.readAck(ackBuffer))
assertEqual(decodedAck.operationId, "session-1:4")
assertEqual(decodedAck.accepted, true)

local tooLongIdentifier = string.rep("x", Core.LIMITS.MAX_IDENTIFIER_BYTES + 1)
assert(Core.newLook(true, false, { Head = tooLongIdentifier }) == nil)
assert(Core.newLook(true, false, { Unknown = "x" }) == nil)

local unknownVersionBuffer = newBuffer()
unknownVersionBuffer.WriteUInt16(99)
local unknownVersionLook, unknownVersionReason = tryReadLook(unknownVersionBuffer)
assert(unknownVersionLook == nil)
assert(tostring(unknownVersionReason):find("unsupported", 1, true) ~= nil)

local truncatedBuffer = newBuffer()
truncatedBuffer.WriteUInt16(Core.LOOK_SCHEMA_VERSION)
local truncatedLook, truncatedReason = tryReadLook(truncatedBuffer)
assert(truncatedLook == nil)
assert(tostring(truncatedReason):find("malformed", 1, true) ~= nil)

local duplicateSlotBuffer = newBuffer()
duplicateSlotBuffer.WriteUInt16(Core.LOOK_SCHEMA_VERSION)
duplicateSlotBuffer.WriteBoolean(true)
duplicateSlotBuffer.WriteBoolean(false)
duplicateSlotBuffer.WriteUInt16(2)
duplicateSlotBuffer.WriteString("Head")
duplicateSlotBuffer.WriteString("helmet")
duplicateSlotBuffer.WriteBoolean(false)
duplicateSlotBuffer.WriteString("Head")
duplicateSlotBuffer.WriteString("anotherhelmet")
duplicateSlotBuffer.WriteBoolean(false)
local duplicateLook, duplicateReason = tryReadLook(duplicateSlotBuffer)
assert(duplicateLook == nil)
assert(tostring(duplicateReason):find("duplicate", 1, true) ~= nil)

local truncatedColorBuffer = newBuffer()
truncatedColorBuffer.WriteUInt16(Core.LOOK_SCHEMA_VERSION)
truncatedColorBuffer.WriteBoolean(true)
truncatedColorBuffer.WriteBoolean(false)
truncatedColorBuffer.WriteUInt16(1)
truncatedColorBuffer.WriteString("Head")
truncatedColorBuffer.WriteString("helmet")
truncatedColorBuffer.WriteBoolean(true)
local truncatedColor, truncatedColorReason = tryReadLook(truncatedColorBuffer)
assert(truncatedColor == nil)
assert(tostring(truncatedColorReason):find("malformed", 1, true) ~= nil)

local client = Core.newClientState({ characterKey = "42", look = look, revision = 4 })
local pending, effects = Core.reduce(client, {
    type = "CommandRequested",
    operationId = "session-1:5",
    kind = Core.COMMAND.Clear
})
assertEqual(pending.phase, Core.PHASE.ClearPending)
assertEqual(effects[1].type, "SendCommand")
assertEqual(#effects, 1)

local acknowledged, clearAckEffects = Core.reduce(pending, {
    type = "AckReceived",
    operationId = "session-1:5",
    accepted = true,
    revision = 5
})
assertEqual(acknowledged.phase, Core.PHASE.ClearPending)
assertEqual(clearAckEffects[1].type, "ClearRender")
local clearPersisting = Core.reduce(acknowledged, { type = "ClearRenderSucceeded" })
local cleared = Core.reduce(clearPersisting, { type = "PersistenceSucceeded" })
assertEqual(cleared.phase, Core.PHASE.SavedInactive)
assertEqual(cleared.revision, 5)

local stale, staleEffects = Core.reduce(cleared, {
    type = "RemoteStateReceived",
    revision = 4,
    characterId = 42,
    active = true,
    look = look
})
assertEqual(stale.phase, Core.PHASE.SavedInactive)
assertEqual(staleEffects[1].type, "IgnoredStaleState")

local awaitingAck = Core.newClientState({ characterKey = "42", look = look, revision = 8 })
awaitingAck = Core.reduce(awaitingAck, {
    type = "CommandRequested",
    operationId = "session-1:9",
    kind = Core.COMMAND.Apply,
    look = look
})
local foreignAckState, foreignAckEffects = Core.reduce(awaitingAck, {
    type = "AckReceived",
    operationId = "another-session:999",
    accepted = true,
    revision = 999
})
assertEqual(foreignAckEffects[1].type, "IgnoredForeignAck")
assertEqual(foreignAckState.revision, 8,
    "a foreign acknowledgement must not advance the local revision")
assertEqual(foreignAckState.pendingOperationId, "session-1:9")
local matchingAfterForeign = Core.reduce(foreignAckState, {
    type = "AckReceived",
    operationId = "session-1:9",
    accepted = true,
    revision = 9
})
assertEqual(matchingAfterForeign.revision, 9,
    "the matching acknowledgement was poisoned by a foreign revision")
assertEqual(matchingAfterForeign.pendingOperationId, nil)

local staleAckState, staleAckEffects = Core.reduce(awaitingAck, {
    type = "AckReceived",
    operationId = "session-1:9",
    accepted = true,
    revision = 7
})
assertEqual(staleAckState.phase, Core.PHASE.ApplyPending)
assertEqual(staleAckEffects[1].type, "IgnoredStaleAck")

local timedOutApply = Core.reduce(awaitingAck, {
    type = "CommandTimedOut",
    operationId = "session-1:9",
    reason = "test timeout"
})
assertEqual(timedOutApply.phase, Core.PHASE.Faulted)
assertEqual(timedOutApply.pendingOperationId, nil)
assertEqual(timedOutApply.pendingKind, nil)
assertEqual(Core.clientViewModel(timedOutApply).busy, false,
    "an Apply timeout must release all busy-gated controls")

local rejectedAckState = Core.reduce(awaitingAck, {
    type = "AckReceived",
    operationId = "session-1:9",
    accepted = false,
    revision = 8,
    reason = "stale base revision"
})
assertEqual(rejectedAckState.phase, Core.PHASE.Faulted)
assertEqual(rejectedAckState.error, "stale base revision")

-- Apply is also used to refresh an already-active look after equipment changes.
-- A failed or cancelled request must restore that accepted active state, while
-- an Apply requested from an inactive state must remain inactive.
local activeApplyRollbackBase = Core.reduce(
    Core.newClientState({ characterKey = "42", look = look, revision = 12 }),
    {
        type = "RestoreLook",
        look = look,
        active = true,
        autoApply = true
    }
)

local function pendingActiveApply(operationId)
    local result = Core.reduce(activeApplyRollbackBase, {
        type = "CommandRequested",
        operationId = operationId,
        kind = Core.COMMAND.Apply,
        look = look
    })
    assertEqual(result.active, false, "pending Apply must await authoritative state")
    assertEqual(result.rollbackActive, true, "pending Apply did not capture its active state")
    return result
end

local applyFailureCases = {
    {
        name = "send failure",
        event = function(operationId)
            return {
                type = "CommandSendFailed",
                operationId = operationId,
                reason = "synthetic send failure"
            }
        end
    },
    {
        name = "rejected acknowledgement",
        event = function(operationId)
            return {
                type = "AckReceived",
                operationId = operationId,
                accepted = false,
                revision = 12,
                reason = "synthetic rejection"
            }
        end
    },
    {
        name = "timeout",
        event = function(operationId)
            return {
                type = "CommandTimedOut",
                operationId = operationId,
                reason = "synthetic timeout"
            }
        end
    }
}

for index, failureCase in ipairs(applyFailureCases) do
    local operationId = "session-apply-rollback:" .. tostring(index)
    local failed = Core.reduce(
        pendingActiveApply(operationId),
        failureCase.event(operationId)
    )
    assertEqual(failed.phase, Core.PHASE.Faulted, failureCase.name .. " did not fault")
    assertEqual(failed.active, true, failureCase.name .. " lost the accepted active state")
    assertEqual(failed.autoApply, true, failureCase.name .. " lost auto-apply intent")
    assertEqual(failed.pendingOperationId, nil, failureCase.name .. " left an operation pending")
    assert(Core.lookEquals(failed.look, look), failureCase.name .. " changed the accepted look")
end

local inactiveApplyPending = Core.reduce(
    Core.newClientState({ characterKey = "42", look = look, revision = 12 }),
    {
        type = "CommandRequested",
        operationId = "session-apply-inactive",
        kind = Core.COMMAND.Apply,
        look = look
    }
)
local inactiveApplyRejected = Core.reduce(inactiveApplyPending, {
    type = "AckReceived",
    operationId = "session-apply-inactive",
    accepted = false,
    revision = 12,
    reason = "synthetic rejection"
})
assertEqual(inactiveApplyRejected.active, false,
    "rejected inactive Apply was incorrectly marked active")
assertEqual(inactiveApplyRejected.autoApply, false,
    "rejected inactive Apply gained auto-apply intent")

local lifecycleCapturedLook = assert(Core.newLook(true, false, { Head = "replacementhelmet" }))
local lifecycleVisibility = Core.attachmentVisibilityFromLegacy(false)
local lifecyclePendingCases = {
    {
        name = Core.COMMAND.Save,
        state = function(operationId)
            local saving = Core.reduce(activeApplyRollbackBase, {
                type = "SaveRequested",
                remote = true,
                operationId = operationId
            })
            return Core.reduce(saving, {
                type = "CaptureSucceeded",
                look = lifecycleCapturedLook
            })
        end
    },
    {
        name = Core.COMMAND.Apply,
        state = function(operationId)
            return pendingActiveApply(operationId)
        end
    },
    {
        name = Core.COMMAND.Clear,
        state = function(operationId)
            return Core.reduce(activeApplyRollbackBase, {
                type = "CommandRequested",
                operationId = operationId,
                kind = Core.COMMAND.Clear
            })
        end
    },
    {
        name = Core.COMMAND.Forget,
        state = function(operationId)
            return Core.reduce(activeApplyRollbackBase, {
                type = "CommandRequested",
                operationId = operationId,
                kind = Core.COMMAND.Forget
            })
        end
    },
    {
        name = Core.COMMAND.Visibility,
        state = function(operationId)
            return Core.reduce(activeApplyRollbackBase, {
                type = "SetAttachmentVisibility",
                attachmentVisibility = lifecycleVisibility,
                remote = true,
                operationId = operationId
            })
        end
    },
    {
        name = Core.COMMAND.Animation,
        state = function(operationId)
            return Core.reduce(activeApplyRollbackBase, {
                type = "SetMovementAnimationSource",
                enabled = false,
                remote = true,
                operationId = operationId
            })
        end
    },
    {
        name = Core.COMMAND.Footstep,
        state = function(operationId)
            return Core.reduce(activeApplyRollbackBase, {
                type = "SetFootstepSoundSource",
                enabled = true,
                remote = true,
                operationId = operationId
            })
        end
    }
}

for index, pendingCase in ipairs(lifecyclePendingCases) do
    local operationId = "session-lifecycle-" .. pendingCase.name .. ":" .. tostring(index)
    local transitioned, transitionEffects = Core.reduce(
        pendingCase.state(operationId),
        { type = "PrepareSceneTransition", reapply = false }
    )
    assertEqual(transitioned.phase, Core.PHASE.SavedInactive,
        pendingCase.name .. " lifecycle cancellation chose the wrong phase")
    assertEqual(transitioned.active, false,
        pendingCase.name .. " stayed active across the scene boundary")
    assertEqual(transitioned.autoApply, true,
        pendingCase.name .. " lost the accepted scene-reapply intent")
    assertEqual(transitioned.pendingOperationId, nil,
        pendingCase.name .. " remained pending across the scene boundary")
    assertEqual(transitioned.rollbackLook, nil,
        pendingCase.name .. " left rollback state behind")
    assert(Core.lookEquals(transitioned.look, look),
        pendingCase.name .. " persisted an unaccepted optimistic look")
    assertEqual(#transitionEffects, 1,
        pendingCase.name .. " scene cancellation emitted unexpected effects")
    assertEqual(transitionEffects[1].type, "Persist",
        pendingCase.name .. " scene cancellation did not persist the accepted look")
    assert(Core.lookEquals(transitionEffects[1].look, look),
        pendingCase.name .. " scene cancellation persisted the wrong look")
end

local lostDuringApply, lostDuringApplyEffects = Core.reduce(
    pendingActiveApply("session-lifecycle-character-lost"),
    { type = "CharacterLost" }
)
assertEqual(lostDuringApply.phase, Core.PHASE.NoCharacter)
assertEqual(lostDuringApply.active, false)
assertEqual(lostDuringApply.autoApply, true,
    "CharacterLost discarded the accepted active Apply state")
assertEqual(lostDuringApply.pendingOperationId, nil)
assertEqual(lostDuringApplyEffects[1].type, "ClearRender")
assertEqual(lostDuringApplyEffects[1].preserveAutoApply, true)

local detachedCrew, detachedCrewEffects = Core.reduce(
    pendingActiveApply("session-lifecycle-crew-handoff"),
    { type = "CharacterLost", preserveRender = true }
)
assertEqual(detachedCrew.phase, Core.PHASE.NoCharacter)
assertEqual(detachedCrew.active, false)
assertEqual(detachedCrew.autoApply, true)
assertEqual(#detachedCrewEffects, 0,
    "a live single-player crew handoff disposed its retained renderer")

-- Once the server accepts a command, lifecycle cleanup keeps the accepted
-- result instead of restoring the pre-command rollback snapshot.
local acceptedLifecycleSave = Core.reduce(activeApplyRollbackBase, {
    type = "SaveRequested",
    remote = true,
    operationId = "session-lifecycle-accepted-save"
})
acceptedLifecycleSave = Core.reduce(acceptedLifecycleSave, {
    type = "CaptureSucceeded",
    look = lifecycleCapturedLook
})
acceptedLifecycleSave = Core.reduce(acceptedLifecycleSave, {
    type = "AckReceived",
    operationId = "session-lifecycle-accepted-save",
    accepted = true,
    revision = 13
})
local acceptedLifecycleTransition, acceptedLifecycleEffects = Core.reduce(
    acceptedLifecycleSave,
    { type = "PrepareSceneTransition", reapply = false }
)
assert(Core.lookEquals(acceptedLifecycleTransition.look, lifecycleCapturedLook),
    "scene cleanup rolled back a server-accepted look")
assertEqual(acceptedLifecycleTransition.autoApply, false,
    "server-accepted inactive Save gained reapply intent")
assertEqual(acceptedLifecycleEffects[1].type, "Persist")
assert(Core.lookEquals(acceptedLifecycleEffects[1].look, lifecycleCapturedLook),
    "scene cleanup persisted the pre-command look after server acceptance")

-- The client controller is the only place that executes effects. Every adapter
-- reports a success/failure event back through the same reducer before the next
-- effect is allowed to run.
local adapterOrder = {}
local controller = Core.createClientController(
    Core.newClientState({ characterKey = "42" }),
    {
        Capture = function()
            adapterOrder[#adapterOrder + 1] = "Capture"
            return { type = "CaptureSucceeded", look = look }
        end,
        Unequip = function()
            adapterOrder[#adapterOrder + 1] = "Unequip"
            return { type = "UnequipSucceeded" }
        end,
        Persist = function()
            adapterOrder[#adapterOrder + 1] = "Persist"
            return { type = "PersistenceSucceeded" }
        end
    }
)
local saveEffects, saveFeedback = controller.dispatch({ type = "SaveRequested" })
assertEqual(table.concat(adapterOrder, ","), "Capture,Persist,Unequip")
assertEqual(saveEffects[1].type, "Capture")
assertEqual(saveEffects[2].type, "Persist")
assertEqual(saveEffects[3].type, "Unequip")
assertEqual(saveFeedback[1].type, "CaptureSucceeded")
assertEqual(saveFeedback[2].type, "PersistenceSucceeded")
assertEqual(saveFeedback[3].type, "UnequipSucceeded")
assertEqual(controller.getState().phase, Core.PHASE.SavedInactive)
assertEqual(controller.getState().autoApply, false,
    "saving a look must not enable scene reapply before the look is applied")

-- View models are detached snapshots: UI code cannot mutate reducer state.
local view = controller.getViewModel()
assertEqual(view.canApply, true)
view.look.slots.Head = "tampered"
assertEqual(controller.getState().look.slots.Head, "helmet")

-- A capture failure retains the previously accepted look and active flag while
-- surfacing Faulted. No later Unequip/Persist adapter may run.
local previousLook = assert(Core.newLook(true, false, { Head = "oldhelmet" }))
local failedState = Core.newClientState({ characterKey = "42", look = previousLook })
failedState = Core.reduce(failedState, {
    type = "RestoreLook",
    look = previousLook,
    active = true,
    autoApply = true
})
local failedOrder = {}
local failedController = Core.createClientController(failedState, {
    Capture = function()
        failedOrder[#failedOrder + 1] = "Capture"
        return false, "synthetic capture failure"
    end,
    Unequip = function()
        failedOrder[#failedOrder + 1] = "Unequip"
        return true
    end,
    Persist = function()
        failedOrder[#failedOrder + 1] = "Persist"
        return true
    end
})
failedController.dispatch({ type = "SaveRequested" })
local captureFailedState = failedController.getState()
assertEqual(table.concat(failedOrder, ","), "Capture")
assertEqual(captureFailedState.phase, Core.PHASE.Faulted)
assertEqual(captureFailedState.active, true)
assert(Core.lookEquals(captureFailedState.look, previousLook))

-- Render failure is also fail-closed: the accepted look and activation survive.
local renderController = Core.createClientController(failedState, {
    Render = function() return false, "synthetic render failure" end
})
renderController.dispatch({ type = "LocalApplyRequested", look = look })
local renderFailedState = renderController.getState()
assertEqual(renderFailedState.phase, Core.PHASE.Faulted)
assertEqual(renderFailedState.active, true)
assert(Core.lookEquals(renderFailedState.look, previousLook))

-- Clear and Forget use the same feedback pipeline and never mutate persistence
-- before the renderer acknowledges cleanup.
local clearOrder = {}
local clearController = Core.createClientController(failedState, {
    ClearRender = function()
        clearOrder[#clearOrder + 1] = "ClearRender"
        return { type = "ClearRenderSucceeded" }
    end,
    Persist = function()
        clearOrder[#clearOrder + 1] = "Persist"
        return { type = "PersistenceSucceeded" }
    end,
    ClearPersistence = function()
        clearOrder[#clearOrder + 1] = "ClearPersistence"
        return { type = "PersistenceSucceeded" }
    end
})
clearController.dispatch({ type = "LocalClearRequested" })
assertEqual(table.concat(clearOrder, ","), "ClearRender,Persist")
assertEqual(clearController.getState().phase, Core.PHASE.SavedInactive)
assertEqual(clearController.getState().autoApply, false)
clearOrder = {}
clearController.dispatch({ type = "LocalForgetRequested" })
assertEqual(table.concat(clearOrder, ","), "ClearRender,ClearPersistence")
assertEqual(clearController.getState().phase, Core.PHASE.Idle)
assertEqual(clearController.getState().autoApply, false)
assertEqual(clearController.getViewModel().hasSavedLook, false)

-- Character teardown disposes renderer state without clearing the previously
-- active look's scene-reapply intent. The replacement character renders once.
local sceneCalls = {}
local sceneState = Core.newClientState({ characterKey = "old-character", look = look })
sceneState = Core.reduce(sceneState, {
    type = "RestoreLook",
    look = look,
    active = true,
    autoApply = false
})
local sceneController = Core.createClientController(sceneState, {
    ClearRender = function(effect)
        sceneCalls[#sceneCalls + 1] = "ClearRender:" .. tostring(effect.preserveAutoApply)
        return { type = "ClearRenderSucceeded" }
    end,
    Render = function()
        sceneCalls[#sceneCalls + 1] = "Render"
        return { type = "RenderSucceeded" }
    end,
    Persist = function()
        sceneCalls[#sceneCalls + 1] = "Persist"
        return { type = "PersistenceSucceeded" }
    end
})
sceneController.dispatch({ type = "CharacterLost" })
assertEqual(sceneController.getState().phase, Core.PHASE.NoCharacter)
assertEqual(sceneController.getState().autoApply, true)
assertEqual(table.concat(sceneCalls, ","), "ClearRender:true,Persist")
sceneController.dispatch({ type = "CharacterReady", characterKey = "new-character" })
assertEqual(sceneController.getState().autoApply, true)
sceneController.dispatch({ type = "LocalApplyRequested" })
assertEqual(sceneController.getState().phase, Core.PHASE.Active)
assertEqual(sceneController.getState().autoApply, true)
assertEqual(table.concat(sceneCalls, ","), "ClearRender:true,Persist,Render,Persist")

local savedInactiveScene = Core.createClientController(
    Core.newClientState({ characterKey = "saved-character", look = look, autoApply = false }),
    {
        ClearRender = function() return { type = "ClearRenderSucceeded" } end,
        Persist = function() return { type = "PersistenceSucceeded" } end
    }
)
savedInactiveScene.dispatch({ type = "CharacterLost" })
assertEqual(savedInactiveScene.getState().autoApply, false,
    "a saved but inactive look must stay inactive across character replacement")

local emptyCleanupCalls = {}
local emptyCleanupAdapters = {
    ClearRender = function()
        emptyCleanupCalls[#emptyCleanupCalls + 1] = "ClearRender"
        return { type = "ClearRenderSucceeded" }
    end,
    Persist = function()
        emptyCleanupCalls[#emptyCleanupCalls + 1] = "Persist"
        return false, "nil look must not be persisted"
    end
}
local lostWithoutLook = Core.createClientController(
    Core.newClientState({ characterKey = "42" }),
    emptyCleanupAdapters
)
lostWithoutLook.dispatch({ type = "CharacterLost" })
assertEqual(lostWithoutLook.getState().phase, Core.PHASE.NoCharacter)
assertEqual(table.concat(emptyCleanupCalls, ","), "ClearRender")
emptyCleanupCalls = {}
local clearWithoutLook = Core.createClientController(
    Core.newClientState({ characterKey = "42" }),
    emptyCleanupAdapters
)
clearWithoutLook.dispatch({ type = "LocalClearRequested" })
assertEqual(clearWithoutLook.getState().phase, Core.PHASE.Idle)
assertEqual(table.concat(emptyCleanupCalls, ","), "ClearRender")

-- A SAVE acknowledgement is sufficient even if the canonical inactive state
-- frame was dropped. Duplicate acknowledgements cannot strand ApplyPending.
local saveAckState = Core.newClientState({ characterKey = "42", look = look, revision = 10 })
saveAckState = Core.reduce(saveAckState, {
    type = "CommandRequested",
    operationId = "session-1:save",
    kind = Core.COMMAND.Save,
    look = look
})
assertEqual(saveAckState.phase, Core.PHASE.Saving)
local saveAckEffects
saveAckState, saveAckEffects = Core.reduce(saveAckState, {
    type = "AckReceived",
    operationId = "session-1:save",
    accepted = true,
    revision = 11,
    reason = "duplicate"
})
assertEqual(saveAckState.phase, Core.PHASE.Saving)
assertEqual(saveAckState.active, false)
assertEqual(saveAckEffects[1].type, "ClearRender")
saveAckState, saveAckEffects = Core.reduce(saveAckState, { type = "ClearRenderSucceeded", save = true })
assertEqual(saveAckEffects[1].type, "Persist")
saveAckState = Core.reduce(saveAckState, { type = "PersistenceSucceeded" })
assertEqual(saveAckState.phase, Core.PHASE.SavedInactive)
assertEqual(saveAckState.autoApply, false)

local remoteSaveCalls = {}
local remoteSaveInitial = Core.newClientState({ characterKey = "42", look = look, revision = 12 })
remoteSaveInitial = Core.reduce(remoteSaveInitial, {
    type = "RestoreLook",
    look = look,
    active = true,
    autoApply = true
})
local remoteSave = Core.createClientController(remoteSaveInitial, {
    Capture = function()
        remoteSaveCalls[#remoteSaveCalls + 1] = "Capture"
        return { type = "CaptureSucceeded", look = look }
    end,
    SendCommand = function(effect)
        remoteSaveCalls[#remoteSaveCalls + 1] = "SendCommand"
        return { type = "CommandSendSucceeded", operationId = effect.operationId, awaitAck = true }
    end,
    ClearRender = function(effect)
        remoteSaveCalls[#remoteSaveCalls + 1] = effect.save and "ClearRender:save" or "ClearRender"
        return { type = "ClearRenderSucceeded", save = effect.save == true }
    end,
    Persist = function()
        remoteSaveCalls[#remoteSaveCalls + 1] = "Persist"
        return { type = "PersistenceSucceeded" }
    end
})
remoteSave.dispatch({ type = "SaveRequested", remote = true, operationId = "session-1:remote-save" })
assertEqual(table.concat(remoteSaveCalls, ","), "Capture,SendCommand")
remoteSave.dispatch({
    type = "AckReceived",
    operationId = "session-1:remote-save",
    accepted = true,
    revision = 13
})
assertEqual(table.concat(remoteSaveCalls, ","), "Capture,SendCommand,ClearRender:save,Persist")
assertEqual(remoteSave.getState().phase, Core.PHASE.SavedInactive)
assertEqual(remoteSave.getState().active, false)
assertEqual(remoteSave.getState().autoApply, false)

-- Duplicate active state is a no-op and never asks the renderer to run twice.
local duplicateState = Core.newClientState({ characterKey = "42", look = look, revision = 12 })
duplicateState = Core.reduce(duplicateState, {
    type = "RestoreLook",
    look = look,
    active = true,
    autoApply = true
})
local duplicateResult, duplicateEffects = Core.reduce(duplicateState, {
    type = "RemoteStateReceived",
    revision = 12,
    characterId = 42,
    active = true,
    look = look
})
assertEqual(duplicateResult.phase, Core.PHASE.Active)
assertEqual(#duplicateEffects, 1)
assertEqual(duplicateEffects[1].type, "IgnoredDuplicateState")

local inactiveState = Core.newClientState({ characterKey = "42", look = look, revision = 13 })
local inactiveDuplicate, inactiveEffects = Core.reduce(inactiveState, {
    type = "RemoteStateReceived",
    revision = 13,
    characterId = 42,
    active = false,
    look = look
})
assertEqual(inactiveDuplicate.phase, Core.PHASE.SavedInactive)
assertEqual(#inactiveEffects, 1)
assertEqual(inactiveEffects[1].type, "IgnoredDuplicateState")

-- Remote destructive commands do not touch renderer/persistence before ACK.
local destructiveCalls = {}
local remoteClearController = Core.createClientController(duplicateState, {
    SendCommand = function(effect)
        destructiveCalls[#destructiveCalls + 1] = "SendCommand"
        return { type = "CommandSendSucceeded", operationId = effect.operationId, awaitAck = true }
    end,
    ClearRender = function()
        destructiveCalls[#destructiveCalls + 1] = "ClearRender"
        return { type = "ClearRenderSucceeded" }
    end,
    Persist = function()
        destructiveCalls[#destructiveCalls + 1] = "Persist"
        return { type = "PersistenceSucceeded" }
    end
})
remoteClearController.dispatch({
    type = "CommandRequested",
    operationId = "session-1:clear",
    kind = Core.COMMAND.Clear
})
assertEqual(table.concat(destructiveCalls, ","), "SendCommand")
assertEqual(remoteClearController.getState().active, true)
remoteClearController.dispatch({
    type = "AckReceived",
    operationId = "session-1:clear",
    accepted = false,
    revision = 12,
    reason = "stale base revision"
})
assertEqual(table.concat(destructiveCalls, ","), "SendCommand")
assertEqual(remoteClearController.getState().active, true)
assert(Core.lookEquals(remoteClearController.getState().look, look))

local stateFirstCalls = {}
local stateFirstForget = Core.createClientController(duplicateState, {
    SendCommand = function(effect)
        stateFirstCalls[#stateFirstCalls + 1] = "SendCommand"
        return { type = "CommandSendSucceeded", operationId = effect.operationId, awaitAck = true }
    end,
    ClearRender = function(effect)
        stateFirstCalls[#stateFirstCalls + 1] = "ClearRender"
        return { type = "ClearRenderSucceeded", forget = effect.forget == true }
    end,
    ClearPersistence = function()
        stateFirstCalls[#stateFirstCalls + 1] = "ClearPersistence"
        return { type = "PersistenceSucceeded" }
    end
})
stateFirstForget.dispatch({
    type = "CommandRequested",
    operationId = "session-1:forget-state-first",
    kind = Core.COMMAND.Forget
})
stateFirstForget.dispatch({
    type = "RemoteStateReceived",
    revision = 14,
    characterId = 42,
    active = false,
    look = nil
})
assertEqual(table.concat(stateFirstCalls, ","), "SendCommand,ClearRender,ClearPersistence")
assertEqual(stateFirstForget.getState().phase, Core.PHASE.Idle)
assertEqual(stateFirstForget.getViewModel().hasSavedLook, false)
local lateAckEffects = stateFirstForget.dispatch({
    type = "AckReceived",
    operationId = "session-1:forget-state-first",
    accepted = true,
    revision = 14
})
assertEqual(lateAckEffects[1].type, "IgnoredForeignAck")

-- Local Forget persistence failure is fail-closed: renderer cleanup is skipped
-- and the accepted in-memory look remains available.
local forgetCalls = {}
local localForgetController = Core.createClientController(duplicateState, {
    ClearPersistence = function()
        forgetCalls[#forgetCalls + 1] = "ClearPersistence"
        return false, "synthetic replace failure"
    end,
    ClearRender = function()
        forgetCalls[#forgetCalls + 1] = "ClearRender"
        return { type = "ClearRenderSucceeded", forget = true }
    end,
    RenderCompensation = function()
        forgetCalls[#forgetCalls + 1] = "RenderCompensation"
        return { type = "CompensationSucceeded" }
    end
})
localForgetController.dispatch({ type = "LocalForgetRequested" })
assertEqual(table.concat(forgetCalls, ","), "ClearRender,ClearPersistence,RenderCompensation")
assertEqual(localForgetController.getState().phase, Core.PHASE.Faulted)
assertEqual(localForgetController.getState().active, true)
assert(Core.lookEquals(localForgetController.getState().look, look))

local savePersistCalls = {}
local replacementLook = assert(Core.newLook(true, true, { Head = "replacementhelmet" }))
local savePersistFailure = Core.createClientController(duplicateState, {
    Capture = function()
        savePersistCalls[#savePersistCalls + 1] = "Capture"
        return { type = "CaptureSucceeded", look = replacementLook }
    end,
    Persist = function()
        savePersistCalls[#savePersistCalls + 1] = "Persist"
        return false, "synthetic atomic replace failure"
    end,
    AbortCapture = function() savePersistCalls[#savePersistCalls + 1] = "AbortCapture"; return true end,
    Unequip = function() savePersistCalls[#savePersistCalls + 1] = "Unequip"; return true end
})
savePersistFailure.dispatch({ type = "SaveRequested" })
assertEqual(table.concat(savePersistCalls, ","), "Capture,Persist,AbortCapture")
assertEqual(savePersistFailure.getState().phase, Core.PHASE.Faulted)
assertEqual(savePersistFailure.getState().active, true)
assert(Core.lookEquals(savePersistFailure.getState().look, look))

local unequipRollbackCalls = {}
local saveUnequipFailure = Core.createClientController(duplicateState, {
    Capture = function()
        unequipRollbackCalls[#unequipRollbackCalls + 1] = "Capture"
        return { type = "CaptureSucceeded", look = replacementLook }
    end,
    Persist = function(currentEffect)
        local identifier = currentEffect.look ~= nil and currentEffect.look.slots.Head or "nil"
        unequipRollbackCalls[#unequipRollbackCalls + 1] = "Persist:" .. tostring(identifier)
        return { type = "PersistenceSucceeded" }
    end,
    Unequip = function()
        unequipRollbackCalls[#unequipRollbackCalls + 1] = "Unequip"
        return false, "synthetic renderer commit failure"
    end
})
saveUnequipFailure.dispatch({ type = "SaveRequested" })
assertEqual(table.concat(unequipRollbackCalls, ","),
    "Capture,Persist:replacementhelmet,Unequip,Persist:helmet")
assertEqual(saveUnequipFailure.getState().phase, Core.PHASE.Faulted)
assertEqual(saveUnequipFailure.getState().active, true)
assert(Core.lookEquals(saveUnequipFailure.getState().look, look),
    "failed unequip must restore the prior in-memory look after restoring persistence")

local clearPersistCalls = {}
local clearPersistFailure = Core.createClientController(duplicateState, {
    ClearRender = function()
        clearPersistCalls[#clearPersistCalls + 1] = "ClearRender"
        return { type = "ClearRenderSucceeded" }
    end,
    Persist = function()
        clearPersistCalls[#clearPersistCalls + 1] = "Persist"
        return false, "synthetic atomic replace failure"
    end,
    RenderCompensation = function()
        clearPersistCalls[#clearPersistCalls + 1] = "RenderCompensation"
        return { type = "CompensationSucceeded" }
    end
})
clearPersistFailure.dispatch({ type = "LocalClearRequested" })
assertEqual(table.concat(clearPersistCalls, ","), "ClearRender,Persist,RenderCompensation")
assertEqual(clearPersistFailure.getState().phase, Core.PHASE.Faulted)
assertEqual(clearPersistFailure.getState().active, true)

local allShown = {
    Hair = "show",
    Beard = "show",
    Moustache = "show",
    FaceAttachment = "show"
}
local inactiveVisibilityState = Core.newClientState({
    characterKey = "42",
    look = look,
    revision = 10
})
local inactiveVisibilityPending, inactiveVisibilityEffects = Core.reduce(
    inactiveVisibilityState,
    {
        type = "SetAttachmentVisibility",
        attachmentVisibility = allShown
    }
)
assertEqual(inactiveVisibilityEffects[1].type, "Persist",
    "inactive local visibility changes must persist without rendering")
local inactiveVisibilitySaved = Core.reduce(
    inactiveVisibilityPending,
    { type = "PersistenceSucceeded" }
)
assertEqual(inactiveVisibilitySaved.look.attachmentVisibility.Hair, "show")
assertEqual(inactiveVisibilitySaved.pendingKind, nil)

local activeVisibilityState = Core.newClientState({
    characterKey = "42",
    look = look,
    revision = 10
})
activeVisibilityState = Core.reduce(activeVisibilityState, {
    type = "RestoreLook",
    look = look,
    active = true,
    autoApply = true
})
local activeVisibilityPending, activeVisibilityEffects = Core.reduce(
    activeVisibilityState,
    {
        type = "SetAttachmentVisibility",
        attachmentVisibility = allShown,
        remote = true,
        operationId = "visibility-active"
    }
)
assertEqual(activeVisibilityEffects[1].type, "ApplyAttachmentVisibility",
    "active visibility changes must preview before network/persistence")
local activeVisibilityRendered, renderedEffects = Core.reduce(
    activeVisibilityPending,
    { type = "AttachmentVisibilityUpdateSucceeded" }
)
assertEqual(renderedEffects[1].type, "SendCommand")
assertEqual(renderedEffects[1].kind, Core.COMMAND.Visibility)
local rejectedVisibility, rejectedEffects = Core.reduce(activeVisibilityRendered, {
    type = "AckReceived",
    operationId = "visibility-active",
    accepted = false,
    revision = 10,
    reason = "denied"
})
assertEqual(rejectedVisibility.look.attachmentVisibility.Hair, "hide")
assertEqual(rejectedEffects[1].type, "ApplyAttachmentVisibilityCompensation")

local activeAnimationPending, activeAnimationEffects = Core.reduce(
    activeVisibilityState,
    {
        type = "SetMovementAnimationSource",
        enabled = false,
        remote = true,
        operationId = "animation-active"
    }
)
assertEqual(activeAnimationEffects[1].type, "ApplyMovementAnimationSource")
assertEqual(activeAnimationEffects[1].useFashionMovementAnimations, false)
local activeAnimationRendered, animationRenderedEffects = Core.reduce(
    activeAnimationPending,
    { type = "MovementAnimationSourceUpdateSucceeded" }
)
assertEqual(animationRenderedEffects[1].type, "SendCommand")
assertEqual(animationRenderedEffects[1].kind, Core.COMMAND.Animation)
assertEqual(animationRenderedEffects[1].look.useFashionMovementAnimations, false)
local rejectedAnimation, rejectedAnimationEffects = Core.reduce(activeAnimationRendered, {
    type = "AckReceived",
    operationId = "animation-active",
    accepted = false,
    revision = 10,
    reason = "denied"
})
assertEqual(rejectedAnimation.look.useFashionMovementAnimations, true)
assertEqual(rejectedAnimationEffects[1].type, "ApplyMovementAnimationSourceCompensation")
assertEqual(rejectedAnimationEffects[1].useFashionMovementAnimations, true)

local activeFootstepPending, activeFootstepEffects = Core.reduce(
    activeVisibilityState,
    {
        type = "SetFootstepSoundSource",
        enabled = true,
        remote = true,
        operationId = "footstep-active"
    }
)
assertEqual(activeFootstepEffects[1].type, "ApplyFootstepSoundSource")
assertEqual(activeFootstepEffects[1].useFashionFootstepSounds, true)
local activeFootstepRendered, footstepRenderedEffects = Core.reduce(
    activeFootstepPending,
    { type = "FootstepSoundSourceUpdateSucceeded" }
)
assertEqual(footstepRenderedEffects[1].type, "SendCommand")
assertEqual(footstepRenderedEffects[1].kind, Core.COMMAND.Footstep)
assertEqual(footstepRenderedEffects[1].look.useFashionFootstepSounds, true)
local rejectedFootstep, rejectedFootstepEffects = Core.reduce(activeFootstepRendered, {
    type = "AckReceived",
    operationId = "footstep-active",
    accepted = false,
    revision = 10,
    reason = "denied"
})
assertEqual(rejectedFootstep.look.useFashionFootstepSounds, false)
assertEqual(rejectedFootstepEffects[1].type, "ApplyFootstepSoundSourceCompensation")
assertEqual(rejectedFootstepEffects[1].useFashionFootstepSounds, false)

local inactiveRemotePending, inactiveRemoteEffects = Core.reduce(
    inactiveVisibilityState,
    {
        type = "SetAttachmentVisibility",
        attachmentVisibility = allShown,
        remote = true,
        operationId = "visibility-inactive"
    }
)
assertEqual(inactiveRemoteEffects[1].type, "SendCommand",
    "inactive remote visibility changes must skip renderer preview")
local timedOutVisibility, timedOutEffects = Core.reduce(inactiveRemotePending, {
    type = "CommandTimedOut",
    operationId = "visibility-inactive"
})
assertEqual(timedOutVisibility.look.attachmentVisibility.Hair, "hide")
assertEqual(#timedOutEffects, 0,
    "inactive timeout rollback must not schedule renderer compensation")

local acceptedVisibility, acceptedVisibilityEffects = Core.reduce(inactiveRemotePending, {
    type = "AckReceived",
    operationId = "visibility-inactive",
    accepted = true,
    revision = 11,
    reason = "ok"
})
assertEqual(acceptedVisibilityEffects[1].type, "Persist")
local acceptedButUnpersisted, acceptedFailureEffects = Core.reduce(
    acceptedVisibility,
    { type = "PersistenceFailed", reason = "disk full" }
)
assertEqual(acceptedButUnpersisted.look.attachmentVisibility.Hair, "show",
    "server-accepted visibility must not roll back when local persistence fails")
assertEqual(#acceptedFailureEffects, 0)

local hairCalls = {}
local hairFailure = Core.createClientController(duplicateState, {
    ApplyAttachmentVisibility = function(effect)
        hairCalls[#hairCalls + 1] = "ApplyVisibility:" ..
            table.concat({
                effect.attachmentVisibility.Hair,
                effect.attachmentVisibility.Beard,
                effect.attachmentVisibility.Moustache,
                effect.attachmentVisibility.FaceAttachment
            }, "/")
        return { type = "AttachmentVisibilityUpdateSucceeded" }
    end,
    Persist = function()
        hairCalls[#hairCalls + 1] = "Persist"
        return false, "synthetic atomic replace failure"
    end,
    ApplyAttachmentVisibilityCompensation = function(effect)
        hairCalls[#hairCalls + 1] = "VisibilityCompensation:" ..
            table.concat({
                effect.attachmentVisibility.Hair,
                effect.attachmentVisibility.Beard,
                effect.attachmentVisibility.Moustache,
                effect.attachmentVisibility.FaceAttachment
            }, "/")
        return { type = "CompensationSucceeded" }
    end
})
hairFailure.dispatch({ type = "SetHairHidden", hidden = false })
assertEqual(table.concat(hairCalls, ","),
    "ApplyVisibility:auto/auto/auto/auto,Persist,VisibilityCompensation:hide/hide/hide/auto")
assertEqual(hairFailure.getState().phase, Core.PHASE.Faulted)
assertEqual(hairFailure.getState().look.hideHair, true)

-- Strict legacy migration rejects truncation, duplicates, unknown fields and
-- invalid booleans without mutating any runtime state.
local legacy = assert(Core.parseLegacyClientLookLine(
    "captured=true|active=false|auto=true|hidehair=true|fashionMovement=false|" ..
    "Head=helmet,Ballistic Helmet|HeadColor=2131821311"
))
assertEqual(legacy.look.slots.Head, "helmet")
assertEqual(legacy.look.colors.Head, 2131821311)
assertEqual(legacy.look.hideHair, true)
assertEqual(legacy.look.useFashionMovementAnimations, false)
assert(Core.parseLegacyClientLookLine("captured=true|Head=helmet") == nil)
assert(Core.parseLegacyClientLookLine("captured=true|captured=false") == nil)
assert(Core.parseLegacyClientLookLine("captured=true|mystery=value") == nil)
assert(Core.parseLegacyClientLookLine("captured=yes") == nil)
assert(Core.parseLegacyClientLookLine("captured=true|fashionMovement=yes|Head=helmet,") == nil)
assert(Core.parseLegacyClientLookLine(
    "captured=true|Head=helmet,name|HeadColor=4294967296") == nil)
assert(Core.parseLegacyClientLookLine(
    "captured=true|HeadColor=1") == nil)

-- v1 has no ACK channel. A successful send completes Save/Clear/Forget
-- locally; Apply remains pending until the v1 LOOK_APPLY frame is rendered.
local function v1Adapters(order)
    return {
        SendCommand = function(effect)
            order[#order + 1] = "Send:" .. effect.kind
            return { type = "CommandSendSucceeded", operationId = effect.operationId, awaitAck = false }
        end,
        ClearRender = function(effect)
            order[#order + 1] = effect.forget and "ForgetRender" or "ClearRender"
            return { type = "ClearRenderSucceeded", forget = effect.forget == true }
        end,
        Persist = function() order[#order + 1] = "Persist"; return { type = "PersistenceSucceeded" } end,
        ClearPersistence = function()
            order[#order + 1] = "ClearPersistence"
            return { type = "PersistenceSucceeded" }
        end,
        Render = function() order[#order + 1] = "Render"; return { type = "RenderSucceeded" } end
    }
end

local v1SaveOrder = {}
local v1Save = Core.createClientController(Core.newClientState({ characterKey = "42", look = look }), v1Adapters(v1SaveOrder))
v1Save.dispatch({ type = "CommandRequested", operationId = "v1:save", kind = Core.COMMAND.Save, look = look })
assertEqual(v1Save.getState().phase, Core.PHASE.SavedInactive)
assertEqual(v1Save.getState().autoApply, false)

local v1ApplyOrder = {}
local v1Apply = Core.createClientController(Core.newClientState({ characterKey = "42", look = look }), v1Adapters(v1ApplyOrder))
v1Apply.dispatch({ type = "CommandRequested", operationId = "v1:apply", kind = Core.COMMAND.Apply, look = look })
assertEqual(v1Apply.getState().phase, Core.PHASE.ApplyPending)
v1Apply.dispatch({ type = "LocalApplyRequested", look = look })
assertEqual(v1Apply.getState().phase, Core.PHASE.Active)

local v1ClearOrder = {}
local v1Clear = Core.createClientController(duplicateState, v1Adapters(v1ClearOrder))
v1Clear.dispatch({ type = "CommandRequested", operationId = "v1:clear", kind = Core.COMMAND.Clear })
assertEqual(v1Clear.getState().phase, Core.PHASE.SavedInactive)
assertEqual(v1Clear.getState().active, false)

local v1ForgetOrder = {}
local v1Forget = Core.createClientController(duplicateState, v1Adapters(v1ForgetOrder))
v1Forget.dispatch({ type = "CommandRequested", operationId = "v1:forget", kind = Core.COMMAND.Forget })
assertEqual(v1Forget.getState().phase, Core.PHASE.Idle)
assertEqual(v1Forget.getViewModel().hasSavedLook, false)

print("WardrobeCore tests passed")
