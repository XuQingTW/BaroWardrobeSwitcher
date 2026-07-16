local coreCandidates = { "Lua/WardrobeCore.lua", "../WardrobeCore.lua", "WardrobeCore.lua" }
if debug ~= nil and debug.getinfo ~= nil then
    local source = debug.getinfo(1, "S").source
    local testFile = source:sub(1, 1) == "@" and source:sub(2) or source
    local testDirectory = testFile:match("^(.*[/\\])") or ""
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

local function newBuffer()
    local values = {}
    local readIndex = 1
    local buffer = {}

    local function write(kind, value)
        values[#values + 1] = { kind = kind, value = value }
    end

    local function read(kind)
        local entry = values[readIndex]
        assert(entry ~= nil, "attempted to read beyond buffer")
        assert(entry.kind == kind, "expected " .. kind .. ", got " .. tostring(entry.kind))
        readIndex = readIndex + 1
        return entry.value
    end

    buffer.WriteUInt16 = function(value) write("u16", value) end
    buffer.WriteUInt32 = function(value) write("u32", value) end
    buffer.WriteBoolean = function(value) write("bool", value) end
    buffer.WriteString = function(value) write("string", value) end
    buffer.ReadUInt16 = function() return read("u16") end
    buffer.ReadUInt32 = function() return read("u32") end
    buffer.ReadBoolean = function() return read("bool") end
    buffer.ReadString = function() return read("string") end
    return buffer
end

local function assertEqual(actual, expected, message)
    assert(actual == expected, (message or "values differ") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end

assert(Core.selfTest())

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

local command = {
    clientSessionId = "session-1",
    operationId = "session-1:4",
    baseRevision = 3,
    kind = Core.COMMAND.Apply,
    look = look
}
local commandBuffer = newBuffer()
assert(Core.writeCommand(commandBuffer, command))
local decodedCommand = assert(Core.readCommand(commandBuffer))
assertEqual(decodedCommand.operationId, command.operationId)
assertEqual(decodedCommand.baseRevision, 3)
assert(Core.lookEquals(decodedCommand.look, look))

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
local unknownVersionLook, unknownVersionReason = Core.tryReadLook(unknownVersionBuffer)
assert(unknownVersionLook == nil)
assert(tostring(unknownVersionReason):find("unsupported", 1, true) ~= nil)

local truncatedBuffer = newBuffer()
truncatedBuffer.WriteUInt16(Core.LOOK_SCHEMA_VERSION)
local truncatedLook, truncatedReason = Core.tryReadLook(truncatedBuffer)
assert(truncatedLook == nil)
assert(tostring(truncatedReason):find("malformed", 1, true) ~= nil)

local duplicateSlotBuffer = newBuffer()
duplicateSlotBuffer.WriteUInt16(Core.LOOK_SCHEMA_VERSION)
duplicateSlotBuffer.WriteBoolean(true)
duplicateSlotBuffer.WriteBoolean(false)
duplicateSlotBuffer.WriteUInt16(2)
duplicateSlotBuffer.WriteString("Head")
duplicateSlotBuffer.WriteString("helmet")
duplicateSlotBuffer.WriteString("Head")
duplicateSlotBuffer.WriteString("anotherhelmet")
local duplicateLook, duplicateReason = Core.tryReadLook(duplicateSlotBuffer)
assert(duplicateLook == nil)
assert(tostring(duplicateReason):find("duplicate", 1, true) ~= nil)

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
local staleAckState, staleAckEffects = Core.reduce(awaitingAck, {
    type = "AckReceived",
    operationId = "session-1:9",
    accepted = true,
    revision = 7
})
assertEqual(staleAckState.phase, Core.PHASE.ApplyPending)
assertEqual(staleAckEffects[1].type, "IgnoredStaleAck")

local rejectedAckState = Core.reduce(awaitingAck, {
    type = "AckReceived",
    operationId = "session-1:9",
    accepted = false,
    revision = 8,
    reason = "stale base revision"
})
assertEqual(rejectedAckState.phase, Core.PHASE.Faulted)
assertEqual(rejectedAckState.error, "stale base revision")

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

local hairCalls = {}
local hairFailure = Core.createClientController(duplicateState, {
    SetHair = function(effect)
        hairCalls[#hairCalls + 1] = "SetHair:" .. tostring(effect.hidden)
        return { type = "HairUpdateSucceeded" }
    end,
    Persist = function()
        hairCalls[#hairCalls + 1] = "Persist"
        return false, "synthetic atomic replace failure"
    end,
    SetHairCompensation = function(effect)
        hairCalls[#hairCalls + 1] = "SetHairCompensation:" .. tostring(effect.hidden)
        return { type = "CompensationSucceeded" }
    end
})
hairFailure.dispatch({ type = "SetHairHidden", hidden = false })
assertEqual(table.concat(hairCalls, ","), "SetHair:false,Persist,SetHairCompensation:true")
assertEqual(hairFailure.getState().phase, Core.PHASE.Faulted)
assertEqual(hairFailure.getState().look.hideHair, true)

-- Strict legacy migration rejects truncation, duplicates, unknown fields and
-- invalid booleans without mutating any runtime state.
local legacy = assert(Core.parseLegacyClientLookLine(
    "captured=true|active=false|auto=true|hidehair=true|Head=helmet,Ballistic Helmet"
))
assertEqual(legacy.look.slots.Head, "helmet")
assertEqual(legacy.look.hideHair, true)
assert(Core.parseLegacyClientLookLine("captured=true|Head=helmet") == nil)
assert(Core.parseLegacyClientLookLine("captured=true|captured=false") == nil)
assert(Core.parseLegacyClientLookLine("captured=true|mystery=value") == nil)
assert(Core.parseLegacyClientLookLine("captured=yes") == nil)

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
