local MOD_NAME = "Baro Wardrobe Switcher"
local NET_SAVE_REQUEST = "barowardrobeswitcher.save"
local NET_APPLY_REQUEST = "barowardrobeswitcher.apply"
local NET_CLEAR_REQUEST = "barowardrobeswitcher.clear"
local NET_LOOK_APPLY = "barowardrobeswitcher.look.apply"
local NET_LOOK_CLEAR = "barowardrobeswitcher.look.clear"

if SERVER then return end

local Vector2 = LuaUserData.CreateStatic("Microsoft.Xna.Framework.Vector2", true)
local Color = LuaUserData.CreateStatic("Microsoft.Xna.Framework.Color", true)
local ChatBox = nil
pcall(function()
    ChatBox = LuaUserData.CreateStatic("Barotrauma.ChatBox", true)
end)
local GameMain = nil
pcall(function()
    GameMain = LuaUserData.CreateStatic("Barotrauma.GameMain", true)
end)
local PlayerConnectionChangeType = nil
pcall(function()
    PlayerConnectionChangeType = LuaUserData.CreateEnumTable("Barotrauma.Networking.PlayerConnectionChangeType")
end)
local CharacterInventory = nil
pcall(function()
    CharacterInventory = LuaUserData.CreateStatic("Barotrauma.CharacterInventory", true)
end)
local Entity = nil
pcall(function()
    Entity = LuaUserData.CreateStatic("Barotrauma.Entity", true)
end)
local Item = nil
pcall(function()
    Item = LuaUserData.CreateStatic("Barotrauma.Item", true)
end)
local TextManager = TextManager
pcall(function()
    TextManager = LuaUserData.CreateStatic("Barotrauma.TextManager", true)
end)
local GameSettings = GameSettings
pcall(function()
    GameSettings = LuaUserData.CreateStatic("Barotrauma.GameSettings", true)
end)
local VisualOverride = nil
local visualOverrideFailure = nil
local visualOverrideDiagnostics = nil
local WardrobePersistence = nil
local wardrobePersistenceFailure = nil

local translations = {
    en = {
        ["notice.open_panel"] = "Wardrobe control panel can be opened by pressing F8.",
        ["panel.title"] = "Wardrobe Switcher",
        ["panel.saved_look"] = "Saved look",
        ["panel.look"] = "Look",
        ["panel.active"] = "active",
        ["panel.inactive"] = "inactive",
        ["panel.last"] = "Last",
        ["panel.current"] = "Current",
        ["panel.saved"] = "Saved",
        ["panel.result"] = "Result",
        ["panel.diagnostics"] = "Diagnostics",
        ["panel.character"] = "Character",
        ["panel.debug_log_hint"] = "Debug dump writes to the LuaCs/Barotrauma log; search for [Baro Wardrobe Switcher].",
        ["panel.saved_file"] = "Saved-look file",
        ["button.save"] = "Save Current Outfit",
        ["button.apply"] = "Apply Saved Look",
        ["button.clear"] = "Clear Look",
        ["button.forget"] = "Forget Saved Look",
        ["button.diagnostics"] = "Diagnostics",
        ["button.hide_diagnostics"] = "Hide Diagnostics",
        ["button.dump_debug"] = "Dump Debug Log",
        ["button.close"] = "Close",
        ["slot.head"] = "Head",
        ["slot.headset"] = "Headset",
        ["slot.inner"] = "Inner",
        ["slot.outer"] = "Outer",
        ["slot.bag"] = "Bag",
        ["slot.health"] = "Health",
        ["summary.none"] = "none",
        ["summary.empty"] = "empty outfit",
        ["summary.slot"] = "slot",
        ["summary.slots"] = "slots",
        ["status.ready"] = "Ready.",
        ["status.empty"] = "Empty",
        ["status.already_handled"] = "Already handled",
        ["status.server_removal_requested"] = "Saved; server removal requested",
        ["status.saved_removed"] = "Saved and removed",
        ["status.synced_server"] = "Synced from server",
        ["status.saved_applied_sync"] = "Saved look applied from multiplayer sync.",
        ["status.auto_applied"] = "Saved look auto-applied.",
        ["status.multiplayer_sync_failed"] = "Multiplayer wardrobe sync failed; make sure every client has the fashion items and C# scripting enabled.",
        ["status.still_equipped_in"] = "Still equipped in ",
        ["status.look_cleared_sync"] = "Look cleared from multiplayer sync.",
        ["status.round_ended"] = "Round ended.",
        ["status.next_scene_preserved"] = "Saved look will be reapplied in the next scene.",
        ["status.refreshed"] = "Saved look refreshed for changed equipment.",
        ["status.restored_character"] = "Saved look restored for this character.",
        ["status.apply_again"] = "Saved look needs to be applied again.",
        ["status.character_changed"] = "Controlled character changed. Save a new outfit for this character.",
        ["status.saved_cleared"] = "Saved look cleared.",
        ["status.none"] = "none"
    },
    zh_hans = {
        ["notice.open_panel"] = "按 F8 可打开衣柜控制面板。",
        ["panel.title"] = "衣柜切换器",
        ["panel.saved_look"] = "已保存外观",
        ["panel.look"] = "外观",
        ["panel.active"] = "启用",
        ["panel.inactive"] = "未启用",
        ["panel.last"] = "上次操作",
        ["panel.current"] = "当前",
        ["panel.saved"] = "已保存",
        ["panel.result"] = "结果",
        ["panel.diagnostics"] = "诊断",
        ["panel.character"] = "角色",
        ["panel.debug_log_hint"] = "诊断会写入 LuaCs/Barotrauma 日志；搜索 [Baro Wardrobe Switcher]。",
        ["panel.saved_file"] = "保存外观文件",
        ["button.save"] = "保存当前服装",
        ["button.apply"] = "套用已保存外观",
        ["button.clear"] = "清除外观",
        ["button.forget"] = "忘记已保存外观",
        ["button.diagnostics"] = "诊断",
        ["button.hide_diagnostics"] = "隐藏诊断",
        ["button.dump_debug"] = "输出诊断到日志",
        ["button.close"] = "关闭",
        ["slot.head"] = "头部",
        ["slot.headset"] = "耳机",
        ["slot.inner"] = "内衣",
        ["slot.outer"] = "外衣",
        ["slot.bag"] = "背包",
        ["slot.health"] = "医疗接口",
        ["summary.none"] = "无",
        ["summary.empty"] = "空服装",
        ["summary.slot"] = "个栏位",
        ["summary.slots"] = "个栏位",
        ["status.ready"] = "就绪。",
        ["status.empty"] = "空",
        ["status.already_handled"] = "已处理",
        ["status.server_removal_requested"] = "已保存；已请求服务器移除",
        ["status.saved_removed"] = "已保存并移除",
        ["status.synced_server"] = "已从服务器同步",
        ["status.saved_applied_sync"] = "已从多人同步套用保存的外观。",
        ["status.auto_applied"] = "已自动套用保存的外观。",
        ["status.multiplayer_sync_failed"] = "多人衣柜同步失败；请确认每位客户端都有这些时装物品并已启用 C# 脚本。",
        ["status.still_equipped_in"] = "仍装备于 ",
        ["status.look_cleared_sync"] = "外观已由多人同步清除。",
        ["status.round_ended"] = "回合结束。",
        ["status.next_scene_preserved"] = "保存的外观会在下一个场景重新套用。",
        ["status.refreshed"] = "装备改变，已刷新保存的外观。",
        ["status.restored_character"] = "已恢复此角色保存的外观。",
        ["status.apply_again"] = "保存的外观需要重新套用。",
        ["status.character_changed"] = "控制角色已改变。请为此角色保存新的服装。",
        ["status.saved_cleared"] = "已清除保存的外观。",
        ["status.none"] = "无"
    },
    zh_hant = {
        ["notice.open_panel"] = "按 F8 可開啟衣櫃控制面板。",
        ["panel.title"] = "衣櫃切換器",
        ["panel.saved_look"] = "已儲存外觀",
        ["panel.look"] = "外觀",
        ["panel.active"] = "啟用",
        ["panel.inactive"] = "未啟用",
        ["panel.last"] = "上次操作",
        ["panel.current"] = "目前",
        ["panel.saved"] = "已儲存",
        ["panel.result"] = "結果",
        ["panel.diagnostics"] = "診斷",
        ["panel.character"] = "角色",
        ["panel.debug_log_hint"] = "診斷會寫入 LuaCs/Barotrauma 日誌；搜尋 [Baro Wardrobe Switcher]。",
        ["panel.saved_file"] = "儲存外觀檔案",
        ["button.save"] = "儲存目前服裝",
        ["button.apply"] = "套用已儲存外觀",
        ["button.clear"] = "清除外觀",
        ["button.forget"] = "忘記已儲存外觀",
        ["button.diagnostics"] = "診斷",
        ["button.hide_diagnostics"] = "隱藏診斷",
        ["button.dump_debug"] = "輸出診斷到日誌",
        ["button.close"] = "關閉",
        ["slot.head"] = "頭部",
        ["slot.headset"] = "耳機",
        ["slot.inner"] = "內衣",
        ["slot.outer"] = "外衣",
        ["slot.bag"] = "背包",
        ["slot.health"] = "醫療介面",
        ["summary.none"] = "無",
        ["summary.empty"] = "空服裝",
        ["summary.slot"] = "個欄位",
        ["summary.slots"] = "個欄位",
        ["status.ready"] = "就緒。",
        ["status.empty"] = "空",
        ["status.already_handled"] = "已處理",
        ["status.server_removal_requested"] = "已儲存；已要求伺服器移除",
        ["status.saved_removed"] = "已儲存並移除",
        ["status.synced_server"] = "已從伺服器同步",
        ["status.saved_applied_sync"] = "已從多人同步套用儲存外觀。",
        ["status.auto_applied"] = "已自動套用儲存外觀。",
        ["status.multiplayer_sync_failed"] = "多人衣櫃同步失敗；請確認每位客戶端都有這些時裝物品並已啟用 C# 腳本。",
        ["status.still_equipped_in"] = "仍裝備於 ",
        ["status.look_cleared_sync"] = "外觀已由多人同步清除。",
        ["status.round_ended"] = "回合結束。",
        ["status.next_scene_preserved"] = "儲存外觀會在下一個場景重新套用。",
        ["status.refreshed"] = "裝備改變，已重新套用儲存外觀。",
        ["status.restored_character"] = "已恢復此角色儲存外觀。",
        ["status.apply_again"] = "儲存外觀需要重新套用。",
        ["status.character_changed"] = "控制角色已改變。請為此角色儲存新的服裝。",
        ["status.saved_cleared"] = "已清除儲存的外觀。",
        ["status.none"] = "無"
    }
}

local statusKeys = {
    ["Ready."] = "status.ready",
    ["Empty"] = "status.empty",
    ["Already handled"] = "status.already_handled",
    ["Saved; server removal requested"] = "status.server_removal_requested",
    ["Saved and removed"] = "status.saved_removed",
    ["Synced from server"] = "status.synced_server",
    ["Saved look applied from multiplayer sync."] = "status.saved_applied_sync",
    ["Saved look auto-applied."] = "status.auto_applied",
    ["Multiplayer wardrobe sync failed; make sure every client has the fashion items and C# scripting enabled."] = "status.multiplayer_sync_failed",
    ["Look cleared from multiplayer sync."] = "status.look_cleared_sync",
    ["Round ended."] = "status.round_ended",
    ["Saved look will be reapplied in the next scene."] = "status.next_scene_preserved",
    ["Saved look refreshed for changed equipment."] = "status.refreshed",
    ["Saved look restored for this character."] = "status.restored_character",
    ["Saved look needs to be applied again."] = "status.apply_again",
    ["Controlled character changed. Save a new outfit for this character."] = "status.character_changed",
    ["Saved look cleared."] = "status.saved_cleared"
}

local function normalizeLanguage(value)
    if value == nil then return nil end
    local text = tostring(value):lower()
    if text:find("traditional", 1, true) or text:find("tchinese", 1, true) or
        text:find("zh%-hant") or text:find("zh_hant", 1, true) or
        text:find("zhtw", 1, true) or text:find("zh%-tw") or
        text:find("繁", 1, true) or text:find("語言", 1, true) then
        return "zh_hant"
    end
    if text:find("simplified", 1, true) or text:find("schinese", 1, true) or
        text:find("zh%-hans") or text:find("zh_hans", 1, true) or
        text:find("zhcn", 1, true) or text:find("zh%-cn") or
        text:find("简", 1, true) or text:find("语言", 1, true) then
        return "zh_hans"
    end
    if text == "chinese" or text == "中文" then
        return "zh_hant"
    end
    if text == "english" or text == "en" or text:find("english", 1, true) then
        return "en"
    end
    return nil
end

local function languageFromCandidate(getter)
    local ok, value = pcall(getter)
    if not ok or value == nil then return nil end
    return normalizeLanguage(value)
end

local function currentLanguage()
    local candidates = {
        function() return TextManager ~= nil and TextManager.CurrentLanguage or nil end,
        function() return TextManager ~= nil and TextManager.Language or nil end,
        function() return TextManager ~= nil and TextManager.SelectedLanguage or nil end,
        function() return GameSettings ~= nil and GameSettings.CurrentConfig ~= nil and GameSettings.CurrentConfig.Language or nil end,
        function() return GameSettings ~= nil and GameSettings.CurrentConfig ~= nil and GameSettings.CurrentConfig.SelectedLanguage or nil end,
        function() return TextManager ~= nil and TextManager.Get ~= nil and TextManager.Get("language") or nil end
    }

    for _, getter in ipairs(candidates) do
        local language = languageFromCandidate(getter)
        if language ~= nil then return language end
    end
    return "en"
end

local function tr(key, fallback)
    local language = currentLanguage()
    local localized = translations[language] ~= nil and translations[language][key] or nil
    if localized ~= nil then return localized end
    localized = translations.en[key]
    if localized ~= nil then return localized end
    return fallback or key
end

local function localizedStatus(value)
    local text = tostring(value)
    local key = statusKeys[text]
    if key ~= nil then return tr(key, text) end
    local stillEquippedPrefix = "Still equipped in "
    if text:sub(1, #stillEquippedPrefix) == stillEquippedPrefix then
        return tr("status.still_equipped_in") .. text:sub(#stillEquippedPrefix + 1)
    end
    return text
end

local function slotLabel(entry)
    return tr(entry.labelKey, entry.label)
end

local slots = {
    { key = "Head", label = "Head", labelKey = "slot.head", slot = InvSlotType.Head },
    { key = "Headset", label = "Headset", labelKey = "slot.headset", slot = InvSlotType.Headset },
    { key = "InnerClothes", label = "Inner", labelKey = "slot.inner", slot = InvSlotType.InnerClothes },
    { key = "OuterClothes", label = "Outer", labelKey = "slot.outer", slot = InvSlotType.OuterClothes },
    { key = "Bag", label = "Bag", labelKey = "slot.bag", slot = InvSlotType.Bag },
    { key = "HealthInterface", label = "Health", labelKey = "slot.health", slot = InvSlotType.HealthInterface }
}

local visualCarrierPriority = {
    InnerClothes = 1,
    OuterClothes = 2,
    Head = 3,
    Bag = 4,
    Headset = 5,
    HealthInterface = 6
}

local savedLook = {}
local savedLookCaptured = false
local activeLook = false
local autoApplyLook = false
local characterStates = {}
local lastOperation = "Ready."
local diagnosticsVisible = false
local lastEquipmentSignature = nil
local slotResults = {}
local lastNetworkApplyDiagnostics = {}
local window = nil
local overlayRoot = nil
local lastCharacter = nil
local buildWindow
local toggleWindow
local fullPanelOpen = false
local unequipItem
local isInSlot
local getSlotItem
local isInAnyWearableSlot
local roundStartNoticeSent = false
local lastServerAutoApplySignature = nil
local globalTick = 0
local initialEquipGateActive = false
local initialEquipGateStartedTick = 0
local initialEquipGateLastEquipTick = 0
local initialEquipGateSeenEquip = false
local initialEquipGateSignature = nil
local initialEquipGateStableTicks = 0
local initialEquipGateCharacterKey = nil
local initialEquipGateLastStatusTick = 0
local pendingRoundStartNetworkLook = nil
local pendingRoundStartNetworkCharacterKey = nil
local clientPersistPathCache = nil
local lastSessionKey = nil
local persistentClientLookLoaded = false
local persistClientLook
local clearPersistentClientLook
local ensureWardrobePersistence

local InitialEquipStableTicks = 12
local InitialEquipFallbackTicks = 120

local function copyLookData(lookData)
    local copy = {}
    lookData = lookData or {}
    for _, entry in ipairs(slots) do
        local slotState = lookData[entry.key]
        if slotState ~= nil then
            copy[entry.key] = {
                identifier = tostring(slotState.identifier or ""),
                itemId = tonumber(slotState.itemId) or 0,
                name = tostring(slotState.name or ""),
                slot = entry.key
            }
        end
    end
    return copy
end

local function lookDataHasSavedLook(lookData, captured)
    if captured == true then return true end
    lookData = lookData or {}
    for _, entry in ipairs(slots) do
        if lookData[entry.key] ~= nil then return true end
    end
    return false
end

local function characterStateKey(character)
    if character == nil then return nil end
    local ok, id = pcall(function()
        return character.ID
    end)
    if ok and id ~= nil and tonumber(id) ~= nil and tonumber(id) > 0 then
        return tostring(id)
    end
    ok, id = pcall(function()
        return character.Name
    end)
    if ok and id ~= nil and tostring(id) ~= "" then
        return tostring(id)
    end
    return tostring(character)
end

local function saveCharacterState(character)
    local key = characterStateKey(character)
    if key == nil then return end
    characterStates[key] = {
        savedLook = copyLookData(savedLook),
        savedLookCaptured = savedLookCaptured,
        activeLook = activeLook,
        autoApplyLook = autoApplyLook,
        lastEquipmentSignature = lastEquipmentSignature,
        slotResults = slotResults,
        lastNetworkApplyDiagnostics = lastNetworkApplyDiagnostics
    }
end

local function loadCharacterState(character)
    local key = characterStateKey(character)
    local state = key ~= nil and characterStates[key] or nil
    if state == nil or not lookDataHasSavedLook(state.savedLook, state.savedLookCaptured) then
        activeLook = false
        lastEquipmentSignature = nil
        lastNetworkApplyDiagnostics = {}
        if lookDataHasSavedLook(savedLook, savedLookCaptured) then
            return false
        end
        savedLook = {}
        savedLookCaptured = false
        autoApplyLook = false
        slotResults = {}
        return false
    end
    savedLook = copyLookData(state.savedLook)
    savedLookCaptured = state.savedLookCaptured == true
    activeLook = state.activeLook == true
    autoApplyLook = state.autoApplyLook == true
    lastEquipmentSignature = state.lastEquipmentSignature
    slotResults = state.slotResults or {}
    lastNetworkApplyDiagnostics = state.lastNetworkApplyDiagnostics or {}
    return true
end

local function log(message)
    local line = "[" .. MOD_NAME .. "] " .. tostring(message)
    lastOperation = tostring(message)
    if LuaCsLogger ~= nil and LuaCsLogger.Log ~= nil then
        LuaCsLogger.Log(line)
    else
        print(line)
    end
end

local function debugLog(message)
    local line = "[" .. MOD_NAME .. " DEBUG] " .. tostring(message)
    if LuaCsLogger ~= nil and LuaCsLogger.Log ~= nil then
        LuaCsLogger.Log(line)
    else
        print(line)
    end
end

local function clientPersistPath()
    if clientPersistPathCache ~= nil then return clientPersistPathCache end

    local source = nil
    pcall(function()
        if debug ~= nil and debug.getinfo ~= nil then
            local info = debug.getinfo(1, "S")
            source = info ~= nil and info.source or nil
        end
    end)

    if source ~= nil then
        source = tostring(source):gsub("^@", ""):gsub("\\", "/")
        local root = source:match("^(.*)/Lua/WardrobeSwitcher%.lua$")
        if root ~= nil and root ~= "" then
            clientPersistPathCache = root .. "/PersistentClientLook.txt"
            return clientPersistPathCache
        end
    end

    clientPersistPathCache = "PersistentClientLook.txt"
    return clientPersistPathCache
end

local function escapePersistentValue(value)
    return tostring(value or "")
        :gsub("%%", "%%25")
        :gsub("|", "%%7C")
        :gsub(",", "%%2C")
        :gsub("=", "%%3D")
        :gsub("\r", "%%0D")
        :gsub("\n", "%%0A")
end

local function unescapePersistentValue(value)
    return tostring(value or "")
        :gsub("%%0A", "\n")
        :gsub("%%0D", "\r")
        :gsub("%%3D", "=")
        :gsub("%%2C", ",")
        :gsub("%%7C", "|")
        :gsub("%%25", "%%")
end

local function userDataMember(object, name)
    if object == nil or name == nil then return nil end
    local ok, value = pcall(function()
        return object[name]
    end)
    if ok then return value end
    return nil
end

local function normalizedSessionValue(value)
    if value == nil then return nil end
    local text = tostring(value):gsub("\\", "/")
    if text == "" or text == "nil" or text == "null" then return nil end
    return text
end

local function firstSessionValue(object, names)
    for _, name in ipairs(names) do
        local value = normalizedSessionValue(userDataMember(object, name))
        if value ~= nil then return value end
    end
    return nil
end

local function currentSessionKey()
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

local function encodePersistentClientLook()
    local parts = {
        "captured=" .. tostring(savedLookCaptured == true),
        "active=" .. tostring(activeLook == true),
        "auto=" .. tostring(autoApplyLook == true)
    }
    local sessionKey = currentSessionKey()
    if sessionKey ~= nil then
        parts[#parts + 1] = "session=" .. escapePersistentValue(sessionKey)
    end
    for _, entry in ipairs(slots) do
        local slotState = savedLook[entry.key]
        if slotState ~= nil then
            parts[#parts + 1] =
                entry.key ..
                "=" ..
                escapePersistentValue(slotState.identifier or "") ..
                "," ..
                escapePersistentValue(slotState.name or "")
        end
    end
    return table.concat(parts, "|")
end

local function readLegacyPersistentClientLookLine()
    local path = clientPersistPath()
    local file = io.open(path, "r")
    if file == nil then return false end

    local line = file:read("*l")
    file:close()
    if line == nil or tostring(line) == "" then return false end
    return tostring(line), path
end

local function restorePersistentClientLookLine(line, source)
    local restoredLook = {}
    local captured = false
    local active = false
    local auto = false
    local restoredSessionKey = nil
    for part in tostring(line):gmatch("[^|]+") do
        local name, value = part:match("^([^=]+)=(.*)$")
        if name == "captured" then
            captured = value == "true"
        elseif name == "active" then
            active = value == "true"
        elseif name == "auto" then
            auto = value == "true"
        elseif name == "session" then
            restoredSessionKey = unescapePersistentValue(value)
        elseif name ~= nil then
            local identifier, displayName = tostring(value):match("^([^,]*),(.*)$")
            if identifier ~= nil then
                restoredLook[name] = {
                    identifier = unescapePersistentValue(identifier),
                    itemId = 0,
                    name = unescapePersistentValue(displayName or ""),
                    slot = name
                }
            end
        end
    end

    local sessionKey = currentSessionKey()
    if sessionKey == nil then
        return false
    end
    if restoredSessionKey == nil or restoredSessionKey == "" then
        persistentClientLookLoaded = true
        debugLog("Ignored persistent client wardrobe look without a session key from " .. tostring(source or "C# persistence") .. ".")
        return false
    end
    if restoredSessionKey ~= sessionKey then
        persistentClientLookLoaded = true
        debugLog("Ignored persistent client wardrobe look for another session from " .. tostring(source or "C# persistence") .. ".")
        return false
    end

    if not lookDataHasSavedLook(restoredLook, captured) then return false end
    savedLook = copyLookData(restoredLook)
    persistentClientLookLoaded = true
    savedLookCaptured = true
    activeLook = false
    autoApplyLook = active == true or auto == true
    lastEquipmentSignature = nil
    lastServerAutoApplySignature = nil
    slotResults = {}
    for _, entry in ipairs(slots) do
        slotResults[entry.key] = savedLook[entry.key] ~= nil and "Saved look needs to be applied again." or "Empty"
    end
    lastOperation = autoApplyLook and "Saved look will be reapplied in the next scene." or "Saved look needs to be applied again."
    debugLog("Loaded persistent client wardrobe look from " .. tostring(source or "C# persistence") .. ".")
    return true
end

persistClientLook = function()
    if not lookDataHasSavedLook(savedLook, savedLookCaptured) then
        return false
    end
    if currentSessionKey() == nil then
        debugLog("Skipped persistent client wardrobe write because no game session key is available.")
        return false
    end

    local encoded = encodePersistentClientLook()
    local persistence = ensureWardrobePersistence()
    if persistence ~= nil then
        local ok, saved = pcall(function()
            return persistence.SaveClientLook(encoded)
        end)
        if ok and saved == true then
            return true
        end
        debugLog("C# wardrobe persistence write failed; saved look remains in memory for this session. " .. tostring(ok and saved or wardrobePersistenceFailure))
    end

    return false
end

clearPersistentClientLook = function()
    local cleared = false
    local persistence = ensureWardrobePersistence()
    if persistence ~= nil then
        local ok, result = pcall(function()
            return persistence.ClearClientLook()
        end)
        cleared = ok and result == true
    end
    return cleared
end

local function loadPersistentClientLook()
    if currentSessionKey() == nil then
        return false
    end

    local persistence = ensureWardrobePersistence()
    if persistence ~= nil then
        local ok, line = pcall(function()
            return persistence.LoadClientLook()
        end)
        if ok and line ~= nil and tostring(line) ~= "" then
            return restorePersistentClientLookLine(tostring(line), "C# persistence")
        end
        if ok then
            local existsOk, exists = pcall(function()
                return persistence.ClientLookFileExists()
            end)
            if existsOk and exists == true then
                persistentClientLookLoaded = true
                return false
            end
        end
    end

    local legacyLine, legacyPath = readLegacyPersistentClientLookLine()
    if legacyLine == false then
        if persistence ~= nil then
            persistentClientLookLoaded = true
        end
        return false
    end
    local restored = restorePersistentClientLookLine(legacyLine, legacyPath)
    if restored then
        persistClientLook()
    end
    return restored
end

local function addChatLine(text)
    local chatType = ChatMessageType.ServerMessageBoxInGame or ChatMessageType.MessageBox
    local changeType = PlayerConnectionChangeType ~= nil and PlayerConnectionChangeType.None or nil
    if GameMain ~= nil and GameMain.Client ~= nil then
        local ok = pcall(function()
            GameMain.Client.AddChatMessage(tostring(text), chatType, MOD_NAME, nil, nil, changeType, Color.Cyan)
        end)
        if ok then return true end
    end

    local ok, sent = pcall(function()
        if ChatBox == nil then return false end
        local chatBox = ChatBox.GetChatBox()
        if chatBox == nil then return false end
        local message = ChatMessage.Create(MOD_NAME, tostring(text), chatType, nil, nil, changeType, Color.Cyan)
        chatBox.AddMessage(message)
        return true
    end)
    if ok and sent == true then return true end

    log(text)
    return false
end

local function sendRoundStartNotice()
    if roundStartNoticeSent then return end
    roundStartNoticeSent = true
    addChatLine(tr("notice.open_panel"))
end

local function ensureVisualOverride()
    if VisualOverride ~= nil then return VisualOverride end

    visualOverrideFailure = nil
    local diagnostics = {}

    local function diag(message)
        diagnostics[#diagnostics + 1] = tostring(message)
    end

    if PluginPackageManager ~= nil and PluginPackageManager.LuaTryRegisterPackageTypes ~= nil then
        pcall(function()
            diag("AssembliesLoaded=" .. tostring(PluginPackageManager.AssembliesLoaded))
            diag("PluginsLoaded=" .. tostring(PluginPackageManager.PluginsLoaded))
        end)
        local okRegisterDisplay, registerDisplay = pcall(function()
            return PluginPackageManager.LuaTryRegisterPackageTypes("Baro Wardrobe Switcher", false)
        end)
        diag("RegisterDisplay=" .. tostring(okRegisterDisplay and registerDisplay))
        local okRegisterAssembly, registerAssembly = pcall(function()
            return PluginPackageManager.LuaTryRegisterPackageTypes("BaroWardrobeSwitcher", false)
        end)
        diag("RegisterAssembly=" .. tostring(okRegisterAssembly and registerAssembly))
    else
        diag("PluginPackageManager unavailable")
    end

    local okRegisterType, registerTypeError = pcall(function()
        LuaUserData.RegisterType("BaroWardrobeSwitcher.VisualOverride")
    end)
    diag("RegisterType=" .. tostring(okRegisterType))
    if not okRegisterType then
        diag("RegisterTypeError=" .. tostring(registerTypeError))
    end

    local ok, result = pcall(function()
        VisualOverride = LuaUserData.CreateStatic("BaroWardrobeSwitcher.VisualOverride", true)
    end)
    if not ok then
        VisualOverride = nil
        visualOverrideFailure = tostring(result)
    end

    visualOverrideDiagnostics = table.concat(diagnostics, " ")
    return VisualOverride
end

ensureWardrobePersistence = function()
    if WardrobePersistence ~= nil then return WardrobePersistence end

    wardrobePersistenceFailure = nil
    pcall(function()
        if PluginPackageManager ~= nil and PluginPackageManager.LuaTryRegisterPackageTypes ~= nil then
            PluginPackageManager.LuaTryRegisterPackageTypes("Baro Wardrobe Switcher", false)
            PluginPackageManager.LuaTryRegisterPackageTypes("BaroWardrobeSwitcher", false)
        end
    end)

    pcall(function()
        LuaUserData.RegisterType("BaroWardrobeSwitcher.WardrobePersistence")
    end)

    local ok, result = pcall(function()
        return LuaUserData.CreateStatic("BaroWardrobeSwitcher.WardrobePersistence", true)
    end)
    if ok then
        WardrobePersistence = result
    else
        WardrobePersistence = nil
        wardrobePersistenceFailure = tostring(result)
    end
    return WardrobePersistence
end

local function visualOverrideState()
    local override = ensureVisualOverride()
    if override == nil then
        local details = "C# visual override unavailable; check LuaCs C# compile/load log and reload."
        if CSActive ~= nil then
            details = details .. " CSActive=" .. tostring(CSActive) .. "."
        end
        if visualOverrideFailure ~= nil then
            details = details .. " Lua error: " .. visualOverrideFailure
        end
        if visualOverrideDiagnostics ~= nil then
            details = details .. " Diagnostics: " .. visualOverrideDiagnostics
        end
        return {
            ready = false,
            label = "C#: unavailable",
            details = details
        }
    end

    local ok, ready = pcall(function()
        return override.IsReady()
    end)
    local statusOk, status = pcall(function()
        return override.GetReadinessStatus()
    end)
    local details = statusOk and status ~= nil and tostring(status) or nil
    if not ok or ready ~= true then
        return {
            ready = false,
            label = details ~= nil and ("C#: " .. details) or "C#: not ready",
            details = details or "C# visual override loaded but did not report ready."
        }
    end
    return {
        ready = true,
        label = details ~= nil and ("C#: " .. details) or "C#: ready",
        details = details
    }
end

local function visualOverrideStatus()
    local state = visualOverrideState()
    if state.ready then return nil end
    return "C# visual override is not ready. Enable C# scripting in LuaCs, accept this mod's C# prompt, then reload."
end

local function visualOverrideDebugStatus(character)
    local override = ensureVisualOverride()
    if override == nil or character == nil then return nil end
    local ok, result = pcall(function()
        return override.GetCharacterDebugStatus(character)
    end)
    if ok and result ~= nil then
        return tostring(result)
    end
    return nil
end

local function controlled()
    return Character.Controlled
end

local function isMultiplayerClient()
    return CLIENT == true and Game ~= nil and Game.IsMultiplayer == true
end

local function ensureOverlayRoot()
    if overlayRoot ~= nil then return overlayRoot end

    local ok, root = pcall(function()
        return GUI.Frame(GUI.RectTransform(Vector2(1.0, 1.0)), nil)
    end)
    if not ok then
        log("Overlay root failed to build: " .. tostring(root))
        return nil
    end

    overlayRoot = root
    pcall(function() overlayRoot.CanBeFocused = false end)
    return overlayRoot
end

local function overlayParent()
    local root = ensureOverlayRoot()
    if root == nil then return nil end
    return root.RectTransform
end

local function drawOverlay()
    if overlayRoot == nil then return end
    pcall(function() overlayRoot.AddToGUIUpdateList() end)
end

local function resetOverlay()
    if overlayRoot ~= nil then
        pcall(function() overlayRoot.Remove() end)
    end
    overlayRoot = nil
    window = nil
end

local function itemName(item)
    if item == nil then return "-" end
    if type(item) == "table" then
        if item.name ~= nil then return tostring(item.name) end
        if item.identifier ~= nil then return tostring(item.identifier) end
    end
    local prefab = item.Prefab
    if prefab == nil then return tostring(item) end
    if prefab.Name ~= nil then return tostring(prefab.Name) end
    if prefab.Identifier ~= nil then return tostring(prefab.Identifier) end
    return tostring(item)
end

local function itemIdentifier(item)
    if item == nil or item.Prefab == nil or item.Prefab.Identifier == nil then return nil end
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

local function findEntityById(id)
    if Entity == nil or id == nil or id <= 0 then return nil end
    local ok, entity = pcall(function()
        return Entity.FindEntityByID(id)
    end)
    if ok then return entity end
    return nil
end

local function collectionContains(collection, value)
    if collection == nil or value == nil then return false end
    local ok, result = pcall(function()
        return collection.Contains(value)
    end)
    if ok then return result == true end
    pcall(function()
        for entry in collection do
            if entry == value then result = true end
        end
    end)
    return result == true
end

local function itemBelongsToCharacter(character, item)
    if character == nil or item == nil then return false end
    if isInAnyWearableSlot(character, item) then return true end
    if character.Inventory ~= nil then
        local ok, allItems = pcall(function()
            return character.Inventory.AllItems
        end)
        if ok and collectionContains(allItems, item) then return true end
        local parentOk, parentInventory = pcall(function()
            return item.ParentInventory
        end)
        if parentOk and parentInventory == character.Inventory then return true end
    end
    return false
end

local function findItemByIdentifier(character, identifier)
    if character == nil or identifier == nil or identifier == "" then return nil end
    for _, entry in ipairs(slots) do
        local item = getSlotItem(character, entry.slot)
        if item ~= nil and itemIdentifier(item) == identifier then return item end
    end
    if character.Inventory ~= nil then
        local ok, allItems = pcall(function()
            return character.Inventory.AllItems
        end)
        if ok and allItems ~= nil then
            pcall(function()
                for item in allItems do
                    if itemIdentifier(item) == identifier then
                        ok = item
                        return
                    end
                end
            end)
            if ok ~= true and ok ~= false and ok ~= nil then return ok end
        end
    end
    if Item ~= nil and Item.ItemList ~= nil then
        local found = nil
        pcall(function()
            for item in Item.ItemList do
                if itemIdentifier(item) == identifier and itemBelongsToCharacter(character, item) then
                    found = item
                    return
                end
            end
        end)
        if found ~= nil then return found end
    end
    return nil
end

local function itemStableId(item)
    if item == nil then return "-" end
    local id = itemIdentifier(item) or itemName(item)
    local runtimeId = nil
    pcall(function()
        runtimeId = item.ID
    end)
    if runtimeId ~= nil then
        return tostring(id) .. "#" .. tostring(runtimeId)
    end
    return tostring(id)
end

local function hasSavedLook()
    return lookDataHasSavedLook(savedLook, savedLookCaptured)
end

local function stateHasSavedLook(state)
    if state == nil then return false end
    return lookDataHasSavedLook(state.savedLook, state.savedLookCaptured)
end

local function preserveSceneTransitionLookIntent()
    local shouldReapplyCurrentLook = hasSavedLook() and (activeLook or autoApplyLook)
    if shouldReapplyCurrentLook then
        autoApplyLook = true
        activeLook = false
        lastEquipmentSignature = nil
        lastServerAutoApplySignature = nil
    end

    for _, state in pairs(characterStates) do
        if stateHasSavedLook(state) and (state.activeLook == true or state.autoApplyLook == true) then
            state.activeLook = false
            state.autoApplyLook = true
            state.lastEquipmentSignature = nil
        else
            state.activeLook = false
            state.lastEquipmentSignature = nil
        end
    end

    if hasSavedLook() then
        persistClientLook()
    end

    return shouldReapplyCurrentLook
end

local function savedLookSummary()
    if not hasSavedLook() then return tr("summary.none") end
    local count = 0
    for _, entry in ipairs(slots) do
        if savedLook[entry.key] ~= nil then
            count = count + 1
        end
    end
    if count == 0 then return tr("summary.empty") end
    local slotKey = count == 1 and "summary.slot" or "summary.slots"
    if currentLanguage() == "en" then
        return tostring(count) .. " " .. tr(slotKey)
    end
    return tostring(count) .. " " .. tr(slotKey)
end

getSlotItem = function(character, slot)
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

isInSlot = function(character, item, slot)
    if character == nil or character.Inventory == nil or item == nil then return false end
    local ok, result = pcall(function()
        return character.Inventory.IsInLimbSlot(item, slot)
    end)
    if ok then return result == true end
    return getSlotItem(character, slot) == item
end

local function wornSlotLabelsForItem(character, item)
    local labels = {}
    if character == nil or item == nil then return labels end
    for _, entry in ipairs(slots) do
        if isInSlot(character, item, entry.slot) then
            labels[#labels + 1] = slotLabel(entry)
        end
    end
    return labels
end

isInAnyWearableSlot = function(character, item)
    return #wornSlotLabelsForItem(character, item) > 0
end

local function equipmentSignature(character)
    if character == nil then return "no-character" end
    local parts = {}
    for _, entry in ipairs(slots) do
        parts[#parts + 1] = entry.key .. "=" .. itemStableId(getSlotItem(character, entry.slot))
    end
    return table.concat(parts, ";")
end

local function resetInitialEquipGate()
    initialEquipGateActive = false
    initialEquipGateStartedTick = 0
    initialEquipGateLastEquipTick = 0
    initialEquipGateSeenEquip = false
    initialEquipGateSignature = nil
    initialEquipGateStableTicks = 0
    initialEquipGateCharacterKey = nil
    initialEquipGateLastStatusTick = 0
end

local function startInitialEquipGate()
    initialEquipGateActive = true
    initialEquipGateStartedTick = globalTick
    initialEquipGateLastEquipTick = 0
    initialEquipGateSeenEquip = false
    initialEquipGateSignature = nil
    initialEquipGateStableTicks = 0
    initialEquipGateCharacterKey = nil
    initialEquipGateLastStatusTick = 0
end

local function currentSessionRunning()
    if GameMain == nil then return false end
    local ok, session = pcall(function()
        return GameMain.GameSession
    end)
    if not ok or session == nil then return false end
    local runningOk, running = pcall(function()
        return session.IsRunning
    end)
    if runningOk and running ~= true then return false end
    local endingOk, ending = pcall(function()
        return session.RoundEnding
    end)
    if endingOk and ending == true then return false end
    return true
end

local function initialEquipGateReady(character)
    if not initialEquipGateActive then return true end
    if character == nil or not currentSessionRunning() then return false end

    local key = characterStateKey(character)
    if initialEquipGateCharacterKey ~= key then
        initialEquipGateCharacterKey = key
        initialEquipGateSignature = nil
        initialEquipGateStableTicks = 0
        initialEquipGateSeenEquip = false
        initialEquipGateLastEquipTick = 0
    end

    local signature = equipmentSignature(character)
    if signature == initialEquipGateSignature then
        initialEquipGateStableTicks = initialEquipGateStableTicks + 1
    else
        initialEquipGateSignature = signature
        initialEquipGateStableTicks = 0
    end

    local waitedTicks = globalTick - initialEquipGateStartedTick
    local quietAfterEquip = initialEquipGateSeenEquip and (globalTick - initialEquipGateLastEquipTick >= InitialEquipStableTicks)
    local stable = initialEquipGateStableTicks >= InitialEquipStableTicks
    local fallbackStable = waitedTicks >= InitialEquipFallbackTicks and stable

    if (quietAfterEquip and stable) or fallbackStable then
        resetInitialEquipGate()
        return true
    end

    if globalTick - initialEquipGateLastStatusTick >= 60 then
        initialEquipGateLastStatusTick = globalTick
        lastOperation = "Waiting for initial equipment to finish equipping before applying saved look."
    end
    return false
end

unequipItem = function(character, item)
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

local function snapshot(character)
    local data = {}
    for _, entry in ipairs(slots) do
        local item = getSlotItem(character, entry.slot)
        data[entry.key] = isIgnoredWardrobeItem(item) and nil or item
    end
    return data
end

local function clearVisualOverride(character)
    if ensureVisualOverride() == nil then return end
    pcall(function()
        VisualOverride.ClearCharacter(character)
    end)
end

local function clearAllVisualOverrides()
    if ensureVisualOverride() == nil then return end
    pcall(function()
        VisualOverride.ClearAll()
    end)
end

local function restoreItemVisuals(character)
    if ensureVisualOverride() == nil then return end
    if character ~= nil then
        local ok = pcall(function()
            VisualOverride.RestoreCharacterItemVisuals(character)
        end)
        if ok then return end
    end
    pcall(function()
        VisualOverride.RestoreItemVisuals()
    end)
end

local function pruneVisualOverrides()
    if ensureVisualOverride() == nil then return end
    pcall(function()
        VisualOverride.PruneStaleCharacters()
    end)
end

local function captureVisualOverride(character, item)
    if ensureVisualOverride() == nil or character == nil or item == nil then return 0 end
    local ok, count = pcall(function()
        return VisualOverride.CaptureFashionItem(character, item)
    end)
    if ok and count ~= nil then return count end
    return 0
end

local function captureVisualOverridePrefab(character, identifier)
    if ensureVisualOverride() == nil or character == nil or identifier == nil or identifier == "" then return 0 end
    local ok, count = pcall(function()
        return VisualOverride.CaptureFashionPrefab(character, tostring(identifier))
    end)
    if ok and count ~= nil then return count end
    return 0
end

local function captureEmptyVisualOverride(character)
    if ensureVisualOverride() == nil or character == nil then return false end
    local ok, result = pcall(function()
        return VisualOverride.CaptureEmptyFashion(character)
    end)
    return ok and result == true
end

local function setFashionSlotMask(character, lookData)
    if ensureVisualOverride() == nil or character == nil then return false end
    local savedSlots = {}
    local emptySlots = {}
    lookData = lookData or savedLook
    for _, entry in ipairs(slots) do
        if lookData[entry.key] ~= nil then
            savedSlots[#savedSlots + 1] = entry.key
        else
            emptySlots[#emptySlots + 1] = entry.key
        end
    end
    local ok, result = pcall(function()
        return VisualOverride.SetFashionSlots(character, table.concat(savedSlots, ","), table.concat(emptySlots, ","))
    end)
    return ok and result == true
end

local function applyVisualOverrideToItem(character, item, carrier)
    if ensureVisualOverride() == nil or character == nil or item == nil then return false end
    local ok, result = pcall(function()
        return VisualOverride.ApplyFashionItemVisual(character, item, carrier == true)
    end)
    return ok and result == true
end

local function activateFashionVisual(character)
    if ensureVisualOverride() == nil or character == nil then return false end
    local ok, result = pcall(function()
        return VisualOverride.ActivateFashionVisual(character)
    end)
    return ok and result == true
end

local function visualSnapshot(character)
    local data = {}
    for _, entry in ipairs(slots) do
        local item = getSlotItem(character, entry.slot)
        if item ~= nil and not isIgnoredWardrobeItem(item) then
            data[entry.key] = {
                identifier = itemIdentifier(item),
                itemId = itemEntityId(item),
                name = itemName(item),
                slot = entry.key
            }
        else
            data[entry.key] = nil
        end
    end
    return data
end

local function requestServerSaveFashion()
    if not isMultiplayerClient() or Networking == nil then return false end
    local ok = pcall(function()
        local message = Networking.Start(NET_SAVE_REQUEST)
        Networking.Send(message)
    end)
    return ok == true
end

local function requestServerApplyFashion()
    if not isMultiplayerClient() or Networking == nil then return false end
    local ok = pcall(function()
        local message = Networking.Start(NET_APPLY_REQUEST)
        Networking.Send(message)
    end)
    return ok == true
end

local function requestServerClearFashion()
    if not isMultiplayerClient() or Networking == nil then return false end
    local ok = pcall(function()
        local message = Networking.Start(NET_CLEAR_REQUEST)
        Networking.Send(message)
    end)
    return ok == true
end

local function readNetworkLook(message)
    local characterId = message.ReadUInt16()
    local data = {}
    for _, entry in ipairs(slots) do
        if message.ReadBoolean() then
            data[entry.key] = {
                itemId = message.ReadUInt16(),
                identifier = message.ReadString(),
                name = message.ReadString(),
                slot = entry.key
            }
        else
            data[entry.key] = nil
        end
    end
    return characterId, data
end

local function captureFashionPayloadFromLook(character, lookData, diagnostics)
    if character == nil or lookData == nil then return false, 0, 0 end

    local expectedItems = 0
    local capturedItems = 0
    for _, entry in ipairs(slots) do
        local data = lookData[entry.key]
        local itemId = data ~= nil and tonumber(data.itemId) or 0
        local identifier = data ~= nil and tostring(data.identifier or "") or ""
        if data ~= nil and (itemId > 0 or identifier ~= "") then
            expectedItems = expectedItems + 1
            local item = findEntityById(itemId)
            local foundBy = item ~= nil and "entity id" or "none"
            if item == nil or itemIdentifier(item) ~= identifier then
                item = findItemByIdentifier(character, identifier)
                foundBy = item ~= nil and "character inventory identifier" or "none"
            end
            if item ~= nil then
                local captured = captureVisualOverride(character, item)
                if captured > 0 then
                    capturedItems = capturedItems + 1
                end
                if diagnostics ~= nil then
                    diagnostics[#diagnostics + 1] =
                        entry.key .. ": identifier=" .. tostring(identifier) ..
                        ", itemId=" .. tostring(itemId) ..
                        ", savedName=" .. tostring(data.name) ..
                        ", found=" .. foundBy ..
                        ", capturedSprites=" .. tostring(captured)
                end
            else
                local captured = captureVisualOverridePrefab(character, identifier)
                if captured > 0 then
                    capturedItems = capturedItems + 1
                end
                if diagnostics ~= nil then
                    diagnostics[#diagnostics + 1] =
                        entry.key .. ": identifier=" .. tostring(identifier) ..
                        ", itemId=" .. tostring(itemId) ..
                        ", savedName=" .. tostring(data.name) ..
                        ", found=missing item instance" ..
                        ", prefabCapturedSprites=" .. tostring(captured)
                end
            end
        end
    end

    if expectedItems == 0 then
        captureEmptyVisualOverride(character)
        if diagnostics ~= nil then
            diagnostics[#diagnostics + 1] = "look had no saved slots; captured empty look"
        end
        return true, expectedItems, capturedItems
    end

    if capturedItems == 0 then
        if diagnostics ~= nil then
            diagnostics[#diagnostics + 1] = "no saved fashion sprites could be captured"
        end
        return false, expectedItems, capturedItems
    end

    return true, expectedItems, capturedItems
end

local function applyCapturedFashionToCharacterEquipment(character, lookData, recapturePayload)
    if character == nil then return false, 0 end

    local look = lookData or savedLook
    if recapturePayload ~= false then
        clearVisualOverride(character)
        if not captureFashionPayloadFromLook(character, look) then
            return false, 0
        end
    else
        restoreItemVisuals(character)
    end
    setFashionSlotMask(character, look)

    local current = snapshot(character)
    local equippedItems = {}
    for _, entry in ipairs(slots) do
        local equipped = current[entry.key]
        if equipped ~= nil then
            equippedItems[#equippedItems + 1] = {
                item = equipped,
                priority = visualCarrierPriority[entry.key] or 99
            }
        end
    end

    table.sort(equippedItems, function(a, b)
        return a.priority < b.priority
    end)

    local visualItems = 0
    for index, entry in ipairs(equippedItems) do
        if applyVisualOverrideToItem(character, entry.item, index == 1) then
            visualItems = visualItems + 1
        end
    end

    return activateFashionVisual(character), visualItems
end

local function applyNetworkLook(character, networkLook)
    local diagnostics = {}
    if character == nil or networkLook == nil then return false, diagnostics end
    local visualStatus = visualOverrideStatus()
    if visualStatus ~= nil then
        diagnostics[#diagnostics + 1] = "visual override not ready: " .. tostring(visualStatus)
        return false, diagnostics
    end

    clearVisualOverride(character)

    local capturedPayload, expectedItems, capturedItems = captureFashionPayloadFromLook(character, networkLook, diagnostics)
    if not capturedPayload then
        return false, diagnostics
    end

    local activated = applyCapturedFashionToCharacterEquipment(character, networkLook, false)
    diagnostics[#diagnostics + 1] = "activated=" .. tostring(activated == true) .. ", expectedItems=" .. tostring(expectedItems) .. ", capturedItems=" .. tostring(capturedItems)
    return activated == true, diagnostics
end

local function saveFashionAndUnequip()
    local character = controlled()
    if character == nil then
        log("No controlled character.")
        return
    end

    local overrideState = visualOverrideState()
    if not overrideState.ready then
        log("C# visual override is not ready. Enable C# scripting in LuaCs, accept this mod's C# prompt, then reload.")
        return
    end

    local startingItems = snapshot(character)
    savedLook = visualSnapshot(character)
    savedLookCaptured = true
    slotResults = {}
    activeLook = false
    autoApplyLook = true
    lastServerAutoApplySignature = nil
    lastEquipmentSignature = nil
    clearVisualOverride(character)

    local capturedSprites = 0
    local removedItems = 0
    local startingItemCount = 0
    local failedItems = {}
    local processedItems = {}
    local serverRequested = isMultiplayerClient()
    for _, entry in ipairs(slots) do
        local item = startingItems[entry.key]
        if item ~= nil then
            startingItemCount = startingItemCount + 1
            if processedItems[item] then
                slotResults[entry.key] = "Already handled"
            else
                processedItems[item] = true
                capturedSprites = capturedSprites + captureVisualOverride(character, item)
                if serverRequested then
                    slotResults[entry.key] = "Saved; server removal requested"
                else
                    unequipItem(character, item)
                    local remainingSlots = wornSlotLabelsForItem(character, item)
                    if #remainingSlots > 0 then
                        local result = "Still equipped in " .. table.concat(remainingSlots, ", ")
                        slotResults[entry.key] = result
                        failedItems[#failedItems + 1] = slotLabel(entry) .. ": " .. itemName(item) .. " (" .. table.concat(remainingSlots, ", ") .. ")"
                    else
                        removedItems = removedItems + 1
                        slotResults[entry.key] = "Saved and removed"
                    end
                end
            end
        else
            slotResults[entry.key] = "Empty"
        end
    end

    if capturedSprites <= 0 then
        captureEmptyVisualOverride(character)
    end

    lastCharacter = character
    local message = "Saved current outfit: "
    if startingItemCount == 0 then
        message = message .. "empty outfit captured."
    else
        message = message .. tostring(capturedSprites) .. " wearable sprites captured"
        if serverRequested then
            message = message .. "."
        else
            message = message ..
                ", " ..
                tostring(removedItems) ..
                " item" .. (removedItems == 1 and "" or "s") .. " removed."
        end
        if capturedSprites <= 0 then
            message = message .. " Saved as an empty visual look."
        end
    end
    if serverRequested then
        if requestServerSaveFashion() then
            message = message .. " Server-side removal requested for multiplayer."
        else
            message = message .. " Server-side removal request failed; make sure the server has this mod enabled."
        end
    end
    if #failedItems > 0 then
        message = message .. " Still equipped: " .. table.concat(failedItems, "; ") .. "."
    end
    saveCharacterState(character)
    persistClientLook()
    log(message)
end

local function applyFashionToCurrentEquipment(silent)
    local character = controlled()
    if character == nil then
        if not silent then log("No controlled character.") end
        return false
    end

    if not hasSavedLook() then
        if not silent then log("No saved look. Save an outfit first.") end
        activeLook = false
        lastEquipmentSignature = nil
        return false
    end

    local visualStatus = visualOverrideStatus()
    if visualStatus ~= nil then
        if not silent then log(visualStatus) end
        activeLook = false
        lastEquipmentSignature = nil
        return false
    end

    if isMultiplayerClient() and requestServerApplyFashion() then
        lastCharacter = character
        autoApplyLook = true
        lastServerAutoApplySignature = equipmentSignature(character)
        saveCharacterState(character)
        persistClientLook()
        if not silent then log("Requested multiplayer wardrobe apply from the server.") end
        return true
    end

    local activated, visualItems = applyCapturedFashionToCharacterEquipment(character, savedLook)

    lastCharacter = character
    activeLook = activated == true
    autoApplyLook = activated == true
    lastEquipmentSignature = equipmentSignature(character)
    saveCharacterState(character)
    persistClientLook()

    if not activated then
        if not silent then
            log("Saved look could not be applied. Save the outfit again after C# has loaded.")
        end
        return false
    end

    if not silent then
        local message = "Saved look applied."
        if visualItems > 0 then
            message = message .. " Checked " .. tostring(visualItems) .. " worn item" .. (visualItems == 1 and "" or "s") .. "."
        else
            message = message .. " No worn equipment required."
        end
        log(message)
    end
    return true
end

local function clearActiveLook()
    local character = controlled()
    local multiplayerClearRequested = requestServerClearFashion()
    if character ~= nil then
        restoreItemVisuals(character)
    end
    activeLook = false
    autoApplyLook = false
    lastServerAutoApplySignature = nil
    lastEquipmentSignature = nil
    saveCharacterState(character)
    persistClientLook()
    if multiplayerClearRequested then
        log("Look cleared. Multiplayer clear requested from the server.")
    else
        log("Look cleared. Real equipment visuals restored.")
    end
end

local function refreshActiveLookIfNeeded(character)
    if character == nil or not activeLook or not hasSavedLook() then return end
    local signature = equipmentSignature(character)
    if lastEquipmentSignature == signature then return end
    if applyFashionToCurrentEquipment(true) then
        lastOperation = "Saved look refreshed for changed equipment."
        saveCharacterState(character)
        persistClientLook()
    else
        activeLook = false
        lastEquipmentSignature = nil
        lastOperation = "Saved look needs to be applied again."
        saveCharacterState(character)
        persistClientLook()
    end
end

local function autoApplySavedLookIfNeeded(character)
    if character == nil or activeLook or not autoApplyLook or not hasSavedLook() then return end
    if isMultiplayerClient() then
        local signature = equipmentSignature(character)
        if lastServerAutoApplySignature == signature then return end
        if requestServerApplyFashion() then
            lastServerAutoApplySignature = signature
            lastOperation = "Saved look needs to be applied again."
            saveCharacterState(character)
            persistClientLook()
        end
        return
    end
    if applyFashionToCurrentEquipment(true) then
        lastOperation = "Saved look auto-applied."
        saveCharacterState(character)
        persistClientLook()
    end
end

local function handleNoControlledCharacter()
    if lastCharacter ~= nil then
        saveCharacterState(lastCharacter)
    end

    local shouldReapplySavedLook = hasSavedLook() and (activeLook or autoApplyLook)
    activeLook = false
    lastEquipmentSignature = nil
    lastServerAutoApplySignature = nil
    lastCharacter = nil

    if hasSavedLook() then
        if shouldReapplySavedLook then
            autoApplyLook = true
            lastOperation = "Saved look will be reapplied in the next scene."
        end
        if next(slotResults) == nil then
            for _, entry in ipairs(slots) do
                slotResults[entry.key] = savedLook[entry.key] ~= nil and "Saved look needs to be applied again." or "Empty"
            end
        end
    else
        slotResults = {}
        lastNetworkApplyDiagnostics = {}
    end
end

local function handleControlledCharacterChange(character)
    if lastCharacter == nil or character == lastCharacter then return end
    saveCharacterState(lastCharacter)
    local hadState = loadCharacterState(character)
    if hadState then
        lastOperation = hasSavedLook() and "Saved look restored for this character." or "Controlled character changed."
    else
        lastServerAutoApplySignature = nil
        if hasSavedLook() then
            autoApplyLook = true
            lastOperation = "Saved look needs to be applied again."
        else
            lastOperation = "Controlled character changed. Save a new outfit for this character."
        end
    end
    pruneVisualOverrides()
end

local function clearSavedLook()
    local character = controlled()
    if character ~= nil then
        clearVisualOverride(character)
    end
    savedLook = {}
    savedLookCaptured = false
    activeLook = false
    autoApplyLook = false
    lastServerAutoApplySignature = nil
    slotResults = {}
    lastEquipmentSignature = nil
    saveCharacterState(character)
    clearPersistentClientLook()
    log("Saved look cleared.")
end

local function deferRoundStartNetworkLook(character, networkLook)
    savedLook = copyLookData(networkLook)
    savedLookCaptured = true
    activeLook = false
    autoApplyLook = true
    lastServerAutoApplySignature = nil
    lastCharacter = character
    lastEquipmentSignature = nil
    pendingRoundStartNetworkLook = copyLookData(networkLook)
    pendingRoundStartNetworkCharacterKey = characterStateKey(character)
    slotResults = {}
    lastNetworkApplyDiagnostics = { "waiting for initial equipment to finish equipping" }
    for _, entry in ipairs(slots) do
        slotResults[entry.key] = savedLook[entry.key] ~= nil and "Waiting for initial equipment" or "Empty"
    end
    lastOperation = "Multiplayer wardrobe sync is waiting for initial equipment."
    saveCharacterState(character)
    persistClientLook()
end

local function applyPendingRoundStartNetworkLook(character)
    if character == nil or pendingRoundStartNetworkLook == nil then return false end
    if pendingRoundStartNetworkCharacterKey ~= characterStateKey(character) then return false end

    local networkLook = copyLookData(pendingRoundStartNetworkLook)
    pendingRoundStartNetworkLook = nil
    pendingRoundStartNetworkCharacterKey = nil

    local applied, diagnostics = applyNetworkLook(character, networkLook)
    savedLook = copyLookData(networkLook)
    savedLookCaptured = true
    activeLook = applied == true
    autoApplyLook = true
    lastServerAutoApplySignature = nil
    lastCharacter = character
    lastEquipmentSignature = equipmentSignature(character)
    slotResults = {}
    lastNetworkApplyDiagnostics = diagnostics or {}
    for _, entry in ipairs(slots) do
        slotResults[entry.key] = networkLook[entry.key] ~= nil and (applied and "Synced from server" or "Sync failed; dump debug log") or "Empty"
    end
    if applied then
        lastOperation = "Saved look applied from multiplayer sync after initial equipment."
    else
        lastOperation = "Multiplayer wardrobe sync failed after initial equipment; dump debug log."
    end
    saveCharacterState(character)
    persistClientLook()
    return true
end

if Networking ~= nil then
    Networking.Receive(NET_LOOK_APPLY, function(message)
        local characterId, networkLook = readNetworkLook(message)
        local character = findEntityById(characterId)
        if character == nil then return end

        if character == controlled() and initialEquipGateActive and not initialEquipGateReady(character) then
            deferRoundStartNetworkLook(character, networkLook)
            return
        end

        local applied, diagnostics = applyNetworkLook(character, networkLook)
        if character == controlled() then
            savedLook = copyLookData(networkLook)
            savedLookCaptured = true
            activeLook = applied == true
            autoApplyLook = true
            lastServerAutoApplySignature = nil
            lastCharacter = character
            lastEquipmentSignature = equipmentSignature(character)
            slotResults = {}
            lastNetworkApplyDiagnostics = diagnostics or {}
            for _, entry in ipairs(slots) do
                slotResults[entry.key] = networkLook[entry.key] ~= nil and (applied and "Synced from server" or "Sync failed; dump debug log") or "Empty"
            end
            if applied then
                lastOperation = "Saved look applied from multiplayer sync."
            else
                lastOperation = "Multiplayer wardrobe sync failed; make sure every client has the fashion items and C# scripting enabled."
            end
            saveCharacterState(character)
            persistClientLook()
        end
    end)

    Networking.Receive(NET_LOOK_CLEAR, function(message)
        local characterId = message.ReadUInt16()
        local character = findEntityById(characterId)
        if character == nil then return end

        clearVisualOverride(character)
        if character == controlled() then
            activeLook = false
            autoApplyLook = false
            lastServerAutoApplySignature = nil
            lastEquipmentSignature = nil
            pendingRoundStartNetworkLook = nil
            pendingRoundStartNetworkCharacterKey = nil
            lastOperation = "Look cleared from multiplayer sync."
            saveCharacterState(character)
            persistClientLook()
        end
    end)
end

local function clientLookStoragePath()
    local persistence = ensureWardrobePersistence()
    if persistence ~= nil then
        local ok, path = pcall(function()
            return persistence.GetClientLookPath()
        end)
        if ok and path ~= nil and tostring(path) ~= "" then
            return tostring(path)
        end
    end
    return clientPersistPath()
end

local function dumpDebugLog()
    local character = controlled()
    local overrideState = visualOverrideState()
    local lines = {}
    local function emit(line)
        lines[#lines + 1] = tostring(line)
        debugLog(line)
    end
    emit("---- wardrobe diagnostic dump begin ----")
    emit("lastOperation=" .. tostring(lastOperation))
    emit("savedLookCaptured=" .. tostring(savedLookCaptured) .. ", activeLook=" .. tostring(activeLook) .. ", autoApplyLook=" .. tostring(autoApplyLook))
    emit("sessionKey=" .. tostring(currentSessionKey()))
    emit("overrideLabel=" .. tostring(overrideState.label) .. ", overrideDetails=" .. tostring(overrideState.details))
    emit("persistence=" .. tostring(clientLookStoragePath()))
    emit("character=" .. tostring(character) .. ", equipmentSignature=" .. tostring(character ~= nil and equipmentSignature(character) or "no-character"))
    for _, entry in ipairs(slots) do
        local current = character ~= nil and getSlotItem(character, entry.slot) or nil
        local saved = savedLook[entry.key]
        emit(
            entry.key ..
            " currentIdentifier=" .. tostring(itemIdentifier(current)) ..
            ", currentName=" .. tostring(itemName(current)) ..
            ", currentId=" .. tostring(itemEntityId(current)) ..
            ", savedIdentifier=" .. tostring(saved ~= nil and saved.identifier or nil) ..
            ", savedName=" .. tostring(saved ~= nil and saved.name or nil) ..
            ", savedItemId=" .. tostring(saved ~= nil and saved.itemId or nil) ..
            ", result=" .. tostring(slotResults[entry.key])
        )
    end
    if #lastNetworkApplyDiagnostics > 0 then
        for index, line in ipairs(lastNetworkApplyDiagnostics) do
            emit("networkApply[" .. tostring(index) .. "] " .. tostring(line))
        end
    else
        emit("networkApply=<none>")
    end
    local debugStatus = visualOverrideDebugStatus(character)
    emit("visualOverrideCharacter=" .. tostring(debugStatus))
    emit("---- wardrobe diagnostic dump end ----")
    lastOperation = "Debug diagnostics dumped to LuaCs log."
end

local function clearWindow()
    if window ~= nil then
        pcall(function() window.Remove() end)
        window = nil
    end
    fullPanelOpen = false
    resetOverlay()
end

local function addText(parent, text)
    local block = GUI.TextBlock(GUI.RectTransform(Vector2(1.0, 0.0), parent.RectTransform), text)
    block.TextColor = Color.White
    return block
end

local function addButton(parent, text, action, refresh, enabled)
    local button = GUI.Button(GUI.RectTransform(Vector2(1.0, 0.08), parent.RectTransform), text)
    if enabled == false then
        pcall(function() button.Enabled = false end)
    end
    button.OnClicked = function()
        action()
        if refresh ~= false then
            clearWindow()
            buildWindow()
        end
        return true
    end
    return button
end

buildWindow = function()
    if window ~= nil then
        pcall(function() window.Remove() end)
        window = nil
    end

    local parent = overlayParent()
    if parent == nil then
        log("Overlay root is not ready.")
        return
    end

    local frame = GUI.Frame(GUI.RectTransform(Vector2(0.48, 0.68), parent, GUI.Anchor.Center), "GUIFrame")
    window = frame
    fullPanelOpen = true

    local list = GUI.LayoutGroup(GUI.RectTransform(Vector2(0.94, 0.94), frame.RectTransform, GUI.Anchor.Center), false)
    list.Stretch = true
    list.RelativeSpacing = 0.03

    local character = controlled()
    local overrideState = visualOverrideState()
    local canApply = overrideState.ready and hasSavedLook()

    addText(list, tr("panel.title"))
    addText(list, overrideState.label)
    addText(list, tr("panel.saved_look") .. ": " .. savedLookSummary() .. " | " .. tr("panel.look") .. ": " .. (activeLook and tr("panel.active") or tr("panel.inactive")))
    addText(list, tr("panel.last") .. ": " .. localizedStatus(lastOperation))

    addButton(list, tr("button.save"), function() saveFashionAndUnequip() end, true, overrideState.ready)
    addButton(list, tr("button.apply"), function() applyFashionToCurrentEquipment(false) end, true, canApply)
    addButton(list, tr("button.clear"), function() clearActiveLook() end)
    addButton(list, tr("button.forget"), function() clearSavedLook() end, true, hasSavedLook())
    addButton(list, diagnosticsVisible and tr("button.hide_diagnostics") or tr("button.diagnostics"), function()
        diagnosticsVisible = not diagnosticsVisible
    end)
    addButton(list, tr("button.dump_debug"), function() dumpDebugLog() end, true)
    addText(list, tr("panel.debug_log_hint"))
    addText(list, tr("panel.saved_file") .. ": " .. clientLookStoragePath())
    addButton(list, tr("button.close"), function() fullPanelOpen = false; resetOverlay() end, false)

    for _, entry in ipairs(slots) do
        local currentItem = "-"
        if character ~= nil then
            currentItem = itemName(getSlotItem(character, entry.slot))
        end
        local result = localizedStatus(slotResults[entry.key] or "-")
        addText(
            list,
            slotLabel(entry) .. " | " .. tr("panel.current") .. ": " .. currentItem .. " | " .. tr("panel.saved") .. ": " .. itemName(savedLook[entry.key]) .. " | " .. tr("panel.result") .. ": " .. result
        )
    end

    if diagnosticsVisible then
        addText(list, tr("panel.diagnostics") .. ": " .. tostring(overrideState.details or tr("status.none")))
        local debugStatus = visualOverrideDebugStatus(character)
        if debugStatus ~= nil then
            addText(list, tr("panel.character") .. ": " .. debugStatus)
        end
    end
end

toggleWindow = function()
    if fullPanelOpen then
        fullPanelOpen = false
        resetOverlay()
    else
        fullPanelOpen = true
        resetOverlay()
        buildWindow()
    end
end

local function f8Hit()
    local ok, result = pcall(function()
        return PlayerInput.KeyHit(Keys.F8)
    end)
    return ok and result == true
end

local function resetSavedLookForNewSession()
    clearAllVisualOverrides()
    savedLook = {}
    savedLookCaptured = false
    activeLook = false
    autoApplyLook = false
    characterStates = {}
    slotResults = {}
    lastNetworkApplyDiagnostics = {}
    lastEquipmentSignature = nil
    lastServerAutoApplySignature = nil
    pendingRoundStartNetworkLook = nil
    pendingRoundStartNetworkCharacterKey = nil
    persistentClientLookLoaded = false
    lastOperation = "Ready."
end

local function handleSessionChange()
    local sessionKey = currentSessionKey()
    if sessionKey == nil then return end
    if lastSessionKey == nil then
        lastSessionKey = sessionKey
        return
    end
    if sessionKey == lastSessionKey then return end

    lastSessionKey = sessionKey
    resetSavedLookForNewSession()
    debugLog("Detected a new game session; cleared in-memory saved wardrobe look.")
end

Hook.Add("think", "barowardrobeswitcher.panel", function()
    globalTick = globalTick + 1

    handleSessionChange()
    if not persistentClientLookLoaded then
        loadPersistentClientLook()
    end

    if f8Hit() then
        toggleWindow()
    end

    local character = controlled()
    if character == nil then
        handleNoControlledCharacter()
        if fullPanelOpen and window == nil then
            buildWindow()
        end
        if fullPanelOpen then
            drawOverlay()
        end
        return
    end

    sendRoundStartNotice()

    handleControlledCharacterChange(character)
    lastCharacter = character
    if initialEquipGateActive and not initialEquipGateReady(character) then
        -- Wait until Barotrauma has finished its own initial equipment burst.
    else
        applyPendingRoundStartNetworkLook(character)
        autoApplySavedLookIfNeeded(character)
        refreshActiveLookIfNeeded(character)
    end

    if fullPanelOpen and window == nil then
        buildWindow()
    end
    if fullPanelOpen then
        drawOverlay()
    end

end)

Hook.Add("roundStart", "barowardrobeswitcher.notice", function()
    startInitialEquipGate()
    if hasSavedLook() and autoApplyLook then
        activeLook = false
        lastEquipmentSignature = nil
        lastServerAutoApplySignature = nil
    end
    sendRoundStartNotice()
end)

Hook.Add("item.equip", "barowardrobeswitcher.initial-equip", function(item, character)
    if not initialEquipGateActive or character == nil then return end
    local controlledCharacter = controlled()
    if controlledCharacter == nil or character ~= controlledCharacter then return end
    initialEquipGateSeenEquip = true
    initialEquipGateLastEquipTick = globalTick
    initialEquipGateStableTicks = 0
end)

Hook.Add("roundEnd", "barowardrobeswitcher.cleanup", function()
    if lastCharacter ~= nil then
        saveCharacterState(lastCharacter)
    end
    local preservedForNextScene = preserveSceneTransitionLookIntent()
    resetInitialEquipGate()
    pendingRoundStartNetworkLook = nil
    pendingRoundStartNetworkCharacterKey = nil
    fullPanelOpen = false
    resetOverlay()
    slotResults = {}
    lastNetworkApplyDiagnostics = {}
    activeLook = false
    diagnosticsVisible = false
    lastServerAutoApplySignature = nil
    lastEquipmentSignature = nil
    clearAllVisualOverrides()
    lastCharacter = nil
    roundStartNoticeSent = false
    if preservedForNextScene then
        lastOperation = "Saved look will be reapplied in the next scene."
    else
        lastOperation = hasSavedLook() and "Saved look needs to be applied again." or "Round ended."
    end
    if hasSavedLook() then
        persistClientLook()
    end
end)

loadPersistentClientLook()
log("Loaded. Press F8 to open the wardrobe panel.")
