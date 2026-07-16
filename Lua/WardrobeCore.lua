-- Pure Lua domain, protocol and state-reducer contract shared by both realms.
-- This file deliberately has no dependency on Barotrauma or LuaCs globals.

local Core = {}

Core.MOD_VERSION = "0.5.0"
Core.PROTOCOL_VERSION = 2
Core.LOOK_SCHEMA_VERSION = 2
Core.PERSISTENCE_VERSION = 2
Core.HELLO_TIMEOUT_SECONDS = 5

Core.NET = {
    V2_HELLO = "barowardrobeswitcher.v2.hello",
    V2_COMMAND = "barowardrobeswitcher.v2.command",
    V2_STATE = "barowardrobeswitcher.v2.state",
    V2_ACK = "barowardrobeswitcher.v2.ack",
    V1_SAVE_REQUEST = "barowardrobeswitcher.save",
    V1_APPLY_REQUEST = "barowardrobeswitcher.apply",
    V1_CLEAR_REQUEST = "barowardrobeswitcher.clear",
    V1_FORGET_REQUEST = "barowardrobeswitcher.forget",
    V1_LOOK_APPLY = "barowardrobeswitcher.look.apply",
    V1_LOOK_CLEAR = "barowardrobeswitcher.look.clear"
}

Core.SLOT_KEYS = {
    "Head",
    "Headset",
    "InnerClothes",
    "OuterClothes",
    "Bag",
    "HealthInterface"
}

Core.SLOT_SET = {}
for _, key in ipairs(Core.SLOT_KEYS) do
    Core.SLOT_SET[key] = true
end

Core.LIMITS = {
    MAX_SLOTS = 6,
    MAX_IDENTIFIER_BYTES = 256,
    MAX_PAYLOAD_BYTES = 4096,
    MAX_SESSION_ID_BYTES = 128,
    MAX_OPERATION_ID_BYTES = 128,
    MAX_SEEN_OPERATIONS = 512,
    MAX_REASON_BYTES = 512,
    MAX_UINT32 = 4294967295
}

Core.PHASE = {
    NoCharacter = "NoCharacter",
    Idle = "Idle",
    Saving = "Saving",
    SavedInactive = "SavedInactive",
    ApplyPending = "ApplyPending",
    Active = "Active",
    ClearPending = "ClearPending",
    Faulted = "Faulted"
}

Core.COMMAND = {
    Save = "save",
    Apply = "apply",
    Clear = "clear",
    Forget = "forget"
}

local validCommands = {
    [Core.COMMAND.Save] = true,
    [Core.COMMAND.Apply] = true,
    [Core.COMMAND.Clear] = true,
    [Core.COMMAND.Forget] = true
}

local function shallowCopy(source)
    local copy = {}
    for key, value in pairs(source or {}) do
        copy[key] = value
    end
    return copy
end

local function copySlots(source)
    local copy = {}
    source = source or {}
    for _, key in ipairs(Core.SLOT_KEYS) do
        if source[key] ~= nil then
            copy[key] = tostring(source[key])
        end
    end
    return copy
end

local function checkBoundedString(value, field, maximum, allowEmpty)
    if type(value) ~= "string" then
        return nil, field .. " must be a string"
    end
    if not allowEmpty and value == "" then
        return nil, field .. " must not be empty"
    end
    if #value > maximum then
        return nil, field .. " exceeds " .. tostring(maximum) .. " bytes"
    end
    return value
end

local function normalizeRevision(value, field)
    local revision = tonumber(value)
    if revision == nil or revision < 0 or revision > Core.LIMITS.MAX_UINT32 or revision % 1 ~= 0 then
        return nil, (field or "revision") .. " must be an unsigned 32-bit integer"
    end
    return revision
end

local function rawSlotIdentifier(value)
    if type(value) == "table" then
        value = value.identifier
    end
    if value == nil then return nil end
    return tostring(value)
end

function Core.validateLook(value)
    if type(value) ~= "table" then
        return nil, "look must be a table"
    end

    local schemaVersion = tonumber(value.schemaVersion or value.version or Core.LOOK_SCHEMA_VERSION)
    if schemaVersion ~= Core.LOOK_SCHEMA_VERSION then
        return nil, "unsupported look schema version " .. tostring(schemaVersion)
    end

    local slotSource = value.slots
    local isCanonical = type(slotSource) == "table"
    if not isCanonical then slotSource = value end

    if isCanonical then
        for key, _ in pairs(slotSource) do
            if not Core.SLOT_SET[key] then
                return nil, "unknown wardrobe slot " .. tostring(key)
            end
        end
    end

    local slots = {}
    local count = 0
    local payloadBytes = 8
    for _, key in ipairs(Core.SLOT_KEYS) do
        local identifier = rawSlotIdentifier(slotSource[key])
        if identifier ~= nil and identifier ~= "" then
            local valid, reason = checkBoundedString(
                identifier,
                "identifier for " .. key,
                Core.LIMITS.MAX_IDENTIFIER_BYTES,
                false
            )
            if valid == nil then return nil, reason end
            count = count + 1
            payloadBytes = payloadBytes + #key + #identifier + 4
            slots[key] = identifier
        end
    end

    if count > Core.LIMITS.MAX_SLOTS then
        return nil, "look contains too many slots"
    end
    if payloadBytes > Core.LIMITS.MAX_PAYLOAD_BYTES then
        return nil, "look exceeds maximum payload size"
    end

    return {
        schemaVersion = Core.LOOK_SCHEMA_VERSION,
        captured = value.captured == true,
        hideHair = value.hideHair == true,
        slots = slots
    }
end

function Core.newLook(captured, hideHair, slots)
    return Core.validateLook({
        schemaVersion = Core.LOOK_SCHEMA_VERSION,
        captured = captured == true,
        hideHair = hideHair == true,
        slots = slots or {}
    })
end

function Core.copyLook(look)
    if look == nil then return nil end
    local valid, reason = Core.validateLook(look)
    if valid == nil then return nil, reason end
    return valid
end

function Core.fromLegacyLook(legacyLook, captured, hideHair)
    return Core.validateLook({
        schemaVersion = Core.LOOK_SCHEMA_VERSION,
        captured = captured == true,
        hideHair = hideHair == true,
        slots = legacyLook or {}
    })
end

function Core.toLegacyLook(look)
    local valid, reason = Core.validateLook(look)
    if valid == nil then return nil, reason end
    local legacy = {}
    for _, key in ipairs(Core.SLOT_KEYS) do
        local identifier = valid.slots[key]
        if identifier ~= nil then
            legacy[key] = {
                identifier = identifier,
                itemId = 0,
                name = "",
                slot = key
            }
        end
    end
    return legacy
end

local function decodePersistentValue(value)
    return tostring(value or "")
        :gsub("%%0A", "\n")
        :gsub("%%0D", "\r")
        :gsub("%%3D", "=")
        :gsub("%%2C", ",")
        :gsub("%%7C", "|")
        :gsub("%%25", "%%")
end

function Core.parseLegacyClientLookLine(line)
    if type(line) ~= "string" or line == "" then return nil, "legacy client look is empty" end
    if line:sub(1, 1) == "|" or line:sub(-1) == "|" or line:find("||", 1, true) then
        return nil, "legacy client look contains an empty field"
    end

    local seen = {}
    local legacy = {}
    local captured = nil
    local active = false
    local autoApply = false
    local hideHair = false
    local sessionKey = nil

    local function booleanValue(name, value)
        if value == "true" then return true end
        if value == "false" then return false end
        return nil, name .. " must be true or false"
    end

    for part in line:gmatch("[^|]+") do
        local name, value = part:match("^([^=]+)=(.*)$")
        if name == nil then return nil, "legacy client look field is malformed" end
        if seen[name] then return nil, "duplicate legacy client look field " .. name end
        seen[name] = true

        if name == "schema" then
            if value ~= "1" and value ~= "2" then
                return nil, "unsupported legacy client look schema " .. tostring(value)
            end
        elseif name == "captured" then
            local reason
            captured, reason = booleanValue(name, value)
            if captured == nil then return nil, reason end
        elseif name == "active" then
            local reason
            active, reason = booleanValue(name, value)
            if active == nil then return nil, reason end
        elseif name == "auto" then
            local reason
            autoApply, reason = booleanValue(name, value)
            if autoApply == nil then return nil, reason end
        elseif name == "hidehair" then
            local reason
            hideHair, reason = booleanValue(name, value)
            if hideHair == nil then return nil, reason end
        elseif name == "session" then
            sessionKey = decodePersistentValue(value)
        elseif Core.SLOT_SET[name] then
            local identifier, displayName = value:match("^([^,]+),(.*)$")
            if identifier == nil then return nil, "slot " .. name .. " is truncated" end
            identifier = decodePersistentValue(identifier)
            if identifier == "" or #identifier > Core.LIMITS.MAX_IDENTIFIER_BYTES then
                return nil, "slot " .. name .. " identifier is invalid"
            end
            legacy[name] = {
                identifier = identifier,
                itemId = 0,
                name = decodePersistentValue(displayName),
                slot = name
            }
        else
            return nil, "unknown legacy client look field " .. tostring(name)
        end
    end

    if captured == nil then return nil, "legacy client look is missing captured intent" end
    local look, reason = Core.fromLegacyLook(legacy, captured, hideHair)
    if look == nil then return nil, reason end
    if not Core.hasLook(look) then return nil, "legacy client look has no captured intent" end
    return {
        look = look,
        legacyLook = legacy,
        active = active,
        autoApply = autoApply,
        sessionKey = sessionKey
    }
end

function Core.hasLook(look)
    local valid = Core.validateLook(look)
    if valid == nil then return false end
    if valid.captured then return true end
    for _, key in ipairs(Core.SLOT_KEYS) do
        if valid.slots[key] ~= nil then return true end
    end
    return false
end

function Core.lookSignature(look)
    local valid, reason = Core.validateLook(look)
    if valid == nil then return nil, reason end
    local parts = {
        "v=" .. tostring(valid.schemaVersion),
        "captured=" .. tostring(valid.captured),
        "hideHair=" .. tostring(valid.hideHair)
    }
    for _, key in ipairs(Core.SLOT_KEYS) do
        parts[#parts + 1] = key .. "=" .. tostring(valid.slots[key] or "-")
    end
    return table.concat(parts, ";")
end

function Core.lookEquals(left, right)
    if left == nil or right == nil then return left == right end
    local leftSignature = Core.lookSignature(left)
    local rightSignature = Core.lookSignature(right)
    return leftSignature ~= nil and leftSignature == rightSignature
end

function Core.writeLook(message, look)
    local valid, reason = Core.validateLook(look)
    if valid == nil then return false, reason end

    message.WriteUInt16(Core.LOOK_SCHEMA_VERSION)
    message.WriteBoolean(valid.captured)
    message.WriteBoolean(valid.hideHair)

    local count = 0
    for _, key in ipairs(Core.SLOT_KEYS) do
        if valid.slots[key] ~= nil then count = count + 1 end
    end
    message.WriteUInt16(count)
    for _, key in ipairs(Core.SLOT_KEYS) do
        local identifier = valid.slots[key]
        if identifier ~= nil then
            message.WriteString(key)
            message.WriteString(identifier)
        end
    end
    return true
end

function Core.readLook(message)
    local schemaVersion = message.ReadUInt16()
    if schemaVersion ~= Core.LOOK_SCHEMA_VERSION then
        return nil, "unsupported look schema version " .. tostring(schemaVersion)
    end

    local captured = message.ReadBoolean() == true
    local hideHair = message.ReadBoolean() == true
    local count = message.ReadUInt16()
    if count > Core.LIMITS.MAX_SLOTS then
        return nil, "look contains too many slots"
    end

    local slots = {}
    for _ = 1, count do
        local key = message.ReadString()
        local identifier = message.ReadString()
        if not Core.SLOT_SET[key] then
            return nil, "unknown wardrobe slot " .. tostring(key)
        end
        if slots[key] ~= nil then
            return nil, "duplicate wardrobe slot " .. tostring(key)
        end
        slots[key] = identifier
    end

    return Core.validateLook({
        schemaVersion = schemaVersion,
        captured = captured,
        hideHair = hideHair,
        slots = slots
    })
end

function Core.tryReadLook(message)
    local ok, look, reason = pcall(Core.readLook, message)
    if not ok then return nil, "malformed look payload: " .. tostring(look) end
    return look, reason
end

function Core.writeClientHello(message, clientSessionId)
    local sessionId, reason = checkBoundedString(
        clientSessionId,
        "clientSessionId",
        Core.LIMITS.MAX_SESSION_ID_BYTES,
        false
    )
    if sessionId == nil then return false, reason end
    message.WriteUInt16(Core.PROTOCOL_VERSION)
    message.WriteString(sessionId)
    return true
end

function Core.readClientHello(message)
    local version = message.ReadUInt16()
    local sessionId = message.ReadString()
    if version ~= Core.PROTOCOL_VERSION then
        return nil, "unsupported protocol version " .. tostring(version)
    end
    local valid, reason = checkBoundedString(
        sessionId,
        "clientSessionId",
        Core.LIMITS.MAX_SESSION_ID_BYTES,
        false
    )
    if valid == nil then return nil, reason end
    return { protocolVersion = version, clientSessionId = valid }
end

function Core.writeServerHello(message, revision)
    local validRevision, reason = normalizeRevision(revision, "revision")
    if validRevision == nil then return false, reason end
    message.WriteUInt16(Core.PROTOCOL_VERSION)
    message.WriteUInt32(validRevision)
    return true
end

function Core.readServerHello(message)
    local version = message.ReadUInt16()
    local revision = message.ReadUInt32()
    if version ~= Core.PROTOCOL_VERSION then
        return nil, "unsupported protocol version " .. tostring(version)
    end
    return { protocolVersion = version, revision = revision }
end

function Core.validateCommand(command)
    if type(command) ~= "table" then return nil, "command must be a table" end
    if not validCommands[command.kind] then
        return nil, "unknown command " .. tostring(command.kind)
    end
    local clientSessionId, sessionReason = checkBoundedString(
        command.clientSessionId,
        "clientSessionId",
        Core.LIMITS.MAX_SESSION_ID_BYTES,
        false
    )
    if clientSessionId == nil then return nil, sessionReason end
    local operationId, operationReason = checkBoundedString(
        command.operationId,
        "operationId",
        Core.LIMITS.MAX_OPERATION_ID_BYTES,
        false
    )
    if operationId == nil then return nil, operationReason end
    local revision, revisionReason = normalizeRevision(command.baseRevision or 0, "baseRevision")
    if revision == nil then return nil, revisionReason end

    local look = nil
    if command.look ~= nil then
        local lookReason
        look, lookReason = Core.validateLook(command.look)
        if look == nil then return nil, lookReason end
    end
    if (command.kind == Core.COMMAND.Clear or command.kind == Core.COMMAND.Forget) and look ~= nil then
        return nil, command.kind .. " command must not contain a look"
    end

    return {
        protocolVersion = Core.PROTOCOL_VERSION,
        clientSessionId = clientSessionId,
        operationId = operationId,
        baseRevision = revision,
        kind = command.kind,
        look = look
    }
end

function Core.writeCommand(message, command)
    local valid, reason = Core.validateCommand(command)
    if valid == nil then return false, reason end
    message.WriteUInt16(Core.PROTOCOL_VERSION)
    message.WriteString(valid.clientSessionId)
    message.WriteString(valid.operationId)
    message.WriteUInt32(valid.baseRevision)
    message.WriteString(valid.kind)
    message.WriteBoolean(valid.look ~= nil)
    if valid.look ~= nil then
        return Core.writeLook(message, valid.look)
    end
    return true
end

function Core.readCommand(message)
    local version = message.ReadUInt16()
    if version ~= Core.PROTOCOL_VERSION then
        return nil, "unsupported protocol version " .. tostring(version)
    end
    local command = {
        protocolVersion = version,
        clientSessionId = message.ReadString(),
        operationId = message.ReadString(),
        baseRevision = message.ReadUInt32(),
        kind = message.ReadString()
    }
    if message.ReadBoolean() then
        local look, reason = Core.readLook(message)
        if look == nil then return nil, reason end
        command.look = look
    end
    return Core.validateCommand(command)
end

function Core.tryReadCommand(message)
    local ok, command, reason = pcall(Core.readCommand, message)
    if not ok then return nil, "malformed command payload: " .. tostring(command) end
    return command, reason
end

function Core.writeState(message, state)
    if type(state) ~= "table" then return false, "state must be a table" end
    local revision, revisionReason = normalizeRevision(state.revision or 0, "revision")
    if revision == nil then return false, revisionReason end
    local characterId = tonumber(state.characterId)
    if characterId == nil or characterId < 0 or characterId > 65535 or characterId % 1 ~= 0 then
        return false, "characterId must be an unsigned 16-bit integer"
    end
    local look = nil
    if state.look ~= nil then
        local lookReason
        look, lookReason = Core.validateLook(state.look)
        if look == nil then return false, lookReason end
    end

    message.WriteUInt16(Core.PROTOCOL_VERSION)
    message.WriteUInt32(revision)
    message.WriteUInt16(characterId)
    message.WriteBoolean(state.active == true)
    message.WriteBoolean(look ~= nil)
    if look ~= nil then return Core.writeLook(message, look) end
    return true
end

function Core.readState(message)
    local version = message.ReadUInt16()
    if version ~= Core.PROTOCOL_VERSION then
        return nil, "unsupported protocol version " .. tostring(version)
    end
    local state = {
        protocolVersion = version,
        revision = message.ReadUInt32(),
        characterId = message.ReadUInt16(),
        active = message.ReadBoolean() == true
    }
    if message.ReadBoolean() then
        local look, reason = Core.readLook(message)
        if look == nil then return nil, reason end
        state.look = look
    end
    if state.active and state.look == nil then
        return nil, "active state requires a look"
    end
    return state
end

function Core.tryReadState(message)
    local ok, state, reason = pcall(Core.readState, message)
    if not ok then return nil, "malformed state payload: " .. tostring(state) end
    return state, reason
end

function Core.writeAck(message, ack)
    if type(ack) ~= "table" then return false, "ack must be a table" end
    local operationId, operationReason = checkBoundedString(
        ack.operationId,
        "operationId",
        Core.LIMITS.MAX_OPERATION_ID_BYTES,
        false
    )
    if operationId == nil then return false, operationReason end
    local revision, revisionReason = normalizeRevision(ack.revision or 0, "revision")
    if revision == nil then return false, revisionReason end
    local reason = tostring(ack.reason or "")
    local validReason, reasonError = checkBoundedString(
        reason,
        "reason",
        Core.LIMITS.MAX_REASON_BYTES,
        true
    )
    if validReason == nil then return false, reasonError end

    message.WriteUInt16(Core.PROTOCOL_VERSION)
    message.WriteString(operationId)
    message.WriteBoolean(ack.accepted == true)
    message.WriteUInt32(revision)
    message.WriteString(validReason)
    return true
end

function Core.readAck(message)
    local version = message.ReadUInt16()
    if version ~= Core.PROTOCOL_VERSION then
        return nil, "unsupported protocol version " .. tostring(version)
    end
    local operationId = message.ReadString()
    local accepted = message.ReadBoolean() == true
    local revision = message.ReadUInt32()
    local reason = message.ReadString()
    local validOperation, operationReason = checkBoundedString(
        operationId,
        "operationId",
        Core.LIMITS.MAX_OPERATION_ID_BYTES,
        false
    )
    if validOperation == nil then return nil, operationReason end
    local validReason, reasonError = checkBoundedString(reason, "reason", Core.LIMITS.MAX_REASON_BYTES, true)
    if validReason == nil then return nil, reasonError end
    return {
        protocolVersion = version,
        operationId = validOperation,
        accepted = accepted,
        revision = revision,
        reason = validReason
    }
end

function Core.tryReadAck(message)
    local ok, ack, reason = pcall(Core.readAck, message)
    if not ok then return nil, "malformed ack payload: " .. tostring(ack) end
    return ack, reason
end

local function copyClientState(state)
    local copy = shallowCopy(state)
    copy.look = Core.copyLook(state.look)
    copy.rollbackLook = Core.copyLook(state.rollbackLook)
    return copy
end

local function effect(kind, values)
    local result = values and shallowCopy(values) or {}
    result.type = kind
    return result
end

function Core.newClientState(options)
    options = options or {}
    local look = Core.copyLook(options.look)
    local characterKey = options.characterKey
    local phase
    if characterKey == nil then
        phase = Core.PHASE.NoCharacter
    elseif Core.hasLook(look) then
        phase = Core.PHASE.SavedInactive
    else
        phase = Core.PHASE.Idle
    end
    return {
        phase = phase,
        revision = tonumber(options.revision) or 0,
        sessionKey = options.sessionKey,
        characterKey = characterKey,
        clientSessionId = options.clientSessionId,
        look = look,
        active = false,
        autoApply = options.autoApply == true,
        pendingOperationId = nil,
        pendingKind = nil,
        pendingRemote = false,
        pendingServerAccepted = false,
        rollbackLook = nil,
        rollbackActive = false,
        rollbackAutoApply = false,
        error = nil
    }
end

local function clearPending(state)
    state.pendingOperationId = nil
    state.pendingKind = nil
    state.pendingRemote = false
    state.pendingServerAccepted = false
end

local function clearRollback(state)
    state.rollbackLook = nil
    state.rollbackActive = false
    state.rollbackAutoApply = false
end

local function beginRollback(state)
    state.rollbackLook = Core.copyLook(state.look)
    state.rollbackActive = state.active == true
    state.rollbackAutoApply = state.autoApply == true
end

local function restoreRollback(state)
    state.look = Core.copyLook(state.rollbackLook)
    state.active = state.rollbackActive == true
    state.autoApply = state.rollbackAutoApply == true
    if state.characterKey == nil then
        state.phase = Core.PHASE.NoCharacter
    elseif state.active then
        state.phase = Core.PHASE.Active
    elseif Core.hasLook(state.look) then
        state.phase = Core.PHASE.SavedInactive
    else
        state.phase = Core.PHASE.Idle
    end
    clearPending(state)
    clearRollback(state)
end

local function commandPending(state, event, phase)
    state.phase = phase
    state.pendingOperationId = event.operationId
    state.pendingKind = event.kind
    state.pendingRemote = true
    state.pendingServerAccepted = false
    state.error = nil
end

function Core.reduce(currentState, event)
    if type(currentState) ~= "table" then error("currentState must be a table") end
    if type(event) ~= "table" or type(event.type) ~= "string" then error("event.type is required") end

    local state = copyClientState(currentState)
    local effects = {}

    if event.type == "CharacterLost" then
        local preserveAutoApply = Core.hasLook(state.look) and
            (state.active == true or state.autoApply == true)
        state.phase = Core.PHASE.NoCharacter
        state.characterKey = nil
        state.active = false
        state.autoApply = preserveAutoApply
        clearPending(state)
        clearRollback(state)
        effects[#effects + 1] = effect("ClearRender", {
            dispose = true,
            preserveAutoApply = preserveAutoApply
        })
        return state, effects
    end

    if event.type == "CharacterReady" then
        state.characterKey = event.characterKey
        state.phase = Core.hasLook(state.look) and Core.PHASE.SavedInactive or Core.PHASE.Idle
        state.active = false
        clearPending(state)
        clearRollback(state)
        return state, effects
    end

    if event.type == "RestoreLook" then
        local look = nil
        if event.look ~= nil then
            local reason
            look, reason = Core.validateLook(event.look)
            if look == nil then
                state.phase = Core.PHASE.Faulted
                state.error = reason
                return state, effects
            end
        end
        state.look = look
        state.active = event.active == true
        state.autoApply = event.autoApply == true
        state.phase = state.characterKey == nil and Core.PHASE.NoCharacter or
            (state.active and Core.PHASE.Active or
            (Core.hasLook(look) and Core.PHASE.SavedInactive or Core.PHASE.Idle))
        state.error = nil
        clearPending(state)
        clearRollback(state)
        return state, effects
    end

    if event.type == "SetHairHidden" then
        if state.look == nil then
            state.error = "cannot change hair visibility without a saved look"
            return state, effects
        end
        beginRollback(state)
        state.pendingKind = "hair"
        local updated = Core.copyLook(state.look)
        updated.hideHair = event.hidden == true
        state.look = updated
        state.error = nil
        if state.active then
            effects[#effects + 1] = effect("SetHair", { hidden = updated.hideHair })
        else
            effects[#effects + 1] = effect("Persist", { look = Core.copyLook(updated) })
        end
        return state, effects
    end

    if event.type == "SetAutoApply" then
        state.autoApply = event.enabled == true
        return state, effects
    end

    if event.type == "RevisionObserved" then
        local revision = tonumber(event.revision) or state.revision
        if revision > (tonumber(state.revision) or 0) then state.revision = revision end
        return state, effects
    end

    if event.type == "Deactivate" then
        state.active = false
        state.phase = state.characterKey == nil and Core.PHASE.NoCharacter or
            (Core.hasLook(state.look) and Core.PHASE.SavedInactive or Core.PHASE.Idle)
        return state, effects
    end

    if event.type == "PrepareSceneTransition" then
        state.autoApply = Core.hasLook(state.look) and
            (event.reapply == true or state.active == true or state.autoApply == true)
        state.active = false
        state.phase = state.characterKey == nil and Core.PHASE.NoCharacter or
            (Core.hasLook(state.look) and Core.PHASE.SavedInactive or Core.PHASE.Idle)
        clearPending(state)
        clearRollback(state)
        if Core.hasLook(state.look) then
            effects[#effects + 1] = effect("Persist", { look = Core.copyLook(state.look) })
        end
        return state, effects
    end

    if event.type == "SaveRequested" then
        if state.characterKey == nil then
            state.phase = Core.PHASE.Faulted
            state.error = "cannot save without a controlled character"
            return state, effects
        end
        beginRollback(state)
        state.phase = Core.PHASE.Saving
        state.pendingKind = Core.COMMAND.Save
        state.pendingOperationId = event.operationId
        state.pendingRemote = event.remote == true
        state.error = nil
        effects[#effects + 1] = effect("Capture", {
            characterKey = state.characterKey,
            operationId = event.operationId,
            remote = event.remote == true
        })
        return state, effects
    end

    if event.type == "CaptureSucceeded" then
        local look, reason = Core.validateLook(event.look)
        if look == nil then
            restoreRollback(state)
            state.phase = Core.PHASE.Faulted
            state.error = reason
            return state, effects
        end
        state.look = look
        state.phase = Core.PHASE.Saving
        state.active = false
        state.autoApply = false
        state.error = nil
        if state.pendingRemote then
            effects[#effects + 1] = effect("SendCommand", {
                operationId = state.pendingOperationId,
                kind = Core.COMMAND.Save,
                baseRevision = state.revision,
                look = Core.copyLook(look)
            })
        else
            effects[#effects + 1] = effect("Persist", { look = Core.copyLook(look) })
        end
        return state, effects
    end

    if event.type == "CaptureFailed" then
        restoreRollback(state)
        state.phase = Core.PHASE.Faulted
        state.error = tostring(event.reason or "capture failed")
        return state, effects
    end

    if event.type == "UnequipSucceeded" then
        state.phase = Core.PHASE.SavedInactive
        state.active = false
        state.autoApply = false
        state.error = nil
        clearPending(state)
        clearRollback(state)
        return state, effects
    end

    if event.type == "UnequipFailed" then
        local rollbackLook = Core.copyLook(state.rollbackLook)
        restoreRollback(state)
        state.phase = Core.PHASE.Faulted
        state.error = tostring(event.reason or "unequip failed")
        if rollbackLook ~= nil then
            effects[#effects + 1] = effect("Persist", { look = rollbackLook })
        else
            effects[#effects + 1] = effect("ClearPersistence")
        end
        return state, effects
    end

    if event.type == "CommandRequested" then
        if not validCommands[event.kind] then error("unknown command " .. tostring(event.kind)) end
        if event.kind == Core.COMMAND.Apply and not Core.hasLook(event.look or state.look) then
            state.phase = Core.PHASE.Faulted
            state.error = "cannot apply without a saved look"
            return state, effects
        end
        if event.kind == Core.COMMAND.Clear or event.kind == Core.COMMAND.Forget then
            beginRollback(state)
        end
        local phase
        if event.kind == Core.COMMAND.Clear or event.kind == Core.COMMAND.Forget then
            phase = Core.PHASE.ClearPending
        elseif event.kind == Core.COMMAND.Save then
            phase = Core.PHASE.Saving
        else
            phase = Core.PHASE.ApplyPending
        end
        commandPending(state, event, phase)
        if event.kind == Core.COMMAND.Apply then
            state.active = false
        end
        if event.kind == Core.COMMAND.Clear or event.kind == Core.COMMAND.Forget then
            state.autoApply = false
        end
        effects[#effects + 1] = effect("SendCommand", {
            operationId = event.operationId,
            kind = event.kind,
            baseRevision = state.revision,
            look = Core.copyLook(event.look or state.look)
        })
        return state, effects
    end

    if event.type == "CommandSendSucceeded" then
        if event.operationId ~= nil and state.pendingOperationId ~= nil and
            event.operationId ~= state.pendingOperationId then
            effects[#effects + 1] = effect("IgnoredForeignSend", { operationId = event.operationId })
            return state, effects
        end
        if state.pendingKind == Core.COMMAND.Save and event.awaitAck ~= true then
            state.phase = Core.PHASE.SavedInactive
            state.active = false
            state.autoApply = false
            clearPending(state)
            clearRollback(state)
            effects[#effects + 1] = effect("Persist", { look = Core.copyLook(state.look) })
        elseif event.awaitAck ~= true and state.pendingKind == Core.COMMAND.Clear then
            state.pendingRemote = false
            effects[#effects + 1] = effect("ClearRender", { remote = false })
        elseif event.awaitAck ~= true and state.pendingKind == Core.COMMAND.Forget then
            state.pendingRemote = false
            effects[#effects + 1] = effect("ClearRender", { remote = false, forget = true })
        end
        return state, effects
    end

    if event.type == "CommandSendFailed" then
        if state.pendingKind == Core.COMMAND.Save or
            state.pendingKind == Core.COMMAND.Clear or
            state.pendingKind == Core.COMMAND.Forget then
            restoreRollback(state)
        end
        state.phase = Core.PHASE.Faulted
        state.error = tostring(event.reason or "network command could not be sent")
        clearPending(state)
        return state, effects
    end

    if event.type == "LocalApplyRequested" then
        local requestedLook = event.look or state.look
        local validLook, lookReason = Core.validateLook(requestedLook)
        if validLook == nil or not Core.hasLook(validLook) then
            state.phase = Core.PHASE.Faulted
            state.error = tostring(lookReason or "cannot apply without a saved look")
            return state, effects
        end
        beginRollback(state)
        state.look = validLook
        state.phase = Core.PHASE.ApplyPending
        state.error = nil
        effects[#effects + 1] = effect("Render", { look = Core.copyLook(validLook) })
        return state, effects
    end

    if event.type == "LocalClearRequested" or event.type == "LocalForgetRequested" then
        beginRollback(state)
        state.phase = Core.PHASE.ClearPending
        state.active = false
        state.error = nil
        clearPending(state)
        state.pendingKind = event.type == "LocalForgetRequested" and Core.COMMAND.Forget or Core.COMMAND.Clear
        effects[#effects + 1] = effect("ClearRender", {
            forget = event.type == "LocalForgetRequested"
        })
        return state, effects
    end

    if event.type == "ClearSucceeded" then
        state.active = false
        state.autoApply = false
        state.phase = Core.hasLook(state.look) and Core.PHASE.SavedInactive or Core.PHASE.Idle
        clearPending(state)
        clearRollback(state)
        effects[#effects + 1] = effect("Persist", { look = Core.copyLook(state.look) })
        return state, effects
    end

    if event.type == "ForgetSucceeded" then
        state.look = nil
        state.active = false
        state.autoApply = false
        if event.preservePending == true then
            state.phase = Core.PHASE.ClearPending
        else
            state.phase = state.characterKey ~= nil and Core.PHASE.Idle or Core.PHASE.NoCharacter
            clearPending(state)
        end
        clearRollback(state)
        effects[#effects + 1] = effect("ClearPersistence")
        return state, effects
    end

    if event.type == "AckReceived" then
        local revision = tonumber(event.revision) or -1
        if revision < state.revision then
            effects[#effects + 1] = effect("IgnoredStaleAck", { revision = revision })
            return state, effects
        end
        state.revision = revision
        if state.pendingOperationId == nil or event.operationId ~= state.pendingOperationId then
            effects[#effects + 1] = effect("IgnoredForeignAck", { operationId = event.operationId })
            return state, effects
        end
        if event.accepted ~= true then
            if state.pendingKind == Core.COMMAND.Save or
                state.pendingKind == Core.COMMAND.Clear or
                state.pendingKind == Core.COMMAND.Forget then
                restoreRollback(state)
            end
            state.phase = Core.PHASE.Faulted
            state.error = tostring(event.reason or "server rejected command")
            clearPending(state)
            return state, effects
        end

        local kind = state.pendingKind
        if kind == Core.COMMAND.Forget then
            state.pendingRemote = false
            state.pendingServerAccepted = true
            state.phase = Core.PHASE.ClearPending
            effects[#effects + 1] = effect("ClearRender", { forget = true, remote = true })
        elseif kind == Core.COMMAND.Clear then
            state.pendingRemote = false
            state.pendingServerAccepted = true
            state.phase = Core.PHASE.ClearPending
            effects[#effects + 1] = effect("ClearRender", { remote = true })
        elseif kind == Core.COMMAND.Save then
            state.pendingRemote = false
            state.pendingServerAccepted = true
            state.active = false
            state.autoApply = false
            state.phase = Core.PHASE.Saving
            effects[#effects + 1] = effect("ClearRender", { remote = true, save = true })
        else
            clearPending(state)
            state.phase = Core.PHASE.ApplyPending
        end
        return state, effects
    end

    if event.type == "RemoteStateReceived" then
        local revision = tonumber(event.revision) or -1
        local conflictsWithPendingClear =
            state.phase == Core.PHASE.ClearPending and event.active == true
        if revision < state.revision then
            effects[#effects + 1] = effect("IgnoredStaleState", { revision = revision })
            return state, effects
        end
        if conflictsWithPendingClear then
            state.revision = revision
            effects[#effects + 1] = effect("IgnoredSupersededState", { revision = revision })
            return state, effects
        end

        local look = nil
        if event.look ~= nil then
            local reason
            look, reason = Core.validateLook(event.look)
            if look == nil then
                state.phase = Core.PHASE.Faulted
                state.error = reason
                return state, effects
            end
        end

        if event.active ~= true and currentState.active ~= true and
            revision == (tonumber(currentState.revision) or -1) and
            (look == nil or Core.lookEquals(currentState.look, look)) then
            effects[#effects + 1] = effect("IgnoredDuplicateState", { revision = revision })
            return state, effects
        end

        local pendingKindBeforeState = state.pendingKind
        local confirmsPendingDestructive = event.active ~= true and state.pendingRemote == true and
            (pendingKindBeforeState == Core.COMMAND.Clear or pendingKindBeforeState == Core.COMMAND.Forget)
        if not confirmsPendingDestructive then beginRollback(state) end
        state.revision = revision
        state.look = look or state.look
        state.error = nil
        if confirmsPendingDestructive then
            state.pendingRemote = false
            state.pendingServerAccepted = true
        else
            clearPending(state)
        end
        if event.active == true then
            if look == nil then
                state.phase = Core.PHASE.Faulted
                state.error = "active server state did not include a look"
                return state, effects
            end
            if state.active and Core.lookEquals(currentState.look, look) and revision == currentState.revision then
                state.phase = Core.PHASE.Active
                clearRollback(state)
                effects[#effects + 1] = effect("IgnoredDuplicateState", { revision = revision })
            else
                state.phase = Core.PHASE.ApplyPending
                state.active = false
                effects[#effects + 1] = effect("Render", {
                    look = Core.copyLook(look),
                    revision = revision,
                    characterId = event.characterId
                })
            end
        else
            state.active = false
            state.phase = confirmsPendingDestructive and Core.PHASE.ClearPending or
                (Core.hasLook(state.look) and Core.PHASE.SavedInactive or Core.PHASE.Idle)
            effects[#effects + 1] = effect("ClearRender", {
                characterId = event.characterId,
                remote = true,
                forget = confirmsPendingDestructive and pendingKindBeforeState == Core.COMMAND.Forget
            })
        end
        return state, effects
    end

    if event.type == "RenderSucceeded" then
        local revision = tonumber(event.revision)
        if revision ~= nil and revision < state.revision then
            effects[#effects + 1] = effect("IgnoredStaleRender", { revision = revision })
            return state, effects
        end
        state.phase = Core.PHASE.Active
        state.active = true
        state.autoApply = true
        state.error = nil
        clearPending(state)
        clearRollback(state)
        effects[#effects + 1] = effect("Persist", { look = Core.copyLook(state.look) })
        return state, effects
    end

    if event.type == "RenderFailed" then
        restoreRollback(state)
        state.phase = Core.PHASE.Faulted
        state.error = tostring(event.reason or "render failed")
        return state, effects
    end

    if event.type == "ClearRenderSucceeded" then
        local kind = event.forget == true and Core.COMMAND.Forget or state.pendingKind
        local preservePending = state.pendingOperationId ~= nil and state.pendingRemote == true
        state.active = false
        state.autoApply = event.preserveAutoApply == true and Core.hasLook(state.look)
        if event.save == true then
            state.phase = Core.PHASE.Saving
            effects[#effects + 1] = effect("Persist", { look = Core.copyLook(state.look) })
            return state, effects
        elseif kind == Core.COMMAND.Forget then
            state.phase = Core.PHASE.ClearPending
            effects[#effects + 1] = effect("ClearPersistence")
            return state, effects
        elseif kind == Core.COMMAND.Clear then
            if Core.hasLook(state.look) then
                state.phase = Core.PHASE.ClearPending
                effects[#effects + 1] = effect("Persist", { look = Core.copyLook(state.look) })
            else
                state.phase = state.characterKey ~= nil and Core.PHASE.Idle or Core.PHASE.NoCharacter
                clearPending(state)
                clearRollback(state)
            end
            return state, effects
        else
            if Core.hasLook(state.look) then
                effects[#effects + 1] = effect("Persist", { look = Core.copyLook(state.look) })
            end
        end
        if preservePending then
            state.phase = Core.PHASE.ClearPending
        else
            state.phase = state.characterKey == nil and Core.PHASE.NoCharacter or
                (Core.hasLook(state.look) and Core.PHASE.SavedInactive or Core.PHASE.Idle)
            clearPending(state)
        end
        clearRollback(state)
        return state, effects
    end

    if event.type == "ClearRenderFailed" then
        local preserveAutoApply = event.preserveAutoApply == true and Core.hasLook(state.look)
        if state.pendingServerAccepted then
            state.active = false
            state.autoApply = false
            if state.pendingKind == Core.COMMAND.Forget then state.look = nil end
            clearPending(state)
            clearRollback(state)
        else
            restoreRollback(state)
        end
        if preserveAutoApply then state.autoApply = true end
        state.phase = Core.PHASE.Faulted
        state.error = tostring(event.reason or "renderer clear failed")
        return state, effects
    end

    if event.type == "PersistenceSucceeded" then
        if state.pendingKind == "hair" then
            clearPending(state)
            clearRollback(state)
        elseif state.pendingKind == Core.COMMAND.Save then
            if state.pendingServerAccepted then
                state.active = false
                state.autoApply = false
                state.phase = state.characterKey ~= nil and Core.PHASE.SavedInactive or Core.PHASE.NoCharacter
                clearPending(state)
                clearRollback(state)
            elseif state.pendingRemote ~= true then
                effects[#effects + 1] = effect("Unequip", { look = Core.copyLook(state.look) })
            end
        elseif state.pendingKind == Core.COMMAND.Forget then
            state.look = nil
            state.active = false
            state.autoApply = false
            clearRollback(state)
            state.phase = state.characterKey ~= nil and Core.PHASE.Idle or Core.PHASE.NoCharacter
            clearPending(state)
        elseif state.pendingKind == Core.COMMAND.Clear then
            state.active = false
            state.autoApply = false
            state.phase = state.characterKey == nil and Core.PHASE.NoCharacter or
                (Core.hasLook(state.look) and Core.PHASE.SavedInactive or Core.PHASE.Idle)
            clearPending(state)
            clearRollback(state)
        end
        return state, effects
    end

    if event.type == "HairUpdateSucceeded" then
        if state.pendingKind == "hair" then
            effects[#effects + 1] = effect("Persist", { look = Core.copyLook(state.look) })
        end
        return state, effects
    end

    if event.type == "PersistenceFailed" or event.type == "HairUpdateFailed" then
        if state.pendingKind == "hair" then
            local rollbackLook = Core.copyLook(state.rollbackLook)
            local needsHairCompensation = event.type == "PersistenceFailed" and state.rollbackActive == true
            restoreRollback(state)
            if needsHairCompensation and rollbackLook ~= nil then
                effects[#effects + 1] = effect("SetHairCompensation", { hidden = rollbackLook.hideHair == true })
            end
        elseif state.pendingKind == Core.COMMAND.Save then
            restoreRollback(state)
            effects[#effects + 1] = effect("AbortCapture")
        elseif state.pendingKind == Core.COMMAND.Forget or state.pendingKind == Core.COMMAND.Clear then
            if state.pendingServerAccepted then
                if state.pendingKind == Core.COMMAND.Forget then state.look = nil end
                state.active = false
                state.autoApply = false
                clearPending(state)
                clearRollback(state)
            else
                local rollbackLook = Core.copyLook(state.rollbackLook)
                local rollbackActive = state.rollbackActive == true
                restoreRollback(state)
                if rollbackActive and rollbackLook ~= nil then
                    effects[#effects + 1] = effect("RenderCompensation", { look = rollbackLook })
                end
            end
        end
        state.phase = Core.PHASE.Faulted
        state.error = tostring(event.reason or "client persistence failed")
        return state, effects
    end

    if event.type == "CompensationSucceeded" then return state, effects end
    if event.type == "CompensationFailed" then
        state.phase = Core.PHASE.Faulted
        state.error = tostring(state.error or "server-accepted cleanup failed") ..
            "; renderer compensation failed: " .. tostring(event.reason or "unknown error")
        return state, effects
    end

    if event.type == "CommandTimedOut" then
        if event.operationId == nil or event.operationId == state.pendingOperationId then
            if state.pendingKind == Core.COMMAND.Save or
                state.pendingKind == Core.COMMAND.Clear or
                state.pendingKind == Core.COMMAND.Forget then
                restoreRollback(state)
            end
            state.phase = Core.PHASE.Faulted
            state.error = tostring(event.reason or "server command timed out")
            clearPending(state)
        end
        return state, effects
    end

    if event.type == "Reset" then
        return Core.newClientState({
            clientSessionId = state.clientSessionId,
            sessionKey = event.sessionKey,
            characterKey = event.characterKey
        }), effects
    end

    error("unknown reducer event " .. tostring(event.type))
end

function Core.copyClientState(state)
    if type(state) ~= "table" then return nil end
    return copyClientState(state)
end

function Core.clientViewModel(state)
    if type(state) ~= "table" then error("state must be a table") end
    local look = Core.copyLook(state.look)
    local phase = state.phase
    local busy = phase == Core.PHASE.Saving or
        phase == Core.PHASE.ApplyPending or
        phase == Core.PHASE.ClearPending
    return {
        phase = phase,
        revision = tonumber(state.revision) or 0,
        characterKey = state.characterKey,
        look = look,
        hasSavedLook = Core.hasLook(look),
        active = state.active == true,
        autoApply = state.autoApply == true,
        busy = busy,
        canSave = state.characterKey ~= nil and not busy,
        canApply = state.characterKey ~= nil and Core.hasLook(look) and not busy,
        canClear = state.characterKey ~= nil and not busy,
        canForget = Core.hasLook(look) and not busy,
        error = state.error
    }
end

local requiredClientEffects = {
    Capture = true,
    AbortCapture = true,
    Unequip = true,
    SendCommand = true,
    Persist = true,
    ClearPersistence = true,
    Render = true,
    RenderCompensation = true,
    ClearRender = true,
    ClearRenderCompensation = true,
    SetHair = true,
    SetHairCompensation = true
}

local function successEventForEffect(currentEffect)
    if currentEffect.type == "Unequip" then return { type = "UnequipSucceeded" } end
    if currentEffect.type == "SendCommand" then
        return {
            type = "CommandSendSucceeded",
            operationId = currentEffect.operationId,
            awaitAck = currentEffect.awaitAck == true
        }
    end
    if currentEffect.type == "Persist" or currentEffect.type == "ClearPersistence" then
        return { type = "PersistenceSucceeded" }
    end
    if currentEffect.type == "Render" then
        return { type = "RenderSucceeded", revision = currentEffect.revision }
    end
    if currentEffect.type == "RenderCompensation" then return { type = "CompensationSucceeded" } end
    if currentEffect.type == "ClearRender" then
        return {
            type = "ClearRenderSucceeded",
            preserveAutoApply = currentEffect.preserveAutoApply == true
        }
    end
    if currentEffect.type == "ClearRenderCompensation" then return { type = "CompensationSucceeded" } end
    if currentEffect.type == "SetHair" then return { type = "HairUpdateSucceeded" } end
    if currentEffect.type == "SetHairCompensation" then return { type = "CompensationSucceeded" } end
    return nil
end

local function failureEventForEffect(currentEffect, reason)
    local message = tostring(reason or (currentEffect.type .. " adapter failed"))
    if currentEffect.type == "Capture" then return { type = "CaptureFailed", reason = message } end
    if currentEffect.type == "Unequip" then return { type = "UnequipFailed", reason = message } end
    if currentEffect.type == "SendCommand" then
        return {
            type = "CommandSendFailed",
            operationId = currentEffect.operationId,
            reason = message
        }
    end
    if currentEffect.type == "Persist" or currentEffect.type == "ClearPersistence" then
        return { type = "PersistenceFailed", reason = message }
    end
    if currentEffect.type == "Render" then return { type = "RenderFailed", reason = message } end
    if currentEffect.type == "RenderCompensation" then
        return { type = "CompensationFailed", reason = message }
    end
    if currentEffect.type == "ClearRender" then
        return {
            type = "ClearRenderFailed",
            reason = message,
            preserveAutoApply = currentEffect.preserveAutoApply == true
        }
    end
    if currentEffect.type == "ClearRenderCompensation" then
        return { type = "CompensationFailed", reason = message }
    end
    if currentEffect.type == "SetHair" then return { type = "HairUpdateFailed", reason = message } end
    if currentEffect.type == "SetHairCompensation" then
        return { type = "CompensationFailed", reason = message }
    end
    return nil
end

local function normalizeAdapterEvents(currentEffect, result, reason)
    if result == false then
        local failure = failureEventForEffect(currentEffect, reason)
        return failure ~= nil and { failure } or {}
    end
    if result == true or result == nil then
        local success = successEventForEffect(currentEffect)
        return success ~= nil and { success } or {}
    end
    if type(result) ~= "table" then
        local failure = failureEventForEffect(currentEffect, "adapter returned " .. type(result))
        return failure ~= nil and { failure } or {}
    end
    if type(result.type) == "string" then
        if currentEffect.type == "ClearRender" and result.type == "ClearRenderSucceeded" and
            result.forget == nil then
            result.forget = currentEffect.forget == true
        end
        if currentEffect.type == "ClearRender" and result.type == "ClearRenderSucceeded" and
            result.save == nil then
            result.save = currentEffect.save == true
        end
        if currentEffect.type == "ClearRender" and
            (result.type == "ClearRenderSucceeded" or result.type == "ClearRenderFailed") and
            result.preserveAutoApply == nil then
            result.preserveAutoApply = currentEffect.preserveAutoApply == true
        end
        return { result }
    end
    local events = {}
    for _, candidate in ipairs(result) do
        if type(candidate) == "table" and type(candidate.type) == "string" then
            events[#events + 1] = candidate
        end
    end
    return events
end

function Core.createClientController(initialState, adapters)
    local state = copyClientState(initialState or Core.newClientState())
    adapters = adapters or {}
    local processing = false

    local function adapterFor(currentEffect)
        local direct = adapters[currentEffect.type]
        if type(direct) == "function" then return direct end
        if type(adapters.run) == "function" then
            return function(effectValue, snapshot)
                return adapters.run(effectValue, snapshot)
            end
        end
        return nil
    end

    local function dispatch(rootEvent)
        if processing then error("client controller dispatch is not re-entrant") end
        processing = true
        local effectHistory = {}
        local feedbackHistory = {}

        local function processEvent(currentEvent, depth)
            if depth > 64 then error("client controller effect chain exceeded 64 events") end
            local nextState, effects = Core.reduce(state, currentEvent)
            state = nextState
            for _, currentEffect in ipairs(effects or {}) do
                effectHistory[#effectHistory + 1] = currentEffect
                if requiredClientEffects[currentEffect.type] then
                    local adapter = adapterFor(currentEffect)
                    local feedbackEvents
                    if adapter == nil then
                        feedbackEvents = normalizeAdapterEvents(
                            currentEffect,
                            false,
                            "missing " .. currentEffect.type .. " adapter"
                        )
                    else
                        local ok, result, reason = pcall(adapter, currentEffect, Core.clientViewModel(state))
                        if not ok then
                            feedbackEvents = normalizeAdapterEvents(currentEffect, false, result)
                        else
                            feedbackEvents = normalizeAdapterEvents(currentEffect, result, reason)
                        end
                    end
                    for _, feedback in ipairs(feedbackEvents) do
                        feedbackHistory[#feedbackHistory + 1] = feedback
                        processEvent(feedback, depth + 1)
                    end
                    if state.phase == Core.PHASE.Faulted then break end
                end
            end
        end

        local ok, reason = pcall(processEvent, rootEvent, 0)
        processing = false
        if not ok then error(reason) end
        return effectHistory, feedbackHistory
    end

    return {
        dispatch = dispatch,
        getState = function() return copyClientState(state) end,
        getViewModel = function() return Core.clientViewModel(state) end
    }
end

function Core.selfTest()
    local emptyLook = assert(Core.newLook(true, false, {}))
    assert(Core.hasLook(emptyLook), "captured empty look must be preserved")

    local look = assert(Core.newLook(true, true, { Head = "ballistichelmet", Bag = "duffelbag" }))
    assert(look.slots.Head == "ballistichelmet")
    assert(Core.validateLook({ schemaVersion = 99, slots = {} }) == nil)
    assert(Core.validateLook({ slots = { Unknown = "bad" } }) == nil)

    local state = Core.newClientState({ characterKey = "7" })
    state = Core.reduce(state, { type = "SaveRequested" })
    assert(state.phase == Core.PHASE.Saving)
    state = Core.reduce(state, { type = "CaptureSucceeded", look = look })
    assert(state.phase == Core.PHASE.Saving)
    state = Core.reduce(state, { type = "UnequipSucceeded" })
    assert(state.phase == Core.PHASE.SavedInactive)
    state = Core.reduce(state, {
        type = "RemoteStateReceived",
        revision = 2,
        characterId = 7,
        active = true,
        look = look
    })
    assert(state.phase == Core.PHASE.ApplyPending)
    state = Core.reduce(state, { type = "RenderSucceeded", revision = 2 })
    assert(state.phase == Core.PHASE.Active)
    local unchanged, effects = Core.reduce(state, {
        type = "RemoteStateReceived",
        revision = 1,
        characterId = 7,
        active = false
    })
    assert(unchanged.phase == Core.PHASE.Active)
    assert(effects[1].type == "IgnoredStaleState")
    return true
end

WardrobeCore = Core
return Core
