local MOD_NAME = "Baro Wardrobe Switcher"

if not SERVER then return end

-- WardrobeCore is loaded first by ModConfig in v0.5.1. Keep the constants below
-- as a deployment-safe fallback so a partially upgraded installation fails
-- gracefully instead of preventing the server script from loading.
local Core = rawget(_G, "WardrobeCore") or rawget(_G, "BaroWardrobeCore")
local NET = Core ~= nil and Core.NET or {
    SAVE_REQUEST = "barowardrobeswitcher.save",
    APPLY_REQUEST = "barowardrobeswitcher.apply",
    CLEAR_REQUEST = "barowardrobeswitcher.clear",
    FORGET_REQUEST = "barowardrobeswitcher.forget",
    LOOK_APPLY = "barowardrobeswitcher.look.apply",
    LOOK_CLEAR = "barowardrobeswitcher.look.clear",
    V2_HELLO = "barowardrobeswitcher.v2.hello",
    V2_COMMAND = "barowardrobeswitcher.v2.command",
    V2_STATE = "barowardrobeswitcher.v2.state",
    V2_ACK = "barowardrobeswitcher.v2.ack"
}
NET.SAVE_REQUEST = NET.SAVE_REQUEST or NET.V1_SAVE_REQUEST or "barowardrobeswitcher.save"
NET.APPLY_REQUEST = NET.APPLY_REQUEST or NET.V1_APPLY_REQUEST or "barowardrobeswitcher.apply"
NET.CLEAR_REQUEST = NET.CLEAR_REQUEST or NET.V1_CLEAR_REQUEST or "barowardrobeswitcher.clear"
NET.FORGET_REQUEST = NET.FORGET_REQUEST or NET.V1_FORGET_REQUEST or "barowardrobeswitcher.forget"
NET.LOOK_APPLY = NET.LOOK_APPLY or NET.V1_LOOK_APPLY or "barowardrobeswitcher.look.apply"
NET.LOOK_CLEAR = NET.LOOK_CLEAR or NET.V1_LOOK_CLEAR or "barowardrobeswitcher.look.clear"
local PROTOCOL_VERSION = Core ~= nil and (Core.PROTOCOL_VERSION or Core.PROTOCOL) or 2
local LOOK_SCHEMA_VERSION = Core ~= nil and (Core.LOOK_SCHEMA_VERSION or Core.SCHEMA_VERSION) or 2
local PERSISTENCE_VERSION = Core ~= nil and Core.PERSISTENCE_VERSION or 3
local LIMITS = Core ~= nil and Core.LIMITS or {}
local MAX_SLOTS = tonumber(LIMITS.MAX_SLOTS or LIMITS.maxSlots) or 6
local MAX_IDENTIFIER_BYTES = tonumber(LIMITS.MAX_IDENTIFIER_BYTES or LIMITS.maxIdentifierBytes) or 256
local MAX_PAYLOAD_BYTES = tonumber(LIMITS.MAX_PAYLOAD_BYTES or LIMITS.maxPayloadBytes) or 4096
local MAX_SESSION_ID_BYTES = 128
local MAX_OPERATION_ID_BYTES = 128
local MAX_SEEN_OPERATIONS = tonumber(LIMITS.MAX_SEEN_OPERATIONS or LIMITS.maxSeenOperations) or 512
local MAX_REVISION = 4294967295
local ATTACHMENT_KEYS = Core ~= nil and Core.ATTACHMENT_KEYS or {
    "Hair",
    "Beard",
    "Moustache",
    "FaceAttachment"
}
local ATTACHMENT_BITS = Core ~= nil and Core.ATTACHMENT_BITS or {
    Hair = 0x01,
    Beard = 0x02,
    Moustache = 0x04,
    FaceAttachment = 0x08
}
local ATTACHMENT_VISIBILITY = Core ~= nil and Core.ATTACHMENT_VISIBILITY or {
    Auto = "auto",
    Hide = "hide",
    Show = "show"
}
local ATTACHMENT_MASK = Core ~= nil and Core.ATTACHMENT_MASK or 0x0F
local CAPABILITY_ATTACHMENT_VISIBILITY =
    Core ~= nil and Core.CAPABILITY ~= nil and Core.CAPABILITY.AttachmentVisibility or 0x01
local COMMAND_VISIBILITY =
    Core ~= nil and Core.COMMAND ~= nil and Core.COMMAND.Visibility or "visibility"
local SUPPORTS_ATTACHMENT_VISIBILITY =
    Core ~= nil and
    type(Core.validateAttachmentVisibility) == "function" and
    type(Core.attachmentVisibilityMasks) == "function" and
    (type(Core.readLook) == "function" or type(Core.ReadLook) == "function") and
    (type(Core.writeLook) == "function" or type(Core.WriteLook) == "function")

local CharacterInventory = nil
local Client = nil
local GameMain = nil
local ItemPrefab = nil
local Environment = nil
local Directory = nil
local File = nil
local EnvironmentSpecialFolder = nil
pcall(function() CharacterInventory = LuaUserData.CreateStatic("Barotrauma.CharacterInventory", true) end)
pcall(function() Client = LuaUserData.CreateStatic("Barotrauma.Networking.Client", true) end)
pcall(function() GameMain = LuaUserData.CreateStatic("Barotrauma.GameMain", true) end)
pcall(function() ItemPrefab = LuaUserData.CreateStatic("Barotrauma.ItemPrefab", true) end)
pcall(function() Environment = LuaUserData.CreateStatic("System.Environment", true) end)
pcall(function() Directory = LuaUserData.CreateStatic("System.IO.Directory", true) end)
pcall(function() File = LuaUserData.CreateStatic("System.IO.File", true) end)
pcall(function() EnvironmentSpecialFolder = CreateEnum("System.Environment+SpecialFolder") end)

local slots = {
    { key = "Head", slot = InvSlotType.Head },
    { key = "Headset", slot = InvSlotType.Headset },
    { key = "InnerClothes", slot = InvSlotType.InnerClothes },
    { key = "OuterClothes", slot = InvSlotType.OuterClothes },
    { key = "Bag", slot = InvSlotType.Bag },
    { key = "HealthInterface", slot = InvSlotType.HealthInterface }
}
local slotByKey = {}
for _, entry in ipairs(slots) do slotByKey[entry.key] = entry end

local persistentRecords = {}
local legacySteamRecords = {}
local migratedLegacySteamIds = {}
local sessionsByClient = setmetatable({}, { __mode = "k" })
local operationCachesByAccount = {}
local activeByCharacterId = {}
local serverSessionId = tostring(os.time()) .. "-" .. tostring(math.random(100000, 999999))
local lastGameSessionKey = nil

local function log(message)
    local line = "[" .. MOD_NAME .. "] " .. tostring(message)
    if LuaCsLogger ~= nil and LuaCsLogger.Log ~= nil then
        LuaCsLogger.Log(line)
    else
        print(line)
    end
end

local function warn(message)
    local line = "[" .. MOD_NAME .. "] " .. tostring(message)
    if LuaCsLogger ~= nil and LuaCsLogger.LogError ~= nil then
        LuaCsLogger.LogError(line)
    else
        log(message)
    end
end

local function trim(value)
    if value == nil then return nil end
    local text = tostring(value):match("^%s*(.-)%s*$")
    if text == nil or text == "" or text:lower() == "nil" or text:lower() == "null" then return nil end
    return text
end

local function byteLength(value)
    return #(tostring(value or ""))
end

local function messageLengthBytes(message)
    if message == nil then return nil end
    local ok, value = pcall(function() return message.LengthBytes end)
    if ok and tonumber(value) ~= nil then return tonumber(value) end
    ok, value = pcall(function() return message.LengthBits end)
    if ok and tonumber(value) ~= nil then return math.ceil(tonumber(value) / 8) end
    return nil
end

local function attachmentVisibilityFromLegacy(hideHair)
    if Core ~= nil and Core.attachmentVisibilityFromLegacy ~= nil then
        return Core.attachmentVisibilityFromLegacy(hideHair == true)
    end
    local hidden = hideHair == true
    return {
        Hair = hidden and ATTACHMENT_VISIBILITY.Hide or ATTACHMENT_VISIBILITY.Auto,
        Beard = hidden and ATTACHMENT_VISIBILITY.Hide or ATTACHMENT_VISIBILITY.Auto,
        Moustache = hidden and ATTACHMENT_VISIBILITY.Hide or ATTACHMENT_VISIBILITY.Auto,
        FaceAttachment = ATTACHMENT_VISIBILITY.Auto
    }
end

local function validateAttachmentVisibility(value, legacyHideHair)
    if Core ~= nil and Core.validateAttachmentVisibility ~= nil then
        return Core.validateAttachmentVisibility(value, legacyHideHair == true)
    end
    if value == nil then return attachmentVisibilityFromLegacy(legacyHideHair) end
    if type(value) ~= "table" then return nil, "invalid_attachment_visibility" end
    local expected = {}
    for _, key in ipairs(ATTACHMENT_KEYS) do expected[key] = true end
    for key in pairs(value) do
        if expected[key] ~= true then return nil, "unknown_attachment_layer" end
    end
    local result = {}
    for _, key in ipairs(ATTACHMENT_KEYS) do
        local state = value[key]
        if state ~= ATTACHMENT_VISIBILITY.Auto and
            state ~= ATTACHMENT_VISIBILITY.Hide and
            state ~= ATTACHMENT_VISIBILITY.Show then
            return nil, "invalid_attachment_visibility"
        end
        result[key] = state
    end
    return result
end

local function copyAttachmentVisibility(value, legacyHideHair)
    local visibility = validateAttachmentVisibility(value, legacyHideHair)
    if visibility == nil then return attachmentVisibilityFromLegacy(legacyHideHair) end
    local copy = {}
    for _, key in ipairs(ATTACHMENT_KEYS) do copy[key] = visibility[key] end
    return copy
end

local function legacyHideHair(value)
    if Core ~= nil and Core.legacyHideHair ~= nil then return Core.legacyHideHair(value) end
    local visibility = validateAttachmentVisibility(value, false)
    return visibility ~= nil and
        visibility.Hair == ATTACHMENT_VISIBILITY.Hide and
        visibility.Beard == ATTACHMENT_VISIBILITY.Hide and
        visibility.Moustache == ATTACHMENT_VISIBILITY.Hide
end

local function attachmentVisibilityMasks(value)
    if Core ~= nil and Core.attachmentVisibilityMasks ~= nil then
        return Core.attachmentVisibilityMasks(value)
    end
    local visibility, reason = validateAttachmentVisibility(value, false)
    if visibility == nil then return nil, nil, reason end
    local forceHide, forceShow = 0, 0
    for _, key in ipairs(ATTACHMENT_KEYS) do
        local bit = ATTACHMENT_BITS[key]
        if visibility[key] == ATTACHMENT_VISIBILITY.Hide then
            forceHide = forceHide + bit
        elseif visibility[key] == ATTACHMENT_VISIBILITY.Show then
            forceShow = forceShow + bit
        end
    end
    return forceHide, forceShow
end

local function cloneLook(look)
    if look == nil then return nil end
    local attachmentVisibility =
        copyAttachmentVisibility(look.attachmentVisibility, look.hideHair == true)
    local cloned = {
        schemaVersion = LOOK_SCHEMA_VERSION,
        captured = look.captured == true,
        hideHair = legacyHideHair(attachmentVisibility),
        attachmentVisibility = attachmentVisibility,
        slots = {}
    }
    for _, entry in ipairs(slots) do
        local source = look.slots ~= nil and look.slots[entry.key] or nil
        if source ~= nil then
            if type(source) == "table" then
                cloned.slots[entry.key] = {
                    identifier = tostring(source.identifier or ""),
                    itemId = tonumber(source.itemId) or 0,
                    name = tostring(source.name or "")
                }
            else
                cloned.slots[entry.key] = { identifier = tostring(source), itemId = 0, name = "" }
            end
        end
    end
    return cloned
end

local function characterEntityId(character)
    if character == nil then return 0 end
    local ok, id = pcall(function() return character.ID end)
    return ok and tonumber(id) or 0
end

local function clientCharacter(client)
    if client == nil then return nil end
    local ok, character = pcall(function() return client.Character end)
    return ok and character or nil
end

local function userDataMember(object, name)
    if object == nil then return nil end
    local ok, value = pcall(function() return object[name] end)
    return ok and value or nil
end

local function normalizedSessionValue(value)
    local text = trim(value)
    return text ~= nil and text:gsub("\\", "/") or nil
end

local function firstSessionValue(object, names)
    for _, name in ipairs(names) do
        local value = normalizedSessionValue(userDataMember(object, name))
        if value ~= nil then return value end
    end
    return nil
end

local function currentGameSessionKey()
    if GameMain == nil then return nil end
    local session = userDataMember(GameMain, "GameSession")
    if session == nil then return nil end
    local direct = firstSessionValue(session, { "SavePath", "SaveFilePath", "SaveFile", "FilePath" })
    if direct ~= nil then return "session:" .. direct end
    local gameMode = userDataMember(session, "GameMode")
    local fromMode = firstSessionValue(gameMode, { "SavePath", "SaveFilePath", "SaveFile", "FilePath" })
    if fromMode ~= nil then return "gamemode:" .. fromMode end
    local campaign = userDataMember(session, "Campaign") or userDataMember(gameMode, "Campaign")
    local fromCampaign = firstSessionValue(campaign, {
        "SavePath", "SaveFilePath", "SaveFile", "FilePath", "CampaignID", "Identifier"
    })
    if fromCampaign ~= nil then return "campaign:" .. fromCampaign end
    return nil
end

local function accountIdForClient(client)
    if client == nil then return nil end
    local ok, option = pcall(function() return client.AccountId end)
    if not ok or option == nil then return nil end

    local isSome = false
    pcall(function() isSome = option.IsSome() == true end)
    if not isSome then return nil end

    local function representation(accountId)
        if accountId == nil or type(accountId) == "boolean" then return nil end
        local value = trim(userDataMember(accountId, "StringRepresentation"))
        return value
    end

    -- LuaCs versions have exposed out parameters in more than one shape. Try
    -- the official TryUnwrap API first and accept either return ordering.
    local called, first, second = pcall(function() return option.TryUnwrap() end)
    if called then
        local value = representation(second) or representation(first)
        if value ~= nil then return value end
        if type(first) == "table" then
            value = representation(first[2]) or representation(first.value) or representation(first.Value)
            if value ~= nil then return value end
        end
    end

    -- Some LuaCs binders resolve the Action overload more reliably than an out
    -- parameter. Match is also part of the official Option API.
    local matched = nil
    pcall(function()
        option.Match(
            function(value) matched = value end,
            function() end
        )
    end)
    local matchedValue = representation(matched)
    if matchedValue ~= nil then return matchedValue end

    -- Publicized builds can expose the backing value. This remains a guarded
    -- compatibility path and still reads AccountId.StringRepresentation.
    local backing = userDataMember(option, "value") or userDataMember(option, "Value")
    local backingValue = representation(backing)
    if backingValue ~= nil then return backingValue end

    -- Last-resort bridge for older LuaCs binders that expose neither out values
    -- nor delegates. Require IsSome and the exact Option<T>.ToString shape.
    local value = tostring(option):match("^Some<.-%((.*)%)$")
    return trim(value)
end

local function steamIdForClient(client)
    if client == nil then return nil end
    local ok, value = pcall(function() return client.SteamID end)
    if not ok then return nil end
    value = trim(value)
    if value == nil or value:match("^0+$") then return nil end
    return value
end

local function connectedClients()
    local result, seen = {}, {}
    local function append(client)
        if client ~= nil and not seen[client] then
            seen[client] = true
            result[#result + 1] = client
        end
    end
    local function collect(source)
        if source == nil then return end
        local ok = pcall(function() for client in source do append(client) end end)
        if ok then return end
        ok = pcall(function() for _, client in pairs(source) do append(client) end end)
        if ok then return end
        pcall(function()
            local count = tonumber(source.Count) or 0
            for index = 0, count - 1 do append(source[index]) end
        end)
    end
    if Client ~= nil then collect(userDataMember(Client, "ClientList")) end
    local server = GameMain ~= nil and userDataMember(GameMain, "Server") or nil
    collect(server ~= nil and userDataMember(server, "ConnectedClients") or nil)
    local ok, gameServer = pcall(function() return Game ~= nil and Game.Server or nil end)
    if ok and gameServer ~= nil then collect(userDataMember(gameServer, "ConnectedClients")) end
    return result
end

-- JSON codec kept local to avoid adding a server-side C# assembly. It accepts
-- standard JSON but the writer emits only the persistence-v3 document below.
local function jsonEscape(value)
    return tostring(value or "")
        :gsub("\\", "\\\\")
        :gsub('"', '\\"')
        :gsub("\b", "\\b")
        :gsub("\f", "\\f")
        :gsub("\n", "\\n")
        :gsub("\r", "\\r")
        :gsub("\t", "\\t")
        :gsub("[%z\1-\31]", function(character) return string.format("\\u%04x", string.byte(character)) end)
end

local function decodeJson(text)
    local position, length = 1, #text
    local function skipSpace()
        while position <= length and text:sub(position, position):match("%s") do position = position + 1 end
    end
    local parseValue
    local function parseString()
        if text:sub(position, position) ~= '"' then error("expected string") end
        position = position + 1
        local result = {}
        while position <= length do
            local character = text:sub(position, position)
            if character == '"' then
                position = position + 1
                return table.concat(result)
            end
            if character == "\\" then
                local escape = text:sub(position + 1, position + 1)
                local replacements = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }
                if replacements[escape] ~= nil then
                    result[#result + 1] = replacements[escape]
                    position = position + 2
                elseif escape == "u" then
                    local hex = text:sub(position + 2, position + 5)
                    local codepoint = tonumber(hex, 16)
                    if codepoint == nil then error("invalid unicode escape") end
                    if utf8 ~= nil and utf8.char ~= nil then
                        result[#result + 1] = utf8.char(codepoint)
                    elseif codepoint <= 255 then
                        result[#result + 1] = string.char(codepoint)
                    else
                        result[#result + 1] = "?"
                    end
                    position = position + 6
                else
                    error("invalid string escape")
                end
            else
                if string.byte(character) < 32 then error("control character in string") end
                result[#result + 1] = character
                position = position + 1
            end
        end
        error("unterminated string")
    end
    local function parseArray()
        position = position + 1
        local result = {}
        skipSpace()
        if text:sub(position, position) == "]" then position = position + 1 return result end
        while true do
            result[#result + 1] = parseValue()
            skipSpace()
            local separator = text:sub(position, position)
            if separator == "]" then position = position + 1 return result end
            if separator ~= "," then error("expected array separator") end
            position = position + 1
        end
    end
    local function parseObject()
        position = position + 1
        local result = {}
        skipSpace()
        if text:sub(position, position) == "}" then position = position + 1 return result end
        while true do
            skipSpace()
            local key = parseString()
            skipSpace()
            if text:sub(position, position) ~= ":" then error("expected object separator") end
            position = position + 1
            result[key] = parseValue()
            skipSpace()
            local separator = text:sub(position, position)
            if separator == "}" then position = position + 1 return result end
            if separator ~= "," then error("expected member separator") end
            position = position + 1
        end
    end
    parseValue = function()
        skipSpace()
        local character = text:sub(position, position)
        if character == '"' then return parseString() end
        if character == "{" then return parseObject() end
        if character == "[" then return parseArray() end
        if text:sub(position, position + 3) == "true" then position = position + 4 return true end
        if text:sub(position, position + 4) == "false" then position = position + 5 return false end
        if text:sub(position, position + 3) == "null" then position = position + 4 return nil end
        local start = position
        while position <= length and text:sub(position, position):match("[%d%+%-%.eE]") do position = position + 1 end
        if start == position then error("expected value") end
        local number = tonumber(text:sub(start, position - 1))
        if number == nil then error("invalid number") end
        return number
    end
    local value = parseValue()
    skipSpace()
    if position <= length then error("trailing JSON data") end
    return value
end

local function storageDirectory()
    if Environment == nil then return nil end
    local ok, root = pcall(function()
        local value = EnvironmentSpecialFolder ~= nil and EnvironmentSpecialFolder.LocalApplicationData or 28
        return Environment.GetFolderPath(value)
    end)
    if not ok or trim(root) == nil then return nil end
    return tostring(root):gsub("\\", "/") .. "/Daedalic Entertainment GmbH/Barotrauma/ModData/BaroWardrobeSwitcher"
end

local function storagePath(fileName)
    local directory = storageDirectory()
    return directory ~= nil and (directory .. "/" .. fileName) or nil
end

local function fileExists(path)
    if File == nil or path == nil then return false end
    local ok, exists = pcall(function() return File.Exists(path) end)
    return ok and exists == true
end

local function readAllText(path)
    if File == nil or path == nil then return nil end
    local ok, text = pcall(function() return File.ReadAllText(path) end)
    return ok and tostring(text) or nil
end

local function ensureStorageDirectory()
    local directory = storageDirectory()
    if Directory == nil or directory == nil then return false end
    return pcall(function() Directory.CreateDirectory(directory) end)
end

-- Persistence is replace-based so a crash cannot expose a partially written
-- document. The backup path also gives the fallback Move implementation a
-- recoverable copy of the previous state.
local function atomicWrite(path, contents)
    if File == nil or path == nil or not ensureStorageDirectory() then return false, "storage_unavailable" end
    local temporaryPath = path .. ".tmp"
    local backupPath = path .. ".bak"
    local ok, failure = pcall(function()
        if File.Exists(temporaryPath) then File.Delete(temporaryPath) end
        File.WriteAllText(temporaryPath, contents)
        if File.Exists(path) then
            if File.Exists(backupPath) then File.Delete(backupPath) end
            local replaced = pcall(function() File.Replace(temporaryPath, path, backupPath) end)
            if not replaced then
                File.Copy(path, backupPath, true)
                File.Move(temporaryPath, path, true)
            end
        else
            File.Move(temporaryPath, path)
        end
    end)
    if not ok then
        pcall(function() if File.Exists(temporaryPath) then File.Delete(temporaryPath) end end)
        return false, tostring(failure)
    end
    return true
end

local function hasOnlyFields(value, allowed)
    if type(value) ~= "table" then return false end
    for key in pairs(value) do
        if allowed[key] ~= true then return false end
    end
    return true
end

local function encodeAttachmentVisibilityJson(visibility)
    local canonical = copyAttachmentVisibility(visibility, false)
    local members = {}
    for _, key in ipairs(ATTACHMENT_KEYS) do
        members[#members + 1] = '"' .. key .. '":"' .. jsonEscape(canonical[key]) .. '"'
    end
    return "{" .. table.concat(members, ",") .. "}"
end

local function encodeLookJson(look)
    local members = {
        '"schemaVersion":' .. tostring(LOOK_SCHEMA_VERSION),
        '"captured":' .. tostring(look ~= nil and look.captured == true),
        '"attachmentVisibility":' .. encodeAttachmentVisibilityJson(
            look ~= nil and look.attachmentVisibility or nil
        )
    }
    local slotMembers = {}
    for _, entry in ipairs(slots) do
        local slot = look ~= nil and look.slots ~= nil and look.slots[entry.key] or nil
        local identifier = slot ~= nil and (type(slot) == "table" and slot.identifier or slot) or nil
        identifier = trim(identifier)
        if identifier ~= nil then
            slotMembers[#slotMembers + 1] = '"' .. entry.key .. '":"' .. jsonEscape(identifier) .. '"'
        end
    end
    members[#members + 1] = '"slots":{' .. table.concat(slotMembers, ",") .. "}"
    return "{" .. table.concat(members, ",") .. "}"
end

local function encodePersistenceDocument()
    local accountIds = {}
    for accountId in pairs(persistentRecords) do accountIds[#accountIds + 1] = accountId end
    table.sort(accountIds)
    local records = {}
    for _, accountId in ipairs(accountIds) do
        local record = persistentRecords[accountId]
        if record ~= nil and record.savedLook ~= nil then
            records[#records + 1] = "{" .. table.concat({
                '"accountId":"' .. jsonEscape(accountId) .. '"',
                '"revision":' .. tostring(math.max(0, math.floor(tonumber(record.revision) or 0))),
                '"active":' .. tostring(record.active == true),
                '"sessionKey":' .. (record.sessionKey ~= nil and ('"' .. jsonEscape(record.sessionKey) .. '"') or "null"),
                '"look":' .. encodeLookJson(record.savedLook)
            }, ",") .. "}"
        end
    end
    local migrated = {}
    for steamId in pairs(migratedLegacySteamIds) do migrated[#migrated + 1] = steamId end
    table.sort(migrated)
    for index, steamId in ipairs(migrated) do migrated[index] = '"' .. jsonEscape(steamId) .. '"' end
    local pendingLegacyIds = {}
    for steamId, record in pairs(legacySteamRecords) do
        if record ~= nil and record.savedLook ~= nil and migratedLegacySteamIds[steamId] ~= true then
            pendingLegacyIds[#pendingLegacyIds + 1] = steamId
        end
    end
    table.sort(pendingLegacyIds)
    local pendingLegacy = {}
    for _, steamId in ipairs(pendingLegacyIds) do
        local record = legacySteamRecords[steamId]
        pendingLegacy[#pendingLegacy + 1] = "{" .. table.concat({
            '"steamId":"' .. jsonEscape(steamId) .. '"',
            '"revision":' .. tostring(math.max(0, math.floor(tonumber(record.revision) or 0))),
            '"active":' .. tostring(record.active == true),
            '"sessionKey":' .. (record.sessionKey ~= nil and ('"' .. jsonEscape(record.sessionKey) .. '"') or "null"),
            '"look":' .. encodeLookJson(record.savedLook)
        }, ",") .. "}"
    end
    return "{" .. table.concat({
        '"schemaVersion":' .. tostring(PERSISTENCE_VERSION),
        '"records":[' .. table.concat(records, ",") .. "]",
        '"pendingLegacySteamRecords":[' .. table.concat(pendingLegacy, ",") .. "]",
        '"migratedLegacySteamIds":[' .. table.concat(migrated, ",") .. "]"
    }, ",") .. "}\n"
end

local function persistLooks()
    local path = storagePath("ServerLooks.json")
    local ok, reason = atomicWrite(path, encodePersistenceDocument())
    if not ok then warn("Could not atomically persist server wardrobes: " .. tostring(reason)) end
    return ok
end

local function escapeLegacy(value)
    local text = tostring(value or "")
    return text:gsub("%%0D", "\r"):gsub("%%0A", "\n"):gsub("%%3D", "="):gsub("%%2C", ","):gsub("%%7C", "|"):gsub("%%25", "%%")
end

local function parseLegacyDocument(text)
    local accountRecords, steamRecords = {}, {}
    for line in tostring(text):gmatch("[^\r\n]+") do
        local identity, sessionKey, active = nil, nil, false
        local sawActive = false
        local look = {
            schemaVersion = LOOK_SCHEMA_VERSION,
            captured = true,
            hideHair = false,
            attachmentVisibility = attachmentVisibilityFromLegacy(false),
            slots = {}
        }
        for part in line:gmatch("[^|]+") do
            local name, value = part:match("^([^=]+)=(.*)$")
            if name == nil then return nil, nil, "malformed_field" end
            if name == "key" then
                if identity ~= nil then return nil, nil, "duplicate_identity" end
                identity = escapeLegacy(value)
            elseif name == "session" then
                sessionKey = normalizedSessionValue(escapeLegacy(value))
            elseif name == "active" then
                if value ~= "true" and value ~= "false" then return nil, nil, "invalid_active_flag" end
                active = value == "true"
                sawActive = true
            elseif slotByKey[name] ~= nil then
                local identifier = tostring(value):match("^([^,]*),.*$")
                if identifier == nil then return nil, nil, "truncated_slot:" .. tostring(name) end
                identifier = trim(escapeLegacy(identifier or ""))
                if identifier == nil or byteLength(identifier) > MAX_IDENTIFIER_BYTES then
                    return nil, nil, "invalid_identifier:" .. tostring(name)
                end
                look.slots[name] = { identifier = identifier, itemId = 0, name = "" }
            else
                return nil, nil, "unknown_field:" .. tostring(name)
            end
        end
        if identity == nil or not sawActive then return nil, nil, "incomplete_record" end
        local kind, value = tostring(identity or ""):match("^([%a_]+):(.*)$")
        if kind == nil and tostring(identity or ""):match("^%d+$") then kind, value = "steam", identity end
        value = trim(value)
        if value == nil or (kind ~= "account" and kind ~= "steam") then return nil, nil, "invalid_identity" end
        local destination = kind == "account" and accountRecords or steamRecords
        if destination[value] ~= nil then return nil, nil, "duplicate_record" end
        destination[value] = { revision = 1, savedLook = look, active = active, sessionKey = sessionKey }
    end
    return accountRecords, steamRecords
end

local function validateStoredLook(raw, persistenceVersion)
    if type(raw) ~= "table" or type(raw.schemaVersion) ~= "number" or
        raw.schemaVersion ~= LOOK_SCHEMA_VERSION or
        raw.captured ~= true or type(raw.slots) ~= "table" then
        return nil
    end
    local visibility
    if persistenceVersion == PERSISTENCE_VERSION then
        if not hasOnlyFields(raw, {
            schemaVersion = true,
            captured = true,
            attachmentVisibility = true,
            slots = true
        }) or raw.hideHair ~= nil or type(raw.attachmentVisibility) ~= "table" then
            return nil
        end
        visibility = validateAttachmentVisibility(raw.attachmentVisibility, false)
    elseif persistenceVersion == 2 then
        if not hasOnlyFields(raw, {
            schemaVersion = true,
            captured = true,
            hideHair = true,
            slots = true
        }) or type(raw.hideHair) ~= "boolean" then
            return nil
        end
        visibility = attachmentVisibilityFromLegacy(raw.hideHair == true)
    else
        return nil
    end
    if visibility == nil then return nil end
    local look = {
        schemaVersion = LOOK_SCHEMA_VERSION,
        captured = raw.captured == true,
        hideHair = legacyHideHair(visibility),
        attachmentVisibility = visibility,
        slots = {}
    }
    local count = 0
    for key, identifier in pairs(raw.slots) do
        if slotByKey[key] == nil or type(identifier) ~= "string" or byteLength(identifier) > MAX_IDENTIFIER_BYTES then return nil end
        identifier = trim(identifier)
        if identifier == nil then return nil end
        count = count + 1
        if count > MAX_SLOTS then return nil end
        look.slots[key] = { identifier = identifier, itemId = 0, name = "" }
    end
    return look
end

local function quarantine(path, reason)
    local suffix = os.date("!%Y%m%d-%H%M%S")
    local destination = path .. "." .. suffix .. ".corrupt"
    local moved = File ~= nil and pcall(function() File.Move(path, destination, true) end)
    warn("Quarantined invalid wardrobe persistence" .. (moved and " to " .. destination or "") .. ": " .. tostring(reason))
end

local function decodeStoredRecord(raw, persistenceVersion, identityField)
    if type(raw) ~= "table" or not hasOnlyFields(raw, {
        [identityField] = true,
        revision = true,
        active = true,
        sessionKey = true,
        look = true
    }) then
        return nil
    end
    if type(raw[identityField]) ~= "string" or
        type(raw.active) ~= "boolean" or
        type(raw.revision) ~= "number" or
        (raw.sessionKey ~= nil and type(raw.sessionKey) ~= "string") then
        return nil
    end
    local look = validateStoredLook(raw.look, persistenceVersion)
    local revision = raw.revision
    if look == nil or revision == nil or revision < 0 or revision > 4294967295 or revision % 1 ~= 0 then
        return nil
    end
    return {
        revision = math.floor(revision),
        savedLook = look,
        active = raw.active == true,
        sessionKey = normalizedSessionValue(raw.sessionKey)
    }
end

local function loadJsonPersistence(path)
    local text = readAllText(path)
    if text == nil then return false end
    local ok, document = pcall(decodeJson, text)
    local documentVersion =
        ok and type(document) == "table" and type(document.schemaVersion) == "number" and
        document.schemaVersion or nil
    if not ok or
        (documentVersion ~= PERSISTENCE_VERSION and documentVersion ~= 2) or
        type(document.records) ~= "table" or
        type(document.pendingLegacySteamRecords) ~= "table" or
        type(document.migratedLegacySteamIds) ~= "table" or
        not hasOnlyFields(document, {
            schemaVersion = true,
            records = true,
            pendingLegacySteamRecords = true,
            migratedLegacySteamIds = true
        }) then
        quarantine(path, ok and "invalid_schema" or document)
        return false
    end
    local loaded = {}
    for _, raw in ipairs(document.records) do
        local accountId = type(raw) == "table" and trim(raw.accountId) or nil
        local record = decodeStoredRecord(raw, documentVersion, "accountId")
        if accountId == nil or loaded[accountId] ~= nil or record == nil then
            quarantine(path, "invalid_record")
            return false
        end
        loaded[accountId] = record
    end
    if document.migratedLegacySteamIds ~= nil and type(document.migratedLegacySteamIds) ~= "table" then
        quarantine(path, "invalid_migrated_legacy_ids")
        return false
    end
    local loadedMigrated = {}
    for _, steamId in ipairs(document.migratedLegacySteamIds or {}) do
        if type(steamId) ~= "string" then
            quarantine(path, "invalid_migrated_legacy_id")
            return false
        end
        steamId = trim(steamId)
        if steamId == nil or loadedMigrated[steamId] then
            quarantine(path, "invalid_migrated_legacy_id")
            return false
        end
        loadedMigrated[steamId] = true
    end
    local pendingLegacy = {}
    if document.pendingLegacySteamRecords ~= nil and type(document.pendingLegacySteamRecords) ~= "table" then
        quarantine(path, "invalid_pending_legacy_records")
        return false
    end
    for _, raw in ipairs(document.pendingLegacySteamRecords or {}) do
        local steamId = type(raw) == "table" and trim(raw.steamId) or nil
        local record = decodeStoredRecord(raw, documentVersion, "steamId")
        if steamId == nil or pendingLegacy[steamId] ~= nil or record == nil then
            quarantine(path, "invalid_pending_legacy_record")
            return false
        end
        if loadedMigrated[steamId] ~= true then pendingLegacy[steamId] = record end
    end
    persistentRecords = loaded
    migratedLegacySteamIds = loadedMigrated
    legacySteamRecords = pendingLegacy
    if documentVersion == 2 then
        local backupPath = path .. ".v2.bak"
        local backedUp = File ~= nil and pcall(function()
            if File.Exists(backupPath) then File.Delete(backupPath) end
            File.Copy(path, backupPath, true)
        end)
        if not backedUp then
            warn("Could not preserve ServerLooks.json.v2.bak; leaving the valid v2 file unchanged.")
            return true
        end
        if persistLooks() then
            log("Migrated server wardrobe persistence from v2 to v3.")
        else
            warn("Could not persist migrated server wardrobe v3; the v2 source remains available for retry.")
        end
    end
    return true
end

local function moveLegacyToBackup(path)
    if File == nil or not fileExists(path) then return end
    local backup = path .. ".v1.bak"
    pcall(function()
        if File.Exists(backup) then File.Delete(backup) end
        File.Move(path, backup)
    end)
end

local function loadLegacyPersistence(path)
    local text = readAllText(path)
    if text == nil then return false end
    local accounts, steam, reason = parseLegacyDocument(text)
    if accounts == nil or steam == nil then
        quarantine(path, reason or "invalid_legacy_document")
        return false
    end
    for accountId, record in pairs(accounts) do
        if persistentRecords[accountId] == nil then persistentRecords[accountId] = record end
    end
    for steamId, record in pairs(steam) do
        if migratedLegacySteamIds[steamId] ~= true then legacySteamRecords[steamId] = record end
    end
    return true
end

local function loadPersistence()
    local jsonPath = storagePath("ServerLooks.json")
    local legacyPath = storagePath("ServerLooks.txt")
    local primaryExists = jsonPath ~= nil and fileExists(jsonPath)
    local loadedJson = primaryExists and loadJsonPersistence(jsonPath)
    if primaryExists and not loadedJson then
        -- The primary was present but unreadable/invalid and has been quarantined.
        -- Persist an empty current-version tombstone so a later restart cannot silently import
        -- an older legacy source after the corrupt primary has been moved away.
        -- If even that write fails, retire the legacy sources as migration evidence
        -- rather than leaving data that could be auto-applied on the next startup.
        if not persistLooks() then
            if legacyPath ~= nil then moveLegacyToBackup(legacyPath) end
            moveLegacyToBackup("PersistentLooks.txt")
        end
        return
    end
    if not loadedJson and legacyPath ~= nil and fileExists(legacyPath) and loadLegacyPersistence(legacyPath) then
        if persistLooks() then
            moveLegacyToBackup(legacyPath)
            loadedJson = true
        end
    end
    -- A .v1.bak file is migration evidence only. Never import it automatically:
    -- doing so after Forget, a missing current file, or corrupt-primary quarantine could
    -- resurrect state that the user explicitly deleted.
    -- Very old builds used a process-relative file. It is imported once only.
    if not loadedJson and fileExists("PersistentLooks.txt") and loadLegacyPersistence("PersistentLooks.txt") then
        if persistLooks() then
            moveLegacyToBackup("PersistentLooks.txt")
            loadedJson = true
        end
    end
end

local function prefabIdentifier(prefab)
    return prefab ~= nil and trim(userDataMember(prefab, "Identifier")) or nil
end

local function prefabName(prefab)
    return prefab ~= nil and tostring(userDataMember(prefab, "Name") or prefabIdentifier(prefab) or "") or ""
end

local function resolveItemPrefab(identifier)
    if ItemPrefab == nil then return nil end
    local prefab = nil
    pcall(function() prefab = ItemPrefab.Prefabs[identifier] end)
    if prefab ~= nil then return prefab end
    pcall(function()
        for candidate in ItemPrefab.Prefabs do
            if tostring(candidate.Identifier):lower() == tostring(identifier):lower() then prefab = candidate break end
        end
    end)
    return prefab
end

local function wearableAllowsSlot(prefab, slotKey)
    if prefab == nil or slotByKey[slotKey] == nil then return false end
    local element = userDataMember(prefab, "ConfigElement")
    if element == nil then return false end
    local wearable = nil
    pcall(function() wearable = element.GetChildElement("Wearable") end)
    if wearable == nil then return false end
    local slotText = nil
    pcall(function() slotText = tostring(wearable.GetAttributeString("slots", "Any")) end)
    if trim(slotText) == nil then
        pcall(function()
            local attribute = wearable.Element.Attribute("slots") or wearable.Element.Attribute("Slots")
            if attribute ~= nil then slotText = tostring(attribute.Value) end
        end)
    end
    slotText = trim(slotText) or "Any"
    for combination in tostring(slotText):gmatch("[^,]+") do
        for token in combination:gmatch("[^+]+") do
            local normalized = tostring(token):match("^%s*(.-)%s*$"):lower()
            if normalized == "any" or normalized == slotKey:lower() then return true end
        end
    end
    return false
end

local function itemIdentifier(item)
    return item ~= nil and item.Prefab ~= nil and trim(item.Prefab.Identifier) or nil
end

local function isIgnoredItem(item)
    local identifier = itemIdentifier(item)
    return identifier == "genesplicer" or identifier == "advancedgenesplicer"
end

local function getSlotItem(character, slot)
    if character == nil or character.Inventory == nil then return nil end
    local ok, item = pcall(function() return character.Inventory.GetItemInLimbSlot(slot) end)
    if ok then return item end
    local index = nil
    pcall(function() index = character.Inventory.FindLimbSlot(slot) end)
    if index == nil or index < 0 then return nil end
    ok, item = pcall(function() return character.Inventory.GetItemAtSlot(index) end)
    if ok then return item end
    ok, item = pcall(function() return character.Inventory.GetItemAt(index) end)
    return ok and item or nil
end

local function isInAnyWardrobeSlot(character, item)
    if character == nil or character.Inventory == nil or item == nil then return false end
    for _, entry in ipairs(slots) do
        local ok, result = pcall(function() return character.Inventory.IsInLimbSlot(item, entry.slot) end)
        if (ok and result == true) or getSlotItem(character, entry.slot) == item then return true end
    end
    return false
end

local function unequipItem(character, item)
    if character == nil or item == nil then return true end
    local function clear() return not isInAnyWardrobeSlot(character, item) end
    pcall(function() item.Unequip(character) end)
    if clear() then return true end
    if character.Inventory ~= nil and CharacterInventory ~= nil then
        local ok, moved = pcall(function()
            return character.Inventory.TryPutItem(item, character, CharacterInventory.AnySlot, true, true)
        end)
        if ok and moved == true and clear() then return true end
    end
    pcall(function() item.Unequip(character) end)
    if clear() then return true end
    pcall(function() item.Drop(character) end)
    return clear()
end

local function collectWardrobeItems(character)
    local result, byItem = {}, {}
    for _, entry in ipairs(slots) do
        local item = getSlotItem(character, entry.slot)
        if item ~= nil and not isIgnoredItem(item) then
            local snapshot = byItem[item]
            if snapshot == nil then
                snapshot = { item = item, slots = {} }
                byItem[item] = snapshot
                result[#result + 1] = snapshot
            end
            snapshot.slots[#snapshot.slots + 1] = entry.slot
        end
    end
    return result
end

local function itemOccupiesSlot(character, item, slot)
    if character == nil or character.Inventory == nil or item == nil then return false end
    local ok, result = pcall(function() return character.Inventory.IsInLimbSlot(item, slot) end)
    return (ok and result == true) or getSlotItem(character, slot) == item
end

local function restoreWardrobeItems(character, snapshots)
    local restored = true
    for _, snapshot in ipairs(snapshots or {}) do
        local alreadyRestored = true
        for _, slot in ipairs(snapshot.slots) do
            if not itemOccupiesSlot(character, snapshot.item, slot) then
                alreadyRestored = false
                break
            end
        end
        if not alreadyRestored then pcall(function() snapshot.item.Equip(character) end) end
        for _, slot in ipairs(snapshot.slots) do
            if not itemOccupiesSlot(character, snapshot.item, slot) then restored = false end
        end
    end
    return restored
end

local function canonicalSlot(identifier, slotKey)
    identifier = trim(identifier)
    if identifier == nil then return nil, "empty_identifier" end
    if byteLength(identifier) > MAX_IDENTIFIER_BYTES then return nil, "identifier_too_long" end
    local prefab = resolveItemPrefab(identifier)
    if prefab == nil then return nil, "unknown_item" end
    if not wearableAllowsSlot(prefab, slotKey) then return nil, "item_not_wearable_in_slot" end
    local canonicalIdentifier = prefabIdentifier(prefab)
    if canonicalIdentifier == nil or byteLength(canonicalIdentifier) > MAX_IDENTIFIER_BYTES then return nil, "invalid_prefab_identifier" end
    return { identifier = canonicalIdentifier, itemId = 0, name = prefabName(prefab) }
end

local function canonicalizeLook(raw, requireCaptured)
    if type(raw) ~= "table" or tonumber(raw.schemaVersion) ~= LOOK_SCHEMA_VERSION or type(raw.slots) ~= "table" then
        return nil, "invalid_look_schema"
    end
    if requireCaptured and raw.captured ~= true then return nil, "look_not_captured" end
    local attachmentVisibility, visibilityReason =
        validateAttachmentVisibility(raw.attachmentVisibility, raw.hideHair == true)
    if attachmentVisibility == nil then return nil, visibilityReason end
    local canonical = {
        schemaVersion = LOOK_SCHEMA_VERSION,
        captured = raw.captured == true,
        hideHair = legacyHideHair(attachmentVisibility),
        attachmentVisibility = attachmentVisibility,
        slots = {}
    }
    local count, payloadBytes = 0, 16
    for key, rawSlot in pairs(raw.slots) do
        if type(key) ~= "string" or slotByKey[key] == nil then return nil, "unknown_slot" end
        count = count + 1
        if count > MAX_SLOTS then return nil, "too_many_slots" end
        local identifier = type(rawSlot) == "table" and rawSlot.identifier or rawSlot
        if type(identifier) ~= "string" then return nil, "invalid_identifier" end
        payloadBytes = payloadBytes + byteLength(key) + byteLength(identifier) + 4
        if payloadBytes > MAX_PAYLOAD_BYTES then return nil, "payload_too_large" end
        local slot, reason = canonicalSlot(identifier, key)
        if slot == nil then return nil, reason .. ":" .. key end
        canonical.slots[key] = slot
    end
    return canonical
end

local function captureAuthoritativeLook(character, clientLook)
    if character == nil then return nil, "character_unavailable" end
    local attachmentVisibility, visibilityReason = validateAttachmentVisibility(
        type(clientLook) == "table" and clientLook.attachmentVisibility or nil,
        type(clientLook) == "table" and clientLook.hideHair == true
    )
    if attachmentVisibility == nil then return nil, visibilityReason end
    local raw = {
        schemaVersion = LOOK_SCHEMA_VERSION,
        captured = true,
        hideHair = legacyHideHair(attachmentVisibility),
        attachmentVisibility = attachmentVisibility,
        slots = {}
    }
    for _, entry in ipairs(slots) do
        local item = getSlotItem(character, entry.slot)
        if item ~= nil and not isIgnoredItem(item) then
            local identifier = itemIdentifier(item)
            if identifier ~= nil then raw.slots[entry.key] = identifier end
        end
    end
    return canonicalizeLook(raw, true)
end

local function readCoreLook(message)
    if Core ~= nil and Core.readLook ~= nil then
        local look, reason = Core.readLook(message)
        if look == nil then error(reason or "invalid_look") end
        return look
    end
    if Core ~= nil and Core.ReadLook ~= nil then
        local look, reason = Core.ReadLook(message)
        if look == nil then error(reason or "invalid_look") end
        return look
    end
    local look = {
        schemaVersion = tonumber(message.ReadUInt16()),
        captured = message.ReadBoolean() == true,
        hideHair = message.ReadBoolean() == true,
        attachmentVisibility = nil,
        slots = {}
    }
    local count = tonumber(message.ReadUInt16()) or 0
    if count > MAX_SLOTS then error("too_many_slots") end
    for _ = 1, count do
        local key = tostring(message.ReadString() or "")
        local identifier = tostring(message.ReadString() or "")
        if look.slots[key] ~= nil then error("duplicate_slot") end
        look.slots[key] = identifier
    end
    return look
end

local function writeCoreLook(message, look)
    local attachmentVisibility = copyAttachmentVisibility(
        look ~= nil and look.attachmentVisibility or nil,
        look ~= nil and look.hideHair == true
    )
    local wireLook = {
        schemaVersion = LOOK_SCHEMA_VERSION,
        captured = look ~= nil and look.captured == true,
        hideHair = legacyHideHair(attachmentVisibility),
        attachmentVisibility = attachmentVisibility,
        slots = {}
    }
    for _, entry in ipairs(slots) do
        local slot = look ~= nil and look.slots ~= nil and look.slots[entry.key] or nil
        if slot ~= nil then wireLook.slots[entry.key] = type(slot) == "table" and slot.identifier or tostring(slot) end
    end
    if Core ~= nil and Core.writeLook ~= nil then Core.writeLook(message, wireLook) return end
    if Core ~= nil and Core.WriteLook ~= nil then Core.WriteLook(message, wireLook) return end
    message.WriteUInt16(LOOK_SCHEMA_VERSION)
    message.WriteBoolean(wireLook.captured)
    message.WriteBoolean(wireLook.hideHair)
    local count = 0
    for _, entry in ipairs(slots) do if wireLook.slots[entry.key] ~= nil then count = count + 1 end end
    message.WriteUInt16(count)
    for _, entry in ipairs(slots) do
        local identifier = wireLook.slots[entry.key]
        if identifier ~= nil then message.WriteString(entry.key) message.WriteString(identifier) end
    end
    if SUPPORTS_ATTACHMENT_VISIBILITY then
        local forceHide, forceShow = attachmentVisibilityMasks(wireLook.attachmentVisibility)
        message.WriteByte(0x57)
        message.WriteByte(1)
        message.WriteByte(forceHide)
        message.WriteByte(forceShow)
    end
end

local function writeLegacyLook(message, characterId, look)
    message.WriteUInt16(characterId or 0)
    for _, entry in ipairs(slots) do
        local slot = look ~= nil and look.slots ~= nil and look.slots[entry.key] or nil
        message.WriteBoolean(slot ~= nil)
        if slot ~= nil then
            message.WriteUInt16(0)
            message.WriteString(tostring(slot.identifier or ""))
            message.WriteString(tostring(slot.name or ""))
        end
    end
end

local function sessionRecord(session)
    return session ~= nil and session.accountId ~= nil and persistentRecords[session.accountId] or nil
end

local function migrateLegacyForClient(client, accountId)
    local steamId = steamIdForClient(client)
    if accountId == nil or steamId == nil or migratedLegacySteamIds[steamId] == true then return end
    local legacy = legacySteamRecords[steamId]
    if legacy == nil then return end
    if persistentRecords[accountId] == nil then persistentRecords[accountId] = legacy end
    legacySteamRecords[steamId] = nil
    migratedLegacySteamIds[steamId] = true
    persistLooks()
    log("Migrated a legacy Steam wardrobe record to Client.AccountId.")
end

-- v2 retries reuse operation IDs. Retaining the first result per account/session
-- makes repeated packets idempotent even if the connection object is replaced.
local function newOperationCache(clientSessionId)
    return {
        clientSessionId = clientSessionId,
        results = {},
        count = 0,
        limitResult = nil
    }
end

local function bindOperationCache(session, clientSessionId)
    if session == nil then return end
    clientSessionId = tostring(clientSessionId or "")
    local cache = nil
    if session.accountId ~= nil then
        local retained = operationCachesByAccount[session.accountId]
        if retained ~= nil and retained.clientSessionId == clientSessionId then
            cache = retained
        else
            cache = newOperationCache(clientSessionId)
            operationCachesByAccount[session.accountId] = cache
        end
    elseif session.clientSessionId == clientSessionId and session.operationCache ~= nil then
        cache = session.operationCache
    else
        cache = newOperationCache(clientSessionId)
    end
    session.clientSessionId = clientSessionId
    session.operationCache = cache
    -- Keep this field in the ClientWardrobeSession aggregate while the cache
    -- metadata enforces a hard memory bound.
    session.seenOperations = cache.results
end

local function sessionFor(client)
    if client == nil then return nil end
    local existing = sessionsByClient[client]
    if existing ~= nil then return existing end
    local accountId = accountIdForClient(client)
    migrateLegacyForClient(client, accountId)
    local record = accountId ~= nil and persistentRecords[accountId] or nil
    local recordLook = nil
    if record ~= nil then
        local reason
        recordLook, reason = canonicalizeLook(record.savedLook, true)
        if recordLook == nil then
            warn("Ignored an invalid stored wardrobe for account " .. tostring(accountId) .. ": " .. tostring(reason))
            record.active = false
        else
            record.savedLook = cloneLook(recordLook)
        end
    end
    local initialOperationCache = newOperationCache(nil)
    local session = {
        client = client,
        serverSessionId = serverSessionId,
        accountId = accountId,
        -- Capability is unknown until this connection either completes the v2
        -- hello or sends one of the legacy commands. Treating a fresh connection
        -- as v1 would race the client's hello and force an immediate downgrade.
        protocol = 0,
        clientSessionId = nil,
        revision = record ~= nil and (tonumber(record.revision) or 0) or 0,
        savedLook = cloneLook(recordLook),
        active = recordLook ~= nil and record.active == true and record.sessionKey ~= nil and record.sessionKey == currentGameSessionKey(),
        activeCharacterId = nil,
        seenOperations = initialOperationCache.results,
        operationCache = initialOperationCache
    }
    sessionsByClient[client] = session
    return session
end

local function updatePersistentRecord(session)
    if session == nil or session.accountId == nil then return end
    if session.savedLook == nil then
        persistentRecords[session.accountId] = nil
        return
    end
    persistentRecords[session.accountId] = {
        revision = session.revision,
        savedLook = cloneLook(session.savedLook),
        active = session.active == true,
        sessionKey = currentGameSessionKey()
    }
end

local function clonePersistentRecord(record)
    if record == nil then return nil end
    return {
        revision = tonumber(record.revision) or 0,
        savedLook = cloneLook(record.savedLook),
        active = record.active == true,
        sessionKey = record.sessionKey
    }
end

local function snapshotCommitState(session)
    return {
        revision = session.revision,
        savedLook = cloneLook(session.savedLook),
        active = session.active == true,
        activeCharacterId = session.activeCharacterId,
        persistentRecord = session.accountId ~= nil and clonePersistentRecord(persistentRecords[session.accountId]) or nil
    }
end

local function restoreCommitState(session, snapshot)
    session.revision = snapshot.revision
    session.savedLook = cloneLook(snapshot.savedLook)
    session.active = snapshot.active == true
    session.activeCharacterId = snapshot.activeCharacterId
    if session.accountId ~= nil then
        persistentRecords[session.accountId] = clonePersistentRecord(snapshot.persistentRecord)
    end
end

local function persistStableSessionOrRollback(session, snapshot)
    if session.accountId == nil then return true end
    updatePersistentRecord(session)
    if persistLooks() then return true end
    restoreCommitState(session, snapshot)
    return false
end

local function sendV2Ack(session, operationId, accepted, reason, revision)
    if session == nil or session.client == nil or session.client.Connection == nil then return end
    local message = Networking.Start(NET.V2_ACK)
    if Core ~= nil and Core.writeAck ~= nil then
        local written, writeReason = Core.writeAck(message, {
            operationId = operationId or "",
            accepted = accepted == true,
            revision = math.max(0, tonumber(revision) or session.revision or 0),
            reason = reason or ""
        })
        if not written then warn("Could not encode v2 acknowledgement: " .. tostring(writeReason)) return end
    else
        message.WriteUInt16(PROTOCOL_VERSION)
        message.WriteString(operationId or "")
        message.WriteBoolean(accepted == true)
        message.WriteUInt32(math.max(0, tonumber(revision) or session.revision or 0))
        message.WriteString(reason or "")
    end
    Networking.Send(message, session.client.Connection)
end

local function sendV2State(client, revision, characterId, active, look)
    if client == nil or client.Connection == nil then return end
    local message = Networking.Start(NET.V2_STATE)
    if Core ~= nil and Core.writeState ~= nil then
        local written, writeReason = Core.writeState(message, {
            revision = math.max(0, tonumber(revision) or 0),
            characterId = math.max(0, tonumber(characterId) or 0),
            active = active == true,
            look = look
        })
        if not written then warn("Could not encode v2 state: " .. tostring(writeReason)) return end
    else
        message.WriteUInt16(PROTOCOL_VERSION)
        message.WriteUInt32(math.max(0, tonumber(revision) or 0))
        message.WriteUInt16(math.max(0, tonumber(characterId) or 0))
        message.WriteBoolean(active == true)
        message.WriteBoolean(look ~= nil)
        if look ~= nil then writeCoreLook(message, look) end
    end
    Networking.Send(message, client.Connection)
end

local function sendLegacyState(client, characterId, active, look)
    if client == nil or client.Connection == nil then return end
    if active then
        local message = Networking.Start(NET.LOOK_APPLY)
        writeLegacyLook(message, characterId, look)
        Networking.Send(message, client.Connection)
    else
        local message = Networking.Start(NET.LOOK_CLEAR)
        message.WriteUInt16(characterId or 0)
        Networking.Send(message, client.Connection)
    end
end

local function sendStateTo(client, revision, characterId, active, look)
    local recipient = sessionFor(client)
    if recipient ~= nil and recipient.protocol == 2 then
        sendV2State(client, revision, characterId, active, look)
    elseif recipient ~= nil and recipient.protocol == 1 then
        sendLegacyState(client, characterId, active, look)
    end
end

local function broadcastState(revision, characterId, active, look)
    if tonumber(characterId) == nil or tonumber(characterId) <= 0 then return end
    for _, client in ipairs(connectedClients()) do sendStateTo(client, revision, characterId, active, look) end
end

local function sendActiveSnapshot(client)
    for characterId, active in pairs(activeByCharacterId) do
        sendStateTo(client, active.revision, characterId, true, active.look)
    end
end

local function sendOwnInactiveState(session)
    if session == nil or session.protocol ~= 2 or session.savedLook == nil or session.active or session.activeCharacterId ~= nil then return end
    local characterId = characterEntityId(clientCharacter(session.client))
    if characterId <= 0 then return end
    sendV2State(session.client, session.revision, characterId, false, session.savedLook)
end

local function clearActiveRuntime(session, shouldBroadcast)
    if session == nil then return nil end
    local characterId = tonumber(session.activeCharacterId)
    session.active = false
    session.activeCharacterId = nil
    if characterId ~= nil and characterId > 0 then
        local active = activeByCharacterId[characterId]
        if active == nil or active.session == session then activeByCharacterId[characterId] = nil end
        if shouldBroadcast then broadcastState(session.revision, characterId, false, nil) end
    end
    return characterId
end

local function activateRuntime(session, character, look)
    local characterId = characterEntityId(character)
    if session == nil or characterId <= 0 or look == nil then return false end
    if session.activeCharacterId ~= nil and tonumber(session.activeCharacterId) ~= characterId then
        clearActiveRuntime(session, true)
    end
    local previous = activeByCharacterId[characterId]
    if previous ~= nil and previous.session ~= session then
        previous.session.active = false
        previous.session.activeCharacterId = nil
    end
    session.active = true
    session.activeCharacterId = characterId
    activeByCharacterId[characterId] = {
        session = session,
        revision = session.revision,
        look = cloneLook(look)
    }
    broadcastState(session.revision, characterId, true, look)
    return true
end

local function operationResultFor(session, operationId)
    local cache = session.operationCache
    if cache == nil then
        cache = newOperationCache(session.clientSessionId)
        session.operationCache = cache
        session.seenOperations = cache.results
    end
    local result = cache.results[operationId]
    if result ~= nil then return result end
    if cache.count >= MAX_SEEN_OPERATIONS then
        if cache.limitResult == nil then
            cache.limitResult = {
                accepted = false,
                reason = "operation_limit_reached",
                revision = session.revision
            }
        end
        return cache.limitResult
    end
    return nil
end

local function rememberOperation(session, operationId, accepted, reason)
    local existing = operationResultFor(session, operationId)
    if existing ~= nil then return existing end
    local result = { accepted = accepted == true, reason = reason, revision = session.revision }
    local cache = session.operationCache
    cache.results[operationId] = result
    cache.count = cache.count + 1
    return result
end

local function canAdvanceRevision(session)
    local revision = math.max(0, tonumber(session.revision) or 0)
    return revision < MAX_REVISION
end

local function nextRevision(session)
    if not canAdvanceRevision(session) then return false end
    session.revision = math.max(0, tonumber(session.revision) or 0) + 1
    return true
end

local function commitSave(session, character, clientLook)
    if not canAdvanceRevision(session) then return false, "revision_exhausted" end
    local look, reason = captureAuthoritativeLook(character, clientLook)
    if look == nil then return false, reason end

    -- Treat equipment removal as part of the command transaction. Do not advance
    -- the revision, persist, or broadcast unless every captured item left all
    -- managed slots. Best-effort re-equip restores already removed items when a
    -- later item fails, including persistence failures after removal.
    local itemSnapshots = collectWardrobeItems(character)
    local removed = 0
    for _, snapshot in ipairs(itemSnapshots) do
        if not unequipItem(character, snapshot.item) then
            local restored = restoreWardrobeItems(character, itemSnapshots)
            return false, restored and "unequip_failed" or "unequip_rollback_failed"
        end
        removed = removed + 1
    end

    local previous = snapshotCommitState(session)
    nextRevision(session)
    session.savedLook = look
    session.active = false
    if not persistStableSessionOrRollback(session, previous) then
        local restored = restoreWardrobeItems(character, itemSnapshots)
        return false, restored and "persistence_failed" or "persistence_failed_equipment_rollback_failed"
    end
    clearActiveRuntime(session, true)
    if session.protocol == 2 then
        -- SAVE is intentionally inactive. Send the canonical server capture so
        -- the v2 client can leave ApplyPending even when there was no prior
        -- active character state to clear.
        sendV2State(session.client, session.revision, characterEntityId(character), false, look)
    end
    log("Saved authoritative wardrobe for " .. tostring(character.Name) .. "; removed " .. tostring(removed) .. " item(s).")
    return true, "ok"
end

local function commitApply(session, character, look)
    if not canAdvanceRevision(session) then return false, "revision_exhausted" end
    if look == nil then return false, "look_unavailable" end
    if characterEntityId(character) <= 0 then return false, "character_unavailable" end
    local previous = snapshotCommitState(session)
    nextRevision(session)
    session.savedLook = cloneLook(look)
    session.active = true
    if not persistStableSessionOrRollback(session, previous) then return false, "persistence_failed" end
    if not activateRuntime(session, character, look) then
        restoreCommitState(session, previous)
        if session.accountId ~= nil and not persistLooks() then
            warn("Could not roll back persisted wardrobe after activation failure.")
        end
        return false, "character_unavailable"
    end
    return true, "ok"
end

local function commitVisibility(session, requestedLook)
    if not canAdvanceRevision(session) then return false, "revision_exhausted" end
    if session.savedLook == nil then return false, "look_unavailable" end
    if type(requestedLook) ~= "table" then return false, "visibility_unavailable" end
    local attachmentVisibility, visibilityReason =
        validateAttachmentVisibility(requestedLook.attachmentVisibility, requestedLook.hideHair == true)
    if attachmentVisibility == nil then return false, visibilityReason or "invalid_attachment_visibility" end

    -- Only merge the visibility policy into the authoritative server capture.
    -- Client-supplied slots are deliberately ignored so this command cannot be
    -- used to replace or smuggle equipment identifiers.
    local merged = cloneLook(session.savedLook)
    merged.attachmentVisibility = copyAttachmentVisibility(attachmentVisibility, false)
    merged.hideHair = legacyHideHair(merged.attachmentVisibility)

    local previous = snapshotCommitState(session)
    nextRevision(session)
    session.savedLook = merged
    if not persistStableSessionOrRollback(session, previous) then return false, "persistence_failed" end

    local characterId = tonumber(session.activeCharacterId)
    if session.active == true and characterId ~= nil and characterId > 0 then
        activeByCharacterId[characterId] = {
            session = session,
            revision = session.revision,
            look = cloneLook(merged)
        }
        broadcastState(session.revision, characterId, true, merged)
    else
        sendOwnInactiveState(session)
    end
    return true, "ok"
end

local function commitClear(session, deleteSaved)
    if not canAdvanceRevision(session) then return false, "revision_exhausted" end
    local previous = snapshotCommitState(session)
    nextRevision(session)
    session.active = false
    if deleteSaved then session.savedLook = nil end
    if not persistStableSessionOrRollback(session, previous) then return false, "persistence_failed" end
    clearActiveRuntime(session, true)
    return true, "ok"
end

-- Decode and envelope validation stay separate so a request whose operation ID
-- was readable can still receive a deterministic, correlated rejection ACK.
-- Truly truncated packets fail before such a response is possible.
local function parseV2Command(message)
    local command = {
        version = tonumber(message.ReadUInt16()),
        clientSessionId = tostring(message.ReadString() or ""),
        operationId = tostring(message.ReadString() or ""),
        baseRevision = tonumber(message.ReadUInt32()),
        kind = tostring(message.ReadString() or ""):lower(),
        hasLook = message.ReadBoolean() == true,
        look = nil
    }
    if command.hasLook then
        local ok, lookOrError, readReason = pcall(readCoreLook, message)
        if ok and lookOrError ~= nil then
            command.look = lookOrError
        else
            command.parseError = tostring(ok and (readReason or "invalid_look") or lookOrError)
        end
    end
    return command
end

local validCommandKinds = {
    save = true,
    apply = true,
    clear = true,
    forget = true
}
if SUPPORTS_ATTACHMENT_VISIBILITY then
    validCommandKinds[COMMAND_VISIBILITY] = true
end

local function validateV2Envelope(command)
    if type(command) ~= "table" or command.version ~= PROTOCOL_VERSION then return false, "unsupported_protocol" end
    if byteLength(command.clientSessionId) == 0 or byteLength(command.clientSessionId) > MAX_SESSION_ID_BYTES then
        return false, "invalid_client_session"
    end
    if byteLength(command.operationId) == 0 or byteLength(command.operationId) > MAX_OPERATION_ID_BYTES then
        return false, "invalid_operation_id"
    end
    if command.baseRevision == nil or command.baseRevision < 0 then return false, "invalid_revision" end
    if validCommandKinds[command.kind] ~= true then return false, "unknown_command" end
    if command.parseError ~= nil then return false, "malformed_look" end
    local envelopeBytes = 16 + byteLength(command.clientSessionId) + byteLength(command.operationId) + byteLength(command.kind)
    if envelopeBytes > MAX_PAYLOAD_BYTES then return false, "payload_too_large" end
    if (command.kind == "clear" or command.kind == "forget") and command.hasLook then return false, "unexpected_look" end
    if command.kind == COMMAND_VISIBILITY and not command.hasLook then return false, "missing_look" end
    return true
end

local function resendCurrentState(session)
    if session.active and session.activeCharacterId ~= nil then
        sendV2State(session.client, session.revision, session.activeCharacterId, true, session.savedLook)
    else
        sendOwnInactiveState(session)
    end
end

Networking.Receive(NET.V2_HELLO, function(message, client)
    local ok, hello, helloReason = pcall(function()
        if Core ~= nil and Core.readClientHello ~= nil then return Core.readClientHello(message) end
        local version = tonumber(message.ReadUInt16())
        local clientSessionId = tostring(message.ReadString() or "")
        if version ~= PROTOCOL_VERSION then return nil, "unsupported_protocol" end
        return { protocolVersion = version, clientSessionId = clientSessionId }
    end)
    if not ok or hello == nil then
        warn("Rejected malformed v2 hello: " .. tostring(ok and helloReason or hello))
        return
    end
    local clientSessionId = tostring(hello.clientSessionId or "")
    if byteLength(clientSessionId) == 0 or byteLength(clientSessionId) > MAX_SESSION_ID_BYTES then return end
    local session = sessionFor(client)
    if session == nil then return end
    session.protocol = 2
    bindOperationCache(session, clientSessionId)
    local response = Networking.Start(NET.V2_HELLO)
    local advertisedCapabilities =
        SUPPORTS_ATTACHMENT_VISIBILITY and CAPABILITY_ATTACHMENT_VISIBILITY or 0
    if Core ~= nil and Core.writeServerHello ~= nil then
        local written, writeReason = Core.writeServerHello(
            response,
            math.max(0, session.revision),
            advertisedCapabilities
        )
        if not written then warn("Could not encode v2 hello response: " .. tostring(writeReason)) return end
    else
        response.WriteUInt16(PROTOCOL_VERSION)
        response.WriteUInt32(math.max(0, session.revision))
        if advertisedCapabilities ~= 0 then
            response.WriteByte(0x57)
            response.WriteByte(1)
            response.WriteByte(advertisedCapabilities)
        end
    end
    Networking.Send(response, client.Connection)
    sendActiveSnapshot(client)
    sendOwnInactiveState(session)
end)

Networking.Receive(NET.V2_COMMAND, function(message, client)
    local session = sessionFor(client)
    if session == nil then return end
    local wireBytes = messageLengthBytes(message)
    if wireBytes ~= nil and wireBytes > MAX_PAYLOAD_BYTES then
        warn("Rejected an oversized v2 command before decoding (" .. tostring(wireBytes) .. " bytes).")
        return
    end
    local ok, command = pcall(parseV2Command, message)
    if not ok then
        warn("Rejected a truncated v2 command before its operation ID could be authenticated.")
        return
    end
    session.protocol = 2
    local envelopeOk, envelopeReason = validateV2Envelope(command)
    if not envelopeOk then
        sendV2Ack(session, command.operationId, false, envelopeReason, session.revision)
        return
    end
    if session.clientSessionId ~= command.clientSessionId then
        bindOperationCache(session, command.clientSessionId)
    end
    local duplicate = operationResultFor(session, command.operationId)
    if duplicate ~= nil then
        sendV2Ack(session, command.operationId, duplicate.accepted, duplicate.reason, duplicate.revision)
        if duplicate.accepted then resendCurrentState(session) end
        return
    end
    if command.baseRevision ~= session.revision then
        local result = rememberOperation(session, command.operationId, false, "stale_revision")
        sendV2Ack(session, command.operationId, false, result.reason, result.revision)
        return
    end

    local character = clientCharacter(client)
    local accepted, reason = false, "character_unavailable"
    if command.kind == "save" then
        if character ~= nil then accepted, reason = commitSave(session, character, command.look) end
    elseif command.kind == "apply" then
        local look = nil
        if command.hasLook then look, reason = canonicalizeLook(command.look, true) else look = cloneLook(session.savedLook) end
        if character ~= nil and look ~= nil then accepted, reason = commitApply(session, character, look)
        elseif look == nil and reason == nil then reason = "look_unavailable" end
    elseif command.kind == COMMAND_VISIBILITY then
        accepted, reason = commitVisibility(session, command.look)
    elseif command.kind == "clear" then
        accepted, reason = commitClear(session, false)
    elseif command.kind == "forget" then
        accepted, reason = commitClear(session, true)
    end
    local result = rememberOperation(session, command.operationId, accepted, reason)
    sendV2Ack(session, command.operationId, result.accepted, result.reason, result.revision)
end)

local function readLegacyApplyLook(message)
    local ok, supplied, look, payloadBytes = pcall(function()
        local hasLook = message.ReadBoolean() == true
        if not hasLook then return false, nil, 1 end
        local raw = {
            schemaVersion = LOOK_SCHEMA_VERSION,
            captured = true,
            hideHair = false,
            attachmentVisibility = attachmentVisibilityFromLegacy(false),
            slots = {}
        }
        local bytes = 1
        for _, entry in ipairs(slots) do
            if message.ReadBoolean() then
                message.ReadUInt16() -- Untrusted runtime item ID: intentionally discarded.
                local identifier = tostring(message.ReadString() or "")
                local displayName = tostring(message.ReadString() or "") -- Intentionally discarded.
                bytes = bytes + byteLength(identifier) + byteLength(displayName) + 8
                raw.slots[entry.key] = identifier
            end
        end
        return true, raw, bytes
    end)
    if not ok then return false, nil, 0 end -- Old pre-payload clients fall back to the stored look.
    if payloadBytes > MAX_PAYLOAD_BYTES then return true, nil, payloadBytes end
    return supplied, look, payloadBytes
end

local function selectLegacyProtocol(session)
    if session == nil then return false end
    if session.protocol == 2 then
        warn("Ignored a legacy wardrobe command after this connection negotiated protocol v2.")
        return false
    end
    session.protocol = 1
    return true
end

Networking.Receive(NET.SAVE_REQUEST, function(_, client)
    local session = sessionFor(client)
    local character = clientCharacter(client)
    if session == nil or character == nil then return end
    if not selectLegacyProtocol(session) then return end
    commitSave(session, character, nil)
end)

Networking.Receive(NET.APPLY_REQUEST, function(message, client)
    local session = sessionFor(client)
    local character = clientCharacter(client)
    if session == nil or character == nil then return end
    if not selectLegacyProtocol(session) then return end
    local wireBytes = messageLengthBytes(message)
    if wireBytes ~= nil and wireBytes > MAX_PAYLOAD_BYTES then
        warn("Rejected oversized v1 apply payload (" .. tostring(wireBytes) .. " bytes).")
        return
    end
    local supplied, raw, bytes = readLegacyApplyLook(message)
    if bytes > MAX_PAYLOAD_BYTES then warn("Rejected oversized v1 apply payload.") return end
    local look, reason
    if supplied then
        if raw == nil then warn("Rejected malformed v1 apply payload.") return end
        look, reason = canonicalizeLook(raw, true)
    else
        look = cloneLook(session.savedLook)
    end
    if look == nil then
        if reason ~= nil then warn("Rejected v1 apply payload: " .. tostring(reason)) end
        return
    end
    commitApply(session, character, look)
end)

Networking.Receive(NET.CLEAR_REQUEST, function(_, client)
    local session = sessionFor(client)
    if session == nil then return end
    if not selectLegacyProtocol(session) then return end
    commitClear(session, false)
end)

Networking.Receive(NET.FORGET_REQUEST, function(_, client)
    local session = sessionFor(client)
    if session == nil then return end
    if not selectLegacyProtocol(session) then return end
    commitClear(session, true)
end)

local function clearRoundRuntime()
    activeByCharacterId = {}
    for _, session in pairs(sessionsByClient) do session.activeCharacterId = nil end
end

local function handleGameSessionChange()
    local key = currentGameSessionKey()
    if key == nil then return end
    if lastGameSessionKey == nil then lastGameSessionKey = key return end
    if key == lastGameSessionKey then return end
    lastGameSessionKey = key
    clearRoundRuntime()
    for _, record in pairs(persistentRecords) do record.active = false end
    for _, session in pairs(sessionsByClient) do
        if session.active and not nextRevision(session) then
            warn("Revision exhausted while deactivating a session at a campaign/session boundary.")
        end
        session.active = false
        updatePersistentRecord(session)
    end
    persistLooks()
    log("Detected a new campaign/session; deactivated persisted wardrobe looks.")
end

local function reactivateSession(session)
    if session == nil or not session.active or session.savedLook == nil then return end
    local character = clientCharacter(session.client)
    if character == nil or characterEntityId(character) <= 0 then return end
    activateRuntime(session, character, session.savedLook)
end

local function rebindCreatedCharacter(character)
    if character == nil or characterEntityId(character) <= 0 then return false end
    for _, client in ipairs(connectedClients()) do
        if clientCharacter(client) == character then
            local session = sessionFor(client)
            if session ~= nil and session.active and session.savedLook ~= nil and
                tonumber(session.activeCharacterId) ~= characterEntityId(character) then
                activateRuntime(session, character, session.savedLook)
            end
            return true
        end
    end
    return false
end

Hook.Add("client.connected", "barowardrobeswitcher.v2-connected", function(client)
    handleGameSessionChange()
    local session = sessionFor(client)
    reactivateSession(session)

    -- Old clients have no hello message. Give a v2-capable client the full
    -- negotiation window before selecting the bridge, then send one targeted
    -- v1 snapshot. This is a one-shot timer, not steady-state traffic.
    if Timer ~= nil and Timer.Wait ~= nil then
        Timer.Wait(function()
            if sessionsByClient[client] ~= session or session == nil or session.protocol ~= 0 then return end
            session.protocol = 1
            sendActiveSnapshot(client)
        end, 5000)
    end
end)

Hook.Add("client.disconnected", "barowardrobeswitcher.v2-disconnected", function(client)
    local session = sessionsByClient[client]
    if session == nil then return end
    local wasActive = session.active == true
    clearActiveRuntime(session, true)
    -- Preserve the active intent for a stable account so reconnect/round start
    -- can assign the look to the new Character entity ID.
    local record = sessionRecord(session)
    if record ~= nil then record.active = wasActive end
    sessionsByClient[client] = nil
end)

Hook.Add("character.created", "barowardrobeswitcher.v2-character-created", function(character)
    -- LuaCs may raise character.created just before Client.Character is assigned.
    -- Retry a bounded number of times from this event; never install a frame scan.
    local attempts = 0
    local function attemptRebind()
        attempts = attempts + 1
        if rebindCreatedCharacter(character) or attempts >= 3 then return end
        if Timer ~= nil and Timer.Wait ~= nil then
            Timer.Wait(attemptRebind, attempts == 1 and 100 or 500)
        end
    end
    attemptRebind()
end)

Hook.Add("roundStart", "barowardrobeswitcher.v2-round-start", function()
    handleGameSessionChange()
    clearRoundRuntime()
    for _, client in ipairs(connectedClients()) do reactivateSession(sessionFor(client)) end
end)

Hook.Add("roundEnd", "barowardrobeswitcher.v2-round-end", function()
    clearRoundRuntime()
end)

loadPersistence()
lastGameSessionKey = currentGameSessionKey()
log("Server authority v0.5.1 loaded (protocol 2, look schema 2, persistence 3). Path: " ..
    tostring(storagePath("ServerLooks.json")))
