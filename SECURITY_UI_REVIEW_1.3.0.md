# 1.3.0 安全與聊天介面交付報告

基準 `c346351`（1.2.0）；本版 1.3.0。安全優先，沒有使用真金鑰、真 API 或新增 App／UI 自動測試。

## 調查結論與界線

1.2.0 的主 App PasteButton 直接將字串指定至 `model.task.source`；鍵盤 paste 直接指定 homeSource／source／instruction／saveEdit，未過濾。WorkspaceModel 接受 AI 回覆即 append 並顯示／儲存。CredentialPayloadGuard 只對送出本文檢查完整現用金鑰，無法阻止較早的畫面顯示、不同金鑰、輸出回音或恢復舊紀錄。這些為已核對原始碼的確定缺口；**使用者真機事件的完整傳播路徑仍未證實**，不能斷言外部服務已收到真金鑰。

合成憑證測試覆蓋新防線；沒有存取裝置、使用者剪貼簿、舊金鑰或帳務資料。未把「已編譯」當成安全全數驗收。

## 防護範圍

| 邊界 | 實作 |
| --- | --- |
| 主 App 普通輸入／貼上 | SafeTextInput 的 UITextViewDelegate 在緩衝區變更前拒絕；PasteButton 在賦值前驗證；進階設定／工具欄位亦使用同一輸入元件 |
| 鍵盤貼上／選取 | 先驗證再更新 published state；選取上下文只留雜湊，不保存周邊原文；拒絕含憑證的選取 |
| 現用與舊金鑰 | 常見前綴形狀＋去除空白／控制／format 字元後檢查；啟用時本機讀取憑證建立 SHA-256 指紋，之後輸入檢查不需讀取完整金鑰；刪除後保留受保護的指紋 |
| HTTP | 最終組裝 JSON 的名稱、字串與巢狀值全檢查；真金鑰只進固定 OpenAI HTTPS 的 Authorization header |
| API 回覆 | 成功回覆在解析前遞迴檢查所有 JSON 字串，包括詳細解析、來源標題／網址、模型清單；另用當次 key 精確比對；WorkspaceModel 再檢查 Answer |
| 錯誤 | 不回顯 server code／message／refusal，未知錯誤用一般說明；沒有 request／response／key 日誌 |
| 結果／版本 | source、instruction、result 改 private(set)，用 guarded 方法修改；恢復 WorkTask、編輯、切版、複製與分享／插入都檢查 |
| 持久化 | SharedStore 寫入前驗證；讀取舊 JSON（含未知欄位）先驗證；污染或損壞檔整檔移除，不保留秘密副本；關閉歷史／刪金鑰清空紀錄 |
| 工具／偏好 | 匯入前、顯示前與匯出前驗證；不允許憑證放入提示詞、模型 ID 或工具說明 |
| 剪貼簿 | 只有使用者動作才讀取；金鑰貼上後提供主動清空按鈕；不使用剪貼簿傳遞共享憑證 |

指紋不是金鑰備份，但可用來比對猜測值，與金鑰放同一完整檔案保護／排除備份的目錄。短弱字串本來就不適合當 API 金鑰。偵測不是任意編碼／分段／加密的完整 DLP；不承諾零漏洞，沒有後端代理或自動輪替憑證。

## App Group 技術結論

已核對 StorageLocation、兩個 entitlements、Config.xcconfig、project.yml 及 build／verify 腳本：App 與 extension 使用同一 `SHARED_APP_GROUP`，CI 仍只輸出無簽章 App＋Keyboard appex。設定檔一致不會替裝置取得 Apple 授權。

要讓鍵盤讀到同一秘密，最終安裝的 App 與 extension 都必須被系統允許相同 App Group，鍵盤另外需完整取用；實際執行時須取得共同 container URL。單靠 unsigned IPA **無法保證**這些條件。主 App fallback 仍只在主 App 私有 Application Support；extension 不建立假共享空間。不以 Keychain、明文 defaults、URL query 或剪貼簿繞過。

診斷分為：完整取用、主 App 群組、鍵盤群組、金鑰存在、模型連線。跨 process 無法觀測的狀態標成「請在另一端確認」，不推測成成功。沒有共享／金鑰時鍵盤只列可用的本機計算，AI 不假裝可執行；主 App 仍可生成再複製。

依據：[Apple App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups)、[Keyboard open access](https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard)。本次不要求任何簽署材料、不改變 IPA 交付方式。

## 流程前後

| 範圍 | 1.2.0 | 1.3.0 |
| --- | --- | --- |
| 主入口 | 工具清單 → 卡片表單 | 對話工作台；頂列模式、中央使用者／AI 訊息、底部固定輸入 |
| 文章生成 | 主題／額外要求多欄 | 直接輸入「幫我寫…」送出 |
| 追加修訂 | 捲到另一張修訂卡 | 同一輸入區繼續描述要求；訊息流保留原文和各版本 |
| 結果 | 常駐大編輯器 | 可閱讀訊息；選版、複製、分享、編輯 Sheet、來源／解析展開 |
| 工具選擇 | 導航新表單 | 同頁選單與快捷；已有對話時確認開新工作，避免混用上下文 |
| 鍵盤首頁 | 四欄八格 | 最多六格三欄；大字兩欄；其他工具次層入口 |
| 鍵盤提示 | 浮在工具上方 | 頂列一行狀態，點開獨立可返回的捲動資訊區，不覆蓋按鈕 |
| 鍵盤動作 | 執行／複製／插入同列 | 輸入時執行／貼上；處理時取消；結果時複製／插入，取代在選單 |
| 宿主上下文 | 不同欄位可能留舊結果 | documentIdentifier 改變即清除暫存工作，取代仍核對選取與前後文雜湊 |

單一 UIHostingController 與幾何高度政策保留，頁面不參與根高度計算；移除鍵盤全畫面切換動畫。系統控制原生／第三方鍵盤之間的轉場，本次沒有證據可保證實際高度零跳動。

## 檢查與結果

- 本地配置／安全路徑靜態檢查通過；30 個 Swift 檔 Tree-sitter 語法解析通過；Shell 語法通過。這不等同 Swift 型別檢查。
- 原 10 項核心測試保留；新增 SecurityTests：合成憑證變形、非標準現用指紋、回覆主文／解析／來源、錯誤、持久化與舊檔清除、Published 狀態、HTTP 前後攔截、聊天修訂取消及選取上下文。
- CI 必須先 `swift test` 再 Xcode Release iphoneos 編譯、IPA 結構與 arm64／平台／版本檢查。**本版 CI 結果待實際執行後填寫。**
- S01–S06 的核心防線由合成資料自動測試；真機剪貼簿、UITextView delegate、主 App／鍵盤共享生命週期與輸出手勢仍需裝置驗收。S07 本次不接觸真金鑰，程式不記錄秘密；不能聲稱已查驗使用者過去的外部日誌／帳務。

## 必須誠實保留的視覺待驗收

**視覺尚未驗證**：目前環境無 iOS 模擬器／真機，不提供假截圖。以下八組前後對照都待實機拍攝：

1. 主 App 空白對話。
2. 主 App 輸入主題／原文。
3. 主 App 生成中及取消。
4. 主 App 結果、版本及追加修訂。
5. 鍵盤首頁／全部工具。
6. 鍵盤貼上／處理中。
7. 鍵盤結果／複製／插入。
8. 鍵盤共享不可用與狀態頁。

U01–U10 真機項目均待驗收：iPhone 17 Pro 級／較小 iPhone、橫直式、深淺色、大字／VoiceOver／Reduce Motion；同宿主連切 20 次、原生鍵盤來回切換、離線、權限缺失、選取失效、歷史關閉與快速取消。CI 模型測試可驗證部分資料流程，但不冒充觸控、可達性或視覺驗收。
