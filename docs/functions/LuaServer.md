# Lua 伺服器函式

[返回程式導覽](../CODEMAP.md)

共 132 個具名函式／方法，包含建構函式、區域函式、多載及 adapter。

用途按目前原碼整理；簽章保留參數名稱，定位列為檔案內的定義起始行。呼叫欄僅列索引內的部分直接呼叫，方便追查，不代表完整執行期呼叫圖。

## WardrobeSwitcherServer.lua

來源：[Lua/WardrobeSwitcherServer.lua](../../Lua/WardrobeSwitcherServer.lua)

| 函式／方法（含參數） | 用途 | 相關呼叫 | 定位 |
|---|---|---|---|
| `local function writeLog(level, message)` | 把時間、等級及訊息寫入有容量上限的 WardrobeServer.log，寫檔失敗不影響遊戲。 | `Write` | [L82](../../Lua/WardrobeSwitcherServer.lua#L82) |
| `local function log(message)` | 以一般等級寫入伺服器專用日誌。 | `writeLog` | [L119](../../Lua/WardrobeSwitcherServer.lua#L119) |
| `local function warn(message)` | 以警告等級寫入伺服器專用日誌。 | `writeLog` | [L123](../../Lua/WardrobeSwitcherServer.lua#L123) |
| `local function trim(value)` | 移除字串前後空白，供身分與存檔資料正規化。 | — | [L127](../../Lua/WardrobeSwitcherServer.lua#L127) |
| `local function byteLength(value)` | 取得字串的位元組長度，供封包及識別碼上限檢查。 | — | [L134](../../Lua/WardrobeSwitcherServer.lua#L134) |
| `local function messageLengthBytes(message)` | 取得網路訊息長度，避免接受過大負載。 | — | [L138](../../Lua/WardrobeSwitcherServer.lua#L138) |
| `local function cloneLook(look)` | 複製並驗證標準外觀資料，避免不同玩家共享可變表。 | `Core.validateAttachmentVisibility`、`Core.attachmentVisibilityFromLegacy`、`Core.legacyHideHair` | [L147](../../Lua/WardrobeSwitcherServer.lua#L147) |
| `local function characterEntityId(character)` | 安全取得角色的網路 entity ID。 | — | [L179](../../Lua/WardrobeSwitcherServer.lua#L179) |
| `local function clientCharacter(client)` | 安全取得指定連線目前控制的角色。 | — | [L183](../../Lua/WardrobeSwitcherServer.lua#L183) |
| `local function characterListSnapshot()` | 將遊戲角色集合轉成可安全掃描的 Lua 快照。 | — | [L189](../../Lua/WardrobeSwitcherServer.lua#L189) |
| `local function userDataMember(object, name)` | 受保護地讀取 Lua／C# 成員，缺少時回傳 nil。 | — | [L203](../../Lua/WardrobeSwitcherServer.lua#L203) |
| `local function normalizedSessionValue(value)` | 將戰役或 session 來源資訊轉成穩定可比較文字。 | `trim` | [L209](../../Lua/WardrobeSwitcherServer.lua#L209) |
| `local function firstSessionValue(object, names)` | 在候選 session 欄位中尋找第一個可用值。 | `normalizedSessionValue`、`userDataMember` | [L214](../../Lua/WardrobeSwitcherServer.lua#L214) |
| `local function currentGameSessionKey()` | 取得目前戰役穩定鍵或暫時執行期鍵。 | `userDataMember`、`firstSessionValue` | [L222](../../Lua/WardrobeSwitcherServer.lua#L222) |
| `local function profileIdentifierPart(value)` | 正規化船員身分的組成值。 | `normalizedSessionValue` | [L247](../../Lua/WardrobeSwitcherServer.lua#L247) |
| `local function crewCharacterKey(character)` | 由船員穩定資訊建立跨回合可用的角色鍵。 | `userDataMember`、`normalizedSessionValue`、`profileIdentifierPart` | [L252](../../Lua/WardrobeSwitcherServer.lua#L252) |
| `local function crewStorageKey(character)` | 結合戰役及船員鍵，定位伺服器持久化設定。 | `currentGameSessionKey`、`crewCharacterKey` | [L272](../../Lua/WardrobeSwitcherServer.lua#L272) |
| `local function isRuntimeSessionKey(key)` | 區分只在本次程序有效的 session 鍵。 | — | [L279](../../Lua/WardrobeSwitcherServer.lua#L279) |
| `local function canAwaitPersistentSessionKey(persistentKey, currentKey)` | 判斷是否應等待戰役提供穩定身分，避免太早使用暫時鍵。 | `isRuntimeSessionKey` | [L283](../../Lua/WardrobeSwitcherServer.lua#L283) |
| `local function accountIdForClient(client)` | 優先取得連線的穩定帳號身分，供跨連線保存。 | `representation`、`trim`、`userDataMember` | [L289](../../Lua/WardrobeSwitcherServer.lua#L289) |
| `local function representation(accountId)` | 把帳號或 Steam 身分的候選表示安全轉成字串。 | `trim`、`userDataMember` | [L298](../../Lua/WardrobeSwitcherServer.lua#L298) |
| `local function steamIdForClient(client)` | 從連線與端點資訊尋找可用的 Steam 身分。 | `trim` | [L340](../../Lua/WardrobeSwitcherServer.lua#L340) |
| `local function steamPersistenceIdForClient(client)` | 將 Steam 身分正規化成持久化紀錄鍵，作為帳號 API 不可用時的備援。 | `steamIdForClient` | [L349](../../Lua/WardrobeSwitcherServer.lua#L349) |
| `local function connectedClients()` | 掃描並去重目前連線玩家，兼容可用的伺服器 API。 | `append`、`collect`、`userDataMember` | [L354](../../Lua/WardrobeSwitcherServer.lua#L354) |
| `local function append(client)` | 將合法且尚未加入的連線加到結果集合。 | — | [L356](../../Lua/WardrobeSwitcherServer.lua#L356) |
| `local function collect(source)` | 掃描候選連線集合，交由 append 去重。 | `append` | [L362](../../Lua/WardrobeSwitcherServer.lua#L362) |
| `local function resolveCrewTarget(client, targetCharacterId)` | 驗證請求者與指定船員的權限、隊伍、存活及人類／機器人條件。 | `clientCharacter`、`userDataMember`、`characterListSnapshot`、`characterEntityId`、`connectedClients` | [L381](../../Lua/WardrobeSwitcherServer.lua#L381) |
| `local function jsonEscape(value)` | 跳脫 JSON 字串中的控制字元及特殊字元。 | — | [L411](../../Lua/WardrobeSwitcherServer.lua#L411) |
| `local function decodeJson(text)` | 使用內建遞迴解析器讀取 JSON，拒絕截斷、重複鍵及尾隨資料。 | `skipSpace`、`parseString`、`parseArray`、`parseValue`、`parseObject` | [L423](../../Lua/WardrobeSwitcherServer.lua#L423) |
| `local function skipSpace()` | JSON 解析器略過合法空白字元。 | — | [L425](../../Lua/WardrobeSwitcherServer.lua#L425) |
| `local function parseString()` | JSON 解析器讀取字串與跳脫內容，拒絕格式錯誤。 | — | [L429](../../Lua/WardrobeSwitcherServer.lua#L429) |
| `local function parseArray()` | JSON 解析器逐一解析陣列元素並驗證分隔符號。 | `skipSpace`、`parseValue` | [L468](../../Lua/WardrobeSwitcherServer.lua#L468) |
| `local function parseObject()` | JSON 解析器讀取物件欄位，拒絕重複鍵及不完整內容。 | `skipSpace`、`parseString`、`parseValue` | [L482](../../Lua/WardrobeSwitcherServer.lua#L482) |
| `parseValue = function()` | JSON 解析器依首字元分派字串、容器、數字及布林／空值。 | `skipSpace`、`parseString`、`parseObject`、`parseArray` | [L501](../../Lua/WardrobeSwitcherServer.lua#L501) |
| `local function storageDirectory()` | 取得伺服器可寫的模組存檔目錄。 | `trim`、`userDataMember` | [L523](../../Lua/WardrobeSwitcherServer.lua#L523) |
| `local function storagePath(fileName)` | 組合指定伺服器存檔的完整路徑。 | `storageDirectory` | [L532](../../Lua/WardrobeSwitcherServer.lua#L532) |
| `local function fileExists(path)` | 受保護地檢查檔案是否存在。 | — | [L537](../../Lua/WardrobeSwitcherServer.lua#L537) |
| `local function readAllText(path)` | 透過可用檔案 API 讀取指定文字檔，回報失敗。 | — | [L543](../../Lua/WardrobeSwitcherServer.lua#L543) |
| `local function ensureStorageDirectory()` | 確認並建立伺服器存檔目錄。 | `storageDirectory` | [L549](../../Lua/WardrobeSwitcherServer.lua#L549) |
| `local function atomicWrite(path, contents)` | 先寫暫存並保存備份，再替換正式檔案；失敗保留舊資料。 | `ensureStorageDirectory`、`Write`、`readAllText` | [L559](../../Lua/WardrobeSwitcherServer.lua#L559) |
| `local function hasOnlyFields(value, allowed)` | 拒絕持久化物件或負載中未宣告的欄位。 | — | [L583](../../Lua/WardrobeSwitcherServer.lua#L583) |
| `local function encodeAttachmentVisibilityJson(visibility)` | 把四種附件的可見性政策序列化為 JSON。 | `Core.validateAttachmentVisibility`、`Core.attachmentVisibilityFromLegacy`、`jsonEscape` | [L591](../../Lua/WardrobeSwitcherServer.lua#L591) |
| `local function encodeLookJson(look)` | 將標準外觀序列化為伺服器存檔 JSON。 | `encodeAttachmentVisibilityJson`、`trim`、`jsonEscape` | [L601](../../Lua/WardrobeSwitcherServer.lua#L601) |
| `local function encodePersistenceDocument()` | 產生包含玩家帳號外觀的持久化文件。 | `jsonEscape`、`encodeLookJson` | [L633](../../Lua/WardrobeSwitcherServer.lua#L633) |
| `local function encodeCrewPersistenceDocument()` | 產生包含戰役船員外觀及潛水設定的持久化文件。 | `jsonEscape`、`encodeLookJson` | [L680](../../Lua/WardrobeSwitcherServer.lua#L680) |
| `local function persistLooks()` | 安全保存玩家外觀紀錄，記錄失敗原因。 | `storagePath`、`atomicWrite`、`encodePersistenceDocument`、`warn` | [L706](../../Lua/WardrobeSwitcherServer.lua#L706) |
| `local function persistCrewLooks()` | 安全保存船員外觀與潛水設定紀錄。 | `storagePath`、`atomicWrite`、`encodeCrewPersistenceDocument`、`warn` | [L713](../../Lua/WardrobeSwitcherServer.lua#L713) |
| `local function escapeLegacy(value)` | 跳脫舊文字存檔格式的分隔字元。 | — | [L720](../../Lua/WardrobeSwitcherServer.lua#L720) |
| `local function parseLegacyDocument(text)` | 解析舊版伺服器文字外觀文件，轉成可驗證紀錄。 | `Core.attachmentVisibilityFromLegacy`、`escapeLegacy`、`normalizedSessionValue`、`trim`、`byteLength` | [L725](../../Lua/WardrobeSwitcherServer.lua#L725) |
| `local function validateStoredLook(raw, persistenceVersion)` | 驗證磁碟中的外觀資料，避免損壞或不支援的內容進入 session。 | `hasOnlyFields`、`Core.validateAttachmentVisibility`、`Core.attachmentVisibilityFromLegacy`、`Core.legacyHideHair`、`byteLength`、`trim` | [L775](../../Lua/WardrobeSwitcherServer.lua#L775) |
| `local function quarantine(path, reason)` | 將損壞存檔改名隔離，保留原資料供追查。 | `warn` | [L877](../../Lua/WardrobeSwitcherServer.lua#L877) |
| `local function decodeStoredRecord(raw, persistenceVersion, identityField)` | 驗證並解析單筆持久化玩家外觀紀錄。 | `hasOnlyFields`、`validateStoredLook`、`normalizedSessionValue` | [L884](../../Lua/WardrobeSwitcherServer.lua#L884) |
| `local function loadJsonPersistence(path)` | 讀取目前 JSON 存檔，驗證版本及每筆紀錄。 | `readAllText`、`hasOnlyFields`、`quarantine`、`trim`、`decodeStoredRecord`、`Write`、`warn`、`persistLooks` 等 | [L913](../../Lua/WardrobeSwitcherServer.lua#L913) |
| `local function moveLegacyToBackup(path)` | 遷移成功後保存舊文字存檔備份。 | `fileExists` | [L991](../../Lua/WardrobeSwitcherServer.lua#L991) |
| `local function loadLegacyPersistence(path)` | 載入舊文字資料並遷移到目前持久化結構。 | `readAllText`、`parseLegacyDocument`、`quarantine` | [L999](../../Lua/WardrobeSwitcherServer.lua#L999) |
| `local function loadPersistence()` | 選擇目前 JSON 或舊版存檔載入，安排遷移及隔離。 | `storagePath`、`fileExists`、`loadJsonPersistence`、`persistLooks`、`moveLegacyToBackup`、`loadLegacyPersistence` | [L1016](../../Lua/WardrobeSwitcherServer.lua#L1016) |
| `local function prefabIdentifier(prefab)` | 安全取得物品 prefab 的識別碼。 | `trim`、`userDataMember` | [L1051](../../Lua/WardrobeSwitcherServer.lua#L1051) |
| `local function prefabName(prefab)` | 安全取得物品 prefab 的顯示名稱。 | `userDataMember`、`prefabIdentifier` | [L1055](../../Lua/WardrobeSwitcherServer.lua#L1055) |
| `local function resolveItemPrefab(identifier)` | 依識別碼在伺服器已載入的 prefab 中查找物品。 | — | [L1059](../../Lua/WardrobeSwitcherServer.lua#L1059) |
| `local function wearableAllowsSlot(prefab, slotKey)` | 確認 prefab 的穿戴元件允許指定欄位，拒絕偽造外觀位置。 | `userDataMember`、`trim` | [L1072](../../Lua/WardrobeSwitcherServer.lua#L1072) |
| `local function itemIdentifier(item)` | 取得實際物品的 prefab 識別碼。 | `trim` | [L1097](../../Lua/WardrobeSwitcherServer.lua#L1097) |
| `local function itemSpriteColor(item)` | 取得伺服器真物品的 packed 色彩，保存時不相信客戶端提交值。 | — | [L1101](../../Lua/WardrobeSwitcherServer.lua#L1101) |
| `local function isLockedWardrobeItem(item)` | 判斷真裝備是否禁止由衣櫃卸下或保存。 | `HasTag` | [L1108](../../Lua/WardrobeSwitcherServer.lua#L1108) |
| `local function loadCrewPersistence()` | 載入並驗證船員外觀及潛水設定，處理舊版預設與損壞資料。 | `storagePath`、`fileExists`、`readAllText`、`hasOnlyFields`、`quarantine`、`persistCrewLooks`、`validateStoredLook`、`normalizedSessionValue` 等 | [L1120](../../Lua/WardrobeSwitcherServer.lua#L1120) |
| `local function getSlotItem(character, slot)` | 從伺服器角色的實際裝備欄取得物品。 | — | [L1200](../../Lua/WardrobeSwitcherServer.lua#L1200) |
| `local function isInAnyWardrobeSlot(character, item)` | 確認物品是否仍占用任何管理中的穿戴欄位。 | `getSlotItem` | [L1213](../../Lua/WardrobeSwitcherServer.lua#L1213) |
| `local function unequipItem(character, item)` | 在伺服器卸下物品並驗證實際結果，避免只相信 API 回傳值。 | `clear`、`isInAnyWardrobeSlot`、`Unequip`、`isLockedWardrobeItem` | [L1222](../../Lua/WardrobeSwitcherServer.lua#L1222) |
| `local function clear()` | 卸裝內部檢查：確認物品已離開管理穿戴欄位。 | `isInAnyWardrobeSlot` | [L1224](../../Lua/WardrobeSwitcherServer.lua#L1224) |
| `local function collectWardrobeItems(character, look)` | 收集角色裝備並去除多欄物品重複，供權威保存及卸裝。 | `getSlotItem` | [L1243](../../Lua/WardrobeSwitcherServer.lua#L1243) |
| `local function itemOccupiesSlot(character, item, slot)` | 檢查真物品是否占用角色指定欄位。 | `getSlotItem` | [L1270](../../Lua/WardrobeSwitcherServer.lua#L1270) |
| `local function restoreWardrobeItems(character, snapshots)` | 交易失敗時嘗試穿回原裝備並回報無法還原的項目。 | `itemOccupiesSlot` | [L1276](../../Lua/WardrobeSwitcherServer.lua#L1276) |
| `local function canonicalSlot(identifier, slotKey, color)` | 由伺服器實體或 prefab 驗證欄位，建立可信的標準欄位紀錄。 | `trim`、`byteLength`、`resolveItemPrefab`、`wearableAllowsSlot`、`prefabIdentifier`、`prefabName` | [L1294](../../Lua/WardrobeSwitcherServer.lua#L1294) |
| `local function canonicalizeLook(raw, requireCaptured)` | 驗證客戶端外觀中的所有欄位，轉成伺服器接受的標準資料。 | `Core.validateAttachmentVisibility`、`Core.legacyHideHair`、`byteLength`、`canonicalSlot` | [L1314](../../Lua/WardrobeSwitcherServer.lua#L1314) |
| `local function captureAuthoritativeLook(character, clientLook)` | 直接從伺服器角色的真裝備取得識別碼、名稱及色彩，拒絕偽造保存資料。 | `Core.validateAttachmentVisibility`、`Core.legacyHideHair`、`getSlotItem`、`itemIdentifier`、`itemSpriteColor`、`canonicalizeLook` | [L1362](../../Lua/WardrobeSwitcherServer.lua#L1362) |
| `local function writeLegacyLook(message, characterId, look)` | 將外觀寫成舊協定可接收的欄位格式。 | — | [L1398](../../Lua/WardrobeSwitcherServer.lua#L1398) |
| `local function migrateLegacyForClient(client, accountId)` | 為已有穩定身分的連線遷移舊版外觀紀錄。 | `steamIdForClient`、`persistLooks`、`log` | [L1411](../../Lua/WardrobeSwitcherServer.lua#L1411) |
| `local function operationCacheNow()` | 取得命令去重快取使用的時鐘。 | — | [L1438](../../Lua/WardrobeSwitcherServer.lua#L1438) |
| `local function newOperationCache(clientSessionId)` | 建立操作 ID 與結果的去重快取。 | `operationCacheNow` | [L1443](../../Lua/WardrobeSwitcherServer.lua#L1443) |
| `local function operationCacheInUse(cache)` | 確認快取是否仍被有效 session 使用，避免過早淘汰。 | — | [L1453](../../Lua/WardrobeSwitcherServer.lua#L1453) |
| `local function pruneOperationCaches(now)` | 按期限及容量移除不再使用的命令結果快取。 | `operationCacheNow`、`operationCacheInUse` | [L1460](../../Lua/WardrobeSwitcherServer.lua#L1460) |
| `local function bindOperationCache(session, clientSessionId)` | 把連線 session 綁到對應去重快取，重傳仍使用原結果。 | `operationCacheNow`、`newOperationCache`、`pruneOperationCaches` | [L1485](../../Lua/WardrobeSwitcherServer.lua#L1485) |
| `local function sessionFor(client)` | 取得或建立玩家 session，載入可用持久化外觀及協定狀態。 | `accountIdForClient`、`bindOperationCache`、`migrateLegacyForClient`、`steamPersistenceIdForClient`、`canonicalizeLook`、`warn`、`cloneLook`、`currentGameSessionKey` 等 | [L1513](../../Lua/WardrobeSwitcherServer.lua#L1513) |
| `local function updatePersistentRecord(session)` | 把 session 已接受外觀及啟用意圖投影回穩定帳號存檔。 | `cloneLook`、`currentGameSessionKey` | [L1584](../../Lua/WardrobeSwitcherServer.lua#L1584) |
| `local function clonePersistentRecord(record)` | 複製玩家磁碟紀錄供交易回滾。 | `cloneLook` | [L1598](../../Lua/WardrobeSwitcherServer.lua#L1598) |
| `local function snapshotCommitState(session)` | 快照玩家 session 與持久化紀錄，保護命令提交。 | `cloneLook`、`clonePersistentRecord` | [L1608](../../Lua/WardrobeSwitcherServer.lua#L1608) |
| `local function restoreCommitState(session, snapshot)` | 恢復提交前的 session 及磁碟紀錄快照。 | `cloneLook`、`clonePersistentRecord` | [L1620](../../Lua/WardrobeSwitcherServer.lua#L1620) |
| `local function persistStableSessionOrRollback(session, snapshot)` | 穩定帳號的資料寫入失敗時回滾狀態，避免回覆成功卻未保存。 | `updatePersistentRecord`、`persistLooks`、`restoreCommitState` | [L1633](../../Lua/WardrobeSwitcherServer.lua#L1633) |
| `local function sendV2Ack(session, operationId, accepted, reason, revision)` | 向命令發送者回覆接受與否、操作 ID、修訂及原因。 | `Core.writeAck`、`warn` | [L1641](../../Lua/WardrobeSwitcherServer.lua#L1641) |
| `local function sendV2State(client, revision, characterId, active, look)` | 向指定連線發送目前協定的角色外觀狀態。 | `Core.writeState`、`warn` | [L1654](../../Lua/WardrobeSwitcherServer.lua#L1654) |
| `local function sendLegacyState(client, characterId, active, look)` | 向舊版連線發送相容的外觀或清除狀態。 | `writeLegacyLook` | [L1667](../../Lua/WardrobeSwitcherServer.lua#L1667) |
| `local function sendStateTo(client, ownerSession, ownerRevision, observerRevision, characterId, active, look, crewOwned)` | 依目標連線已協商的版本選擇新舊狀態發送方式。 | `sessionFor`、`sendV2State`、`sendLegacyState` | [L1680](../../Lua/WardrobeSwitcherServer.lua#L1680) |
| `local function cloneCrewRecord(record)` | 複製船員持久化紀錄及潛水設定，供回滾使用。 | `cloneLook` | [L1691](../../Lua/WardrobeSwitcherServer.lua#L1691) |
| `local function snapshotCrewState(character)` | 快照指定船員的執行期及持久化狀態。 | `crewStorageKey`、`cloneCrewRecord` | [L1705](../../Lua/WardrobeSwitcherServer.lua#L1705) |
| `local function crewLook(character)` | 取得指定船員目前保存的外觀。 | `crewStorageKey`、`cloneLook` | [L1716](../../Lua/WardrobeSwitcherServer.lua#L1716) |
| `local function crewDivingProfile(character)` | 取得船員的潛水模式及自訂外觀，缺少時提供預設。 | `crewStorageKey`、`cloneLook` | [L1722](../../Lua/WardrobeSwitcherServer.lua#L1722) |
| `local function crewRecordHasData(record)` | 判斷船員紀錄是否仍有外觀或潛水資料需要保留。 | — | [L1733](../../Lua/WardrobeSwitcherServer.lua#L1733) |
| `local function setCrewLook(snapshot, character, look, active)` | 更新船員保存外觀，整理空紀錄。 | `cloneCrewRecord`、`userDataMember`、`cloneLook`、`crewRecordHasData` | [L1738](../../Lua/WardrobeSwitcherServer.lua#L1738) |
| `local function setCrewDivingProfile(snapshot, character, profile)` | 更新船員潛水模式及自訂外觀，保留其他外觀資料。 | `cloneCrewRecord`、`userDataMember`、`cloneLook`、`crewRecordHasData` | [L1750](../../Lua/WardrobeSwitcherServer.lua#L1750) |
| `local function persistCrewOrRollback(snapshot)` | 船員資料保存失敗時回復提交前快照。 | `persistCrewLooks`、`cloneCrewRecord` | [L1764](../../Lua/WardrobeSwitcherServer.lua#L1764) |
| `local function sendCrewDivingState(client, character, profile)` | 向指定連線同步某個船員的潛水外觀設定。 | `sessionFor`、`Core.writeDivingProfile`、`characterEntityId`、`warn` | [L1771](../../Lua/WardrobeSwitcherServer.lua#L1771) |
| `local function broadcastCrewDivingState(character, profile)` | 向支援能力的連線廣播船員潛水設定。 | `connectedClients`、`sendCrewDivingState` | [L1790](../../Lua/WardrobeSwitcherServer.lua#L1790) |
| `local function sendCrewDivingSnapshot(client)` | 向新連線或重新握手的客戶端發送現有船員潛水設定。 | `characterListSnapshot`、`crewDivingProfile`、`sendCrewDivingState` | [L1796](../../Lua/WardrobeSwitcherServer.lua#L1796) |
| `local function nextObserverRevision(characterId)` | 產生觀察者廣播所用的單調修訂號。 | — | [L1803](../../Lua/WardrobeSwitcherServer.lua#L1803) |
| `local function broadcastState(ownerSession, ownerRevision, characterId, active, look, observerRevision, crewOwned)` | 向連線玩家廣播角色外觀狀態，依協定能力轉換負載。 | `nextObserverRevision`、`connectedClients`、`sendStateTo` | [L1812](../../Lua/WardrobeSwitcherServer.lua#L1812) |
| `local function sendActiveSnapshot(client)` | 將目前啟用的角色外觀快照發給指定客戶端。 | `restoreCrewRuntimes`、`sessionFor`、`connectedClients`、`clientCharacter`、`characterEntityId`、`activateRuntime`、`sendStateTo`、`characterListSnapshot` 等 | [L1825](../../Lua/WardrobeSwitcherServer.lua#L1825) |
| `local function sendOwnInactiveState(session)` | 把玩家自己的已保存但未啟用外觀回傳給該玩家。 | `characterEntityId`、`clientCharacter`、`sendV2State` | [L1882](../../Lua/WardrobeSwitcherServer.lua#L1882) |
| `local function clearActiveRuntime(session, shouldBroadcast, targetCharacterId, inactiveLook, crewOwned)` | 清除指定角色的啟用外觀執行期紀錄。 | `broadcastState` | [L1889](../../Lua/WardrobeSwitcherServer.lua#L1889) |
| `activateRuntime = function(session, character, look, restoring, targeted)` | 把已接受外觀登記為角色目前啟用狀態。 | `characterEntityId`、`currentGameSessionKey`、`clearActiveRuntime`、`clientCharacter`、`nextObserverRevision`、`crewStorageKey`、`cloneLook`、`broadcastState` | [L1910](../../Lua/WardrobeSwitcherServer.lua#L1910) |
| `local function operationResultFor(session, operationId)` | 查詢操作 ID 是否已有結果，避免重複執行命令。 | `newOperationCache`、`operationCacheNow` | [L1949](../../Lua/WardrobeSwitcherServer.lua#L1949) |
| `local function rememberOperation(session, operationId, accepted, reason, command)` | 把已完成操作的結果寫入去重快取。 | `operationResultFor`、`operationCacheNow` | [L1972](../../Lua/WardrobeSwitcherServer.lua#L1972) |
| `local function canAdvanceRevision(session)` | 檢查修訂號能否安全遞增，避免溢位。 | — | [L1989](../../Lua/WardrobeSwitcherServer.lua#L1989) |
| `local function nextRevision(session)` | 遞增並回傳 session 的下一個修訂號。 | `canAdvanceRevision` | [L1994](../../Lua/WardrobeSwitcherServer.lua#L1994) |
| `local function commitSave(session, character, clientLook, targeted, unequipOnSave)` | 權威擷取真裝備，依選項卸裝並驗證，保存成功才接受命令，失敗回滾。 | `canAdvanceRevision`、`captureAuthoritativeLook`、`snapshotCrewState`、`persistCrewLooks`、`persistLooks`、`collectWardrobeItems`、`unequipItem`、`restoreWardrobeItems` 等 | [L2002](../../Lua/WardrobeSwitcherServer.lua#L2002) |
| `local function commitApply(session, character, look, targeted)` | 驗證保存外觀或補交資料，啟用並保存狀態，再廣播套用結果。 | `canAdvanceRevision`、`characterEntityId`、`snapshotCrewState`、`snapshotCommitState`、`nextRevision`、`setCrewLook`、`persistCrewOrRollback`、`cloneLook` 等 | [L2068](../../Lua/WardrobeSwitcherServer.lua#L2068) |
| `local function commitVisualPreference(session, character, requestedLook, preference, targeted)` | 只更新伺服器允許的外觀偏好，不接受客戶端藉此替換裝備內容。 | `canAdvanceRevision`、`crewLook`、`cloneLook`、`Core.validateAttachmentVisibility`、`Core.attachmentVisibilityFromLegacy`、`Core.legacyHideHair`、`snapshotCommitState`、`snapshotCrewState` 等 | [L2105](../../Lua/WardrobeSwitcherServer.lua#L2105) |
| `local function commitClear(session, character, deleteSaved, targeted)` | 清除或忘記外觀，持久化成功後更新修訂及執行期狀態。 | `canAdvanceRevision`、`snapshotCommitState`、`snapshotCrewState`、`nextRevision`、`cloneLook`、`setCrewLook`、`persistCrewOrRollback`、`persistStableSessionOrRollback` 等 | [L2172](../../Lua/WardrobeSwitcherServer.lua#L2172) |
| `local function parseV2Command(message, targeted)` | 依訊息格式解析一般命令或船員目標命令。 | `ReadBoolean` | [L2215](../../Lua/WardrobeSwitcherServer.lua#L2215) |
| `local function validateV2Envelope(command)` | 驗證協定版本、session、操作 ID 及修訂等外層欄位。 | `byteLength` | [L2249](../../Lua/WardrobeSwitcherServer.lua#L2249) |
| `local function resendCurrentState(session, operation)` | 重傳操作確認後仍需到達的目前外觀狀態。 | `sendV2State`、`characterListSnapshot`、`characterEntityId`、`crewLook`、`sendOwnInactiveState` | [L2275](../../Lua/WardrobeSwitcherServer.lua#L2275) |
| `local function handleV2Command(message, client, targeted)` | 執行權限、格式、去重及修訂檢查，再分派權威命令並發送確認。 | `handleGameSessionChange`、`sessionFor`、`messageLengthBytes`、`warn`、`validateV2Envelope`、`sendV2Ack`、`bindOperationCache`、`operationResultFor` 等 | [L2325](../../Lua/WardrobeSwitcherServer.lua#L2325) |
| `local function releaseSessionCrewRuntimes(session)` | 移除玩家 session 關聯的船員執行期登記。 | — | [L2408](../../Lua/WardrobeSwitcherServer.lua#L2408) |
| `local function restoreCrewRuntime(character)` | 為符合穩定身分及還原意圖的船員恢復伺服器執行期外觀。 | `userDataMember`、`crewStorageKey`、`characterEntityId`、`canonicalizeLook`、`persistCrewLooks`、`warn`、`cloneLook`、`activateRuntime` | [L2416](../../Lua/WardrobeSwitcherServer.lua#L2416) |
| `restoreCrewRuntimes = function()` | 掃描目前船員，從戰役持久化紀錄恢復可用的外觀。 | `characterListSnapshot`、`restoreCrewRuntime` | [L2440](../../Lua/WardrobeSwitcherServer.lua#L2440) |
| `local function readLegacyApplyLook(message)` | 讀取舊版 Apply 附帶的外觀負載，處理可省略資料。 | `ReadBoolean`、`Core.attachmentVisibilityFromLegacy`、`byteLength` | [L2488](../../Lua/WardrobeSwitcherServer.lua#L2488) |
| `local function selectLegacyProtocol(session)` | 為舊命令連線標記相容協定狀態。 | `warn` | [L2516](../../Lua/WardrobeSwitcherServer.lua#L2516) |
| `local function clearRoundRuntime()` | 回合結束時清除角色實體關聯及暫時廣播狀態，保留持久化意圖。 | — | [L2575](../../Lua/WardrobeSwitcherServer.lua#L2575) |
| `handleGameSessionChange = function()` | 偵測戰役變更或 session 重綁，隔離不同戰役紀錄並安排恢復。 | `currentGameSessionKey`、`clearRoundRuntime`、`nextRevision`、`warn`、`updatePersistentRecord`、`persistLooks`、`log` | [L2584](../../Lua/WardrobeSwitcherServer.lua#L2584) |
| `local function reactivateSession(session)` | 角色及穩定戰役鍵就緒後，恢復玩家先前已啟用的保存外觀。 | `currentGameSessionKey`、`isRuntimeSessionKey`、`clientCharacter`、`characterEntityId`、`activateRuntime` | [L2612](../../Lua/WardrobeSwitcherServer.lua#L2612) |
| `local function rebindCreatedCharacter(character)` | 角色替換後重新綁定玩家 session，維持正確的外觀所有權。 | `characterEntityId`、`handleGameSessionChange`、`connectedClients`、`clientCharacter`、`sessionFor`、`activateRuntime`、`restoreCrewRuntime` | [L2640](../../Lua/WardrobeSwitcherServer.lua#L2640) |
| `local function scheduleSessionReactivation(session, generation)` | 安排延後的 session 恢復，等待遊戲完成角色及戰役初始化。 | `attemptReactivation`、`handleGameSessionChange`、`reactivateSession` | [L2656](../../Lua/WardrobeSwitcherServer.lua#L2656) |
| `local function attemptReactivation()` | 延後重試玩家外觀恢復，達到限制或成功後停止。 | `handleGameSessionChange`、`reactivateSession` | [L2658](../../Lua/WardrobeSwitcherServer.lua#L2658) |
| `local function attemptRebind()` | 延後重試新角色與 session 的綁定。 | `rebindCreatedCharacter`、`crewDivingProfile`、`broadcastCrewDivingState` | [L2707](../../Lua/WardrobeSwitcherServer.lua#L2707) |

## 匿名回呼

包含事件、網路接收、按鈕、計時器及集合處理回呼；用註冊位置及外層函式定位。

| 位置 | 外層／註冊入口 | 參數 | 用途／本體起始 | 本體呼叫線索 |
|---|---|---|---|---|
| [L42](../../Lua/WardrobeSwitcherServer.lua#L42) | 檔案層級註冊；pcall( | `function()` | 建立 C# 靜態橋接：`Barotrauma.CharacterInventory`。 | — |
| [L43](../../Lua/WardrobeSwitcherServer.lua#L43) | 檔案層級註冊；pcall( | `function()` | 建立 C# 靜態橋接：`Barotrauma.Networking.Client`。 | — |
| [L44](../../Lua/WardrobeSwitcherServer.lua#L44) | 檔案層級註冊；pcall( | `function()` | 建立 C# 靜態橋接：`Barotrauma.GameMain`。 | — |
| [L45](../../Lua/WardrobeSwitcherServer.lua#L45) | 檔案層級註冊；pcall( | `function()` | 建立 C# 靜態橋接：`Barotrauma.ItemPrefab`。 | — |
| [L87](../../Lua/WardrobeSwitcherServer.lua#L87) | writeLog；written, writeFailure = pcall( | `function()` | 受保護地執行；本體起始：`local now = math.floor(tonumber(os.time()) or 0) if serverLogWindowSecond ~= now then`。 | `Write` |
| [L111](../../Lua/WardrobeSwitcherServer.lua#L111) | writeLog；pcall( | `function()` | 受保護地執行；本體起始：`local consoleLine = line .. (writeFailure ~= nil and (" [file log unavailable: " .. tostring(writeFailure) .. "]") or "")`。 | — |
| [L140](../../Lua/WardrobeSwitcherServer.lua#L140) | messageLengthBytes；local ok, value = pcall( | `function()` | 受保護地執行；本體起始：`return message.LengthBytes end`。 | — |
| [L142](../../Lua/WardrobeSwitcherServer.lua#L142) | messageLengthBytes；ok, value = pcall( | `function()` | 受保護地執行；本體起始：`return message.LengthBits end`。 | — |
| [L185](../../Lua/WardrobeSwitcherServer.lua#L185) | clientCharacter；local ok, character = pcall( | `function()` | 受保護地執行；本體起始：`return client.Character end`。 | — |
| [L197](../../Lua/WardrobeSwitcherServer.lua#L197) | characterListSnapshot；pcall( | `function()` | 受保護地執行；本體起始：`for character in list do characters[#characters + 1] = character end`。 | — |
| [L205](../../Lua/WardrobeSwitcherServer.lua#L205) | userDataMember；local ok, value = pcall( | `function()` | 受保護地執行；本體起始：`return object[name] end`。 | — |
| [L291](../../Lua/WardrobeSwitcherServer.lua#L291) | accountIdForClient；local ok, option = pcall( | `function()` | 受保護地執行；本體起始：`return client.AccountId end`。 | — |
| [L295](../../Lua/WardrobeSwitcherServer.lua#L295) | accountIdForClient；pcall( | `function()` | 受保護地執行；本體起始：`isSome = option.IsSome() == true end`。 | — |
| [L306](../../Lua/WardrobeSwitcherServer.lua#L306) | accountIdForClient；local called, first, second = pcall( | `function()` | 受保護地執行；本體起始：`return option.TryUnwrap() end`。 | — |
| [L319](../../Lua/WardrobeSwitcherServer.lua#L319) | accountIdForClient；pcall( | `function()` | 受保護地執行；本體起始：`option.Match( function(value) matched = value end,`。 | — |
| [L321](../../Lua/WardrobeSwitcherServer.lua#L321) | accountIdForClient； | `function(value)` | 執行回呼；本體起始：`matched = value end`。 | — |
| [L322](../../Lua/WardrobeSwitcherServer.lua#L322) | accountIdForClient； | `function()` | 執行回呼；本體起始：``。 | — |
| [L342](../../Lua/WardrobeSwitcherServer.lua#L342) | steamIdForClient；local ok, value = pcall( | `function()` | 受保護地執行；本體起始：`return client.SteamID end`。 | — |
| [L364](../../Lua/WardrobeSwitcherServer.lua#L364) | collect；local ok = pcall( | `function()` | 受保護地執行；本體起始：`for client in source do append(client) end end`。 | `append` |
| [L366](../../Lua/WardrobeSwitcherServer.lua#L366) | collect；ok = pcall( | `function()` | 受保護地執行；本體起始：`for _, client in pairs(source) do append(client) end end`。 | `append` |
| [L368](../../Lua/WardrobeSwitcherServer.lua#L368) | collect；pcall( | `function()` | 受保護地執行；本體起始：`local count = tonumber(source.Count) or 0 for index = 0, count - 1 do append(source[index]) end`。 | `append` |
| [L376](../../Lua/WardrobeSwitcherServer.lua#L376) | connectedClients；local ok, gameServer = pcall( | `function()` | 受保護地執行；本體起始：`return Game ~= nil and Game.Server or nil end`。 | — |
| [L420](../../Lua/WardrobeSwitcherServer.lua#L420) | jsonEscape；:gsub("[%z\1-\31]", | `function(character)` | 執行回呼；本體起始：`return string.format("\\u%04x", string.byte(character)) end`。 | — |
| [L539](../../Lua/WardrobeSwitcherServer.lua#L539) | fileExists；local ok, exists = pcall( | `function()` | 受保護地執行；本體起始：`return File.Exists(path) end`。 | — |
| [L545](../../Lua/WardrobeSwitcherServer.lua#L545) | readAllText；local ok, text = pcall( | `function()` | 受保護地執行；本體起始：`return File.Read(path) end`。 | — |
| [L552](../../Lua/WardrobeSwitcherServer.lua#L552) | ensureStorageDirectory；local ok, created = pcall( | `function()` | 受保護地執行；本體起始：`return File.CreateDirectory(directory) end`。 | — |
| [L564](../../Lua/WardrobeSwitcherServer.lua#L564) | atomicWrite；local ok, failure = pcall( | `function()` | 受保護地執行；本體起始：`if File.Exists(temporaryPath) then File.Delete(temporaryPath) end File.Write(temporaryPath, contents)`。 | `Write`、`readAllText` |
| [L575](../../Lua/WardrobeSwitcherServer.lua#L575) | atomicWrite；pcall( | `function()` | 受保護地執行；本體起始：`if File.Exists(backupPath) then File.Move(backupPath, path) end end`。 | — |
| [L577](../../Lua/WardrobeSwitcherServer.lua#L577) | atomicWrite；pcall( | `function()` | 受保護地執行；本體起始：`if File.Exists(temporaryPath) then File.Delete(temporaryPath) end end`。 | — |
| [L880](../../Lua/WardrobeSwitcherServer.lua#L880) | quarantine；local moved = File ~= nil and pcall( | `function()` | 受保護地執行；本體起始：`File.Move(path, destination) end`。 | — |
| [L975](../../Lua/WardrobeSwitcherServer.lua#L975) | loadJsonPersistence；pcall( | `function()` | 受保護地執行；本體起始：`File.Write(backupPath, source) end`。 | `Write` |
| [L994](../../Lua/WardrobeSwitcherServer.lua#L994) | moveLegacyToBackup；pcall( | `function()` | 受保護地執行；本體起始：`File.Move(path, backup)`。 | — |
| [L1062](../../Lua/WardrobeSwitcherServer.lua#L1062) | resolveItemPrefab；pcall( | `function()` | 受保護地執行；本體起始：`prefab = ItemPrefab.Prefabs[identifier] end`。 | — |
| [L1064](../../Lua/WardrobeSwitcherServer.lua#L1064) | resolveItemPrefab；pcall( | `function()` | 受保護地執行；本體起始：`for candidate in ItemPrefab.Prefabs do if tostring(candidate.Identifier):lower() == tostring(identifier):lower() then prefab = candidate break end`。 | — |
| [L1077](../../Lua/WardrobeSwitcherServer.lua#L1077) | wearableAllowsSlot；pcall( | `function()` | 受保護地執行；本體起始：`wearable = element.GetChildElement("Wearable") end`。 | — |
| [L1080](../../Lua/WardrobeSwitcherServer.lua#L1080) | wearableAllowsSlot；pcall( | `function()` | 受保護地執行；本體起始：`slotText = tostring(wearable.GetAttributeString("slots", "Any")) end`。 | — |
| [L1082](../../Lua/WardrobeSwitcherServer.lua#L1082) | wearableAllowsSlot；pcall( | `function()` | 受保護地執行；本體起始：`local attribute = wearable.Element.Attribute("slots") or wearable.Element.Attribute("Slots") if attribute ~= nil then slotText = tostring(attribute.Value) end`。 | — |
| [L1103](../../Lua/WardrobeSwitcherServer.lua#L1103) | itemSpriteColor；local ok, color = pcall( | `function()` | 受保護地執行；本體起始：`return tonumber(item.SpriteColor.PackedValue) end`。 | — |
| [L1110](../../Lua/WardrobeSwitcherServer.lua#L1110) | isLockedWardrobeItem；local ok, locked = pcall( | `function()` | 受保護地執行；本體起始：`return item.OwnInventory ~= nil and item.OwnInventory.Locked == true`。 | — |
| [L1114](../../Lua/WardrobeSwitcherServer.lua#L1114) | isLockedWardrobeItem；ok, locked = pcall( | `function()` | 受保護地執行；本體起始：`return item.HasTag("lock") or item.HasTag("locked")`。 | `HasTag` |
| [L1202](../../Lua/WardrobeSwitcherServer.lua#L1202) | getSlotItem；local ok, item = pcall( | `function()` | 受保護地執行；本體起始：`return character.Inventory.GetItemInLimbSlot(slot) end`。 | — |
| [L1205](../../Lua/WardrobeSwitcherServer.lua#L1205) | getSlotItem；pcall( | `function()` | 受保護地執行；本體起始：`index = character.Inventory.FindLimbSlot(slot) end`。 | — |
| [L1207](../../Lua/WardrobeSwitcherServer.lua#L1207) | getSlotItem；ok, item = pcall( | `function()` | 受保護地執行；本體起始：`return character.Inventory.GetItemAtSlot(index) end`。 | — |
| [L1209](../../Lua/WardrobeSwitcherServer.lua#L1209) | getSlotItem；ok, item = pcall( | `function()` | 受保護地執行；本體起始：`return character.Inventory.GetItemAt(index) end`。 | — |
| [L1216](../../Lua/WardrobeSwitcherServer.lua#L1216) | isInAnyWardrobeSlot；local ok, result = pcall( | `function()` | 受保護地執行；本體起始：`return character.Inventory.IsInLimbSlot(item, entry.slot) end`。 | — |
| [L1225](../../Lua/WardrobeSwitcherServer.lua#L1225) | unequipItem；pcall( | `function()` | 受保護地執行；本體起始：`item.Unequip(character) end`。 | `Unequip` |
| [L1228](../../Lua/WardrobeSwitcherServer.lua#L1228) | unequipItem；pcall( | `function()` | 受保護地執行；本體起始：`item.Drop(character) end`。 | — |
| [L1232](../../Lua/WardrobeSwitcherServer.lua#L1232) | unequipItem；local ok, moved = pcall( | `function()` | 受保護地執行；本體起始：`return character.Inventory.TryPutItem(item, character, CharacterInventory.AnySlot, true, true)`。 | — |
| [L1237](../../Lua/WardrobeSwitcherServer.lua#L1237) | unequipItem；pcall( | `function()` | 受保護地執行；本體起始：`item.Unequip(character) end`。 | `Unequip` |
| [L1239](../../Lua/WardrobeSwitcherServer.lua#L1239) | unequipItem；pcall( | `function()` | 受保護地執行；本體起始：`item.Drop(character) end`。 | — |
| [L1272](../../Lua/WardrobeSwitcherServer.lua#L1272) | itemOccupiesSlot；local ok, result = pcall( | `function()` | 受保護地執行；本體起始：`return character.Inventory.IsInLimbSlot(item, slot) end`。 | — |
| [L1286](../../Lua/WardrobeSwitcherServer.lua#L1286) | restoreWardrobeItems；if not alreadyRestored then pcall( | `function()` | 受保護地執行；本體起始：`snapshot.item.Equip(character) end`。 | — |
| [L1472](../../Lua/WardrobeSwitcherServer.lua#L1472) | pruneOperationCaches；table.sort(retained, | `function(left, right)` | 執行回呼；本體起始：`return (tonumber(left.cache.lastTouchedAt) or 0) < (tonumber(right.cache.lastTouchedAt) or 0)`。 | — |
| [L2295](../../Lua/WardrobeSwitcherServer.lua#L2295) | 檔案層級註冊；Networking.Receive(NET.V2_HELLO, | `function(message, client)` | 執行回呼；本體起始：`local ok, hello, helloReason = pcall(Core.readClientHello, message) if not ok or hello == nil then`。 | `warn`、`byteLength`、`handleGameSessionChange`、`sessionFor`、`bindOperationCache`、`Core.writeServerHello`、`sendActiveSnapshot`、`sendCrewDivingSnapshot` 等 |
| [L2448](../../Lua/WardrobeSwitcherServer.lua#L2448) | 檔案層級註冊；Networking.Receive(NET.V2_COMMAND, | `function(message, client)` | 執行回呼；本體起始：`handleV2Command(message, client, false)`。 | `handleV2Command` |
| [L2452](../../Lua/WardrobeSwitcherServer.lua#L2452) | 檔案層級註冊；Networking.Receive(NET.V2_TARGET_COMMAND, | `function(message, client)` | 執行回呼；本體起始：`handleV2Command(message, client, true)`。 | `handleV2Command` |
| [L2456](../../Lua/WardrobeSwitcherServer.lua#L2456) | 檔案層級註冊；Networking.Receive(NET.V2_DIVING_COMMAND, | `function(message, client)` | 執行回呼；本體起始：`local session = sessionFor(client) if session == nil or session.protocol ~= PROTOCOL_VERSION then return end`。 | `sessionFor`、`messageLengthBytes`、`Core.tryReadDivingProfile`、`warn`、`canonicalizeLook`、`resolveCrewTarget`、`snapshotCrewState`、`setCrewDivingProfile` 等 |
| [L2489](../../Lua/WardrobeSwitcherServer.lua#L2489) | readLegacyApplyLook；local ok, supplied, look, payloadBytes = pcall( | `function()` | 受保護地執行；本體起始：`local hasLook = message.ReadBoolean() == true if not hasLook then return false, nil, 1 end`。 | `ReadBoolean`、`Core.attachmentVisibilityFromLegacy`、`byteLength` |
| [L2527](../../Lua/WardrobeSwitcherServer.lua#L2527) | 檔案層級註冊；Networking.Receive(NET.V1_SAVE_REQUEST, | `function(_, client)` | 執行回呼；本體起始：`local session = sessionFor(client) local character = clientCharacter(client)`。 | `sessionFor`、`clientCharacter`、`selectLegacyProtocol`、`commitSave` |
| [L2535](../../Lua/WardrobeSwitcherServer.lua#L2535) | 檔案層級註冊；Networking.Receive(NET.V1_APPLY_REQUEST, | `function(message, client)` | 執行回呼；本體起始：`local session = sessionFor(client) local character = clientCharacter(client)`。 | `sessionFor`、`clientCharacter`、`selectLegacyProtocol`、`messageLengthBytes`、`warn`、`readLegacyApplyLook`、`canonicalizeLook`、`cloneLook` 等 |
| [L2561](../../Lua/WardrobeSwitcherServer.lua#L2561) | 檔案層級註冊；Networking.Receive(NET.V1_CLEAR_REQUEST, | `function(_, client)` | 執行回呼；本體起始：`local session = sessionFor(client) if session == nil then return end`。 | `sessionFor`、`selectLegacyProtocol`、`commitClear`、`clientCharacter` |
| [L2568](../../Lua/WardrobeSwitcherServer.lua#L2568) | 檔案層級註冊；Networking.Receive(NET.V1_FORGET_REQUEST, | `function(_, client)` | 執行回呼；本體起始：`local session = sessionFor(client) if session == nil then return end`。 | `sessionFor`、`selectLegacyProtocol`、`commitClear`、`clientCharacter` |
| [L2673](../../Lua/WardrobeSwitcherServer.lua#L2673) | 檔案層級註冊；Hook.Add("client.connected", "barowardrobeswitcher.v2-connected", | `function(client)` | 執行回呼；本體起始：`handleGameSessionChange() local session = sessionFor(client)`。 | `handleGameSessionChange`、`sessionFor`、`scheduleSessionReactivation`、`sendActiveSnapshot` |
| [L2682](../../Lua/WardrobeSwitcherServer.lua#L2682) | 檔案層級註冊；Timer.Wait( | `function()` | 執行回呼；本體起始：`if sessionsByClient[client] ~= session or session == nil or session.protocol ~= 0 then return end session.protocol = 1`。 | `sendActiveSnapshot` |
| [L2690](../../Lua/WardrobeSwitcherServer.lua#L2690) | 檔案層級註冊；Hook.Add("client.disconnected", "barowardrobeswitcher.v2-disconnected", | `function(client)` | 執行回呼；本體起始：`local session = sessionsByClient[client] if session == nil then return end`。 | `releaseSessionCrewRuntimes`、`clearActiveRuntime`、`operationCacheNow`、`pruneOperationCaches` |
| [L2703](../../Lua/WardrobeSwitcherServer.lua#L2703) | 檔案層級註冊；Hook.Add("character.created", "barowardrobeswitcher.v2-character-created", | `function(character)` | 執行回呼；本體起始：`local attempts = 0 local function attemptRebind()`。 | `attemptRebind`、`rebindCreatedCharacter`、`crewDivingProfile`、`broadcastCrewDivingState` |
| [L2724](../../Lua/WardrobeSwitcherServer.lua#L2724) | 檔案層級註冊；Hook.Add("roundStart", "barowardrobeswitcher.v2-round-start", | `function()` | 執行回呼；本體起始：`roundReactivationGeneration = roundReactivationGeneration + 1 local generation = roundReactivationGeneration`。 | `handleGameSessionChange`、`clearRoundRuntime`、`restoreCrewRuntimes`、`connectedClients`、`scheduleSessionReactivation`、`sessionFor`、`sendCrewDivingSnapshot` |
| [L2736](../../Lua/WardrobeSwitcherServer.lua#L2736) | 檔案層級註冊；Hook.Add("roundEnd", "barowardrobeswitcher.v2-round-end", | `function()` | 執行回呼；本體起始：`roundReactivationGeneration = roundReactivationGeneration + 1 clearRoundRuntime()`。 | `clearRoundRuntime` |
