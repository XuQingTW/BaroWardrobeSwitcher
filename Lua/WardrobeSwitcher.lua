-- Client facade: projects the pure Core state machine onto Barotrauma networking,
-- persistence, renderer transactions and the in-game panel.
local MOD_NAME = "Baro Wardrobe Switcher"
local Core = WardrobeCore
local coreAvailable = type(Core) == "table" and
    tonumber(Core.PROTOCOL_VERSION) == 2 and
    type(Core.NET) == "table"
local EXPECTED_CSHARP_VERSION = coreAvailable and tostring(Core.MOD_VERSION or "0.5.1") or "0.5.1"
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
local COMMAND_VISIBILITY = coreAvailable and Core.COMMAND.Visibility or "visibility"
local ATTACHMENT_KEYS = coreAvailable and Core.ATTACHMENT_KEYS or {
    "Hair",
    "Beard",
    "Moustache",
    "FaceAttachment"
}
local ATTACHMENT_VISIBILITY = coreAvailable and Core.ATTACHMENT_VISIBILITY or {
    Auto = "auto",
    Hide = "hide",
    Show = "show"
}
local CAPABILITY_ATTACHMENT_VISIBILITY =
    coreAvailable and Core.CAPABILITY ~= nil and Core.CAPABILITY.AttachmentVisibility or 0x01

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
        ["panel.profile"] = "Character profile",
        ["panel.transfer"] = "Transfer to unconfigured characters",
        ["panel.attachment_layers"] = "Appearance Layers",
        ["panel.attachment_help"] = "Character mods may reuse these wearable slots for head parts. Auto follows the appearance item's XML; Show overrides equipment hiding.",
        ["panel.visibility"] = "Visibility",
        ["panel.debug_log_hint"] = "Debug dump writes to the LuaCs/Barotrauma log; search for [Baro Wardrobe Switcher].",
        ["panel.saved_file"] = "Saved-look file",
        ["button.save"] = "Save Current Outfit",
        ["button.apply"] = "Apply Saved Look",
        ["button.clear"] = "Clear Look",
        ["button.forget"] = "Forget Saved Look",
        ["button.hide_hair"] = "Hide Hair",
        ["button.show_hair"] = "Show Hair",
        ["button.attachment_layers"] = "Appearance Layers...",
        ["button.hide_standard_hair"] = "Hide Standard Hair",
        ["button.all_auto"] = "All Auto",
        ["button.back"] = "Back",
        ["button.enable_transfer"] = "Enable Appearance Transfer",
        ["button.disable_transfer"] = "Disable Appearance Transfer",
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
        ["attachment.hair"] = "Hair",
        ["attachment.beard"] = "Beard",
        ["attachment.moustache"] = "Moustache",
        ["attachment.face"] = "Face Attachment",
        ["visibility.auto"] = "Auto",
        ["visibility.hide"] = "Hide",
        ["visibility.show"] = "Show",
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
        ["status.profile_unavailable"] = "memory only",
        ["status.profile_collision"] = "ambiguous identity; automatic restore disabled",
        ["status.enabled"] = "enabled",
        ["status.disabled"] = "disabled",
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
        ["panel.profile"] = "角色配置",
        ["panel.transfer"] = "沿用外观至未设置角色",
        ["panel.attachment_layers"] = "外观图层",
        ["panel.attachment_help"] = "角色模组可能重用这些穿戴槽位作为头部组件。自动会遵循外观物品 XML；显示可覆盖装备的隐藏规则。",
        ["panel.visibility"] = "可见性",
        ["panel.debug_log_hint"] = "诊断会写入 LuaCs/Barotrauma 日志；搜索 [Baro Wardrobe Switcher]。",
        ["panel.saved_file"] = "保存外观文件",
        ["button.save"] = "保存当前服装",
        ["button.apply"] = "套用已保存外观",
        ["button.clear"] = "清除外观",
        ["button.forget"] = "忘记已保存外观",
        ["button.hide_hair"] = "隐藏头发",
        ["button.show_hair"] = "显示头发",
        ["button.attachment_layers"] = "外观图层…",
        ["button.hide_standard_hair"] = "隐藏标准头发",
        ["button.all_auto"] = "全部自动",
        ["button.back"] = "返回",
        ["button.enable_transfer"] = "启用外观沿用",
        ["button.disable_transfer"] = "停用外观沿用",
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
        ["attachment.hair"] = "头发",
        ["attachment.beard"] = "胡须",
        ["attachment.moustache"] = "上唇胡",
        ["attachment.face"] = "脸部附件",
        ["visibility.auto"] = "自动",
        ["visibility.hide"] = "隐藏",
        ["visibility.show"] = "显示",
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
        ["status.profile_unavailable"] = "仅保存在内存",
        ["status.profile_collision"] = "角色身份重复；已停用自动恢复",
        ["status.enabled"] = "启用",
        ["status.disabled"] = "停用",
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
        ["panel.profile"] = "角色設定檔",
        ["panel.transfer"] = "沿用外觀至未設定角色",
        ["panel.attachment_layers"] = "外觀圖層",
        ["panel.attachment_help"] = "角色模組可能重用這些穿戴槽位作為頭部組件。自動會遵循外觀物品 XML；顯示可覆寫裝備的隱藏規則。",
        ["panel.visibility"] = "可見性",
        ["panel.debug_log_hint"] = "診斷會寫入 LuaCs/Barotrauma 日誌；搜尋 [Baro Wardrobe Switcher]。",
        ["panel.saved_file"] = "儲存外觀檔案",
        ["button.save"] = "儲存目前服裝",
        ["button.apply"] = "套用已儲存外觀",
        ["button.clear"] = "清除外觀",
        ["button.forget"] = "忘記已儲存外觀",
        ["button.hide_hair"] = "隱藏頭髮",
        ["button.show_hair"] = "顯示頭髮",
        ["button.attachment_layers"] = "外觀圖層…",
        ["button.hide_standard_hair"] = "隱藏標準頭髮",
        ["button.all_auto"] = "全部自動",
        ["button.back"] = "返回",
        ["button.enable_transfer"] = "啟用外觀沿用",
        ["button.disable_transfer"] = "停用外觀沿用",
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
        ["attachment.hair"] = "頭髮",
        ["attachment.beard"] = "鬍鬚",
        ["attachment.moustache"] = "上唇鬍",
        ["attachment.face"] = "臉部附件",
        ["visibility.auto"] = "自動",
        ["visibility.hide"] = "隱藏",
        ["visibility.show"] = "顯示",
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
        ["status.profile_unavailable"] = "僅保存在記憶體",
        ["status.profile_collision"] = "角色身分重複；已停用自動恢復",
        ["status.enabled"] = "啟用",
        ["status.disabled"] = "停用",
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
local attachmentVisibility = {
    Hair = ATTACHMENT_VISIBILITY.Auto,
    Beard = ATTACHMENT_VISIBILITY.Auto,
    Moustache = ATTACHMENT_VISIBILITY.Auto,
    FaceAttachment = ATTACHMENT_VISIBILITY.Auto
}
local characterStates = {}
local transferToUnconfiguredCharacter = false
local singlePlayerTransferSettingLoaded = false
local singlePlayerProfileLoadAttempts = {}
local pendingSinglePlayerRestores = {}
local singlePlayerFingerprintOwners = {}
local singlePlayerCharactersByRuntimeKey = {}
local singlePlayerAmbiguousFingerprints = {}
local singlePlayerRoundScanned = false
local pendingSinglePlayerTransferSourceKey = nil
local singlePlayerAutomaticRestoreAllowed = nil
local lastOperation = "Ready."
local diagnosticsVisible = false
local lastEquipmentSignature = nil
local slotResults = {}
local lastNetworkApplyDiagnostics = {}
local window = nil
local windowNeedsRefresh = false
local overlayRoot = nil
local attachmentPanelOpen = false
local lastCharacter = nil
local buildWindow
local buildAttachmentVisibilityWindow
local toggleWindow
local fullPanelOpen = false
local controlled
local tryCaptureEmptyVisualOverride
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
local pendingRoundStartAttachmentVisibility = nil
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
local persistenceFailureReason
local protocolMode = coreAvailable and "probing" or "v1"
local serverCapabilities = 0
local visibilitySyncPendingNegotiation = false
local protocolHelloSentAt = nil
local protocolCommandQueue = {}
local inFlightV2Command = nil
local protocolOperationCounter = 0
local reducerCharacterKey = nil
local remoteRevisionByCharacterId = {}
local clientEffectAdapters = {}
local applyReducerProjection = nil
local syncControlledCharacterState = nil
local suppressControlledCharacterStateSync = false

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

-- This is the single state projection point. Marking the panel dirty here keeps
-- asynchronous ACK/state changes from leaving stale enabled/disabled buttons.
local function dispatchReducer(event)
    if not coreAvailable or clientController == nil then return {} end
    local ok, effects, feedback = pcall(clientController.dispatch, event)
    if not ok then
        print("[" .. MOD_NAME .. " DEBUG] reducer rejected event " .. tostring(event and event.type) .. ": " .. tostring(effects))
        return {}
    end
    reducerState = clientController.getState()
    if applyReducerProjection ~= nil then applyReducerProjection(reducerState) end
    if syncControlledCharacterState ~= nil then syncControlledCharacterState() end
    windowNeedsRefresh = true
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

local function attachmentVisibilityFromLegacy(hairHidden)
    if coreAvailable and type(Core.attachmentVisibilityFromLegacy) == "function" then
        return Core.attachmentVisibilityFromLegacy(hairHidden == true)
    end
    local hidden = hairHidden == true
    return {
        Hair = hidden and ATTACHMENT_VISIBILITY.Hide or ATTACHMENT_VISIBILITY.Auto,
        Beard = hidden and ATTACHMENT_VISIBILITY.Hide or ATTACHMENT_VISIBILITY.Auto,
        Moustache = hidden and ATTACHMENT_VISIBILITY.Hide or ATTACHMENT_VISIBILITY.Auto,
        FaceAttachment = ATTACHMENT_VISIBILITY.Auto
    }
end

local function validateAttachmentVisibility(value, legacyHairHidden)
    if coreAvailable and type(Core.validateAttachmentVisibility) == "function" then
        return Core.validateAttachmentVisibility(value, legacyHairHidden == true)
    end
    if value == nil then return attachmentVisibilityFromLegacy(legacyHairHidden) end
    if type(value) ~= "table" then return nil, "attachment visibility must be a table" end
    local expected = {}
    for _, key in ipairs(ATTACHMENT_KEYS) do expected[key] = true end
    for key in pairs(value) do
        if expected[key] ~= true then return nil, "unknown attachment layer " .. tostring(key) end
    end
    local result = {}
    for _, key in ipairs(ATTACHMENT_KEYS) do
        local state = value[key]
        if state ~= ATTACHMENT_VISIBILITY.Auto and
            state ~= ATTACHMENT_VISIBILITY.Hide and
            state ~= ATTACHMENT_VISIBILITY.Show then
            return nil, "invalid attachment visibility for " .. tostring(key)
        end
        result[key] = state
    end
    return result
end

local function copyAttachmentVisibility(value, legacyHairHidden)
    local valid = validateAttachmentVisibility(value, legacyHairHidden)
    if valid == nil then valid = attachmentVisibilityFromLegacy(legacyHairHidden) end
    local copy = {}
    for _, key in ipairs(ATTACHMENT_KEYS) do copy[key] = valid[key] end
    return copy
end

local function legacyHideHairForVisibility(value)
    if coreAvailable and type(Core.legacyHideHair) == "function" then
        return Core.legacyHideHair(value)
    end
    local valid = validateAttachmentVisibility(value, false)
    return valid ~= nil and
        valid.Hair == ATTACHMENT_VISIBILITY.Hide and
        valid.Beard == ATTACHMENT_VISIBILITY.Hide and
        valid.Moustache == ATTACHMENT_VISIBILITY.Hide
end

local function attachmentVisibilityMasks(value)
    if coreAvailable and type(Core.attachmentVisibilityMasks) == "function" then
        return Core.attachmentVisibilityMasks(value)
    end
    local valid, reason = validateAttachmentVisibility(value, false)
    if valid == nil then return nil, nil, reason end
    local bits = { Hair = 0x01, Beard = 0x02, Moustache = 0x04, FaceAttachment = 0x08 }
    local forceHide, forceShow = 0, 0
    for _, key in ipairs(ATTACHMENT_KEYS) do
        if valid[key] == ATTACHMENT_VISIBILITY.Hide then
            forceHide = forceHide + bits[key]
        elseif valid[key] == ATTACHMENT_VISIBILITY.Show then
            forceShow = forceShow + bits[key]
        end
    end
    return forceHide, forceShow
end

local function serverSupportsAttachmentVisibility()
    return protocolMode == "v2" and
        math.floor((tonumber(serverCapabilities) or 0) / CAPABILITY_ATTACHMENT_VISIBILITY) % 2 == 1
end

local function lookDataHasSavedLook(lookData, captured)
    if captured == true then return true end
    lookData = lookData or {}
    for _, entry in ipairs(slots) do
        if lookData[entry.key] ~= nil then return true end
    end
    return false
end

local function lookDataSignature(lookData, captured, visibility)
    local parts = { "captured=" .. tostring(captured == true) }
    if visibility ~= nil then
        local canonical = copyAttachmentVisibility(visibility, false)
        for _, key in ipairs(ATTACHMENT_KEYS) do
            parts[#parts + 1] = "visibility." .. key .. "=" .. canonical[key]
        end
    end
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

local function domainLookFromLegacy(lookData, captured, hairHidden, visibility)
    if not coreAvailable then return nil end
    local look = Core.fromLegacyLook(
        lookData or {},
        captured == true,
        hairHidden == true,
        visibility
    )
    return look
end

local function currentDomainLook()
    return domainLookFromLegacy(
        savedLook,
        savedLookCaptured,
        hideHair,
        attachmentVisibility
    )
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
    if state.look ~= nil then
        attachmentVisibility =
            copyAttachmentVisibility(state.look.attachmentVisibility, state.look.hideHair == true)
        hideHair = legacyHideHairForVisibility(attachmentVisibility)
    else
        attachmentVisibility = attachmentVisibilityFromLegacy(false)
        hideHair = false
    end
end

local function nextOperationId()
    protocolOperationCounter = protocolOperationCounter + 1
    return clientSessionId .. ":" .. tostring(protocolOperationCounter)
end

local function isSinglePlayerClient()
    return CLIENT == true and not (Game ~= nil and Game.IsMultiplayer == true)
end

local loadSinglePlayerProfileState = nil

local function characterStateKey(character)
    if character == nil then return nil end
    if isSinglePlayerClient() then
        local okInfo, infoId = pcall(function()
            return character.Info ~= nil and character.Info.ID or nil
        end)
        if okInfo and infoId ~= nil and tonumber(infoId) ~= nil and tonumber(infoId) > 0 then
            return "info:" .. tostring(infoId)
        end
        return nil
    end
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

local function applyCharacterState(state)
    if state == nil then
        savedLook = {}
        savedLookCaptured = false
        activeLook = false
        autoApplyLook = false
        hideHair = false
        attachmentVisibility = attachmentVisibilityFromLegacy(false)
        lastEquipmentSignature = nil
        slotResults = {}
        lastNetworkApplyDiagnostics = {}
        return
    end
    savedLook = copyLookData(state.savedLook)
    savedLookCaptured = state.savedLookCaptured == true
    activeLook = state.activeLook == true
    autoApplyLook = state.autoApplyLook == true
    attachmentVisibility = copyAttachmentVisibility(
        state.attachmentVisibility,
        state.hideHair == true
    )
    hideHair = legacyHideHairForVisibility(attachmentVisibility)
    lastEquipmentSignature = state.lastEquipmentSignature
    slotResults = state.slotResults or {}
    lastNetworkApplyDiagnostics = state.lastNetworkApplyDiagnostics or {}
end

local function saveCharacterState(character)
    local key = characterStateKey(character)
    if key == nil then return end
    if isSinglePlayerClient() and
        not lookDataHasSavedLook(savedLook, savedLookCaptured) and
        not activeLook and
        not autoApplyLook then
        characterStates[key] = nil
        return
    end
    local previous = characterStates[key] or {}
    characterStates[key] = {
        savedLook = copyLookData(savedLook),
        savedLookCaptured = savedLookCaptured == true,
        hideHair = hideHair == true,
        attachmentVisibility = copyAttachmentVisibility(attachmentVisibility, hideHair),
        activeLook = activeLook,
        autoApplyLook = autoApplyLook,
        lastEquipmentSignature = lastEquipmentSignature,
        slotResults = slotResults,
        lastNetworkApplyDiagnostics = lastNetworkApplyDiagnostics,
        profileKey = previous.profileKey,
        displayName = previous.displayName,
        persistent = previous.persistent == true,
        profileAmbiguous = previous.profileAmbiguous == true
    }
end

syncControlledCharacterState = function()
    if isSinglePlayerClient() and not suppressControlledCharacterStateSync then
        local character = controlled ~= nil and controlled() or nil
        if character ~= nil then saveCharacterState(character) end
    end
end

local function loadCharacterState(character)
    local key = characterStateKey(character)
    local state = key ~= nil and characterStates[key] or nil
    if isSinglePlayerClient() then
        if state == nil and type(loadSinglePlayerProfileState) == "function" then
            state = loadSinglePlayerProfileState(character)
            if state ~= nil and key ~= nil then characterStates[key] = state end
        end
        applyCharacterState(state)
        return state ~= nil and
            lookDataHasSavedLook(state.savedLook, state.savedLookCaptured)
    end

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

-- Keep later helpers on one table so standard Lua compilers stay below
-- their 200-local limit without exposing implementation details globally.
local Helpers = {}

function Helpers.log(message)
    local line = "[" .. MOD_NAME .. "] " .. tostring(message)
    lastOperation = tostring(message)
    if LuaCsLogger ~= nil and LuaCsLogger.Log ~= nil then
        LuaCsLogger.Log(line)
    else
        print(line)
    end
end

function Helpers.debugLog(message)
    local line = "[" .. MOD_NAME .. " DEBUG] " .. tostring(message)
    if LuaCsLogger ~= nil and LuaCsLogger.Log ~= nil then
        LuaCsLogger.Log(line)
    else
        print(line)
    end
end

function Helpers.clientPersistPath()
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

function Helpers.escapePersistentValue(value)
    return tostring(value or "")
        :gsub("%%", "%%25")
        :gsub("|", "%%7C")
        :gsub(",", "%%2C")
        :gsub("=", "%%3D")
        :gsub("\r", "%%0D")
        :gsub("\n", "%%0A")
end

function Helpers.unescapePersistentValue(value)
    return tostring(value or "")
        :gsub("%%0A", "\n")
        :gsub("%%0D", "\r")
        :gsub("%%3D", "=")
        :gsub("%%2C", ",")
        :gsub("%%7C", "|")
        :gsub("%%25", "%%")
end

function Helpers.userDataMember(object, name)
    if object == nil or name == nil then return nil end
    local ok, value = pcall(function()
        return object[name]
    end)
    if ok then return value end
    return nil
end

function Helpers.normalizedSessionValue(value)
    if value == nil then return nil end
    local text = tostring(value):gsub("\\", "/")
    if text == "" or text == "nil" or text == "null" then return nil end
    return text
end

function Helpers.firstSessionValue(object, names)
    for _, name in ipairs(names) do
        local value = Helpers.normalizedSessionValue(Helpers.userDataMember(object, name))
        if value ~= nil then return value end
    end
    return nil
end

function Helpers.currentSessionKey()
    if GameMain == nil then return nil end
    local session = Helpers.userDataMember(GameMain, "GameSession")
    if session == nil then return nil end

    local dataPath = Helpers.userDataMember(session, "DataPath")
    local fromDataPath = Helpers.firstSessionValue(dataPath, { "SavePath", "LoadPath" })
    if fromDataPath ~= nil then return "campaign:" .. fromDataPath end

    local direct = Helpers.firstSessionValue(session, { "SavePath", "SaveFilePath", "SaveFile", "FilePath" })
    if direct ~= nil then return "session:" .. direct end

    local gameMode = Helpers.userDataMember(session, "GameMode")
    local fromGameMode = Helpers.firstSessionValue(gameMode, { "SavePath", "SaveFilePath", "SaveFile", "FilePath" })
    if fromGameMode ~= nil then return "gamemode:" .. fromGameMode end

    local campaign = Helpers.userDataMember(session, "Campaign") or Helpers.userDataMember(gameMode, "Campaign")
    local fromCampaign = Helpers.firstSessionValue(campaign, { "SavePath", "SaveFilePath", "SaveFile", "FilePath", "CampaignID", "Identifier" })
    if fromCampaign ~= nil then return "campaign:" .. fromCampaign end

    return nil
end

function Helpers.currentSinglePlayerCampaignKey()
    if not isSinglePlayerClient() or GameMain == nil then return nil end
    local session = Helpers.userDataMember(GameMain, "GameSession")
    if session == nil then return nil end

    local dataPath = Helpers.userDataMember(session, "DataPath")
    local savePath = Helpers.firstSessionValue(dataPath, { "SavePath", "LoadPath" })
    if savePath == nil then
        savePath = Helpers.firstSessionValue(
            session,
            { "SavePath", "SaveFilePath", "FilePath" }
        )
    end
    if savePath == nil then
        local gameMode = Helpers.userDataMember(session, "GameMode")
        local campaign = Helpers.userDataMember(session, "Campaign") or
            Helpers.userDataMember(gameMode, "Campaign")
        savePath = Helpers.firstSessionValue(
            campaign,
            { "SavePath", "SaveFilePath", "FilePath" }
        )
    end
    return savePath ~= nil and "campaign:" .. savePath or nil
end

function Helpers.encodePersistentClientLook(lookData, captured, active, auto, visibilityValue)
    lookData = lookData or savedLook
    if captured == nil then captured = savedLookCaptured == true end
    if active == nil then active = activeLook == true end
    if auto == nil then auto = autoApplyLook == true end
    local visibility
    if type(visibilityValue) == "table" then
        visibility = copyAttachmentVisibility(visibilityValue, false)
    elseif type(visibilityValue) == "boolean" then
        visibility = attachmentVisibilityFromLegacy(visibilityValue)
    else
        visibility = copyAttachmentVisibility(attachmentVisibility, hideHair)
    end
    local hairHidden = legacyHideHairForVisibility(visibility)
    local parts = {
        "schema=3",
        "captured=" .. tostring(captured == true),
        "active=" .. tostring(active == true),
        "auto=" .. tostring(auto == true),
        "hidehair=" .. tostring(hairHidden == true),
        "visibilityHair=" .. visibility.Hair,
        "visibilityBeard=" .. visibility.Beard,
        "visibilityMoustache=" .. visibility.Moustache,
        "visibilityFaceAttachment=" .. visibility.FaceAttachment
    }
    local sessionKey = Helpers.currentSessionKey()
    if sessionKey ~= nil then
        parts[#parts + 1] = "session=" .. Helpers.escapePersistentValue(sessionKey)
    end
    for _, entry in ipairs(slots) do
        local slotState = lookData[entry.key]
        if slotState ~= nil then
            parts[#parts + 1] =
                entry.key ..
                "=" ..
                Helpers.escapePersistentValue(slotState.identifier or "") ..
                "," ..
                Helpers.escapePersistentValue(slotState.name or "")
        end
    end
    return table.concat(parts, "|")
end

function Helpers.singlePlayerCharacterEligible(character)
    if not isSinglePlayerClient() or character == nil then return false end
    local info = Helpers.userDataMember(character, "Info")
    if info == nil then return false end
    return Helpers.userDataMember(character, "IsHuman") == true and
        Helpers.userDataMember(character, "IsOnPlayerTeam") == true
end

function Helpers.profileIdentifierPart(value)
    local text = Helpers.normalizedSessionValue(value) or ""
    return tostring(#text) .. ":" .. text
end

function Helpers.singlePlayerCharacterProfileKey(character)
    if not Helpers.singlePlayerCharacterEligible(character) then return nil end
    local info = Helpers.userDataMember(character, "Info")
    local originalName = Helpers.normalizedSessionValue(Helpers.userDataMember(info, "OriginalName"))
    local speciesName = Helpers.normalizedSessionValue(Helpers.userDataMember(info, "SpeciesName"))
    if originalName == nil or speciesName == nil then return nil end

    local humanPrefabIds = Helpers.userDataMember(info, "HumanPrefabIds")
    local npcSetIdentifier = humanPrefabIds ~= nil and
        Helpers.normalizedSessionValue(Helpers.userDataMember(humanPrefabIds, "Item1")) or nil
    local npcIdentifier = humanPrefabIds ~= nil and
        Helpers.normalizedSessionValue(Helpers.userDataMember(humanPrefabIds, "Item2")) or nil
    return table.concat({
        Helpers.profileIdentifierPart(originalName),
        Helpers.profileIdentifierPart(speciesName),
        Helpers.profileIdentifierPart(npcSetIdentifier),
        Helpers.profileIdentifierPart(npcIdentifier)
    }, "|")
end

function Helpers.singlePlayerCharacterDisplayName(character)
    local info = character ~= nil and Helpers.userDataMember(character, "Info") or nil
    return Helpers.normalizedSessionValue(info ~= nil and Helpers.userDataMember(info, "Name") or nil) or
        Helpers.normalizedSessionValue(character ~= nil and Helpers.userDataMember(character, "Name") or nil) or
        "Unknown"
end

function Helpers.singlePlayerProfileLineState(line)
    if not coreAvailable or type(Core.parseLegacyClientLookLine) ~= "function" then return nil end
    local parsed, reason = Core.parseLegacyClientLookLine(tostring(line or ""))
    if parsed == nil or parsed.look == nil then
        Helpers.debugLog("Rejected single-player wardrobe profile: " .. tostring(reason))
        return nil
    end
    local legacyLook, legacyReason = Core.toLegacyLook(parsed.look)
    if legacyLook == nil then
        Helpers.debugLog("Rejected single-player wardrobe profile look: " .. tostring(legacyReason))
        return nil
    end
    local results = {}
    for _, entry in ipairs(slots) do
        results[entry.key] = legacyLook[entry.key] ~= nil and
            "Saved look needs to be applied again." or "Empty"
    end
    return {
        savedLook = legacyLook,
        savedLookCaptured = parsed.look.captured == true,
        hideHair = parsed.look.hideHair == true,
        attachmentVisibility = copyAttachmentVisibility(
            parsed.look.attachmentVisibility,
            parsed.look.hideHair == true
        ),
        activeLook = false,
        autoApplyLook = parsed.autoApply == true or parsed.active == true,
        lastEquipmentSignature = nil,
        slotResults = results,
        lastNetworkApplyDiagnostics = {},
        persistent = true
    }
end

function Helpers.loadSinglePlayerTransferSetting()
    if singlePlayerTransferSettingLoaded or not isSinglePlayerClient() then return end
    local persistence = ensureWardrobePersistence()
    if persistence == nil then return end
    local ok, enabled = pcall(function()
        return persistence.GetSinglePlayerTransferEnabled()
    end)
    if ok then
        transferToUnconfiguredCharacter = enabled == true
        singlePlayerTransferSettingLoaded = true
    else
        Helpers.debugLog("Could not load single-player appearance-transfer setting: " .. tostring(enabled))
    end
end

function Helpers.setSinglePlayerTransferSetting(enabled)
    local previous = transferToUnconfiguredCharacter
    transferToUnconfiguredCharacter = enabled == true
    singlePlayerTransferSettingLoaded = true
    local persistence = ensureWardrobePersistence()
    if persistence == nil then
        transferToUnconfiguredCharacter = previous
        return false, persistenceFailureReason("C# wardrobe persistence is unavailable")
    end
    local ok, saved = pcall(function()
        return persistence.SetSinglePlayerTransferEnabled(transferToUnconfiguredCharacter)
    end)
    if ok and saved == true then return true end
    transferToUnconfiguredCharacter = previous
    return false, ok and
        persistenceFailureReason("C# SetSinglePlayerTransferEnabled returned false") or
        tostring(saved)
end

loadSinglePlayerProfileState = function(character)
    if not Helpers.singlePlayerCharacterEligible(character) then return nil end
    local campaignKey = Helpers.currentSinglePlayerCampaignKey()
    local profileKey = Helpers.singlePlayerCharacterProfileKey(character)
    if campaignKey == nil or profileKey == nil or singlePlayerAmbiguousFingerprints[profileKey] then
        return nil
    end
    local persistence = ensureWardrobePersistence()
    if persistence == nil then return nil end

    local attemptKey = campaignKey .. "\n" .. profileKey
    if not singlePlayerProfileLoadAttempts[attemptKey] and character == controlled() and
        Helpers.userDataMember(character, "IsBot") ~= true then
        singlePlayerProfileLoadAttempts[attemptKey] = true
        local importedOk, imported = pcall(function()
            return persistence.TryImportLegacyClientLook(
                campaignKey,
                profileKey,
                Helpers.singlePlayerCharacterDisplayName(character)
            )
        end)
        if not importedOk then
            Helpers.debugLog("Legacy client-look import failed: " .. tostring(imported))
        end
    end

    local ok, line = pcall(function()
        return persistence.LoadSinglePlayerProfile(campaignKey, profileKey)
    end)
    if not ok or line == nil or tostring(line) == "" then
        if not ok then
            Helpers.debugLog("Single-player wardrobe profile load failed: " .. tostring(line))
        end
        return nil
    end
    local state = Helpers.singlePlayerProfileLineState(line)
    if state == nil then return nil end
    state.profileKey = profileKey
    state.displayName = Helpers.singlePlayerCharacterDisplayName(character)
    return state
end

function Helpers.saveSinglePlayerProfile(
    character,
    lookData,
    captured,
    active,
    auto,
    visibilityValue
)
    if not Helpers.singlePlayerCharacterEligible(character) then return true end
    local campaignKey = Helpers.currentSinglePlayerCampaignKey()
    local profileKey = Helpers.singlePlayerCharacterProfileKey(character)
    if campaignKey == nil or profileKey == nil or singlePlayerAmbiguousFingerprints[profileKey] then
        return true
    end
    local persistence = ensureWardrobePersistence()
    if persistence == nil then
        return false, persistenceFailureReason("C# wardrobe persistence is unavailable")
    end
    local encoded = Helpers.encodePersistentClientLook(
        lookData,
        captured,
        active,
        auto,
        visibilityValue
    )
    local ok, saved = pcall(function()
        return persistence.SaveSinglePlayerProfile(
            campaignKey,
            profileKey,
            Helpers.singlePlayerCharacterDisplayName(character),
            encoded
        )
    end)
    if ok and saved == true then
        local runtimeKey = characterStateKey(character)
        local state = runtimeKey ~= nil and characterStates[runtimeKey] or nil
        if state ~= nil then
            state.persistent = true
            state.profileKey = profileKey
            state.displayName = Helpers.singlePlayerCharacterDisplayName(character)
        end
        return true
    end
    return false, ok and
        persistenceFailureReason("C# SaveSinglePlayerProfile returned false") or
        tostring(saved)
end

function Helpers.deleteSinglePlayerProfile(character)
    if not Helpers.singlePlayerCharacterEligible(character) then return true end
    local campaignKey = Helpers.currentSinglePlayerCampaignKey()
    local profileKey = Helpers.singlePlayerCharacterProfileKey(character)
    if campaignKey == nil or profileKey == nil or singlePlayerAmbiguousFingerprints[profileKey] then
        return true
    end
    local persistence = ensureWardrobePersistence()
    if persistence == nil then
        return false, persistenceFailureReason("C# wardrobe persistence is unavailable")
    end
    local ok, deleted = pcall(function()
        return persistence.DeleteSinglePlayerProfile(campaignKey, profileKey)
    end)
    if ok and deleted == true then
        local runtimeKey = characterStateKey(character)
        if runtimeKey ~= nil then characterStates[runtimeKey] = nil end
        return true
    end
    return false, ok and
        persistenceFailureReason("C# DeleteSinglePlayerProfile returned false") or
        tostring(deleted)
end

function Helpers.readLegacyPersistentClientLookLine()
    local path = Helpers.clientPersistPath()
    local file = io.open(path, "r")
    if file == nil then return false, path, "missing" end

    local line = file:read("*l")
    file:close()
    if line == nil or tostring(line) == "" then return nil, path, "empty or truncated" end
    return tostring(line), path
end

function Helpers.restorePersistentClientLookLine(line, source)
    if coreAvailable and type(Core.parseLegacyClientLookLine) == "function" then
        local parsed, parseReason = Core.parseLegacyClientLookLine(tostring(line or ""))
        if parsed == nil then
            Helpers.debugLog("Rejected persistent client look: " .. tostring(parseReason))
            return false
        end
    end
    local restoredLook = {}
    local captured = nil
    local active = false
    local auto = false
    local restoredHideHair = false
    local restoredAttachmentVisibility = nil
    local restoredSessionKey = nil
    local seen = {}
    local validSlots = {}
    for _, entry in ipairs(slots) do validSlots[entry.key] = true end

    local function parseBoolean(name, value)
        if value == "true" then return true end
        if value == "false" then return false end
        Helpers.debugLog("Rejected persistent client look with invalid " .. name .. " boolean.")
        return nil
    end

    for part in tostring(line):gmatch("[^|]+") do
        local name, value = part:match("^([^=]+)=(.*)$")
        if name == nil or seen[name] then
            Helpers.debugLog("Rejected persistent client look with a malformed or duplicate field.")
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
        elseif name == "visibilityHair" or
            name == "visibilityBeard" or
            name == "visibilityMoustache" or
            name == "visibilityFaceAttachment" then
            restoredAttachmentVisibility = restoredAttachmentVisibility or {}
            restoredAttachmentVisibility[name:sub(#"visibility" + 1)] = value
        elseif name == "schema" then
            if value ~= "1" and value ~= "2" and value ~= "3" then
                Helpers.debugLog("Rejected persistent client look with unsupported schema " .. tostring(value) .. ".")
                return false
            end
        elseif name == "session" then
            restoredSessionKey = Helpers.unescapePersistentValue(value)
        elseif validSlots[name] then
            local identifier, displayName = tostring(value):match("^([^,]+),(.*)$")
            identifier = identifier ~= nil and Helpers.unescapePersistentValue(identifier) or nil
            if identifier == nil or identifier == "" or #identifier > 256 then
                Helpers.debugLog("Rejected persistent client look with malformed slot " .. tostring(name) .. ".")
                return false
            end
            restoredLook[name] = {
                identifier = identifier,
                itemId = 0,
                name = Helpers.unescapePersistentValue(displayName or ""),
                slot = name
            }
        else
            Helpers.debugLog("Rejected persistent client look with unknown field " .. tostring(name) .. ".")
            return false
        end
    end

    if captured == nil then
        Helpers.debugLog("Rejected persistent client look without captured intent.")
        return false
    end

    local sessionKey = Helpers.currentSessionKey()
    if sessionKey ~= nil and restoredSessionKey ~= nil and
        restoredSessionKey ~= "" and restoredSessionKey ~= sessionKey then
        Helpers.debugLog("Restoring persistent client wardrobe look saved in another campaign session from " .. tostring(source or "C# persistence") .. ".")
    end

    if not lookDataHasSavedLook(restoredLook, captured) then return false end
    local domainLook, lookReason = domainLookFromLegacy(
        restoredLook,
        captured,
        restoredHideHair,
        restoredAttachmentVisibility
    )
    if domainLook == nil then
        Helpers.debugLog("Rejected persistent client look: " .. tostring(lookReason))
        return false
    end
    rememberLegacyLookMetadata(restoredLook)
    savedLook = copyLookData(restoredLook)
    persistentClientLookLoaded = true
    savedLookCaptured = true
    activeLook = false
    autoApplyLook = active == true or auto == true
    attachmentVisibility = copyAttachmentVisibility(
        domainLook.attachmentVisibility,
        domainLook.hideHair == true
    )
    hideHair = legacyHideHairForVisibility(attachmentVisibility)
    lastEquipmentSignature = nil
    lastServerAutoApplySignature = nil
    slotResults = {}
    for _, entry in ipairs(slots) do
        slotResults[entry.key] = savedLook[entry.key] ~= nil and "Saved look needs to be applied again." or "Empty"
    end
    lastOperation = autoApplyLook and "Saved look will be reapplied in the next scene." or "Saved look needs to be applied again."
    syncReducerLook()
    Helpers.debugLog("Loaded persistent client wardrobe look from " .. tostring(source or "C# persistence") .. ".")
    return true
end

persistenceFailureReason = function(fallback)
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
    local visibility = copyAttachmentVisibility(attachmentVisibility, hideHair)
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
        visibility = copyAttachmentVisibility(
            domainLook.attachmentVisibility,
            domainLook.hideHair == true
        )
        if viewModel ~= nil then
            active = viewModel.active == true
            auto = viewModel.autoApply == true
        end
    end
    if not lookDataHasSavedLook(lookData, captured) then
        return false, "no saved client look is available to persist"
    end

    if isSinglePlayerClient() then
        return Helpers.saveSinglePlayerProfile(
            controlled(),
            lookData,
            captured,
            active,
            auto,
            visibility
        )
    end

    local encoded = Helpers.encodePersistentClientLook(lookData, captured, active, auto, visibility)
    local persistence = ensureWardrobePersistence()
    if persistence == nil then
        local reason = persistenceFailureReason("C# wardrobe persistence is unavailable")
        Helpers.debugLog("C# wardrobe persistence write failed; saved look remains in memory for this session. " .. reason)
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
    Helpers.debugLog("C# wardrobe persistence write failed; saved look remains in memory for this session. " .. reason)
    return false, reason
end

clearPersistentClientLook = function()
    if isSinglePlayerClient() then
        return Helpers.deleteSinglePlayerProfile(controlled())
    end
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

function Helpers.loadPersistentClientLook()
    if isSinglePlayerClient() then return false end
    local persistence = ensureWardrobePersistence()
    if persistence ~= nil then
        local existedBeforeLoad = false
        pcall(function() existedBeforeLoad = persistence.ClientLookFileExists() == true end)
        local ok, line = pcall(function()
            return persistence.LoadClientLook()
        end)
        if not ok then
            Helpers.debugLog("C# wardrobe persistence load failed: " .. tostring(line))
            persistentClientLookLoaded = true
            return false
        end
        if ok and line ~= nil and tostring(line) ~= "" then
            local restored = Helpers.restorePersistentClientLookLine(tostring(line), "C# persistence")
            persistentClientLookLoaded = true
            return restored
        end
        local loadFailure = persistenceFailureReason(nil)
        if loadFailure ~= nil then
            Helpers.debugLog("C# wardrobe persistence load failed: " .. loadFailure)
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
                Helpers.debugLog("Corrupt client look was quarantined, but its empty v2 tombstone could not be written.")
            end
            persistentClientLookLoaded = true
            return false
        end
    end

    local legacyLine, legacyPath, legacyReason = Helpers.readLegacyPersistentClientLookLine()
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
        Helpers.debugLog("Quarantined corrupt legacy client look: " .. tostring(legacyReason))
        return false
    end
    local restored = Helpers.restorePersistentClientLookLine(legacyLine, legacyPath)
    if restored then
        local migrated = false
        if persistence ~= nil then
            local ok, result = pcall(function()
                return persistence.SaveMigratedClientLook(Helpers.encodePersistentClientLook(), legacyPath)
            end)
            migrated = ok and result == true
        end
        if not migrated then
            Helpers.debugLog("Legacy client look was restored in memory, but migration could not create its .v1.bak backup.")
        end
    elseif persistence ~= nil then
        pcall(function() persistence.QuarantineLegacyClientLook(legacyPath) end)
        Helpers.debugLog("Quarantined legacy client look that failed schema validation.")
    end
    return restored
end

function Helpers.addChatLine(text)
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

    Helpers.log(text)
    return false
end

function Helpers.sendRoundStartNotice()
    if roundStartNoticeSent then return end
    roundStartNoticeSent = true
    Helpers.addChatLine(tr("notice.open_panel"))
end

function Helpers.ensureVisualOverride()
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

function Helpers.visualOverrideState()
    local override = Helpers.ensureVisualOverride()
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

function Helpers.visualOverrideStatus()
    local state = Helpers.visualOverrideState()
    if state.ready then return nil end
    return "C# visual override is not ready. Enable C# scripting in LuaCs, accept this mod's C# prompt, then reload."
end

function Helpers.visualOverrideDebugStatus(character)
    local override = Helpers.ensureVisualOverride()
    if override == nil or character == nil then return nil end
    local ok, result = pcall(function()
        return override.GetCharacterDebugStatus(character)
    end)
    if ok and result ~= nil then
        return tostring(result)
    end
    return nil
end

controlled = function()
    return Character.Controlled
end

function Helpers.isMultiplayerClient()
    return CLIENT == true and Game ~= nil and Game.IsMultiplayer == true
end

function Helpers.ensureOverlayRoot()
    if overlayRoot ~= nil then return overlayRoot end

    local ok, root = pcall(function()
        return GUI.Frame(GUI.RectTransform(Vector2(1.0, 1.0)), nil)
    end)
    if not ok then
        Helpers.log("Overlay root failed to build: " .. tostring(root))
        return nil
    end

    overlayRoot = root
    pcall(function() overlayRoot.CanBeFocused = false end)
    return overlayRoot
end

function Helpers.overlayParent()
    local root = Helpers.ensureOverlayRoot()
    if root == nil then return nil end
    return root.RectTransform
end

function Helpers.drawOverlay()
    if overlayRoot == nil then return end
    pcall(function() overlayRoot.AddToGUIUpdateList() end)
end

function Helpers.resetOverlay()
    if overlayRoot ~= nil then
        pcall(function() overlayRoot.Remove() end)
    end
    overlayRoot = nil
    window = nil
end

function Helpers.itemName(item)
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

function Helpers.itemIdentifier(item)
    if item == nil or item.Prefab == nil or item.Prefab.Identifier == nil then return nil end
    return tostring(item.Prefab.Identifier)
end

function Helpers.isIgnoredWardrobeItem(item)
    local identifier = Helpers.itemIdentifier(item)
    return identifier == "genesplicer" or identifier == "advancedgenesplicer"
end

function Helpers.itemEntityId(item)
    if item == nil then return 0 end
    local ok, id = pcall(function()
        return item.ID
    end)
    if ok and id ~= nil then return id end
    return 0
end

function Helpers.characterEntityId(character)
    if character == nil then return 0 end
    local ok, id = pcall(function()
        return character.ID
    end)
    if ok and id ~= nil then return id end
    return 0
end

function Helpers.findEntityById(id)
    if Entity == nil or id == nil or id <= 0 then return nil end
    local ok, entity = pcall(function()
        return Entity.FindEntityByID(id)
    end)
    if ok then return entity end
    return nil
end

function Helpers.collectionContains(collection, value)
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

function Helpers.itemBelongsToCharacter(character, item)
    if character == nil or item == nil then return false end
    if isInAnyWearableSlot(character, item) then return true end
    if character.Inventory ~= nil then
        local ok, allItems = pcall(function()
            return character.Inventory.AllItems
        end)
        if ok and Helpers.collectionContains(allItems, item) then return true end
        local parentOk, parentInventory = pcall(function()
            return item.ParentInventory
        end)
        if parentOk and parentInventory == character.Inventory then return true end
    end
    return false
end

function Helpers.findItemByIdentifier(character, identifier)
    if character == nil or identifier == nil or identifier == "" then return nil end
    for _, entry in ipairs(slots) do
        local item = getSlotItem(character, entry.slot)
        if item ~= nil and Helpers.itemIdentifier(item) == identifier then return item end
    end
    if character.Inventory ~= nil then
        local ok, allItems = pcall(function()
            return character.Inventory.AllItems
        end)
        if ok and allItems ~= nil then
            pcall(function()
                for item in allItems do
                    if Helpers.itemIdentifier(item) == identifier then
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
                if Helpers.itemIdentifier(item) == identifier and Helpers.itemBelongsToCharacter(character, item) then
                    found = item
                    return
                end
            end
        end)
        if found ~= nil then return found end
    end
    return nil
end

function Helpers.itemStableId(item)
    if item == nil then return "-" end
    local id = Helpers.itemIdentifier(item) or Helpers.itemName(item)
    local runtimeId = nil
    pcall(function()
        runtimeId = item.ID
    end)
    if runtimeId ~= nil then
        return tostring(id) .. "#" .. tostring(runtimeId)
    end
    return tostring(id)
end

function Helpers.hasSavedLook()
    if clientController ~= nil then
        return Core.hasLook(clientController.getState().look)
    end
    return lookDataHasSavedLook(savedLook, savedLookCaptured)
end

function Helpers.stateHasSavedLook(state)
    if state == nil then return false end
    return lookDataHasSavedLook(state.savedLook, state.savedLookCaptured)
end

function Helpers.deactivateCachedCharacterStates(character, preserveAutoApply)
    if isSinglePlayerClient() then
        local key = characterStateKey(character)
        local state = key ~= nil and characterStates[key] or nil
        if state ~= nil then
            state.activeLook = false
            if preserveAutoApply ~= true then state.autoApplyLook = false end
            state.lastEquipmentSignature = nil
        end
        return
    end
    for _, state in pairs(characterStates) do
        state.activeLook = false
        if preserveAutoApply ~= true then
            state.autoApplyLook = false
        end
        state.lastEquipmentSignature = nil
    end
end

function Helpers.clearPendingNetworkApplyForCharacterId(characterId)
    local id = tonumber(characterId) or 0
    if id <= 0 then return end
    pendingNetworkAppliesByCharacterId[id] = nil
end

function Helpers.clearLocalPendingNetworkState(character)
    local key = characterStateKey(character)
    if key ~= nil then
        lastAppliedNetworkLookSignatureByCharacterKey[key] = nil
        if pendingRoundStartNetworkCharacterKey == key then
            pendingRoundStartNetworkLook = nil
            pendingRoundStartNetworkCharacterKey = nil
            pendingRoundStartNetworkRevision = nil
            pendingRoundStartHideHair = false
            pendingRoundStartAttachmentVisibility = nil
        end
        Helpers.clearPendingNetworkApplyForCharacterId(key)
    end
    Helpers.clearPendingNetworkApplyForCharacterId(Helpers.characterEntityId(character))
end

function Helpers.clearCachedLocalNetworkState()
    for key in pairs(characterStates) do
        lastAppliedNetworkLookSignatureByCharacterKey[key] = nil
        Helpers.clearPendingNetworkApplyForCharacterId(key)
    end
end

function Helpers.suppressNetworkApplyForKey(key)
    if key == nil then return end
    suppressedNetworkAppliesByCharacterKey[tostring(key)] = globalTick + NetworkApplySuppressTicks
end

function Helpers.clearNetworkApplySuppressionForKey(key)
    if key == nil then return end
    suppressedNetworkAppliesByCharacterKey[tostring(key)] = nil
end

function Helpers.suppressNetworkAppliesForCharacter(character)
    if character == nil then return end
    local key = characterStateKey(character)
    if key ~= nil then
        Helpers.suppressNetworkApplyForKey(key)
    end
    local id = Helpers.characterEntityId(character)
    if id > 0 then
        Helpers.suppressNetworkApplyForKey(id)
    end
end

function Helpers.clearNetworkApplySuppressionForCharacter(character)
    if character == nil then return end
    local key = characterStateKey(character)
    if key ~= nil then
        Helpers.clearNetworkApplySuppressionForKey(key)
    end
    local id = Helpers.characterEntityId(character)
    if id > 0 then
        Helpers.clearNetworkApplySuppressionForKey(id)
    end
end

function Helpers.pruneNetworkApplySuppressions()
    for key, suppressUntilTick in pairs(suppressedNetworkAppliesByCharacterKey) do
        if suppressUntilTick == nil or globalTick > suppressUntilTick then
            suppressedNetworkAppliesByCharacterKey[key] = nil
        end
    end
end

function Helpers.networkApplySuppressedForCharacter(characterId, character)
    Helpers.pruneNetworkApplySuppressions()
    local id = tonumber(characterId) or 0
    if id > 0 and suppressedNetworkAppliesByCharacterKey[tostring(id)] ~= nil then
        return true
    end
    local key = characterStateKey(character)
    return key ~= nil and suppressedNetworkAppliesByCharacterKey[tostring(key)] ~= nil
end

function Helpers.preserveSceneTransitionLookIntent()
    local shouldReapplyCurrentLook = Helpers.hasSavedLook() and (activeLook or autoApplyLook)
    dispatchReducer({ type = "PrepareSceneTransition", reapply = shouldReapplyCurrentLook })
    lastEquipmentSignature = nil
    lastServerAutoApplySignature = nil

    for _, state in pairs(characterStates) do
        if Helpers.stateHasSavedLook(state) and (state.activeLook == true or state.autoApplyLook == true) then
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

function Helpers.savedLookSummary(lookData, captured)
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

function Helpers.wornSlotLabelsForItem(character, item)
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
    return #Helpers.wornSlotLabelsForItem(character, item) > 0
end

function Helpers.equipmentSignature(character)
    if character == nil then return "no-character" end
    local parts = {}
    for _, entry in ipairs(slots) do
        parts[#parts + 1] = entry.key .. "=" .. Helpers.itemStableId(getSlotItem(character, entry.slot))
    end
    return table.concat(parts, ";")
end

function Helpers.managedWearableSlotsAreEmpty(character)
    if character == nil then return false end
    for _, entry in ipairs(slots) do
        local item = getSlotItem(character, entry.slot)
        if item ~= nil and not Helpers.isIgnoredWardrobeItem(item) then
            return false
        end
    end
    return true
end

function Helpers.serverAutoApplyRequestKey(character)
    return tostring(characterStateKey(character) or "unknown") .. "|" .. Helpers.equipmentSignature(character)
end

function Helpers.clearPendingServerApplyRequest()
    lastServerAutoApplySignature = nil
    pendingServerApplyRequestKey = nil
    pendingServerApplyLastRequestTick = 0
    pendingServerApplyAttempts = 0
end

function Helpers.markServerApplyRequested(character)
    local requestKey = Helpers.serverAutoApplyRequestKey(character)
    if pendingServerApplyRequestKey ~= requestKey then
        pendingServerApplyAttempts = 0
    end
    pendingServerApplyRequestKey = requestKey
    pendingServerApplyLastRequestTick = globalTick
    pendingServerApplyAttempts = pendingServerApplyAttempts + 1
    lastServerAutoApplySignature = requestKey
    return requestKey
end

function Helpers.resetInitialEquipGate()
    initialEquipGateActive = false
    initialEquipGateStartedTick = 0
    initialEquipGateLastEquipTick = 0
    initialEquipGateSeenEquip = false
    initialEquipGateSignature = nil
    initialEquipGateStableTicks = 0
    initialEquipGateCharacterKey = nil
    initialEquipGateLastStatusTick = 0
end

function Helpers.startInitialEquipGate()
    initialEquipGateActive = true
    initialEquipGateStartedTick = globalTick
    initialEquipGateLastEquipTick = 0
    initialEquipGateSeenEquip = false
    initialEquipGateSignature = nil
    initialEquipGateStableTicks = 0
    initialEquipGateCharacterKey = nil
    initialEquipGateLastStatusTick = 0
end

function Helpers.currentSessionRunning()
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

function Helpers.initialEquipGateReady(character)
    if not initialEquipGateActive then return true end
    if character == nil or not Helpers.currentSessionRunning() then return false end

    local key = characterStateKey(character)
    if initialEquipGateCharacterKey ~= key then
        initialEquipGateCharacterKey = key
        initialEquipGateSignature = nil
        initialEquipGateStableTicks = 0
        initialEquipGateSeenEquip = false
        initialEquipGateLastEquipTick = 0
    end

    local signature = Helpers.equipmentSignature(character)
    if signature == initialEquipGateSignature then
        initialEquipGateStableTicks = initialEquipGateStableTicks + 1
    else
        initialEquipGateSignature = signature
        initialEquipGateStableTicks = 0
    end

    local waitedTicks = globalTick - initialEquipGateStartedTick
    local quietAfterEquip = initialEquipGateSeenEquip and (globalTick - initialEquipGateLastEquipTick >= InitialEquipStableTicks)
    local stable = initialEquipGateStableTicks >= InitialEquipStableTicks
    local emptyStable = not initialEquipGateSeenEquip and stable and Helpers.managedWearableSlotsAreEmpty(character)
    local fallbackStable = waitedTicks >= InitialEquipFallbackTicks and stable

    if (quietAfterEquip and stable) or emptyStable or fallbackStable then
        Helpers.resetInitialEquipGate()
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

function Helpers.snapshot(character)
    local data = {}
    for _, entry in ipairs(slots) do
        local item = getSlotItem(character, entry.slot)
        data[entry.key] = Helpers.isIgnoredWardrobeItem(item) and nil or item
    end
    return data
end

function Helpers.clearVisualOverride(character)
    if Helpers.ensureVisualOverride() == nil then return end
    pcall(function()
        VisualOverride.ClearCharacter(character)
    end)
end

function Helpers.tryClearVisualOverride(character)
    if character == nil then return true end
    if Helpers.ensureVisualOverride() == nil then return true end
    local ok, reason = pcall(function()
        VisualOverride.ClearCharacter(character)
    end)
    return ok, ok and nil or tostring(reason)
end

function Helpers.clearAllVisualOverrides()
    if Helpers.ensureVisualOverride() == nil then return end
    pcall(function()
        VisualOverride.ClearAll()
    end)
end

function Helpers.restoreItemVisuals(character)
    if Helpers.ensureVisualOverride() == nil then return end
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

function Helpers.pruneVisualOverrides()
    if Helpers.ensureVisualOverride() == nil then return end
    pcall(function()
        VisualOverride.PruneStaleCharacters()
    end)
end

function Helpers.captureVisualOverride(character, item)
    if Helpers.ensureVisualOverride() == nil or character == nil or item == nil then return 0 end
    local ok, count = pcall(function()
        return VisualOverride.CaptureFashionItem(character, item)
    end)
    if ok and count ~= nil then return count end
    return 0
end

function Helpers.tryRestoreItemVisuals(character)
    if Helpers.ensureVisualOverride() == nil then return true end
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

function Helpers.beginFashionTransaction(character)
    if Helpers.ensureVisualOverride() == nil or character == nil then
        return false, "visual override is unavailable"
    end
    local ok, result = pcall(function()
        return VisualOverride.BeginFashionTransaction(character)
    end)
    if not ok then return false, "renderer staging API is unavailable: " .. tostring(result) end
    if result ~= true then return false, "renderer refused to begin a staging transaction" end
    return true
end

function Helpers.abortFashionTransaction(character)
    if Helpers.ensureVisualOverride() == nil or character == nil then return false end
    local ok, result = pcall(function()
        return VisualOverride.AbortFashionTransaction(character)
    end)
    return ok and result == true
end

function Helpers.commitFashionTransaction(character)
    if Helpers.ensureVisualOverride() == nil or character == nil then
        return false, "visual override is unavailable"
    end
    local ok, result = pcall(function()
        return VisualOverride.CommitFashionTransaction(character)
    end)
    if not ok then return false, "renderer commit failed: " .. tostring(result) end
    if result ~= true then return false, "renderer rejected the staged fashion session" end
    return true
end

function Helpers.tryCaptureVisualOverride(character, item)
    if Helpers.ensureVisualOverride() == nil or character == nil or item == nil then
        return false, 0, "fashion item is unavailable"
    end
    local ok, count = pcall(function()
        return VisualOverride.CaptureFashionItem(character, item)
    end)
    if not ok then return false, 0, tostring(count) end
    if count == nil then return false, 0, "renderer returned no capture result" end
    return true, tonumber(count) or 0
end

function Helpers.captureVisualOverridePrefab(character, identifier)
    if Helpers.ensureVisualOverride() == nil or character == nil or identifier == nil or identifier == "" then return 0 end
    local ok, count = pcall(function()
        return VisualOverride.CaptureFashionPrefab(character, tostring(identifier))
    end)
    if ok and count ~= nil then return count end
    return 0
end

function Helpers.tryCaptureVisualOverridePrefab(character, identifier)
    if Helpers.ensureVisualOverride() == nil or character == nil or identifier == nil or identifier == "" then
        return false, 0, "fashion prefab identifier is empty"
    end
    local ok, count = pcall(function()
        return VisualOverride.CaptureFashionPrefab(character, tostring(identifier))
    end)
    if not ok then return false, 0, tostring(count) end
    if count == nil then return false, 0, "renderer returned no prefab capture result" end
    return true, tonumber(count) or 0
end

function Helpers.captureEmptyVisualOverride(character)
    if Helpers.ensureVisualOverride() == nil or character == nil then return false end
    local ok, result = pcall(function()
        return VisualOverride.CaptureEmptyFashion(character)
    end)
    return ok and result == true
end

-- Missing entries are explicit saved-empty slots, not "leave current equipment
-- alone". The renderer uses this mask to hide items equipped after the capture.
function Helpers.setFashionSlotMask(character, lookData)
    if Helpers.ensureVisualOverride() == nil or character == nil then return false end
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

function Helpers.setAttachmentVisibilityVisual(character, value)
    if Helpers.ensureVisualOverride() == nil or character == nil then return false end
    local visibility
    if type(value) == "table" then
        visibility = copyAttachmentVisibility(value, false)
    elseif type(value) == "boolean" then
        visibility = attachmentVisibilityFromLegacy(value)
    else
        visibility = copyAttachmentVisibility(attachmentVisibility, hideHair)
    end
    local forceHide, forceShow, maskReason = attachmentVisibilityMasks(visibility)
    if forceHide == nil or forceShow == nil then
        Helpers.log("Appearance-layer update failed: " .. tostring(maskReason or "invalid visibility policy"))
        return false
    end
    local ok, result = pcall(function()
        return VisualOverride.SetAttachmentVisibility(character, forceHide, forceShow)
    end)
    if not ok then
        Helpers.log("Appearance-layer update failed: " .. tostring(result) ..
            ". Reload the mod so LuaCs recompiles the C# plugin.")
        return false
    end
    return result == true
end

function Helpers.applyVisualOverrideToItem(character, item, carrier)
    if Helpers.ensureVisualOverride() == nil or character == nil or item == nil then return false end
    local ok, result = pcall(function()
        return VisualOverride.ApplyFashionItemVisual(character, item, carrier == true)
    end)
    return ok and result == true
end

function Helpers.activateFashionVisual(character)
    if Helpers.ensureVisualOverride() == nil or character == nil then return false end
    local ok, result = pcall(function()
        return VisualOverride.ActivateFashionVisual(character)
    end)
    return ok and result == true
end

function Helpers.canReuseCapturedFashion(character)
    if Helpers.ensureVisualOverride() == nil or character == nil then return false end
    local ok, result = pcall(function()
        return VisualOverride.CanReuseCapturedFashion(character)
    end)
    return ok and result == true
end

function Helpers.visualSnapshot(character)
    local data = {}
    for _, entry in ipairs(slots) do
        local item = getSlotItem(character, entry.slot)
        if item ~= nil and not Helpers.isIgnoredWardrobeItem(item) then
            data[entry.key] = {
                identifier = Helpers.itemIdentifier(item),
                itemId = Helpers.itemEntityId(item),
                name = Helpers.itemName(item),
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
function Helpers.writeClientLookPayload(message, lookData, captured)
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

function Helpers.sendLegacyCommand(command)
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
        elseif command.kind == COMMAND_VISIBILITY then
            error("the legacy wardrobe protocol does not support attachment visibility")
        else
            error("unknown legacy wardrobe command " .. tostring(command.kind))
        end

        local message = Networking.Start(messageName)
        if command.kind == COMMAND_APPLY then
            Helpers.writeClientLookPayload(message, command.legacyLook, command.captured == true)
        end
        Networking.Send(message)
    end)
    if not ok then
        Helpers.debugLog("Failed to send v1 wardrobe command: " .. tostring(reason))
    end
    return ok == true
end

function Helpers.writeProjectedV2Look(message, look)
    local valid, reason = Core.validateLook(look)
    if valid == nil then return false, reason end
    message.WriteUInt16(Core.LOOK_SCHEMA_VERSION)
    message.WriteBoolean(valid.captured == true)
    message.WriteBoolean(legacyHideHairForVisibility(valid.attachmentVisibility))
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

function Helpers.writeAndSendV2Command(command, baseRevision)
    if not coreAvailable or Networking == nil or command == nil then return false end
    local ok, reason = pcall(function()
        local message = Networking.Start(NET_V2_COMMAND)
        if serverSupportsAttachmentVisibility() then
            local written, writeReason = Core.writeCommand(message, {
                clientSessionId = clientSessionId,
                operationId = command.operationId,
                baseRevision = baseRevision,
                kind = command.kind,
                look = command.look
            })
            if not written then error(writeReason) end
        else
            if command.kind == COMMAND_VISIBILITY then
                error("server does not advertise attachment visibility support")
            end
            message.WriteUInt16(Core.PROTOCOL_VERSION)
            message.WriteString(clientSessionId)
            message.WriteString(command.operationId)
            message.WriteUInt32(baseRevision)
            message.WriteString(command.kind)
            message.WriteBoolean(command.look ~= nil)
            if command.look ~= nil then
                local written, writeReason = Helpers.writeProjectedV2Look(message, command.look)
                if not written then error(writeReason) end
            end
        end
        Networking.Send(message)
    end)
    if not ok then
        Helpers.debugLog("Failed to send v2 wardrobe command: " .. tostring(reason))
    end
    return ok == true
end

function Helpers.sendNextProtocolCommand()
    if not Helpers.isMultiplayerClient() or Networking == nil or #protocolCommandQueue == 0 then return false end

    if protocolMode == "v1" then
        local sentAny = false
        while #protocolCommandQueue > 0 do
            local command = table.remove(protocolCommandQueue, 1)
            local sent = Helpers.sendLegacyCommand(command)
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
    if not Helpers.writeAndSendV2Command(command, baseRevision) then return false end

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

function Helpers.sendV2Hello()
    if not coreAvailable or not Helpers.isMultiplayerClient() or Networking == nil then return false end
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
        Helpers.debugLog("Failed to send v2 hello; waiting for v1 fallback: " .. tostring(reason))
        protocolHelloSentAt = protocolClock()
    end
    return ok == true
end

function Helpers.selectV1Protocol(reason)
    if protocolMode == "v1" then return end
    protocolMode = "v1"
    serverCapabilities = 0
    visibilitySyncPendingNegotiation = false
    inFlightV2Command = nil
    Helpers.debugLog("Using v1 wardrobe protocol" .. (reason ~= nil and (": " .. tostring(reason)) or "."))
    Helpers.sendNextProtocolCommand()
end

function Helpers.selectV2Protocol(revision, capabilities)
    if not coreAvailable then return false end
    protocolMode = "v2"
    serverCapabilities = tonumber(capabilities) or 0
    local serverRevision = tonumber(revision) or 0
    if clientController == nil then
        reducerState = Core.newClientState({ clientSessionId = clientSessionId, revision = serverRevision })
        clientController = createClientController(reducerState)
    else
        dispatchReducer({ type = "RevisionObserved", revision = serverRevision })
    end
    Helpers.debugLog("Negotiated wardrobe protocol v2 at revision " .. tostring(serverRevision) ..
        " with capabilities 0x" .. string.format("%02X", serverCapabilities) .. ".")
    Helpers.sendNextProtocolCommand()
    return true
end

function Helpers.flushPendingVisibilitySync()
    if not visibilitySyncPendingNegotiation then return false end
    if not serverSupportsAttachmentVisibility() or not Helpers.hasSavedLook() then
        visibilitySyncPendingNegotiation = false
        return false
    end
    local state = clientController ~= nil and clientController.getState() or reducerState
    if state == nil or state.pendingKind ~= nil then return false end
    visibilitySyncPendingNegotiation = false
    dispatchReducer({
        type = "SetAttachmentVisibility",
        attachmentVisibility = copyAttachmentVisibility(attachmentVisibility, hideHair),
        remote = true,
        operationId = nextOperationId()
    })
    return true
end

-- Commands may be queued before protocol negotiation completes. The queue owns
-- v2 ordering/retries while reducerOwned prevents the same request from being
-- introduced into the state machine twice.
function Helpers.queueProtocolCommand(kind, lookData, captured, operationId, reducerOwned, domainLookOverride)
    if not Helpers.isMultiplayerClient() or Networking == nil then return false end
    local domainLook = nil
    if coreAvailable and kind == COMMAND_VISIBILITY then
        if not serverSupportsAttachmentVisibility() then
            Helpers.debugLog("Kept attachment visibility local because the server did not advertise support.")
            return false
        end
        domainLook = Core.copyLook(domainLookOverride)
        if domainLook == nil then
            Helpers.debugLog("Refused to queue invalid attachment visibility.")
            return false
        end
    elseif coreAvailable and (kind == COMMAND_SAVE or kind == COMMAND_APPLY) then
        domainLook = domainLookOverride ~= nil and Core.copyLook(domainLookOverride) or
            domainLookFromLegacy(
                lookData or {},
                captured == true,
                hideHair == true,
                attachmentVisibility
            )
        if domainLook == nil then
            Helpers.debugLog("Refused to queue invalid wardrobe look for " .. tostring(kind) .. ".")
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
        Helpers.sendV2Hello()
        return true, true
    else
        local sent = Helpers.sendNextProtocolCommand()
        if protocolMode == "v1" then return sent == true, false end
        -- Being queued behind another in-flight v2 command is success. The
        -- queue owns retry/timeout and will feed CommandTimedOut if it can
        -- never put the message on the wire.
        return true, true
    end
end

function Helpers.processProtocolNegotiation()
    if not Helpers.isMultiplayerClient() or Networking == nil then return end
    if protocolMode == "probing" then
        Helpers.sendV2Hello()
        if protocolHelloSentAt ~= nil and
            protocolClock() - protocolHelloSentAt >= (Core.HELLO_TIMEOUT_SECONDS or 5) then
            Helpers.selectV1Protocol("server did not answer the v2 hello within 5 seconds")
        end
        return
    end

    if protocolMode == "v2" then Helpers.flushPendingVisibilitySync() end

    if protocolMode == "v2" and inFlightV2Command ~= nil then
        local elapsed = protocolClock() - (inFlightV2Command.sentAt or 0)
        if elapsed >= 1 then
            if (inFlightV2Command.attempts or 1) < 5 then
                if Helpers.writeAndSendV2Command(inFlightV2Command, inFlightV2Command.baseRevision or 0) then
                    inFlightV2Command.attempts = (inFlightV2Command.attempts or 1) + 1
                    inFlightV2Command.sentAt = protocolClock()
                end
            else
                dispatchReducer({
                    type = "CommandTimedOut",
                    operationId = inFlightV2Command.operationId,
                    reason = "v2 command acknowledgement timed out"
                })
                Helpers.debugLog("v2 wardrobe command timed out after five idempotent attempts: " .. tostring(inFlightV2Command.operationId))
                table.remove(protocolCommandQueue, 1)
                inFlightV2Command = nil
                Helpers.sendNextProtocolCommand()
            end
        end
    elseif protocolMode == "v2" and #protocolCommandQueue > 0 then
        local queued = protocolCommandQueue[1]
        local now = protocolClock()
        if now - (queued.lastUnsentAttemptAt or 0) >= 0.25 then
            queued.lastUnsentAttemptAt = now
            if Helpers.sendNextProtocolCommand() then
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
                    Helpers.sendNextProtocolCommand()
                end
            end
        end
    end
end

function Helpers.requestServerSaveFashion()
    return Helpers.queueProtocolCommand(COMMAND_SAVE, savedLook, savedLookCaptured == true)
end

function Helpers.requestServerApplyFashion(lookData, captured)
    return Helpers.queueProtocolCommand(COMMAND_APPLY, lookData, captured == true)
end

function Helpers.requestServerApplyForCharacter(character)
    if character == nil then return false end
    if not Helpers.requestServerApplyFashion(savedLook, savedLookCaptured == true) then return false end
    Helpers.markServerApplyRequested(character)
    return true
end

function Helpers.requestServerClearFashion()
    return Helpers.queueProtocolCommand(COMMAND_CLEAR, nil, false)
end

function Helpers.requestServerForgetFashion()
    return Helpers.queueProtocolCommand(COMMAND_FORGET, nil, false)
end

function Helpers.readNetworkLook(message)
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

-- One real item can occupy multiple managed slots. Deduplicate by instance/id,
-- then fall back to one prefab capture per identifier when the original item no
-- longer exists (for example after a save removed it from inventory).
function Helpers.captureFashionPayloadFromLook(character, lookData, diagnostics)
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

        local runtimeId = tonumber(Helpers.itemEntityId(item)) or 0
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
            local item = Helpers.findEntityById(itemId)
            local foundBy = item ~= nil and "entity id" or "none"
            if item == nil or Helpers.itemIdentifier(item) ~= identifier then
                item = Helpers.findItemByIdentifier(character, identifier)
                foundBy = item ~= nil and "character inventory identifier" or "none"
            end
            if item ~= nil then
                local duplicate, duplicateKey = rememberRealItem(item, itemId)
                local captured = 0
                local capturedOk = true
                local captureReason = nil
                if not duplicate then
                    uniqueItems = uniqueItems + 1
                    capturedOk, captured, captureReason = Helpers.tryCaptureVisualOverride(character, item)
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
                    capturedOk, captured, captureReason = Helpers.tryCaptureVisualOverridePrefab(character, identifier)
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

function Helpers.applyCapturedFashionToCharacterEquipment(character, lookData, recapturePayload, visibilityValue)
    if character == nil then return false, 0 end

    local look = lookData or savedLook
    if recapturePayload ~= false then
        local begun, beginReason = Helpers.beginFashionTransaction(character)
        if not begun then return false, 0, beginReason end
        local captured, _, _, captureReason = Helpers.captureFashionPayloadFromLook(character, look)
        if not captured then
            Helpers.abortFashionTransaction(character)
            return false, 0, captureReason
        end
        if not Helpers.setFashionSlotMask(character, look) then
            Helpers.abortFashionTransaction(character)
            return false, 0, "renderer rejected the staged fashion slot mask"
        end
        if character == controlled() or visibilityValue ~= nil then
            if not Helpers.setAttachmentVisibilityVisual(character, visibilityValue) then
                Helpers.abortFashionTransaction(character)
                return false, 0, "renderer rejected the staged attachment visibility"
            end
        end
        local committed, commitReason = Helpers.commitFashionTransaction(character)
        if not committed then
            Helpers.abortFashionTransaction(character)
            return false, 0, commitReason
        end
    else
        if not Helpers.setFashionSlotMask(character, look) then
            return false, 0
        end
        if (character == controlled() or visibilityValue ~= nil) and
            not Helpers.setAttachmentVisibilityVisual(character, visibilityValue) then
            return false, 0
        end
    end

    local current = Helpers.snapshot(character)
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
        if Helpers.applyVisualOverrideToItem(character, entry.item, index == 1) then
            visualItems = visualItems + 1
        end
    end

    local activated = Helpers.activateFashionVisual(character)
    if not activated then return false, visualItems, "renderer activation failed" end
    return true, visualItems, nil
end

function Helpers.applyNetworkLook(character, networkLook, visibilityValue)
    local diagnostics = {}
    if character == nil or networkLook == nil then return false, diagnostics end
    local visualStatus = Helpers.visualOverrideStatus()
    if visualStatus ~= nil then
        diagnostics[#diagnostics + 1] = "visual override not ready: " .. tostring(visualStatus)
        return false, diagnostics
    end

    local begun, beginReason = Helpers.beginFashionTransaction(character)
    if not begun then
        diagnostics[#diagnostics + 1] = tostring(beginReason)
        return false, diagnostics
    end

    local capturedPayload, expectedItems, capturedItems, captureReason =
        Helpers.captureFashionPayloadFromLook(character, networkLook, diagnostics)
    if not capturedPayload or not Helpers.setFashionSlotMask(character, networkLook) or
        not Helpers.setAttachmentVisibilityVisual(character, visibilityValue) then
        Helpers.abortFashionTransaction(character)
        diagnostics[#diagnostics + 1] = tostring(captureReason or "renderer rejected staged look metadata")
        return false, diagnostics
    end

    local committed, commitReason = Helpers.commitFashionTransaction(character)
    if not committed then
        Helpers.abortFashionTransaction(character)
        diagnostics[#diagnostics + 1] = tostring(commitReason)
        return false, diagnostics
    end

    local activated = Helpers.applyCapturedFashionToCharacterEquipment(
        character,
        networkLook,
        false,
        visibilityValue
    )
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
    local overrideState = Helpers.visualOverrideState()
    if not overrideState.ready then return false, tostring(overrideState.details or overrideState.label) end

    local startingItems = Helpers.snapshot(character)
    local lookData = Helpers.visualSnapshot(character)
    local domainLook, lookReason = domainLookFromLegacy(
        lookData,
        true,
        hideHair == true,
        attachmentVisibility
    )
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
        local begun, beginReason = Helpers.beginFashionTransaction(character)
        if not begun then return false, beginReason end
        context.staged = true
        local processedItems = {}
        for _, entry in ipairs(slots) do
            local item = startingItems[entry.key]
            if item ~= nil and not processedItems[item] then
                processedItems[item] = true
                context.startingItemCount = context.startingItemCount + 1
                local captured, spriteCount, captureReason = Helpers.tryCaptureVisualOverride(character, item)
                if not captured then
                    Helpers.abortFashionTransaction(character)
                    return false, entry.key .. ": " .. tostring(captureReason)
                end
                context.capturedSprites = context.capturedSprites + spriteCount
            end
        end
        if context.startingItemCount == 0 then
            local emptyCaptured, emptyReason = tryCaptureEmptyVisualOverride(character)
            if not emptyCaptured then
                Helpers.abortFashionTransaction(character)
                return false, emptyReason
            end
        end
        if not Helpers.setFashionSlotMask(character, lookData) or
            not Helpers.setAttachmentVisibilityVisual(character, attachmentVisibility) then
            Helpers.abortFashionTransaction(character)
            return false, "renderer rejected staged slot or attachment metadata"
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
        Helpers.abortFashionTransaction(pendingSaveContext.character)
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
                missing[#missing + 1] = entry.key .. ": " .. Helpers.itemName(item)
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
            local remainingSlots = Helpers.wornSlotLabelsForItem(context.character, item)
            if removed and #remainingSlots == 0 then
                removedItems = removedItems + 1
                results[entry.key] = "Saved and removed"
            else
                local result = "Still equipped in " .. table.concat(remainingSlots, ", ")
                results[entry.key] = result
                failedItems[#failedItems + 1] = slotLabel(entry) .. ": " .. Helpers.itemName(item)
            end
        end
    end

    if #failedItems > 0 then
        Helpers.abortFashionTransaction(context.character)
        local restored, rollbackFailures = restoreStartingEquipment()
        pendingSaveContext = nil
        lastNetworkApplyDiagnostics = { "unequip transaction failed: " .. table.concat(failedItems, "; ") }
        local reason = "one or more fashion items remained equipped: " .. table.concat(failedItems, "; ")
        if not restored then
            reason = reason .. "; equipment rollback failed for " .. table.concat(rollbackFailures, "; ")
        end
        return false, reason
    end

    local committed, commitReason = Helpers.commitFashionTransaction(context.character)
    if not committed then
        Helpers.abortFashionTransaction(context.character)
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
    Helpers.clearPendingServerApplyRequest()
    Helpers.clearNetworkApplySuppressionForCharacter(context.character)
    local message
    if context.startingItemCount == 0 then
        message = "Saved current outfit: empty outfit captured."
    else
        message = "Saved current outfit: " .. tostring(context.capturedSprites) ..
            " wearable sprites captured, " .. tostring(removedItems) ..
            " item" .. (removedItems == 1 and "" or "s") .. " removed."
    end
    pendingSaveContext = nil
    Helpers.log(message)
    return { type = "UnequipSucceeded" }
end

clientEffectAdapters.SendCommand = function(currentEffect)
    local lookData = legacyLookFromDomain(currentEffect.look)
    local captured = currentEffect.look ~= nil and currentEffect.look.captured == true
    local queued, awaitAck = Helpers.queueProtocolCommand(
        currentEffect.kind,
        lookData,
        captured,
        currentEffect.operationId,
        true,
        currentEffect.look
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
        Helpers.clearPendingServerApplyRequest()
        Helpers.log("Saved current outfit; server-side removal requested for multiplayer.")
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
    local character = currentEffect.characterId ~= nil and Helpers.findEntityById(currentEffect.characterId) or controlled()
    if character == nil then return false, "render target character is unavailable" end
    local lookData = legacyLookFromDomain(currentEffect.look)
    local applied, diagnostics
    local visualItems = 0
    if currentEffect.characterId ~= nil then
        applied, diagnostics = Helpers.applyNetworkLook(
            character,
            lookData,
            currentEffect.look.attachmentVisibility
        )
    else
        local reason
        local reuseCapturedSession = Helpers.canReuseCapturedFashion(character)
        applied, visualItems, reason = Helpers.applyCapturedFashionToCharacterEquipment(
            character,
            lookData,
            not reuseCapturedSession,
            currentEffect.look.attachmentVisibility
        )
        diagnostics = reason ~= nil and { reason } or
            (reuseCapturedSession and { "reused committed renderer session" } or {})
    end
    if not applied then
        lastNetworkApplyDiagnostics = diagnostics or {}
        return false, table.concat(lastNetworkApplyDiagnostics, "; ")
    end

    lastCharacter = character
    lastEquipmentSignature = Helpers.equipmentSignature(character)
    lastNetworkApplyDiagnostics = diagnostics or {}
    slotResults = {}
    for _, entry in ipairs(slots) do
        slotResults[entry.key] = lookData[entry.key] ~= nil and
            (currentEffect.characterId ~= nil and "Synced from server" or "Saved and applied") or "Empty"
    end
    Helpers.clearPendingServerApplyRequest()
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
    local applied, _, reason = Helpers.applyCapturedFashionToCharacterEquipment(
        character,
        lookData,
        true,
        currentEffect.look.attachmentVisibility
    )
    if applied then return { type = "CompensationSucceeded" } end
    return { type = "CompensationFailed", reason = reason }
end

clientEffectAdapters.ClearRender = function(currentEffect)
    local character = currentEffect.characterId ~= nil and Helpers.findEntityById(currentEffect.characterId) or controlled()
    if character == nil then character = lastCharacter end
    local ok, reason
    if currentEffect.dispose == true or currentEffect.forget == true or currentEffect.remote == true then
        ok, reason = Helpers.tryClearVisualOverride(character)
    else
        ok, reason = Helpers.tryRestoreItemVisuals(character)
    end
    if not ok then return false, reason end
    Helpers.deactivateCachedCharacterStates(character, currentEffect.preserveAutoApply == true)
    Helpers.clearLocalPendingNetworkState(character)
    lastEquipmentSignature = nil
    lastServerAutoApplySignature = nil
    Helpers.clearPendingServerApplyRequest()
    pendingRoundStartNetworkLook = nil
    pendingRoundStartNetworkCharacterKey = nil
    pendingRoundStartNetworkRevision = nil
    pendingRoundStartHideHair = false
    pendingRoundStartAttachmentVisibility = nil
    if currentEffect.forget == true then
        if isSinglePlayerClient() then
            local key = characterStateKey(character)
            if key ~= nil then characterStates[key] = nil end
        else
            characterStates = {}
        end
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
    local character = currentEffect.characterId ~= nil and Helpers.findEntityById(currentEffect.characterId) or controlled()
    if character == nil then character = lastCharacter end
    local ok, reason = Helpers.tryClearVisualOverride(character)
    if ok then return { type = "CompensationSucceeded" } end
    return { type = "CompensationFailed", reason = reason }
end

clientEffectAdapters.ApplyAttachmentVisibility = function(currentEffect)
    local character = controlled()
    if character == nil then return false, "no controlled character" end
    if Helpers.setAttachmentVisibilityVisual(character, currentEffect.attachmentVisibility) then
        return { type = "AttachmentVisibilityUpdateSucceeded" }
    end
    return false, "renderer rejected attachment visibility"
end

clientEffectAdapters.ApplyAttachmentVisibilityCompensation = function(currentEffect)
    local character = controlled()
    if character ~= nil and
        Helpers.setAttachmentVisibilityVisual(character, currentEffect.attachmentVisibility) then
        return { type = "CompensationSucceeded" }
    end
    return { type = "CompensationFailed", reason = "attachment visibility rollback failed" }
end

function Helpers.saveFashionAndUnequip()
    local character = controlled()
    if character == nil then
        Helpers.log("No controlled character.")
        return false
    end
    Helpers.clearNetworkApplySuppressionForCharacter(character)
    local remote = Helpers.isMultiplayerClient()
    local operationId = remote and nextOperationId() or nil
    dispatchReducer({
        type = "SaveRequested",
        remote = remote,
        operationId = operationId
    })
    local state = clientController ~= nil and clientController.getState() or reducerState
    if state ~= nil and state.phase == Core.PHASE.Faulted then
        Helpers.log("Save failed: " .. tostring(state.error or "unknown adapter failure"))
        return false
    end
    return true
end

function Helpers.applyFashionToCurrentEquipment(silent)
    local character = controlled()
    if character == nil then
        if not silent then Helpers.log("No controlled character.") end
        return false
    end

    if not Helpers.hasSavedLook() then
        if not silent then Helpers.log("No saved look. Save an outfit first.") end
        return false
    end

    local visualStatus = Helpers.visualOverrideStatus()
    if visualStatus ~= nil then
        if not silent then Helpers.log(visualStatus) end
        return false
    end

    if not silent then
        Helpers.clearNetworkApplySuppressionForCharacter(character)
    end

    local domainLook = currentDomainLook()
    if Helpers.isMultiplayerClient() then
        local operationId = nextOperationId()
        dispatchReducer({
            type = "CommandRequested",
            operationId = operationId,
            kind = COMMAND_APPLY,
            look = domainLook
        })
        Helpers.markServerApplyRequested(character)
    else
        dispatchReducer({ type = "LocalApplyRequested", look = domainLook })
    end
    local state = clientController ~= nil and clientController.getState() or reducerState
    if state ~= nil and state.phase == Core.PHASE.Faulted then
        if not silent then Helpers.log("Saved look could not be applied: " .. tostring(state.error)) end
        return false
    end
    if not silent and Helpers.isMultiplayerClient() then Helpers.log("Requested multiplayer wardrobe apply from the server.") end
    return true
end

function Helpers.clearActiveLook()
    local character = controlled()
    local multiplayerClearRequested = Helpers.isMultiplayerClient()
    if multiplayerClearRequested then
        dispatchReducer({
            type = "CommandRequested",
            operationId = nextOperationId(),
            kind = COMMAND_CLEAR
        })
    else
        dispatchReducer({ type = "LocalClearRequested" })
    end
    Helpers.clearLocalPendingNetworkState(character)
    Helpers.suppressNetworkAppliesForCharacter(character)
    local state = clientController ~= nil and clientController.getState() or reducerState
    if state ~= nil and state.phase == Core.PHASE.Faulted then
        Helpers.log("Look clear failed: " .. tostring(state.error))
    elseif multiplayerClearRequested then
        Helpers.log("Look cleared. Multiplayer clear requested from the server.")
    else
        Helpers.log("Look cleared. Real equipment visuals restored.")
    end
end

-- Equipment changes do not alter the saved look, but they can introduce new
-- originals that its saved/empty slot masks must cover. Reapply only when the
-- stable equipment signature changes.
function Helpers.refreshActiveLookIfNeeded(character)
    if character == nil or not activeLook or not Helpers.hasSavedLook() then return end
    local signature = Helpers.equipmentSignature(character)
    if lastEquipmentSignature == signature then return end
    if Helpers.applyFashionToCurrentEquipment(true) then
        lastOperation = "Saved look refreshed for changed equipment."
    else
        lastEquipmentSignature = nil
        lastOperation = "Saved look needs to be applied again."
    end
end

function Helpers.autoApplySavedLookIfNeeded(character)
    if character == nil or activeLook or not autoApplyLook or not Helpers.hasSavedLook() then return end
    if isSinglePlayerClient() and singlePlayerAutomaticRestoreAllowed ~= nil and
        not singlePlayerAutomaticRestoreAllowed(character) then
        return
    end
    if Helpers.isMultiplayerClient() and
        lastServerAutoApplySignature == Helpers.serverAutoApplyRequestKey(character) then return end
    local view = clientController ~= nil and clientController.getViewModel() or nil
    if view ~= nil and view.busy then return end
    if Helpers.applyFashionToCurrentEquipment(true) then
        lastOperation = "Saved look auto-applied."
    end
end

function Helpers.handleNoControlledCharacter()
    if lastCharacter ~= nil then
        saveCharacterState(lastCharacter)
        if isSinglePlayerClient() then
            pendingSinglePlayerTransferSourceKey = characterStateKey(lastCharacter)
        end
    end

    local shouldReapplySavedLook = Helpers.hasSavedLook() and (activeLook or autoApplyLook)
    lastEquipmentSignature = nil
    lastServerAutoApplySignature = nil
    Helpers.clearPendingServerApplyRequest()
    lastCharacter = nil

    if Helpers.hasSavedLook() then
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

function Helpers.handleControlledCharacterChange(character)
    if character == nil or character == lastCharacter then return end
    local sourceState = nil
    if lastCharacter ~= nil then
        saveCharacterState(lastCharacter)
        local sourceKey = characterStateKey(lastCharacter)
        sourceState = sourceKey ~= nil and characterStates[sourceKey] or nil
    elseif pendingSinglePlayerTransferSourceKey ~= nil then
        sourceState = characterStates[pendingSinglePlayerTransferSourceKey]
    end

    local hadState = loadCharacterState(character)
    local transferred = false
    if isSinglePlayerClient() and not hadState and
        transferToUnconfiguredCharacter and
        Helpers.stateHasSavedLook(sourceState) and
        (sourceState.activeLook == true or sourceState.autoApplyLook == true) then
        local targetKey = characterStateKey(character)
        local targetProfileKey = Helpers.singlePlayerCharacterProfileKey(character)
        if targetKey ~= nil and targetProfileKey ~= nil and
            not singlePlayerAmbiguousFingerprints[targetProfileKey] then
            local transferredState = {
                savedLook = copyLookData(sourceState.savedLook),
                savedLookCaptured = sourceState.savedLookCaptured == true,
                hideHair = sourceState.hideHair == true,
                attachmentVisibility = copyAttachmentVisibility(
                    sourceState.attachmentVisibility,
                    sourceState.hideHair == true
                ),
                activeLook = false,
                autoApplyLook = true,
                lastEquipmentSignature = nil,
                slotResults = {},
                lastNetworkApplyDiagnostics = {},
                profileKey = targetProfileKey,
                displayName = Helpers.singlePlayerCharacterDisplayName(character),
                persistent = false,
                profileAmbiguous = false
            }
            for _, entry in ipairs(slots) do
                transferredState.slotResults[entry.key] =
                    transferredState.savedLook[entry.key] ~= nil and
                    "Saved look needs to be applied again." or "Empty"
            end
            characterStates[targetKey] = transferredState
            applyCharacterState(transferredState)
            transferred = true
        end
    end

    if transferred then
        lastOperation = "Current look will be applied to this unconfigured character."
    elseif hadState then
        lastOperation = Helpers.hasSavedLook() and "Saved look restored for this character." or "Controlled character changed."
    else
        lastServerAutoApplySignature = nil
        Helpers.clearPendingServerApplyRequest()
        if Helpers.hasSavedLook() then
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
    pendingSinglePlayerTransferSourceKey = nil
    Helpers.pruneVisualOverrides()
end

function Helpers.markSinglePlayerFingerprintAmbiguous(profileKey, firstKey, secondKey)
    if profileKey == nil then return end
    singlePlayerAmbiguousFingerprints[profileKey] = true
    singlePlayerFingerprintOwners[profileKey] = false
    if firstKey ~= nil then pendingSinglePlayerRestores[firstKey] = nil end
    if secondKey ~= nil then pendingSinglePlayerRestores[secondKey] = nil end
    for runtimeKey, state in pairs(characterStates) do
        if state.profileKey == profileKey or runtimeKey == firstKey or runtimeKey == secondKey then
            state.profileAmbiguous = true
            pendingSinglePlayerRestores[runtimeKey] = nil
        end
    end
    Helpers.debugLog(
        "Disabled automatic single-player wardrobe restore for ambiguous character identity " ..
        tostring(profileKey) ..
        "."
    )
end

function Helpers.registerSinglePlayerCharacter(character)
    if not Helpers.singlePlayerCharacterEligible(character) then return false end
    local runtimeKey = characterStateKey(character)
    local profileKey = Helpers.singlePlayerCharacterProfileKey(character)
    if runtimeKey == nil or profileKey == nil then return false end
    singlePlayerCharactersByRuntimeKey[runtimeKey] = character

    local owner = singlePlayerFingerprintOwners[profileKey]
    if owner == nil then
        singlePlayerFingerprintOwners[profileKey] = runtimeKey
    elseif owner ~= false and owner ~= runtimeKey then
        Helpers.markSinglePlayerFingerprintAmbiguous(profileKey, owner, runtimeKey)
    end

    local state = characterStates[runtimeKey]
    if state ~= nil then
        state.profileKey = profileKey
        state.displayName = Helpers.singlePlayerCharacterDisplayName(character)
        state.profileAmbiguous = singlePlayerAmbiguousFingerprints[profileKey] == true
    end
    return not singlePlayerAmbiguousFingerprints[profileKey]
end

singlePlayerAutomaticRestoreAllowed = function(character)
    if not Helpers.singlePlayerCharacterEligible(character) then return false end
    if not Helpers.registerSinglePlayerCharacter(character) then return false end
    local profileKey = Helpers.singlePlayerCharacterProfileKey(character)
    return profileKey ~= nil and not singlePlayerAmbiguousFingerprints[profileKey]
end

function Helpers.queueSinglePlayerProfileRestore(character)
    if not singlePlayerAutomaticRestoreAllowed(character) then return false end
    local runtimeKey = characterStateKey(character)
    if runtimeKey == nil then return false end

    local state = characterStates[runtimeKey]
    if state == nil and type(loadSinglePlayerProfileState) == "function" then
        state = loadSinglePlayerProfileState(character)
        if state ~= nil then characterStates[runtimeKey] = state end
    end
    if state == nil or not Helpers.stateHasSavedLook(state) then
        return false
    end

    state.profileKey = Helpers.singlePlayerCharacterProfileKey(character)
    state.displayName = Helpers.singlePlayerCharacterDisplayName(character)
    if character == controlled() then
        applyCharacterState(state)
        dispatchReducer({
            type = "RestoreLook",
            look = currentDomainLook(),
            active = state.activeLook == true,
            autoApply = state.autoApplyLook == true
        })
        return true
    end
    if state.autoApplyLook ~= true then return false end

    state.activeLook = false
    state.lastEquipmentSignature = nil

    pendingSinglePlayerRestores[runtimeKey] = {
        character = character,
        startedTick = globalTick,
        lastEquipTick = 0,
        seenEquip = false,
        signature = nil,
        stableTicks = 0,
        ready = false,
        attempts = 0,
        nextAttemptTick = globalTick
    }
    return true
end

function Helpers.singlePlayerCharactersSnapshot()
    local characters = {}
    local list = Character ~= nil and Character.CharacterList or nil
    if list == nil then return characters end
    if type(list) == "table" then
        for _, character in ipairs(list) do
            characters[#characters + 1] = character
        end
        return characters
    end
    pcall(function()
        for character in list do
            characters[#characters + 1] = character
        end
    end)
    return characters
end

function Helpers.scanSinglePlayerCrewForRestores()
    if not isSinglePlayerClient() then return end
    singlePlayerRoundScanned = true
    singlePlayerFingerprintOwners = {}
    singlePlayerCharactersByRuntimeKey = {}
    singlePlayerAmbiguousFingerprints = {}

    local characters = Helpers.singlePlayerCharactersSnapshot()
    for _, character in ipairs(characters) do
        Helpers.registerSinglePlayerCharacter(character)
    end
    for _, character in ipairs(characters) do
        Helpers.queueSinglePlayerProfileRestore(character)
    end
end

function Helpers.noteSinglePlayerEquipmentChange(character)
    if not isSinglePlayerClient() or character == nil then return end
    local key = characterStateKey(character)
    local pending = key ~= nil and pendingSinglePlayerRestores[key] or nil
    if pending == nil then return end
    pending.seenEquip = true
    pending.lastEquipTick = globalTick
    pending.stableTicks = 0
    pending.signature = nil
end

function Helpers.singlePlayerRestoreReady(pending)
    if pending.ready then return true end
    local character = pending.character
    if character == nil or not Helpers.currentSessionRunning() then return false end
    local signature = Helpers.equipmentSignature(character)
    if signature == pending.signature then
        pending.stableTicks = pending.stableTicks + 1
    else
        pending.signature = signature
        pending.stableTicks = 0
    end

    local waitedTicks = globalTick - pending.startedTick
    local stable = pending.stableTicks >= InitialEquipStableTicks
    local quietAfterEquip = pending.seenEquip and
        globalTick - pending.lastEquipTick >= InitialEquipStableTicks
    local emptyStable = not pending.seenEquip and stable and
        Helpers.managedWearableSlotsAreEmpty(character)
    local fallbackStable = waitedTicks >= InitialEquipFallbackTicks and stable
    pending.ready = (quietAfterEquip and stable) or emptyStable or fallbackStable
    return pending.ready
end

function Helpers.processPendingSinglePlayerRestores()
    if not isSinglePlayerClient() then return end
    for runtimeKey, pending in pairs(pendingSinglePlayerRestores) do
        local character = pending.character
        local removed = character == nil or Helpers.userDataMember(character, "Removed") == true
        if removed or character == controlled() then
            pendingSinglePlayerRestores[runtimeKey] = nil
        else
            local state = characterStates[runtimeKey]
            if state == nil or not Helpers.stateHasSavedLook(state) or
                state.autoApplyLook ~= true or
                not singlePlayerAutomaticRestoreAllowed(character) then
                pendingSinglePlayerRestores[runtimeKey] = nil
            elseif globalTick >= pending.nextAttemptTick and Helpers.singlePlayerRestoreReady(pending) then
                pending.attempts = pending.attempts + 1
                local applied, _, reason = Helpers.applyCapturedFashionToCharacterEquipment(
                    character,
                    state.savedLook,
                    true,
                    copyAttachmentVisibility(
                        state.attachmentVisibility,
                        state.hideHair == true
                    )
                )
                if applied then
                    state.activeLook = true
                    state.autoApplyLook = true
                    state.lastEquipmentSignature = Helpers.equipmentSignature(character)
                    state.lastNetworkApplyDiagnostics = {}
                    state.slotResults = {}
                    for _, entry in ipairs(slots) do
                        state.slotResults[entry.key] =
                            state.savedLook[entry.key] ~= nil and "Saved and applied" or "Empty"
                    end
                    pendingSinglePlayerRestores[runtimeKey] = nil
                    Helpers.debugLog(
                        "Auto-restored single-player wardrobe profile for " ..
                        tostring(state.displayName or Helpers.singlePlayerCharacterDisplayName(character)) ..
                        "."
                    )
                elseif pending.attempts >= 3 then
                    state.activeLook = false
                    state.lastNetworkApplyDiagnostics = { tostring(reason or "renderer activation failed") }
                    pendingSinglePlayerRestores[runtimeKey] = nil
                    Helpers.debugLog(
                        "Single-player wardrobe profile restore failed for " ..
                        tostring(state.displayName or Helpers.singlePlayerCharacterDisplayName(character)) ..
                        ": " ..
                        tostring(reason or "renderer activation failed")
                    )
                else
                    pending.nextAttemptTick = globalTick + ServerApplyRetryTicks
                end
            end
        end
    end
end

function Helpers.clearSavedLook()
    local character = controlled()
    local multiplayerForgetRequested = Helpers.isMultiplayerClient()
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
        Helpers.log("Saved look was not forgotten: " .. tostring(state.error))
        return false
    end
    Helpers.clearLocalPendingNetworkState(character)
    Helpers.clearCachedLocalNetworkState()
    Helpers.suppressNetworkAppliesForCharacter(character)
    if multiplayerForgetRequested then
        Helpers.log("Server saved look deletion requested; local look will be cleared after acknowledgement.")
    else
        Helpers.log("Saved look cleared.")
    end
    return true
end

function Helpers.deferRoundStartNetworkLook(
    character,
    networkLook,
    protocolRevision,
    hairHidden,
    protocolLook
)
    lastCharacter = character
    pendingRoundStartNetworkLook = copyLookData(networkLook)
    pendingRoundStartNetworkCharacterKey = characterStateKey(character)
    pendingRoundStartNetworkRevision = protocolRevision
    pendingRoundStartHideHair = hairHidden == true
    pendingRoundStartAttachmentVisibility = protocolLook ~= nil and
        copyAttachmentVisibility(protocolLook.attachmentVisibility, protocolLook.hideHair == true) or
        nil
    slotResults = {}
    lastNetworkApplyDiagnostics = { "waiting for initial equipment to finish equipping" }
    for _, entry in ipairs(slots) do
        slotResults[entry.key] = networkLook[entry.key] ~= nil and "Waiting for initial equipment" or "Empty"
    end
    lastOperation = "Multiplayer wardrobe sync is waiting for initial equipment."
end

function Helpers.applyPendingRoundStartNetworkLook(character)
    if character == nil or pendingRoundStartNetworkLook == nil then return false end
    if pendingRoundStartNetworkCharacterKey ~= characterStateKey(character) then return false end

    local networkLook = copyLookData(pendingRoundStartNetworkLook)
    local protocolRevision = pendingRoundStartNetworkRevision
    local hairHidden = pendingRoundStartHideHair
    local pendingVisibility = pendingRoundStartAttachmentVisibility
    pendingRoundStartNetworkLook = nil
    pendingRoundStartNetworkCharacterKey = nil
    pendingRoundStartNetworkRevision = nil
    pendingRoundStartHideHair = false
    pendingRoundStartAttachmentVisibility = nil

    if protocolRevision ~= nil then
        local domainLook = domainLookFromLegacy(
            networkLook,
            true,
            hairHidden,
            pendingVisibility
        )
        rememberLegacyLookMetadata(networkLook)
        local effects = dispatchReducer({
            type = "RemoteStateReceived",
            revision = protocolRevision,
            characterId = Helpers.characterEntityId(character),
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
                    key .. "|" .. lookDataSignature(networkLook, true, pendingVisibility) ..
                    "|" .. Helpers.equipmentSignature(character)
            end
            lastOperation = "Saved look applied from multiplayer sync after initial equipment."
        else
            lastOperation = "Multiplayer wardrobe sync failed after initial equipment; dump debug log."
        end
        return true
    end

    local domainLook = domainLookFromLegacy(
        networkLook,
        true,
        hideHair,
        attachmentVisibility
    )
    rememberLegacyLookMetadata(networkLook)
    dispatchReducer({ type = "LocalApplyRequested", look = domainLook })
    local acceptedState = clientController ~= nil and clientController.getState() or reducerState
    if acceptedState ~= nil and acceptedState.phase == Core.PHASE.Active then
        local key = characterStateKey(character)
        if key ~= nil then
            lastAppliedNetworkLookSignatureByCharacterKey[key] =
                key .. "|" .. lookDataSignature(networkLook, true) .. "|" .. Helpers.equipmentSignature(character)
        end
        lastOperation = "Saved look applied from multiplayer sync after initial equipment."
    else
        lastOperation = "Multiplayer wardrobe sync failed after initial equipment; dump debug log."
    end
    return true
end

function Helpers.networkApplySignature(character, networkLook, protocolLook)
    local key = characterStateKey(character)
    if key == nil then return nil end
    local visibility = protocolLook ~= nil and protocolLook.attachmentVisibility or nil
    return key .. "|" .. lookDataSignature(networkLook, true, visibility) ..
        "|" .. Helpers.equipmentSignature(character)
end

function Helpers.rememberNetworkLookApplied(character, networkLook, protocolLook)
    local key = characterStateKey(character)
    local signature = Helpers.networkApplySignature(character, networkLook, protocolLook)
    if key == nil or signature == nil then return end
    lastAppliedNetworkLookSignatureByCharacterKey[key] = signature
end

function Helpers.networkLookAlreadyApplied(character, networkLook, protocolLook)
    local key = characterStateKey(character)
    local signature = Helpers.networkApplySignature(character, networkLook, protocolLook)
    return key ~= nil and signature ~= nil and lastAppliedNetworkLookSignatureByCharacterKey[key] == signature
end

function Helpers.storePendingNetworkApply(characterId, networkLook, protocolRevision, hairHidden, protocolLook)
    pendingNetworkAppliesByCharacterId[characterId] = {
        look = copyLookData(networkLook),
        receivedTick = globalTick,
        protocolRevision = protocolRevision,
        hideHair = hairHidden == true,
        attachmentVisibility = protocolLook ~= nil and
            copyAttachmentVisibility(protocolLook.attachmentVisibility, protocolLook.hideHair == true) or
            nil,
        protocolLook = coreAvailable and Core.copyLook(protocolLook) or nil
    }
end

function Helpers.storePendingNetworkClear(characterId, protocolRevision, protocolLook)
    pendingNetworkAppliesByCharacterId[characterId] = nil
    pendingNetworkClearsByCharacterId[characterId] = {
        receivedTick = globalTick,
        protocolRevision = protocolRevision,
        protocolLook = coreAvailable and Core.copyLook(protocolLook) or nil
    }
end

function Helpers.handleNetworkLookApply(characterId, networkLook, protocolRevision, hairHidden, protocolLook)
    if protocolRevision == nil and Helpers.networkApplySuppressedForCharacter(characterId, nil) then
        pendingNetworkAppliesByCharacterId[characterId] = nil
        Helpers.debugLog("Ignored suppressed multiplayer wardrobe apply for characterId=" .. tostring(characterId) .. ".")
        return false
    end

    local character = Helpers.findEntityById(characterId)
    if character == nil then
        Helpers.storePendingNetworkApply(characterId, networkLook, protocolRevision, hairHidden, protocolLook)
        return false
    end

    pendingNetworkAppliesByCharacterId[characterId] = nil

    if character == controlled() and initialEquipGateActive and not Helpers.initialEquipGateReady(character) then
        Helpers.deferRoundStartNetworkLook(
            character,
            networkLook,
            protocolRevision,
            hairHidden,
            protocolLook
        )
        return true
    end

    if protocolRevision ~= nil and character == controlled() then
        local domainLook = protocolLook or domainLookFromLegacy(
            networkLook,
            true,
            hairHidden,
            protocolLook ~= nil and protocolLook.attachmentVisibility or nil
        )
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
            Helpers.rememberNetworkLookApplied(character, networkLook, protocolLook)
            return true
        end
        return false
    end

    if protocolRevision == nil and character == controlled() then
        if Helpers.networkApplySuppressedForCharacter(characterId, character) then
            Helpers.debugLog("Ignored suppressed multiplayer wardrobe apply for characterId=" .. tostring(characterId) .. ".")
            return false
        end
        local domainLook = domainLookFromLegacy(
            networkLook,
            true,
            hideHair,
            attachmentVisibility
        )
        rememberLegacyLookMetadata(networkLook)
        dispatchReducer({ type = "LocalApplyRequested", look = domainLook })
        local acceptedState = clientController ~= nil and clientController.getState() or reducerState
        if acceptedState ~= nil and acceptedState.phase == Core.PHASE.Active then
            Helpers.rememberNetworkLookApplied(character, networkLook)
            return true
        end
        return false
    end

    if protocolRevision == nil and Helpers.networkApplySuppressedForCharacter(characterId, character) then
        Helpers.debugLog("Ignored suppressed multiplayer wardrobe apply for characterId=" .. tostring(characterId) .. ".")
        return false
    end

    if Helpers.networkLookAlreadyApplied(character, networkLook, protocolLook) then
        return true
    end

    local networkVisibility = nil
    if protocolRevision ~= nil then
        networkVisibility = protocolLook ~= nil and
            protocolLook.attachmentVisibility or
            attachmentVisibilityFromLegacy(hairHidden == true)
    end
    local applied, diagnostics = Helpers.applyNetworkLook(character, networkLook, networkVisibility)
    if applied then
        Helpers.rememberNetworkLookApplied(character, networkLook, protocolLook)
    end
    return true
end

function Helpers.handleNetworkLookClear(characterId, protocolRevision, protocolLook)
    pendingNetworkAppliesByCharacterId[characterId] = nil
    local character = Helpers.findEntityById(characterId)
    if character == nil then
        Helpers.storePendingNetworkClear(characterId, protocolRevision, protocolLook)
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
            Helpers.tryClearVisualOverride(character)
        end
        lastOperation = "Look cleared from multiplayer sync."
        return true
    end
    Helpers.clearVisualOverride(character)
    local key = characterStateKey(character)
    if key ~= nil then
        lastAppliedNetworkLookSignatureByCharacterKey[key] = nil
    end
    return true
end

function Helpers.processPendingNetworkMessages()
    Helpers.pruneNetworkApplySuppressions()

    for characterId, pending in pairs(pendingNetworkClearsByCharacterId) do
        if globalTick - pending.receivedTick > PendingNetworkMessageMaxTicks then
            pendingNetworkClearsByCharacterId[characterId] = nil
        elseif Helpers.findEntityById(characterId) ~= nil then
            Helpers.handleNetworkLookClear(characterId, pending.protocolRevision, pending.protocolLook)
        end
    end

    for characterId, pending in pairs(pendingNetworkAppliesByCharacterId) do
        if globalTick - pending.receivedTick > PendingNetworkMessageMaxTicks then
            pendingNetworkAppliesByCharacterId[characterId] = nil
        elseif Helpers.findEntityById(characterId) ~= nil then
            Helpers.handleNetworkLookApply(
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
        if protocolMode == "probing" then Helpers.selectV1Protocol("received a v1 look update") end
        local characterId, networkLook = Helpers.readNetworkLook(message)
        Helpers.handleNetworkLookApply(characterId, networkLook)
    end)

    Networking.Receive(NET_LOOK_CLEAR, function(message)
        if protocolMode == "v2" then return end
        if protocolMode == "probing" then Helpers.selectV1Protocol("received a v1 clear update") end
        local characterId = message.ReadUInt16()
        Helpers.handleNetworkLookClear(characterId)
    end)

    if coreAvailable then
        Networking.Receive(NET_V2_HELLO, function(message)
            local ok, response, reason = pcall(Core.readServerHello, message)
            if not ok or response == nil then
                Helpers.debugLog("Ignored malformed v2 hello response: " .. tostring(ok and reason or response))
                return
            end
            Helpers.selectV2Protocol(response.revision, response.capabilities)
        end)

        Networking.Receive(NET_V2_ACK, function(message)
            local ack, reason = Core.tryReadAck(message)
            if ack == nil then
                Helpers.debugLog("Ignored malformed v2 acknowledgement: " .. tostring(reason))
                return
            end
            if protocolMode ~= "v2" then Helpers.selectV2Protocol(0) end

            local effects = dispatchReducer({
                type = "AckReceived",
                operationId = ack.operationId,
                accepted = ack.accepted,
                revision = ack.revision,
                reason = ack.reason
            })
            if effectsContain(effects, "IgnoredStaleAck") then
                Helpers.debugLog("Ignored stale v2 acknowledgement for " .. tostring(ack.operationId) .. ".")
            end

            if inFlightV2Command ~= nil and inFlightV2Command.operationId == ack.operationId then
                if not ack.accepted then
                    lastOperation = "Server rejected wardrobe command: " .. tostring(ack.reason or "unknown reason")
                    Helpers.debugLog(lastOperation)
                end
                if protocolCommandQueue[1] ~= nil and protocolCommandQueue[1].operationId == ack.operationId then
                    table.remove(protocolCommandQueue, 1)
                end
                inFlightV2Command = nil
                Helpers.sendNextProtocolCommand()
            end
        end)

        Networking.Receive(NET_V2_STATE, function(message)
            local state, reason = Core.tryReadState(message)
            if state == nil then
                Helpers.debugLog("Ignored malformed v2 wardrobe state: " .. tostring(reason))
                return
            end
            if protocolMode ~= "v2" then Helpers.selectV2Protocol(0) end

            local characterId = tonumber(state.characterId) or 0
            local character = Helpers.findEntityById(characterId)
            local controlledCharacter = controlled()
            local belongsToControlledCharacter =
                character ~= nil and controlledCharacter ~= nil and character == controlledCharacter

            -- A v2 server without the capability only understands the legacy
            -- boolean projection. Preserve this client's full four-layer policy
            -- when accepting its own authoritative equipment state.
            if belongsToControlledCharacter and
                not serverSupportsAttachmentVisibility() and
                state.look ~= nil then
                local localLook = clientController ~= nil and
                    clientController.getState().look or
                    currentDomainLook()
                if localLook ~= nil then
                    state.look.attachmentVisibility = copyAttachmentVisibility(
                        localLook.attachmentVisibility,
                        localLook.hideHair == true
                    )
                    state.look.hideHair =
                        legacyHideHairForVisibility(state.look.attachmentVisibility)
                end
            end

            if not belongsToControlledCharacter then
                local lastRevision = tonumber(remoteRevisionByCharacterId[characterId]) or -1
                if state.revision < lastRevision then
                    Helpers.debugLog(
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
                    Helpers.debugLog("Ignored invalid v2 state look: " .. tostring(reason))
                    return
                end
            end

            if state.active then
                Helpers.handleNetworkLookApply(
                    characterId,
                    legacyLook,
                    state.revision,
                    state.look.hideHair == true,
                    state.look
                )
            else
                Helpers.handleNetworkLookClear(characterId, state.revision, state.look)
            end
        end)
    end
end

function Helpers.clientLookStoragePath()
    local persistence = ensureWardrobePersistence()
    if persistence ~= nil then
        local ok, path = pcall(function()
            if isSinglePlayerClient() then
                return persistence.GetSinglePlayerProfilesPath()
            end
            return persistence.GetClientLookPath()
        end)
        if ok and path ~= nil and tostring(path) ~= "" then
            return tostring(path)
        end
    end
    return Helpers.clientPersistPath()
end

function Helpers.singlePlayerProfileLabel(character)
    if not isSinglePlayerClient() then return nil end
    local displayName = Helpers.singlePlayerCharacterDisplayName(character)
    local profileKey = Helpers.singlePlayerCharacterProfileKey(character)
    if profileKey ~= nil and singlePlayerAmbiguousFingerprints[profileKey] then
        return displayName .. " (" .. tr("status.profile_collision") .. ")"
    end
    if Helpers.currentSinglePlayerCampaignKey() == nil or profileKey == nil then
        return displayName .. " (" .. tr("status.profile_unavailable") .. ")"
    end
    return displayName
end

function Helpers.dumpDebugLog()
    local character = controlled()
    local overrideState = Helpers.visualOverrideState()
    local lines = {}
    local function emit(line)
        lines[#lines + 1] = tostring(line)
        Helpers.debugLog(line)
    end
    emit("---- wardrobe diagnostic dump begin ----")
    emit("lastOperation=" .. tostring(lastOperation))
    emit("savedLookCaptured=" .. tostring(savedLookCaptured) .. ", activeLook=" .. tostring(activeLook) .. ", autoApplyLook=" .. tostring(autoApplyLook))
    emit("sessionKey=" .. tostring(Helpers.currentSessionKey()))
    emit("singlePlayerProfile=" .. tostring(Helpers.singlePlayerProfileLabel(character)))
    emit("transferToUnconfiguredCharacter=" .. tostring(transferToUnconfiguredCharacter))
    emit("pendingSinglePlayerRestores=" .. tostring(next(pendingSinglePlayerRestores) ~= nil))
    emit("overrideLabel=" .. tostring(overrideState.label) .. ", overrideDetails=" .. tostring(overrideState.details))
    emit("persistence=" .. tostring(Helpers.clientLookStoragePath()))
    emit("character=" .. tostring(character) .. ", equipmentSignature=" .. tostring(character ~= nil and Helpers.equipmentSignature(character) or "no-character"))
    for _, entry in ipairs(slots) do
        local current = character ~= nil and getSlotItem(character, entry.slot) or nil
        local saved = savedLook[entry.key]
        emit(
            entry.key ..
            " currentIdentifier=" .. tostring(Helpers.itemIdentifier(current)) ..
            ", currentName=" .. tostring(Helpers.itemName(current)) ..
            ", currentId=" .. tostring(Helpers.itemEntityId(current)) ..
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
    local debugStatus = Helpers.visualOverrideDebugStatus(character)
    emit("visualOverrideCharacter=" .. tostring(debugStatus))
    emit("---- wardrobe diagnostic dump end ----")
    lastOperation = "Debug diagnostics dumped to LuaCs log."
end

function Helpers.removeWindow()
    if window ~= nil then
        pcall(function() window.Remove() end)
        window = nil
    end
end

function Helpers.clearWindow()
    Helpers.removeWindow()
    fullPanelOpen = false
    attachmentPanelOpen = false
    Helpers.resetOverlay()
end

function Helpers.refreshWindow()
    Helpers.removeWindow()
    if attachmentPanelOpen then
        buildAttachmentVisibilityWindow()
    else
        buildWindow()
    end
end

function Helpers.addText(parent, text)
    local block = GUI.TextBlock(GUI.RectTransform(Vector2(1.0, 0.0), parent.RectTransform), text)
    block.TextColor = Color.White
    return block
end

function Helpers.addButton(parent, text, action, refresh, enabled)
    local button = GUI.Button(GUI.RectTransform(Vector2(1.0, 0.08), parent.RectTransform), text)
    if enabled == false then
        pcall(function() button.Enabled = false end)
    end
    button.OnClicked = function()
        action()
        if refresh ~= false then
            Helpers.refreshWindow()
        end
        return true
    end
    return button
end

function Helpers.clientViewModelSnapshot(character, overrideState)
    local reducerView = clientController ~= nil and clientController.getViewModel() or {
        phase = "Legacy",
        hasSavedLook = Helpers.hasSavedLook(),
        active = activeLook == true,
        autoApply = autoApplyLook == true,
        canSave = character ~= nil,
        canApply = character ~= nil and Helpers.hasSavedLook(),
        canClear = character ~= nil,
        canForget = Helpers.hasSavedLook(),
        error = nil
    }
    local lookCopy = copyLookData(savedLook)
    local resultCopy = {}
    local currentNames = {}
    for _, entry in ipairs(slots) do
        resultCopy[entry.key] = slotResults[entry.key]
        currentNames[entry.key] = character ~= nil and Helpers.itemName(getSlotItem(character, entry.slot)) or "-"
    end
    local viewCaptured = savedLookCaptured == true
    local viewHideHair = hideHair == true
    local viewAttachmentVisibility =
        copyAttachmentVisibility(attachmentVisibility, hideHair)
    if coreAvailable then
        viewCaptured = reducerView.look ~= nil and reducerView.look.captured == true
        viewHideHair = reducerView.look ~= nil and reducerView.look.hideHair == true
        if reducerView.look ~= nil then
            viewAttachmentVisibility = copyAttachmentVisibility(
                reducerView.look.attachmentVisibility,
                reducerView.look.hideHair == true
            )
        end
    end
    return {
        phase = reducerView.phase,
        look = lookCopy,
        captured = viewCaptured,
        hideHair = viewHideHair,
        attachmentVisibility = viewAttachmentVisibility,
        canSetAttachmentVisibility =
            overrideState.ready and reducerView.hasSavedLook == true and reducerView.busy ~= true,
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
        singlePlayer = isSinglePlayerClient(),
        profileLabel = Helpers.singlePlayerProfileLabel(character),
        transferEnabled = transferToUnconfiguredCharacter == true,
        overrideLabel = tostring(overrideState.label),
        overrideDetails = overrideState.details
    }
end

local attachmentLayerDefinitions = {
    { key = "Hair", labelKey = "attachment.hair" },
    { key = "Beard", labelKey = "attachment.beard" },
    { key = "Moustache", labelKey = "attachment.moustache" },
    { key = "FaceAttachment", labelKey = "attachment.face" }
}

function Helpers.attachmentVisibilityLabel(value)
    if value == ATTACHMENT_VISIBILITY.Hide then return tr("visibility.hide") end
    if value == ATTACHMENT_VISIBILITY.Show then return tr("visibility.show") end
    return tr("visibility.auto")
end

function Helpers.nextAttachmentVisibility(value)
    if value == ATTACHMENT_VISIBILITY.Auto then return ATTACHMENT_VISIBILITY.Hide end
    if value == ATTACHMENT_VISIBILITY.Hide then return ATTACHMENT_VISIBILITY.Show end
    return ATTACHMENT_VISIBILITY.Auto
end

function Helpers.updateAttachmentVisibility(nextVisibility)
    local canonical, reason = validateAttachmentVisibility(nextVisibility, false)
    if canonical == nil then
        Helpers.log("Appearance-layer update failed: " .. tostring(reason))
        return false
    end
    local multiplayer = Helpers.isMultiplayerClient()
    local remote = multiplayer and serverSupportsAttachmentVisibility()
    dispatchReducer({
        type = "SetAttachmentVisibility",
        attachmentVisibility = canonical,
        remote = remote,
        operationId = remote and nextOperationId() or nil
    })
    local state = clientController ~= nil and clientController.getState() or reducerState
    if state ~= nil and state.phase == Core.PHASE.Faulted then
        Helpers.log("Appearance-layer update failed: " .. tostring(state.error))
        return false
    end
    if multiplayer and protocolMode == "probing" then
        visibilitySyncPendingNegotiation = true
    end
    lastOperation = remote and
        "Appearance-layer visibility update sent to the server." or
        "Appearance-layer visibility saved locally."
    return true
end

buildWindow = function()
    Helpers.removeWindow()
    windowNeedsRefresh = false
    attachmentPanelOpen = false

    local parent = Helpers.overlayParent()
    if parent == nil then
        Helpers.log("Overlay root is not ready.")
        return
    end

    local frame = GUI.Frame(GUI.RectTransform(Vector2(0.48, 0.74), parent, GUI.Anchor.Center), "GUIFrame")
    window = frame
    fullPanelOpen = true

    local list = GUI.LayoutGroup(GUI.RectTransform(Vector2(0.94, 0.94), frame.RectTransform, GUI.Anchor.Center), false)
    list.Stretch = true
    list.RelativeSpacing = 0.03

    local character = controlled()
    local overrideState = Helpers.visualOverrideState()
    local view = Helpers.clientViewModelSnapshot(character, overrideState)

    Helpers.addText(list, tr("panel.title"))
    Helpers.addText(list, view.overrideLabel)
    if view.singlePlayer then
        Helpers.addText(list, tr("panel.profile") .. ": " .. tostring(view.profileLabel))
        Helpers.addText(
            list,
            tr("panel.transfer") ..
            ": " ..
            (view.transferEnabled and tr("status.enabled") or tr("status.disabled"))
        )
    end
    Helpers.addText(list, tr("panel.saved_look") .. ": " .. Helpers.savedLookSummary(view.look, view.captured) .. " | " .. tr("panel.look") .. ": " .. (view.active and tr("panel.active") or tr("panel.inactive")))
    Helpers.addText(list, tr("panel.last") .. ": " .. localizedStatus(view.lastOperation))

    Helpers.addButton(list, tr("button.save"), function() Helpers.saveFashionAndUnequip() end, true, view.canSave)
    Helpers.addButton(list, tr("button.apply"), function() Helpers.applyFashionToCurrentEquipment(false) end, true, view.canApply)
    Helpers.addButton(list, tr("button.attachment_layers"), function()
        attachmentPanelOpen = true
        Helpers.removeWindow()
        buildAttachmentVisibilityWindow()
    end, false, view.canSetAttachmentVisibility)
    if view.singlePlayer then
        Helpers.addButton(
            list,
            view.transferEnabled and
                tr("button.disable_transfer") or
                tr("button.enable_transfer"),
            function()
                local saved, reason = Helpers.setSinglePlayerTransferSetting(not view.transferEnabled)
                if not saved then
                    Helpers.log("Appearance-transfer setting could not be saved: " .. tostring(reason))
                end
            end,
            true,
            true
        )
    end
    Helpers.addButton(list, tr("button.clear"), function() Helpers.clearActiveLook() end, true, view.canClear)
    Helpers.addButton(list, tr("button.forget"), function() Helpers.clearSavedLook() end, true, view.canForget)
    Helpers.addButton(list, view.diagnosticsVisible and tr("button.hide_diagnostics") or tr("button.diagnostics"), function()
        diagnosticsVisible = not diagnosticsVisible
    end)
    Helpers.addButton(list, tr("button.dump_debug"), function() Helpers.dumpDebugLog() end, true)
    Helpers.addText(list, tr("panel.debug_log_hint"))
    Helpers.addText(list, tr("panel.saved_file") .. ": " .. Helpers.clientLookStoragePath())
    Helpers.addButton(list, tr("button.close"), function() fullPanelOpen = false; Helpers.resetOverlay() end, false)

    for _, entry in ipairs(slots) do
        local currentItem = view.currentNames[entry.key]
        local result = localizedStatus(view.slotResults[entry.key] or "-")
        Helpers.addText(
            list,
            slotLabel(entry) .. " | " .. tr("panel.current") .. ": " .. currentItem .. " | " .. tr("panel.saved") .. ": " .. Helpers.itemName(view.look[entry.key]) .. " | " .. tr("panel.result") .. ": " .. result
        )
    end

    if view.diagnosticsVisible then
        Helpers.addText(list, tr("panel.diagnostics") .. ": " .. tostring(view.overrideDetails or tr("status.none")))
        local debugStatus = Helpers.visualOverrideDebugStatus(character)
        if debugStatus ~= nil then
            Helpers.addText(list, tr("panel.character") .. ": " .. debugStatus)
        end
    end
end

buildAttachmentVisibilityWindow = function()
    Helpers.removeWindow()
    windowNeedsRefresh = false
    attachmentPanelOpen = true
    fullPanelOpen = true

    local parent = Helpers.overlayParent()
    if parent == nil then
        Helpers.log("Overlay root is not ready.")
        return
    end

    local frame = GUI.Frame(
        GUI.RectTransform(Vector2(0.46, 0.68), parent, GUI.Anchor.Center),
        "GUIFrame"
    )
    window = frame
    local list = GUI.LayoutGroup(
        GUI.RectTransform(Vector2(0.92, 0.92), frame.RectTransform, GUI.Anchor.Center),
        false
    )
    list.Stretch = true
    list.RelativeSpacing = 0.035

    local character = controlled()
    local overrideState = Helpers.visualOverrideState()
    local view = Helpers.clientViewModelSnapshot(character, overrideState)
    Helpers.addText(list, tr("panel.attachment_layers"))
    Helpers.addText(list, tr("panel.attachment_help"))

    for _, layer in ipairs(attachmentLayerDefinitions) do
        local state = view.attachmentVisibility[layer.key]
        Helpers.addButton(
            list,
            tr(layer.labelKey) .. " — " .. Helpers.attachmentVisibilityLabel(state),
            function()
                local nextVisibility =
                    copyAttachmentVisibility(view.attachmentVisibility, false)
                nextVisibility[layer.key] = Helpers.nextAttachmentVisibility(state)
                Helpers.updateAttachmentVisibility(nextVisibility)
            end,
            true,
            view.canSetAttachmentVisibility
        )
    end

    Helpers.addButton(list, tr("button.hide_standard_hair"), function()
        Helpers.updateAttachmentVisibility({
            Hair = ATTACHMENT_VISIBILITY.Hide,
            Beard = ATTACHMENT_VISIBILITY.Hide,
            Moustache = ATTACHMENT_VISIBILITY.Hide,
            FaceAttachment = ATTACHMENT_VISIBILITY.Auto
        })
    end, true, view.canSetAttachmentVisibility)

    Helpers.addButton(list, tr("button.all_auto"), function()
        Helpers.updateAttachmentVisibility(attachmentVisibilityFromLegacy(false))
    end, true, view.canSetAttachmentVisibility)

    Helpers.addButton(list, tr("button.back"), function()
        attachmentPanelOpen = false
        Helpers.removeWindow()
        buildWindow()
    end, false, true)
    Helpers.addButton(list, tr("button.close"), function()
        fullPanelOpen = false
        attachmentPanelOpen = false
        Helpers.resetOverlay()
    end, false, true)
end

toggleWindow = function()
    if fullPanelOpen then
        fullPanelOpen = false
        Helpers.resetOverlay()
    else
        fullPanelOpen = true
        Helpers.resetOverlay()
        buildWindow()
    end
end

function Helpers.f8Hit()
    local ok, result = pcall(function()
        return PlayerInput.KeyHit(Keys.F8)
    end)
    return ok and result == true
end

tryCaptureEmptyVisualOverride = function(character)
    if Helpers.ensureVisualOverride() == nil or character == nil then
        return false, "visual override is unavailable"
    end
    local ok, result = pcall(function()
        return VisualOverride.CaptureEmptyFashion(character)
    end)
    if not ok then return false, tostring(result) end
    if result ~= true then return false, "renderer rejected the empty look" end
    return true
end

function Helpers.syncReducerCharacter(character)
    if not coreAvailable then return end
    local key = characterStateKey(character)
    if key == nil then
        if reducerCharacterKey ~= nil then
            if not isSinglePlayerClient() then
                dispatchReducer({ type = "CharacterLost" })
            end
            reducerCharacterKey = nil
        end
        return
    end
    if key ~= reducerCharacterKey then
        reducerCharacterKey = key
        suppressControlledCharacterStateSync = true
        dispatchReducer({ type = "CharacterReady", characterKey = key })
        syncReducerLook()
        suppressControlledCharacterStateSync = false
    end
end

function Helpers.resetSavedLookForNewSession()
    Helpers.clearAllVisualOverrides()
    savedLook = {}
    savedLookCaptured = false
    activeLook = false
    autoApplyLook = false
    hideHair = false
    attachmentVisibility = attachmentVisibilityFromLegacy(false)
    characterStates = {}
    slotResults = {}
    lastNetworkApplyDiagnostics = {}
    lastEquipmentSignature = nil
    lastServerAutoApplySignature = nil
    Helpers.clearPendingServerApplyRequest()
    pendingRoundStartNetworkLook = nil
    pendingRoundStartNetworkCharacterKey = nil
    pendingRoundStartNetworkRevision = nil
    pendingRoundStartHideHair = false
    pendingRoundStartAttachmentVisibility = nil
    pendingNetworkAppliesByCharacterId = {}
    pendingNetworkClearsByCharacterId = {}
    pendingSinglePlayerRestores = {}
    singlePlayerFingerprintOwners = {}
    singlePlayerCharactersByRuntimeKey = {}
    singlePlayerAmbiguousFingerprints = {}
    singlePlayerRoundScanned = false
    pendingSinglePlayerTransferSourceKey = nil
    singlePlayerProfileLoadAttempts = {}
    lastAppliedNetworkLookSignatureByCharacterKey = {}
    suppressedNetworkAppliesByCharacterKey = {}
    remoteRevisionByCharacterId = {}
    protocolMode = coreAvailable and "probing" or "v1"
    serverCapabilities = 0
    visibilitySyncPendingNegotiation = false
    protocolHelloSentAt = nil
    protocolCommandQueue = {}
    inFlightV2Command = nil
    protocolOperationCounter = 0
    clientSessionId = createClientSessionId()
    reducerCharacterKey = nil
    reducerState = coreAvailable and Core.newClientState({
        clientSessionId = clientSessionId,
        sessionKey = Helpers.currentSessionKey()
    }) or nil
    clientController = createClientController(reducerState)
    persistentClientLookLoaded = false
    lastOperation = "Ready."
end

function Helpers.handleSessionChange()
    local sessionKey = Helpers.currentSessionKey()
    if sessionKey == nil then return end
    if lastSessionKey == nil then
        lastSessionKey = sessionKey
        return
    end
    if sessionKey == lastSessionKey then return end

    lastSessionKey = sessionKey
    Helpers.resetSavedLookForNewSession()
    Helpers.debugLog("Detected a new game session; cleared in-memory saved wardrobe look.")
end

Hook.Add("think", "barowardrobeswitcher.panel", function()
    globalTick = globalTick + 1

    Helpers.handleSessionChange()
    if isSinglePlayerClient() then
        Helpers.loadSinglePlayerTransferSetting()
        if not singlePlayerRoundScanned and Helpers.currentSessionRunning() then
            Helpers.scanSinglePlayerCrewForRestores()
        end
        Helpers.processPendingSinglePlayerRestores()
    elseif not persistentClientLookLoaded then
        Helpers.loadPersistentClientLook()
    end
    Helpers.processPendingNetworkMessages()
    Helpers.processProtocolNegotiation()

    if Helpers.f8Hit() then
        toggleWindow()
    end

    local character = controlled()
    Helpers.syncReducerCharacter(character)
    if character == nil then
        Helpers.handleNoControlledCharacter()
        if fullPanelOpen and (window == nil or windowNeedsRefresh) then
            if attachmentPanelOpen then buildAttachmentVisibilityWindow() else buildWindow() end
        end
        if fullPanelOpen then
            Helpers.drawOverlay()
        end
        return
    end

    Helpers.sendRoundStartNotice()

    Helpers.handleControlledCharacterChange(character)
    lastCharacter = character
    if initialEquipGateActive and not Helpers.initialEquipGateReady(character) then
        -- Wait until Barotrauma has finished its own initial equipment burst.
    else
        Helpers.applyPendingRoundStartNetworkLook(character)
        Helpers.autoApplySavedLookIfNeeded(character)
        Helpers.refreshActiveLookIfNeeded(character)
    end

    if fullPanelOpen and (window == nil or windowNeedsRefresh) then
        if attachmentPanelOpen then buildAttachmentVisibilityWindow() else buildWindow() end
    end
    if fullPanelOpen then
        Helpers.drawOverlay()
    end

end)

Hook.Add("roundStart", "barowardrobeswitcher.notice", function()
    Helpers.startInitialEquipGate()
    if isSinglePlayerClient() then
        pendingSinglePlayerRestores = {}
        singlePlayerRoundScanned = false
        Helpers.scanSinglePlayerCrewForRestores()
    end
    if Helpers.hasSavedLook() and autoApplyLook then
        dispatchReducer({ type = "Deactivate" })
        lastEquipmentSignature = nil
        lastServerAutoApplySignature = nil
        Helpers.clearPendingServerApplyRequest()
    end
    Helpers.sendRoundStartNotice()
end)

Hook.Add("item.equip", "barowardrobeswitcher.initial-equip", function(item, character)
    Helpers.noteSinglePlayerEquipmentChange(character)
    if not initialEquipGateActive or character == nil then return end
    local controlledCharacter = controlled()
    if controlledCharacter == nil or character ~= controlledCharacter then return end
    initialEquipGateSeenEquip = true
    initialEquipGateLastEquipTick = globalTick
    initialEquipGateStableTicks = 0
end)

Hook.Add("item.unequip", "barowardrobeswitcher.profile-equip", function(item, character)
    Helpers.noteSinglePlayerEquipmentChange(character)
end)

Hook.Add("character.created", "barowardrobeswitcher.profile-character-created", function(character)
    if not isSinglePlayerClient() then return end
    local attempts = 0
    local function attemptQueue()
        attempts = attempts + 1
        if Helpers.singlePlayerCharacterEligible(character) then
            Helpers.registerSinglePlayerCharacter(character)
            Helpers.queueSinglePlayerProfileRestore(character)
            return
        end
        if attempts < 3 and Timer ~= nil and Timer.Wait ~= nil then
            Timer.Wait(attemptQueue, attempts == 1 and 100 or 500)
        end
    end
    attemptQueue()
end)

Hook.Add("roundEnd", "barowardrobeswitcher.cleanup", function()
    if lastCharacter ~= nil then
        saveCharacterState(lastCharacter)
    end
    local preservedForNextScene = Helpers.preserveSceneTransitionLookIntent()
    Helpers.resetInitialEquipGate()
    pendingRoundStartNetworkLook = nil
    pendingRoundStartNetworkCharacterKey = nil
    pendingRoundStartNetworkRevision = nil
    pendingRoundStartHideHair = false
    pendingNetworkAppliesByCharacterId = {}
    pendingNetworkClearsByCharacterId = {}
    pendingSinglePlayerRestores = {}
    singlePlayerFingerprintOwners = {}
    singlePlayerCharactersByRuntimeKey = {}
    singlePlayerAmbiguousFingerprints = {}
    singlePlayerRoundScanned = false
    pendingSinglePlayerTransferSourceKey = nil
    lastAppliedNetworkLookSignatureByCharacterKey = {}
    suppressedNetworkAppliesByCharacterKey = {}
    remoteRevisionByCharacterId = {}
    fullPanelOpen = false
    Helpers.resetOverlay()
    slotResults = {}
    lastNetworkApplyDiagnostics = {}
    diagnosticsVisible = false
    lastServerAutoApplySignature = nil
    Helpers.clearPendingServerApplyRequest()
    lastEquipmentSignature = nil
    Helpers.clearAllVisualOverrides()
    lastCharacter = nil
    roundStartNoticeSent = false
    if preservedForNextScene then
        lastOperation = "Saved look will be reapplied in the next scene."
    else
        lastOperation = Helpers.hasSavedLook() and "Saved look needs to be applied again." or "Round ended."
    end
end)

Helpers.log("Loaded. Press F8 to open the wardrobe panel.")
