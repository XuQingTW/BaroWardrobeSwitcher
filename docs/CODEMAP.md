# 程式導覽與檔案樹

這次只拆分 C# 原始碼與整理導覽，未實作幻化器混搭，也未改 Lua 執行流程、資料格式、公開方法名稱或多人協定。

## 從功能找程式

| 想改的功能 | 先看哪裡 |
|---|---|
| F8 面板、按鈕、目標船員 | `Lua/WardrobeSwitcher.lua` 的 `buildWindow`、`buildAttachmentVisibilityWindow`、`Helpers.addButton` |
| 保存、套用、清除的狀態與失敗回滾 | `Lua/WardrobeCore.lua` 的 `Core.reduce`、`Core.createClientController` |
| 本機保存／套用如何操作遊戲 | `Lua/WardrobeSwitcher.lua` 的 `clientEffectAdapters`、`Helpers.applyCapturedFashionToCharacterEquipment` |
| 伺服器權限、真裝備擷取、卸裝 | `Lua/WardrobeSwitcherServer.lua` 的 `resolveCrewTarget`、`captureAuthoritativeLook`、`commitSave` |
| 進出站、重連、角色切換後還原 | 客戶端的 `Helpers.handleSessionChange`、`Helpers.handleControlledCharacterChange`、`Helpers.processPendingSinglePlayerRestores`；伺服器的 `reactivateSession` |
| 從物品擷取外觀／建立暫時物品 | `CSharp/Client/WardrobeFashionCapture.cs` |
| 貼圖副本、session 所有權、資源釋放 | `CSharp/Client/WardrobeRendering.cs` |
| 衣服層次、肢體綁定、附件與空欄位遮罩 | `CSharp/Client/WardrobeVisualLayers.cs` |
| 真正繪圖、補畫、屍殼／附肢遮蔽 | `CSharp/Client/WardrobeVisualDraw.cs` |
| 繪圖／腳步音效前後的快照與還原 | `CSharp/Client/WardrobeRenderTransactions.cs` |
| 動畫、音效替代與功能效果保留 | `CSharp/Client/WardrobeFashionEffects.cs`、`WardrobeFunctionalFashionFilters.cs` |
| 設定值綁定、儲存、能力偵測 | `CSharp/Client/WardrobeVisualOverride.cs`、`WardrobeVisualOverridePlugin.cs` |
| 修改 patch 目標或 prefix／postfix／finalizer | `WardrobeVisualOverride.cs` 的 `InstallPatches` 及 `WardrobePatches.cs` |
| 客戶端 JSON、舊版遷移、安全寫檔 | `CSharp/Client/WardrobePersistence.cs` |
| 每個單人船員的獨立外觀 | `CSharp/Client/WardrobeSinglePlayerProfiles.cs` |
| 高壓潛水外觀 | `CSharp/Client/WardrobeDivingProfiles.cs` 及 Lua 的 `Helpers.refreshDivingAppearance` |
| 客戶端檔案日誌 | `CSharp/Client/WardrobeFileLogger.cs`，Lua 的 `Helpers.dumpDebugLog` |

## 檔案樹

```text
BaroWardrobeSwitcher/
├─ README.md                           使用方式與行為說明
├─ docs/
│  ├─ CODEMAP.md                       本導覽：功能入口與檔案職責
│  └─ functions/
│     ├─ CSharp.md                     每個 C# 方法、建構及區域函式
│     ├─ LuaCore.md                    純資料、封包協定與 reducer
│     ├─ LuaClient.md                  客戶端具名函式與匿名回呼
│     └─ LuaServer.md                  伺服器具名函式與匿名回呼
├─ CSharp/
│  └─ Client/
│     ├─ WardrobeVisualOverridePlugin.cs  插件生命週期、設定注入及卸載
│     ├─ WardrobeFileLogger.cs           帶時間與等級的 UTF-8 檔案日誌
│     ├─ WardrobePersistence.cs          一般外觀存檔、驗證、遷移及安全寫入
│     ├─ WardrobeSinglePlayerProfiles.cs 單人戰役／船員設定及身分雜湊
│     ├─ WardrobeDivingProfiles.cs        潛水模式及自訂潛水外觀存檔
│     ├─ WardrobeVisualOverride.cs       VisualOverride 共用狀態、設定及 patch 安裝
│     ├─ WardrobeFashionCapture.cs       角色 session、擷取交易、物品來源及啟用
│     ├─ WardrobeVisualDraw.cs           繪圖入口、屍殼／附肢及腳步替代
│     ├─ WardrobeFashionEffects.cs       動畫與音效擷取、替代、循環維持
│     ├─ WardrobeVisualLayers.cs         層次、肢體綁定、遮罩及來源診斷
│     ├─ WardrobeRenderTransactions.cs   繪製／腳步交易、遮罩快照及復原
│     ├─ WardrobePatches.cs              Harmony 的薄轉接入口
│     ├─ WardrobeRendering.cs            FashionSpriteDescriptor 與 RenderSession
│     └─ WardrobeFunctionalFashionFilters.cs 功能裝備與純外觀效果的分類政策
├─ Lua/
│  ├─ WardrobeCore.lua                 純資料、協定、reducer 與控制器
│  ├─ WardrobeSwitcher.lua             客戶端橋接、保存還原、同步及介面
│  └─ WardrobeSwitcherServer.lua       伺服器權威、持久化及廣播
├─ Config/
│  └─ SettingsClient.xml              LuaCs 客戶端設定定義與預設值
├─ Texts.xml                          英文翻譯
├─ TextsSimplifiedChinese.xml         簡體中文翻譯
├─ TextsTraditionalChinese.xml        繁體中文翻譯
├─ filelist.xml                       遊戲內容與執行期原始碼打包清單
├─ ModConfig.xml                      LuaCs 模組設定入口
├─ MultiplayerSyncMarker.xml          多人同步能力標記物品
├─ version.json                       版本、協定及發布驗證中繼資料
└─ todo                               待辦事項
```

## 逐函式索引

- [C#：284 個方法／建構／區域函式](functions/CSharp.md)
- [Lua Core：69 個具名函式](functions/LuaCore.md)
- [Lua 客戶端：267 個具名函式／處理器](functions/LuaClient.md)
- [Lua 伺服器：132 個具名函式／處理器](functions/LuaServer.md)

四份索引逐項列出簽章、用途、部分直接呼叫及來源行。Lua 另列匿名回呼的外層、註冊入口、參數及呼叫線索。索引涵蓋正式執行期原碼；測試替身、探針及建置腳本已移至專案外，未列入索引。C# LINQ lambda 不另作具名方法列舉。

## 理解拆分後的 C#

`VisualOverride` 是同一個 `public static partial class`，分放在六個檔案。拆檔不建立新的服務層、不改 Lua 呼叫的型別名稱，也不改私有方法的可見性。共用靜態欄位與初始化仍集中在 `WardrobeVisualOverride.cs`；`WardrobeRenderTransactions.cs` 放原有巢狀型別。

`WardrobePersistence` 同樣維持原有 partial 類別，分為一般外觀、單人角色與潛水設定。`WardrobeRendering.cs` 的描述及 session 聚合維持既有結構。

新增正式 C# 檔案時，SDK 專案會自動編譯；仍必須把路徑加入 `filelist.xml`，讓工坊來源包包含它。渲染來源契約測試依明確檔案順序組合 partial 原碼，新增相關 partial 時也要更新清單。

## 三條常用流程

```text
保存：Lua saveFashionAndUnequip
   → Core.reduce → Capture adapter
   → C# BeginFashionTransaction → CaptureFashionItem
   → Unequip adapter（依選項卸裝，驗證後提交）→ Persist

套用：Lua applyFashionToCurrentEquipment
   → Core.reduce → Render adapter
   → 重用已提交 session，或由保存資料重新擷取
   → CaptureFashionPrefabCore（只在需要 prefab 來源時建立暫時 Item）
   → ActivateFashionVisual → 遊戲繪製 hooks

繪製：WardrobePatches 的 LimbDrawPatch
   → BeginLimbDraw → LimbRenderTransaction.Begin
   → TryOverrideDrawWearable／DrawMissingFashionSprites
   → EndLimbDraw → Cleanup → 還原原列表、遮罩與快取
```

多人命令走伺服器的 `handleV2Command` → 權限／去重／修訂檢查 → `commitSave`／`commitApply`／`commitClear` → 持久化 → 確認及廣播。客戶端收到狀態後走 `Helpers.handleNetworkLookApply` 或 `Helpers.handleNetworkLookClear`。

## 閱讀與維護方式

先由功能表找到檔案，再在逐函式索引用 `Ctrl+F` 搜尋完整函式名。定位連結的 `#L` 行號對應此次整理的原碼；後續增刪程式時需同步更新索引。呼叫線索是靜態閱讀輔助，實際事件、反射與網路執行順序以原碼為準。

本次拆分驗證以建置、既有渲染契約、原碼方法／欄位對照與相關測試為準，不代替遊戲內繪製驗證。

| 檢查 | 本次結果 |
|---|---|
| Release 建置 | 通過，零警告、零錯誤 |
| 拆分前後語法樹對照 | 通過，356 個方法、建構、欄位及屬性的 token 內容一致 |
| 渲染來源契約 | 全部通過 |
| 函式位置、文件連結及 C# 打包清單 | 通過，776 個具名定義、1,032 個文件連結均可定位 |
| Lua 語法 | 正式原碼與測試檔均可由 MoonSharp 解析 |
| Lua Core、伺服器權威、基因接合器測試 | 通過 |
| Lua 客戶端介面測試 | 現有面板尺寸／來源契約 assertion 失敗；本次未改 Lua 原碼 |
| 存檔探針 | 遮罩、移動與日誌案例通過；20 個存檔案例失敗，拆分前原碼重建亦有相同結果 |
| 遊戲 API 相容探針 | API 檢查通過；本機 LuaCs publicized commit 與探針釘選值不符，整體仍回報失敗 |
| 打包驗證 | 仍有既有 `filelist.xml` 版本號與 `version.json` 不一致；未替使用者改版本號 |
| `git diff --check` | 通過 |

這些未通過項目需分別追查，本次沒有把它們混入純拆分變更。

建置、測試與暫存產物已移至專案外的 Codex 工作區；.github 保留於專案。
