# C# 客戶端函式

[返回程式導覽](../CODEMAP.md)

共 284 個具名函式／方法，包含建構函式、區域函式、多載及 adapter。

用途按目前原碼整理；簽章保留參數名稱，定位列為檔案內的定義起始行。呼叫欄僅列索引內的部分直接呼叫，方便追查，不代表完整執行期呼叫圖。

## WardrobeDivingProfiles.cs

來源：[CSharp/Client/WardrobeDivingProfiles.cs](../../CSharp/Client/WardrobeDivingProfiles.cs)

| 函式／方法（含參數） | 用途 | 相關呼叫 | 定位 |
|---|---|---|---|
| `WardrobePersistence · public static string GetDivingProfilesPath()` | 回傳本機 DivingProfiles.json 的完整路徑。 | `GetStorageDirectory` | [L18](../../CSharp/Client/WardrobeDivingProfiles.cs#L18) |
| `WardrobePersistence · public static string LoadDivingProfile(string profileKey)` | 以雜湊後的角色設定鍵查找潛水外觀，轉成 Lua 橋接字串；失敗回傳空字串並記錄原因。 | `ClearLastError`、`HashRequiredKey`、`ReadDivingProfiles`、`EncodeDivingProfile`、`LogPersistenceError` | [L23](../../CSharp/Client/WardrobeDivingProfiles.cs#L23) |
| `WardrobePersistence · public static bool SaveDivingProfile(string profileKey, int mode, string encodedLook)` | 驗證模式和外觀，新增或更新該角色的潛水設定，再安全寫入 JSON。 | `ClearLastError`、`HashRequiredKey`、`ParseClientLook`、`ValidateDocument`、`ReadDivingProfiles`、`HasAnySlot`、`WriteDivingProfiles`、`Add` 等 | [L42](../../CSharp/Client/WardrobeDivingProfiles.cs#L42) |
| `WardrobePersistence · private static DivingProfilesDocument ReadDivingProfiles()` | 讀取、反序列化並驗證潛水設定；損壞檔案進入隔離流程。 | `GetDivingProfilesPath`、`CreateEmptyDivingProfiles`、`ReadSchemaVersion`、`ValidateDivingProfiles`、`QuarantineCorruptFile` | [L92](../../CSharp/Client/WardrobeDivingProfiles.cs#L92) |
| `WardrobePersistence · private static void WriteDivingProfiles(DivingProfilesDocument document)` | 驗證整份潛水設定後呼叫共用的安全 JSON 寫檔流程。 | `ValidateDivingProfiles`、`WriteJson`、`GetDivingProfilesPath` | [L121](../../CSharp/Client/WardrobeDivingProfiles.cs#L121) |
| `WardrobePersistence · private static DivingProfilesDocument CreateEmptyDivingProfiles()` | 建立目前格式的空潛水設定文件。 | — | [L130](../../CSharp/Client/WardrobeDivingProfiles.cs#L130) |
| `WardrobePersistence · private static void ValidateDivingProfiles(DivingProfilesDocument document)` | 檢查潛水設定的版本、數量、重複鍵、模式與內嵌外觀。 | `ValidateHash`、`Add`、`CreateAttachmentVisibility`、`ValidateDocument`、`CopySlots`、`CopyColors` | [L139](../../CSharp/Client/WardrobeDivingProfiles.cs#L139) |
| `WardrobePersistence · private static string EncodeDivingProfile(DivingProfile profile)` | 將潛水模式和外觀編成 Lua 可讀的橋接字串。 | `AppendEncodedSlots`、`AppendEncodedColors` | [L177](../../CSharp/Client/WardrobeDivingProfiles.cs#L177) |

## WardrobeFashionCapture.cs

來源：[CSharp/Client/WardrobeFashionCapture.cs](../../CSharp/Client/WardrobeFashionCapture.cs)

| 函式／方法（含參數） | 用途 | 相關呼叫 | 定位 |
|---|---|---|---|
| `VisualOverride · public static void ClearCharacter(Character character)` | 釋放指定角色的外觀 session，移除表中紀錄並刷新穿戴顯示。 | `Dispose`、`RefreshWearables` | [L25](../../CSharp/Client/WardrobeFashionCapture.cs#L25) |
| `VisualOverride · public static void PruneStaleCharacters()` | 找出已移除的角色，釋放它們持有的外觀資源。 | `Dispose` | [L36](../../CSharp/Client/WardrobeFashionCapture.cs#L36) |
| `VisualOverride · private static RenderSession GetOrCreateSession(Character character)` | 取得角色的渲染 session；不存在時建立並加入角色表。 | `RenderSession` | [L50](../../CSharp/Client/WardrobeFashionCapture.cs#L50) |
| `VisualOverride · private static RenderSession GetCaptureSession(Character character)` | 優先取得待提交的擷取 session，否則使用目前 session。 | `GetOrCreateSession` | [L61](../../CSharp/Client/WardrobeFashionCapture.cs#L61) |
| `VisualOverride · public static bool BeginFashionTransaction(Character character)` | 建立待提交的外觀擷取，保留目前已生效的外觀供失敗時繼續使用。 | `HasCapability`、`GetOrCreateSession`、`BeginPendingCapture`、`Log` | [L66](../../CSharp/Client/WardrobeFashionCapture.cs#L66) |
| `VisualOverride · public static bool CommitFashionTransaction(Character character)` | 驗證待提交資料，成功後取代舊 session 並釋放舊資源。 | `DetachPendingCapture`、`Validate`、`HasFashionPayload`、`Dispose`、`Log`、`MarkCommitted` | [L83](../../CSharp/Client/WardrobeFashionCapture.cs#L83) |
| `VisualOverride · public static bool CanReuseCapturedFashion(Character character)` | 判斷已提交 session 是否仍可重用，避免重新擷取貼圖及建立暫時物品。 | `HasCapability`、`HasFashionPayload`、`Validate` | [L106](../../CSharp/Client/WardrobeFashionCapture.cs#L106) |
| `VisualOverride · public static bool AbortFashionTransaction(Character character)` | 放棄待提交的擷取，保留先前已提交外觀。 | `AbortPendingCapture`、`Log` | [L120](../../CSharp/Client/WardrobeFashionCapture.cs#L120) |
| `VisualOverride · public static int CaptureFashionItem(Character character, Item item)` | 從現存裝備擷取外觀；不取得或刪除玩家物品的所有權。 | `CaptureFashionItemCore` | [L131](../../CSharp/Client/WardrobeFashionCapture.cs#L131) |
| `VisualOverride · private static int CaptureFashionItemCore( Character character, Item item, bool takeOwnership, out bool capturedSuccessfully)` | 建立獨立貼圖描述，擷取動畫及音效，記住遮罩與來源；任一步失敗會標記 session 無效。 | `HasCapability`、`GetCaptureSession`、`MarkInvalid`、`Log`、`IsEquipmentSprite`、`IsSealedSuit`、`TryCreate`、`Dispose` 等 | [L136](../../CSharp/Client/WardrobeFashionCapture.cs#L136) |
| `VisualOverride · public static int CaptureFashionPrefab(Character character, string identifier)` | 以物品識別碼重建外觀；有 packedColor 的多載同時還原保存色彩。 | `CaptureFashionPrefabCore` | [L224](../../CSharp/Client/WardrobeFashionCapture.cs#L224) |
| `VisualOverride · public static int CaptureFashionPrefab(Character character, string identifier, uint packedColor)` | 以物品識別碼重建外觀；有 packedColor 的多載同時還原保存色彩。 | `CaptureFashionPrefabCore` | [L229](../../CSharp/Client/WardrobeFashionCapture.cs#L229) |
| `VisualOverride · private static int CaptureFashionPrefabCore( Character character, string identifier, uint? packedColor)` | 建立暫時 Item 並釋放其 entity ID，擷取成功後交由 session 管理，失敗則清除暫時物品。 | `GetCaptureSession`、`MarkInvalid`、`Log`、`CaptureFashionItemCore` | [L234](../../CSharp/Client/WardrobeFashionCapture.cs#L234) |
| `VisualOverride · public static bool CaptureEmptyFashion(Character character)` | 將目前擷取標記為合法的空外觀。 | `HasCapability`、`GetCaptureSession`、`Log` | [L293](../../CSharp/Client/WardrobeFashionCapture.cs#L293) |
| `VisualOverride · public static bool SetFashionSlots( Character character, string savedSlotsCsv, string emptySlotsCsv, bool forceHideEmptySlots = false)` | 解析保存欄位與空欄位，更新遮罩政策並清除需重新註冊的裝備效果快取。 | `GetCaptureSession`、`ParseSlotCsv`、`Log`、`DescribeSavedSlots`、`DescribeEmptySlots` | [L303](../../CSharp/Client/WardrobeFashionCapture.cs#L303) |
| `VisualOverride · public static bool IsDivingSuitItem(Item item)` | 透過共用裝備分類判斷是否為密閉潛水服。 | `IsSealedSuit` | [L332](../../CSharp/Client/WardrobeFashionCapture.cs#L332) |
| `VisualOverride · public static bool SetAttachmentVisibility( Character character, int forceHideMask, int forceShowMask)` | 驗證頭髮、鬍鬚及臉部附件的強制顯示／隱藏位元，寫入擷取 session。 | `Log`、`GetCaptureSession` | [L337](../../CSharp/Client/WardrobeFashionCapture.cs#L337) |
| `VisualOverride · public static bool SetUseFashionMovementAnimations(Character character, bool enabled)` | 設定移動動畫來源；改用真裝備時清除外觀移動動畫快取。 | — | [L374](../../CSharp/Client/WardrobeFashionCapture.cs#L374) |
| `VisualOverride · public static bool SetUseFashionFootstepSounds(Character character, bool enabled)` | 設定腳步音效來源並更新相關 session 狀態。 | `HasCapability` | [L387](../../CSharp/Client/WardrobeFashionCapture.cs#L387) |
| `VisualOverride · public static bool SetHideHair(Character character, bool hideHair)` | 把舊版隱藏頭髮選項轉交目前的附件可見性介面。 | `SetAttachmentVisibility` | [L401](../../CSharp/Client/WardrobeFashionCapture.cs#L401) |
| `VisualOverride · public static bool ApplyFashionItemVisual(Character character, Item item, bool carrier)` | 登記真裝備需被抑制的動畫及音效；carrier 參數可觸發外觀啟用。 | `HasCapability`、`HasFashionPayload`、`RegisterSuppressedEquipmentAnimations`、`RegisterSuppressedEquipmentSounds`、`RegisterSuppressedEquipmentComponentSounds`、`Log` | [L411](../../CSharp/Client/WardrobeFashionCapture.cs#L411) |
| `VisualOverride · public static bool RemoveFashionItemVisual(Character character, Item item)` | 解除已脫下裝備的效果抑制，避免保留過期元件參照。 | — | [L431](../../CSharp/Client/WardrobeFashionCapture.cs#L431) |
| `VisualOverride · public static bool ActivateFashionVisual(Character character)` | 驗證外觀資料和橋接能力後啟用 session，必要時建立相容附肢。 | `HasCapability`、`HasFashionPayload`、`Log`、`Validate`、`EnsureXdsFashionAppendage` | [L470](../../CSharp/Client/WardrobeFashionCapture.cs#L470) |
| `VisualOverride · private static bool EnsureXdsFashionAppendage(Character character, RenderSession session)` | 為已保存的 XDS-01 背包外觀建立所需附肢，並將清理責任交給 session。 | `RemoveOwnedAppendages`、`Log`、`SetOwnedAppendages` | [L504](../../CSharp/Client/WardrobeFashionCapture.cs#L504) |

## WardrobeFashionEffects.cs

來源：[CSharp/Client/WardrobeFashionEffects.cs](../../CSharp/Client/WardrobeFashionEffects.cs)

| 函式／方法（含參數） | 用途 | 相關呼叫 | 定位 |
|---|---|---|---|
| `VisualOverride · internal static void KeepFashionEffectsAlive(AnimController animController)` | 在角色動畫更新後維持外觀動畫及循環音效。 | `KeepFashionAnimationsAlive`、`KeepFashionSoundsAlive` | [L25](../../CSharp/Client/WardrobeFashionEffects.cs#L25) |
| `VisualOverride · internal static bool ShouldLoadTemporaryAnimation(AnimController animController, object animationInfo)` | 依外觀 session 的策略決定是否允許真裝備載入臨時動畫。 | `HasCapability`、`IsLargeEquipmentMovementAnimation`、`LogAnimationError` | [L36](../../CSharp/Client/WardrobeFashionEffects.cs#L36) |
| `VisualOverride · internal static void PreserveEquipmentMovementSpeed( AnimController animController, AnimationType type, ref float speed)` | 套用外觀動畫時，維持角色真裝備決定的移動速度限制。 | `HasCapability`、`LimitEquipmentMovementSpeed` | [L80](../../CSharp/Client/WardrobeFashionEffects.cs#L80) |
| `VisualOverride · private static void KeepFashionAnimationsAlive(AnimController animController)` | 對已擷取的動畫維持載入及優先權，處理反射呼叫失敗。 | `HasCapability`、`LogAnimationError` | [L90](../../CSharp/Client/WardrobeFashionEffects.cs#L90) |
| `VisualOverride · private static void KeepFashionSoundsAlive(AnimController animController)` | 維持已擷取的循環音效，避免每幀重建觸發資料。 | `TryPlaySpecificFashionSound`、`TryPlaySpecificFashionComponentSound` | [L128](../../CSharp/Client/WardrobeFashionEffects.cs#L128) |
| `VisualOverride · private static bool HasFashionPayload(Character character)` | 判斷指定角色或 session 是否包含合法空外觀、貼圖、動畫或音效資料。 | — | [L157](../../CSharp/Client/WardrobeFashionEffects.cs#L157) |
| `VisualOverride · private static bool HasFashionPayload(RenderSession session)` | 判斷指定角色或 session 是否包含合法空外觀、貼圖、動畫或音效資料。 | — | [L164](../../CSharp/Client/WardrobeFashionEffects.cs#L164) |
| `VisualOverride · private static int CaptureFashionAnimations(RenderSession session, Item item)` | 從物品的狀態效果挑出可用動畫，並分類移動動畫。 | `HasCapability`、`IsStateDependentStatusEffect`、`ShouldCaptureAnimation`、`BoostFashionAnimationPriority`、`Add`、`IsMovementAnimation` | [L174](../../CSharp/Client/WardrobeFashionEffects.cs#L174) |
| `VisualOverride · private static int CaptureFashionSounds(RenderSession session, Item item)` | 從物品狀態效果擷取符合外觀政策的音效，記住循環來源。 | `HasCapability`、`ShouldCaptureItemSounds`、`HasSounds`、`IsStateDependentStatusEffect`、`Add`、`HasLoopingSound` | [L208](../../CSharp/Client/WardrobeFashionEffects.cs#L208) |
| `VisualOverride · private static int CaptureFashionComponentSounds(RenderSession session, Item item)` | 擷取物品元件音效與動作類型，排除不適合複製的功能音效。 | `HasCapability`、`ShouldCaptureItemSounds`、`HasComponentSounds`、`GetComponentSoundTypes`、`Add`、`ShouldKeepComponentLoopAlive`、`HasLoopingComponentSound` | [L242](../../CSharp/Client/WardrobeFashionEffects.cs#L242) |
| `VisualOverride · private static void RegisterSuppressedEquipmentAnimations(Character character, Item item)` | 登記真裝備應被外觀替代的動畫及其原始優先權。 | `ShouldSuppressEquipmentAnimation`、`Add` | [L274](../../CSharp/Client/WardrobeFashionEffects.cs#L274) |
| `VisualOverride · private static void RegisterSuppressedEquipmentSounds(Character character, Item item)` | 登記真裝備狀態效果中需被外觀替代的音效。 | `HasAnyFashionSound`、`HasSounds`、`IsFashionStatusSound`、`IsStateDependentStatusEffect`、`HasLoopingSound`、`Add` | [L298](../../CSharp/Client/WardrobeFashionEffects.cs#L298) |
| `VisualOverride · private static void RegisterSuppressedEquipmentComponentSounds(Character character, Item item)` | 登記真裝備元件中需被外觀替代的音效。 | `HasAnyFashionSound`、`HasComponentSounds`、`IsFashionComponentSound`、`GetComponentSoundTypes`、`HasLoopingComponentSound`、`Add` | [L334](../../CSharp/Client/WardrobeFashionEffects.cs#L334) |
| `VisualOverride · internal static bool ShouldPlayOriginalStatusEffectSound(StatusEffect statusEffect, Entity entity, Hull hull, Vector2 worldPosition)` | 在狀態效果播音前判斷保留原音效、略過或改播外觀音效；功能警報仍交給原遊戲。 | `HasCapability`、`IsStateDependentStatusEffect`、`HasAnyFashionSound`、`TryPlayReplacementFashionSound`、`TryPlayReplacementFashionComponentSound`、`LogSoundError` | [L358](../../CSharp/Client/WardrobeFashionEffects.cs#L358) |
| `VisualOverride · internal static bool ShouldPlayOriginalItemComponentSound(ItemComponent component, ActionType actionType, Character user)` | 在元件播音前依角色 session、動作及音效來源決定是否使用替代音效。 | `HasCapability`、`HasAnyFashionSound`、`TryPlayReplacementFashionComponentSound`、`TryPlayReplacementFashionSound`、`LogSoundError` | [L405](../../CSharp/Client/WardrobeFashionEffects.cs#L405) |
| `VisualOverride · private static bool HasAnyFashionSound(Character character)` | 判斷角色 session 是否包含狀態效果或元件的外觀音效。 | — | [L451](../../CSharp/Client/WardrobeFashionEffects.cs#L451) |
| `VisualOverride · private static bool IsFashionStatusSound(Character character, StatusEffect statusEffect)` | 判斷指定狀態效果是否已登記為該角色的外觀音效來源。 | — | [L458](../../CSharp/Client/WardrobeFashionEffects.cs#L458) |
| `VisualOverride · private static bool IsFashionComponentSound(Character character, ItemComponent component)` | 判斷指定元件是否已登記為該角色的外觀音效來源。 | — | [L466](../../CSharp/Client/WardrobeFashionEffects.cs#L466) |
| `VisualOverride · private static bool TryPlayReplacementFashionSound( RenderSession session, List<StatusEffect> fashionSounds, Entity entity, Hull hull, Vector2 worldPosition)` | 尋找可替代真裝備的狀態效果音效並嘗試播放。 | `TryPlaySpecificFashionSound` | [L474](../../CSharp/Client/WardrobeFashionEffects.cs#L474) |
| `VisualOverride · private static bool TryPlaySpecificFashionSound( RenderSession session, StatusEffect statusEffect, Entity entity, Hull hull, Vector2 worldPosition, bool forceRestart = false)` | 透過遊戲音效介面播放指定外觀狀態效果，維護遞迴保護及錯誤處理。 | `LogSoundError` | [L507](../../CSharp/Client/WardrobeFashionEffects.cs#L507) |
| `VisualOverride · private static bool TryPlayReplacementFashionComponentSound( RenderSession session, List<(ItemComponent Component, ActionType ActionType)> fashionSounds, ActionType actionType, Character user)` | 按動作類型尋找並播放可替代真裝備的元件音效。 | `TryPlaySpecificFashionComponentSound` | [L558](../../CSharp/Client/WardrobeFashionEffects.cs#L558) |
| `VisualOverride · private static bool TryPlaySpecificFashionComponentSound( Character character, ItemComponent component, ActionType actionType, Character user)` | 播放指定外觀元件及動作的音效，使用遞迴保護避免重新進入替代流程。 | `LogSoundError` | [L585](../../CSharp/Client/WardrobeFashionEffects.cs#L585) |
| `VisualOverride · private static bool HasSounds(StatusEffect statusEffect)` | 透過已綁定的反射欄位確認狀態效果是否有音效。 | `LogSoundError` | [L604](../../CSharp/Client/WardrobeFashionEffects.cs#L604) |
| `VisualOverride · private static bool HasComponentSounds(ItemComponent component)` | 確認物品元件是否具有可用的音效集合。 | `LogSoundError` | [L623](../../CSharp/Client/WardrobeFashionEffects.cs#L623) |
| `VisualOverride · private static bool HasLoopingSound(StatusEffect statusEffect)` | 檢查狀態效果是否包含循環音效。 | `LogSoundError` | [L638](../../CSharp/Client/WardrobeFashionEffects.cs#L638) |
| `VisualOverride · private static bool HasLoopingComponentSound(ItemComponent component, ActionType actionType)` | 檢查元件在指定動作下是否包含循環音效。 | `LogSoundError` | [L653](../../CSharp/Client/WardrobeFashionEffects.cs#L653) |
| `VisualOverride · private static IEnumerable<ActionType> GetComponentSoundTypes(ItemComponent component)` | 列舉物品元件已有音效的動作類型。 | `LogSoundError` | [L674](../../CSharp/Client/WardrobeFashionEffects.cs#L674) |

## WardrobeFileLogger.cs

來源：[CSharp/Client/WardrobeFileLogger.cs](../../CSharp/Client/WardrobeFileLogger.cs)

| 函式／方法（含參數） | 用途 | 相關呼叫 | 定位 |
|---|---|---|---|
| `WardrobeFileLogger · public static string GetPath()` | 回傳 WardrobeClient.log 的完整路徑。 | `WardrobePersistence.GetStorageDirectory` | [L31](../../CSharp/Client/WardrobeFileLogger.cs#L31) |
| `WardrobeFileLogger · public static bool Write(string level, string message)` | 附加時間、等級及訊息至 UTF-8 日誌；鎖定寫入，失敗回傳 false 而不打斷遊戲。 | `GetPath` | [L36](../../CSharp/Client/WardrobeFileLogger.cs#L36) |
| `WardrobeFileLogger · public static void Log(string message)` | 以 INFO 等級寫入模組日誌。 | `Write` | [L59](../../CSharp/Client/WardrobeFileLogger.cs#L59) |

## WardrobeFunctionalFashionFilters.cs

來源：[CSharp/Client/WardrobeFunctionalFashionFilters.cs](../../CSharp/Client/WardrobeFunctionalFashionFilters.cs)

| 函式／方法（含參數） | 用途 | 相關呼叫 | 定位 |
|---|---|---|---|
| `FashionEffectPolicy · public static bool ShouldCaptureAnimation(Item item, object animationInfo)` | 依是否密閉服及動畫種類，排除不應作為外觀複製的移動動畫。 | `IsSealedSuit`、`IsMovementAnimation`、`IsLargeEquipmentMovementAnimation` | [L35](../../CSharp/Client/WardrobeFunctionalFashionFilters.cs#L35) |
| `FashionEffectPolicy · public static bool ShouldCaptureItemSounds(Item item)` | 判斷物品的音效是否適合作為純外觀音效。 | `IsSealedSuit`、`NormalizedItemText` | [L108](../../CSharp/Client/WardrobeFunctionalFashionFilters.cs#L108) |
| `FashionEffectPolicy · public static bool ShouldSuppressEquipmentAnimation(Item item, object animationInfo)` | 只對符合政策的密閉服移動動畫進行替代。 | `IsSealedSuit`、`IsMovementAnimation` | [L43](../../CSharp/Client/WardrobeFunctionalFashionFilters.cs#L43) |
| `FashionEffectPolicy · public static bool ShouldKeepComponentLoopAlive(ActionType actionType)` | 限定 Always、OnWearing 動作可由外觀流程持續維持循環音效。 | — | [L48](../../CSharp/Client/WardrobeFunctionalFashionFilters.cs#L48) |
| `FashionEffectPolicy · internal static bool IsStateDependentStatusEffect(StatusEffect statusEffect)` | 檢查條件、所需物品及環境限制；無法檢查時保守交還原遊戲處理。 | `HasEntriesOrCannotInspect`、`IsEnabledOrCannotInspect`、`HasTextOrCannotInspect` | [L55](../../CSharp/Client/WardrobeFunctionalFashionFilters.cs#L55) |
| `FashionEffectPolicy · internal static bool IsSealedSuit(Item item)` | 以標籤及元件等資訊辨識密閉服，必要時使用文字相容判斷。 | `HasTag`、`NormalizedItemText` | [L94](../../CSharp/Client/WardrobeFunctionalFashionFilters.cs#L94) |
| `FashionEffectPolicy · private static bool HasTag(Item item, Identifier tag)` | 檢查物品 prefab 是否具有指定標籤。 | — | [L118](../../CSharp/Client/WardrobeFunctionalFashionFilters.cs#L118) |
| `FashionEffectPolicy · private static bool HasEntriesOrCannotInspect(FieldInfo field, StatusEffect statusEffect)` | 讀取反射集合欄位；集合有內容或讀取失敗均回傳保守判斷。 | — | [L123](../../CSharp/Client/WardrobeFunctionalFashionFilters.cs#L123) |
| `FashionEffectPolicy · private static bool IsEnabledOrCannotInspect(FieldInfo field, StatusEffect statusEffect)` | 讀取反射布林欄位；啟用或無法確認時採保守判斷。 | — | [L135](../../CSharp/Client/WardrobeFunctionalFashionFilters.cs#L135) |
| `FashionEffectPolicy · private static bool HasTextOrCannotInspect(FieldInfo field, StatusEffect statusEffect)` | 檢查反射欄位是否有文字限制；無法確認時採保守判斷。 | — | [L142](../../CSharp/Client/WardrobeFunctionalFashionFilters.cs#L142) |
| `FashionEffectPolicy · private static string NormalizedItemText(Item item)` | 合併物品識別碼及名稱，產生相容比對用文字。 | — | [L150](../../CSharp/Client/WardrobeFunctionalFashionFilters.cs#L150) |
| `FashionEffectPolicy · internal static bool IsMovementAnimation(object animationInfo)` | 判斷動畫資訊是否屬於角色移動動畫。 | — | [L157](../../CSharp/Client/WardrobeFunctionalFashionFilters.cs#L157) |
| `FashionEffectPolicy · internal static bool IsLargeEquipmentMovementAnimation(object animationInfo)` | 辨識大型裝備會影響步態的移動動畫。 | `IsMovementAnimation` | [L172](../../CSharp/Client/WardrobeFunctionalFashionFilters.cs#L172) |

## WardrobePatches.cs

來源：[CSharp/Client/WardrobePatches.cs](../../CSharp/Client/WardrobePatches.cs)

| 函式／方法（含參數） | 用途 | 相關呼叫 | 定位 |
|---|---|---|---|
| `LimbDrawWearablePatch · private static bool Prefix(Limb __instance, ref WearableSprite wearable)` | 在原遊戲方法執行前調整輸入或決定是否略過原行為；對應 LimbDrawWearablePatch。 | `VisualOverride.TryOverrideDrawWearable` | [L24](../../CSharp/Client/WardrobePatches.cs#L24) |
| `LimbDrawPatch · private static bool Prefix(Limb __instance, out State __state)` | 在原遊戲方法執行前調整輸入或決定是否略過原行為；對應 LimbDrawPatch。 | `VisualOverride.ShouldSuppressAfflictionAppendage`、`VisualOverride.ShouldSuppressEquipmentAppendage`、`VisualOverride.BeginHuskSpriteSuppression`、`VisualOverride.BeginLimbDraw` | [L50](../../CSharp/Client/WardrobePatches.cs#L50) |
| `LimbDrawPatch · private static void Postfix( Limb __instance, SpriteBatch spriteBatch, Camera cam, Color? overrideColor, bool disableDeformations, State __state)` | 在原遊戲方法完成後更新外觀效果或結果；對應 LimbDrawPatch。 | `VisualOverride.DrawMissingFashionSprites` | [L63](../../CSharp/Client/WardrobePatches.cs#L63) |
| `LimbDrawPatch · private static Exception Finalizer( Limb __instance, Exception __exception, State __state)` | 在正常或例外離開時還原 transaction，保留原始例外；對應 LimbDrawPatch。 | `VisualOverride.EndLimbDraw`、`VisualOverride.EndHuskSpriteSuppression` | [L78](../../CSharp/Client/WardrobePatches.cs#L78) |
| `AfflictionBodyTintPatch · private static void Postfix(Affliction __instance, ref Color __result)` | 在原遊戲方法完成後更新外觀效果或結果；對應 AfflictionBodyTintPatch。 | `VisualOverride.SuppressHuskTint` | [L96](../../CSharp/Client/WardrobePatches.cs#L96) |
| `AfflictionFaceTintPatch · private static void Postfix(Affliction __instance, ref Color __result)` | 在原遊戲方法完成後更新外觀效果或結果；對應 AfflictionFaceTintPatch。 | `VisualOverride.SuppressHuskTint` | [L104](../../CSharp/Client/WardrobePatches.cs#L104) |
| `AnimControllerUpdateAnimationsPatch · private static void Postfix(AnimController __instance)` | 在原遊戲方法完成後更新外觀效果或結果；對應 AnimControllerUpdateAnimationsPatch。 | `VisualOverride.KeepFashionEffectsAlive` | [L112](../../CSharp/Client/WardrobePatches.cs#L112) |
| `AnimControllerTryLoadTemporaryAnimationPatch · private static bool Prefix(AnimController __instance, object __0, ref bool __result)` | 在原遊戲方法執行前調整輸入或決定是否略過原行為；對應 AnimControllerTryLoadTemporaryAnimationPatch。 | `VisualOverride.ShouldLoadTemporaryAnimation` | [L120](../../CSharp/Client/WardrobePatches.cs#L120) |
| `AnimControllerGetSpeedPatch · private static void Postfix(AnimController __instance, AnimationType __0, ref float __result)` | 在原遊戲方法完成後更新外觀效果或結果；對應 AnimControllerGetSpeedPatch。 | `VisualOverride.PreserveEquipmentMovementSpeed` | [L132](../../CSharp/Client/WardrobePatches.cs#L132) |
| `StatusEffectPlaySoundPatch · private static bool Prefix(StatusEffect __instance, Entity entity, Hull hull, Vector2 worldPosition)` | 在原遊戲方法執行前調整輸入或決定是否略過原行為；對應 StatusEffectPlaySoundPatch。 | `VisualOverride.ShouldPlayOriginalStatusEffectSound` | [L140](../../CSharp/Client/WardrobePatches.cs#L140) |
| `ItemComponentPlaySoundPatch · private static bool Prefix(ItemComponent __instance, ActionType type, Character user)` | 在原遊戲方法執行前調整輸入或決定是否略過原行為；對應 ItemComponentPlaySoundPatch。 | `VisualOverride.ShouldPlayOriginalItemComponentSound` | [L148](../../CSharp/Client/WardrobePatches.cs#L148) |
| `RagdollPlayImpactSoundPatch · private static void Prefix(Limb __0, out VisualOverride.FootstepSoundTransaction __state)` | 在原遊戲方法執行前調整輸入或決定是否略過原行為；對應 RagdollPlayImpactSoundPatch。 | `VisualOverride.BeginFootstepSound` | [L156](../../CSharp/Client/WardrobePatches.cs#L156) |
| `RagdollPlayImpactSoundPatch · private static Exception Finalizer( Exception __exception, VisualOverride.FootstepSoundTransaction __state)` | 在正常或例外離開時還原 transaction，保留原始例外；對應 RagdollPlayImpactSoundPatch。 | `VisualOverride.EndFootstepSound` | [L161](../../CSharp/Client/WardrobePatches.cs#L161) |

## WardrobePersistence.cs

來源：[CSharp/Client/WardrobePersistence.cs](../../CSharp/Client/WardrobePersistence.cs)

| 函式／方法（含參數） | 用途 | 相關呼叫 | 定位 |
|---|---|---|---|
| `WardrobePersistence · public static string GetVersion()` | 回傳所屬橋接類別的版本字串。 | — | [L50](../../CSharp/Client/WardrobePersistence.cs#L50) |
| `WardrobePersistence · public static string GetLastError()` | 回傳最近一次持久化失敗原因，供 Lua 顯示及診斷。 | — | [L55](../../CSharp/Client/WardrobePersistence.cs#L55) |
| `WardrobePersistence · public static string GetStorageDirectory()` | 取得使用者 LocalApplicationData 下的模組存檔目錄；測試執行器可指定隔離根目錄。 |  | [L60](../../CSharp/Client/WardrobePersistence.cs#L60) |
| `WardrobePersistence · public static string GetClientLookPath()` | 回傳 ClientLook.json 的完整路徑。 | `GetStorageDirectory` | [L76](../../CSharp/Client/WardrobePersistence.cs#L76) |
| `WardrobePersistence · public static string LoadClientLook()` | 讀取客戶端外觀，處理舊格式遷移與損壞隔離，轉成 Lua 橋接字串。 | `ClearLastError`、`GetClientLookPath`、`ReadClientDocument`、`WriteJson`、`LogPersistenceInfo`、`HasAnySlot`、`EncodeClientLook`、`QuarantineCorruptFile` 等 | [L81](../../CSharp/Client/WardrobePersistence.cs#L81) |
| `WardrobePersistence · public static bool ClientLookFileExists()` | 檢查客戶端外觀 JSON 是否存在，並保留錯誤診斷。 | `ClearLastError`、`GetClientLookPath`、`LogPersistenceError` | [L124](../../CSharp/Client/WardrobePersistence.cs#L124) |
| `WardrobePersistence · public static bool SaveClientLook(string encodedLook)` | 解析並驗證橋接外觀字串，安全寫入目前格式的 ClientLook.json。 | `ClearLastError`、`ParseClientLook`、`HasAnySlot`、`ClearClientLook`、`ValidateDocument`、`WriteJson`、`GetClientLookPath`、`LogPersistenceError` | [L138](../../CSharp/Client/WardrobePersistence.cs#L138) |
| `WardrobePersistence · public static bool SaveMigratedClientLook(string encodedLook, string legacyPath)` | 先保存遷移結果，再為指定的舊文字存檔建立備份。 | `SaveClientLook`、`LogPersistenceInfo`、`LogPersistenceError` | [L159](../../CSharp/Client/WardrobePersistence.cs#L159) |
| `WardrobePersistence · public static bool QuarantineLegacyClientLook(string legacyPath)` | 確認是允許的舊存檔路徑後隔離損壞文字檔，避免誤移動任意檔案。 | `ClearLastError`、`LogPersistenceInfo`、`LogPersistenceError` | [L194](../../CSharp/Client/WardrobePersistence.cs#L194) |
| `WardrobePersistence · public static bool ClearClientLook()` | 寫入清除後的外觀狀態，維持安全替換與失敗診斷。 | `ClearLastError`、`WriteJson`、`GetClientLookPath`、`CreateAttachmentVisibility`、`CreateEmptySlots`、`CreateEmptyColors`、`LogPersistenceError` | [L224](../../CSharp/Client/WardrobePersistence.cs#L224) |
| `WardrobePersistence · private static ClientLookDocument ReadClientDocument(string path, out int migratedFromVersion)` | 讀取 JSON 格式版本，驗證目前格式或遷移舊版文件。 | `ReadSchemaVersion`、`ValidateDocument`、`CreateEmptyColors`、`CreateAttachmentVisibility`、`MigrateLegacyDocument` | [L248](../../CSharp/Client/WardrobePersistence.cs#L248) |
| `WardrobePersistence · private static void WriteJson<T>(string path, T value)` | 序列化至同目錄暫存檔，沖寫後原子替換目標；處理備份、平台備援及暫存清理。 | `Write``ReplaceWithPortableFallback` | [L322](../../CSharp/Client/WardrobePersistence.cs#L322) |
| `WardrobePersistence · private static ClientLookDocument ParseClientLook(Dictionary<string, string> parts)` | 由已解析的欄位建立外觀資料，避免重複解析同一字串。 | `GetBoolean`、`GetBooleanOrDefault`、`ParseAttachmentVisibility`、`ParseSlots`、`ParseColors` | [L367](../../CSharp/Client/WardrobePersistence.cs#L367) |
| `WardrobePersistence · private static string EncodeClientLook(ClientLookDocument document)` | 將外觀文件編成 Lua 橋接字串，保留啟用意圖及各項外觀偏好。 | `LegacyHideHair`、`AppendEncodedSlots`、`AppendEncodedColors` | [L384](../../CSharp/Client/WardrobePersistence.cs#L384) |
| `WardrobePersistence · private static void AppendEncodedSlots(List<string> parts, Dictionary<string, string> slots)` | 把六個管理欄位的物品識別碼附加到橋接字串片段。 | `Add`、`Escape` | [L408](../../CSharp/Client/WardrobePersistence.cs#L408) |
| `WardrobePersistence · private static void AppendEncodedColors( List<string> parts, Dictionary<string, uint?> colors)` | 只附加有保存值的欄位色彩，保留缺少色彩的舊版語意。 | `Add` | [L420](../../CSharp/Client/WardrobePersistence.cs#L420) |
| `WardrobePersistence · private static Dictionary<string, string> ParseSlots(Dictionary<string, string> parts)` | 解析橋接資料的各裝備欄位，解碼物品識別碼。 | `CreateEmptySlots`、`Unescape` | [L434](../../CSharp/Client/WardrobePersistence.cs#L434) |
| `WardrobePersistence · private static Dictionary<string, uint?> ParseColors(Dictionary<string, string> parts)` | 解析各欄位的 UInt32 色彩；遇到無效格式即拒絕。 | `CreateEmptyColors` | [L448](../../CSharp/Client/WardrobePersistence.cs#L448) |
| `WardrobePersistence · private static Dictionary<string, string> ParseParts(string line)` | 把以分隔符號組成的鍵值字串拆成字典。 | — | [L464](../../CSharp/Client/WardrobePersistence.cs#L464) |
| `WardrobePersistence · private static bool GetBoolean(Dictionary<string, string> parts, string key)` | 讀取橋接字典內明確等於 true 的布林欄位。 | — | [L479](../../CSharp/Client/WardrobePersistence.cs#L479) |
| `WardrobePersistence · private static bool GetBooleanOrDefault( Dictionary<string, string> parts, string key, bool defaultValue)` | 讀取布林欄位，缺少欄位時使用指定預設值。 | — | [L486](../../CSharp/Client/WardrobePersistence.cs#L486) |
| `WardrobePersistence · private static AttachmentVisibilityDocument ParseAttachmentVisibility( Dictionary<string, string> parts)` | 解析附件的 auto／hide／show 政策，兼容舊版 hideHair。 | `CreateAttachmentVisibility`、`GetBoolean`、`ValidateAttachmentVisibility` | [L499](../../CSharp/Client/WardrobePersistence.cs#L499) |
| `WardrobePersistence · private static AttachmentVisibilityDocument CreateAttachmentVisibility(bool hideHair)` | 由舊版頭髮選項建立四種附件的可見性政策。 | — | [L531](../../CSharp/Client/WardrobePersistence.cs#L531) |
| `WardrobePersistence · private static AttachmentVisibilityDocument CopyAttachmentVisibility( AttachmentVisibilityDocument source)` | 複製可見性文件，避免共享可變狀態。 | `ValidateAttachmentVisibility` | [L542](../../CSharp/Client/WardrobePersistence.cs#L542) |
| `WardrobePersistence · private static bool LegacyHideHair(AttachmentVisibilityDocument visibility)` | 把目前附件政策投影成舊版隱藏頭髮值。 | — | [L555](../../CSharp/Client/WardrobePersistence.cs#L555) |
| `WardrobePersistence · private static bool IsVisibilityState(string value)` | 檢查值是否為允許的 auto、hide 或 show。 | — | [L563](../../CSharp/Client/WardrobePersistence.cs#L563) |
| `WardrobePersistence · private static void ValidateAttachmentVisibility(AttachmentVisibilityDocument visibility)` | 驗證四種附件都有合法可見性值。 | `IsVisibilityState` | [L570](../../CSharp/Client/WardrobePersistence.cs#L570) |
| `WardrobePersistence · private static AttachmentVisibilityDocument ReadLegacyAttachmentVisibility(JsonElement root)` | 從舊版 JSON 讀取附件政策，缺少時轉用舊版頭髮旗標。 | `TryGetPropertyIgnoreCase`、`ValidateAttachmentVisibility`、`CreateAttachmentVisibility`、`ReadBoolean` | [L582](../../CSharp/Client/WardrobePersistence.cs#L582) |
| `WardrobePersistence · private static bool HasAnySlot(Dictionary<string, string> slots)` | 確認外觀欄位中是否至少有一個物品識別碼。 | — | [L627](../../CSharp/Client/WardrobePersistence.cs#L627) |
| `WardrobePersistence · private static int ReadSchemaVersion(JsonElement root)` | 安全讀取並檢查 JSON 格式版本。 | — | [L633](../../CSharp/Client/WardrobePersistence.cs#L633) |
| `WardrobePersistence · private static ClientLookDocument MigrateLegacyDocument(JsonElement root)` | 把舊版外觀文件轉成目前文件，補上新欄位的相容預設。 | `CreateEmptySlots`、`TryGetPropertyIgnoreCase`、`ReadLegacyIdentifier`、`ReadBoolean`、`HasAnySlot`、`ReadLegacyAttachmentVisibility`、`CreateEmptyColors` | [L655](../../CSharp/Client/WardrobePersistence.cs#L655) |
| `WardrobePersistence · private static string ReadLegacyIdentifier(JsonElement value)` | 從舊版物品字串或物件中取得識別碼。 | `TryGetPropertyIgnoreCase` | [L694](../../CSharp/Client/WardrobePersistence.cs#L694) |
| `WardrobePersistence · private static bool ReadBoolean(JsonElement root, string name)` | 從 JSON 讀取指定布林欄位。 | `TryGetPropertyIgnoreCase` | [L707](../../CSharp/Client/WardrobePersistence.cs#L707) |
| `WardrobePersistence · private static bool TryGetPropertyIgnoreCase(JsonElement root, string name, out JsonElement value)` | 在舊版 JSON 中以不分大小寫方式尋找欄位。 | — | [L717](../../CSharp/Client/WardrobePersistence.cs#L717) |
| `WardrobePersistence · private static Dictionary<string, string> CreateEmptySlots()` | 建立六個管理欄位皆為空的字典。 | — | [L731](../../CSharp/Client/WardrobePersistence.cs#L731) |
| `WardrobePersistence · private static Dictionary<string, uint?> CreateEmptyColors()` | 建立六個管理欄位皆未指定色彩的字典。 | — | [L741](../../CSharp/Client/WardrobePersistence.cs#L741) |
| `WardrobePersistence · private static void ValidateDocument(ClientLookDocument document)` | 驗證版本、必要欄位、識別碼長度、色彩配對及附件政策。 | `ValidateAttachmentVisibility`、`CreateEmptySlots`、`CreateEmptyColors` | [L751](../../CSharp/Client/WardrobePersistence.cs#L751) |
| `WardrobePersistence · private static void ReplaceWithPortableFallback(string tempPath, string path, string backupPath)` | 原子替換不可用時先備份舊檔，再以覆寫移動完成替換。 | — | [L801](../../CSharp/Client/WardrobePersistence.cs#L801) |
| `WardrobePersistence · private static void QuarantineCorruptFile(string path, Exception reason)` | 將無法讀取的存檔改名隔離並記錄原因；隔離失敗也會記錄。 | `LogPersistenceInfo`、`LogPersistenceError` | [L810](../../CSharp/Client/WardrobePersistence.cs#L810) |
| `WardrobePersistence · private static string Escape(string value)` | 跳脫橋接字串的特殊分隔字元。 | — | [L827](../../CSharp/Client/WardrobePersistence.cs#L827) |
| `WardrobePersistence · private static string Unescape(string value)` | 還原橋接字串被跳脫的特殊字元。 | — | [L838](../../CSharp/Client/WardrobePersistence.cs#L838) |
| `WardrobePersistence · private static void LogPersistenceError(string message, Exception ex)` | 更新最近失敗原因並寫入模組檔案日誌。 | `LogPersistenceInfo` | [L849](../../CSharp/Client/WardrobePersistence.cs#L849) |
| `WardrobePersistence · private static void ClearLastError()` | 清空持久化橋接的上一筆錯誤。 | — | [L855](../../CSharp/Client/WardrobePersistence.cs#L855) |
| `WardrobePersistence · private static void LogPersistenceInfo(string message)` | 將持久化操作訊息寫入模組日誌，日誌失敗不打斷操作。 | `Log` | [L860](../../CSharp/Client/WardrobePersistence.cs#L860) |

## WardrobeRendering.cs

來源：[CSharp/Client/WardrobeRendering.cs](../../CSharp/Client/WardrobeRendering.cs)

| 函式／方法（含參數） | 用途 | 相關呼叫 | 定位 |
|---|---|---|---|
| `FashionSpriteDescriptor · private FashionSpriteDescriptor( WearableSprite sprite, IEnumerable<InvSlotType> allowedSlots, string sourceIdentifier, string sourceContentPackage, string resolvedSpritePath)` | 保存獨立貼圖、來源欄位及相容性中繼資料。 | — | [L17](../../CSharp/Client/WardrobeRendering.cs#L17) |
| `FashionSpriteDescriptor · public bool IsValid(out string error)` | 檢查描述尚未釋放、貼圖已初始化、必要來源及隱藏集合存在。 | — | [L51](../../CSharp/Client/WardrobeRendering.cs#L51) |
| `FashionSpriteDescriptor · public static bool TryCreate( Character character, Item sourceItem, WearableSprite source, bool preserveMasks, out FashionSpriteDescriptor descriptor, out string error)` | 初始化來源、建立獨立 WearableSprite 與貼圖資源，複製執行期視覺狀態並套用遮罩政策；失敗會清理。 | `CloneResolvedSprite`、`CopyRuntimeVisualState`、`RemoveSprite`、`FashionSpriteDescriptor`、`GetResolvedSpritePath`、`IsValid`、`Dispose` | [L90](../../CSharp/Client/WardrobeRendering.cs#L90) |
| `FashionSpriteDescriptor · public void Dispose()` | 標記描述已釋放，移除它獨立持有的貼圖資源。 | — | [L195](../../CSharp/Client/WardrobeRendering.cs#L195) |
| `FashionSpriteDescriptor · private static Sprite CloneResolvedSprite(Sprite source)` | 複製已解析的實際 Sprite 及可變繪圖狀態，失敗時釋放副本。 | `RemoveSprite` | [L210](../../CSharp/Client/WardrobeRendering.cs#L210) |
| `FashionSpriteDescriptor · private static void CopyRuntimeVisualState( WearableSprite source, WearableSprite target, Character character)` | 複製肢體綁定、縮放、色彩、變體及遮罩等執行期視覺屬性。 | — | [L235](../../CSharp/Client/WardrobeRendering.cs#L235) |
| `FashionSpriteDescriptor · private static string GetResolvedSpritePath(Sprite sprite)` | 取得已載入貼圖的實際路徑供診斷與相容判斷。 | — | [L267](../../CSharp/Client/WardrobeRendering.cs#L267) |
| `FashionSpriteDescriptor · private static void RemoveSprite(Sprite sprite)` | 安全釋放指定 Sprite 資源。 | — | [L273](../../CSharp/Client/WardrobeRendering.cs#L273) |
| `RenderSession · public RenderSession(Character character)` | 建立角色外觀資源的聚合容器，保存角色及相應 session 狀態。 | — | [L292](../../CSharp/Client/WardrobeRendering.cs#L292) |
| `RenderSession · internal float LimitEquipmentMovementSpeed(AnimationType type, bool backwards, float speed)` | 彙整真裝備的移動限制，供外觀動畫使用時保留功能效果。 | — | [L335](../../CSharp/Client/WardrobeRendering.cs#L335) |
| `RenderSession · public RenderSession BeginPendingCapture()` | 建立新的待提交 session，先清除先前未完成擷取。 | `Dispose`、`RenderSession` | [L407](../../CSharp/Client/WardrobeRendering.cs#L407) |
| `RenderSession · public RenderSession DetachPendingCapture()` | 取出並解除待提交 session 的關聯，讓呼叫者接管提交。 | — | [L416](../../CSharp/Client/WardrobeRendering.cs#L416) |
| `RenderSession · public bool AbortPendingCapture()` | 釋放待提交的擷取資源。 | `Dispose` | [L424](../../CSharp/Client/WardrobeRendering.cs#L424) |
| `RenderSession · public void MarkCommitted()` | 標記 session 已提交，完成後續重用判斷所需狀態。 | — | [L433](../../CSharp/Client/WardrobeRendering.cs#L433) |
| `RenderSession · public void Add(FashionSpriteDescriptor descriptor)` | 把貼圖描述加入 session 的索引及所有權集合。 | `IsValid` | [L439](../../CSharp/Client/WardrobeRendering.cs#L439) |
| `RenderSession · public bool TryGetDescriptor(WearableSprite sprite, out FashionSpriteDescriptor descriptor)` | 從貼圖參照查找對應的外觀描述。 | — | [L457](../../CSharp/Client/WardrobeRendering.cs#L457) |
| `RenderSession · public void AddOwnedTemporaryItem(Item item)` | 記住由 prefab 備援建立的暫時物品，由 session 最後釋放。 | `Add` | [L463](../../CSharp/Client/WardrobeRendering.cs#L463) |
| `RenderSession · public bool OwnsAppendage(Limb limb)` | 判斷指定附肢是否由這個 session 建立。 | — | [L473](../../CSharp/Client/WardrobeRendering.cs#L473) |
| `RenderSession · public void SetOwnedAppendages(IEnumerable<Limb> limbs)` | 登記 session 建立的附肢及其所屬 ragdoll。 | `RemoveOwnedAppendages` | [L478](../../CSharp/Client/WardrobeRendering.cs#L478) |
| `RenderSession · public void RemoveOwnedAppendages()` | 移除外觀專用附肢並清空所有權紀錄。 | — | [L485](../../CSharp/Client/WardrobeRendering.cs#L485) |
| `RenderSession · public void MarkLiveItemSource()` | 記住外觀來自現存物品，供生命週期與重用判斷。 | — | [L500](../../CSharp/Client/WardrobeRendering.cs#L500) |
| `RenderSession · public void MarkInvalid(string error)` | 標記 session 無效並保存拒絕啟用的原因。 | — | [L505](../../CSharp/Client/WardrobeRendering.cs#L505) |
| `RenderSession · public bool Validate(out string error)` | 檢查 session 與所有貼圖描述是否可用，失敗回傳原因。 | `IsValid`、`MarkInvalid` | [L512](../../CSharp/Client/WardrobeRendering.cs#L512) |
| `RenderSession · public bool TryEnterDraw(Limb limb, object context)` | 登記肢體的繪製 transaction，避免同一肢體重複擁有繪製狀態。 | — | [L536](../../CSharp/Client/WardrobeRendering.cs#L536) |
| `RenderSession · public bool TryGetDrawContext(Limb limb, out object context)` | 查找指定肢體正在使用的繪製 transaction。 | — | [L543](../../CSharp/Client/WardrobeRendering.cs#L543) |
| `RenderSession · public void ExitDraw(Limb limb)` | 移除肢體目前的繪製 transaction 登記。 | — | [L549](../../CSharp/Client/WardrobeRendering.cs#L549) |
| `RenderSession · public void Dispose()` | 停止外觀、還原裝備動畫優先權，釋放貼圖、附肢、效果參照及最後的暫時物品。 | `AbortPendingCapture`、`RemoveOwnedAppendages` | [L554](../../CSharp/Client/WardrobeRendering.cs#L554) |

## WardrobeRenderTransactions.cs

來源：[CSharp/Client/WardrobeRenderTransactions.cs](../../CSharp/Client/WardrobeRenderTransactions.cs)

| 函式／方法（含參數） | 用途 | 相關呼叫 | 定位 |
|---|---|---|---|
| `VisualOverride.FootstepSoundTransaction · public void Reset(Limb nextLimb)` | 綁定新的肢體並重設 transaction 執行狀態，供池中物件重用。 | — | [L31](../../CSharp/Client/WardrobeRenderTransactions.cs#L31) |
| `VisualOverride.FootstepSoundTransaction · public void ResetForPool()` | 清除參照與暫存集合，讓 transaction 可安全放回物件池。 | — | [L38](../../CSharp/Client/WardrobeRenderTransactions.cs#L38) |
| `VisualOverride.FootstepSoundTransaction · public void Begin(RenderSession session)` | 開始 transaction：快照原始肢體資料，再準備本次繪製或腳步音效所需的替代狀態。 | `IsEquipmentSprite`、`IsValid`、`Add` | [L45](../../CSharp/Client/WardrobeRenderTransactions.cs#L45) |
| `VisualOverride.FootstepSoundTransaction · public void Cleanup()` | 還原 transaction 修改過的列表及遮罩，釋放繪製登記；保留清理失敗供上層處理。 | — | [L80](../../CSharp/Client/WardrobeRenderTransactions.cs#L80) |
| `VisualOverride.LimbRenderTransaction · public LimbRenderTransaction(Limb limb)` | 綁定肢體，建立可重用的逐肢體繪製 transaction。 | `Reset` | [L104](../../CSharp/Client/WardrobeRenderTransactions.cs#L104) |
| `VisualOverride.LimbRenderTransaction · public object[] GetDrawArguments( WearableSprite wearable, float depth, SpriteBatch spriteBatch, Color color, float alpha, SpriteEffects spriteEffect)` | 取得重用的反射繪製參數陣列，填入這次繪製的值。 | — | [L120](../../CSharp/Client/WardrobeRenderTransactions.cs#L120) |
| `VisualOverride.LimbRenderTransaction · public void Reset(Limb nextLimb)` | 綁定新的肢體並重設 transaction 執行狀態，供池中物件重用。 | — | [L138](../../CSharp/Client/WardrobeRenderTransactions.cs#L138) |
| `VisualOverride.LimbRenderTransaction · public void ResetForPool()` | 清除參照與暫存集合，讓 transaction 可安全放回物件池。 | — | [L156](../../CSharp/Client/WardrobeRenderTransactions.cs#L156) |
| `VisualOverride.LimbRenderTransaction · public void EnterStoredFashionDraw()` | 進入外觀貼圖繪製的遞迴保護區段。 | — | [L174](../../CSharp/Client/WardrobeRenderTransactions.cs#L174) |
| `VisualOverride.LimbRenderTransaction · public void ExitStoredFashionDraw()` | 離開外觀貼圖繪製保護區段，檢查進出計數是否平衡。 | — | [L180](../../CSharp/Client/WardrobeRenderTransactions.cs#L180) |
| `VisualOverride.LimbRenderTransaction · public void Begin(RenderSession renderSession)` | 開始 transaction：快照原始肢體資料，再準備本次繪製或腳步音效所需的替代狀態。 | `GetFashionSpritesForLimb`、`IsEquipmentSprite`、`TryGetDescriptor`、`ShouldDrawOriginalForEmptySavedSlot`、`NeedsMaskClear`、`SpriteMaskState`、`ClearMask`、`EnumerateFashionSpritesForLimb` 等 | [L189](../../CSharp/Client/WardrobeRenderTransactions.cs#L189) |
| `VisualOverride.LimbRenderTransaction · static List<FashionSpriteDescriptor> GetFashionSpritesForLimb(RenderSession session, Limb limb)` | 優先重用 session 的逐肢體描述快取，不存在時列舉、排序並快取。 | `EnumerateFashionSpritesForLimb` | [L245](../../CSharp/Client/WardrobeRenderTransactions.cs#L245) |
| `VisualOverride.LimbRenderTransaction · public void Cleanup()` | 還原 transaction 修改過的列表及遮罩，釋放繪製登記；保留清理失敗供上層處理。 | `Add`、`Restore`、`ExitDraw` | [L295](../../CSharp/Client/WardrobeRenderTransactions.cs#L295) |
| `VisualOverride.PatchState · public PatchState(bool required)` | 建立 patch 是否必要及安裝狀態的紀錄。 | — | [L374](../../CSharp/Client/WardrobeRenderTransactions.cs#L374) |
| `VisualOverride.PatchState · public void Fail(string error)` | 記住 patch 安裝失敗原因並標記不可用。 | — | [L385](../../CSharp/Client/WardrobeRenderTransactions.cs#L385) |
| `VisualOverride.SpriteMaskState · public SpriteMaskState(WearableSprite sprite)` | 快照 WearableSprite 的肢體隱藏、附件隱藏及遮蔽屬性。 | — | [L399](../../CSharp/Client/WardrobeRenderTransactions.cs#L399) |
| `VisualOverride.SpriteMaskState · public void Restore(WearableSprite sprite)` | 把快照遮罩寫回原貼圖，避免逐幀變更殘留。 | — | [L407](../../CSharp/Client/WardrobeRenderTransactions.cs#L407) |

## WardrobeSinglePlayerProfiles.cs

來源：[CSharp/Client/WardrobeSinglePlayerProfiles.cs](../../CSharp/Client/WardrobeSinglePlayerProfiles.cs)

| 函式／方法（含參數） | 用途 | 相關呼叫 | 定位 |
|---|---|---|---|
| `WardrobePersistence · public static string GetSinglePlayerProfilesPath()` | 回傳 SinglePlayerProfiles.json 的完整路徑。 | `GetStorageDirectory` | [L24](../../CSharp/Client/WardrobeSinglePlayerProfiles.cs#L24) |
| `WardrobePersistence · public static bool GetSinglePlayerTransferEnabled()` | 讀取跨角色外觀轉移選項，失敗採安全預設。 | `ClearLastError`、`ReadSinglePlayerProfiles`、`LogPersistenceError` | [L29](../../CSharp/Client/WardrobeSinglePlayerProfiles.cs#L29) |
| `WardrobePersistence · public static bool SetSinglePlayerTransferEnabled(bool enabled)` | 修改跨角色外觀轉移選項並安全寫入角色設定文件。 | `ClearLastError`、`ReadSinglePlayerProfiles`、`WriteSinglePlayerProfiles`、`LogPersistenceError` | [L43](../../CSharp/Client/WardrobeSinglePlayerProfiles.cs#L43) |
| `WardrobePersistence · public static string LoadSinglePlayerProfile(string campaignKey, string characterKey)` | 用戰役與穩定角色鍵的雜湊查找外觀，轉成 Lua 橋接字串。 | `ClearLastError`、`HashRequiredKey`、`ReadSinglePlayerProfiles`、`EncodeSinglePlayerProfile`、`LogPersistenceError` | [L61](../../CSharp/Client/WardrobeSinglePlayerProfiles.cs#L61) |
| `WardrobePersistence · public static bool SaveSinglePlayerProfile( string campaignKey, string characterKey, string displayName, string encodedLook)` | 驗證戰役、角色、名稱及外觀，新增或更新該角色設定並安全寫入。 | `ClearLastError`、`HashRequiredKey`、`ValidateDisplayName`、`ParseParts`、`ParseClientLook`、`ValidateDocument`、`HasAnySlot`、`DeleteSinglePlayerProfile` 等 | [L81](../../CSharp/Client/WardrobeSinglePlayerProfiles.cs#L81) |
| `WardrobePersistence · public static bool DeleteSinglePlayerProfile(string campaignKey, string characterKey)` | 只刪除指定戰役及角色的設定，保留其他角色資料。 | `ClearLastError`、`HashRequiredKey`、`ReadSinglePlayerProfiles`、`WriteSinglePlayerProfiles`、`LogPersistenceError` | [L144](../../CSharp/Client/WardrobeSinglePlayerProfiles.cs#L144) |
| `WardrobePersistence · public static bool TryImportLegacyClientLook( string campaignKey, string characterKey, string displayName)` | 將舊版單一外觀匯入指定角色一次，保留未套用意圖並處理備份標記。 | `ClearLastError`、`HashRequiredKey`、`ValidateDisplayName`、`ReadSinglePlayerProfiles`、`Add`、`ReadLegacyClientLookForImport`、`HasAnySlot`、`CopyAttachmentVisibility` 等 | [L169](../../CSharp/Client/WardrobeSinglePlayerProfiles.cs#L169) |
| `WardrobePersistence · private static ClientLookDocument ReadLegacyClientLookForImport()` | 讀取供匯入使用的舊外觀，避免正常載入流程提前改寫匯入意圖。 | `GetClientLookPath`、`ReadClientDocument`、`WriteJson`、`LogPersistenceInfo`、`QuarantineCorruptFile` | [L233](../../CSharp/Client/WardrobeSinglePlayerProfiles.cs#L233) |
| `WardrobePersistence · private static SinglePlayerProfilesDocument ReadSinglePlayerProfiles()` | 讀取、遷移並驗證單人設定；損壞時隔離文件。 | `GetSinglePlayerProfilesPath`、`CreateEmptySinglePlayerProfiles`、`ReadSchemaVersion`、`MigrateSinglePlayerProfilesV1`、`ValidateSinglePlayerProfiles`、`WriteSinglePlayerProfiles`、`LogPersistenceInfo`、`MigrateSinglePlayerProfilesV2` 等 | [L268](../../CSharp/Client/WardrobeSinglePlayerProfiles.cs#L268) |
| `WardrobePersistence · private static void WriteSinglePlayerProfiles(SinglePlayerProfilesDocument document)` | 驗證整份單人設定後使用共用 JSON 安全寫入。 | `ValidateSinglePlayerProfiles`、`WriteJson`、`GetSinglePlayerProfilesPath` | [L321](../../CSharp/Client/WardrobeSinglePlayerProfiles.cs#L321) |
| `WardrobePersistence · private static SinglePlayerProfilesDocument MigrateSinglePlayerProfilesV1(string json)` | 遷移第一版單人角色設定，補上目前格式所需的外觀政策。 | `CreateAttachmentVisibility`、`CopySlots`、`CreateEmptyColors` | [L334](../../CSharp/Client/WardrobeSinglePlayerProfiles.cs#L334) |
| `WardrobePersistence · private static SinglePlayerProfilesDocument MigrateSinglePlayerProfilesV2(string json)` | 遷移第二版單人角色設定，保留缺少色彩等舊版語意。 | `CopyAttachmentVisibility`、`CopySlots`、`CreateEmptyColors` | [L367](../../CSharp/Client/WardrobeSinglePlayerProfiles.cs#L367) |
| `WardrobePersistence · private static SinglePlayerProfilesDocument CreateEmptySinglePlayerProfiles()` | 建立空角色設定文件及預設轉移選項。 | — | [L400](../../CSharp/Client/WardrobeSinglePlayerProfiles.cs#L400) |
| `WardrobePersistence · private static void ValidateSinglePlayerProfiles(SinglePlayerProfilesDocument document)` | 驗證角色數量、雜湊、重複身分、顯示名稱與每份外觀。 | `ValidateHash`、`Add`、`ValidateDisplayName`、`ValidateDocument`、`HasAnySlot`、`CopySlots`、`CopyColors` | [L411](../../CSharp/Client/WardrobeSinglePlayerProfiles.cs#L411) |
| `WardrobePersistence · private static string EncodeSinglePlayerProfile(SinglePlayerProfile profile)` | 把指定角色設定轉成 Lua 可解析的橋接資料。 | `LegacyHideHair`、`AppendEncodedSlots`、`AppendEncodedColors` | [L477](../../CSharp/Client/WardrobeSinglePlayerProfiles.cs#L477) |
| `WardrobePersistence · private static Dictionary<string, string> CopySlots(Dictionary<string, string> source)` | 複製外觀欄位字典，避免不同角色共用可變資料。 | `CreateEmptySlots` | [L500](../../CSharp/Client/WardrobeSinglePlayerProfiles.cs#L500) |
| `WardrobePersistence · private static Dictionary<string, uint?> CopyColors(Dictionary<string, uint?> source)` | 複製外觀色彩字典，保留未指定色彩的值。 | `CreateEmptyColors` | [L514](../../CSharp/Client/WardrobeSinglePlayerProfiles.cs#L514) |
| `WardrobePersistence · private static string HashRequiredKey(string value, string field)` | 驗證必要身分鍵後轉成穩定雜湊，不把原始戰役路徑存入設定。 | — | [L530](../../CSharp/Client/WardrobeSinglePlayerProfiles.cs#L530) |
| `WardrobePersistence · private static void ValidateHash(string value, string field)` | 檢查儲存的身分雜湊格式。 | — | [L540](../../CSharp/Client/WardrobeSinglePlayerProfiles.cs#L540) |
| `WardrobePersistence · private static string ValidateDisplayName(string value)` | 限制顯示名稱格式及長度；顯示名稱不作為角色身分。 | — | [L552](../../CSharp/Client/WardrobeSinglePlayerProfiles.cs#L552) |

## WardrobeVisualDraw.cs

來源：[CSharp/Client/WardrobeVisualDraw.cs](../../CSharp/Client/WardrobeVisualDraw.cs)

| 函式／方法（含參數） | 用途 | 相關呼叫 | 定位 |
|---|---|---|---|
| `VisualOverride · internal static bool TryOverrideDrawWearable(Limb limb, WearableSprite original, out WearableSprite replacement, out bool skipOriginal)` | 在真實繪製邊界判斷使用原貼圖、外觀替代或跳過，處理空欄位及同肢體去重。 | `HasCapability`、`TryGetDrawContext`、`IsFashionSpriteCompatibleWithLimb`、`Add`、`IsEquipmentSprite`、`ShouldHideAttachmentForFashion`、`ShouldHideFashionBehindVisibleEquipment`、`SpriteBelongsToLimb` 等 | [L25](../../CSharp/Client/WardrobeVisualDraw.cs#L25) |
| `VisualOverride · internal static LimbRenderTransaction BeginLimbDraw(Limb limb)` | 確認角色有啟用且合法的 session 後取得繪製 transaction，失敗時清理並標記 session 無效。 | `HasCapability`、`RentLimbRenderTransaction`、`TryEnterDraw`、`Begin`、`LogVirtualDrawError`、`Cleanup`、`MarkInvalid` | [L127](../../CSharp/Client/WardrobeVisualDraw.cs#L127) |
| `VisualOverride · private static LimbRenderTransaction RentLimbRenderTransaction(Limb limb)` | 從執行緒本地物件池取得 transaction，不足時建立。 | `Reset`、`LimbRenderTransaction` | [L170](../../CSharp/Client/WardrobeVisualDraw.cs#L170) |
| `VisualOverride · private static void ReturnLimbRenderTransaction(LimbRenderTransaction transaction)` | 重設 transaction 後放回有容量上限的執行緒本地池。 | `ResetForPool` | [L182](../../CSharp/Client/WardrobeVisualDraw.cs#L182) |
| `VisualOverride · internal static bool ShouldSuppressEquipmentAppendage(Limb limb)` | 判斷真裝備附肢是否應被外觀遮蔽，保留允許顯示的空欄位裝備。 | `GetHideEmptySlotEquipment`、`OwnsAppendage` | [L194](../../CSharp/Client/WardrobeVisualDraw.cs#L194) |
| `VisualOverride · internal static bool ShouldSuppressAfflictionAppendage(Limb limb)` | 依屍殼選項及已知翼附肢識別碼判斷是否只隱藏其外觀。 | `GetHideHuskVisuals`、`IsHuskAppearanceAffliction` | [L250](../../CSharp/Client/WardrobeVisualDraw.cs#L250) |
| `VisualOverride · internal static WearableSprite BeginHuskSpriteSuppression(Limb limb)` | 暫時移除屍殼視覺貼圖，回傳原值供繪製結束還原。 | `GetHideHuskVisuals`、`HasHuskAppearanceAffliction`、`LogVirtualDrawError` | [L282](../../CSharp/Client/WardrobeVisualDraw.cs#L282) |
| `VisualOverride · internal static Exception EndHuskSpriteSuppression( Limb limb, WearableSprite huskSprite, Exception exception)` | 還原暫時隱藏的屍殼貼圖，保留原本例外並合併清理錯誤。 | `LogVirtualDrawError` | [L302](../../CSharp/Client/WardrobeVisualDraw.cs#L302) |
| `VisualOverride · internal static void SuppressHuskTint(Affliction affliction, ref Color result)` | 僅對允許的屍殼狀態取消外觀染色，不移除遊戲效果。 | `GetHideHuskVisuals`、`IsHuskAppearanceAffliction` | [L320](../../CSharp/Client/WardrobeVisualDraw.cs#L320) |
| `VisualOverride · private static bool HasHuskAppearanceAffliction(Character character)` | 確認角色是否具有需要隱藏外觀的屍殼狀態。 | `IsHuskAppearanceAffliction` | [L328](../../CSharp/Client/WardrobeVisualDraw.cs#L328) |
| `VisualOverride · private static bool IsHuskAppearanceAffliction(Affliction affliction)` | 以固定識別碼限制屍殼外觀處理範圍。 | — | [L338](../../CSharp/Client/WardrobeVisualDraw.cs#L338) |
| `VisualOverride · internal static Exception EndLimbDraw(Limb limb, LimbRenderTransaction transaction, Exception exception = null)` | 結束繪製 transaction，還原修改並放回物件池；讓原始例外繼續傳遞。 | `Cleanup`、`LogVirtualDrawError`、`ReturnLimbRenderTransaction` | [L344](../../CSharp/Client/WardrobeVisualDraw.cs#L344) |
| `VisualOverride · internal static FootstepSoundTransaction BeginFootstepSound(Limb limb)` | 為外觀腳步音效建立短期替代 transaction，保留原肢體穿戴列表。 | `HasCapability`、`Reset`、`Begin`、`LogSoundError`、`Cleanup`、`ReturnFootstepSoundTransaction` | [L366](../../CSharp/Client/WardrobeVisualDraw.cs#L366) |
| `VisualOverride · private static string DescribeFashionFootstepSounds(RenderSession session)` | 產生腳步音效來源的診斷文字。 | — | [L408](../../CSharp/Client/WardrobeVisualDraw.cs#L408) |
| `VisualOverride · internal static Exception EndFootstepSound( FootstepSoundTransaction transaction, Exception exception = null)` | 還原腳步音效 transaction，回收池物件並保留原始例外。 | `Cleanup`、`LogSoundError`、`ReturnFootstepSoundTransaction` | [L419](../../CSharp/Client/WardrobeVisualDraw.cs#L419) |
| `VisualOverride · private static void ReturnFootstepSoundTransaction(FootstepSoundTransaction transaction)` | 重設並回收腳步音效 transaction，限制池大小。 | `ResetForPool` | [L437](../../CSharp/Client/WardrobeVisualDraw.cs#L437) |
| `VisualOverride · internal static void DrawMissingFashionSprites( Limb limb, LimbRenderTransaction transaction, SpriteBatch spriteBatch, Color? overrideColor)` | 補畫未由原穿戴物路徑畫出的外觀貼圖，沿用 transaction 的描述與去重狀態。 | `LogVirtualDrawError`、`IsFashionSpriteCompatibleWithLimb`、`ShouldHideFashionBehindVisibleEquipment`、`Add`、`UsesRecessedFashionLayer`、`DrawFashionWearable` | [L449](../../CSharp/Client/WardrobeVisualDraw.cs#L449) |
| `VisualOverride · private static void DrawFashionWearable( RenderSession session, Limb limb, LimbRenderTransaction transaction, WearableSprite wearable, int depthIndex, SpriteBatch spriteBatch, Color? overrideColor)` | 呼叫原遊戲的穿戴繪製方法，套用外觀色彩、深度及遞迴保護。 | `SpriteBelongsToLimb`、`EnterStoredFashionDraw`、`GetDrawArguments`、`Capture`、`ExitStoredFashionDraw` | [L494](../../CSharp/Client/WardrobeVisualDraw.cs#L494) |

## WardrobeVisualLayers.cs

來源：[CSharp/Client/WardrobeVisualLayers.cs](../../CSharp/Client/WardrobeVisualLayers.cs)

| 函式／方法（含參數） | 用途 | 相關呼叫 | 定位 |
|---|---|---|---|
| `VisualOverride · private static IEnumerable<FashionSpriteDescriptor> EnumerateFashionSpritesForLimb( RenderSession session, LimbType limbType)` | 列舉符合實際肢體或萬用綁定的外觀描述，按層次與深度排序。 | `SpriteBelongsToLimb` | [L25](../../CSharp/Client/WardrobeVisualLayers.cs#L25) |
| `VisualOverride · private static void SortWearablesForDraw(List<WearableSprite> wearingItems)` | 以穩定的原地插入排序整理小型穿戴貼圖列表。 | `CompareWearablesForDraw` | [L39](../../CSharp/Client/WardrobeVisualLayers.cs#L39) |
| `VisualOverride · private static int CompareWearablesForDraw(WearableSprite left, WearableSprite right)` | 先比較裝備層次，再比較 Sprite 深度，提供穩定繪製順序。 | `GetFashionLayerSortKey` | [L57](../../CSharp/Client/WardrobeVisualLayers.cs#L57) |
| `VisualOverride · private static int GetFashionLayerSortKey(WearableSprite sprite)` | 依來源裝備欄位決定背包、醫療欄、內衣、頭部及外衣的排序鍵。 | `SlotContains`、`IsHeadSlotSprite` | [L66](../../CSharp/Client/WardrobeVisualLayers.cs#L66) |
| `VisualOverride · private static int GetFashionLayerSortKey(FashionSpriteDescriptor descriptor)` | 依來源裝備欄位決定背包、醫療欄、內衣、頭部及外衣的排序鍵。 | — | [L78](../../CSharp/Client/WardrobeVisualLayers.cs#L78) |
| `VisualOverride · private static bool UsesRecessedFashionLayer(FashionSpriteDescriptor descriptor)` | 判斷背包或醫療欄外觀是否使用較後方的繪製層。 | — | [L89](../../CSharp/Client/WardrobeVisualLayers.cs#L89) |
| `VisualOverride · private static string GetFashionLayerName(WearableSprite sprite)` | 將貼圖所屬排序層轉為診斷名稱。 | `SlotContains`、`IsHeadSlotSprite` | [L96](../../CSharp/Client/WardrobeVisualLayers.cs#L96) |
| `VisualOverride · private static bool IsHeadSlotSprite(WearableSprite sprite)` | 確認貼圖的 Wearable 允許頭部或耳機欄位。 | `SlotContains` | [L107](../../CSharp/Client/WardrobeVisualLayers.cs#L107) |
| `VisualOverride · private static bool SlotContains(WearableSprite sprite, InvSlotType slot)` | 直接檢查 Wearable 是否允許指定欄位。 | — | [L113](../../CSharp/Client/WardrobeVisualLayers.cs#L113) |
| `VisualOverride · private static bool SpriteBelongsToLimb(RenderSession session, WearableSprite sprite, LimbType limbType)` | 驗證貼圖是否屬於正在繪製的實際肢體，處理明確及備援綁定。 | `TryGetDescriptor`、`GetFallbackAnchorLimb` | [L119](../../CSharp/Client/WardrobeVisualLayers.cs#L119) |
| `VisualOverride · private static bool IsFashionSpriteCompatibleWithLimb( RenderSession session, WearableSprite sprite, Limb limb)` | 限制已知工坊 LeftBreast／None 貼圖只畫在對應實際肢體。 | `TryGetDescriptor` | [L134](../../CSharp/Client/WardrobeVisualLayers.cs#L134) |
| `VisualOverride · private static LimbType GetFallbackAnchorLimb(WearableSprite sprite)` | 對沒有明確肢體綁定的貼圖，依來源欄位選擇頭或軀幹等備援錨點。 | — | [L153](../../CSharp/Client/WardrobeVisualLayers.cs#L153) |
| `VisualOverride · private static object BoostFashionAnimationPriority(object animationInfo)` | 提高外觀動畫優先權，讓外觀動畫可蓋過裝備動畫。 | `LogAnimationError` | [L172](../../CSharp/Client/WardrobeVisualLayers.cs#L172) |
| `VisualOverride · private static void LogVirtualDrawError(string message)` | 限制繪製錯誤的記錄次數，避免每幀洗版。 | `Log` | [L205](../../CSharp/Client/WardrobeVisualLayers.cs#L205) |
| `VisualOverride · private static void LogAnimationError(string message)` | 限制外觀動畫錯誤的記錄次數。 | `Log` | [L212](../../CSharp/Client/WardrobeVisualLayers.cs#L212) |
| `VisualOverride · private static void LogSoundError(string message)` | 限制外觀音效錯誤的記錄次數。 | `Log` | [L219](../../CSharp/Client/WardrobeVisualLayers.cs#L219) |
| `VisualOverride · private static bool IsEquipmentSprite(WearableSprite sprite)` | 只將 WearableType.Item 視為裝備貼圖。 | — | [L226](../../CSharp/Client/WardrobeVisualLayers.cs#L226) |
| `VisualOverride · private static HashSet<InvSlotType> ParseSlotCsv(string slotsCsv)` | 把逗號分隔欄位字串轉成 InvSlotType 集合。 | `Add` | [L231](../../CSharp/Client/WardrobeVisualLayers.cs#L231) |
| `VisualOverride · private static bool ShouldHideOriginalForEmptySavedSlot(Character character, WearableSprite original)` | 判斷真裝備是否落在外觀明確保存為空的欄位。 | — | [L247](../../CSharp/Client/WardrobeVisualLayers.cs#L247) |
| `VisualOverride · private static bool ShouldDrawOriginalForEmptySavedSlot(Character character, WearableSprite original)` | 綜合顯示空欄位裝備選項與強制遮罩，判斷是否保留真裝備繪製。 | `GetHideEmptySlotEquipment`、`ShouldHideOriginalForEmptySavedSlot`、`ShouldHideOriginalForSavedSlot` | [L262](../../CSharp/Client/WardrobeVisualLayers.cs#L262) |
| `VisualOverride · private static bool ShouldHideFashionBehindVisibleEquipment(Limb limb)` | 當可見真裝備在同肢體遮住身體及其他穿戴物時，讓注入外觀也受遮蔽。 | `IsEquipmentSprite`、`ShouldDrawOriginalForEmptySavedSlot` | [L273](../../CSharp/Client/WardrobeVisualLayers.cs#L273) |
| `VisualOverride · private static void CaptureFashionHiddenWearableTypes(RenderSession session, WearableSprite sprite)` | 保留來源對頭髮、鬍鬚及臉部附件的隱藏意圖。 | `Add` | [L290](../../CSharp/Client/WardrobeVisualLayers.cs#L290) |
| `VisualOverride · private static bool ShouldHideAttachmentForFashion(Character character, WearableSprite original)` | 依強制顯示、強制隱藏、來源政策的優先序判斷附件可見性。 | — | [L300](../../CSharp/Client/WardrobeVisualLayers.cs#L300) |
| `VisualOverride · private static string DescribeFashionHiddenTypes(Character character)` | 輸出外觀要求隱藏的附件類型。 | — | [L319](../../CSharp/Client/WardrobeVisualLayers.cs#L319) |
| `VisualOverride · private static bool ShouldHideOriginalForSavedSlot(Character character, WearableSprite original)` | 確認真裝備是否位於已被保存外觀接管的欄位。 | — | [L330](../../CSharp/Client/WardrobeVisualLayers.cs#L330) |
| `VisualOverride · private static string DescribeSavedSlots(Character character)` | 輸出指定角色已保存欄位的診斷文字。 | `DescribeSlotSet` | [L345](../../CSharp/Client/WardrobeVisualLayers.cs#L345) |
| `VisualOverride · private static string DescribeEmptySlots(Character character)` | 輸出指定角色保存為空的欄位診斷文字。 | `DescribeSlotSet` | [L352](../../CSharp/Client/WardrobeVisualLayers.cs#L352) |
| `VisualOverride · private static string DescribeSlotSet(HashSet<InvSlotType> slots)` | 將欄位集合排序並轉成文字，空集合顯示明確空值。 | — | [L359](../../CSharp/Client/WardrobeVisualLayers.cs#L359) |
| `VisualOverride · private static bool NeedsMaskClear(WearableSprite sprite)` | 先檢查貼圖是否真的有遮罩需要暫時清除，避免無效快照。 | — | [L368](../../CSharp/Client/WardrobeVisualLayers.cs#L368) |
| `VisualOverride · private static void ClearMask(WearableSprite sprite, List<WearableType> emptyHideWearablesOfType)` | 暫時取消原貼圖的身體隱藏、附件隱藏及遮蔽設定。 | — | [L377](../../CSharp/Client/WardrobeVisualLayers.cs#L377) |
| `VisualOverride · private static bool IsCharacterStale(Character character)` | 判斷角色是否為空或已從遊戲移除。 | — | [L393](../../CSharp/Client/WardrobeVisualLayers.cs#L393) |
| `VisualOverride · private static void RefreshWearables(Character character)` | 通知角色穿戴物已變更，刷新遊戲維護的視覺快取。 | `Log` | [L408](../../CSharp/Client/WardrobeVisualLayers.cs#L408) |
| `VisualOverride · internal static bool TryGetFashionSprite( Character character, WearableType type, LimbType limbType, HashSet<WearableSprite> drawnSprites, out WearableSprite sprite, out bool alreadyDrawn)` | 依角色、貼圖類型與肢體尋找尚未畫過的替代外觀，同時回報是否已畫過。 | `TryGetFashionSpriteFromList` | [L421](../../CSharp/Client/WardrobeVisualLayers.cs#L421) |
| `VisualOverride · private static bool TryGetFashionSpriteFromList( RenderSession session, List<FashionSpriteDescriptor> descriptors, LimbType limbType, HashSet<WearableSprite> drawnSprites, ref bool alreadyDrawn, out WearableSprite sprite)` | 掃描一份候選描述，檢查肢體綁定與去重集合後回傳貼圖。 | `SpriteBelongsToLimb` | [L460](../../CSharp/Client/WardrobeVisualLayers.cs#L460) |
| `VisualOverride · private static string DescribeFashionSprites(Character character)` | 輸出保存貼圖數量及來源概要。 | — | [L485](../../CSharp/Client/WardrobeVisualLayers.cs#L485) |
| `VisualOverride · private static string DescribeFashionSpriteLayers(Character character)` | 輸出外觀貼圖的圖層與深度診斷。 | `GetFashionLayerName` | [L500](../../CSharp/Client/WardrobeVisualLayers.cs#L500) |
| `VisualOverride · private static string DescribeFashionSpriteSources(Character character)` | 輸出每張貼圖的物品識別碼、內容包及解析路徑。 | — | [L517](../../CSharp/Client/WardrobeVisualLayers.cs#L517) |

## WardrobeVisualOverride.cs

來源：[CSharp/Client/WardrobeVisualOverride.cs](../../CSharp/Client/WardrobeVisualOverride.cs)

| 函式／方法（含參數） | 用途 | 相關呼叫 | 定位 |
|---|---|---|---|
| `VisualOverride · public static string GetVersion()` | 回傳所屬橋接類別的版本字串。 | — | [L39](../../CSharp/Client/WardrobeVisualOverride.cs#L39) |
| `VisualOverride · public static void ResetPatchStatus()` | 重建必要及可選 Harmony patch 的能力狀態。 | `PatchState` | [L167](../../CSharp/Client/WardrobeVisualOverride.cs#L167) |
| `VisualOverride · public static void InstallPatches(Harmony harmony)` | 將繪製、動畫、音效、移速與屍殼視覺 hooks 裝到對應遊戲方法。 | `ResetPatchStatus`、`Fail`、`PatchTarget` | [L183](../../CSharp/Client/WardrobeVisualOverride.cs#L183) |
| `VisualOverride · public static bool IsReady()` | 確認外觀渲染所需的必要 patch 是否已安裝。 | `ResetPatchStatus` | [L258](../../CSharp/Client/WardrobeVisualOverride.cs#L258) |
| `VisualOverride · public static bool HasCapability(string name)` | 依 renderer、animation、sound 等能力名稱檢查所需方法及 patch。 | `ResetPatchStatus`、`PatchApplied` | [L264](../../CSharp/Client/WardrobeVisualOverride.cs#L264) |
| `VisualOverride · public static string GetReadinessStatus()` | 彙整可用能力與失敗原因，供 Lua 面板顯示。 | `ResetPatchStatus`、`HasCapability` | [L307](../../CSharp/Client/WardrobeVisualOverride.cs#L307) |
| `VisualOverride · private static bool PatchApplied(string name)` | 查詢指定 patch 是否安裝成功。 | — | [L338](../../CSharp/Client/WardrobeVisualOverride.cs#L338) |
| `VisualOverride · private static void PatchTarget( Harmony harmony, string name, MethodBase target, MethodInfo prefix = null, MethodInfo postfix = null, MethodInfo finalizer = null, bool required = true)` | 驗證目標方法後安裝 prefix／postfix／finalizer，記住安裝結果與錯誤。 | `PatchState`、`Fail`、`Log` | [L343](../../CSharp/Client/WardrobeVisualOverride.cs#L343) |
| `VisualOverride · public static string GetCharacterDebugStatus(Character character)` | 彙整角色 session、貼圖、圖層、遮罩、效果及繪製計數供診斷。 | `GetHideHuskVisuals`、`GetHideEmptySlotEquipment`、`DescribeFashionFootstepSounds`、`DescribeFashionHiddenTypes`、`DescribeSavedSlots`、`DescribeEmptySlots`、`DescribeFashionSprites`、`DescribeFashionSpriteLayers` 等 | [L396](../../CSharp/Client/WardrobeVisualOverride.cs#L396) |
| `VisualOverride · public static void ClearAll()` | 清除全部角色 session 並重設視覺狀態。 | `Dispose` | [L446](../../CSharp/Client/WardrobeVisualOverride.cs#L446) |
| `VisualOverride · public static void RestoreItemVisuals()` | 對全部 session 關閉外觀並清除遮罩政策，恢復真裝備顯示。 | `RemoveOwnedAppendages` | [L455](../../CSharp/Client/WardrobeVisualOverride.cs#L455) |
| `VisualOverride · public static void RestoreCharacterItemVisuals(Character character)` | 只恢復指定角色的真裝備顯示。 | `RemoveOwnedAppendages`、`RefreshWearables` | [L470](../../CSharp/Client/WardrobeVisualOverride.cs#L470) |
| `VisualOverride · internal static void SetPanelKeySetting(ISettingBase<string> setting)` | 綁定模組設定服務提供的開啟面板按鍵設定。 | — | [L490](../../CSharp/Client/WardrobeVisualOverride.cs#L490) |
| `VisualOverride · internal static void SetHideHuskVisualsSetting( ISettingBase<bool> setting, IConfigService service)` | 綁定屍殼外觀設定及變更事件，解除舊訂閱並刷新視覺。 | `ForceUpdateCharacterVisuals` | [L495](../../CSharp/Client/WardrobeVisualOverride.cs#L495) |
| `VisualOverride · public static string GetPanelKeyName()` | 取得合法按鍵名稱；未設定或無效時使用 F8。 | — | [L513](../../CSharp/Client/WardrobeVisualOverride.cs#L513) |
| `VisualOverride · public static bool GetHideHuskVisuals()` | 讀取屍殼外觀隱藏選項，設定服務缺少時使用記憶體備援值。 | — | [L519](../../CSharp/Client/WardrobeVisualOverride.cs#L519) |
| `VisualOverride · public static bool SetHideHuskVisuals(bool enabled)` | 保存屍殼外觀選項；寫入失敗回復舊值，成功刷新角色視覺。 | `HasCapability`、`SaveBooleanSetting`、`Log`、`ForceUpdateCharacterVisuals` | [L524](../../CSharp/Client/WardrobeVisualOverride.cs#L524) |
| `VisualOverride · internal static void SetUnequipOnSaveSetting( ISettingBase<bool> setting, IConfigService service)` | 綁定保存時卸裝的設定與設定服務。 | — | [L541](../../CSharp/Client/WardrobeVisualOverride.cs#L541) |
| `VisualOverride · public static bool GetUnequipOnSave()` | 讀取保存時卸裝選項，缺少設定服務時使用備援值。 | — | [L550](../../CSharp/Client/WardrobeVisualOverride.cs#L550) |
| `VisualOverride · public static bool SetUnequipOnSave(bool enabled)` | 保存卸裝選項，寫入失敗保留先前值。 | `SaveBooleanSetting`、`Log` | [L555](../../CSharp/Client/WardrobeVisualOverride.cs#L555) |
| `VisualOverride · internal static void SetHideEmptySlotEquipmentSetting( ISettingBase<bool> setting, IConfigService service)` | 綁定空欄位裝備可見性的設定及服務。 | — | [L570](../../CSharp/Client/WardrobeVisualOverride.cs#L570) |
| `VisualOverride · public static bool GetHideEmptySlotEquipment()` | 取得是否隱藏外觀空欄位的真裝備。 | — | [L579](../../CSharp/Client/WardrobeVisualOverride.cs#L579) |
| `VisualOverride · public static bool SetHideEmptySlotEquipment(bool enabled)` | 保存空欄位真裝備的隱藏選項，失敗時回滾。 | `SaveBooleanSetting`、`Log` | [L584](../../CSharp/Client/WardrobeVisualOverride.cs#L584) |
| `VisualOverride · internal static void SetOverrideGeneSplicerAppearanceSetting( ISettingBase<bool> setting, IConfigService service)` | 綁定基因接合器外觀選項及設定服務。 | — | [L601](../../CSharp/Client/WardrobeVisualOverride.cs#L601) |
| `VisualOverride · public static bool GetOverrideGeneSplicerAppearance()` | 讀取是否讓衣櫃管理醫療欄／基因接合器外觀。 | — | [L610](../../CSharp/Client/WardrobeVisualOverride.cs#L610) |
| `VisualOverride · public static bool SetOverrideGeneSplicerAppearance(bool enabled)` | 保存基因接合器外觀選項，失敗時回復先前值。 | `SaveBooleanSetting`、`Log` | [L615](../../CSharp/Client/WardrobeVisualOverride.cs#L615) |
| `VisualOverride · private static bool SaveBooleanSetting(ISettingBase<bool> setting)` | 直接呼叫設定服務保存單一布林選項，儲存失敗回傳 false。 | — | [L630](../../CSharp/Client/WardrobeVisualOverride.cs#L630) |
| `VisualOverride · private static void OnHideHuskVisualsChanged(ISettingBase setting)` | 同步屍殼選項備援值，通知角色健康視覺刷新。 | `ForceUpdateCharacterVisuals` | [L643](../../CSharp/Client/WardrobeVisualOverride.cs#L643) |
| `VisualOverride · private static void ForceUpdateCharacterVisuals()` | 逐一要求遊戲角色刷新健康相關視覺，單一角色失敗不影響其餘角色。 | — | [L649](../../CSharp/Client/WardrobeVisualOverride.cs#L649) |

## WardrobeVisualOverridePlugin.cs

來源：[CSharp/Client/WardrobeVisualOverridePlugin.cs](../../CSharp/Client/WardrobeVisualOverridePlugin.cs)

| 函式／方法（含參數） | 用途 | 相關呼叫 | 定位 |
|---|---|---|---|
| `WardrobeVisualOverridePlugin · public void Initialize()` | 建立 Harmony 實例，從模組設定服務綁定按鍵及各項外觀選項。 | `Log`、`VisualOverride.ResetPatchStatus`、`VisualOverride.SetPanelKeySetting`、`VisualOverride.SetHideHuskVisualsSetting`、`VisualOverride.SetUnequipOnSaveSetting`、`VisualOverride.SetHideEmptySlotEquipmentSetting`、`VisualOverride.SetOverrideGeneSplicerAppearanceSetting` | [L31](../../CSharp/Client/WardrobeVisualOverridePlugin.cs#L31) |
| `WardrobeVisualOverridePlugin · public void OnLoadCompleted()` | 安裝全部外觀 hooks 並記錄能力狀態。 | `VisualOverride.InstallPatches`、`Log`、`VisualOverride.GetReadinessStatus` | [L87](../../CSharp/Client/WardrobeVisualOverridePlugin.cs#L87) |
| `WardrobeVisualOverridePlugin · public void PreInitPatching()` | 實作插件預先 patch 階段介面，目前沒有額外工作。 | — | [L93](../../CSharp/Client/WardrobeVisualOverridePlugin.cs#L93) |
| `WardrobeVisualOverridePlugin · public void Dispose()` | 解除設定訂閱、清除所有外觀資源並卸除本插件 Harmony patches。 | `VisualOverride.SetPanelKeySetting`、`VisualOverride.SetHideHuskVisualsSetting`、`VisualOverride.SetUnequipOnSaveSetting`、`VisualOverride.SetHideEmptySlotEquipmentSetting`、`VisualOverride.SetOverrideGeneSplicerAppearanceSetting`、`VisualOverride.ClearAll`、`Log` | [L95](../../CSharp/Client/WardrobeVisualOverridePlugin.cs#L95) |
