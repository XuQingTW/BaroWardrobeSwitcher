# Lua 純資料、協定與狀態機

[返回程式導覽](../CODEMAP.md)

共 69 個具名函式／方法，包含建構函式、區域函式、多載及 adapter。

用途按目前原碼整理；簽章保留參數名稱，定位列為檔案內的定義起始行。呼叫欄僅列索引內的部分直接呼叫，方便追查，不代表完整執行期呼叫圖。

## WardrobeCore.lua

來源：[Lua/WardrobeCore.lua](../../Lua/WardrobeCore.lua)

| 函式／方法（含參數） | 用途 | 相關呼叫 | 定位 |
|---|---|---|---|
| `local function shallowCopy(source)` | 複製表格第一層，避免直接修改傳入的狀態表。 | — | [L130](../../Lua/WardrobeCore.lua#L130) |
| `local function checkBoundedString(value, field, maximum, allowEmpty)` | 驗證文字型別、空值政策及位元組長度上限。 | — | [L138](../../Lua/WardrobeCore.lua#L138) |
| `local function normalizeUInt32(value, field)` | 驗證並正規化無號 32 位整數，拒絕小數及超出範圍的值。 | — | [L151](../../Lua/WardrobeCore.lua#L151) |
| `local function rawSlotIdentifier(value)` | 從字串或舊版欄位物件取得物品識別碼。 | — | [L160](../../Lua/WardrobeCore.lua#L160) |
| `local function rawSlotColor(value, colors, key)` | 從欄位或色彩表取得保存的 UInt32 色彩。 | — | [L168](../../Lua/WardrobeCore.lua#L168) |
| `function Core.attachmentVisibilityFromLegacy(hideHair)` | 由舊版 hideHair 建立四種附件的預設可見性表。 | — | [L174](../../Lua/WardrobeCore.lua#L174) |
| `function Core.validateAttachmentVisibility(value, legacyHideHair)` | 驗證附件政策的欄位、狀態值及舊版相容輸入。 | `Core.attachmentVisibilityFromLegacy` | [L184](../../Lua/WardrobeCore.lua#L184) |
| `function Core.legacyHideHair(value)` | Lua 橋接：把目前附件政策投影成舊版隱藏頭髮值。 | `Core.validateAttachmentVisibility` | [L211](../../Lua/WardrobeCore.lua#L211) |
| `function Core.attachmentVisibilityMasks(value)` | 將 auto／hide／show 政策編成兩組強制隱藏及顯示位元。 | `Core.validateAttachmentVisibility` | [L219](../../Lua/WardrobeCore.lua#L219) |
| `function Core.attachmentVisibilityFromMasks(forceHide, forceShow)` | 驗證位元遮罩後還原附件政策，拒絕未知或互相重疊的位元。 | — | [L234](../../Lua/WardrobeCore.lua#L234) |
| `local function messageRemainingBits(message)` | 安全查詢網路訊息剩餘位元數，區分缺少尾段與截斷資料。 | — | [L262](../../Lua/WardrobeCore.lua#L262) |
| `function Core.validateLook(value)` | 驗證外觀 schema、欄位、識別碼、色彩、附件政策及資料大小，回傳標準外觀或原因。 | `rawSlotIdentifier`、`rawSlotColor`、`checkBoundedString`、`normalizeUInt32`、`Core.validateAttachmentVisibility`、`Core.legacyHideHair` | [L288](../../Lua/WardrobeCore.lua#L288) |
| `function Core.newLook( captured, hideHair, slots, attachmentVisibility, colors, useFashionMovementAnimations, useFashionFootstepSounds)` | 由輸入建立經驗證的標準外觀資料。 | `Core.validateLook` | [L380](../../Lua/WardrobeCore.lua#L380) |
| `local function copyLook(look)` | 複製已驗證的內部外觀，分離欄位、顏色與附件子表。 | `shallowCopy` | [L401](../../Lua/WardrobeCore.lua#L401) |
| `function Core.copyLook(look)` | 複製標準外觀及其可變子表。 | `Core.validateLook` | [L410](../../Lua/WardrobeCore.lua#L410) |
| `function Core.fromLegacyLook( legacyLook, captured, hideHair, attachmentVisibility, useFashionMovementAnimations, useFashionFootstepSounds)` | 將舊版欄位表及偏好轉成標準外觀 schema。 | `Core.validateLook` | [L417](../../Lua/WardrobeCore.lua#L417) |
| `function Core.toLegacyLook(look)` | 把標準外觀投影回既有客戶端欄位格式。 | `Core.validateLook` | [L435](../../Lua/WardrobeCore.lua#L435) |
| `local function decodePersistentValue(value)` | 還原持久化字串中的跳脫值。 | — | [L454](../../Lua/WardrobeCore.lua#L454) |
| `function Core.parseLegacyClientLookLine(line)` | 解析舊版單行外觀存檔，驗證並轉成目前外觀資料。 | `booleanValue`、`decodePersistentValue`、`normalizeUInt32`、`Core.fromLegacyLook`、`Core.hasLook` | [L464](../../Lua/WardrobeCore.lua#L464) |
| `local function booleanValue(name, value)` | 把舊格式值投影為相容布林值。 | — | [L482](../../Lua/WardrobeCore.lua#L482) |
| `local function hasLook(look)` | 判斷已驗證的內部外觀是否包含保存意圖。 | — | [L578](../../Lua/WardrobeCore.lua#L578) |
| `function Core.hasLook(look)` | 判斷資料是否表示已保存的外觀，包含合法空外觀。 | `Core.validateLook` | [L571](../../Lua/WardrobeCore.lua#L571) |
| `function Core.lookSignature(look)` | 將外觀內容與偏好編成穩定簽章，供去重及變更判斷。 | `Core.validateLook` | [L591](../../Lua/WardrobeCore.lua#L591) |
| `function Core.lookEquals(left, right)` | 比較外觀簽章；同一物件仍驗證一次，非法物件不因參照相同而通過。 | `Core.lookSignature` | [L611](../../Lua/WardrobeCore.lua#L611) |
| `function Core.writeLook(message, look)` | 依協定順序寫入外觀欄位、色彩及相容擴充尾段。 | `Core.validateLook`、`Core.attachmentVisibilityMasks` | [L619](../../Lua/WardrobeCore.lua#L619) |
| `function Core.readLook(message)` | 依協定解析並驗證外觀；處理缺少或完整擴充尾段，拒絕截斷資料。 | `ReadBoolean`、`messageRemainingBits`、`Core.attachmentVisibilityFromMasks`、`Core.validateLook` | [L652](../../Lua/WardrobeCore.lua#L652) |
| `function Core.writeClientHello(message, clientSessionId)` | 寫入客戶端協定版本、session 身分及可用能力。 | `checkBoundedString` | [L734](../../Lua/WardrobeCore.lua#L734) |
| `function Core.readClientHello(message)` | 解析並驗證客戶端握手資料。 | `checkBoundedString` | [L747](../../Lua/WardrobeCore.lua#L747) |
| `function Core.writeServerHello(message, revision, capabilities)` | 寫入伺服器協定版本、session、修訂號及能力。 | `normalizeUInt32` | [L763](../../Lua/WardrobeCore.lua#L763) |
| `function Core.readServerHello(message)` | 解析並驗證伺服器握手資料。 | `messageRemainingBits` | [L779](../../Lua/WardrobeCore.lua#L779) |
| `function Core.validateCommand(command)` | 驗證命令種類、操作 ID、修訂號及附帶的外觀資料。 | `checkBoundedString`、`normalizeUInt32`、`Core.validateLook` | [L807](../../Lua/WardrobeCore.lua#L807) |
| `function Core.writeCommand(message, command)` | 序列化目前版本的衣櫃命令。 | `Core.validateCommand`、`Core.writeLook` | [L862](../../Lua/WardrobeCore.lua#L862) |
| `function Core.readCommand(message)` | 解析並驗證衣櫃命令，拒絕不支援的格式。 | `ReadBoolean`、`Core.readLook`、`Core.validateCommand` | [L877](../../Lua/WardrobeCore.lua#L877) |
| `function Core.writeTargetCommand(message, command)` | 將一般命令加上目標船員 entity ID 後寫入。 | `Core.validateCommand`、`Core.writeLook` | [L897](../../Lua/WardrobeCore.lua#L897) |
| `function Core.readTargetCommand(message)` | 解析船員目標及命令本體，驗證目標命令封包。 | `ReadBoolean`、`Core.readLook`、`Core.validateCommand` | [L916](../../Lua/WardrobeCore.lua#L916) |
| `function Core.writeState(message, state)` | 寫入角色外觀、啟用狀態與修訂號，供伺服器同步。 | `normalizeUInt32`、`Core.validateLook`、`Core.writeLook` | [L937](../../Lua/WardrobeCore.lua#L937) |
| `function Core.readState(message)` | 解析並驗證伺服器外觀狀態。 | `ReadBoolean`、`Core.readLook` | [L961](../../Lua/WardrobeCore.lua#L961) |
| `function Core.tryReadState(message)` | 以受保護呼叫解析狀態，將解析例外轉成失敗結果。 | — | [L983](../../Lua/WardrobeCore.lua#L983) |
| `function Core.validateDivingProfile(profile)` | 驗證潛水模式、自訂外觀與角色目標資料。 | `Core.validateLook` | [L989](../../Lua/WardrobeCore.lua#L989) |
| `function Core.writeDivingProfile(message, profile)` | 將潛水外觀設定序列化至訊息。 | `Core.validateDivingProfile`、`Core.writeLook` | [L1022](../../Lua/WardrobeCore.lua#L1022) |
| `function Core.readDivingProfile(message)` | 讀取並驗證潛水外觀設定。 | `ReadBoolean`、`Core.readLook`、`Core.validateDivingProfile` | [L1033](../../Lua/WardrobeCore.lua#L1033) |
| `function Core.tryReadDivingProfile(message)` | 受保護地讀取潛水設定，回傳結果或錯誤。 | — | [L1051](../../Lua/WardrobeCore.lua#L1051) |
| `function Core.writeAck(message, ack)` | 寫入操作確認、接受與否、修訂號及錯誤原因。 | `checkBoundedString`、`normalizeUInt32` | [L1057](../../Lua/WardrobeCore.lua#L1057) |
| `function Core.readAck(message)` | 解析並驗證操作確認訊息。 | `ReadBoolean`、`checkBoundedString` | [L1085](../../Lua/WardrobeCore.lua#L1085) |
| `function Core.tryReadAck(message)` | 受保護地讀取確認訊息，避免格式錯誤中斷接收流程。 | — | [L1112](../../Lua/WardrobeCore.lua#L1112) |
| `local function copyClientState(state)` | 複製 reducer 狀態與需要獨立保存的子表。 | `shallowCopy`、`copyLook` | [L1118](../../Lua/WardrobeCore.lua#L1118) |
| `local function effect(kind, values)` | 建立具種類及負載的副作用描述，不直接操作遊戲。 | `shallowCopy` | [L1125](../../Lua/WardrobeCore.lua#L1125) |
| `local function attachmentVisibilityEffect(kind, look)` | 建立附件可見性變更的副作用描述。 | `effect`、`Core.validateAttachmentVisibility`、`Core.attachmentVisibilityFromLegacy` | [L1131](../../Lua/WardrobeCore.lua#L1131) |
| `local function movementAnimationEffect(kind, look)` | 建立移動動畫來源變更的副作用描述。 | `effect` | [L1139](../../Lua/WardrobeCore.lua#L1139) |
| `local function footstepSoundEffect(kind, look)` | 建立腳步音效來源變更的副作用描述。 | `effect` | [L1146](../../Lua/WardrobeCore.lua#L1146) |
| `function Core.newClientState(options)` | 建立客戶端 reducer 的初始狀態及預設外觀偏好。 | `Core.copyLook`、`Core.hasLook` | [L1153](../../Lua/WardrobeCore.lua#L1153) |
| `local function clearPending(state)` | 清除目前待確認的命令與操作資訊。 | — | [L1185](../../Lua/WardrobeCore.lua#L1185) |
| `local function clearRollback(state)` | 清除先前保存的回滾快照。 | — | [L1192](../../Lua/WardrobeCore.lua#L1192) |
| `local function beginRollback(state)` | 在操作開始前保存外觀及啟用狀態，供失敗還原。 | `copyLook` | [L1198](../../Lua/WardrobeCore.lua#L1198) |
| `local function restoreRollback(state)` | 把操作前快照還原至 reducer 狀態。 | `copyLook`、`hasLook`、`clearPending`、`clearRollback` | [L1204](../../Lua/WardrobeCore.lua#L1204) |
| `local function restoreSettingRollback(state, effects, compensate)` | 還原附件、移動動畫或腳步音效設定，必要時補送對應外觀效果。 | `copyLook`、`restoreRollback`、`attachmentVisibilityEffect`、`movementAnimationEffect`、`footstepSoundEffect` | [L1221](../../Lua/WardrobeCore.lua#L1221) |
| `local function cancelPendingForLifecycle(state)` | 角色或場景生命週期改變時取消待處理命令及回滾資訊。 | `restoreRollback`、`clearPending`、`clearRollback` | [L1239](../../Lua/WardrobeCore.lua#L1239) |
| `local function commandPending(state, event, phase)` | 把操作標成等待命令結果，填入操作 ID、種類及修訂號。 | — | [L1248](../../Lua/WardrobeCore.lua#L1248) |
| `function Core.reduce(currentState, event)` | 處理事件並產生新狀態與副作用列表；集中管理保存、套用、確認、失敗回滾及生命週期。 | `copyClientState`、`shallowCopy`、`Core.attachmentVisibilityFromLegacy`、`cancelPendingForLifecycle`、`hasLook`、`effect`、`clearPending`、`clearRollback` 等 | [L1263](../../Lua/WardrobeCore.lua#L1263) |
| `function Core.clientViewModel(state)` | 由 reducer 狀態產生按鈕可用性、忙碌及顯示狀態，不讀寫遊戲實體。 | `Core.copyLook`、`Core.hasLook` | [L2048](../../Lua/WardrobeCore.lua#L2048) |
| `local function successEventForEffect(currentEffect)` | 將成功的副作用結果轉成對應 reducer 事件。 | — | [L2130](../../Lua/WardrobeCore.lua#L2130) |
| `local function failureEventForEffect(currentEffect, reason)` | 將失敗原因轉成該副作用的失敗事件。 | — | [L2145](../../Lua/WardrobeCore.lua#L2145) |
| `local function normalizeAdapterEvents(currentEffect, result, reason)` | 統一副作用 adapter 的布林、單一事件或事件列表結果。 | `failureEventForEffect`、`successEventForEffect` | [L2160](../../Lua/WardrobeCore.lua#L2160) |
| `function Core.createClientController(initialState, adapters)` | 建立 reducer 控制器，串接事件佇列與遊戲副作用 adapter。 | `copyClientState`、`Core.newClientState`、`adapterFor`、`run`、`dispatch`、`processEvent`、`Core.reduce`、`normalizeAdapterEvents` 等 | [L2203](../../Lua/WardrobeCore.lua#L2203) |
| `local function adapterFor(currentEffect)` | 依副作用種類取得對應 adapter。 | `run` | [L2208](../../Lua/WardrobeCore.lua#L2208) |
| `local function dispatch(rootEvent)` | 將事件加入控制器佇列，依序處理，避免副作用回呼造成重入。 | `processEvent`、`Core.reduce`、`adapterFor`、`normalizeAdapterEvents`、`Core.clientViewModel` | [L2219](../../Lua/WardrobeCore.lua#L2219) |
| `local function processEvent(currentEvent, depth)` | 執行一次 reducer 與副作用，再把結果事件回送控制器。 | `Core.reduce`、`adapterFor`、`normalizeAdapterEvents`、`Core.clientViewModel` | [L2225](../../Lua/WardrobeCore.lua#L2225) |
| `getState = function()` | 取得控制器目前的狀態快照。 | `copyClientState` | [L2265](../../Lua/WardrobeCore.lua#L2265) |
| `getViewModel = function()` | 取得控制器目前狀態所投影的介面資料。 | `Core.clientViewModel` | [L2266](../../Lua/WardrobeCore.lua#L2266) |

## 匿名回呼

包含事件、網路接收、按鈕、計時器及集合處理回呼；用註冊位置及外層函式定位。

| 位置 | 外層／註冊入口 | 參數 | 用途／本體起始 | 本體呼叫線索 |
|---|---|---|---|---|
| [L2212](../../Lua/WardrobeCore.lua#L2212) | adapterFor；return | `function(effectValue, snapshot)` | 執行回呼；本體起始：`return adapters.run(effectValue, snapshot)`。 | `run` |
