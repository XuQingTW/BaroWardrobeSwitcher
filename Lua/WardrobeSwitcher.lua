local MOD_NAME = "Baro Wardrobe Switcher"
local Core = WardrobeCore
local coreAvailable = type(Core) == "table" and
    tonumber(Core.PROTOCOL_VERSION) == 2 and
    type(Core.NET) == "table"
local EXPECTED_CSHARP_VERSION = coreAvailable and tostring(Core.MOD_VERSION or "0.5.0") or "0.5.0"
local NET = coreAvailable and Core.NET or {}
local NET_SAVE_REQUEST = NET.V1_SAVE_REQUEST or "barowardrobeswitcher.save"
local NET_APPLY_REQUEST = NET.V1_APPLY_REQUEST or "barowardrobeswitcher.apply"
local NET_CLEAR_REQUEST = NET.V1_CLEAR_REQUEST or "barowardrobeswitcher.clear"
local NET_FORGET_REQUEST = NET.V1_FORGET_REQUEST or "barowardrobeswitcher.forget"
local NET_LOOK_APPLY = NET.V1_LOOK_APPLY or "barowardrobeswitcher.look.apply"
local NET_LOOK_CLEAR = NET.V1_LOOK_CLEAR or "barowardrobeswitcher.look.clear"
local NET_V2_HELLO = NET.V2_HELLO or "barowardrobeswitcher.v2.hello"
local NET_V2_COMMAND = NET.V2_COMMAND or "barowardrobeswitcher.v2.command"
local NET_V2_STATE = NET.V2_STATE or "barowardrobeswitcher.v2.state"
local NET_V2_ACK = NET.V2_ACK or "barowardrobeswitcher.v2.ack"
local COMMAND_SAVE = coreAvailable and Core.COMMAND.Save or "save"
local COMMAND_APPLY = coreAvailable and Core.COMMAND.Apply or "apply"
local COMMAND_CLEAR = coreAvailable and Core.COMMAND.Clear or "clear"
local COMMAND_FORGET = coreAvailable and Core.COMMAND.Forget or "forget"

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
        ["button.hide_hair"] = "Hide Hair",
        ["button.show_hair"] = "Show Hair",
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
        ["button.hide_hair"] = "隐藏头发",
        ["button.show_hair"] = "显示头发",
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
        ["button.hide_hair"] = "隱藏頭髮",
        ["button.show_hair"] = "顯示頭髮",
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
local legacyLookMetadata = {}
local savedLookCaptured = false
local activeLook = false
local autoApplyLook = false
local hideHair = false
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
local pendingServerApplyRequestKey = nil
local pendingServerApplyLastRequestTick = 0
local pendingServerApplyAttempts = 0
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
local pendingRoundStartNetworkRevision = nil
local pendingRoundStartHideHair = false
local pendingNetworkAppliesByCharacterId = {}
local pendingNetworkClearsByCharacterId = {}
local lastAppliedNetworkLookSignatureByCharacterKey = {}
local suppressedNetworkAppliesByCharacterKey = {}
local clientPersistPathCache = nil
local lastSessionKey = nil
local persistentClientLookLoaded = false
local persistClientLook
local clearPersistentClientLook
local ensureWardrobePersistence
local protocolMode = coreAvailable and "probing" or "v1"
local protocolHelloSentAt = nil
local protocolCommandQueue = {}
local inFlightV2Command = nil
local protocolOperationCounter = 0
local reducerCharacterKey = nil
local remoteRevisionByCharacterId = {}
local clientEffectAdapters = {}
local applyReducerProjection = nil

local function protocolClock()
    local ok, value = pcall(function()
        if Timer ~= nil and Timer.GetTime ~= nil then return Timer.GetTime end
        return nil
    end)
    if ok and tonumber(value) ~= nil then return tonumber(value) end
    return os.clock()
end

local function createClientSessionId()
    local timestamp = 0
    pcall(function() timestamp = os.time() end)
    local entropy = tostring({}):gsub("[^%w]", "")
    return tostring(timestamp) .. "-" .. entropy
end

local clientSessionId = createClientSessionId()
local reducerState = coreAvailable and Core.newClientState({ clientSessionId = clientSessionId }) or nil
local clientController = nil

local function createClientController(state)
    if not coreAvailable or state == nil then return nil end
    return Core.createClientController(state, {
        run = function(currentEffect, viewModel)
            local adapter = clientEffectAdapters[currentEffect.type]
            if type(adapter) ~= "function" then
                return false, "client adapter is not installed for " .. tostring(currentEffect.type)
            end
            return adapter(currentEffect, viewModel)
        end
    })
end

clientController = createClientController(reducerState)

local function dispatchReducer(event)
    if not coreAvailable or clientController == nil then return {} end
    local ok, effects, feedback = pcall(clientController.dispatch, event)
    if not ok then
        print("[" .. MOD_NAME .. " DEBUG] reducer rejected event " .. tostring(event and event.type) .. ": " .. tostring(effects))
        return {}
    end
    reducerState = clientController.getState()
    if applyReducerProjection ~= nil then applyReducerProjection(reducerState) end
    return effects or {}
end

local function effectsContain(effects, effectType)
    for _, current in ipairs(effects or {}) do
        if current.type == effectType then return true end
    end
    return false
end

local InitialEquipStableTicks = 12
local InitialEquipFallbackTicks = 120
local ServerApplyRetryTicks = 30
local ServerApplyMaxAttempts = 10
local PendingNetworkMessageMaxTicks = 300
local NetworkApplySuppressTicks = PendingNetworkMessageMaxTicks

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

local function lookDataSignature(lookData, captured)
    local parts = { "captured=" .. tostring(captured == true) }
    lookData = lookData or {}
    for _, entry in ipairs(slots) do
        local slotState = lookData[entry.key]
        if slotState ~= nil then
            parts[#parts + 1] =
                entry.key ..
                "=" ..
                tostring(slotState.identifier or "") ..
                "#" ..
                tostring(tonumber(slotState.itemId) or 0)
        else
            parts[#parts + 1] = entry.key .. "=-"
        end
    end
    return table.concat(parts, ";")
end

local function rememberLegacyLookMetadata(lookData)
    lookData = lookData or {}
    for _, entry in ipairs(slots) do
        local value = lookData[entry.key]
        if value ~= nil then
            legacyLookMetadata[entry.key] = {
                identifier = tostring(value.identifier or ""),
                itemId = tonumber(value.itemId) or 0,
                name = tostring(value.name or ""),
                slot = entry.key
            }
        end
    end
end

local function domainLookFromLegacy(lookData, captured, hairHidden)
    if not coreAvailable then return nil end
    local look = Core.fromLegacyLook(lookData or {}, captured == true, hairHidden == true)
    return look
end

local function currentDomainLook()
    return domainLookFromLegacy(savedLook, savedLookCaptured, hideHair)
end

local function syncReducerLook()
    if not coreAvailable then return end
    local look = currentDomainLook()
    if look ~= nil and Core.hasLook(look) then
        dispatchReducer({
            type = "RestoreLook",
            look = look,
            active = activeLook == true,
            autoApply = autoApplyLook == true
        })
    end
end

local function legacyLookFromDomain(look)
    if not coreAvailable or look == nil then return {} end
    local projected = Core.toLegacyLook(look) or {}
    for _, entry in ipairs(slots) do
        local value = projected[entry.key]
        local metadata = legacyLookMetadata[entry.key]
        if value ~= nil and metadata ~= nil and
            tostring(metadata.identifier or "") == tostring(value.identifier or "") then
            value.itemId = tonumber(metadata.itemId) or 0
            value.name = tostring(metadata.name or "")
        end
    end
    return projected
end


applyReducerProjection = function(state)
    if not coreAvailable or type(state) ~= "table" then return end
    local projected = legacyLookFromDomain(state.look)
    savedLook = projected
    savedLookCaptured = state.look ~= nil and state.look.captured == true
    activeLook = state.active == true
    autoApplyLook = state.autoApply == true
    if state.look ~= nil then hideHair = state.look.hideHair == true end
end

local function nextOperationId()
    protocolOperationCounter = protocolOperationCounter + 1
    return clientSessionId .. ":" .. tostring(protocolOperationCounter)
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
    if state == nil then
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
    if not lookDataHasSavedLook(savedLook, savedLookCaptured) then
        activeLook = false
        autoApplyLook = false
        lastEquipmentSignature = nil
        slotResults = {}
        lastNetworkApplyDiagnostics = {}
        return false
    end
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

local function encodePersistentClientLook(lookData, captured, active, auto, hairHidden)
    lookData = lookData or savedLook
    if captured == nil then captured = savedLookCaptured == true end
    if active == nil then active = activeLook == true end
    if auto == nil then auto = autoApplyLook == true end
    if hairHidden == nil then hairHidden = hideHair == true end
    local parts = {
        "schema=2",
        "captured=" .. tostring(captured == true),
        "active=" .. tostring(active == true),
        "auto=" .. tostring(auto == true),
        "hidehair=" .. tostring(hairHidden == true)
    }
    local sessionKey = currentSessionKey()
    if sessionKey ~= nil then
        parts[#parts + 1] = "session=" .. escapePersistentValue(sessionKey)
    end
    for _, entry in ipairs(slots) do
        local slotState = lookData[entry.key]
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
    if file == nil then return false, path, "missing" end

    local line = file:read("*l")
    file:close()
    if line == nil or tostring(line) == "" then return nil, path, "empty or truncated" end
    return tostring(line), path
end

local function restorePersistentClientLookLine(line, source)
    if coreAvailable and type(Core.parseLegacyClientLookLine) == "function" then
        local parsed, parseReason = Core.parseLegacyClientLookLine(tostring(line or ""))
        if parsed == nil then
            debugLog("Rejected persistent client look: " .. tostring(parseReason))
            return false
        end
    end
    local restoredLook = {}
    local captured = nil
    local active = false
    local auto = false
    local restoredHideHair = false
    local restoredSessionKey = nil
    local seen = {}
    local validSlots = {}
    for _, entry in ipairs(slots) do validSlots[entry.key] = true end

    local function parseBoolean(name, value)
        if value == "true" then return true end
        if value == "false" then return false end
        debugLog("Rejected persistent client look with invalid " .. name .. " boolean.")
        return nil
    end

    for part in tostring(line):gmatch("[^|]+") do
        local name, value = part:match("^([^=]+)=(.*)$")
        if name == nil or seen[name] then
            debugLog("Rejected persistent client look with a malformed or duplicate field.")
            return false
        end
        seen[name] = true
        if name == "captured" then
            captured = parseBoolean(name, value)
            if captured == nil then return false end
        elseif name == "active" then
            active = parseBoolean(name, value)
            if active == nil then return false end
        elseif name == "auto" then
            auto = parseBoolean(name, value)
            if auto == nil then return false end
        elseif name == "hidehair" then
            restoredHideHair = parseBoolean(name, value)
            if restoredHideHair == nil then return false end
        elseif name == "schema" then
            if value ~= "1" and value ~= "2" then
                debugLog("Rejected persistent client look with unsupported schema " .. tostring(value) .. ".")
                return false
            end
        elseif name == "session" then
            restoredSessionKey = unescapePersistentValue(value)
        elseif validSlots[name] then
            local identifier, displayName = tostring(value):match("^([^,]+),(.*)$")
            identifier = identifier ~= nil and unescapePersistentValue(identifier) or nil
            if identifier == nil or identifier == "" or #identifier > 256 then
                debugLog("Rejected persistent client look with malformed slot " .. tostring(name) .. ".")
                return false
            end
            restoredLook[name] = {
                identifier = identifier,
                itemId = 0,
                name = unescapePersistentValue(displayName or ""),
                slot = name
            }
        else
            debugLog("Rejected persistent client look with unknown field " .. tostring(name) .. ".")
            return false
        end
    end

    if captured == nil then
        debugLog("Rejected persistent client look without captured intent.")
        return false
    end

    local sessionKey = currentSessionKey()
    if sessionKey ~= nil and restoredSessionKey ~= nil and
        restoredSessionKey ~= "" and restoredSessionKey ~= sessionKey then
        debugLog("Restoring persistent client wardrobe look saved in another campaign session from " .. tostring(source or "C# persistence") .. ".")
    end

    if not lookDataHasSavedLook(restoredLook, captured) then return false end
    local domainLook, lookReason = domainLookFromLegacy(restoredLook, captured, restoredHideHair)
    if domainLook == nil then
        debugLog("Rejected persistent client look: " .. tostring(lookReason))
        return false
    end
    rememberLegacyLookMetadata(restoredLook)
    savedLook = copyLookData(restoredLook)
    persistentClientLookLoaded = true
    savedLookCaptured = true
    activeLook = false
    autoApplyLook = active == true or auto == true
    hideHair = restoredHideHair == true
    lastEquipmentSignature = nil
    lastServerAutoApplySignature = nil
    slotResults = {}
    for _, entry in ipairs(slots) do
        slotResults[entry.key] = savedLook[entry.key] ~= nil and "Saved look needs to be applied again." or "Empty"
    end
    lastOperation = autoApplyLook and "Saved look will be reapplied in the next scene." or "Saved look needs to be applied again."
    syncReducerLook()
    debugLog("Loaded persistent client wardrobe look from " .. tostring(source or "C# persistence") .. ".")
    return true
end

local function persistenceFailureReason(fallback)
    if WardrobePersistence ~= nil then
        local ok, reason = pcall(function()
            return WardrobePersistence.GetLastError()
        end)
        if ok and reason ~= nil and tostring(reason) ~= "" then
            return tostring(reason)
        end
    end
    if wardrobePersistenceFailure ~= nil and tostring(wardrobePersistenceFailure) ~= "" then
        return tostring(wardrobePersistenceFailure)
    end
    return fallback
end

persistClientLook = function(domainLook, viewModel)
    local lookData = savedLook
    local captured = savedLookCaptured == true
    local active = activeLook == true
    local auto = autoApplyLook == true
    local hairHidden = hideHair == true
    if domainLook ~= nil and coreAvailable then
        lookData = Core.toLegacyLook(domainLook) or {}
        for _, entry in ipairs(slots) do
            local value = lookData[entry.key]
            local metadata = legacyLookMetadata[entry.key]
            if value ~= nil and metadata ~= nil and value.identifier == metadata.identifier then
                value.itemId = tonumber(metadata.itemId) or 0
                value.name = tostring(metadata.name or "")
            end
        end
        captured = domainLook.captured == true
        hairHidden = domainLook.hideHair == true
        if viewModel ~= nil then
            active = viewModel.active == true
            auto = viewModel.autoApply == true
        end
    end
    if not lookDataHasSavedLook(lookData, captured) then
        return false, "no saved client look is available to persist"
    end

    local encoded = encodePersistentClientLook(lookData, captured, active, auto, hairHidden)
    local persistence = ensureWardrobePersistence()
    if persistence == nil then
        local reason = persistenceFailureReason("C# wardrobe persistence is unavailable")
        debugLog("C# wardrobe persistence write failed; saved look remains in memory for this session. " .. reason)
        return false, reason
    end

    local ok, saved = pcall(function()
        return persistence.SaveClientLook(encoded)
    end)
    if ok and saved == true then
        return true
    end
    local reason = ok and
        persistenceFailureReason("C# SaveClientLook returned false") or
        tostring(saved)
    debugLog("C# wardrobe persistence write failed; saved look remains in memory for this session. " .. reason)
    return false, reason
end

clearPersistentClientLook = function()
    local persistence = ensureWardrobePersistence()
    if persistence == nil then
        return false, persistenceFailureReason("C# wardrobe persistence is unavailable")
    end
    local ok, result = pcall(function()
        return persistence.ClearClientLook()
    end)
    if ok and result == true then return true end
    return false, ok and
        persistenceFailureReason("C# ClearClientLook returned false") or
        tostring(result)
end

local function loadPersistentClientLook()
    local persistence = ensureWardrobePersistence()
    if persistence ~= nil then
        local existedBeforeLoad = false
        pcall(function() existedBeforeLoad = persistence.ClientLookFileExists() == true end)
        local ok, line = pcall(function()
            return persistence.LoadClientLook()
        end)
        if not ok then
            debugLog("C# wardrobe persistence load failed: " .. tostring(line))
            persistentClientLookLoaded = true
            return false
        end
        if ok and line ~= nil and tostring(line) ~= "" then
            local restored = restorePersistentClientLookLine(tostring(line), "C# persistence")
            persistentClientLookLoaded = true
            return restored
        end
        local loadFailure = persistenceFailureReason(nil)
        if loadFailure ~= nil then
            debugLog("C# wardrobe persistence load failed: " .. loadFailure)
            persistentClientLookLoaded = true
            return false
        end
        if ok and existedBeforeLoad then
            -- LoadClientLook quarantines malformed schema-v2 JSON. Never fall
            -- back to an older legacy file after a corrupt primary existed,
            -- otherwise stale wardrobe intent could be applied automatically.
            -- Persist an empty v2 tombstone so the same stale legacy file also
            -- remains blocked on every later restart.
            local tombstoned = false
            pcall(function() tombstoned = persistence.ClearClientLook() == true end)
            if not tombstoned then
                debugLog("Corrupt client look was quarantined, but its empty v2 tombstone could not be written.")
            end
            persistentClientLookLoaded = true
            return false
        end
    end

    local legacyLine, legacyPath, legacyReason = readLegacyPersistentClientLookLine()
    if legacyLine == false then
        if persistence ~= nil then
            persistentClientLookLoaded = true
        end
        return false
    end
    if legacyLine == nil then
        if persistence ~= nil then
            pcall(function() persistence.QuarantineLegacyClientLook(legacyPath) end)
        end
        debugLog("Quarantined corrupt legacy client look: " .. tostring(legacyReason))
        return false
    end
    local restored = restorePersistentClientLookLine(legacyLine, legacyPath)
    if restored then
        local migrated = false
        if persistence ~= nil then
            local ok, result = pcall(function()
                return persistence.SaveMigratedClientLook(encodePersistentClientLook(), legacyPath)
            end)
            migrated = ok and result == true
        end
        if not migrated then
            debugLog("Legacy client look was restored in memory, but migration could not create its .v1.bak backup.")
        end
    elseif persistence ~= nil then
        pcall(function() persistence.QuarantineLegacyClientLook(legacyPath) end)
        debugLog("Quarantined legacy client look that failed schema validation.")
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
    elseif VisualOverride == nil then
        visualOverrideFailure = "LuaCs returned no BaroWardrobeSwitcher.VisualOverride type."
    else
        local versionOk, loadedVersion = pcall(function()
            return VisualOverride.GetVersion()
        end)
        if not versionOk or tostring(loadedVersion) ~= EXPECTED_CSHARP_VERSION then
            visualOverrideFailure =
                "C# visual override version mismatch: expected " ..
                EXPECTED_CSHARP_VERSION ..
                ", loaded " ..
                tostring(versionOk and loadedVersion or "unknown") ..
                ". Fully restart Barotrauma so LuaCs recompiles this mod."
            VisualOverride = nil
        end
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
        local versionOk, loadedVersion = pcall(function()
            return result.GetVersion()
        end)
        if result ~= nil and versionOk and tostring(loadedVersion) == EXPECTED_CSHARP_VERSION then
            WardrobePersistence = result
        else
            WardrobePersistence = nil
            wardrobePersistenceFailure =
                "C# persistence version mismatch: expected " ..
                EXPECTED_CSHARP_VERSION ..
                ", loaded " ..
                tostring(versionOk and loadedVersion or "unknown") ..
                ". Fully restart Barotrauma so LuaCs recompiles this mod."
        end
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

local function characterEntityId(character)
    if character == nil then return 0 end
    local ok, id = pcall(function()
        return character.ID
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
    if clientController ~= nil then
        return Core.hasLook(clientController.getState().look)
    end
    return lookDataHasSavedLook(savedLook, savedLookCaptured)
end

local function stateHasSavedLook(state)
    if state == nil then return false end
    return hasSavedLook()
end

local function deactivateCachedCharacterStates(preserveAutoApply)
    for _, state in pairs(characterStates) do
        state.activeLook = false
        if preserveAutoApply ~= true then
            state.autoApplyLook = false
        end
        state.lastEquipmentSignature = nil
    end
end

local function clearPendingNetworkApplyForCharacterId(characterId)
    local id = tonumber(characterId) or 0
    if id <= 0 then return end
    pendingNetworkAppliesByCharacterId[id] = nil
end

local function clearLocalPendingNetworkState(character)
    local key = characterStateKey(character)
    if key ~= nil then
        lastAppliedNetworkLookSignatureByCharacterKey[key] = nil
        if pendingRoundStartNetworkCharacterKey == key then
            pendingRoundStartNetworkLook = nil
            pendingRoundStartNetworkCharacterKey = nil
            pendingRoundStartNetworkRevision = nil
            pendingRoundStartHideHair = false
        end
        clearPendingNetworkApplyForCharacterId(key)
    end
    clearPendingNetworkApplyForCharacterId(characterEntityId(character))
end

local function clearCachedLocalNetworkState()
    for key in pairs(characterStates) do
        lastAppliedNetworkLookSignatureByCharacterKey[key] = nil
        clearPendingNetworkApplyForCharacterId(key)
    end
end

local function suppressNetworkApplyForKey(key)
    if key == nil then return end
    suppressedNetworkAppliesByCharacterKey[tostring(key)] = globalTick + NetworkApplySuppressTicks
end

local function clearNetworkApplySuppressionForKey(key)
    if key == nil then return end
    suppressedNetworkAppliesByCharacterKey[tostring(key)] = nil
end

local function suppressNetworkAppliesForCharacter(character)
    if character == nil then return end
    local key = characterStateKey(character)
    if key ~= nil then
        suppressNetworkApplyForKey(key)
    end
    local id = characterEntityId(character)
    if id > 0 then
        suppressNetworkApplyForKey(id)
    end
end

local function clearNetworkApplySuppressionForCharacter(character)
    if character == nil then return end
    local key = characterStateKey(character)
    if key ~= nil then
        clearNetworkApplySuppressionForKey(key)
    end
    local id = characterEntityId(character)
    if id > 0 then
        clearNetworkApplySuppressionForKey(id)
    end
end

local function pruneNetworkApplySuppressions()
    for key, suppressUntilTick in pairs(suppressedNetworkAppliesByCharacterKey) do
        if suppressUntilTick == nil or globalTick > suppressUntilTick then
            suppressedNetworkAppliesByCharacterKey[key] = nil
        end
    end
end

local function networkApplySuppressedForCharacter(characterId, character)
    pruneNetworkApplySuppressions()
    local id = tonumber(characterId) or 0
    if id > 0 and suppressedNetworkAppliesByCharacterKey[tostring(id)] ~= nil then
        return true
    end
    local key = characterStateKey(character)
    return key ~= nil and suppressedNetworkAppliesByCharacterKey[tostring(key)] ~= nil
end

local function preserveSceneTransitionLookIntent()
    local shouldReapplyCurrentLook = hasSavedLook() and (activeLook or autoApplyLook)
    dispatchReducer({ type = "PrepareSceneTransition", reapply = shouldReapplyCurrentLook })
    lastEquipmentSignature = nil
    lastServerAutoApplySignature = nil

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

    return shouldReapplyCurrentLook
end

local function savedLookSummary(lookData, captured)
    lookData = lookData or savedLook
    if captured == nil then captured = savedLookCaptured end
    if not lookDataHasSavedLook(lookData, captured) then return tr("summary.none") end
    local count = 0
    for _, entry in ipairs(slots) do
        if lookData[entry.key] ~= nil then
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

local function managedWearableSlotsAreEmpty(character)
    if character == nil then return false end
    for _, entry in ipairs(slots) do
        local item = getSlotItem(character, entry.slot)
        if item ~= nil and not isIgnoredWardrobeItem(item) then
            return false
        end
    end
    return true
end

local function serverAutoApplyRequestKey(character)
    return tostring(characterStateKey(character) or "unknown") .. "|" .. equipmentSignature(character)
end

local function clearPendingServerApplyRequest()
    pendingServerApplyRequestKey = nil
    pendingServerApplyLastRequestTick = 0
    pendingServerApplyAttempts = 0
end

local function markServerApplyRequested(character)
    local requestKey = serverAutoApplyRequestKey(character)
    if pendingServerApplyRequestKey ~= requestKey then
        pendingServerApplyAttempts = 0
    end
    pendingServerApplyRequestKey = requestKey
    pendingServerApplyLastRequestTick = globalTick
    pendingServerApplyAttempts = pendingServerApplyAttempts + 1
    lastServerAutoApplySignature = requestKey
    return requestKey
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
    local emptyStable = not initialEquipGateSeenEquip and stable and managedWearableSlotsAreEmpty(character)
    local fallbackStable = waitedTicks >= InitialEquipFallbackTicks and stable

    if (quietAfterEquip and stable) or emptyStable or fallbackStable then
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

local function tryClearVisualOverride(character)
    if character == nil then return true end
    if ensureVisualOverride() == nil then return true end
    local ok, reason = pcall(function()
        VisualOverride.ClearCharacter(character)
    end)
    return ok, ok and nil or tostring(reason)
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

local function tryRestoreItemVisuals(character)
    if ensureVisualOverride() == nil then return true end
    if character ~= nil then
        local ok, reason = pcall(function()
            VisualOverride.RestoreCharacterItemVisuals(character)
        end)
        return ok, ok and nil or tostring(reason)
    end
    local ok, reason = pcall(function()
        VisualOverride.RestoreItemVisuals()
    end)
    return ok, ok and nil or tostring(reason)
end

local function beginFashionTransaction(character)
    if ensureVisualOverride() == nil or character == nil then
        return false, "visual override is unavailable"
    end
    local ok, result = pcall(function()
        return VisualOverride.BeginFashionTransaction(character)
    end)
    if not ok then return false, "renderer staging API is unavailable: " .. tostring(result) end
    if result ~= true then return false, "renderer refused to begin a staging transaction" end
    return true
end

local function abortFashionTransaction(character)
    if ensureVisualOverride() == nil or character == nil then return false end
    local ok, result = pcall(function()
        return VisualOverride.AbortFashionTransaction(character)
    end)
    return ok and result == true
end

local function commitFashionTransaction(character)
    if ensureVisualOverride() == nil or character == nil then
        return false, "visual override is unavailable"
    end
    local ok, result = pcall(function()
        return VisualOverride.CommitFashionTransaction(character)
    end)
    if not ok then return false, "renderer commit failed: " .. tostring(result) end
    if result ~= true then return false, "renderer rejected the staged fashion session" end
    return true
end

local function tryCaptureVisualOverride(character, item)
    if ensureVisualOverride() == nil or character == nil or item == nil then
        return false, 0, "fashion item is unavailable"
    end
    local ok, count = pcall(function()
        return VisualOverride.CaptureFashionItem(character, item)
    end)
    if not ok then return false, 0, tostring(count) end
    if count == nil then return false, 0, "renderer returned no capture result" end
    return true, tonumber(count) or 0
end

local function captureVisualOverridePrefab(character, identifier)
    if ensureVisualOverride() == nil or character == nil or identifier == nil or identifier == "" then return 0 end
    local ok, count = pcall(function()
        return VisualOverride.CaptureFashionPrefab(character, tostring(identifier))
    end)
    if ok and count ~= nil then return count end
    return 0
end

local function tryCaptureVisualOverridePrefab(character, identifier)
    if ensureVisualOverride() == nil or character == nil or identifier == nil or identifier == "" then
        return false, 0, "fashion prefab identifier is empty"
    end
    local ok, count = pcall(function()
        return VisualOverride.CaptureFashionPrefab(character, tostring(identifier))
    end)
    if not ok then return false, 0, tostring(count) end
    if count == nil then return false, 0, "renderer returned no prefab capture result" end
    return true, tonumber(count) or 0
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

local function setHideHairVisual(character, hidden)
    if ensureVisualOverride() == nil or character == nil then return false end
    if hidden == nil then hidden = hideHair == true end
    local ok, result = pcall(function()
        return VisualOverride.SetHideHair(character, hidden == true)
    end)
    if not ok then
        -- Surface the failure instead of swallowing it: a missing SetHideHair
        -- method (stale LuaCs assembly cache after an update) is the usual reason
        -- the Hide Hair button appears to "do nothing". Reloading the mod so the
        -- C# plugin recompiles resolves it.
        log("Hide Hair toggle failed: " .. tostring(result) .. ". Reload the mod so LuaCs recompiles the C# plugin.")
        return false
    end
    return result == true
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

local function canReuseCapturedFashion(character)
    if ensureVisualOverride() == nil or character == nil then return false end
    local ok, result = pcall(function()
        return VisualOverride.CanReuseCapturedFashion(character)
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

-- Cross-campaign/cross-server apply: the server may no longer hold this client's
-- saved look (different server, wiped ServerLooks.txt, or a fresh process before
-- the player re-saved). Send the locally saved visual identifiers along with the
-- apply request so the server can always rebuild and broadcast the look, even when
-- its own stored state is missing or stale. The leading boolean lets the server
-- detect whether any payload follows, keeping the message backwards compatible.
local function writeClientLookPayload(message, lookData, captured)
    if message == nil then return end
    message.WriteBoolean(captured == true)
    if captured ~= true then return end
    lookData = lookData or {}
    for _, entry in ipairs(slots) do
        local data = lookData[entry.key]
        local identifier = data ~= nil and tostring(data.identifier or "") or ""
        local hasSlot = data ~= nil and identifier ~= ""
        message.WriteBoolean(hasSlot)
        if hasSlot then
            message.WriteUInt16(tonumber(data.itemId) or 0)
            message.WriteString(identifier)
            message.WriteString(tostring(data.name or ""))
        end
    end
end

local function sendLegacyCommand(command)
    if command == nil or Networking == nil then return false end
    local ok, reason = pcall(function()
        local messageName = nil
        if command.kind == COMMAND_SAVE then
            messageName = NET_SAVE_REQUEST
        elseif command.kind == COMMAND_APPLY then
            messageName = NET_APPLY_REQUEST
        elseif command.kind == COMMAND_CLEAR then
            messageName = NET_CLEAR_REQUEST
        elseif command.kind == COMMAND_FORGET then
            messageName = NET_FORGET_REQUEST
        else
            error("unknown legacy wardrobe command " .. tostring(command.kind))
        end

        local message = Networking.Start(messageName)
        if command.kind == COMMAND_APPLY then
            writeClientLookPayload(message, command.legacyLook, command.captured == true)
        end
        Networking.Send(message)
    end)
    if not ok then
        debugLog("Failed to send v1 wardrobe command: " .. tostring(reason))
    end
    return ok == true
end

local function writeAndSendV2Command(command, baseRevision)
    if not coreAvailable or Networking == nil or command == nil then return false end
    local ok, reason = pcall(function()
        local message = Networking.Start(NET_V2_COMMAND)
        local written, writeReason = Core.writeCommand(message, {
            clientSessionId = clientSessionId,
            operationId = command.operationId,
            baseRevision = baseRevision,
            kind = command.kind,
            look = command.look
        })
        if not written then error(writeReason) end
        Networking.Send(message)
    end)
    if not ok then
        debugLog("Failed to send v2 wardrobe command: " .. tostring(reason))
    end
    return ok == true
end

local function sendNextProtocolCommand()
    if not isMultiplayerClient() or Networking == nil or #protocolCommandQueue == 0 then return false end

    if protocolMode == "v1" then
        local sentAny = false
        while #protocolCommandQueue > 0 do
            local command = table.remove(protocolCommandQueue, 1)
            local sent = sendLegacyCommand(command)
            sentAny = sent or sentAny
            if command.reducerOwned == true and command.feedbackAwaitingFallback == true then
                dispatchReducer({
                    type = sent and "CommandSendSucceeded" or "CommandSendFailed",
                    operationId = command.operationId,
                    awaitAck = false,
                    reason = sent and nil or "v1 wardrobe command could not be sent"
                })
            end
        end
        return sentAny
    end

    if protocolMode ~= "v2" or inFlightV2Command ~= nil then return false end
    local command = protocolCommandQueue[1]
    local baseRevision = reducerState ~= nil and tonumber(reducerState.revision) or 0
    if not writeAndSendV2Command(command, baseRevision) then return false end

    command.baseRevision = baseRevision
    command.sentAt = protocolClock()
    command.attempts = 1
    inFlightV2Command = command
    if command.reducerOwned ~= true then
        dispatchReducer({
            type = "CommandRequested",
            operationId = command.operationId,
            kind = command.kind,
            look = command.look
        })
    end
    return true
end

local function sendV2Hello()
    if not coreAvailable or not isMultiplayerClient() or Networking == nil then return false end
    if protocolMode ~= "probing" or protocolHelloSentAt ~= nil then return false end
    local ok, reason = pcall(function()
        local message = Networking.Start(NET_V2_HELLO)
        local written, writeReason = Core.writeClientHello(message, clientSessionId)
        if not written then error(writeReason) end
        Networking.Send(message)
    end)
    if ok then
        protocolHelloSentAt = protocolClock()
    else
        debugLog("Failed to send v2 hello; waiting for v1 fallback: " .. tostring(reason))
        protocolHelloSentAt = protocolClock()
    end
    return ok == true
end

local function selectV1Protocol(reason)
    if protocolMode == "v1" then return end
    protocolMode = "v1"
    inFlightV2Command = nil
    debugLog("Using v1 wardrobe protocol" .. (reason ~= nil and (": " .. tostring(reason)) or "."))
    sendNextProtocolCommand()
end

local function selectV2Protocol(revision)
    if not coreAvailable then return false end
    protocolMode = "v2"
    local serverRevision = tonumber(revision) or 0
    if clientController == nil then
        reducerState = Core.newClientState({ clientSessionId = clientSessionId, revision = serverRevision })
        clientController = createClientController(reducerState)
    else
        dispatchReducer({ type = "RevisionObserved", revision = serverRevision })
    end
    debugLog("Negotiated wardrobe protocol v2 at revision " .. tostring(serverRevision) .. ".")
    sendNextProtocolCommand()
    return true
end

local function queueProtocolCommand(kind, lookData, captured, operationId, reducerOwned)
    if not isMultiplayerClient() or Networking == nil then return false end
    local domainLook = nil
    if coreAvailable and (kind == COMMAND_SAVE or kind == COMMAND_APPLY) then
        domainLook = domainLookFromLegacy(lookData or {}, captured == true, hideHair == true)
        if domainLook == nil then
            debugLog("Refused to queue invalid wardrobe look for " .. tostring(kind) .. ".")
            return false
        end
    end

    if kind == COMMAND_APPLY and coreAvailable and reducerOwned ~= true then
        local signature = Core.lookSignature(domainLook)
        for _, queued in ipairs(protocolCommandQueue) do
            if queued.kind == COMMAND_APPLY and Core.lookSignature(queued.look) == signature then
                return true, protocolMode ~= "v1"
            end
        end
    elseif (kind == COMMAND_CLEAR or kind == COMMAND_FORGET) and reducerOwned ~= true then
        local queued = protocolCommandQueue[#protocolCommandQueue]
        if queued ~= nil and queued.kind == kind then return true, protocolMode ~= "v1" end
    end
    protocolCommandQueue[#protocolCommandQueue + 1] = {
        kind = kind,
        operationId = operationId or nextOperationId(),
        look = domainLook,
        legacyLook = copyLookData(lookData),
        captured = captured == true,
        reducerOwned = reducerOwned == true,
        feedbackAwaitingFallback = reducerOwned == true and protocolMode == "probing",
        queuedAt = protocolClock(),
        unsentAttempts = 0,
        lastUnsentAttemptAt = 0
    }

    if protocolMode == "probing" then
        sendV2Hello()
        return true, true
    else
        local sent = sendNextProtocolCommand()
        if protocolMode == "v1" then return sent == true, false end
        -- Being queued behind another in-flight v2 command is success. The
        -- queue owns retry/timeout and will feed CommandTimedOut if it can
        -- never put the message on the wire.
        return true, true
    end
end

local function processProtocolNegotiation()
    if not isMultiplayerClient() or Networking == nil then return end
    if protocolMode == "probing" then
        sendV2Hello()
        if protocolHelloSentAt ~= nil and
            protocolClock() - protocolHelloSentAt >= (Core.HELLO_TIMEOUT_SECONDS or 5) then
            selectV1Protocol("server did not answer the v2 hello within 5 seconds")
        end
        return
    end

    if protocolMode == "v2" and inFlightV2Command ~= nil then
        local elapsed = protocolClock() - (inFlightV2Command.sentAt or 0)
        if elapsed >= 1 then
            if (inFlightV2Command.attempts or 1) < 5 then
                if writeAndSendV2Command(inFlightV2Command, inFlightV2Command.baseRevision or 0) then
                    inFlightV2Command.attempts = (inFlightV2Command.attempts or 1) + 1
                    inFlightV2Command.sentAt = protocolClock()
                end
            else
                dispatchReducer({
                    type = "CommandTimedOut",
                    operationId = inFlightV2Command.operationId,
                    reason = "v2 command acknowledgement timed out"
                })
                debugLog("v2 wardrobe command timed out after five idempotent attempts: " .. tostring(inFlightV2Command.operationId))
                table.remove(protocolCommandQueue, 1)
                inFlightV2Command = nil
                sendNextProtocolCommand()
            end
        end
    elseif protocolMode == "v2" and #protocolCommandQueue > 0 then
        local queued = protocolCommandQueue[1]
        local now = protocolClock()
        if now - (queued.lastUnsentAttemptAt or 0) >= 0.25 then
            queued.lastUnsentAttemptAt = now
            if sendNextProtocolCommand() then
                queued.unsentAttempts = 0
            else
                queued.unsentAttempts = (queued.unsentAttempts or 0) + 1
                if queued.unsentAttempts >= 5 then
                    dispatchReducer({
                        type = "CommandTimedOut",
                        operationId = queued.operationId,
                        reason = "v2 command could not be sent after five attempts"
                    })
                    table.remove(protocolCommandQueue, 1)
                    sendNextProtocolCommand()
                end
            end
        end
    end
end

local function requestServerSaveFashion()
    return queueProtocolCommand(COMMAND_SAVE, savedLook, savedLookCaptured == true)
end

local function requestServerApplyFashion(lookData, captured)
    return queueProtocolCommand(COMMAND_APPLY, lookData, captured == true)
end

local function requestServerApplyForCharacter(character)
    if character == nil then return false end
    if not requestServerApplyFashion(savedLook, savedLookCaptured == true) then return false end
    markServerApplyRequested(character)
    return true
end

local function requestServerClearFashion()
    return queueProtocolCommand(COMMAND_CLEAR, nil, false)
end

local function requestServerForgetFashion()
    return queueProtocolCommand(COMMAND_FORGET, nil, false)
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
    if character == nil or lookData == nil then return false, 0, 0, "character or look is missing" end

    local expectedItems = 0
    local capturedItems = 0
    local uniqueItems = 0
    local processedItems = {}
    local processedItemIds = {}
    local processedPrefabIdentifiers = {}

    local function normalizedSavedIdentifier(value)
        return tostring(value or ""):lower():gsub("[^%w]", "")
    end

    local function rememberRealItem(item, savedItemId)
        if item == nil then return false, "none" end

        local runtimeId = tonumber(itemEntityId(item)) or 0
        local rememberedId = runtimeId > 0 and runtimeId or (tonumber(savedItemId) or 0)
        if processedItems[item] then
            return true, "item instance"
        end
        if rememberedId > 0 then
            if processedItemIds[rememberedId] then
                return true, "itemId " .. tostring(rememberedId)
            end
            processedItemIds[rememberedId] = true
        end

        processedItems[item] = true
        return false, rememberedId > 0 and ("itemId " .. tostring(rememberedId)) or "item instance"
    end

    local function rememberPrefabIdentifier(identifier)
        local normalized = normalizedSavedIdentifier(identifier)
        if normalized == "" then return false, "empty identifier" end
        if processedPrefabIdentifiers[normalized] then
            return true, normalized
        end
        processedPrefabIdentifiers[normalized] = true
        return false, normalized
    end

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
                local duplicate, duplicateKey = rememberRealItem(item, itemId)
                local captured = 0
                local capturedOk = true
                local captureReason = nil
                if not duplicate then
                    uniqueItems = uniqueItems + 1
                    capturedOk, captured, captureReason = tryCaptureVisualOverride(character, item)
                    if capturedOk then capturedItems = capturedItems + 1 end
                end
                if diagnostics ~= nil then
                    diagnostics[#diagnostics + 1] =
                        entry.key .. ": identifier=" .. tostring(identifier) ..
                        ", itemId=" .. tostring(itemId) ..
                        ", savedName=" .. tostring(data.name) ..
                        ", found=" .. foundBy ..
                        (duplicate and (", duplicate=reused real item " .. tostring(duplicateKey)) or "") ..
                        ", capturedSprites=" .. tostring(captured) ..
                        (captureReason ~= nil and (", error=" .. tostring(captureReason)) or "")
                end
                if not capturedOk then return false, expectedItems, capturedItems, captureReason end
            else
                local duplicate, duplicateKey = rememberPrefabIdentifier(identifier)
                local captured = 0
                local capturedOk = true
                local captureReason = nil
                if not duplicate then
                    uniqueItems = uniqueItems + 1
                    capturedOk, captured, captureReason = tryCaptureVisualOverridePrefab(character, identifier)
                    if capturedOk then capturedItems = capturedItems + 1 end
                end
                if diagnostics ~= nil then
                    diagnostics[#diagnostics + 1] =
                        entry.key .. ": identifier=" .. tostring(identifier) ..
                        ", itemId=" .. tostring(itemId) ..
                        ", savedName=" .. tostring(data.name) ..
                        ", found=missing item instance" ..
                        (duplicate and (", duplicate=reused prefab " .. tostring(duplicateKey)) or "") ..
                        ", prefabCapturedSprites=" .. tostring(captured) ..
                        (captureReason ~= nil and (", error=" .. tostring(captureReason)) or "")
                end
                if not capturedOk then return false, expectedItems, capturedItems, captureReason end
            end
        end
    end

    if expectedItems == 0 then
        local emptyOk, emptyReason = tryCaptureEmptyVisualOverride(character)
        if not emptyOk then return false, 0, 0, emptyReason end
        if diagnostics ~= nil then
            diagnostics[#diagnostics + 1] = "look had no saved slots; captured empty look"
        end
        return true, expectedItems, capturedItems, nil
    end

    if capturedItems ~= uniqueItems then
        if diagnostics ~= nil then
            diagnostics[#diagnostics + 1] =
                "incomplete fashion capture: " .. tostring(capturedItems) .. "/" .. tostring(uniqueItems)
        end
        return false, expectedItems, capturedItems, "one or more unique fashion items could not be captured"
    end

    return true, expectedItems, capturedItems, nil
end

local function applyCapturedFashionToCharacterEquipment(character, lookData, recapturePayload, hairHidden)
    if character == nil then return false, 0 end

    local look = lookData or savedLook
    if recapturePayload ~= false then
        local begun, beginReason = beginFashionTransaction(character)
        if not begun then return false, 0, beginReason end
        local captured, _, _, captureReason = captureFashionPayloadFromLook(character, look)
        if not captured then
            abortFashionTransaction(character)
            return false, 0, captureReason
        end
        if not setFashionSlotMask(character, look) then
            abortFashionTransaction(character)
            return false, 0, "renderer rejected the staged fashion slot mask"
        end
        if character == controlled() or hairHidden ~= nil then
            if not setHideHairVisual(character, hairHidden) then
                abortFashionTransaction(character)
                return false, 0, "renderer rejected the staged hair visibility"
            end
        end
        local committed, commitReason = commitFashionTransaction(character)
        if not committed then
            abortFashionTransaction(character)
            return false, 0, commitReason
        end
    else
        if not setFashionSlotMask(character, look) then
            return false, 0
        end
        if (character == controlled() or hairHidden ~= nil) and not setHideHairVisual(character, hairHidden) then
            return false, 0
        end
    end

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

    local activated = activateFashionVisual(character)
    if not activated then return false, visualItems, "renderer activation failed" end
    return true, visualItems, nil
end

local function applyNetworkLook(character, networkLook, hairHidden)
    local diagnostics = {}
    if character == nil or networkLook == nil then return false, diagnostics end
    local visualStatus = visualOverrideStatus()
    if visualStatus ~= nil then
        diagnostics[#diagnostics + 1] = "visual override not ready: " .. tostring(visualStatus)
        return false, diagnostics
    end

    local begun, beginReason = beginFashionTransaction(character)
    if not begun then
        diagnostics[#diagnostics + 1] = tostring(beginReason)
        return false, diagnostics
    end

    local capturedPayload, expectedItems, capturedItems, captureReason =
        captureFashionPayloadFromLook(character, networkLook, diagnostics)
    if not capturedPayload or not setFashionSlotMask(character, networkLook) or
        not setHideHairVisual(character, hairHidden) then
        abortFashionTransaction(character)
        diagnostics[#diagnostics + 1] = tostring(captureReason or "renderer rejected staged look metadata")
        return false, diagnostics
    end

    local committed, commitReason = commitFashionTransaction(character)
    if not committed then
        abortFashionTransaction(character)
        diagnostics[#diagnostics + 1] = tostring(commitReason)
        return false, diagnostics
    end

    local activated = applyCapturedFashionToCharacterEquipment(character, networkLook, false, hairHidden)
    diagnostics[#diagnostics + 1] = "activated=" .. tostring(activated == true) .. ", expectedItems=" .. tostring(expectedItems) .. ", capturedItems=" .. tostring(capturedItems)
    return activated == true, diagnostics
end

-- Adapters are the only impure boundary for reducer effects. In particular,
-- renderer capture is staged and never clears the previously accepted session.
-- The staged session is committed only after every local unequip succeeds.
local pendingSaveContext = nil

clientEffectAdapters.Capture = function(currentEffect)
    local character = controlled()
    if character == nil then return false, "no controlled character" end
    local overrideState = visualOverrideState()
    if not overrideState.ready then return false, tostring(overrideState.details or overrideState.label) end

    local startingItems = snapshot(character)
    local lookData = visualSnapshot(character)
    local domainLook, lookReason = domainLookFromLegacy(lookData, true, hideHair == true)
    if domainLook == nil then return false, tostring(lookReason or "captured look failed schema v2 validation") end
    rememberLegacyLookMetadata(lookData)

    local context = {
        character = character,
        startingItems = startingItems,
        lookData = lookData,
        domainLook = domainLook,
        remote = currentEffect.remote == true,
        capturedSprites = 0,
        startingItemCount = 0,
        staged = false
    }

    if not context.remote then
        local begun, beginReason = beginFashionTransaction(character)
        if not begun then return false, beginReason end
        context.staged = true
        local processedItems = {}
        for _, entry in ipairs(slots) do
            local item = startingItems[entry.key]
            if item ~= nil and not processedItems[item] then
                processedItems[item] = true
                context.startingItemCount = context.startingItemCount + 1
                local captured, spriteCount, captureReason = tryCaptureVisualOverride(character, item)
                if not captured then
                    abortFashionTransaction(character)
                    return false, entry.key .. ": " .. tostring(captureReason)
                end
                context.capturedSprites = context.capturedSprites + spriteCount
            end
        end
        if context.startingItemCount == 0 then
            local emptyCaptured, emptyReason = tryCaptureEmptyVisualOverride(character)
            if not emptyCaptured then
                abortFashionTransaction(character)
                return false, emptyReason
            end
        end
        if not setFashionSlotMask(character, lookData) or not setHideHairVisual(character, hideHair) then
            abortFashionTransaction(character)
            return false, "renderer rejected staged slot or hair metadata"
        end
    else
        for _, entry in ipairs(slots) do
            if startingItems[entry.key] ~= nil then context.startingItemCount = context.startingItemCount + 1 end
        end
    end

    pendingSaveContext = context
    return { type = "CaptureSucceeded", look = domainLook }
end

clientEffectAdapters.AbortCapture = function()
    if pendingSaveContext ~= nil and pendingSaveContext.character ~= nil and pendingSaveContext.staged then
        abortFashionTransaction(pendingSaveContext.character)
    end
    pendingSaveContext = nil
    return true
end

clientEffectAdapters.Unequip = function()
    local context = pendingSaveContext
    if context == nil or context.character == nil or not context.staged then
        return false, "save capture context is missing"
    end

    local results = {}
    local failedItems = {}
    local removedItems = 0
    local processedItems = {}
    local function restoreStartingEquipment()
        local restoredItems = {}
        for _, entry in ipairs(slots) do
            local item = context.startingItems[entry.key]
            if item ~= nil and not restoredItems[item] then
                restoredItems[item] = true
                pcall(function() item.Equip(context.character) end)
            end
        end
        local missing = {}
        for _, entry in ipairs(slots) do
            local item = context.startingItems[entry.key]
            if item ~= nil and not isInSlot(context.character, item, entry.slot) then
                missing[#missing + 1] = entry.key .. ": " .. itemName(item)
            end
        end
        return #missing == 0, missing
    end
    for _, entry in ipairs(slots) do
        local item = context.startingItems[entry.key]
        if item == nil then
            results[entry.key] = "Empty"
        elseif processedItems[item] then
            results[entry.key] = "Already handled"
        else
            processedItems[item] = true
            local removed = unequipItem(context.character, item)
            local remainingSlots = wornSlotLabelsForItem(context.character, item)
            if removed and #remainingSlots == 0 then
                removedItems = removedItems + 1
                results[entry.key] = "Saved and removed"
            else
                local result = "Still equipped in " .. table.concat(remainingSlots, ", ")
                results[entry.key] = result
                failedItems[#failedItems + 1] = slotLabel(entry) .. ": " .. itemName(item)
            end
        end
    end

    if #failedItems > 0 then
        abortFashionTransaction(context.character)
        local restored, rollbackFailures = restoreStartingEquipment()
        pendingSaveContext = nil
        lastNetworkApplyDiagnostics = { "unequip transaction failed: " .. table.concat(failedItems, "; ") }
        local reason = "one or more fashion items remained equipped: " .. table.concat(failedItems, "; ")
        if not restored then
            reason = reason .. "; equipment rollback failed for " .. table.concat(rollbackFailures, "; ")
        end
        return false, reason
    end

    local committed, commitReason = commitFashionTransaction(context.character)
    if not committed then
        abortFashionTransaction(context.character)
        local restored, rollbackFailures = restoreStartingEquipment()
        pendingSaveContext = nil
        if not restored then
            commitReason = tostring(commitReason) .. "; equipment rollback failed for " ..
                table.concat(rollbackFailures, "; ")
        end
        return false, commitReason
    end

    slotResults = results
    lastCharacter = context.character
    lastEquipmentSignature = nil
    lastServerAutoApplySignature = nil
    clearPendingServerApplyRequest()
    clearNetworkApplySuppressionForCharacter(context.character)
    local message
    if context.startingItemCount == 0 then
        message = "Saved current outfit: empty outfit captured."
    else
        message = "Saved current outfit: " .. tostring(context.capturedSprites) ..
            " wearable sprites captured, " .. tostring(removedItems) ..
            " item" .. (removedItems == 1 and "" or "s") .. " removed."
    end
    pendingSaveContext = nil
    log(message)
    return { type = "UnequipSucceeded" }
end

clientEffectAdapters.SendCommand = function(currentEffect)
    local lookData = legacyLookFromDomain(currentEffect.look)
    local captured = currentEffect.look ~= nil and currentEffect.look.captured == true
    local queued, awaitAck = queueProtocolCommand(
        currentEffect.kind,
        lookData,
        captured,
        currentEffect.operationId,
        true
    )
    if not queued then
        pendingSaveContext = nil
        return false, "wardrobe command could not be queued"
    end
    if currentEffect.kind == COMMAND_SAVE and pendingSaveContext ~= nil then
        local context = pendingSaveContext
        local results = {}
        for _, entry in ipairs(slots) do
            results[entry.key] = context.lookData[entry.key] ~= nil and "Saved; server removal requested" or "Empty"
        end
        slotResults = results
        lastCharacter = context.character
        lastEquipmentSignature = nil
        lastServerAutoApplySignature = nil
        clearPendingServerApplyRequest()
        log("Saved current outfit; server-side removal requested for multiplayer.")
        pendingSaveContext = nil
    end
    return {
        type = "CommandSendSucceeded",
        operationId = currentEffect.operationId,
        awaitAck = awaitAck == true
    }
end

clientEffectAdapters.Persist = function(currentEffect, viewModel)
    local persisted, reason = persistClientLook(currentEffect.look, viewModel)
    if persisted then
        return { type = "PersistenceSucceeded" }
    end
    return false, reason or "client look could not be written atomically"
end

clientEffectAdapters.ClearPersistence = function()
    local cleared, reason = clearPersistentClientLook()
    if cleared then return { type = "PersistenceSucceeded" } end
    return false, reason or "client look could not be cleared atomically"
end

clientEffectAdapters.Render = function(currentEffect)
    local character = currentEffect.characterId ~= nil and findEntityById(currentEffect.characterId) or controlled()
    if character == nil then return false, "render target character is unavailable" end
    local lookData = legacyLookFromDomain(currentEffect.look)
    local applied, diagnostics
    local visualItems = 0
    if currentEffect.characterId ~= nil then
        applied, diagnostics = applyNetworkLook(character, lookData, currentEffect.look.hideHair == true)
    else
        local reason
        local reuseCapturedSession = canReuseCapturedFashion(character)
        applied, visualItems, reason = applyCapturedFashionToCharacterEquipment(
            character,
            lookData,
            not reuseCapturedSession,
            currentEffect.look.hideHair == true
        )
        diagnostics = reason ~= nil and { reason } or
            (reuseCapturedSession and { "reused committed renderer session" } or {})
    end
    if not applied then
        lastNetworkApplyDiagnostics = diagnostics or {}
        return false, table.concat(lastNetworkApplyDiagnostics, "; ")
    end

    lastCharacter = character
    lastEquipmentSignature = equipmentSignature(character)
    lastNetworkApplyDiagnostics = diagnostics or {}
    slotResults = {}
    for _, entry in ipairs(slots) do
        slotResults[entry.key] = lookData[entry.key] ~= nil and
            (currentEffect.characterId ~= nil and "Synced from server" or "Saved and applied") or "Empty"
    end
    clearPendingServerApplyRequest()
    if currentEffect.characterId ~= nil then
        lastOperation = "Saved look applied from multiplayer sync."
    else
        lastOperation = "Saved look applied. Checked " .. tostring(visualItems) .. " worn item(s)."
    end
    return { type = "RenderSucceeded", revision = currentEffect.revision }
end

clientEffectAdapters.RenderCompensation = function(currentEffect)
    local character = controlled()
    if character == nil then return { type = "CompensationFailed", reason = "no controlled character" } end
    local lookData = legacyLookFromDomain(currentEffect.look)
    local applied, _, reason = applyCapturedFashionToCharacterEquipment(
        character,
        lookData,
        true,
        currentEffect.look.hideHair == true
    )
    if applied then return { type = "CompensationSucceeded" } end
    return { type = "CompensationFailed", reason = reason }
end

clientEffectAdapters.ClearRender = function(currentEffect)
    local character = currentEffect.characterId ~= nil and findEntityById(currentEffect.characterId) or controlled()
    if character == nil then character = lastCharacter end
    local ok, reason
    if currentEffect.dispose == true or currentEffect.forget == true or currentEffect.remote == true then
        ok, reason = tryClearVisualOverride(character)
    else
        ok, reason = tryRestoreItemVisuals(character)
    end
    if not ok then return false, reason end
    deactivateCachedCharacterStates(currentEffect.preserveAutoApply == true)
    clearLocalPendingNetworkState(character)
    lastEquipmentSignature = nil
    lastServerAutoApplySignature = nil
    clearPendingServerApplyRequest()
    pendingRoundStartNetworkLook = nil
    pendingRoundStartNetworkCharacterKey = nil
    pendingRoundStartNetworkRevision = nil
    pendingRoundStartHideHair = false
    if currentEffect.forget == true then
        characterStates = {}
        slotResults = {}
    end
    return {
        type = "ClearRenderSucceeded",
        forget = currentEffect.forget == true,
        save = currentEffect.save == true,
        preserveAutoApply = currentEffect.preserveAutoApply == true
    }
end

clientEffectAdapters.ClearRenderCompensation = function(currentEffect)
    local character = currentEffect.characterId ~= nil and findEntityById(currentEffect.characterId) or controlled()
    if character == nil then character = lastCharacter end
    local ok, reason = tryClearVisualOverride(character)
    if ok then return { type = "CompensationSucceeded" } end
    return { type = "CompensationFailed", reason = reason }
end

clientEffectAdapters.SetHair = function(currentEffect)
    local character = controlled()
    if character == nil then return false, "no controlled character" end
    if setHideHairVisual(character, currentEffect.hidden == true) then
        return { type = "HairUpdateSucceeded" }
    end
    return false, "renderer rejected hair visibility"
end

clientEffectAdapters.SetHairCompensation = function(currentEffect)
    local character = controlled()
    if character ~= nil and setHideHairVisual(character, currentEffect.hidden == true) then
        return { type = "CompensationSucceeded" }
    end
    return { type = "CompensationFailed", reason = "hair visibility rollback failed" }
end

local function saveFashionAndUnequip()
    local character = controlled()
    if character == nil then
        log("No controlled character.")
        return false
    end
    clearNetworkApplySuppressionForCharacter(character)
    local remote = isMultiplayerClient()
    local operationId = remote and nextOperationId() or nil
    dispatchReducer({
        type = "SaveRequested",
        remote = remote,
        operationId = operationId
    })
    local state = clientController ~= nil and clientController.getState() or reducerState
    if state ~= nil and state.phase == Core.PHASE.Faulted then
        log("Save failed: " .. tostring(state.error or "unknown adapter failure"))
        return false
    end
    return true
end

local function applyFashionToCurrentEquipment(silent)
    local character = controlled()
    if character == nil then
        if not silent then log("No controlled character.") end
        return false
    end

    if not hasSavedLook() then
        if not silent then log("No saved look. Save an outfit first.") end
        return false
    end

    local visualStatus = visualOverrideStatus()
    if visualStatus ~= nil then
        if not silent then log(visualStatus) end
        return false
    end

    if not silent then
        clearNetworkApplySuppressionForCharacter(character)
    end

    local domainLook = currentDomainLook()
    if isMultiplayerClient() then
        local operationId = nextOperationId()
        dispatchReducer({
            type = "CommandRequested",
            operationId = operationId,
            kind = COMMAND_APPLY,
            look = domainLook
        })
        markServerApplyRequested(character)
    else
        dispatchReducer({ type = "LocalApplyRequested", look = domainLook })
    end
    local state = clientController ~= nil and clientController.getState() or reducerState
    if state ~= nil and state.phase == Core.PHASE.Faulted then
        if not silent then log("Saved look could not be applied: " .. tostring(state.error)) end
        return false
    end
    if not silent and isMultiplayerClient() then log("Requested multiplayer wardrobe apply from the server.") end
    return true
end

local function clearActiveLook()
    local character = controlled()
    local multiplayerClearRequested = isMultiplayerClient()
    if multiplayerClearRequested then
        dispatchReducer({
            type = "CommandRequested",
            operationId = nextOperationId(),
            kind = COMMAND_CLEAR
        })
    else
        dispatchReducer({ type = "LocalClearRequested" })
    end
    clearLocalPendingNetworkState(character)
    suppressNetworkAppliesForCharacter(character)
    local state = clientController ~= nil and clientController.getState() or reducerState
    if state ~= nil and state.phase == Core.PHASE.Faulted then
        log("Look clear failed: " .. tostring(state.error))
    elseif multiplayerClearRequested then
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
    else
        lastEquipmentSignature = nil
        lastOperation = "Saved look needs to be applied again."
    end
end

local function autoApplySavedLookIfNeeded(character)
    if character == nil or activeLook or not autoApplyLook or not hasSavedLook() then return end
    local view = clientController ~= nil and clientController.getViewModel() or nil
    if view ~= nil and view.busy then return end
    if applyFashionToCurrentEquipment(true) then
        lastOperation = "Saved look auto-applied."
    end
end

local function handleNoControlledCharacter()
    if lastCharacter ~= nil then
        saveCharacterState(lastCharacter)
    end

    local shouldReapplySavedLook = hasSavedLook() and (activeLook or autoApplyLook)
    lastEquipmentSignature = nil
    lastServerAutoApplySignature = nil
    clearPendingServerApplyRequest()
    lastCharacter = nil

    if hasSavedLook() then
        if shouldReapplySavedLook then
            dispatchReducer({ type = "SetAutoApply", enabled = true })
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
        clearPendingServerApplyRequest()
        if hasSavedLook() then
            lastOperation = autoApplyLook and
                "Saved look will be reapplied for the new character." or
                "Saved look needs to be applied again."
        else
            lastOperation = "Controlled character changed. Save a new outfit for this character."
        end
    end
    dispatchReducer({
        type = "RestoreLook",
        look = currentDomainLook(),
        active = activeLook == true,
        autoApply = autoApplyLook == true
    })
    pruneVisualOverrides()
end

local function clearSavedLook()
    local character = controlled()
    local multiplayerForgetRequested = isMultiplayerClient()
    if multiplayerForgetRequested then
        dispatchReducer({
            type = "CommandRequested",
            operationId = nextOperationId(),
            kind = COMMAND_FORGET
        })
    else
        dispatchReducer({ type = "LocalForgetRequested" })
    end
    local state = clientController ~= nil and clientController.getState() or reducerState
    if state ~= nil and state.phase == Core.PHASE.Faulted then
        log("Saved look was not forgotten: " .. tostring(state.error))
        return false
    end
    clearLocalPendingNetworkState(character)
    clearCachedLocalNetworkState()
    suppressNetworkAppliesForCharacter(character)
    if multiplayerForgetRequested then
        log("Server saved look deletion requested; local look will be cleared after acknowledgement.")
    else
        log("Saved look cleared.")
    end
    return true
end

local function deferRoundStartNetworkLook(character, networkLook, protocolRevision, hairHidden)
    lastCharacter = character
    pendingRoundStartNetworkLook = copyLookData(networkLook)
    pendingRoundStartNetworkCharacterKey = characterStateKey(character)
    pendingRoundStartNetworkRevision = protocolRevision
    pendingRoundStartHideHair = hairHidden == true
    slotResults = {}
    lastNetworkApplyDiagnostics = { "waiting for initial equipment to finish equipping" }
    for _, entry in ipairs(slots) do
        slotResults[entry.key] = networkLook[entry.key] ~= nil and "Waiting for initial equipment" or "Empty"
    end
    lastOperation = "Multiplayer wardrobe sync is waiting for initial equipment."
end

local function applyPendingRoundStartNetworkLook(character)
    if character == nil or pendingRoundStartNetworkLook == nil then return false end
    if pendingRoundStartNetworkCharacterKey ~= characterStateKey(character) then return false end

    local networkLook = copyLookData(pendingRoundStartNetworkLook)
    local protocolRevision = pendingRoundStartNetworkRevision
    local hairHidden = pendingRoundStartHideHair
    pendingRoundStartNetworkLook = nil
    pendingRoundStartNetworkCharacterKey = nil
    pendingRoundStartNetworkRevision = nil
    pendingRoundStartHideHair = false

    if protocolRevision ~= nil then
        local domainLook = domainLookFromLegacy(networkLook, true, hairHidden)
        rememberLegacyLookMetadata(networkLook)
        local effects = dispatchReducer({
            type = "RemoteStateReceived",
            revision = protocolRevision,
            characterId = characterEntityId(character),
            active = true,
            look = domainLook
        })
        if effectsContain(effects, "IgnoredStaleState") or
            effectsContain(effects, "IgnoredSupersededState") then
            return false
        end
        local acceptedState = clientController ~= nil and clientController.getState() or reducerState
        if acceptedState ~= nil and acceptedState.phase == Core.PHASE.Active then
            local key = characterStateKey(character)
            if key ~= nil then
                lastAppliedNetworkLookSignatureByCharacterKey[key] =
                    key .. "|" .. lookDataSignature(networkLook, true) .. "|" .. equipmentSignature(character)
            end
            lastOperation = "Saved look applied from multiplayer sync after initial equipment."
        else
            lastOperation = "Multiplayer wardrobe sync failed after initial equipment; dump debug log."
        end
        return true
    end

    local domainLook = domainLookFromLegacy(networkLook, true, hideHair)
    rememberLegacyLookMetadata(networkLook)
    dispatchReducer({ type = "LocalApplyRequested", look = domainLook })
    local acceptedState = clientController ~= nil and clientController.getState() or reducerState
    if acceptedState ~= nil and acceptedState.phase == Core.PHASE.Active then
        local key = characterStateKey(character)
        if key ~= nil then
            lastAppliedNetworkLookSignatureByCharacterKey[key] =
                key .. "|" .. lookDataSignature(networkLook, true) .. "|" .. equipmentSignature(character)
        end
        lastOperation = "Saved look applied from multiplayer sync after initial equipment."
    else
        lastOperation = "Multiplayer wardrobe sync failed after initial equipment; dump debug log."
    end
    return true
end

local function networkApplySignature(character, networkLook)
    local key = characterStateKey(character)
    if key == nil then return nil end
    return key .. "|" .. lookDataSignature(networkLook, true) .. "|" .. equipmentSignature(character)
end

local function rememberNetworkLookApplied(character, networkLook)
    local key = characterStateKey(character)
    local signature = networkApplySignature(character, networkLook)
    if key == nil or signature == nil then return end
    lastAppliedNetworkLookSignatureByCharacterKey[key] = signature
end

local function networkLookAlreadyApplied(character, networkLook)
    local key = characterStateKey(character)
    local signature = networkApplySignature(character, networkLook)
    return key ~= nil and signature ~= nil and lastAppliedNetworkLookSignatureByCharacterKey[key] == signature
end

local function storePendingNetworkApply(characterId, networkLook, protocolRevision, hairHidden, protocolLook)
    pendingNetworkAppliesByCharacterId[characterId] = {
        look = copyLookData(networkLook),
        receivedTick = globalTick,
        protocolRevision = protocolRevision,
        hideHair = hairHidden == true,
        protocolLook = coreAvailable and Core.copyLook(protocolLook) or nil
    }
end

local function storePendingNetworkClear(characterId, protocolRevision, protocolLook)
    pendingNetworkAppliesByCharacterId[characterId] = nil
    pendingNetworkClearsByCharacterId[characterId] = {
        receivedTick = globalTick,
        protocolRevision = protocolRevision,
        protocolLook = coreAvailable and Core.copyLook(protocolLook) or nil
    }
end

local function handleNetworkLookApply(characterId, networkLook, protocolRevision, hairHidden, protocolLook)
    if protocolRevision == nil and networkApplySuppressedForCharacter(characterId, nil) then
        pendingNetworkAppliesByCharacterId[characterId] = nil
        debugLog("Ignored suppressed multiplayer wardrobe apply for characterId=" .. tostring(characterId) .. ".")
        return false
    end

    local character = findEntityById(characterId)
    if character == nil then
        storePendingNetworkApply(characterId, networkLook, protocolRevision, hairHidden, protocolLook)
        return false
    end

    pendingNetworkAppliesByCharacterId[characterId] = nil

    if character == controlled() and initialEquipGateActive and not initialEquipGateReady(character) then
        deferRoundStartNetworkLook(character, networkLook, protocolRevision, hairHidden)
        return true
    end

    if protocolRevision ~= nil and character == controlled() then
        local domainLook = protocolLook or domainLookFromLegacy(networkLook, true, hairHidden)
        rememberLegacyLookMetadata(networkLook)
        local effects = dispatchReducer({
            type = "RemoteStateReceived",
            revision = protocolRevision,
            characterId = characterId,
            active = true,
            look = domainLook
        })
        if effectsContain(effects, "IgnoredStaleState") or
            effectsContain(effects, "IgnoredSupersededState") then
            return false
        end
        if effectsContain(effects, "IgnoredDuplicateState") then return true end
        local acceptedState = clientController ~= nil and clientController.getState() or reducerState
        if acceptedState ~= nil and acceptedState.phase == Core.PHASE.Active then
            rememberNetworkLookApplied(character, networkLook)
            return true
        end
        return false
    end

    if protocolRevision == nil and character == controlled() then
        if networkApplySuppressedForCharacter(characterId, character) then
            debugLog("Ignored suppressed multiplayer wardrobe apply for characterId=" .. tostring(characterId) .. ".")
            return false
        end
        local domainLook = domainLookFromLegacy(networkLook, true, hideHair)
        rememberLegacyLookMetadata(networkLook)
        dispatchReducer({ type = "LocalApplyRequested", look = domainLook })
        local acceptedState = clientController ~= nil and clientController.getState() or reducerState
        if acceptedState ~= nil and acceptedState.phase == Core.PHASE.Active then
            rememberNetworkLookApplied(character, networkLook)
            return true
        end
        return false
    end

    if protocolRevision == nil and networkApplySuppressedForCharacter(characterId, character) then
        debugLog("Ignored suppressed multiplayer wardrobe apply for characterId=" .. tostring(characterId) .. ".")
        return false
    end

    if networkLookAlreadyApplied(character, networkLook) then
        return true
    end

    local networkHideHair = nil
    if protocolRevision ~= nil then networkHideHair = hairHidden == true end
    local applied, diagnostics = applyNetworkLook(character, networkLook, networkHideHair)
    if applied then
        rememberNetworkLookApplied(character, networkLook)
    end
    return true
end

local function handleNetworkLookClear(characterId, protocolRevision, protocolLook)
    pendingNetworkAppliesByCharacterId[characterId] = nil
    local character = findEntityById(characterId)
    if character == nil then
        storePendingNetworkClear(characterId, protocolRevision, protocolLook)
        return false
    end

    pendingNetworkClearsByCharacterId[characterId] = nil
    if protocolRevision ~= nil and character == controlled() then
        if protocolLook ~= nil then
            local canonicalLegacy = Core.toLegacyLook(protocolLook)
            if canonicalLegacy ~= nil then rememberLegacyLookMetadata(canonicalLegacy) end
        end
        local effects = dispatchReducer({
            type = "RemoteStateReceived",
            revision = protocolRevision,
            characterId = characterId,
            active = false,
            look = protocolLook
        })
        if effectsContain(effects, "IgnoredStaleState") then return false end
        local acceptedState = clientController ~= nil and clientController.getState() or reducerState
        if acceptedState ~= nil and acceptedState.phase == Core.PHASE.Faulted then
            return false
        end
        lastOperation = "Look cleared from multiplayer sync."
        return true
    end
    if protocolRevision == nil and character == controlled() then
        local currentState = clientController ~= nil and clientController.getState() or reducerState
        if currentState ~= nil and Core.hasLook(currentState.look) and currentState.active then
            dispatchReducer({ type = "LocalClearRequested" })
        else
            tryClearVisualOverride(character)
        end
        lastOperation = "Look cleared from multiplayer sync."
        return true
    end
    clearVisualOverride(character)
    local key = characterStateKey(character)
    if key ~= nil then
        lastAppliedNetworkLookSignatureByCharacterKey[key] = nil
    end
    return true
end

local function processPendingNetworkMessages()
    pruneNetworkApplySuppressions()

    for characterId, pending in pairs(pendingNetworkClearsByCharacterId) do
        if globalTick - pending.receivedTick > PendingNetworkMessageMaxTicks then
            pendingNetworkClearsByCharacterId[characterId] = nil
        elseif findEntityById(characterId) ~= nil then
            handleNetworkLookClear(characterId, pending.protocolRevision, pending.protocolLook)
        end
    end

    for characterId, pending in pairs(pendingNetworkAppliesByCharacterId) do
        if globalTick - pending.receivedTick > PendingNetworkMessageMaxTicks then
            pendingNetworkAppliesByCharacterId[characterId] = nil
        elseif findEntityById(characterId) ~= nil then
            handleNetworkLookApply(
                characterId,
                pending.look,
                pending.protocolRevision,
                pending.hideHair,
                pending.protocolLook
            )
        end
    end
end

if Networking ~= nil then
    Networking.Receive(NET_LOOK_APPLY, function(message)
        if protocolMode == "v2" then return end
        if protocolMode == "probing" then selectV1Protocol("received a v1 look update") end
        local characterId, networkLook = readNetworkLook(message)
        handleNetworkLookApply(characterId, networkLook)
    end)

    Networking.Receive(NET_LOOK_CLEAR, function(message)
        if protocolMode == "v2" then return end
        if protocolMode == "probing" then selectV1Protocol("received a v1 clear update") end
        local characterId = message.ReadUInt16()
        handleNetworkLookClear(characterId)
    end)

    if coreAvailable then
        Networking.Receive(NET_V2_HELLO, function(message)
            local ok, response, reason = pcall(Core.readServerHello, message)
            if not ok or response == nil then
                debugLog("Ignored malformed v2 hello response: " .. tostring(ok and reason or response))
                return
            end
            selectV2Protocol(response.revision)
        end)

        Networking.Receive(NET_V2_ACK, function(message)
            local ack, reason = Core.tryReadAck(message)
            if ack == nil then
                debugLog("Ignored malformed v2 acknowledgement: " .. tostring(reason))
                return
            end
            if protocolMode ~= "v2" then selectV2Protocol(0) end

            local effects = dispatchReducer({
                type = "AckReceived",
                operationId = ack.operationId,
                accepted = ack.accepted,
                revision = ack.revision,
                reason = ack.reason
            })
            if effectsContain(effects, "IgnoredStaleAck") then
                debugLog("Ignored stale v2 acknowledgement for " .. tostring(ack.operationId) .. ".")
            end

            if inFlightV2Command ~= nil and inFlightV2Command.operationId == ack.operationId then
                if not ack.accepted then
                    lastOperation = "Server rejected wardrobe command: " .. tostring(ack.reason or "unknown reason")
                    debugLog(lastOperation)
                end
                if protocolCommandQueue[1] ~= nil and protocolCommandQueue[1].operationId == ack.operationId then
                    table.remove(protocolCommandQueue, 1)
                end
                inFlightV2Command = nil
                sendNextProtocolCommand()
            end
        end)

        Networking.Receive(NET_V2_STATE, function(message)
            local state, reason = Core.tryReadState(message)
            if state == nil then
                debugLog("Ignored malformed v2 wardrobe state: " .. tostring(reason))
                return
            end
            if protocolMode ~= "v2" then selectV2Protocol(0) end

            local characterId = tonumber(state.characterId) or 0
            local character = findEntityById(characterId)
            local controlledCharacter = controlled()
            local belongsToControlledCharacter =
                character ~= nil and controlledCharacter ~= nil and character == controlledCharacter

            if not belongsToControlledCharacter then
                local lastRevision = tonumber(remoteRevisionByCharacterId[characterId]) or -1
                if state.revision < lastRevision then
                    debugLog(
                        "Ignored stale v2 state for remote character " ..
                        tostring(characterId) ..
                        " at revision " ..
                        tostring(state.revision) ..
                        "."
                    )
                    return
                end
                remoteRevisionByCharacterId[characterId] = state.revision
            end

            local legacyLook = nil
            if state.look ~= nil then
                legacyLook, reason = Core.toLegacyLook(state.look)
                if legacyLook == nil then
                    debugLog("Ignored invalid v2 state look: " .. tostring(reason))
                    return
                end
            end

            if state.active then
                handleNetworkLookApply(
                    characterId,
                    legacyLook,
                    state.revision,
                    state.look.hideHair == true,
                    state.look
                )
            else
                handleNetworkLookClear(characterId, state.revision, state.look)
            end
        end)
    end
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

local function clientViewModelSnapshot(character, overrideState)
    local reducerView = clientController ~= nil and clientController.getViewModel() or {
        phase = "Legacy",
        hasSavedLook = hasSavedLook(),
        active = activeLook == true,
        autoApply = autoApplyLook == true,
        canSave = character ~= nil,
        canApply = character ~= nil and hasSavedLook(),
        canClear = character ~= nil,
        canForget = hasSavedLook(),
        error = nil
    }
    local lookCopy = copyLookData(savedLook)
    local resultCopy = {}
    local currentNames = {}
    for _, entry in ipairs(slots) do
        resultCopy[entry.key] = slotResults[entry.key]
        currentNames[entry.key] = character ~= nil and itemName(getSlotItem(character, entry.slot)) or "-"
    end
    local viewCaptured = savedLookCaptured == true
    local viewHideHair = hideHair == true
    if coreAvailable then
        viewCaptured = reducerView.look ~= nil and reducerView.look.captured == true
        viewHideHair = reducerView.look ~= nil and reducerView.look.hideHair == true
    end
    return {
        phase = reducerView.phase,
        look = lookCopy,
        captured = viewCaptured,
        hideHair = viewHideHair,
        canSetHair = overrideState.ready and reducerView.hasSavedLook == true and reducerView.busy ~= true,
        active = reducerView.active == true,
        autoApply = reducerView.autoApply == true,
        canSave = overrideState.ready and reducerView.canSave == true,
        canApply = overrideState.ready and reducerView.canApply == true,
        canClear = reducerView.canClear == true,
        canForget = reducerView.canForget == true,
        error = reducerView.error,
        lastOperation = tostring(lastOperation),
        diagnosticsVisible = diagnosticsVisible == true,
        slotResults = resultCopy,
        currentNames = currentNames,
        overrideLabel = tostring(overrideState.label),
        overrideDetails = overrideState.details
    }
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
    local view = clientViewModelSnapshot(character, overrideState)

    addText(list, tr("panel.title"))
    addText(list, view.overrideLabel)
    addText(list, tr("panel.saved_look") .. ": " .. savedLookSummary(view.look, view.captured) .. " | " .. tr("panel.look") .. ": " .. (view.active and tr("panel.active") or tr("panel.inactive")))
    addText(list, tr("panel.last") .. ": " .. localizedStatus(view.lastOperation))

    addButton(list, tr("button.save"), function() saveFashionAndUnequip() end, true, view.canSave)
    addButton(list, tr("button.apply"), function() applyFashionToCurrentEquipment(false) end, true, view.canApply)
    addButton(list, view.hideHair and tr("button.show_hair") or tr("button.hide_hair"), function()
        dispatchReducer({ type = "SetHairHidden", hidden = not view.hideHair })
        local state = clientController ~= nil and clientController.getState() or reducerState
        if state ~= nil and state.phase == Core.PHASE.Faulted then
            log("Hide Hair toggle failed: " .. tostring(state.error))
        end
    end, true, view.canSetHair)
    addButton(list, tr("button.clear"), function() clearActiveLook() end, true, view.canClear)
    addButton(list, tr("button.forget"), function() clearSavedLook() end, true, view.canForget)
    addButton(list, view.diagnosticsVisible and tr("button.hide_diagnostics") or tr("button.diagnostics"), function()
        diagnosticsVisible = not diagnosticsVisible
    end)
    addButton(list, tr("button.dump_debug"), function() dumpDebugLog() end, true)
    addText(list, tr("panel.debug_log_hint"))
    addText(list, tr("panel.saved_file") .. ": " .. clientLookStoragePath())
    addButton(list, tr("button.close"), function() fullPanelOpen = false; resetOverlay() end, false)

    for _, entry in ipairs(slots) do
        local currentItem = view.currentNames[entry.key]
        local result = localizedStatus(view.slotResults[entry.key] or "-")
        addText(
            list,
            slotLabel(entry) .. " | " .. tr("panel.current") .. ": " .. currentItem .. " | " .. tr("panel.saved") .. ": " .. itemName(view.look[entry.key]) .. " | " .. tr("panel.result") .. ": " .. result
        )
    end

    if view.diagnosticsVisible then
        addText(list, tr("panel.diagnostics") .. ": " .. tostring(view.overrideDetails or tr("status.none")))
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

local function tryCaptureEmptyVisualOverride(character)
    if ensureVisualOverride() == nil or character == nil then
        return false, "visual override is unavailable"
    end
    local ok, result = pcall(function()
        return VisualOverride.CaptureEmptyFashion(character)
    end)
    if not ok then return false, tostring(result) end
    if result ~= true then return false, "renderer rejected the empty look" end
    return true
end

local function syncReducerCharacter(character)
    if not coreAvailable then return end
    local key = characterStateKey(character)
    if key == nil then
        if reducerCharacterKey ~= nil then
            dispatchReducer({ type = "CharacterLost" })
            reducerCharacterKey = nil
        end
        return
    end
    if key ~= reducerCharacterKey then
        reducerCharacterKey = key
        dispatchReducer({ type = "CharacterReady", characterKey = key })
        syncReducerLook()
    end
end

local function resetSavedLookForNewSession()
    clearAllVisualOverrides()
    savedLook = {}
    savedLookCaptured = false
    activeLook = false
    autoApplyLook = false
    hideHair = false
    characterStates = {}
    slotResults = {}
    lastNetworkApplyDiagnostics = {}
    lastEquipmentSignature = nil
    lastServerAutoApplySignature = nil
    clearPendingServerApplyRequest()
    pendingRoundStartNetworkLook = nil
    pendingRoundStartNetworkCharacterKey = nil
    pendingRoundStartNetworkRevision = nil
    pendingRoundStartHideHair = false
    pendingNetworkAppliesByCharacterId = {}
    pendingNetworkClearsByCharacterId = {}
    lastAppliedNetworkLookSignatureByCharacterKey = {}
    suppressedNetworkAppliesByCharacterKey = {}
    remoteRevisionByCharacterId = {}
    protocolMode = coreAvailable and "probing" or "v1"
    protocolHelloSentAt = nil
    protocolCommandQueue = {}
    inFlightV2Command = nil
    protocolOperationCounter = 0
    clientSessionId = createClientSessionId()
    reducerCharacterKey = nil
    reducerState = coreAvailable and Core.newClientState({
        clientSessionId = clientSessionId,
        sessionKey = currentSessionKey()
    }) or nil
    clientController = createClientController(reducerState)
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
    processPendingNetworkMessages()
    processProtocolNegotiation()

    if f8Hit() then
        toggleWindow()
    end

    local character = controlled()
    syncReducerCharacter(character)
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
        dispatchReducer({ type = "Deactivate" })
        lastEquipmentSignature = nil
        lastServerAutoApplySignature = nil
        clearPendingServerApplyRequest()
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
    pendingRoundStartNetworkRevision = nil
    pendingRoundStartHideHair = false
    pendingNetworkAppliesByCharacterId = {}
    pendingNetworkClearsByCharacterId = {}
    lastAppliedNetworkLookSignatureByCharacterKey = {}
    suppressedNetworkAppliesByCharacterKey = {}
    remoteRevisionByCharacterId = {}
    fullPanelOpen = false
    resetOverlay()
    slotResults = {}
    lastNetworkApplyDiagnostics = {}
    diagnosticsVisible = false
    lastServerAutoApplySignature = nil
    clearPendingServerApplyRequest()
    lastEquipmentSignature = nil
    clearAllVisualOverrides()
    lastCharacter = nil
    roundStartNoticeSent = false
    if preservedForNextScene then
        lastOperation = "Saved look will be reapplied in the next scene."
    else
        lastOperation = hasSavedLook() and "Saved look needs to be applied again." or "Round ended."
    end
end)

loadPersistentClientLook()
log("Loaded. Press F8 to open the wardrobe panel.")
