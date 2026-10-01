-- 編輯導覽：多人命令入口是 handleV2Command，實際修改集中在 commitSave／Apply／Clear。
-- 伺服器以自己的裝備與 prefab 資料驗證請求；此檔不依賴客戶端 C# 渲染器。
local MOD_NAME = "Baro Wardrobe Switcher"

if not SERVER then return end

local Core = assert(
    type(WardrobeCore) == "table" and
    tonumber(WardrobeCore.PROTOCOL_VERSION) == 5 and
    type(WardrobeCore.NET) == "table" and
    WardrobeCore,
    "Baro Wardrobe Switcher requires WardrobeCore protocol 5")
local NET = Core.NET
local PROTOCOL_VERSION = Core.PROTOCOL_VERSION
local LOOK_SCHEMA_VERSION = Core.LOOK_SCHEMA_VERSION
local PERSISTENCE_VERSION = Core.PERSISTENCE_VERSION
local MAX_SLOTS = Core.LIMITS.MAX_SLOTS
local MAX_IDENTIFIER_BYTES = Core.LIMITS.MAX_IDENTIFIER_BYTES
local MAX_PAYLOAD_BYTES = Core.LIMITS.MAX_PAYLOAD_BYTES
local MAX_SESSION_ID_BYTES = Core.LIMITS.MAX_SESSION_ID_BYTES
local MAX_OPERATION_ID_BYTES = Core.LIMITS.MAX_OPERATION_ID_BYTES
local MAX_SEEN_OPERATIONS = Core.LIMITS.MAX_SEEN_OPERATIONS
local MAX_REVISION = Core.LIMITS.MAX_UINT32
local ATTACHMENT_KEYS = Core.ATTACHMENT_KEYS
local CAPABILITY_ATTACHMENT_VISIBILITY = Core.CAPABILITY.AttachmentVisibility
local CAPABILITY_MOVEMENT_ANIMATION_SOURCE = Core.CAPABILITY.MovementAnimationSource
local CAPABILITY_CREW_TARGETING = Core.CAPABILITY.CrewTargeting
local CAPABILITY_FOOTSTEP_SOUND_SOURCE = Core.CAPABILITY.FootstepSoundSource
local CAPABILITY_CREW_DIVING_PROFILES = Core.CAPABILITY.CrewDivingProfiles
local CAPABILITY_SAVE_WITHOUT_UNEQUIP = Core.CAPABILITY.SaveWithoutUnequip
local COMMAND_SAVE_KEEP = Core.COMMAND.SaveKeep
local COMMAND_VISIBILITY = Core.COMMAND.Visibility
local COMMAND_ANIMATION = Core.COMMAND.Animation
local COMMAND_FOOTSTEP = Core.COMMAND.Footstep

local CharacterInventory = nil
local Client = nil
local GameMain = nil
local GameApi = rawget(_G, "Game")
local ItemPrefab = nil
local File = rawget(_G, "File")
pcall(function() CharacterInventory = LuaUserData.CreateStatic("Barotrauma.CharacterInventory", true) end)
pcall(function() Client = LuaUserData.CreateStatic("Barotrauma.Networking.Client", true) end)
pcall(function() GameMain = LuaUserData.CreateStatic("Barotrauma.GameMain", true) end)
pcall(function() ItemPrefab = LuaUserData.CreateStatic("Barotrauma.ItemPrefab", true) end)

-- 裝備欄位須與 Core.SLOT_KEYS 及客戶端 slots 對應，避免單人可用、多人卻被拒絕。
local slots = {
    { key = "Head", slot = InvSlotType.Head },
    { key = "Headset", slot = InvSlotType.Headset },
    { key = "InnerClothes", slot = InvSlotType.InnerClothes },
    { key = "OuterClothes", slot = InvSlotType.OuterClothes },
    { key = "Bag", slot = InvSlotType.Bag },
    { key = "HealthInterface", slot = InvSlotType.HealthInterface, optional = true }
}
local slotByKey = {}
for _, entry in ipairs(slots) do slotByKey[entry.key] = entry end

-- persistent* 保存可持久化紀錄；sessions／activeByCharacterId 管理目前連線與實體。
-- 角色實體 ID 會隨場景更換，不應拿來當跨場景存檔的身分鍵。
local persistentRecords = {}
local persistentCrewRecords = {}
local legacySteamRecords = {}
local migratedLegacySteamIds = {}
local sessionsByClient = setmetatable({}, { __mode = "k" })
local operationCachesByAccount = {}
local activeByCharacterId = {}
local crewRuntimeSession = { revision = 0 }
local observerRevisionByCharacterId = {}
local serverSessionId = tostring(os.time()) .. "-" .. tostring(math.random(100000, 999999))
local lastGameSessionKey = nil
local roundReactivationGeneration = 0
-- 重試結果快取的保留時間（秒）與帳號數上限；同一連線的操作數上限另在 Core.LIMITS。
local OPERATION_CACHE_RETENTION_SECONDS = 120
local MAX_RETAINED_OPERATION_ACCOUNTS = 64
local CREW_PERSISTENCE_VERSION = 2
local SERVER_LOG_MAX_BYTES = 65536
local SERVER_LOG_MAX_WRITES_PER_SECOND = 20
local serverLogWindowSecond = nil
local serverLogWritesInWindow = 0

local function writeLog(level, message)
    local line = "[" .. MOD_NAME .. "] " .. tostring(message)
    local written = false
    local writeFailure = nil
    if File ~= nil and GameApi ~= nil then
        written, writeFailure = pcall(function()
            local now = math.floor(tonumber(os.time()) or 0)
            if serverLogWindowSecond ~= now then
                serverLogWindowSecond = now
                serverLogWritesInWindow = 0
            end
            if serverLogWritesInWindow >= SERVER_LOG_MAX_WRITES_PER_SECOND then return end
            serverLogWritesInWindow = serverLogWritesInWindow + 1
            local root = GameApi.SaveFolder
            if root == nil or tostring(root) == "" then error("Game.SaveFolder unavailable") end
            local directory = tostring(root):gsub("\\", "/"):gsub("/$", "") ..
                "/ModData/BaroWardrobeSwitcher"
            File.CreateDirectory(directory)
            local path = directory .. "/WardrobeServer.log"
            local entry = "[" .. os.date("%Y-%m-%d %H:%M:%S") .. "] [" .. level .. "] " .. line .. "\n"
            if #entry > SERVER_LOG_MAX_BYTES then entry = entry:sub(-SERVER_LOG_MAX_BYTES) end
            local previous = File.Exists(path) and File.Read(path) or ""
            local retainedBytes = SERVER_LOG_MAX_BYTES - #entry
            if retainedBytes <= 0 then previous = ""
            elseif #previous > retainedBytes then previous = previous:sub(-retainedBytes) end
            File.Write(path, previous .. entry)
        end)
    end
    if written then return end
    pcall(function()
        local consoleLine = line .. (writeFailure ~= nil and
            (" [file log unavailable: " .. tostring(writeFailure) .. "]") or "")
        if level == "WARN" and type(printerror) == "function" then printerror(consoleLine)
        else print(consoleLine) end
    end)
end

local function log(message)
    writeLog("INFO", message)
end

local function warn(message)
    writeLog("WARN", message)
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

local function cloneLook(look)
    if look == nil then return nil end
    local attachmentVisibility =
        Core.validateAttachmentVisibility(look.attachmentVisibility, look.hideHair == true) or
        Core.attachmentVisibilityFromLegacy(look.hideHair == true)
    local cloned = {
        schemaVersion = LOOK_SCHEMA_VERSION,
        captured = look.captured == true,
        hideHair = Core.legacyHideHair(attachmentVisibility),
        attachmentVisibility = attachmentVisibility,
        useFashionMovementAnimations = look.useFashionMovementAnimations ~= false,
        useFashionFootstepSounds = look.useFashionFootstepSounds == true,
        slots = {}
    }
    for _, entry in ipairs(slots) do
        local source = entry.managed ~= false and look.slots ~= nil and look.slots[entry.key] or nil
        if source ~= nil then
            if type(source) == "table" then
                cloned.slots[entry.key] = {
                    identifier = tostring(source.identifier or ""),
                    itemId = tonumber(source.itemId) or 0,
                    name = tostring(source.name or ""),
                    color = tonumber(source.color)
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

local function characterListSnapshot()
    local characters = {}
    local list = Character ~= nil and Character.CharacterList or nil
    if list == nil then return characters end
    if type(list) == "table" then
        for _, character in ipairs(list) do characters[#characters + 1] = character end
        return characters
    end
    pcall(function()
        for character in list do characters[#characters + 1] = character end
    end)
    return characters
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
    local session = userDataMember(GameMain, "GameSession") or
        userDataMember(GameApi, "GameSession")
    if session == nil then return nil end
    local dataPath = userDataMember(session, "DataPath")
    local fromDataPath = firstSessionValue(dataPath, { "SavePath", "LoadPath" })
    if fromDataPath ~= nil then return "campaign:" .. fromDataPath end
    local direct = firstSessionValue(session, { "SavePath", "SaveFilePath", "SaveFile", "FilePath" })
    if direct ~= nil then return "session:" .. direct end
    local gameMode = userDataMember(session, "GameMode")
    local fromMode = firstSessionValue(gameMode, { "SavePath", "SaveFilePath", "SaveFile", "FilePath" })
    if fromMode ~= nil then return "gamemode:" .. fromMode end
    local campaign = userDataMember(session, "Campaign") or userDataMember(gameMode, "Campaign")
    local fromCampaign = firstSessionValue(campaign, {
        "SavePath", "SaveFilePath", "SaveFile", "FilePath"
    })
    if fromCampaign ~= nil then return "campaign:" .. fromCampaign end
    local preset = userDataMember(gameMode, "Preset")
    local presetIdentifier = firstSessionValue(preset, { "Identifier" })
    if presetIdentifier ~= nil then
        return "runtime:" .. serverSessionId .. ":" .. presetIdentifier
    end
    return nil
end

local function profileIdentifierPart(value)
    local text = normalizedSessionValue(value) or ""
    return tostring(#text) .. ":" .. text
end

local function crewCharacterKey(character)
    local info = userDataMember(character, "Info")
    local infoId = tonumber(userDataMember(info, "ID"))
    if infoId ~= nil and infoId > 0 then return "info:" .. tostring(math.floor(infoId)) end
    local originalName = normalizedSessionValue(userDataMember(info, "OriginalName"))
    local speciesName = normalizedSessionValue(userDataMember(info, "SpeciesName"))
    if originalName ~= nil and speciesName ~= nil then
        local prefabIds = userDataMember(info, "HumanPrefabIds")
        return table.concat({
            profileIdentifierPart(originalName),
            profileIdentifierPart(speciesName),
            profileIdentifierPart(userDataMember(prefabIds, "Item1")),
            profileIdentifierPart(userDataMember(prefabIds, "Item2"))
        }, "|")
    end
    local name = normalizedSessionValue(userDataMember(info, "Name")) or
        normalizedSessionValue(userDataMember(character, "Name"))
    return name ~= nil and ("name:" .. profileIdentifierPart(name)) or nil
end

local function crewStorageKey(character)
    local sessionKey = currentGameSessionKey()
    local characterKey = crewCharacterKey(character)
    if sessionKey == nil or characterKey == nil then return nil end
    return sessionKey .. "\n" .. characterKey, sessionKey, characterKey
end

local function isRuntimeSessionKey(key)
    return type(key) == "string" and key:sub(1, 8) == "runtime:"
end

local function canAwaitPersistentSessionKey(persistentKey, currentKey)
    return persistentKey ~= nil and
        (currentKey == nil or persistentKey == currentKey or
            (isRuntimeSessionKey(currentKey) and not isRuntimeSessionKey(persistentKey)))
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

local function steamPersistenceIdForClient(client)
    local steamId = steamIdForClient(client)
    return steamId ~= nil and ("steam:" .. steamId) or nil
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

local function resolveCrewTarget(client, targetCharacterId)
    local requester = clientCharacter(client)
    if requester == nil or userDataMember(requester, "IsDead") == true or
        userDataMember(requester, "Removed") == true then
        return nil, "character_unavailable"
    end
    targetCharacterId = tonumber(targetCharacterId)
    if targetCharacterId == nil or targetCharacterId <= 0 then return nil, "target_unavailable" end

    local target = nil
    for _, character in ipairs(characterListSnapshot()) do
        if characterEntityId(character) == targetCharacterId then target = character break end
    end
    if target == nil or userDataMember(target, "IsDead") == true or
        userDataMember(target, "Removed") == true then
        return nil, "target_unavailable"
    end
    if userDataMember(target, "IsHuman") ~= true or
        userDataMember(target, "IsOnPlayerTeam") ~= true or
        userDataMember(target, "IsBot") ~= true then
        return nil, "target_not_permitted"
    end
    for _, connected in ipairs(connectedClients()) do
        if clientCharacter(connected) == target then return nil, "target_not_permitted" end
    end
    return target
end

-- JSON codec kept local to avoid adding a server-side C# assembly. It accepts
-- standard JSON but the writer emits only the current persistence document below.
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
    local saveFolder = trim(userDataMember(GameApi, "SaveFolder"))
    if saveFolder ~= nil then
        return tostring(saveFolder):gsub("\\", "/"):gsub("/$", "") ..
            "/ModData/BaroWardrobeSwitcher"
    end
    return nil
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
    local ok, text = pcall(function() return File.Read(path) end)
    return ok and tostring(text) or nil
end

local function ensureStorageDirectory()
    local directory = storageDirectory()
    if File == nil or directory == nil then return false end
    local ok, created = pcall(function() return File.CreateDirectory(directory) end)
    return ok and created ~= false
end

-- Persistence is replace-based so a crash cannot expose a partially written
-- document. The backup path also gives the fallback Move implementation a
-- recoverable copy of the previous state.
local function atomicWrite(path, contents)
    if File == nil or path == nil or not ensureStorageDirectory() then return false, "storage_unavailable" end
    local temporaryPath = path .. ".tmp"
    local backupPath = path .. ".bak"
    local hadPrimary = false
    local ok, failure = pcall(function()
        if File.Exists(temporaryPath) then File.Delete(temporaryPath) end
        File.Write(temporaryPath, contents)
        if readAllText(temporaryPath) ~= contents then error("temporary_write_verification_failed") end
        hadPrimary = File.Exists(path)
        if hadPrimary then File.Move(path, backupPath) end
        File.Move(temporaryPath, path)
        if readAllText(path) ~= contents then error("write_verification_failed") end
    end)
    if not ok then
        if hadPrimary then
            pcall(function() if File.Exists(backupPath) then File.Move(backupPath, path) end end)
        end
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
    local canonical = Core.validateAttachmentVisibility(visibility, false) or
        Core.attachmentVisibilityFromLegacy(false)
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
        '"useFashionMovementAnimations":' ..
            tostring(look == nil or look.useFashionMovementAnimations ~= false),
        '"useFashionFootstepSounds":' ..
            tostring(look ~= nil and look.useFashionFootstepSounds == true),
        '"attachmentVisibility":' .. encodeAttachmentVisibilityJson(
            look ~= nil and look.attachmentVisibility or nil
        )
    }
    local slotMembers = {}
    local colorMembers = {}
    for _, entry in ipairs(slots) do
        local slot = entry.managed ~= false and look ~= nil and look.slots ~= nil and
            look.slots[entry.key] or nil
        local identifier = slot ~= nil and (type(slot) == "table" and slot.identifier or slot) or nil
        identifier = trim(identifier)
        if identifier ~= nil then
            slotMembers[#slotMembers + 1] = '"' .. entry.key .. '":"' .. jsonEscape(identifier) .. '"'
            local color = type(slot) == "table" and tonumber(slot.color) or nil
            if color ~= nil then
                colorMembers[#colorMembers + 1] = '"' .. entry.key .. '":' .. tostring(math.floor(color))
            end
        end
    end
    members[#members + 1] = '"slots":{' .. table.concat(slotMembers, ",") .. "}"
    members[#members + 1] = '"colors":{' .. table.concat(colorMembers, ",") .. "}"
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

local function encodeCrewPersistenceDocument()
    local keys = {}
    for key in pairs(persistentCrewRecords) do keys[#keys + 1] = key end
    table.sort(keys)
    local records = {}
    for _, key in ipairs(keys) do
        local record = persistentCrewRecords[key]
        if record ~= nil and (record.look ~= nil or record.divingCaptured == true or
            (tonumber(record.divingMode) or 0) ~= 0) then
            records[#records + 1] = "{" .. table.concat({
                '"sessionKey":"' .. jsonEscape(record.sessionKey) .. '"',
                '"characterKey":"' .. jsonEscape(record.characterKey) .. '"',
                '"displayName":"' .. jsonEscape(record.displayName or "") .. '"',
                '"active":' .. tostring(record.active == true),
                '"look":' .. (record.look ~= nil and encodeLookJson(record.look) or "null"),
                '"divingMode":' .. tostring(math.floor(tonumber(record.divingMode) or 0)),
                '"divingCaptured":' .. tostring(record.divingCaptured == true),
                '"divingLook":' .. (record.divingLook ~= nil and
                    encodeLookJson(record.divingLook) or "null")
            }, ",") .. "}"
        end
    end
    return '{"schemaVersion":' .. tostring(CREW_PERSISTENCE_VERSION) ..
        ',"records":[' .. table.concat(records, ",") .. "]}\n"
end

local function persistLooks()
    local path = storagePath("ServerLooks.json")
    local ok, reason = atomicWrite(path, encodePersistenceDocument())
    if not ok then warn("Could not atomically persist server wardrobes: " .. tostring(reason)) end
    return ok
end

local function persistCrewLooks()
    local path = storagePath("ServerCrewLooks.json")
    local ok, reason = atomicWrite(path, encodeCrewPersistenceDocument())
    if not ok then warn("Could not atomically persist server crew wardrobes: " .. tostring(reason)) end
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
            attachmentVisibility = Core.attachmentVisibilityFromLegacy(false),
            useFashionMovementAnimations = true,
            useFashionFootstepSounds = false,
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
    local expectedLookSchema = persistenceVersion == PERSISTENCE_VERSION and LOOK_SCHEMA_VERSION or
        (persistenceVersion == 4 and 3 or 2)
    if type(raw) ~= "table" or type(raw.schemaVersion) ~= "number" or
        raw.schemaVersion ~= expectedLookSchema or
        raw.captured ~= true or type(raw.slots) ~= "table" then
        return nil
    end
    local visibility
    if persistenceVersion == PERSISTENCE_VERSION then
        if not hasOnlyFields(raw, {
            schemaVersion = true,
            captured = true,
            attachmentVisibility = true,
            useFashionMovementAnimations = true,
            useFashionFootstepSounds = true,
            slots = true,
            colors = true
        }) or raw.hideHair ~= nil or type(raw.attachmentVisibility) ~= "table" or
            type(raw.colors) ~= "table" or
            (raw.useFashionMovementAnimations ~= nil and
                type(raw.useFashionMovementAnimations) ~= "boolean") or
            (raw.useFashionFootstepSounds ~= nil and
                type(raw.useFashionFootstepSounds) ~= "boolean") then
            return nil
        end
        visibility = Core.validateAttachmentVisibility(raw.attachmentVisibility, false)
    elseif persistenceVersion == 4 then
        if not hasOnlyFields(raw, {
            schemaVersion = true,
            captured = true,
            attachmentVisibility = true,
            useFashionMovementAnimations = true,
            slots = true,
            colors = true
        }) or raw.hideHair ~= nil or type(raw.attachmentVisibility) ~= "table" or
            type(raw.colors) ~= "table" or
            (raw.useFashionMovementAnimations ~= nil and
                type(raw.useFashionMovementAnimations) ~= "boolean") then
            return nil
        end
        visibility = Core.validateAttachmentVisibility(raw.attachmentVisibility, false)
    elseif persistenceVersion == 3 then
        if not hasOnlyFields(raw, {
            schemaVersion = true,
            captured = true,
            attachmentVisibility = true,
            slots = true
        }) or raw.hideHair ~= nil or type(raw.attachmentVisibility) ~= "table" then
            return nil
        end
        visibility = Core.validateAttachmentVisibility(raw.attachmentVisibility, false)
    elseif persistenceVersion == 2 then
        if not hasOnlyFields(raw, {
            schemaVersion = true,
            captured = true,
            hideHair = true,
            slots = true
        }) or type(raw.hideHair) ~= "boolean" then
            return nil
        end
        visibility = Core.attachmentVisibilityFromLegacy(raw.hideHair == true)
    else
        return nil
    end
    if visibility == nil then return nil end
    local look = {
        schemaVersion = LOOK_SCHEMA_VERSION,
        captured = raw.captured == true,
        hideHair = Core.legacyHideHair(visibility),
        attachmentVisibility = visibility,
        useFashionMovementAnimations =
            persistenceVersion < 4 or raw.useFashionMovementAnimations ~= false,
        useFashionFootstepSounds =
            persistenceVersion == PERSISTENCE_VERSION and raw.useFashionFootstepSounds == true,
        slots = {}
    }
    local count = 0
    for key, identifier in pairs(raw.slots) do
        local entry = slotByKey[key]
        if entry == nil or type(identifier) ~= "string" or byteLength(identifier) > MAX_IDENTIFIER_BYTES then return nil end
        if entry.managed ~= false then
            identifier = trim(identifier)
            if identifier == nil then return nil end
            count = count + 1
            if count > MAX_SLOTS then return nil end
            look.slots[key] = { identifier = identifier, itemId = 0, name = "" }
        end
    end
    if persistenceVersion == PERSISTENCE_VERSION or persistenceVersion == 4 then
        for key, color in pairs(raw.colors) do
            local entry = slotByKey[key]
            if entry == nil or (entry.managed ~= false and look.slots[key] == nil) or type(color) ~= "number" or
                color < 0 or color > MAX_REVISION or color % 1 ~= 0 then
                return nil
            end
            if entry.managed ~= false then look.slots[key].color = math.floor(color) end
        end
    end
    return look
end

local function quarantine(path, reason)
    local suffix = os.date("!%Y%m%d-%H%M%S")
    local destination = path .. "." .. suffix .. ".corrupt"
    local moved = File ~= nil and pcall(function() File.Move(path, destination) end)
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
        (documentVersion ~= PERSISTENCE_VERSION and documentVersion ~= 4 and
            documentVersion ~= 3 and documentVersion ~= 2) or
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
    if documentVersion ~= PERSISTENCE_VERSION then
        local backupPath = path .. ".v" .. tostring(documentVersion) .. ".bak"
        local source = readAllText(path)
        local backedUp = File ~= nil and source ~= nil and
            pcall(function() File.Write(backupPath, source) end)
        if not backedUp then
            warn("Could not preserve " .. backupPath .. "; leaving the valid legacy file unchanged.")
            return true
        end
        if persistLooks() then
            log("Migrated server wardrobe persistence from v" .. tostring(documentVersion) ..
                " to v" .. tostring(PERSISTENCE_VERSION) .. ".")
        else
            warn("Could not persist migrated server wardrobe v" .. tostring(PERSISTENCE_VERSION) ..
                "; the legacy source remains available for retry.")
        end
    end
    return true
end

local function moveLegacyToBackup(path)
    if File == nil or not fileExists(path) then return end
    local backup = path .. ".v1.bak"
    pcall(function()
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

local function itemSpriteColor(item)
    if item == nil then return nil end
    local ok, color = pcall(function() return tonumber(item.SpriteColor.PackedValue) end)
    if not ok or color == nil or color < 0 or color > MAX_REVISION or color % 1 ~= 0 then return nil end
    return math.floor(color)
end

local function isLockedWardrobeItem(item)
    if item == nil then return false end
    local ok, locked = pcall(function()
        return item.OwnInventory ~= nil and item.OwnInventory.Locked == true
    end)
    if ok and locked == true then return true end
    ok, locked = pcall(function()
        return item.HasTag("lock") or item.HasTag("locked")
    end)
    return ok and locked == true
end

local function loadCrewPersistence()
    local path = storagePath("ServerCrewLooks.json")
    if path == nil or not fileExists(path) then return end
    local text = readAllText(path)
    local ok, document = pcall(decodeJson, text or "")
    local documentVersion = ok and type(document) == "table" and
        tonumber(document.schemaVersion) or nil
    if not ok or (documentVersion ~= 1 and documentVersion ~= CREW_PERSISTENCE_VERSION) or
        type(document.records) ~= "table" or
        not hasOnlyFields(document, { schemaVersion = true, records = true }) then
        quarantine(path, ok and "invalid_crew_schema" or document)
        persistentCrewRecords = {}
        persistCrewLooks()
        return
    end
    local loaded = {}
    for _, raw in ipairs(document.records) do
        local allowedFields = documentVersion == 1 and {
            sessionKey = true,
            characterKey = true,
            displayName = true,
            active = true,
            look = true
        } or {
            sessionKey = true,
            characterKey = true,
            displayName = true,
            active = true,
            look = true,
            divingMode = true,
            divingCaptured = true,
            divingLook = true
        }
        local valid = type(raw) == "table" and hasOnlyFields(raw, allowedFields) and
            type(raw.sessionKey) == "string" and
            type(raw.characterKey) == "string" and type(raw.displayName) == "string" and
            type(raw.active) == "boolean"
        local look = valid and raw.look ~= nil and
            validateStoredLook(raw.look, PERSISTENCE_VERSION) or nil
        valid = valid and (raw.look == nil or look ~= nil) and
            (raw.active ~= true or look ~= nil)
        local divingMode = documentVersion == 1 and 0 or tonumber(raw.divingMode)
        local divingCaptured = documentVersion ~= 1 and raw.divingCaptured == true
        if documentVersion == CREW_PERSISTENCE_VERSION then
            valid = valid and type(raw.divingMode) == "number" and
                divingMode >= 0 and divingMode <= 2 and divingMode % 1 == 0 and
                type(raw.divingCaptured) == "boolean" and
                ((divingCaptured and raw.divingLook ~= nil) or
                 (not divingCaptured and raw.divingLook == nil))
        end
        local divingLook = valid and divingCaptured and
            validateStoredLook(raw.divingLook, PERSISTENCE_VERSION) or nil
        local sessionKey = valid and normalizedSessionValue(raw.sessionKey) or nil
        local characterKey = valid and trim(raw.characterKey) or nil
        local key = sessionKey ~= nil and characterKey ~= nil and
            (sessionKey .. "\n" .. characterKey) or nil
        if key == nil or (documentVersion == 1 and look == nil) or
            (divingCaptured and divingLook == nil) or
            (look == nil and not divingCaptured and divingMode == 0) or
            loaded[key] ~= nil then
            quarantine(path, "invalid_crew_record")
            persistentCrewRecords = {}
            persistCrewLooks()
            return
        end
        loaded[key] = {
            sessionKey = sessionKey,
            characterKey = characterKey,
            displayName = raw.displayName,
            active = raw.active == true,
            look = look,
            divingMode = divingMode,
            divingCaptured = divingCaptured,
            divingLook = divingLook
        }
    end
    persistentCrewRecords = loaded
    if documentVersion ~= CREW_PERSISTENCE_VERSION then persistCrewLooks() end
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
    if isLockedWardrobeItem(item) then
        pcall(function() item.Drop(character) end)
        return clear()
    end
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

local function collectWardrobeItems(character, look)
    local result, byItem = {}, {}
    local preserved = {}
    for _, entry in ipairs(slots) do
        if entry.optional == true and
            (look == nil or look.slots == nil or look.slots[entry.key] == nil) then
            local item = getSlotItem(character, entry.slot)
            if item ~= nil then preserved[item] = true end
        end
    end
    for _, entry in ipairs(slots) do
        local included = entry.optional ~= true or
            (look ~= nil and look.slots ~= nil and look.slots[entry.key] ~= nil)
        local item = included and getSlotItem(character, entry.slot) or nil
        if item ~= nil and preserved[item] ~= true then
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

local function canonicalSlot(identifier, slotKey, color)
    identifier = trim(identifier)
    if identifier == nil then return nil, "empty_identifier" end
    if byteLength(identifier) > MAX_IDENTIFIER_BYTES then return nil, "identifier_too_long" end
    if color ~= nil and (type(color) ~= "number" or color < 0 or color > MAX_REVISION or color % 1 ~= 0) then
        return nil, "invalid_color"
    end
    local prefab = resolveItemPrefab(identifier)
    if prefab == nil then return nil, "unknown_item" end
    if not wearableAllowsSlot(prefab, slotKey) then return nil, "item_not_wearable_in_slot" end
    local canonicalIdentifier = prefabIdentifier(prefab)
    if canonicalIdentifier == nil or byteLength(canonicalIdentifier) > MAX_IDENTIFIER_BYTES then return nil, "invalid_prefab_identifier" end
    return {
        identifier = canonicalIdentifier,
        itemId = 0,
        name = prefabName(prefab),
        color = color ~= nil and math.floor(color) or nil
    }
end

local function canonicalizeLook(raw, requireCaptured)
    if type(raw) ~= "table" or tonumber(raw.schemaVersion) ~= LOOK_SCHEMA_VERSION or type(raw.slots) ~= "table" then
        return nil, "invalid_look_schema"
    end
    if raw.colors ~= nil and type(raw.colors) ~= "table" then return nil, "invalid_colors" end
    if requireCaptured and raw.captured ~= true then return nil, "look_not_captured" end
    local attachmentVisibility, visibilityReason =
        Core.validateAttachmentVisibility(raw.attachmentVisibility, raw.hideHair == true)
    if attachmentVisibility == nil then return nil, visibilityReason end
    local canonical = {
        schemaVersion = LOOK_SCHEMA_VERSION,
        captured = raw.captured == true,
        hideHair = Core.legacyHideHair(attachmentVisibility),
        attachmentVisibility = attachmentVisibility,
        useFashionMovementAnimations = raw.useFashionMovementAnimations ~= false,
        useFashionFootstepSounds = raw.useFashionFootstepSounds == true,
        slots = {}
    }
    local count, payloadBytes = 0, 16
    for key, color in pairs(raw.colors or {}) do
        local entry = type(key) == "string" and slotByKey[key] or nil
        if entry == nil then return nil, "unknown_color_slot" end
        if entry.managed ~= false and raw.slots[key] == nil then return nil, "orphan_color" end
        if type(color) ~= "number" or color < 0 or color > MAX_REVISION or color % 1 ~= 0 then
            return nil, "invalid_color"
        end
    end
    for key, rawSlot in pairs(raw.slots) do
        local entry = type(key) == "string" and slotByKey[key] or nil
        if entry == nil then return nil, "unknown_slot" end
        if entry.managed ~= false then
            count = count + 1
            if count > MAX_SLOTS then return nil, "too_many_slots" end
            local identifier = type(rawSlot) == "table" and rawSlot.identifier or rawSlot
            local color = raw.colors ~= nil and raw.colors[key] or
                (type(rawSlot) == "table" and rawSlot.color or nil)
            if type(identifier) ~= "string" then return nil, "invalid_identifier" end
            payloadBytes = payloadBytes + byteLength(key) + byteLength(identifier) + 5
            if color ~= nil then payloadBytes = payloadBytes + 4 end
            if payloadBytes > MAX_PAYLOAD_BYTES then return nil, "payload_too_large" end
            local slot, reason = canonicalSlot(identifier, key, color)
            if slot == nil then return nil, reason .. ":" .. key end
            canonical.slots[key] = slot
        end
    end
    return canonical
end

local function captureAuthoritativeLook(character, clientLook)
    if character == nil then return nil, "character_unavailable" end
    local attachmentVisibility, visibilityReason = Core.validateAttachmentVisibility(
        type(clientLook) == "table" and clientLook.attachmentVisibility or nil,
        type(clientLook) == "table" and clientLook.hideHair == true
    )
    if attachmentVisibility == nil then return nil, visibilityReason end
    local raw = {
        schemaVersion = LOOK_SCHEMA_VERSION,
        captured = true,
        hideHair = Core.legacyHideHair(attachmentVisibility),
        attachmentVisibility = attachmentVisibility,
        useFashionMovementAnimations =
            type(clientLook) ~= "table" or clientLook.useFashionMovementAnimations ~= false,
        useFashionFootstepSounds =
            type(clientLook) == "table" and clientLook.useFashionFootstepSounds == true,
        slots = {}
    }
    for _, entry in ipairs(slots) do
        local requested = entry.optional ~= true or
            (type(clientLook) == "table" and type(clientLook.slots) == "table" and
                clientLook.slots[entry.key] ~= nil)
        local item = requested and getSlotItem(character, entry.slot) or nil
        if item ~= nil then
            local identifier = itemIdentifier(item)
            if identifier ~= nil then
                raw.slots[entry.key] = {
                    identifier = identifier,
                    color = itemSpriteColor(item)
                }
            end
        end
    end
    return canonicalizeLook(raw, true)
end

local function readCoreLook(message)
    local look, reason = Core.readLook(message)
    if look == nil then error(reason or "invalid_look") end
    return look
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

local function migrateLegacyForClient(client, accountId)
    local steamId = steamIdForClient(client)
    if accountId == nil or steamId == nil then return end
    local changed = false
    local fallbackAccountId = "steam:" .. steamId
    if fallbackAccountId ~= accountId and persistentRecords[fallbackAccountId] ~= nil then
        if persistentRecords[accountId] == nil then
            persistentRecords[accountId] = persistentRecords[fallbackAccountId]
        end
        persistentRecords[fallbackAccountId] = nil
        changed = true
    end
    local legacy = legacySteamRecords[steamId]
    if legacy ~= nil and migratedLegacySteamIds[steamId] ~= true then
        if persistentRecords[accountId] == nil then persistentRecords[accountId] = legacy end
        legacySteamRecords[steamId] = nil
        migratedLegacySteamIds[steamId] = true
        changed = true
    end
    if changed then
        persistLooks()
        log("Migrated a Steam wardrobe record to Client.AccountId.")
    end
end

-- v2 retries reuse operation IDs. Retaining the first result per account/session
-- makes repeated packets idempotent even if the connection object is replaced.
local function operationCacheNow()
    local ok, value = pcall(os.time)
    return ok and math.floor(tonumber(value) or 0) or 0
end

local function newOperationCache(clientSessionId)
    return {
        clientSessionId = clientSessionId,
        results = {},
        count = 0,
        limitResult = nil,
        lastTouchedAt = operationCacheNow()
    }
end

local function operationCacheInUse(cache)
    for _, session in pairs(sessionsByClient) do
        if session.operationCache == cache then return true end
    end
    return false
end

local function pruneOperationCaches(now)
    now = tonumber(now) or operationCacheNow()
    local retained = {}
    for accountId, cache in pairs(operationCachesByAccount) do
        if not operationCacheInUse(cache) and
            now - (tonumber(cache.lastTouchedAt) or 0) > OPERATION_CACHE_RETENTION_SECONDS then
            operationCachesByAccount[accountId] = nil
        else
            retained[#retained + 1] = { accountId = accountId, cache = cache }
        end
    end
    if #retained <= MAX_RETAINED_OPERATION_ACCOUNTS then return end
    table.sort(retained, function(left, right)
        return (tonumber(left.cache.lastTouchedAt) or 0) < (tonumber(right.cache.lastTouchedAt) or 0)
    end)
    local remove = #retained - MAX_RETAINED_OPERATION_ACCOUNTS
    for _, entry in ipairs(retained) do
        if remove <= 0 then break end
        if not operationCacheInUse(entry.cache) then
            operationCachesByAccount[entry.accountId] = nil
            remove = remove - 1
        end
    end
end

local function bindOperationCache(session, clientSessionId)
    if session == nil then return end
    clientSessionId = tostring(clientSessionId or "")
    local now = operationCacheNow()
    local cache = nil
    if session.accountId ~= nil then
        local retained = operationCachesByAccount[session.accountId]
        if retained ~= nil and retained.clientSessionId == clientSessionId and
            now - (tonumber(retained.lastTouchedAt) or 0) <= OPERATION_CACHE_RETENTION_SECONDS then
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
    cache.lastTouchedAt = now
    session.clientSessionId = clientSessionId
    session.operationCache = cache
    -- Keep this field in the ClientWardrobeSession aggregate while the cache
    -- metadata enforces a hard memory bound.
    session.seenOperations = cache.results
    pruneOperationCaches(now)
end

local function sessionFor(client)
    if client == nil then return nil end
    local existing = sessionsByClient[client]
    if existing ~= nil then
        -- client.connected can run before LuaCs exposes Client.AccountId. If
        -- the hello/character arrives after that, replace the still-pristine
        -- anonymous cache with the stable account session instead of losing
        -- the persisted look for the whole connection.
        local lateAccountId = existing.accountId == nil and accountIdForClient(client) or nil
        if lateAccountId ~= nil and existing.savedLook == nil and
            existing.active ~= true and existing.activeCharacterId == nil and
            (tonumber(existing.revision) or 0) == 0 then
            local previousProtocol = existing.protocol
            local previousClientSessionId = existing.clientSessionId
            sessionsByClient[client] = nil
            local rebound = sessionFor(client)
            if rebound ~= nil then
                rebound.protocol = previousProtocol
                if previousClientSessionId ~= nil then
                    bindOperationCache(rebound, previousClientSessionId)
                end
            end
            return rebound
        end
        return existing
    end
    local accountId = accountIdForClient(client)
    if accountId ~= nil then migrateLegacyForClient(client, accountId) end
    accountId = accountId or steamPersistenceIdForClient(client)
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
    local gameSessionKey = currentGameSessionKey()
    local persistentSessionKey = record ~= nil and record.sessionKey or nil
    local shouldRestorePersistentLook = recordLook ~= nil and record.active == true and
        canAwaitPersistentSessionKey(persistentSessionKey, gameSessionKey)
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
        -- GameSession can still be nil while a reconnecting client is being
        -- constructed. Preserve the persisted intent until the bounded
        -- reactivation retry can compare the eventual key.
        active = shouldRestorePersistentLook,
        activePersistent = shouldRestorePersistentLook,
        persistentSessionKey = shouldRestorePersistentLook and persistentSessionKey or nil,
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
        active = session.active == true and session.activePersistent == true,
        sessionKey = session.persistentSessionKey or currentGameSessionKey()
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
        activePersistent = session.activePersistent == true,
        persistentSessionKey = session.persistentSessionKey,
        activeCharacterId = session.activeCharacterId,
        persistentRecord = session.accountId ~= nil and clonePersistentRecord(persistentRecords[session.accountId]) or nil
    }
end

local function restoreCommitState(session, snapshot)
    session.revision = snapshot.revision
    session.savedLook = cloneLook(snapshot.savedLook)
    session.active = snapshot.active == true
    session.activePersistent = snapshot.activePersistent == true
    session.persistentSessionKey = snapshot.persistentSessionKey
    session.activeCharacterId = snapshot.activeCharacterId
    if session.accountId ~= nil then
        persistentRecords[session.accountId] = clonePersistentRecord(snapshot.persistentRecord)
    end
end

-- 有穩定帳號才落盤；寫入失敗還原快照，避免記憶體狀態與存檔不一致。
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
    local written, writeReason = Core.writeAck(message, {
        operationId = operationId or "",
        accepted = accepted == true,
        revision = math.max(0, tonumber(revision) or session.revision or 0),
        reason = reason or ""
    })
    if not written then warn("Could not encode v2 acknowledgement: " .. tostring(writeReason)) return end
    Networking.Send(message, session.client.Connection)
end

local function sendV2State(client, revision, characterId, active, look)
    if client == nil or client.Connection == nil then return end
    local message = Networking.Start(NET.V2_STATE)
    local written, writeReason = Core.writeState(message, {
        revision = math.max(0, tonumber(revision) or 0),
        characterId = math.max(0, tonumber(characterId) or 0),
        active = active == true,
        look = look
    })
    if not written then warn("Could not encode v2 state: " .. tostring(writeReason)) return end
    Networking.Send(message, client.Connection)
end

local function sendLegacyState(client, characterId, active, look)
    if client == nil or client.Connection == nil then return end
    if active then
        local message = Networking.Start(NET.V1_LOOK_APPLY)
        writeLegacyLook(message, characterId, look)
        Networking.Send(message, client.Connection)
    else
        local message = Networking.Start(NET.V1_LOOK_CLEAR)
        message.WriteUInt16(characterId or 0)
        Networking.Send(message, client.Connection)
    end
end

local function sendStateTo(client, ownerSession, ownerRevision, observerRevision, characterId, active, look, crewOwned)
    local recipient = sessionFor(client)
    if recipient ~= nil and recipient.protocol == PROTOCOL_VERSION then
        local revision = crewOwned == true and recipient.revision or
            (recipient == ownerSession and ownerRevision or observerRevision)
        sendV2State(client, revision, characterId, active, look)
    elseif recipient ~= nil and recipient.protocol == 1 then
        sendLegacyState(client, characterId, active, look)
    end
end

local function cloneCrewRecord(record)
    if record == nil then return nil end
    return {
        sessionKey = record.sessionKey,
        characterKey = record.characterKey,
        displayName = record.displayName,
        active = record.active == true,
        look = cloneLook(record.look),
        divingMode = math.floor(tonumber(record.divingMode) or 0),
        divingCaptured = record.divingCaptured == true,
        divingLook = cloneLook(record.divingLook)
    }
end

local function snapshotCrewState(character)
    local key, sessionKey, characterKey = crewStorageKey(character)
    if key == nil then return nil end
    return {
        key = key,
        sessionKey = sessionKey,
        characterKey = characterKey,
        record = cloneCrewRecord(persistentCrewRecords[key])
    }
end

local function crewLook(character)
    local key = crewStorageKey(character)
    local record = key ~= nil and persistentCrewRecords[key] or nil
    return record ~= nil and cloneLook(record.look) or nil
end

local function crewDivingProfile(character)
    local key = crewStorageKey(character)
    local record = key ~= nil and persistentCrewRecords[key] or nil
    if record == nil then return nil end
    return {
        mode = math.floor(tonumber(record.divingMode) or 0),
        captured = record.divingCaptured == true,
        look = cloneLook(record.divingLook)
    }
end

local function crewRecordHasData(record)
    return record ~= nil and (record.look ~= nil or record.divingCaptured == true or
        (tonumber(record.divingMode) or 0) ~= 0)
end

local function setCrewLook(snapshot, character, look, active)
    if snapshot == nil then return false end
    local record = cloneCrewRecord(persistentCrewRecords[snapshot.key]) or {}
    record.sessionKey = snapshot.sessionKey
    record.characterKey = snapshot.characterKey
    record.displayName = tostring(userDataMember(character, "Name") or "")
    record.active = active == true and look ~= nil
    record.look = cloneLook(look)
    persistentCrewRecords[snapshot.key] = crewRecordHasData(record) and record or nil
    return true
end

local function setCrewDivingProfile(snapshot, character, profile)
    if snapshot == nil or profile == nil then return false end
    local record = cloneCrewRecord(persistentCrewRecords[snapshot.key]) or {}
    record.sessionKey = snapshot.sessionKey
    record.characterKey = snapshot.characterKey
    record.displayName = tostring(userDataMember(character, "Name") or "")
    record.active = record.active == true and record.look ~= nil
    record.divingMode = math.floor(tonumber(profile.mode) or 0)
    record.divingCaptured = profile.captured == true
    record.divingLook = record.divingCaptured and cloneLook(profile.look) or nil
    persistentCrewRecords[snapshot.key] = crewRecordHasData(record) and record or nil
    return true
end

local function persistCrewOrRollback(snapshot)
    if snapshot == nil then return false end
    if persistCrewLooks() then return true end
    persistentCrewRecords[snapshot.key] = cloneCrewRecord(snapshot.record)
    return false
end

local function sendCrewDivingState(client, character, profile)
    if client == nil or client.Connection == nil or character == nil or profile == nil then return false end
    local recipient = sessionFor(client)
    if recipient == nil or recipient.protocol ~= PROTOCOL_VERSION then return false end
    local message = Networking.Start(NET.V2_DIVING_STATE)
    local written, reason = Core.writeDivingProfile(message, {
        characterId = characterEntityId(character),
        mode = profile.mode,
        captured = profile.captured == true,
        look = profile.look
    })
    if not written then
        warn("Could not encode crew diving profile: " .. tostring(reason))
        return false
    end
    Networking.Send(message, client.Connection)
    return true
end

local function broadcastCrewDivingState(character, profile)
    for _, client in ipairs(connectedClients()) do
        sendCrewDivingState(client, character, profile)
    end
end

local function sendCrewDivingSnapshot(client)
    for _, character in ipairs(characterListSnapshot()) do
        local profile = crewDivingProfile(character)
        if profile ~= nil then sendCrewDivingState(client, character, profile) end
    end
end

local function nextObserverRevision(characterId)
    characterId = tonumber(characterId)
    if characterId == nil or characterId <= 0 then return 0 end
    local revision = tonumber(observerRevisionByCharacterId[characterId]) or 0
    if revision < MAX_REVISION then revision = revision + 1 end
    observerRevisionByCharacterId[characterId] = revision
    return revision
end

local function broadcastState(ownerSession, ownerRevision, characterId, active, look, observerRevision, crewOwned)
    if tonumber(characterId) == nil or tonumber(characterId) <= 0 then return end
    observerRevision = tonumber(observerRevision) or nextObserverRevision(characterId)
    for _, client in ipairs(connectedClients()) do
        sendStateTo(client, ownerSession, ownerRevision, observerRevision, characterId, active, look, crewOwned)
    end
    return observerRevision
end

local activateRuntime
local restoreCrewRuntimes
local handleGameSessionChange

local function sendActiveSnapshot(client)
    if restoreCrewRuntimes ~= nil then restoreCrewRuntimes() end
    local reboundCharacterIds = {}
    local requestingSession = sessionFor(client)
    -- Rebuild runtime entries lost during round transitions. A ready owner's
    -- hello reannounces its active look to peers that may have seen a transient
    -- Character before it was ready.
    for _, owner in ipairs(connectedClients()) do
        local ownerSession = sessionFor(owner)
        local character = clientCharacter(owner)
        local characterId = characterEntityId(character)
        if ownerSession ~= nil and ownerSession.active and ownerSession.activePersistent and
            ownerSession.savedLook ~= nil and characterId > 0 then
            local runtime = activeByCharacterId[characterId]
            if ownerSession == requestingSession or
                tonumber(ownerSession.activeCharacterId) ~= characterId or runtime == nil or
                runtime.session ~= ownerSession or runtime.revision ~= ownerSession.revision then
                if activateRuntime(ownerSession, character, ownerSession.savedLook, true) then
                    reboundCharacterIds[characterId] = true
                end
            end
        end
    end
    for characterId, active in pairs(activeByCharacterId) do
        if reboundCharacterIds[characterId] ~= true then
            sendStateTo(
                client,
                active.session,
                active.revision,
                active.observerRevision,
                characterId,
                true,
                active.look,
                active.crewKey ~= nil
            )
        end
    end
    for _, character in ipairs(characterListSnapshot()) do
        local characterId = characterEntityId(character)
        local key = crewStorageKey(character)
        local record = key ~= nil and persistentCrewRecords[key] or nil
        if characterId > 0 and record ~= nil and record.look ~= nil and
            activeByCharacterId[characterId] == nil then
            sendStateTo(
                client,
                crewRuntimeSession,
                0,
                0,
                characterId,
                false,
                record.look,
                true
            )
        end
    end
end

local function sendOwnInactiveState(session)
    if session == nil or session.protocol ~= PROTOCOL_VERSION or session.savedLook == nil or session.active or session.activeCharacterId ~= nil then return end
    local characterId = characterEntityId(clientCharacter(session.client))
    if characterId <= 0 then return end
    sendV2State(session.client, session.revision, characterId, false, session.savedLook)
end

local function clearActiveRuntime(session, shouldBroadcast, targetCharacterId, inactiveLook, crewOwned)
    if session == nil then return nil end
    local characterId = tonumber(targetCharacterId) or tonumber(session.activeCharacterId)
    if characterId == tonumber(session.activeCharacterId) then
        session.active = false
        session.activePersistent = false
        session.persistentSessionKey = nil
        session.activeCharacterId = nil
    end
    if characterId ~= nil and characterId > 0 then
        local active = activeByCharacterId[characterId]
        if active == nil or active.session == session or active.crewKey ~= nil then
            activeByCharacterId[characterId] = nil
        end
        if shouldBroadcast then
            broadcastState(session, session.revision, characterId, false, inactiveLook, nil, crewOwned)
        end
    end
    return characterId
end

activateRuntime = function(session, character, look, restoring, targeted)
    local characterId = characterEntityId(character)
    targeted = targeted == true
    local restoreSessionKey = restoring == true and currentGameSessionKey() or nil
    local expectedSessionKey = restoring == true and session ~= nil and
        session.persistentSessionKey or nil
    if session == nil or characterId <= 0 or look == nil or
        (restoring == true and (restoreSessionKey == nil or lastGameSessionKey == nil or
            restoreSessionKey ~= lastGameSessionKey or
            (expectedSessionKey ~= nil and restoreSessionKey ~= expectedSessionKey))) then
        return false
    end
    if not targeted and session.activeCharacterId ~= nil and
        tonumber(session.activeCharacterId) ~= characterId then
        clearActiveRuntime(session, true)
    end
    local previous = activeByCharacterId[characterId]
    if previous ~= nil and previous.session ~= session and previous.crewKey == nil then
        return false
    end
    if not targeted then
        session.active = true
        session.activePersistent = character == clientCharacter(session.client)
        session.persistentSessionKey = nil
        session.activeCharacterId = characterId
    end
    local observerRevision = nextObserverRevision(characterId)
    local crewKey = targeted and crewStorageKey(character) or nil
    activeByCharacterId[characterId] = {
        session = session,
        revision = session.revision,
        observerRevision = observerRevision,
        look = cloneLook(look),
        crewKey = crewKey
    }
    broadcastState(session, session.revision, characterId, true, look, observerRevision, targeted)
    return true
end

local function operationResultFor(session, operationId)
    local cache = session.operationCache
    if cache == nil then
        cache = newOperationCache(session.clientSessionId)
        session.operationCache = cache
        session.seenOperations = cache.results
    end
    cache.lastTouchedAt = operationCacheNow()
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

local function rememberOperation(session, operationId, accepted, reason, command)
    local existing = operationResultFor(session, operationId)
    if existing ~= nil then return existing end
    local result = {
        accepted = accepted == true,
        reason = reason,
        revision = session.revision,
        kind = command ~= nil and command.kind or nil,
        targetCharacterId = command ~= nil and command.targetCharacterId or nil
    }
    local cache = session.operationCache
    cache.results[operationId] = result
    cache.count = cache.count + 1
    cache.lastTouchedAt = operationCacheNow()
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

-- 儲存是一整筆操作：先驗證存檔可寫，再依設定卸裝；失敗時嘗試還原裝備與狀態。
-- targeted 走船員紀錄；unequipOnSave=false 對應保留裝備的儲存模式。
local function commitSave(session, character, clientLook, targeted, unequipOnSave)
    if not canAdvanceRevision(session) then return false, "revision_exhausted" end
    local look, reason = captureAuthoritativeLook(character, clientLook)
    if look == nil then return false, reason end
    targeted = targeted == true
    local crewSnapshot = targeted and snapshotCrewState(character) or nil
    if targeted and crewSnapshot == nil then return false, "crew_identity_unavailable" end

    -- Verify durable storage before Save changes physical equipment. This keeps
    -- an unavailable server filesystem from turning a rejected Save into lost gear.
    if (targeted and not persistCrewLooks()) or
        (not targeted and session.accountId ~= nil and not persistLooks()) then
        return false, "persistence_failed"
    end

    -- Treat equipment removal as part of the command transaction. Do not advance
    -- the revision, persist, or broadcast unless every captured item left all
    -- managed slots. Best-effort re-equip restores already removed items when a
    -- later item fails, including persistence failures after removal.
    local itemSnapshots = unequipOnSave == false and {} or collectWardrobeItems(character, look)
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
    local persisted
    if targeted then
        setCrewLook(crewSnapshot, character, look, false)
        persisted = persistCrewOrRollback(crewSnapshot)
    else
        session.savedLook = look
        session.active = false
        session.activePersistent = false
        session.persistentSessionKey = nil
        persisted = persistStableSessionOrRollback(session, previous)
    end
    if not persisted then
        restoreCommitState(session, previous)
        local restored = restoreWardrobeItems(character, itemSnapshots)
        return false, restored and "persistence_failed" or "persistence_failed_equipment_rollback_failed"
    end
    clearActiveRuntime(
        session,
        true,
        targeted and characterEntityId(character) or nil,
        look,
        targeted
    )
    if session.protocol == PROTOCOL_VERSION then
        -- SAVE is intentionally inactive. Send the canonical server capture so
        -- the v2 client can leave ApplyPending even when there was no prior
        -- active character state to clear.
        sendV2State(session.client, session.revision, characterEntityId(character), false, look)
    end
    log("Saved authoritative wardrobe for " .. tostring(character.Name) ..
        (unequipOnSave == false and "; equipment kept." or
            "; removed " .. tostring(removed) .. " item(s)."))
    return true, "ok"
end

local function commitApply(session, character, look, targeted)
    if not canAdvanceRevision(session) then return false, "revision_exhausted" end
    if look == nil then return false, "look_unavailable" end
    if characterEntityId(character) <= 0 then return false, "character_unavailable" end
    targeted = targeted == true
    local crewSnapshot = targeted and snapshotCrewState(character) or nil
    if targeted and crewSnapshot == nil then return false, "crew_identity_unavailable" end
    local previous = snapshotCommitState(session)
    nextRevision(session)
    local persisted
    if targeted then
        setCrewLook(crewSnapshot, character, look, true)
        persisted = persistCrewOrRollback(crewSnapshot)
    else
        session.savedLook = cloneLook(look)
        session.active = true
        session.activePersistent = character == clientCharacter(session.client)
        session.persistentSessionKey = nil
        persisted = persistStableSessionOrRollback(session, previous)
    end
    if not persisted then
        restoreCommitState(session, previous)
        return false, "persistence_failed"
    end
    if not activateRuntime(session, character, look, false, targeted) then
        restoreCommitState(session, previous)
        if targeted then
            persistentCrewRecords[crewSnapshot.key] = cloneCrewRecord(crewSnapshot.record)
            if not persistCrewLooks() then warn("Could not roll back persisted crew wardrobe after activation failure.") end
        elseif session.accountId ~= nil and not persistLooks() then
            warn("Could not roll back persisted wardrobe after activation failure.")
        end
        return false, "character_unavailable"
    end
    return true, "ok"
end

local function commitVisualPreference(session, character, requestedLook, preference, targeted)
    if not canAdvanceRevision(session) then return false, "revision_exhausted" end
    targeted = targeted == true
    local baseLook = targeted and crewLook(character) or cloneLook(session.savedLook)
    if baseLook == nil then return false, "look_unavailable" end
    if type(requestedLook) ~= "table" then return false, preference .. "_unavailable" end

    -- Preference commands merge only their own policy field. Client-supplied
    -- slots are deliberately ignored so they cannot replace equipment IDs.
    local merged = baseLook
    if preference == COMMAND_VISIBILITY then
        local attachmentVisibility, visibilityReason =
            Core.validateAttachmentVisibility(requestedLook.attachmentVisibility, requestedLook.hideHair == true)
        if attachmentVisibility == nil then
            return false, visibilityReason or "invalid_attachment_visibility"
        end
        merged.attachmentVisibility = Core.validateAttachmentVisibility(attachmentVisibility, false) or
            Core.attachmentVisibilityFromLegacy(false)
        merged.hideHair = Core.legacyHideHair(merged.attachmentVisibility)
    elseif preference == COMMAND_ANIMATION then
        merged.useFashionMovementAnimations = requestedLook.useFashionMovementAnimations ~= false
    elseif preference == COMMAND_FOOTSTEP then
        merged.useFashionFootstepSounds = requestedLook.useFashionFootstepSounds == true
    else
        return false, "unknown_preference"
    end

    local previous = snapshotCommitState(session)
    local crewSnapshot = targeted and snapshotCrewState(character) or nil
    if targeted and crewSnapshot == nil then return false, "crew_identity_unavailable" end
    nextRevision(session)
    local persisted
    if targeted then
        local wasActive = crewSnapshot.record ~= nil and crewSnapshot.record.active == true
        setCrewLook(crewSnapshot, character, merged, wasActive)
        persisted = persistCrewOrRollback(crewSnapshot)
    else
        session.savedLook = merged
        persisted = persistStableSessionOrRollback(session, previous)
    end
    if not persisted then
        restoreCommitState(session, previous)
        return false, "persistence_failed"
    end

    local characterId = targeted and characterEntityId(character) or tonumber(session.activeCharacterId)
    local runtime = characterId ~= nil and activeByCharacterId[characterId] or nil
    if characterId ~= nil and characterId > 0 and
        ((targeted and runtime ~= nil and runtime.crewKey ~= nil) or
         (not targeted and session.active == true)) then
        local observerRevision = nextObserverRevision(characterId)
        activeByCharacterId[characterId] = {
            session = session,
            revision = session.revision,
            observerRevision = observerRevision,
            look = cloneLook(merged),
            crewKey = targeted and crewSnapshot.key or nil
        }
        broadcastState(session, session.revision, characterId, true, merged, observerRevision, targeted)
    elseif targeted then
        sendV2State(session.client, session.revision, characterEntityId(character), false, merged)
    else
        sendOwnInactiveState(session)
    end
    return true, "ok"
end

local function commitClear(session, character, deleteSaved, targeted)
    if not canAdvanceRevision(session) then return false, "revision_exhausted" end
    targeted = targeted == true
    local previous = snapshotCommitState(session)
    local crewSnapshot = targeted and snapshotCrewState(character) or nil
    if targeted and crewSnapshot == nil then return false, "crew_identity_unavailable" end
    nextRevision(session)
    local inactiveLook = nil
    local persisted
    if targeted then
        local record = crewSnapshot.record
        inactiveLook = not deleteSaved and record ~= nil and cloneLook(record.look) or nil
        if deleteSaved then
            setCrewLook(crewSnapshot, character, nil, false)
        elseif record ~= nil then
            setCrewLook(crewSnapshot, character, record.look, false)
        end
        persisted = persistCrewOrRollback(crewSnapshot)
    else
        session.active = false
        session.activePersistent = false
        session.persistentSessionKey = nil
        if deleteSaved then session.savedLook = nil end
        inactiveLook = session.savedLook
        persisted = persistStableSessionOrRollback(session, previous)
    end
    if not persisted then
        restoreCommitState(session, previous)
        return false, "persistence_failed"
    end
    clearActiveRuntime(
        session,
        true,
        targeted and characterEntityId(character) or nil,
        inactiveLook,
        targeted
    )
    return true, "ok"
end

-- Decode and envelope validation stay separate so a request whose operation ID
-- was readable can still receive a deterministic, correlated rejection ACK.
-- Truly truncated packets fail before such a response is possible.
local function parseV2Command(message, targeted)
    local command = {
        version = tonumber(message.ReadUInt16()),
        clientSessionId = tostring(message.ReadString() or ""),
        operationId = tostring(message.ReadString() or ""),
        baseRevision = tonumber(message.ReadUInt32()),
        kind = tostring(message.ReadString() or ""):lower(),
        targeted = targeted == true,
        look = nil
    }
    if command.targeted then command.targetCharacterId = tonumber(message.ReadUInt16()) end
    command.hasLook = message.ReadBoolean() == true
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
    [COMMAND_SAVE_KEEP] = true,
    apply = true,
    clear = true,
    forget = true,
    [COMMAND_VISIBILITY] = true,
    [COMMAND_ANIMATION] = true,
    [COMMAND_FOOTSTEP] = true
}

local function validateV2Envelope(command)
    if type(command) ~= "table" or command.version ~= PROTOCOL_VERSION then return false, "unsupported_protocol" end
    if byteLength(command.clientSessionId) == 0 or byteLength(command.clientSessionId) > MAX_SESSION_ID_BYTES then
        return false, "invalid_client_session"
    end
    if byteLength(command.operationId) == 0 or byteLength(command.operationId) > MAX_OPERATION_ID_BYTES then
        return false, "invalid_operation_id"
    end
    if command.baseRevision == nil or command.baseRevision < 0 then return false, "invalid_revision" end
    if command.targeted and (command.targetCharacterId == nil or command.targetCharacterId <= 0 or
        command.targetCharacterId > 65535 or command.targetCharacterId % 1 ~= 0) then
        return false, "invalid_target"
    end
    if validCommandKinds[command.kind] ~= true then return false, "unknown_command" end
    if command.parseError ~= nil then return false, "malformed_look" end
    local envelopeBytes = 16 + byteLength(command.clientSessionId) + byteLength(command.operationId) + byteLength(command.kind)
    if envelopeBytes > MAX_PAYLOAD_BYTES then return false, "payload_too_large" end
    if (command.kind == "clear" or command.kind == "forget") and command.hasLook then return false, "unexpected_look" end
    if (command.kind == COMMAND_VISIBILITY or command.kind == COMMAND_ANIMATION or
        command.kind == COMMAND_FOOTSTEP) and
        not command.hasLook then
        return false, "missing_look"
    end
    return true
end

local function resendCurrentState(session, operation)
    local targetId = operation ~= nil and tonumber(operation.targetCharacterId) or nil
    if targetId ~= nil then
        local runtime = activeByCharacterId[targetId]
        if runtime ~= nil and runtime.crewKey ~= nil then
            sendV2State(session.client, session.revision, targetId, true, runtime.look)
            return
        end
        local character = nil
        for _, candidate in ipairs(characterListSnapshot()) do
            if characterEntityId(candidate) == targetId then character = candidate break end
        end
        sendV2State(session.client, session.revision, targetId, false, crewLook(character))
    elseif session.active and session.activeCharacterId ~= nil then
        sendV2State(session.client, session.revision, session.activeCharacterId, true, session.savedLook)
    else
        sendOwnInactiveState(session)
    end
end

Networking.Receive(NET.V2_HELLO, function(message, client)
    local ok, hello, helloReason = pcall(Core.readClientHello, message)
    if not ok or hello == nil then
        warn("Rejected malformed v2 hello: " .. tostring(ok and helloReason or hello))
        return
    end
    local clientSessionId = tostring(hello.clientSessionId or "")
    if byteLength(clientSessionId) == 0 or byteLength(clientSessionId) > MAX_SESSION_ID_BYTES then return end
    if handleGameSessionChange ~= nil then handleGameSessionChange() end
    local session = sessionFor(client)
    if session == nil then return end
    session.protocol = PROTOCOL_VERSION
    bindOperationCache(session, clientSessionId)
    local response = Networking.Start(NET.V2_HELLO)
    local written, writeReason = Core.writeServerHello(
        response,
        math.max(0, session.revision),
        CAPABILITY_ATTACHMENT_VISIBILITY + CAPABILITY_MOVEMENT_ANIMATION_SOURCE +
            CAPABILITY_CREW_TARGETING + CAPABILITY_FOOTSTEP_SOUND_SOURCE +
            CAPABILITY_CREW_DIVING_PROFILES + CAPABILITY_SAVE_WITHOUT_UNEQUIP
    )
    if not written then warn("Could not encode v2 hello response: " .. tostring(writeReason)) return end
    Networking.Send(response, client.Connection)
    sendActiveSnapshot(client)
    sendCrewDivingSnapshot(client)
    sendOwnInactiveState(session)
end)

-- 驗證順序：封包／操作識別 → 重複操作 → revision → 目標權限 → 實際提交。
-- 重複命令必須回傳先前結果；過期 revision 不可重新套用，否則會撤銷較新的清除操作。
local function handleV2Command(message, client, targeted)
    if handleGameSessionChange ~= nil then handleGameSessionChange() end
    local session = sessionFor(client)
    if session == nil then return end
    local wireBytes = messageLengthBytes(message)
    if wireBytes ~= nil and wireBytes > MAX_PAYLOAD_BYTES then
        warn("Rejected an oversized v2 command before decoding (" .. tostring(wireBytes) .. " bytes).")
        return
    end
    local ok, command = pcall(parseV2Command, message, targeted)
    if not ok then
        warn("Rejected a truncated v2 command before its operation ID could be authenticated.")
        return
    end
    session.protocol = PROTOCOL_VERSION
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
        if duplicate.accepted then resendCurrentState(session, duplicate) end
        return
    end
    if command.baseRevision ~= session.revision then
        local result = rememberOperation(session, command.operationId, false, "stale_revision")
        sendV2Ack(session, command.operationId, false, result.reason, result.revision)
        return
    end

    local character, targetReason = clientCharacter(client), nil
    if command.targeted then character, targetReason = resolveCrewTarget(client, command.targetCharacterId) end
    local accepted, reason = false, "character_unavailable"
    if character == nil and targetReason ~= nil then reason = targetReason end
    local runtime = character ~= nil and activeByCharacterId[characterEntityId(character)] or nil
    if runtime ~= nil and runtime.session ~= session and
        (not command.targeted or runtime.crewKey == nil) then
        character = nil
        reason = "target_in_use"
    end
    if command.kind == "save" then
        if character ~= nil then accepted, reason = commitSave(session, character, command.look, command.targeted) end
    elseif command.kind == COMMAND_SAVE_KEEP then
        if character ~= nil then
            accepted, reason = commitSave(session, character, command.look, command.targeted, false)
        end
    elseif command.kind == "apply" then
        local look, lookReason = nil, nil
        if command.hasLook then look, lookReason = canonicalizeLook(command.look, true)
        elseif command.targeted then look = crewLook(character)
        else look = cloneLook(session.savedLook) end
        if character ~= nil and look ~= nil then accepted, reason = commitApply(session, character, look, command.targeted)
        elseif character ~= nil and look == nil then reason = lookReason or "look_unavailable" end
    elseif command.kind == COMMAND_VISIBILITY then
        if character ~= nil or not command.targeted then
            accepted, reason = commitVisualPreference(session, character, command.look, COMMAND_VISIBILITY, command.targeted)
        end
    elseif command.kind == COMMAND_ANIMATION then
        if character ~= nil or not command.targeted then
            accepted, reason = commitVisualPreference(session, character, command.look, COMMAND_ANIMATION, command.targeted)
        end
    elseif command.kind == COMMAND_FOOTSTEP then
        if character ~= nil or not command.targeted then
            accepted, reason = commitVisualPreference(session, character, command.look, COMMAND_FOOTSTEP, command.targeted)
        end
    elseif command.kind == "clear" then
        if character ~= nil or not command.targeted then
            accepted, reason = commitClear(session, character, false, command.targeted)
        end
    elseif command.kind == "forget" then
        if character ~= nil or not command.targeted then
            accepted, reason = commitClear(session, character, true, command.targeted)
        end
    end
    local result = rememberOperation(session, command.operationId, accepted, reason, command)
    sendV2Ack(session, command.operationId, result.accepted, result.reason, result.revision)
end

local function releaseSessionCrewRuntimes(session)
    for _, runtime in pairs(activeByCharacterId) do
        if runtime.session == session and runtime.crewKey ~= nil then
            runtime.session = crewRuntimeSession
        end
    end
end

local function restoreCrewRuntime(character)
    if character == nil or userDataMember(character, "IsHuman") ~= true or
        userDataMember(character, "IsOnPlayerTeam") ~= true or
        userDataMember(character, "IsBot") ~= true or
        userDataMember(character, "IsDead") == true or
        userDataMember(character, "Removed") == true then
        return false
    end
    local key = crewStorageKey(character)
    local record = key ~= nil and persistentCrewRecords[key] or nil
    if record == nil or record.active ~= true or record.look == nil then return false end
    local runtime = activeByCharacterId[characterEntityId(character)]
    if runtime ~= nil and runtime.crewKey == key then return true end
    local look, reason = canonicalizeLook(record.look, true)
    if look == nil then
        record.active = false
        persistCrewLooks()
        warn("Ignored invalid stored crew wardrobe for " .. tostring(record.displayName) .. ": " .. tostring(reason))
        return false
    end
    record.look = cloneLook(look)
    return activateRuntime(crewRuntimeSession, character, look, false, true)
end

restoreCrewRuntimes = function()
    local restored = false
    for _, character in ipairs(characterListSnapshot()) do
        restored = restoreCrewRuntime(character) or restored
    end
    return restored
end

Networking.Receive(NET.V2_COMMAND, function(message, client)
    handleV2Command(message, client, false)
end)

Networking.Receive(NET.V2_TARGET_COMMAND, function(message, client)
    handleV2Command(message, client, true)
end)

Networking.Receive(NET.V2_DIVING_COMMAND, function(message, client)
    local session = sessionFor(client)
    if session == nil or session.protocol ~= PROTOCOL_VERSION then return end
    local wireBytes = messageLengthBytes(message)
    if wireBytes ~= nil and wireBytes > MAX_PAYLOAD_BYTES then return end
    local profile, reason = Core.tryReadDivingProfile(message)
    if profile == nil then
        warn("Rejected malformed crew diving profile: " .. tostring(reason))
        return
    end
    if profile.captured then
        local look
        look, reason = canonicalizeLook(profile.look, true)
        if look == nil then
            warn("Rejected invalid crew diving look: " .. tostring(reason))
            return
        end
        profile.look = look
    end
    local character = resolveCrewTarget(client, profile.characterId)
    if character == nil then return end
    local snapshot = snapshotCrewState(character)
    if snapshot == nil then return end
    setCrewDivingProfile(snapshot, character, profile)
    if not persistCrewOrRollback(snapshot) then return end
    broadcastCrewDivingState(character, crewDivingProfile(character) or {
        mode = 0,
        captured = false,
        look = nil
    })
end)

local function readLegacyApplyLook(message)
    local ok, supplied, look, payloadBytes = pcall(function()
        local hasLook = message.ReadBoolean() == true
        if not hasLook then return false, nil, 1 end
        local raw = {
            schemaVersion = LOOK_SCHEMA_VERSION,
            captured = true,
            hideHair = false,
            attachmentVisibility = Core.attachmentVisibilityFromLegacy(false),
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
    if session.protocol == PROTOCOL_VERSION then
        warn("Ignored a legacy wardrobe command after this connection negotiated protocol " ..
            tostring(PROTOCOL_VERSION) .. ".")
        return false
    end
    session.protocol = 1
    return true
end

Networking.Receive(NET.V1_SAVE_REQUEST, function(_, client)
    local session = sessionFor(client)
    local character = clientCharacter(client)
    if session == nil or character == nil then return end
    if not selectLegacyProtocol(session) then return end
    commitSave(session, character, nil)
end)

Networking.Receive(NET.V1_APPLY_REQUEST, function(message, client)
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

Networking.Receive(NET.V1_CLEAR_REQUEST, function(_, client)
    local session = sessionFor(client)
    if session == nil then return end
    if not selectLegacyProtocol(session) then return end
    commitClear(session, clientCharacter(client), false, false)
end)

Networking.Receive(NET.V1_FORGET_REQUEST, function(_, client)
    local session = sessionFor(client)
    if session == nil then return end
    if not selectLegacyProtocol(session) then return end
    commitClear(session, clientCharacter(client), true, false)
end)

local function clearRoundRuntime()
    activeByCharacterId = {}
    observerRevisionByCharacterId = {}
    for _, session in pairs(sessionsByClient) do
        session.activeCharacterId = nil
        if session.activePersistent ~= true then session.active = false end
    end
end

handleGameSessionChange = function()
    local key = currentGameSessionKey()
    if key == nil then return end
    if lastGameSessionKey == nil then lastGameSessionKey = key return end
    if key == lastGameSessionKey then return end
    lastGameSessionKey = key
    clearRoundRuntime()
    for _, record in pairs(persistentRecords) do
        if record.sessionKey ~= key then record.active = false end
    end
    for _, session in pairs(sessionsByClient) do
        local keepPendingRestore = session.active == true and
            session.activePersistent == true and
            session.persistentSessionKey == key
        if not keepPendingRestore then
            if session.active and not nextRevision(session) then
                warn("Revision exhausted while deactivating a session at a campaign/session boundary.")
            end
            session.active = false
            session.activePersistent = false
            session.persistentSessionKey = nil
            updatePersistentRecord(session)
        end
    end
    persistLooks()
    log("Detected a new campaign/session; retained only matching wardrobe intent.")
end

local function reactivateSession(session)
    if session == nil or not session.active or session.savedLook == nil then return true end
    if session.activePersistent ~= true then
        session.active = false
        session.activeCharacterId = nil
        return true
    end
    local expectedSessionKey = session.persistentSessionKey
    if expectedSessionKey ~= nil then
        local gameSessionKey = currentGameSessionKey()
        if gameSessionKey == nil then return false end
        if gameSessionKey ~= expectedSessionKey then
            if isRuntimeSessionKey(gameSessionKey) and
                not isRuntimeSessionKey(expectedSessionKey) then
                return false
            end
            session.active = false
            session.activePersistent = false
            session.persistentSessionKey = nil
            session.activeCharacterId = nil
            return true
        end
    end
    local character = clientCharacter(session.client)
    if character == nil or characterEntityId(character) <= 0 then return false end
    return activateRuntime(session, character, session.savedLook, true)
end

local function rebindCreatedCharacter(character)
    if character == nil or characterEntityId(character) <= 0 then return false end
    handleGameSessionChange()
    for _, client in ipairs(connectedClients()) do
        if clientCharacter(client) == character then
            local session = sessionFor(client)
            if session ~= nil and session.active and session.activePersistent and session.savedLook ~= nil and
                tonumber(session.activeCharacterId) ~= characterEntityId(character) then
                return activateRuntime(session, character, session.savedLook, true)
            end
            return true
        end
    end
    return restoreCrewRuntime(character)
end

local function scheduleSessionReactivation(session, generation)
    local attempts = 0
    local function attemptReactivation()
        attempts = attempts + 1
        if generation ~= roundReactivationGeneration or
            session == nil or sessionsByClient[session.client] ~= session then
            return
        end
        handleGameSessionChange()
        if reactivateSession(session) or attempts >= 8 then return end
        if Timer ~= nil and Timer.Wait ~= nil then
            Timer.Wait(attemptReactivation, attempts == 1 and 100 or 500)
        end
    end
    attemptReactivation()
end

Hook.Add("client.connected", "barowardrobeswitcher.v2-connected", function(client)
    handleGameSessionChange()
    local session = sessionFor(client)
    scheduleSessionReactivation(session, roundReactivationGeneration)

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
    releaseSessionCrewRuntimes(session)
    clearActiveRuntime(session, true)
    -- Disconnect only clears the runtime binding. The durable account record
    -- already contains the active intent and must not be rewritten from a
    -- transient reconnect session whose Character may not exist yet.
    if session.operationCache ~= nil then session.operationCache.lastTouchedAt = operationCacheNow() end
    sessionsByClient[client] = nil
    pruneOperationCaches()
end)

Hook.Add("character.created", "barowardrobeswitcher.v2-character-created", function(character)
    -- LuaCs may raise character.created just before Client.Character is assigned.
    -- Retry a bounded number of times from this event; never install a frame scan.
    local attempts = 0
    local function attemptRebind()
        attempts = attempts + 1
        local rebound = rebindCreatedCharacter(character)
        local profile = crewDivingProfile(character)
        if profile ~= nil then
            broadcastCrewDivingState(character, profile)
            return
        end
        if rebound then return end
        if attempts >= 3 then return end
        if Timer ~= nil and Timer.Wait ~= nil then
            Timer.Wait(attemptRebind, attempts == 1 and 100 or 500)
        end
    end
    attemptRebind()
end)

Hook.Add("roundStart", "barowardrobeswitcher.v2-round-start", function()
    roundReactivationGeneration = roundReactivationGeneration + 1
    local generation = roundReactivationGeneration
    handleGameSessionChange()
    clearRoundRuntime()
    restoreCrewRuntimes()
    for _, client in ipairs(connectedClients()) do
        scheduleSessionReactivation(sessionFor(client), generation)
        sendCrewDivingSnapshot(client)
    end
end)

Hook.Add("roundEnd", "barowardrobeswitcher.v2-round-end", function()
    roundReactivationGeneration = roundReactivationGeneration + 1
    clearRoundRuntime()
end)

loadPersistence()
loadCrewPersistence()
lastGameSessionKey = currentGameSessionKey()
log("Server authority v" .. tostring(Core.MOD_VERSION) ..
    " loaded (protocol " .. tostring(PROTOCOL_VERSION) ..
    ", look schema " .. tostring(LOOK_SCHEMA_VERSION) ..
    ", persistence " .. tostring(PERSISTENCE_VERSION) .. "). Path: " ..
    tostring(storagePath("ServerLooks.json")))
