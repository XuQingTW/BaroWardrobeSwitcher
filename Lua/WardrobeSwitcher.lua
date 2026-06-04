local MOD_NAME = "Baro Wardrobe Switcher"

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
local VisualOverride = nil
local visualOverrideFailure = nil
local visualOverrideDiagnostics = nil

local slots = {
    { key = "Head", label = "Head", slot = InvSlotType.Head },
    { key = "Headset", label = "Headset", slot = InvSlotType.Headset },
    { key = "InnerClothes", label = "Inner", slot = InvSlotType.InnerClothes },
    { key = "OuterClothes", label = "Outer", slot = InvSlotType.OuterClothes },
    { key = "Bag", label = "Bag", slot = InvSlotType.Bag },
    { key = "HealthInterface", label = "Health", slot = InvSlotType.HealthInterface }
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
    addChatLine("Wardrobe control panel can be opened by pressing F8.")
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
    if not hasSavedLook() then return "none" end
    local count = 0
    for _, entry in ipairs(slots) do
        if savedLook[entry.key] ~= nil then
            count = count + 1
        end
    end
    if count == 0 then return "empty outfit" end
    return tostring(count) .. " slot" .. (count == 1 and "" or "s")
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
            labels[#labels + 1] = entry.label
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
        data[entry.key] = getSlotItem(character, entry.slot)
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
        if item ~= nil then
            data[entry.key] = {
                identifier = itemIdentifier(item),
                name = itemName(item),
                slot = entry.key
            }
        else
            data[entry.key] = nil
        end
    end
    return data
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
    for _, entry in ipairs(slots) do
        local item = startingItems[entry.key]
        if item ~= nil then
            startingItemCount = startingItemCount + 1
            if processedItems[item] then
                slotResults[entry.key] = "Already handled"
            else
                processedItems[item] = true
                capturedSprites = capturedSprites + captureVisualOverride(character, item)
                unequipItem(character, item)
                local remainingSlots = wornSlotLabelsForItem(character, item)
                if #remainingSlots > 0 then
                    local result = "Still equipped in " .. table.concat(remainingSlots, ", ")
                    slotResults[entry.key] = result
                    failedItems[#failedItems + 1] = entry.label .. ": " .. itemName(item) .. " (" .. table.concat(remainingSlots, ", ") .. ")"
                else
                    removedItems = removedItems + 1
                    slotResults[entry.key] = "Saved and removed"
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
        message = message ..
            tostring(capturedSprites) ..
            " wearable sprites captured, " ..
            tostring(removedItems) ..
            " item" .. (removedItems == 1 and "" or "s") .. " removed."
        if capturedSprites <= 0 then
            message = message .. " Saved as an empty visual look."
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
    local activated = activateFashionVisual(character)

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
    if character ~= nil then
        restoreItemVisuals(character)
    end
    activeLook = false
    lastEquipmentSignature = nil
    log("Look cleared. Real equipment visuals restored.")
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

    addText(list, "Wardrobe Switcher")
    addText(list, overrideState.label)
    addText(list, "Saved look: " .. savedLookSummary() .. " | Look: " .. (activeLook and "active" or "inactive"))
    addText(list, "Last: " .. lastOperation)

    addButton(list, "Save Current Outfit", function() saveFashionAndUnequip() end, true, overrideState.ready)
    addButton(list, "Apply Saved Look", function() applyFashionToCurrentEquipment(false) end, true, canApply)
    addButton(list, "Clear Look", function() clearActiveLook() end)
    addButton(list, diagnosticsVisible and "Hide Diagnostics" or "Diagnostics", function()
        diagnosticsVisible = not diagnosticsVisible
    end)
    addButton(list, "Close", function() fullPanelOpen = false; resetOverlay() end, false)

    for _, entry in ipairs(slots) do
        local currentItem = "-"
        if character ~= nil then
            currentItem = itemName(getSlotItem(character, entry.slot))
        end
        local result = slotResults[entry.key] or "-"
        addText(
            list,
            entry.label .. " | Current: " .. currentItem .. " | Saved: " .. itemName(savedLook[entry.key]) .. " | Result: " .. result
        )
    end

    if diagnosticsVisible then
        addText(list, "Diagnostics: " .. tostring(overrideState.details or "none"))
        local debugStatus = visualOverrideDebugStatus(character)
        if debugStatus ~= nil then
            addText(list, "Character: " .. debugStatus)
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
