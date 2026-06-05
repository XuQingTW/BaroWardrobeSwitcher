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
        ["button.save"] = "Save Current Outfit",
        ["button.apply"] = "Apply Saved Look",
        ["button.clear"] = "Clear Look",
        ["button.diagnostics"] = "Diagnostics",
        ["button.hide_diagnostics"] = "Hide Diagnostics",
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
        ["status.multiplayer_sync_failed"] = "Multiplayer wardrobe sync failed; make sure every client has the fashion items and C# scripting enabled.",
        ["status.still_equipped_in"] = "Still equipped in ",
        ["status.look_cleared_sync"] = "Look cleared from multiplayer sync.",
        ["status.round_ended"] = "Round ended. Saved look cleared.",
        ["status.refreshed"] = "Saved look refreshed for changed equipment.",
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
        ["button.save"] = "保存当前服装",
        ["button.apply"] = "套用已保存外观",
        ["button.clear"] = "清除外观",
        ["button.diagnostics"] = "诊断",
        ["button.hide_diagnostics"] = "隐藏诊断",
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
        ["status.multiplayer_sync_failed"] = "多人衣柜同步失败；请确认每位客户端都有这些时装物品并已启用 C# 脚本。",
        ["status.still_equipped_in"] = "仍装备于 ",
        ["status.look_cleared_sync"] = "外观已由多人同步清除。",
        ["status.round_ended"] = "回合结束。已清除保存的外观。",
        ["status.refreshed"] = "装备改变，已刷新保存的外观。",
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
        ["button.save"] = "儲存目前服裝",
        ["button.apply"] = "套用已儲存外觀",
        ["button.clear"] = "清除外觀",
        ["button.diagnostics"] = "診斷",
        ["button.hide_diagnostics"] = "隱藏診斷",
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
        ["status.multiplayer_sync_failed"] = "多人衣櫃同步失敗；請確認每位客戶端都有這些時裝物品並已啟用 C# 腳本。",
        ["status.still_equipped_in"] = "仍裝備於 ",
        ["status.look_cleared_sync"] = "外觀已由多人同步清除。",
        ["status.round_ended"] = "回合結束。已清除儲存的外觀。",
        ["status.refreshed"] = "裝備改變，已重新套用儲存外觀。",
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
    ["Multiplayer wardrobe sync failed; make sure every client has the fashion items and C# scripting enabled."] = "status.multiplayer_sync_failed",
    ["Look cleared from multiplayer sync."] = "status.look_cleared_sync",
    ["Round ended. Saved look cleared."] = "status.round_ended",
    ["Saved look refreshed for changed equipment."] = "status.refreshed",
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
local lastOperation = "Ready."
local diagnosticsVisible = false
local lastEquipmentSignature = nil
local slotResults = {}
local window = nil
local overlayRoot = nil
local lastCharacter = nil
local buildWindow
local toggleWindow
local fullPanelOpen = false
local unequipItem
local isInSlot
local roundStartNoticeSent = false

local function log(message)
    local line = "[" .. MOD_NAME .. "] " .. tostring(message)
    lastOperation = tostring(message)
    if LuaCsLogger ~= nil and LuaCsLogger.Log ~= nil then
        LuaCsLogger.Log(line)
    else
        print(line)
    end
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
    if savedLookCaptured then return true end
    for _, entry in ipairs(slots) do
        if savedLook[entry.key] ~= nil then return true end
    end
    return false
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

local function getSlotItem(character, slot)
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

local function isInAnyWearableSlot(character, item)
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

local function captureEmptyVisualOverride(character)
    if ensureVisualOverride() == nil or character == nil then return false end
    local ok, result = pcall(function()
        return VisualOverride.CaptureEmptyFashion(character)
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

local function applyCapturedFashionToCharacterEquipment(character)
    if character == nil then return false, 0 end

    restoreItemVisuals(character)

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
    if character == nil or networkLook == nil then return false end
    if visualOverrideStatus() ~= nil then return false end

    clearVisualOverride(character)

    local expectedItems = 0
    local capturedItems = 0
    for _, entry in ipairs(slots) do
        local data = networkLook[entry.key]
        if data ~= nil and data.itemId ~= nil and data.itemId > 0 then
            expectedItems = expectedItems + 1
            local item = findEntityById(data.itemId)
            if item ~= nil then
                captureVisualOverride(character, item)
                capturedItems = capturedItems + 1
            end
        end
    end

    if expectedItems == 0 then
        captureEmptyVisualOverride(character)
    elseif capturedItems == 0 then
        return false
    end

    local activated = applyCapturedFashionToCharacterEquipment(character)
    return activated == true
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
        if not silent then log("Requested multiplayer wardrobe apply from the server.") end
        return true
    end

    local activated, visualItems = applyCapturedFashionToCharacterEquipment(character)

    lastCharacter = character
    activeLook = activated == true
    lastEquipmentSignature = equipmentSignature(character)

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
    lastEquipmentSignature = nil
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
    else
        activeLook = false
        lastEquipmentSignature = nil
        lastOperation = "Saved look needs to be applied again."
    end
end

local function handleControlledCharacterChange(character)
    if lastCharacter == nil or character == lastCharacter then return end
    restoreItemVisuals(lastCharacter)
    clearVisualOverride(lastCharacter)
    activeLook = false
    savedLook = {}
    savedLookCaptured = false
    slotResults = {}
    lastEquipmentSignature = nil
    lastOperation = "Controlled character changed. Save a new outfit for this character."
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
    slotResults = {}
    lastEquipmentSignature = nil
    log("Saved look cleared.")
end

if Networking ~= nil then
    Networking.Receive(NET_LOOK_APPLY, function(message)
        local characterId, networkLook = readNetworkLook(message)
        local character = findEntityById(characterId)
        if character == nil then return end

        local applied = applyNetworkLook(character, networkLook)
        if character == controlled() then
            savedLook = networkLook
            savedLookCaptured = true
            activeLook = applied == true
            lastCharacter = character
            lastEquipmentSignature = equipmentSignature(character)
            slotResults = {}
            for _, entry in ipairs(slots) do
                slotResults[entry.key] = networkLook[entry.key] ~= nil and "Synced from server" or "Empty"
            end
            if applied then
                lastOperation = "Saved look applied from multiplayer sync."
            else
                lastOperation = "Multiplayer wardrobe sync failed; make sure every client has the fashion items and C# scripting enabled."
            end
        end
    end)

    Networking.Receive(NET_LOOK_CLEAR, function(message)
        local characterId = message.ReadUInt16()
        local character = findEntityById(characterId)
        if character == nil then return end

        clearVisualOverride(character)
        if character == controlled() then
            activeLook = false
            lastEquipmentSignature = nil
            lastOperation = "Look cleared from multiplayer sync."
        end
    end)
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
    addButton(list, diagnosticsVisible and tr("button.hide_diagnostics") or tr("button.diagnostics"), function()
        diagnosticsVisible = not diagnosticsVisible
    end)
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

Hook.Add("think", "barowardrobeswitcher.panel", function()
    if f8Hit() then
        toggleWindow()
    end

    local character = controlled()
    if character == nil then
        if lastCharacter ~= nil and activeLook then
            restoreItemVisuals(lastCharacter)
        end
        activeLook = false
        lastEquipmentSignature = nil
        lastCharacter = nil
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
    refreshActiveLookIfNeeded(character)

    if fullPanelOpen and window == nil then
        buildWindow()
    end
    if fullPanelOpen then
        drawOverlay()
    end

end)

Hook.Add("roundStart", "barowardrobeswitcher.notice", function()
    sendRoundStartNotice()
end)

Hook.Add("roundEnd", "barowardrobeswitcher.cleanup", function()
    fullPanelOpen = false
    resetOverlay()
    savedLook = {}
    savedLookCaptured = false
    slotResults = {}
    activeLook = false
    diagnosticsVisible = false
    lastEquipmentSignature = nil
    clearAllVisualOverrides()
    lastCharacter = nil
    roundStartNoticeSent = false
    lastOperation = "Round ended. Saved look cleared."
end)

log("Loaded. Press F8 to open the wardrobe panel.")
